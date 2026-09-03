from fastapi import APIRouter

from app.schemas import AgentRespondRequest, AgentRespondResult

router = APIRouter(prefix="/v1/agent", tags=["agent"])


@router.post("/respond", response_model=AgentRespondResult)
def respond(payload: AgentRespondRequest) -> AgentRespondResult:
    """Answer one conversational turn.

    Phase 1: retrieval over pgvector + a single LangChain chain, returned as
    JSON. Phase 2: this becomes an SSE stream. For now, a canned reply so the
    end-to-end path (owl-web -> owl-admin -> owl-api) can be wired up.
    """
    return AgentRespondResult(
        message=(
            "Aún no tengo becas cargadas. Cuando el equipo agregue oportunidades "
            "podré ayudarte a encontrar la más adecuada para tu perfil."
        ),
        citations=[],
        agent="general_advisor",
        trace_url=None,
    )
