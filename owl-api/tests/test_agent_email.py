"""The email route: the router hands off to email_sender, a pure tool call —
no LLM generation at all, just "ask owl-admin to send it" and a templated
confirmation (or graceful failure) message.
"""

import app.graph as graph_module
from app.config import get_settings
from app.graph import RouteDecision
from app.main import app
from app.owl_admin_client import OwlAdminError
from app.security import require_service_auth
from tests.sse_helpers import parse_sse


def _post(client, thread_id, conversation_id="c1"):
    app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}
    try:
        return client.post(
            "/v1/agent/respond",
            json={
                "conversation_id": conversation_id,
                "thread_id": thread_id,
                "user_id": "42",
                "user_message": "envíame esta conversación a mi correo",
            },
        )
    finally:
        app.dependency_overrides.pop(require_service_auth, None)


def _prime(monkeypatch):
    monkeypatch.setattr(
        graph_module, "_classify_route", lambda history: RouteDecision(route="email")
    )
    monkeypatch.setattr(get_settings(), "openai_api_key", "test-key-not-real")


def test_email_route_confirms_on_success(client, monkeypatch):
    _prime(monkeypatch)
    sent = []
    monkeypatch.setattr(
        graph_module,
        "send_conversation_email",
        lambda conversation_id: sent.append(conversation_id),
    )

    resp = _post(client, "test-email-ok", conversation_id="c-99")

    assert resp.status_code == 200
    events = parse_sse(resp.text)

    routing = next(data for name, data in events if name == "routing")
    assert routing["route"] == "email"

    done = next(data for name, data in events if name == "done")
    assert done["agent"] == "email_sender"
    assert "envié la conversación" in done["message"]
    assert sent == ["c-99"]


def test_email_route_fails_gracefully(client, monkeypatch):
    _prime(monkeypatch)

    def fake_send(_conversation_id):
        raise OwlAdminError("owl-admin unreachable")

    monkeypatch.setattr(graph_module, "send_conversation_email", fake_send)

    resp = _post(client, "test-email-fail")

    assert resp.status_code == 200
    done = next(data for name, data in parse_sse(resp.text) if name == "done")
    assert done["agent"] == "email_sender"
    assert "No pude enviar" in done["message"]
