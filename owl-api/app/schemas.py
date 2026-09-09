"""Wire contracts between owl-admin and owl-api.

These mirror the "How the pieces talk" section of the roadmap. Phase 0 only
validates the shapes; Phase 1 fills in the behaviour.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# --- POST /v1/scholarships/ingest -------------------------------------------
class ScholarshipIngest(BaseModel):
    source: str
    source_url: str
    external_id: str | None = None
    title: str
    provider: str
    country: str = "CO"
    fields: list[str] = Field(default_factory=list)
    levels: list[str] = Field(default_factory=list)
    funding_type: str | None = None
    amount_note: str | None = None
    deadline: str | None = None
    eligibility_text: str | None = None
    body_markdown: str
    # Optional: owl-api computes it from the wire fields when the caller omits
    # it, so any edited field triggers a re-embed.
    content_hash: str | None = None
    last_seen_at: datetime | None = None


class ScholarshipIngestResult(BaseModel):
    scholarship_id: str
    chunks: int
    action: Literal["created", "updated", "unchanged"]


# --- POST /v1/agent/respond (SSE) -------------------------------------------
class UserContext(BaseModel):
    country: str | None = None
    level: str | None = None
    fields: list[str] = Field(default_factory=list)


class AgentRespondRequest(BaseModel):
    conversation_id: str
    thread_id: str
    user_message: str
    user_context: UserContext = Field(default_factory=UserContext)
