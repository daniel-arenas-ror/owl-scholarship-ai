"""The three tools the graph nodes lean on: search, detail lookup, and an
eligibility check.

Phase 4 uses a structured-classifier router rather than a ReAct agent, so these
are plain functions the nodes call directly — not tools bound to an LLM. They
are still shaped like tools (flat args, JSON-able returns) and wrapped with
``@traceable`` so each shows up as its own span in LangSmith, which keeps the
door open to binding them to an agent later.
"""

from langsmith import traceable
from sqlalchemy import select

from app.db import SessionLocal
from app.db_models import Scholarship, ScholarshipChunk
from app.embeddings import embed_query

DEFAULT_TOP_K = 5


def _as_int(value: object) -> int:
    try:
        return int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return -1


@traceable(run_type="retriever", name="search_scholarships")
def search_scholarships(query: str, k: int = DEFAULT_TOP_K) -> list[dict]:
    """Vector search over scholarship chunks. Returns one entry per matching
    chunk (a scholarship can appear more than once), best match first."""
    with SessionLocal() as session:
        query_vector = embed_query(query)
        chunks = session.scalars(
            select(ScholarshipChunk)
            .order_by(ScholarshipChunk.embedding.cosine_distance(query_vector))
            .limit(k)
        ).all()
        return [
            {
                "scholarship_id": str(chunk.scholarship.id),
                "title": chunk.scholarship.title,
                "provider": chunk.scholarship.provider,
                "source_url": chunk.scholarship.source_url,
                "snippet": chunk.content,
            }
            for chunk in chunks
        ]


@traceable(run_type="tool", name="get_scholarship_detail")
def get_scholarship_detail(scholarship_id: str) -> dict | None:
    """Every stored field for one scholarship, plus its chunk texts. Returns
    None if the id is unknown."""
    with SessionLocal() as session:
        scholarship = session.get(Scholarship, _as_int(scholarship_id))
        if scholarship is None:
            return None
        return {
            "scholarship_id": str(scholarship.id),
            "title": scholarship.title,
            "provider": scholarship.provider,
            "country": scholarship.country,
            "fields": list(scholarship.fields or []),
            "levels": list(scholarship.levels or []),
            "funding_type": scholarship.funding_type,
            "amount_note": scholarship.amount_note,
            "deadline": scholarship.deadline,
            "eligibility_text": scholarship.eligibility_text,
            "source_url": scholarship.source_url,
            "body_markdown": scholarship.body_markdown,
            "chunks": [chunk.content for chunk in scholarship.chunks],
        }


@traceable(run_type="tool", name="check_eligibility")
def check_eligibility(scholarship_id: str, user_context: dict | None = None) -> dict:
    """Rule-of-thumb match between a user's profile (country / level / fields)
    and one scholarship. Deliberately not an LLM call — it feeds structured
    hints into the expert node's prompt, and the model does the nuance.

    status is one of "likely" | "unlikely" | "unknown".
    """
    context = user_context or {}
    detail = get_scholarship_detail(scholarship_id)
    if detail is None:
        return {"status": "unknown", "reasons": ["No encuentro esa beca."]}

    reasons: list[str] = []
    status = "likely"

    want_level = str(context.get("level") or "").strip().lower()
    levels = [lvl.lower() for lvl in detail["levels"]]
    if want_level and levels:
        if any(want_level in lvl or lvl in want_level for lvl in levels):
            reasons.append(
                f"El nivel «{want_level}» coincide con la beca ({', '.join(detail['levels'])})."
            )
        else:
            status = "unlikely"
            reasons.append(
                f"La beca es para {', '.join(detail['levels'])}, no para «{want_level}»."
            )

    want_country = str(context.get("country") or "").strip().upper()
    if want_country and detail["country"] and want_country != detail["country"].upper():
        reasons.append(
            f"La beca está asociada al país {detail['country']}; tu perfil indica "
            f"{want_country}. Confirma los requisitos de nacionalidad."
        )

    want_fields = [f.lower() for f in (context.get("fields") or [])]
    scholarship_fields = [f.lower() for f in detail["fields"]]
    open_to_all = any("todas" in f for f in scholarship_fields)
    if want_fields and scholarship_fields and not open_to_all:
        matched = any(wf in sf or sf in wf for wf in want_fields for sf in scholarship_fields)
        if matched:
            reasons.append("Tu área de interés aparece entre las áreas elegibles.")
        else:
            reasons.append(
                f"Áreas de la beca: {', '.join(detail['fields'])}. Verifica que la tuya aplique."
            )

    if not reasons:
        return {
            "status": "unknown",
            "scholarship_title": detail["title"],
            "reasons": ["No tengo suficientes datos de tu perfil para estimar la elegibilidad."],
        }

    return {"status": status, "scholarship_title": detail["title"], "reasons": reasons}
