"""Exercises the real pgvector query in app/routers/agent.py. OpenAI calls are
faked (embed_query, get_chat_model) so this runs in CI with no API key and no
network — only the database round-trip and the SQL are real.
"""

import app.routers.agent as agent_module
from app.config import get_settings
from app.db import SessionLocal
from app.db_models import Scholarship, ScholarshipChunk
from app.main import app
from app.security import require_service_auth

EMBEDDING_DIMENSIONS = 1536
CONTENT_HASH = "test-fixture-hash-do-not-reuse"


class _FakeMessage:
    def __init__(self, content):
        self.content = content


class _FakeChatModel:
    def invoke(self, messages):
        return _FakeMessage("Respuesta simulada citando la beca de prueba.")


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
        monkeypatch.setattr(agent_module, "embed_query", lambda text: [0.1] * EMBEDDING_DIMENSIONS)
        monkeypatch.setattr(agent_module, "get_chat_model", lambda: _FakeChatModel())
        monkeypatch.setattr(get_settings(), "openai_api_key", "test-key-not-real")

        app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}
        try:
            resp = client.post(
                "/v1/agent/respond",
                json={
                    "conversation_id": "c1",
                    "thread_id": "t1",
                    "user_message": "¿Hay becas de maestría?",
                },
            )
        finally:
            app.dependency_overrides.pop(require_service_auth, None)

        assert resp.status_code == 200
        body = resp.json()
        assert body["message"] == "Respuesta simulada citando la beca de prueba."
        assert len(body["citations"]) == 1
        assert body["citations"][0]["scholarship_id"] == str(scholarship_id)
        assert body["citations"][0]["title"] == "Beca de prueba para maestría"
    finally:
        _delete_scholarship(scholarship_id)
