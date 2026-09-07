"""app/tools.py — get_scholarship_detail and check_eligibility run against the
real DB with no OpenAI calls; search_scholarships only needs its embedder faked.
"""

import app.tools as tools_module
from app.db import SessionLocal
from app.db_models import Scholarship, ScholarshipChunk
from app.tools import check_eligibility, get_scholarship_detail, search_scholarships

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
