r"""The Phase 4 graph: a structured-classifier router in front of two worker
nodes.

    START -> route ->  general_advisor    -> END
                   \-> scholarship_expert -> END

``route`` makes one cheap, temperature-0 LLM call that tags the turn as
``general`` (broad advice, retrieval over everything) or ``expert`` (the user
named one scholarship — retrieval is pinned to that ``scholarship_id`` and the
prompt is specialised). The two workers keep the Phase 2 retrieve-then-stream
shape. A Postgres checkpointer still holds conversation memory per ``thread_id``.

Adding a third route later (e.g. a node that collects and stores a user's
profile) is a new node + one more branch in ``_pick_route`` — the router prompt
and ``RouteDecision`` grow, nothing else moves.
"""

import re
from typing import Annotated, Literal, TypedDict

from langchain_core.messages import AIMessage, BaseMessage, SystemMessage
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from langsmith import traceable
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select

from app.config import get_settings
from app.db import SessionLocal
from app.db_models import Scholarship
from app.llm import get_chat_model, get_router_model
from app.tools import check_eligibility, get_scholarship_detail, search_scholarships

GENERAL_SYSTEM_PROMPT = (
    "Eres Owl, un asistente que ayuda a estudiantes colombianos a encontrar becas. "
    "Responde en español, de forma breve y concreta, usando únicamente la "
    "información de becas provista a continuación. Si la información no alcanza "
    "para responder, dilo con honestidad en vez de inventar datos. "
    "Responde en texto plano: nada de Markdown (sin **negritas**, sin encabezados "
    "con #, sin listas con - o 1.) — la interfaz aún no interpreta ese formato."
)

EXPERT_SYSTEM_PROMPT = (
    "Eres Owl, y en esta conversación actúas como experto en UNA beca específica: "
    "«{title}» ({provider}). Responde en español, breve y concreto, SOLO sobre esta "
    "beca, usando la ficha y los fragmentos de abajo. Si te preguntan por otra beca, "
    "acláralo y ofrece ayuda general. No inventes fechas ni montos: si no están en la "
    "ficha, dilo. Texto plano, sin Markdown."
)

NO_DATA_MESSAGE = (
    "Aún no tengo becas cargadas. Cuando el equipo agregue oportunidades podré "
    "ayudarte a encontrar la más adecuada para tu perfil."
)

EXPERT_NOT_FOUND_MESSAGE = (
    "No encuentro los detalles de esa beca en este momento. ¿Quieres que te dé "
    "orientación general sobre becas similares?"
)

TOP_K = 5
HISTORY_TURNS = 6
KNOWN_SCHOLARSHIPS_LIMIT = 60

# Words too generic to identify a scholarship on their own, so the name-match
# fallback skips them (otherwise "la beca X" matches every title with "beca").
_RESOLVE_STOPWORDS = {
    "beca",
    "becas",
    "convocatoria",
    "programa",
    "scholarship",
    "para",
    "sobre",
    "acerca",
    "estudios",
    "posgrado",
    "maestria",
    "maestría",
    "doctorado",
    "pregrado",
    "exterior",
}


class RouteDecision(BaseModel):
    """What the router LLM returns."""

    route: Literal["general", "expert"] = Field(
        description=(
            "'expert' ONLY when the user is asking about one specific, named "
            "scholarship or program. Otherwise 'general'."
        )
    )
    scholarship_query: str | None = Field(
        default=None,
        description="When route='expert', the scholarship name or provider the user named.",
    )


class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    citations: list[dict]
    user_context: dict
    route: str
    scholarship_id: str | None
    scholarship_title: str | None


# --- shared helpers -------------------------------------------------------------
def _has_scholarships() -> bool:
    with SessionLocal() as session:
        return bool(session.scalar(select(func.count()).select_from(Scholarship)))


def _known_scholarships() -> list[tuple[str, str]]:
    with SessionLocal() as session:
        rows = session.execute(
            select(Scholarship.title, Scholarship.provider).limit(KNOWN_SCHOLARSHIPS_LIMIT)
        ).all()
        return [(title, provider) for title, provider in rows]


