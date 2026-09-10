import json
import uuid
from collections.abc import Iterator

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from langchain_core.messages import HumanMessage

from app.graph import get_graph
from app.schemas import AgentRespondRequest
from app.security import require_service_auth

router = APIRouter(prefix="/v1/agent", tags=["agent"])

# Only these graph nodes stream user-facing tokens. The router's own LLM call
# (structured classification) also runs under stream_mode="messages"; filtering
# by node keeps its chunks out of the SSE stream.
_ANSWER_NODES = {"general_advisor", "scholarship_expert"}


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def _stream_turn(payload: AgentRespondRequest) -> Iterator[str]:
    graph = get_graph()
    # We set the root run id ourselves so owl-admin can persist it and link the
    # admin transcript straight to the LangSmith trace for this turn.
    run_id = str(uuid.uuid4())
    config = {"run_id": run_id, "configurable": {"thread_id": payload.thread_id}}
    inputs = {
        "messages": [HumanMessage(content=payload.user_message)],
        "user_context": payload.user_context.model_dump(),
    }

    accumulated = ""
    try:
        for mode, chunk in graph.stream(inputs, config=config, stream_mode=["updates", "messages"]):
            if mode == "updates":
                node, delta = next(iter(chunk.items()))
                if node == "route":
                    yield _sse(
                        "routing",
                        {
                            "route": delta.get("route", "general"),
                            "scholarship_id": delta.get("scholarship_id"),
                            "scholarship_title": delta.get("scholarship_title"),
                        },
                    )
                continue

            message_chunk, metadata = chunk
            if metadata.get("langgraph_node") not in _ANSWER_NODES:
                continue
            piece = getattr(message_chunk, "content", "") or ""
            if piece:
                accumulated += piece
                yield _sse("token", {"content": piece})

        final = graph.get_state(config).values
        route = final.get("route", "general")
        agent = "scholarship_expert" if route == "expert" else "general_advisor"
        citations = final.get("citations", [])
        final_message = final["messages"][-1].content if final.get("messages") else accumulated

        # The graceful "no scholarships yet" / "expert scholarship missing" paths
        # return one plain message with no streaming LLM call.
        if not accumulated and final_message:
            yield _sse("token", {"content": final_message})

        done: dict = {
            "message": final_message,
            "citations": citations,
            "agent": agent,
            "route": route,
            "run_id": run_id,
            # Phase 6: what owl-admin persists for the fine-tuning corpus.
            "system_prompt": final.get("system_prompt", ""),
            "model_variant": final.get("model_variant", "base"),
        }
        if route == "expert":
            done["scholarship"] = {
                "id": final.get("scholarship_id"),
                "title": final.get("scholarship_title"),
            }
        yield _sse("done", done)
    except Exception as exc:  # noqa: BLE001 - surface the failure to the client, don't 500 mid-stream
        yield _sse("error", {"detail": str(exc)})


@router.post("/respond")
def respond(
    payload: AgentRespondRequest,
    _claims: dict = Depends(require_service_auth),
) -> StreamingResponse:
    """Streams one conversational turn as SSE.

    Frames: one ``routing`` (which node took the turn), then ``token`` per chunk,
    then ``done`` ({ message, citations, agent, route, run_id, system_prompt,
    model_variant, scholarship? }). ``error`` replaces the tail if something
    breaks mid-stream.

    Called only by owl-admin, which relays this straight to the browser and
    persists the result. Conversation memory lives in the graph's Postgres
    checkpointer, keyed by thread_id — the caller doesn't send history.
    """
    return StreamingResponse(_stream_turn(payload), media_type="text/event-stream")
