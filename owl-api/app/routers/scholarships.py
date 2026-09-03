from fastapi import APIRouter, Depends

from app.schemas import ScholarshipIngest, ScholarshipIngestResult
from app.security import require_internal_token

router = APIRouter(prefix="/v1/scholarships", tags=["scholarships"])


@router.post("/ingest", response_model=ScholarshipIngestResult)
def ingest(
    payload: ScholarshipIngest,
    _: None = Depends(require_internal_token),
) -> ScholarshipIngestResult:
    """Accept a normalized scholarship from owl-admin.

    Phase 1: upsert by content_hash, chunk body_markdown, embed with OpenAI,
    store vectors in pgvector. For now we just echo a deterministic stub.
    """
    return ScholarshipIngestResult(
        scholarship_id=payload.content_hash[:16],
        chunks=0,
        action="unchanged",
    )