def _resolve_scholarship(query: str | None) -> dict | None:
    """Best-effort map a name the router pulled out of the turn to a stored row."""
    text = (query or "").strip()
    if not text:
        return None

    tokens = sorted(
        (
            w
            for w in re.findall(r"[^\W_]{5,}", text, flags=re.UNICODE)
            if w.lower() not in _RESOLVE_STOPWORDS
        ),
        key=len,
        reverse=True,
    )

    with SessionLocal() as session:
        for needle in [text, *tokens]:
            row = session.scalar(
                select(Scholarship)
                .where(
                    or_(
                        Scholarship.title.ilike(f"%{needle}%"),
                        Scholarship.provider.ilike(f"%{needle}%"),
                    )
                )
                .limit(1)
            )
            if row is not None:
                return {
                    "id": str(row.id),
                    "title": row.title,
                    "provider": row.provider,
                    "source_url": row.source_url,
                }
    return None


def _format_user_context(user_context: dict | None) -> str:
    context = user_context or {}
    bits = []
    if context.get("country"):
        bits.append(f"país {context['country']}")
    if context.get("level"):
        bits.append(f"nivel {context['level']}")
    if context.get("fields"):
        bits.append("áreas " + ", ".join(context["fields"]))
    return f"\n\nPERFIL DEL ESTUDIANTE: {'; '.join(bits)}." if bits else ""


def _stream_answer(messages: list[BaseMessage]) -> AIMessage:
    llm = get_chat_model()
    full = None
    for chunk in llm.stream(messages):
        full = chunk if full is None else full + chunk
    return full if full is not None else AIMessage(content="")


# --- nodes --------------------------------------------------------------------
@traceable(run_type="chain", name="classify_route")
def _classify_route(history: list[BaseMessage]) -> RouteDecision:
    catalogue = "\n".join(f"- {title} ({provider})" for title, provider in _known_scholarships())
    system = SystemMessage(
        content=(
            "Clasifica el ÚLTIMO mensaje del usuario en 'general' o 'expert'.\n"
            "- 'expert': el usuario nombra UNA beca/programa concreto y quiere saber de ESE "
            "(requisitos, fechas, monto, cómo aplicar, 'cuéntame sobre X', 'háblame de X', "
            "'qué cubre X'). Aunque el nombre no esté en la lista, si nombra uno solo, es "
            "'expert'.\n"
            "- 'general': orientación amplia, comparar varias, explorar por país/área/nivel, "
            "'qué becas hay para…', o cuando no nombra ninguna.\n"
            "Si es 'expert', pon en scholarship_query el nombre tal como lo escribió el "
            "usuario.\n\n"
            "Ejemplos:\n"
            "  'becas para maestría en Alemania' -> general\n"
            "  'cuéntame sobre DAAD' -> expert, scholarship_query='DAAD'\n"
            "  '¿requisitos de Chevening?' -> expert, scholarship_query='Chevening'\n"
            "  'compara Fulbright y Chevening' -> general\n\n"
            f"BECAS CONOCIDAS:\n{catalogue or '(ninguna)'}"
        )
    )
    router = get_router_model().with_structured_output(RouteDecision)
    return router.invoke([system, *history[-HISTORY_TURNS:]])


def route_node(state: AgentState) -> dict:
    empty = {"route": "general", "scholarship_id": None, "scholarship_title": None}

    if not get_settings().openai_api_key or not _has_scholarships():
        return empty

    try:
        decision = _classify_route(state["messages"])
    except Exception:  # noqa: BLE001 - a router failure must never break the turn
        return empty

    if decision.route != "expert":
        return empty

    match = _resolve_scholarship(decision.scholarship_query)
    if match is None:
        return empty

    return {"route": "expert", "scholarship_id": match["id"], "scholarship_title": match["title"]}


