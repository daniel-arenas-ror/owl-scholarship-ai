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
| `POST /v1/agent/respond` | **SSE.** Runs one turn of `app/graph.py` and streams it: one `event: routing` (`{ route, scholarship_id, scholarship_title }` — which node took the turn), then `event: token` per chunk, then one `event: done` carrying `{ message, citations, agent, route, run_id, scholarship? }`. `run_id` is the LangSmith root-run id (owl-api sets it, owl-admin persists it for the trace link). `event: error` if something breaks mid-stream. owl-admin relays this stream on to the browser. |

Conversation memory lives in the graph's own Postgres checkpointer, keyed by
`thread_id` — the caller sends only the new `user_message` (plus an optional
`user_context`), not the history.

The system prompt asks for plain text (no Markdown) since owl-web renders
`message` as-is — the model mostly complies but not perfectly (occasional
stray `**bold**`). Real Markdown rendering on the frontend is the sturdier
fix, whenever that's worth doing.

## The graph (Phase 4)

```
START -> route ->  general_advisor    -> END
               \-> scholarship_expert -> END
```

`route` makes one temperature-0 LLM call through `.with_structured_output(RouteDecision)`
and tags the turn `general` or `expert`. For `expert` it also pulls out the
scholarship the user named and resolves it to a stored row (`ILIKE` on title /
provider, with a stop-worded token fallback); if nothing resolves it falls back
to `general`. A router failure never breaks the turn — it downgrades to
`general`.

- **`general_advisor`** — retrieve-then-stream over *all* scholarships
  (`search_scholarships`), same shape as Phase 2's single node.
- **`scholarship_expert`** — retrieval pinned to one `scholarship_id`
  (`get_scholarship_detail`), a specialised prompt, and `check_eligibility`
  hints folded in from the turn's `user_context`.

Both workers stream via `llm.stream(...)` accumulated with `+`. The SSE layer
(`app/routers/agent.py`) reads `stream_mode=["updates", "messages"]`: the `route`
node's state update becomes the `routing` frame, and token chunks are relayed
only from the two answer nodes (so the router's own LLM chunks never leak).

A `PostgresSaver` checkpointer (own pool, `init_graph()` / `close_graph()` in
`main.py`'s lifespan) still holds conversation state per `thread_id`. Adding a
third route later (e.g. a node that collects a user's profile and writes it to
the DB) is a new node plus one branch in `_pick_route`.

## Evals

`evals/golden.jsonl` is a hand-written set (question → expected route, expected
scholarship in the citations, `must_mention` substrings). `evals/run.py` runs
each case through the **real** graph — real router, real retrieval, real OpenAI
— against whatever is in your local `OWL_API_DATABASE_URL`, and scores route
accuracy, retrieval hit-rate, and the must-mention rate; `--judge` adds an
LLM groundedness spot-check, `--json` prints a machine-readable summary. It
exits non-zero below the thresholds in `run.py`, so it *can* gate a deploy
later.

```bash
make eval            # needs `make up` running + OPENAI_API_KEY + `make seed` data
```

Not in CI: CI has no key and no seeded data. This is the harness a LangSmith
dataset + `evaluate()` run replaces once there's an account and real transcripts
(Phase 5/6). `@traceable` hooks are already on the nodes and tools, so turning
on `LANGSMITH_TRACING` gives per-node spans with no further wiring.

## Layout

| Path | Purpose |
| --- | --- |
| `app/main.py` | App factory, router wiring, startup (`CREATE EXTENSION vector`, table creation, graph init). |
| `app/config.py` | Env-driven settings (`pydantic-settings`). |
| `app/schemas.py` | Pydantic wire contracts shared with owl-admin. |
| `app/db_models.py` | SQLAlchemy ORM models: `Scholarship`, `ScholarshipChunk` (pgvector column). |
| `app/chunking.py` | Dependency-free paragraph-packing chunker. |
| `app/embeddings.py` / `app/llm.py` | `langchain-openai` wrappers: embeddings, the worker chat model, the temperature-0 router model. |
| `app/graph.py` | The LangGraph router + two worker nodes + Postgres checkpointer (see above). |
| `app/tools.py` | `search_scholarships`, `get_scholarship_detail`, `check_eligibility` — `@traceable` functions the nodes call. |
| `app/routers/scholarships.py` | `POST /v1/scholarships/ingest`. |
| `app/routers/agent.py` | `POST /v1/agent/respond` — SSE framing (`routing` / `token` / `done`) around `app/graph.py`. |
| `app/security.py` | RS256 JWT verification against owl-admin's JWKS (cached 5 min). |
| `evals/` | `golden.jsonl` + `run.py` — the local eval suite (`make eval`). |

## Known Phase 1 shortcut

Tables are created with `Base.metadata.create_all()` at startup instead of real
migrations (see `app/db.py:create_tables`). Fine while there's one schema
change at a time; revisit with Alembic once that's no longer true. (The
checkpointer's own tables are separate — `PostgresSaver.setup()` in
`app/graph.py` manages those.)

## Roadmap

- **Phase 4 (done)** — router + `general_advisor` / `scholarship_expert` nodes,
  the three tools, `@traceable` hooks, and the local `make eval` suite.
- **Still on the Phase 4 list** — real LangSmith `evaluate()` + a dataset built
  from transcripts, and CI gating (waits on a LangSmith account and Phase 7).
- **Phase 5** — the admin dashboards; annotation view feeds the fine-tuning
  corpus.
