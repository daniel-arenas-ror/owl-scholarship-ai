"""app/tools.py — get_scholarship_detail and check_eligibility run against the
real DB with no OpenAI calls; search_scholarships only needs its embedder faked.
save_user_profile / load_user_profile / send_conversation_email are thin
pass-throughs to owl_admin_client — tested here by faking that boundary, the
same way search_scholarships fakes embed_query.
"""

import app.owl_admin_client as owl_admin_client
import app.tools as tools_module
from app.db import SessionLocal
from app.db_models import Scholarship, ScholarshipChunk
from app.tools import (
    check_eligibility,
    get_scholarship_detail,
    load_user_profile,
    save_user_profile,
    search_scholarships,
    send_conversation_email,
)

EMBEDDING_DIMENSIONS = 1536


def _seed():
    with SessionLocal() as session:
        scholarship = Scholarship(
            source="test",
            source_url="https://example.com/tools-fixture",
            title="Beca Tools de doctorado",
            provider="Fundación Tools",
            country="CO",
            fields=["Ingeniería"],
            levels=["doctorado"],
            funding_type="beca completa",
            amount_note="Cubre matrícula y sostenimiento.",
            deadline="Marzo de cada año.",
            eligibility_text="Para colombianos admitidos en un doctorado.",
            body_markdown="Cuerpo de la beca tools.",
            content_hash="tools-fixture-hash",
        )
        scholarship.chunks.append(
            ScholarshipChunk(
                chunk_index=0,
                content="La Beca Tools financia doctorados en ingeniería.",
                embedding=[0.2] * EMBEDDING_DIMENSIONS,
            )
        )
        session.add(scholarship)
        session.commit()
        return scholarship.id


def _delete(scholarship_id):
    with SessionLocal() as session:
        row = session.get(Scholarship, scholarship_id)
        if row:
            session.delete(row)
            session.commit()


def test_get_scholarship_detail_returns_every_field_or_none():
    scholarship_id = _seed()
    try:
        detail = get_scholarship_detail(str(scholarship_id))
        assert detail["title"] == "Beca Tools de doctorado"
        assert detail["levels"] == ["doctorado"]
        assert detail["deadline"] == "Marzo de cada año."
        assert detail["chunks"] == ["La Beca Tools financia doctorados en ingeniería."]

        assert get_scholarship_detail("999999") is None
        assert get_scholarship_detail("not-a-number") is None
    finally:
        _delete(scholarship_id)


def test_check_eligibility_flags_a_level_mismatch():
    scholarship_id = _seed()
    try:
        likely = check_eligibility(str(scholarship_id), {"level": "doctorado", "country": "CO"})
        assert likely["status"] == "likely"

        unlikely = check_eligibility(str(scholarship_id), {"level": "pregrado"})
        assert unlikely["status"] == "unlikely"
        assert any("pregrado" in reason for reason in unlikely["reasons"])

        blank = check_eligibility(str(scholarship_id), {})
        assert blank["status"] == "unknown"

        assert check_eligibility("999999", {"level": "doctorado"})["status"] == "unknown"
    finally:
        _delete(scholarship_id)


def test_search_scholarships_shapes_hits(monkeypatch):
    scholarship_id = _seed()
    try:
        monkeypatch.setattr(tools_module, "embed_query", lambda text: [0.2] * EMBEDDING_DIMENSIONS)
        hits = search_scholarships("doctorado en ingeniería", k=3)
        assert hits
        assert hits[0]["scholarship_id"] == str(scholarship_id)
        assert hits[0]["title"] == "Beca Tools de doctorado"
        assert "snippet" in hits[0]
    finally:
        _delete(scholarship_id)


def test_save_user_profile_forwards_only_given_fields(monkeypatch):
    captured = {}

    def fake_update(user_id, **fields):
        captured["user_id"] = user_id
        captured["fields"] = fields
        return {"full_name": fields.get("full_name")}

    monkeypatch.setattr(owl_admin_client, "update_user_profile", fake_update)

    result = save_user_profile("42", full_name="Maria Lopez", phone=None, degrees=None)

    assert captured["user_id"] == "42"
    assert captured["fields"] == {"full_name": "Maria Lopez", "phone": None, "degrees": None}
    assert result == {"full_name": "Maria Lopez"}


def test_load_user_profile_returns_empty_dict_when_owl_admin_is_unreachable(monkeypatch):
    def fake_get(user_id):
        raise owl_admin_client.OwlAdminError("connection refused")

    monkeypatch.setattr(owl_admin_client, "get_user_profile", fake_get)

    assert load_user_profile("42") == {}


def test_load_user_profile_passes_through_a_real_profile(monkeypatch):
    monkeypatch.setattr(
        owl_admin_client, "get_user_profile", lambda user_id: {"full_name": "Maria Lopez"}
    )
    assert load_user_profile("42") == {"full_name": "Maria Lopez"}


def test_send_conversation_email_forwards_the_conversation_id(monkeypatch):
    captured = {}

    def fake_send(conversation_id):
        captured["conversation_id"] = conversation_id
        return {"status": "sent"}

    monkeypatch.setattr(owl_admin_client, "send_conversation_email", fake_send)

    assert send_conversation_email("123") == {"status": "sent"}
    assert captured["conversation_id"] == "123"
