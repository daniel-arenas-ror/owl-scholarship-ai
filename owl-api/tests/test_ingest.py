"""POST /v1/scholarships/ingest — the caller may omit content_hash and owl-api
computes it from the wire fields, so any edited field re-triggers a re-embed.
OpenAI embedding is faked.
"""

import app.routers.scholarships as scholarships_router
from app.config import get_settings
from app.db import SessionLocal
from app.db_models import Scholarship
from app.main import app
from app.security import require_service_auth

SOURCE_URL = "https://example.com/ingest-fixture"


def _payload(**overrides):
    base = {
        "source": "example.com",
        "source_url": SOURCE_URL,
        "title": "Beca de prueba de ingest",
        "provider": "Proveedor Ingest",
        "country": "CO",
        "fields": ["Ingeniería"],
        "levels": ["maestría"],
        "deadline": "Marzo 2027",
        "body_markdown": "Cuerpo de la beca con suficiente texto para trocear.",
    }
    base.update(overrides)
    return base


def _cleanup():
    with SessionLocal() as session:
        session.query(Scholarship).filter_by(source_url=SOURCE_URL).delete()
        session.commit()


def test_ingest_without_hash_creates_then_dedupes_then_updates(client, monkeypatch):
    monkeypatch.setattr(
        scholarships_router, "embed_texts", lambda texts: [[0.1] * 1536 for _ in texts]
    )
    monkeypatch.setattr(get_settings(), "openai_api_key", "test-key-not-real")
    app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}

    try:
        created = client.post("/v1/scholarships/ingest", json=_payload())
        assert created.status_code == 200, created.text
        assert created.json()["action"] == "created"

        # identical payload, still no hash -> owl-api recomputes the same one
        same = client.post("/v1/scholarships/ingest", json=_payload())
        assert same.json()["action"] == "unchanged"

        # one edited field -> different computed hash -> re-embed
        edited = client.post("/v1/scholarships/ingest", json=_payload(deadline="Abril 2027"))
        assert edited.json()["action"] == "updated"

        with SessionLocal() as session:
            row = session.query(Scholarship).filter_by(source_url=SOURCE_URL).one()
            assert row.deadline == "Abril 2027"
    finally:
        app.dependency_overrides.pop(require_service_auth, None)
        _cleanup()
