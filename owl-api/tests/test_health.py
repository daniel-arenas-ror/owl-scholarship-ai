import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.security import require_service_auth


@pytest.fixture(scope="module")
def client():
    # The `with` form runs the app's lifespan (ensure_pgvector + create_tables)
    # before any test executes — plain TestClient(app) would skip it.
    with TestClient(app) as c:
        yield c


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["database"] in {"up", "down"}


def test_ingest_requires_auth(client):
    resp = client.post("/v1/scholarships/ingest", json={})
    assert resp.status_code in {401, 422}


def test_agent_respond_requires_auth(client):
    resp = client.post(
        "/v1/agent/respond",
        json={"conversation_id": "c1", "thread_id": "t1", "user_message": "hola"},
    )
    assert resp.status_code == 401


def test_agent_respond_without_data_is_graceful(client):
    app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}
    try:
        resp = client.post(
            "/v1/agent/respond",
            json={"conversation_id": "c1", "thread_id": "t1", "user_message": "hola"},
        )
    finally:
        app.dependency_overrides.pop(require_service_auth, None)

    assert resp.status_code == 200
    body = resp.json()
    assert "message" in body
    assert body["agent"] == "general_advisor"