def _pick_route(state: AgentState) -> str:
    return "scholarship_expert" if state.get("route") == "expert" else "general_advisor"


@traceable(run_type="chain", name="general_advisor")
def general_advisor_node(state: AgentState) -> dict:
    if not get_settings().openai_api_key or not _has_scholarships():
        return {"messages": [AIMessage(content=NO_DATA_MESSAGE)], "citations": []}

    latest = state["messages"][-1]
    hits = search_scholarships(latest.content, k=TOP_K)

    context_blocks: list[str] = []
    citations: list[dict] = []
    seen: set[str] = set()
    for hit in hits:
        context_blocks.append(f"### {hit['title']} ({hit['provider']})\n{hit['snippet']}")
        if hit["scholarship_id"] not in seen:
            citations.append(
                {
                    "scholarship_id": hit["scholarship_id"],
                    "title": hit["title"],
                    "source_url": hit["source_url"],
                }
            )
            seen.add(hit["scholarship_id"])

    system = SystemMessage(
        content=f"{GENERAL_SYSTEM_PROMPT}{_format_user_context(state.get('user_context'))}"
        "\n\nBECAS RELEVANTES:\n" + "\n\n".join(context_blocks)
    )
    answer = _stream_answer([system, *state["messages"][-HISTORY_TURNS:]])
    return {"messages": [answer], "citations": citations}


@traceable(run_type="chain", name="scholarship_expert")
def scholarship_expert_node(state: AgentState) -> dict:
    scholarship_id = state.get("scholarship_id")
    detail = get_scholarship_detail(scholarship_id) if scholarship_id else None
    if detail is None:
        return {"messages": [AIMessage(content=EXPERT_NOT_FOUND_MESSAGE)], "citations": []}

    eligibility = check_eligibility(scholarship_id, state.get("user_context"))
    ficha = "\n".join(
        f"{label}: {value}"
        for label, value in (
            ("Proveedor", detail["provider"]),
            ("País", detail["country"]),
            ("Niveles", ", ".join(detail["levels"]) or "—"),
            ("Áreas", ", ".join(detail["fields"]) or "—"),
            ("Financiación", detail["funding_type"] or "—"),
            ("Monto", detail["amount_note"] or "—"),
            ("Fecha límite", detail["deadline"] or "—"),
            ("Elegibilidad", detail["eligibility_text"] or "—"),
        )
    )
    hint = f"\n\nSEÑALES DE ELEGIBILIDAD ({eligibility['status']}):\n- " + "\n- ".join(
        eligibility["reasons"]
    )
    body = "\n\n".join(detail["chunks"]) or detail["body_markdown"]

    system = SystemMessage(
        content=EXPERT_SYSTEM_PROMPT.format(title=detail["title"], provider=detail["provider"])
        + _format_user_context(state.get("user_context"))
        + f"\n\nFICHA:\n{ficha}{hint}\n\nCONTENIDO:\n{body}"
    )
    answer = _stream_answer([system, *state["messages"][-HISTORY_TURNS:]])
    citations = [
        {
            "scholarship_id": detail["scholarship_id"],
            "title": detail["title"],
            "source_url": detail["source_url"],
        }
    ]
    return {"messages": [answer], "citations": citations}


# --- assembly ---------------------------------------------------------------
def _build_graph() -> StateGraph:
    builder = StateGraph(AgentState)
    builder.add_node("route", route_node)
    builder.add_node("general_advisor", general_advisor_node)
    builder.add_node("scholarship_expert", scholarship_expert_node)
    builder.add_edge(START, "route")
    builder.add_conditional_edges(
        "route",
        _pick_route,
        {"general_advisor": "general_advisor", "scholarship_expert": "scholarship_expert"},
    )
    builder.add_edge("general_advisor", END)
    builder.add_edge("scholarship_expert", END)
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


def build_graph_without_checkpointer():
    """A compiled graph with no Postgres checkpointer — for evals and scripts
    that run one turn at a time and don't need conversation memory."""
    return _build_graph().compile()
