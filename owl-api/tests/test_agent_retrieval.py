"""Exercises the real pgvector query inside the general_advisor node. OpenAI
calls are faked (embed_query, the chat model, and the router classifier) so this
runs in CI with no API key and no network — only the database round-trip, the
SQL, and the SSE framing of app/routers/agent.py are real.
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
CONTENT_HASH = "test-fixture-hash-do-not-reuse"


class _FakeChatModel:
    def stream(self, messages):
        from langchain_core.messages import AIMessageChunk

        yield AIMessageChunk(content="Respuesta simulada ")
        yield AIMessageChunk(content="citando la beca de prueba.")


def _seed_one_scholarship():
    with SessionLocal() as session:
        scholarship = Scholarship(
            source="test",
            source_url="https://example.com/beca-prueba",
            title="Beca de prueba para maestría",
            provider="Universidad de Prueba",
            country="CO",
            fields=["Pruebas"],
            levels=["maestría"],
            body_markdown="Contenido de la beca de prueba.",
            content_hash=CONTENT_HASH,
        )
        scholarship.chunks.append(
            ScholarshipChunk(
                chunk_index=0,
                content="La beca de prueba cubre matrícula completa para maestría.",
                embedding=[0.1] * EMBEDDING_DIMENSIONS,
            )
        )
        session.add(scholarship)
        session.commit()
        return scholarship.id


def _delete_scholarship(scholarship_id):
    with SessionLocal() as session:
        scholarship = session.get(Scholarship, scholarship_id)
        if scholarship:
            session.delete(scholarship)
            session.commit()


def test_agent_respond_retrieves_and_cites_a_real_match(client, monkeypatch):
    scholarship_id = _seed_one_scholarship()
    try:
        monkeypatch.setattr(tools_module, "embed_query", lambda text: [0.1] * EMBEDDING_DIMENSIONS)
        monkeypatch.setattr(graph_module, "get_chat_model", lambda: _FakeChatModel())
        monkeypatch.setattr(
            graph_module, "_classify_route", lambda history: RouteDecision(route="general")
        )
        monkeypatch.setattr(get_settings(), "openai_api_key", "test-key-not-real")

        app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}
        try:
            resp = client.post(
                "/v1/agent/respond",
                json={
                    "conversation_id": "c1",
                    "thread_id": "test-agent-retrieval-match",
                    "user_message": "¿Hay becas de maestría?",
                },
            )
        finally:
            app.dependency_overrides.pop(require_service_auth, None)

        assert resp.status_code == 200
        events = parse_sse(resp.text)

        routing = next(data for name, data in events if name == "routing")
        assert routing["route"] == "general"

        tokens = "".join(data["content"] for name, data in events if name == "token")
        assert tokens == "Respuesta simulada citando la beca de prueba."

        done = next(data for name, data in events if name == "done")
        assert done["message"] == "Respuesta simulada citando la beca de prueba."
        assert done["agent"] == "general_advisor"
        assert done["route"] == "general"
        assert done["run_id"]
        assert len(done["citations"]) == 1
        assert done["citations"][0]["scholarship_id"] == str(scholarship_id)
        assert done["citations"][0]["title"] == "Beca de prueba para maestría"
    finally:
        _delete_scholarship(scholarship_id)
