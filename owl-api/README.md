# owl-api

Python + FastAPI. Retrieval, the LangGraph graph, LangSmith tracing, and every
OpenAI call.

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

## API

owl-admin is the only client — no browser ever calls owl-api, so there's no
CORS, and the one trust boundary is a valid RS256 JWT from owl-admin
(`aud: owl-api`), verified in `app/security.py`.

| Route | Purpose |
| --- | --- |
| `GET /health` | `{ status, database }`. |
| `POST /v1/scholarships/ingest` | Upsert by `content_hash`: chunk `body_markdown`, embed each chunk with OpenAI, store the vectors in pgvector. 503 if `OPENAI_API_KEY` isn't set. |
| `POST /v1/agent/respond` | **SSE.** Runs one turn of `app/graph.py` and streams it: `event: token` per chunk, then one `event: done` carrying `{ message, citations, agent }`. `event: error` if something breaks mid-stream. owl-admin relays this stream on to the browser. |

Conversation memory lives in the graph's own Postgres checkpointer, keyed by
`thread_id` — the caller sends only the new `user_message`, not the history.

The system prompt asks for plain text (no Markdown) since owl-web renders
`message` as-is — the model mostly complies but not perfectly (occasional
stray `**bold**`). Real Markdown rendering on the frontend is the sturdier
fix, whenever that's worth doing.

## The graph (Phase 2)

`app/graph.py` is a single-node LangGraph graph: `answer_node` does the same
retrieve-then-generate work Phase 1 did inline, except the LLM call is
`llm.stream(...)` (accumulated with `+`) instead of `.invoke(...)`, so tokens
escape via `graph.stream(..., stream_mode="messages")` as they're generated.
A `PostgresSaver` checkpointer (own connection pool, `init_graph()`/
`close_graph()` in `main.py`'s lifespan) persists conversation state per
`thread_id` — Phase 4 adds a router and more nodes to this same graph rather
than replacing it.

## Layout

| Path | Purpose |
| --- | --- |
| `app/main.py` | App factory, router wiring, startup (`CREATE EXTENSION vector`, table creation, graph init). |
| `app/config.py` | Env-driven settings (`pydantic-settings`). |
| `app/schemas.py` | Pydantic wire contracts shared with owl-admin. |
| `app/db_models.py` | SQLAlchemy ORM models: `Scholarship`, `ScholarshipChunk` (pgvector column). |
| `app/chunking.py` | Dependency-free paragraph-packing chunker. |
| `app/embeddings.py` / `app/llm.py` | `langchain-openai` wrappers for embeddings and chat. |
| `app/graph.py` | The LangGraph graph + Postgres checkpointer (see above). |
| `app/routers/scholarships.py` | `POST /v1/scholarships/ingest`. |
| `app/routers/agent.py` | `POST /v1/agent/respond` — SSE framing around `app/graph.py`. |
| `app/security.py` | RS256 JWT verification against owl-admin's JWKS (cached 5 min). |

## Known Phase 1 shortcut

Tables are created with `Base.metadata.create_all()` at startup instead of real
migrations (see `app/db.py:create_tables`). Fine while there's one schema
change at a time; revisit with Alembic once that's no longer true. (The
checkpointer's own tables are separate — `PostgresSaver.setup()` in
`app/graph.py` manages those.)

## Roadmap

- **Phase 4** — a supervisor node + per-scholarship expert agent added to the
  same graph; LangSmith eval suite.
