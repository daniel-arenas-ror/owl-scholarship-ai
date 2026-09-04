from fastapi import APIRouter, Depends
from langchain_core.messages import HumanMessage, SystemMessage
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db import get_session
from app.db_models import Scholarship, ScholarshipChunk
from app.embeddings import embed_query
from app.llm import get_chat_model
from app.schemas import AgentRespondRequest, AgentRespondResult, Citation
from app.security import require_service_auth

router = APIRouter(prefix="/v1/agent", tags=["agent"])

SYSTEM_PROMPT = (
    "Eres Owl, un asistente que ayuda a estudiantes colombianos a encontrar becas. "
    "Responde en español, de forma breve y concreta, usando únicamente la "
    "información de becas provista a continuación. Si la información no "
    "alcanza para responder, dilo con honestidad en vez de inventar datos."
)

NO_DATA_MESSAGE = (
    "Aún no tengo becas cargadas. Cuando el equipo agregue oportunidades podré "
    "ayudarte a encontrar la más adecuada para tu perfil."
)

TOP_K = 5
HISTORY_TURNS = 6


@router.post("/respond", response_model=AgentRespondResult)
def respond(
    payload: AgentRespondRequest,
    session: Session = Depends(get_session),
    _claims: dict = Depends(require_service_auth),
) -> AgentRespondResult:
    """One conversational turn: retrieve the most relevant scholarship chunks
    from pgvector and answer grounded in them.

    Phase 2 turns this into an SSE stream; Phase 4 replaces the single call
    below with a LangGraph supervisor that can hand off to a per-scholarship
    expert agent.
    """
    settings = get_settings()
    has_data = session.scalar(select(func.count()).select_from(Scholarship)) or 0

    if not settings.openai_api_key or not has_data:
        return AgentRespondResult(message=NO_DATA_MESSAGE, agent="general_advisor")

    query_vector = embed_query(payload.user_message)
    top_chunks = session.scalars(
        select(ScholarshipChunk)
        .order_by(ScholarshipChunk.embedding.cosine_distance(query_vector))
        .limit(TOP_K)
    ).all()

    context_blocks: list[str] = []
    citations: list[Citation] = []
    seen_ids: set[int] = set()
    for chunk in top_chunks:
        s = chunk.scholarship
        context_blocks.append(f"### {s.title} ({s.provider})\n{chunk.content}")
        if s.id not in seen_ids:
            citations.append(
                Citation(scholarship_id=str(s.id), title=s.title, source_url=s.source_url)
            )
            seen_ids.add(s.id)

    history_text = "\n".join(
        f"{turn.role}: {turn.content}" for turn in payload.history[-HISTORY_TURNS:]
    )

    messages = [
        SystemMessage(
            content=f"{SYSTEM_PROMPT}\n\nBECAS RELEVANTES:\n" + "\n\n".join(context_blocks)
        ),
        HumanMessage(
            content=(
                f"HISTORIAL RECIENTE:\n{history_text or '(sin historial)'}\n\n"
                f"PREGUNTA DEL ESTUDIANTE:\n{payload.user_message}"
            )
        ),
    ]

    answer = get_chat_model().invoke(messages)

    return AgentRespondResult(message=answer.content, citations=citations, agent="general_advisor")
