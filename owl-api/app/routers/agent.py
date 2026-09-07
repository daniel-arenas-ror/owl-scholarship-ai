import json
from collections.abc import Iterator

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from langchain_core.messages import HumanMessage

from app.graph import get_graph
from app.schemas import AgentRespondRequest
from app.security import require_service_auth

router = APIRouter(prefix="/v1/agent", tags=["agent"])


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def _stream_turn(payload: AgentRespondRequest) -> Iterator[str]:
    graph = get_graph()
    config = {"configurable": {"thread_id": payload.thread_id}}

    accumulated = ""
    try:
        for message_chunk, _metadata in graph.stream(
            {"messages": [HumanMessage(content=payload.user_message)]},
            config=config,
            stream_mode="messages",
        ):
            piece = getattr(message_chunk, "content", "") or ""
            if piece:
                accumulated += piece
                yield _sse("token", {"content": piece})

        final = graph.get_state(config).values
        citations = final.get("citations", [])
        final_message = final["messages"][-1].content if final.get("messages") else accumulated

        # The graceful "no scholarships yet" path returns one plain message
        # with no streaming LLM call, so no token event was sent above.
        if not accumulated and final_message:
            yield _sse("token", {"content": final_message})

        yield _sse(
            "done", {"message": final_message, "citations": citations, "agent": "general_advisor"}
        )
    except Exception as exc:  # noqa: BLE001 - surface the failure to the client, don't 500 mid-stream
        yield _sse("error", {"detail": str(exc)})


@router.post("/respond")
def respond(
    payload: AgentRespondRequest,
    _claims: dict = Depends(require_service_auth),
) -> StreamingResponse:
    """Streams one conversational turn as SSE (event: token* then event: done).

    Called only by owl-admin, which relays this stream on to the browser and
    persists the result. Conversation memory lives in the graph's Postgres
    checkpointer, keyed by thread_id — the caller doesn't send history. Phase 4
    replaces the single "answer" node with a supervisor that can hand off to a
    per-scholarship expert agent.
    """
    return StreamingResponse(_stream_turn(payload), media_type="text/event-stream")
