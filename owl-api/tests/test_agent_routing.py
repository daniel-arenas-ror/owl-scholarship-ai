"""The Phase 4 router: given a classifier decision, does the graph hand off to
the right worker node, pin the right scholarship, and label the `done` frame?

The classifier LLM is faked (_classify_route), as are the worker chat model and
the embedder. The routing logic, the name->id resolution against the real DB,
and the SSE framing all run for real.
"""

import app.graph as graph_module
import app.tools as tools_module
from app.config import get_settings
from app.db import SessionLocal
from app.db_models import Scholarship, ScholarshipChunk
from app.graph import RouteDecision
from app.main import app
from app.security import require_service_auth
from tests.sse_helpers import parse_sse

EMBEDDING_DIMENSIONS = 1536


class _FakeChatModel:
    def stream(self, messages):
        from langchain_core.messages import AIMessageChunk

        yield AIMessageChunk(content="Detalle de la beca.")


def _seed(title, provider, content_hash, *, levels=("maestría",)):
    with SessionLocal() as session:
        scholarship = Scholarship(
            source="test",
            source_url=f"https://example.com/{content_hash}",
            title=title,
            provider=provider,
            country="CO",
            fields=["Todas las áreas"],
            levels=list(levels),
            body_markdown=f"Cuerpo de {title}.",
            content_hash=content_hash,
        )
        scholarship.chunks.append(
            ScholarshipChunk(
                chunk_index=0,
                content=f"{title} de {provider} financia estudios de posgrado.",
                embedding=[0.05] * EMBEDDING_DIMENSIONS,
            )
        )
        session.add(scholarship)
        session.commit()
        return scholarship.id


def _delete(*ids):
    with SessionLocal() as session:
        for scholarship_id in ids:
            row = session.get(Scholarship, scholarship_id)
            if row:
                session.delete(row)
        session.commit()


def _post(client, thread_id, message):
    app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}
    try:
        return client.post(
            "/v1/agent/respond",
            json={
                "conversation_id": "c1",
                "thread_id": thread_id,
                "user_message": message,
            },
        )
    finally:
        app.dependency_overrides.pop(require_service_auth, None)


def _prime(monkeypatch, decision):
    monkeypatch.setattr(tools_module, "embed_query", lambda text: [0.05] * EMBEDDING_DIMENSIONS)
    monkeypatch.setattr(graph_module, "pick_answer_model", lambda: (_FakeChatModel(), "base"))
    monkeypatch.setattr(graph_module, "_classify_route", lambda history: decision)
    monkeypatch.setattr(get_settings(), "openai_api_key", "test-key-not-real")


def test_routes_to_expert_when_a_named_scholarship_resolves(client, monkeypatch):
    chevening = _seed("Beca Chevening", "Gobierno del Reino Unido", "route-fixture-chevening")
    daad = _seed("Beca DAAD", "DAAD", "route-fixture-daad")
    try:
        _prime(monkeypatch, RouteDecision(route="expert", scholarship_query="Chevening"))
        resp = _post(client, "test-route-expert", "¿Qué cubre Chevening?")

        assert resp.status_code == 200
        events = parse_sse(resp.text)

        routing = next(data for name, data in events if name == "routing")
        assert routing["route"] == "expert"
        assert routing["scholarship_id"] == str(chevening)
        assert routing["scholarship_title"] == "Beca Chevening"

        done = next(data for name, data in events if name == "done")
        assert done["agent"] == "scholarship_expert"
        assert done["route"] == "expert"
        assert done["scholarship"] == {"id": str(chevening), "title": "Beca Chevening"}
        assert [c["scholarship_id"] for c in done["citations"]] == [str(chevening)]
    finally:
        _delete(chevening, daad)


def test_falls_back_to_general_when_the_named_scholarship_is_unknown(client, monkeypatch):
    daad = _seed("Beca DAAD", "DAAD", "route-fixture-daad-only")
    try:
        _prime(monkeypatch, RouteDecision(route="expert", scholarship_query="Beca Inexistente XYZ"))
        resp = _post(client, "test-route-fallback", "Cuéntame de la Beca Inexistente XYZ")

        assert resp.status_code == 200
        events = parse_sse(resp.text)

        routing = next(data for name, data in events if name == "routing")
        assert routing["route"] == "general"
        assert routing["scholarship_id"] is None

        done = next(data for name, data in events if name == "done")
        assert done["agent"] == "general_advisor"
        assert "scholarship" not in done
    finally:
        _delete(daad)
