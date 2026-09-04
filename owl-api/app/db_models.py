"""SQLAlchemy ORM models — distinct from app/schemas.py, which holds the
Pydantic request/response shapes for the HTTP API.

Phase 1 shortcut: tables are created with Base.metadata.create_all() at
startup (see app.db.create_tables) instead of real migrations. Revisit with
Alembic once the schema has more than one moving piece.
"""

from datetime import UTC, datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import ARRAY, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

EMBEDDING_DIMENSIONS = 1536  # text-embedding-3-small


class Base(DeclarativeBase):
    pass


class Scholarship(Base):
    __tablename__ = "scholarships"
    __table_args__ = (UniqueConstraint("content_hash", name="uq_scholarships_content_hash"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(120))
    source_url: Mapped[str] = mapped_column(Text)
    external_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    title: Mapped[str] = mapped_column(String(500))
    provider: Mapped[str] = mapped_column(String(255))
    country: Mapped[str] = mapped_column(String(8), default="CO")
    fields: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)
    levels: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)
    funding_type: Mapped[str | None] = mapped_column(String(120), nullable=True)
    amount_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    deadline: Mapped[str | None] = mapped_column(Text, nullable=True)
    eligibility_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    body_markdown: Mapped[str] = mapped_column(Text)
    content_hash: Mapped[str] = mapped_column(String(64))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=lambda: datetime.now(UTC)
    )

    chunks: Mapped[list["ScholarshipChunk"]] = relationship(
        back_populates="scholarship",
        cascade="all, delete-orphan",
        order_by="ScholarshipChunk.chunk_index",
    )


class ScholarshipChunk(Base):
    __tablename__ = "scholarship_chunks"

    id: Mapped[int] = mapped_column(primary_key=True)
    scholarship_id: Mapped[int] = mapped_column(ForeignKey("scholarships.id", ondelete="CASCADE"))
    chunk_index: Mapped[int] = mapped_column(Integer)
    content: Mapped[str] = mapped_column(Text)
    embedding: Mapped[list[float]] = mapped_column(Vector(EMBEDDING_DIMENSIONS))

    scholarship: Mapped["Scholarship"] = relationship(back_populates="chunks")
