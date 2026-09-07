"""The Phase 2 graph: a single node that retrieves + answers, with a Postgres
checkpointer so conversation memory lives in the graph, not in every request
payload. Phase 4 adds a router and more nodes on top of this same graph.
"""

from typing import Annotated, TypedDict

from langchain_core.messages import AIMessage, SystemMessage
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from sqlalchemy import func, select

from app.config import get_settings
from app.db import SessionLocal
from app.db_models import Scholarship, ScholarshipChunk
from app.embeddings import embed_query
from app.llm import get_chat_model

SYSTEM_PROMPT = (
    "Eres Owl, un asistente que ayuda a estudiantes colombianos a encontrar becas. "
    "Responde en español, de forma breve y concreta, usando únicamente la "
    "información de becas provista a continuación. Si la información no "
    "alcanza para responder, dilo con honestidad en vez de inventar datos. "
    "Responde en texto plano: nada de Markdown (sin **negritas**, sin encabezados "
    "con #, sin listas con - o 1.) — la interfaz aún no interpreta ese formato."
)

NO_DATA_MESSAGE = (
    "Aún no tengo becas cargadas. Cuando el equipo agregue oportunidades podré "
    "ayudarte a encontrar la más adecuada para tu perfil."
)

TOP_K = 5
HISTORY_TURNS = 6


class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    citations: list[dict]


def _retrieve(user_message: str) -> tuple[list[str], list[dict]]:
    with SessionLocal() as session:
        query_vector = embed_query(user_message)
        top_chunks = session.scalars(
            select(ScholarshipChunk)
            .order_by(ScholarshipChunk.embedding.cosine_distance(query_vector))
            .limit(TOP_K)
        ).all()

        context_blocks: list[str] = []
        citations: list[dict] = []
        seen_ids: set[int] = set()
        for chunk in top_chunks:
            s = chunk.scholarship
            context_blocks.append(f"### {s.title} ({s.provider})\n{chunk.content}")
            if s.id not in seen_ids:
                citations.append(
                    {"scholarship_id": str(s.id), "title": s.title, "source_url": s.source_url}
                )
                seen_ids.add(s.id)
        return context_blocks, citations


def _has_scholarships() -> bool:
    with SessionLocal() as session:
        return bool(session.scalar(select(func.count()).select_from(Scholarship)))


def answer_node(state: AgentState) -> dict:
    settings = get_settings()
    latest_human = state["messages"][-1]

    if not settings.openai_api_key or not _has_scholarships():
        return {"messages": [AIMessage(content=NO_DATA_MESSAGE)], "citations": []}

    context_blocks, citations = _retrieve(latest_human.content)
    system = SystemMessage(
        content=f"{SYSTEM_PROMPT}\n\nBECAS RELEVANTES:\n" + "\n\n".join(context_blocks)
    )
    conversation = state["messages"][-HISTORY_TURNS:]

    llm = get_chat_model()
    full = None
    for chunk in llm.stream([system, *conversation]):
        full = chunk if full is None else full + chunk

    return {"messages": [full], "citations": citations}


def _build_graph() -> StateGraph:
    builder = StateGraph(AgentState)
    builder.add_node("answer", answer_node)
    builder.add_edge(START, "answer")
    builder.add_edge("answer", END)
    return builder


def _to_psycopg_dsn(sqlalchemy_url: str) -> str:
    return sqlalchemy_url.replace("postgresql+psycopg://", "postgresql://")


_pool: ConnectionPool | None = None
_graph = None


def init_graph() -> None:
    """Call once at app startup. Opens the checkpointer's own connection pool
    and creates its tables (idempotent)."""
    global _pool, _graph

    dsn = _to_psycopg_dsn(get_settings().owl_api_database_url)
    _pool = ConnectionPool(
        conninfo=dsn,
        min_size=1,
        max_size=5,
        open=True,
        kwargs={"autocommit": True, "prepare_threshold": 0, "row_factory": dict_row},
    )
    checkpointer = PostgresSaver(_pool)
    checkpointer.setup()
    _graph = _build_graph().compile(checkpointer=checkpointer)


def close_graph() -> None:
    global _pool, _graph
    if _pool is not None:
        _pool.close()
    _pool = None
    _graph = None


def get_graph():
    if _graph is None:
        raise RuntimeError("graph not initialized — call init_graph() during startup")
    return _graph
