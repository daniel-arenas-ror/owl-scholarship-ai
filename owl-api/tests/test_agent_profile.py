"""The profile route: the router hands off to profile_collector, which binds
update_profile as a real LangChain tool, executes whatever the model calls it
with, and persists through both owl-admin (durable) and the InMemoryStore
(this process, immediately — so the very next turn sees it with no re-fetch).
"""

import app.graph as graph_module
import app.tools as tools_module
from app.config import get_settings
from app.graph import RouteDecision
from app.main import app
from app.security import require_service_auth
from tests.sse_helpers import parse_sse


class _ToolCallResponse:
    def __init__(self, tool_calls):
        self.tool_calls = tool_calls


class _FakeBindableModel:
    """Stands in for get_router_model().bind_tools([...]).invoke(...) — bind_tools
    returns self so whichever tool object the node built still gets executed for
    real when the test drives .invoke on it."""

    def __init__(self, response):
        self._response = response

    def bind_tools(self, _tools):
        return self

    def invoke(self, _messages):
        return self._response


def _post(client, thread_id, message):
    app.dependency_overrides[require_service_auth] = lambda: {"sub": "1"}
    try:
        return client.post(
            "/v1/agent/respond",
            json={
                "conversation_id": "c1",
                "thread_id": thread_id,
                "user_id": "42",
                "user_message": message,
            },
        )
    finally:
        app.dependency_overrides.pop(require_service_auth, None)


def _prime(monkeypatch, tool_calls, saved: dict):
    monkeypatch.setattr(
        graph_module, "_classify_route", lambda history: RouteDecision(route="profile")
    )
    monkeypatch.setattr(
        graph_module, "get_router_model", lambda: _FakeBindableModel(_ToolCallResponse(tool_calls))
    )
    monkeypatch.setattr(graph_module, "load_user_profile", lambda user_id: {})

    def fake_save(user_id, **fields):
        saved["user_id"] = user_id
        saved.update({k: v for k, v in fields.items() if v is not None})
        return {}

    monkeypatch.setattr(tools_module, "save_user_profile", fake_save)
    monkeypatch.setattr(graph_module, "save_user_profile", fake_save)
    monkeypatch.setattr(get_settings(), "openai_api_key", "test-key-not-real")


def test_profile_route_saves_stated_fields_and_confirms(client, monkeypatch):
    saved: dict = {}
    tool_calls = [
        {
            "name": "update_profile",
            "args": {"full_name": "Maria Lopez", "phone": None, "degrees": ["Ingeniería"]},
            "id": "call_1",
        }
    ]
    _prime(monkeypatch, tool_calls, saved)

    resp = _post(client, "test-profile-save", "me llamo Maria Lopez y estudié Ingeniería")

    assert resp.status_code == 200
    events = parse_sse(resp.text)

    routing = next(data for name, data in events if name == "routing")
    assert routing["route"] == "profile"

    done = next(data for name, data in events if name == "done")
    assert done["agent"] == "profile_collector"
    assert done["route"] == "profile"
    assert "tu nombre" in done["message"]
    assert "tus títulos" in done["message"]
    assert "tu teléfono" not in done["message"]

    assert saved["user_id"] == "42"
    assert saved["full_name"] == "Maria Lopez"
    assert saved["degrees"] == ["Ingeniería"]
    assert "phone" not in saved


def test_profile_route_asks_again_when_nothing_new_was_stated(client, monkeypatch):
    saved: dict = {}
    _prime(monkeypatch, tool_calls=[], saved=saved)

    resp = _post(client, "test-profile-empty", "guarda mis datos")

    assert resp.status_code == 200
    done = next(data for name, data in parse_sse(resp.text) if name == "done")
    assert "Cuéntame" in done["message"]
    assert saved == {}


def test_store_write_through_is_visible_without_a_re_fetch(monkeypatch):
    """The whole point of the InMemoryStore: once profile_collector writes a
    profile, ANY later node in this process — even for a brand new
    conversation thread — sees it with no further owl-admin round trip."""
    from langgraph.store.memory import InMemoryStore

    store = InMemoryStore()
    load_calls = []
    monkeypatch.setattr(
        graph_module, "load_user_profile", lambda user_id: load_calls.append(user_id) or {}
    )

    # Cold: nothing cached yet, so hydrating costs one call to owl-admin.
    profile = graph_module._hydrate_profile(store, "42")
    assert profile == {}
    assert load_calls == ["42"]

    # profile_collector's write path: persist durably (mocked away) + update
    # the cache immediately.
    graph_module._remember_profile(store, "42", full_name="Maria Lopez", degrees=["Ingeniería"])

    # Any later node, any thread, same process: no second call to owl-admin.
    profile_again = graph_module._hydrate_profile(store, "42")
    assert profile_again == {"full_name": "Maria Lopez", "degrees": ["Ingeniería"]}
    assert load_calls == ["42"]  # still just the one cold-cache fetch
