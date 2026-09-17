"""app/owl_admin_client.py — the reverse direction of OwlApiClient. Exercised
against a real httpx.MockTransport (no real network, no owl-admin needed) so
the actual request-building code runs, not just a mocked function boundary.
"""

import json

import httpx
import pytest

import app.owl_admin_client as client
from app.config import get_settings


@pytest.fixture(autouse=True)
def _configured_secret(monkeypatch):
    monkeypatch.setattr(get_settings(), "owl_internal_secret", "test-secret")
    monkeypatch.setattr(get_settings(), "owl_admin_url", "http://admin.test")


def _mock_client(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_get_user_profile_sends_the_bearer_secret(monkeypatch):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["auth"] = request.headers["authorization"]
        return httpx.Response(200, json={"full_name": "Maria Lopez", "email": "m@x.com"})

    monkeypatch.setattr(httpx, "get", lambda url, **kw: _mock_client(handler).get(url, **kw))

    profile = client.get_user_profile("42")

    assert seen["url"] == "http://admin.test/internal/users/42/profile"
    assert seen["auth"] == "Bearer test-secret"
    assert profile["full_name"] == "Maria Lopez"


def test_get_user_profile_wraps_a_non_2xx_as_owl_admin_error(monkeypatch):
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": "not found"})

    monkeypatch.setattr(httpx, "get", lambda url, **kw: _mock_client(handler).get(url, **kw))

    with pytest.raises(client.OwlAdminError):
        client.get_user_profile("999")


def test_update_user_profile_omits_none_fields(monkeypatch):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["body"] = request.content
        return httpx.Response(200, json={"full_name": "Maria Lopez"})

    monkeypatch.setattr(httpx, "patch", lambda url, **kw: _mock_client(handler).patch(url, **kw))

    client.update_user_profile("42", full_name="Maria Lopez", phone=None, degrees=None)

    assert json.loads(seen["body"]) == {"full_name": "Maria Lopez"}


def test_send_conversation_email_posts_with_no_body(monkeypatch):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["method"] = request.method
        seen["url"] = str(request.url)
        return httpx.Response(200, json={"status": "sent"})

    monkeypatch.setattr(httpx, "post", lambda url, **kw: _mock_client(handler).post(url, **kw))

    result = client.send_conversation_email("7")

    assert seen["method"] == "POST"
    assert seen["url"] == "http://admin.test/internal/conversations/7/email"
    assert result == {"status": "sent"}


def test_a_connection_failure_is_also_wrapped(monkeypatch):
    def handler(_request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused")

    monkeypatch.setattr(httpx, "post", lambda url, **kw: _mock_client(handler).post(url, **kw))

    with pytest.raises(client.OwlAdminError):
        client.send_conversation_email("7")
