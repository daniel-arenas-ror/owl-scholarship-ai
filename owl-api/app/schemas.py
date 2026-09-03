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
    content_hash: str
    last_seen_at: datetime | None = None


class ScholarshipIngestResult(BaseModel):
    scholarship_id: str
    chunks: int
    action: Literal["created", "updated", "unchanged"]


# --- POST /v1/agent/respond ------------------------------------------------
class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class UserContext(BaseModel):
    country: str | None = None
    level: str | None = None
    fields: list[str] = Field(default_factory=list)


class AgentRespondRequest(BaseModel):
    conversation_id: str
    thread_id: str
    user_message: str
    history: list[ChatTurn] = Field(default_factory=list)
    user_context: UserContext = Field(default_factory=UserContext)


class Citation(BaseModel):
    scholarship_id: str
    title: str
    source_url: str


class AgentRespondResult(BaseModel):
    message: str
    citations: list[Citation] = Field(default_factory=list)
    agent: str = "general_advisor"
    trace_url: str | None = None
