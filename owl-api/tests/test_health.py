from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_ok():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["database"] in {"up", "down"}


def test_ingest_requires_token():
    resp = client.post("/v1/scholarships/ingest", json={})
    assert resp.status_code in {401, 422}


def test_agent_respond_shape():
    resp = client.post(
        "/v1/agent/respond",
        json={
            "conversation_id": "c1",
            "thread_id": "t1",
            "user_message": "hola",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "message" in body
    assert body["agent"] == "general_advisor"
