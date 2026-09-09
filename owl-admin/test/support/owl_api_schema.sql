-- owl-api owns the real `scholarships` schema (SQLAlchemy, in the owl_api DB).
-- For owl-admin's test suite we just need a table the `Scholarship` model can
-- read and write fixtures against, so this is a faithful-enough subset. The
-- pgvector `scholarship_chunks.embedding` column is intentionally left out —
-- owl-admin never touches it.

CREATE TABLE IF NOT EXISTS scholarships (
  id               bigserial PRIMARY KEY,
  source           varchar(120) NOT NULL,
  source_url       text NOT NULL,
  external_id      varchar(255),
  title            varchar(500) NOT NULL,
  provider         varchar(255) NOT NULL,
  country          varchar(8) NOT NULL DEFAULT 'CO',
  fields           text[] NOT NULL DEFAULT '{}',
  levels           text[] NOT NULL DEFAULT '{}',
  funding_type     varchar(120),
  amount_note      text,
  deadline         text,
  eligibility_text text,
  body_markdown    text NOT NULL,
  content_hash     varchar(64) NOT NULL,
  last_seen_at     timestamp,
  created_at       timestamp NOT NULL DEFAULT now(),
  updated_at       timestamp NOT NULL DEFAULT now(),
  CONSTRAINT uq_scholarships_content_hash UNIQUE (content_hash)
);
