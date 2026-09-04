# owl-api

Python + FastAPI. Retrieval, the LangGraph multi-agent graph, LangSmith tracing,
and every OpenAI call.

## Run with the rest of the stack

From the repo root: `make up` → http://localhost:8000 (`/health`, `/docs`).

## Run on its own

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
export OWL_API_DATABASE_URL=postgresql+psycopg://owl:owl@localhost:5432/owl_api
uvicorn app.main:app --reload
pytest
ruff check . && ruff format --check .
```

Needs a Postgres with the `vector` extension available (the `pgvector/pgvector`
image the compose stack uses; a plain local Postgres won't have it installed).

`tests/conftest.py` repoints `OWL_API_DATABASE_URL` at a `*_test`-suffixed
database before anything else imports, so `pytest` never touches — or gets
confused by — whatever real scholarships are sitting in the dev database. That
database needs to exist first: `CREATE DATABASE owl_api_test;` (already wired
into `docker/postgres/initdb/10-databases.sql` for a fresh compose volume).
`tests/test_agent_retrieval.py` fakes `embed_query` / `get_chat_model` so the
real pgvector query still runs, without an API key or a network call.

## API (Phase 1)

Both endpoints require a valid RS256 JWT from owl-admin (`aud: owl-api`) —
see `app/security.py`.

| Route | Purpose |
| --- | --- |
| `GET /health` | `{ status, database }`. |
| `POST /v1/scholarships/ingest` | Upsert by `content_hash`: chunk `body_markdown`, embed each chunk with OpenAI, store the vectors in pgvector. 503 if `OPENAI_API_KEY` isn't set. |
| `POST /v1/agent/respond` | Embed the question, retrieve the 5 nearest chunks by cosine distance, answer grounded in them with citations. Returns a graceful canned message (no OpenAI call) if there's no key or no scholarships yet. |

The system prompt asks for plain text (no Markdown) since owl-web renders
`message` as-is — the model mostly complies but not perfectly (occasional
stray `**bold**`). Real Markdown rendering on the frontend is the sturdier
fix, whenever that's worth doing.

## Layout

| Path | Purpose |
| --- | --- |
| `app/main.py` | App factory, router wiring, startup (`CREATE EXTENSION vector`, table creation). |
| `app/config.py` | Env-driven settings (`pydantic-settings`). |
| `app/schemas.py` | Pydantic wire contracts shared with owl-admin. |
| `app/db_models.py` | SQLAlchemy ORM models: `Scholarship`, `ScholarshipChunk` (pgvector column). |
| `app/chunking.py` | Dependency-free paragraph-packing chunker. |
| `app/embeddings.py` / `app/llm.py` | `langchain-openai` wrappers for embeddings and chat. |
| `app/routers/scholarships.py` | `POST /v1/scholarships/ingest`. |
| `app/routers/agent.py` | `POST /v1/agent/respond`. |
| `app/security.py` | RS256 JWT verification against owl-admin's JWKS (cached 5 min). |

## Known Phase 1 shortcut

Tables are created with `Base.metadata.create_all()` at startup instead of real
migrations (see `app/db.py:create_tables`). Fine while there's one schema
change at a time; revisit with Alembic once that's no longer true.

## Roadmap

- **Phase 2** — `/v1/agent/respond` becomes an SSE stream; LangGraph Postgres
  checkpointer.
- **Phase 4** — LangGraph supervisor + per-scholarship expert agent; LangSmith
  eval suite.
