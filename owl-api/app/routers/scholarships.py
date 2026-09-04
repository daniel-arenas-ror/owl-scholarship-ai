from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.chunking import chunk_markdown
from app.config import get_settings
from app.db import get_session
from app.db_models import Scholarship, ScholarshipChunk
from app.embeddings import embed_texts
from app.schemas import ScholarshipIngest, ScholarshipIngestResult
from app.security import require_service_auth

router = APIRouter(prefix="/v1/scholarships", tags=["scholarships"])


@router.post("/ingest", response_model=ScholarshipIngestResult)
def ingest(
    payload: ScholarshipIngest,
    session: Session = Depends(get_session),
    _claims: dict = Depends(require_service_auth),
) -> ScholarshipIngestResult:
    """Upsert a scholarship by content_hash: chunk body_markdown, embed each
    chunk with OpenAI, and store the vectors in pgvector."""
    if not get_settings().openai_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OPENAI_API_KEY is not configured — set it before ingesting.",
        )

    unchanged = session.scalar(
        select(Scholarship).where(Scholarship.content_hash == payload.content_hash)
    )
    if unchanged:
        return ScholarshipIngestResult(
            scholarship_id=str(unchanged.id), chunks=len(unchanged.chunks), action="unchanged"
        )

    scholarship = session.scalar(
        select(Scholarship).where(
            Scholarship.source == payload.source, Scholarship.source_url == payload.source_url
        )
    )
    action = "updated" if scholarship else "created"
    scholarship = scholarship or Scholarship(source=payload.source, source_url=payload.source_url)

    scholarship.external_id = payload.external_id
    scholarship.title = payload.title
    scholarship.provider = payload.provider
    scholarship.country = payload.country
    scholarship.fields = payload.fields
    scholarship.levels = payload.levels
    scholarship.funding_type = payload.funding_type
    scholarship.amount_note = payload.amount_note
    scholarship.deadline = payload.deadline
    scholarship.eligibility_text = payload.eligibility_text
    scholarship.body_markdown = payload.body_markdown
    scholarship.content_hash = payload.content_hash
    scholarship.last_seen_at = payload.last_seen_at

    scholarship.chunks.clear()  # cascade delete-orphan drops the old rows on flush
    texts = chunk_markdown(payload.body_markdown)
    vectors = embed_texts(texts)
    for i, (text, vector) in enumerate(zip(texts, vectors, strict=True)):
        scholarship.chunks.append(ScholarshipChunk(chunk_index=i, content=text, embedding=vector))

    session.add(scholarship)
    session.commit()
    session.refresh(scholarship)

    return ScholarshipIngestResult(
        scholarship_id=str(scholarship.id), chunks=len(scholarship.chunks), action=action
    )
