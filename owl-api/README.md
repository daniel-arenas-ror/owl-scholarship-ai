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
| `POST /v1/scholarships/ingest` | Upsert a scholarship: chunk `body_markdown`, embed each chunk with OpenAI, store the vectors in pgvector. Dedupes on `content_hash` — computed from the wire fields when the caller omits it, so any edited field re-triggers a re-embed. 503 if `OPENAI_API_KEY` isn't set. |
| `POST /v1/agent/respond` | **SSE.** Runs one turn of `app/graph.py` and streams it: one `event: routing` (`{ route, scholarship_id, scholarship_title }` — which node took the turn), then `event: token` per chunk (skipped entirely for `profile` / `email`, which never call an answer model), then one `event: done` carrying `{ message, citations, agent, route, run_id, system_prompt, model_variant, scholarship? }`. `run_id` is the LangSmith root-run id; `system_prompt` / `model_variant` are what owl-admin persists for the Phase 6 fine-tuning corpus. `event: error` if something breaks mid-stream. Requires `user_id` (owl-admin's user id, as a string) alongside `conversation_id` — the `profile` / `email` nodes and the `InMemoryStore` hydration key off it. owl-admin relays this stream on to the browser. |

Conversation memory lives in the graph's own Postgres checkpointer, keyed by
`thread_id` — the caller sends only the new `user_message` (plus an optional
`user_context`), not the history. A student's *profile* (name, degrees) is
separate: it's cross-conversation, keyed by `user_id` instead of `thread_id` —
see **Personalization** below.

The system prompt asks for plain text (no Markdown) since owl-web renders
`message` as-is — the model mostly complies but not perfectly (occasional
stray `**bold**`). Real Markdown rendering on the frontend is the sturdier
fix, whenever that's worth doing.

## The graph (Phase 4, extended with agent memory)

```
START -> route ->  general_advisor     -> END
               |-> scholarship_expert  -> END
               |-> profile_collector   -> END
               \-> email_sender        -> END
```

`route` makes one temperature-0 LLM call through `.with_structured_output(RouteDecision)`
and tags the turn `general`, `expert`, `profile` (the user shared or asked to
save personal info), or `email` (the user asked for the conversation by
email). For `expert` it also pulls out the scholarship the user named and
resolves it to a stored row (`ILIKE` on title / provider, with a stop-worded
token fallback); if nothing resolves it falls back to `general`. A router
failure never breaks the turn — it downgrades to `general`. Only a missing
`OPENAI_API_KEY` gates routing entirely; an empty scholarships table doesn't
block `profile` / `email` (each of `general_advisor` / `scholarship_expert`
checks that itself).

- **`general_advisor`** — retrieve-then-stream over *all* scholarships
  (`search_scholarships`), same shape as Phase 2's single node.
- **`scholarship_expert`** — retrieval pinned to one `scholarship_id`
  (`get_scholarship_detail`), a specialised prompt, and `check_eligibility`
  hints folded in from the turn's `user_context`.
- **`profile_collector`** — binds a closure-scoped `update_profile` tool
  (`full_name` / `phone` / `degrees`, `user_id` and the store captured so the
  model can never supply them) to the router model, executes whatever the
  model actually calls it with, and confirms in Spanish which fields it saved
  (or asks again if the turn had nothing new).
- **`email_sender`** — no LLM call at all: asks owl-admin to email the full
  transcript for `conversation_id` and returns a canned confirmation
  (or failure) message.

Both advisor nodes stream via `llm.stream(...)` accumulated with `+`. The SSE
layer (`app/routers/agent.py`) reads `stream_mode=["updates", "messages"]`: the
`route` node's state update becomes the `routing` frame, and token chunks are
relayed only from `general_advisor` / `scholarship_expert` (so the router's own
LLM chunks, and the tool-calling `profile_collector` turn, never leak as
tokens — `profile` / `email` turns arrive as a single `done` message instead).

A `PostgresSaver` checkpointer (own pool, `init_graph()` / `close_graph()` in
`main.py`'s lifespan) holds conversation state per `thread_id`.

### Personalization: `InMemoryStore`

A student's profile (`full_name`, `phone`, `degrees`) needs to outlive one
`thread_id` — the whole point is that a student doesn't have to repeat it in
their next conversation. `app/graph.py` compiles the graph with a
[`langgraph.store.memory.InMemoryStore`](https://langchain-ai.github.io/langgraph/reference/store/),
namespaced `("users", user_id)`, as a **read-through/write-through cache** in
front of owl-admin's `users` table (the durable copy):

- `_hydrate_profile(store, user_id)` — a cache hit returns instantly; a cold
  cache costs one `load_user_profile` round trip to owl-admin, then populates
  the store so nothing after that (any node, any `thread_id`, same process)
  re-fetches it.
- `_remember_profile(store, user_id, **updates)` — `profile_collector`'s write
  path: persist durably through `save_user_profile` (owl-admin), then merge
  into the cached value immediately, so the very next turn sees it with no
  re-fetch.
- `general_advisor` / `scholarship_expert` both fold `_format_stored_profile`
  into their system prompt, so a saved name/degrees can show up naturally in
  an *unrelated* scholarship-advice answer, in a brand new conversation.

It's in-process memory, not Postgres — a restart empties it, but correctness
never depends on that: a cold cache just costs one more owl-admin round trip,
same as never having cached anything. `init_graph()` and
`build_graph_without_checkpointer()` both compile with `store=InMemoryStore()`;
tests construct their own instance directly (`tests/test_agent_profile.py`).

### Calling owl-admin: `app/owl_admin_client.py`

The mirror image of owl-admin's `OwlApiClient` — owl-api calling *back* into
owl-admin, authenticated with a shared secret (`Authorization: Bearer
OWL_INTERNAL_SECRET`, checked on owl-admin's side with
`ActiveSupport::SecurityUtils.secure_compare`) rather than the RS256/JWKS
scheme owl-admin uses to call owl-api. Deliberately simpler: two narrow
internal endpoints, not a general-purpose trust boundary.

| Function | Calls |
| --- | --- |
| `get_user_profile(user_id)` | `GET /internal/users/:id/profile` |
| `update_user_profile(user_id, **fields)` | `PATCH /internal/users/:id/profile` (only non-`None` fields) |
| `send_conversation_email(conversation_id)` | `POST /internal/conversations/:id/email` |

All three wrap `httpx.HTTPError` (and connection failures) as `OwlAdminError`;
`app/tools.py:load_user_profile` swallows that into `{}` so a hiccup talking to
owl-admin degrades to "no known profile" instead of breaking the turn.

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

`python -m evals.run --model <id>` pins every answer turn to one model — run it
twice (base vs a fine-tuned id) for the Phase 6 comparison.

## Fine-tuning (Phase 6 scaffolding)

`scripts/finetune.py` is a manual CLI to `upload` a JSONL corpus (exported from
owl-admin), `create` an OpenAI SFT job, and poll `status` for the
`fine_tuned_model` id. `app/llm.py:pick_answer_model` then routes
`OWL_FINE_TUNED_TRAFFIC` (0.0–1.0) of answer turns to `OWL_FINE_TUNED_MODEL`; the
router always stays on the base model. The chosen `model_variant` rides the
`done` frame so owl-admin can persist it. Nothing runs on its own — see
[`docs/fine-tuning.md`](../docs/fine-tuning.md).

## Layout

| Path | Purpose |
| --- | --- |
| `app/main.py` | App factory, router wiring, startup (`CREATE EXTENSION vector`, table creation, graph init). |
| `app/config.py` | Env-driven settings (`pydantic-settings`). |
| `app/schemas.py` | Pydantic wire contracts shared with owl-admin. |
| `app/db_models.py` | SQLAlchemy ORM models: `Scholarship`, `ScholarshipChunk` (pgvector column). |
| `app/chunking.py` | Dependency-free paragraph-packing chunker. |
| `app/embeddings.py` / `app/llm.py` | `langchain-openai` wrappers: embeddings, the worker chat model, the temperature-0 router model. |
| `app/graph.py` | The LangGraph router + four worker nodes, the Postgres checkpointer, and the profile `InMemoryStore` (see above). |
| `app/tools.py` | `search_scholarships`, `get_scholarship_detail`, `check_eligibility`, `load_user_profile`, `save_user_profile`, `send_conversation_email` — `@traceable` functions the nodes call. |
| `app/owl_admin_client.py` | The reverse-direction HTTP client to owl-admin's `Internal::` endpoints (profile read/write, send-email), shared-secret auth. |
| `app/routers/scholarships.py` | `POST /v1/scholarships/ingest`. |
| `app/routers/agent.py` | `POST /v1/agent/respond` — SSE framing (`routing` / `token` / `done`) around `app/graph.py`. |
| `app/security.py` | RS256 JWT verification against owl-admin's JWKS (cached 5 min). |
| `evals/` | `golden.jsonl` + `run.py` — the local eval suite (`make eval`). |
| `scripts/finetune.py` | Manual CLI to upload a corpus + run an OpenAI SFT job (Phase 6). |

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
- **Phase 6 (scaffolding done)** — `system_prompt` / `model_variant` on the
  `done` frame, `pick_answer_model` A/B routing, `scripts/finetune.py`,
  `evals --model`. Waiting on real annotation data before a job runs; DPO not
  started.
- **Agent memory (done, cross-cutting)** — `profile_collector` (real
  tool-calling) and `email_sender` nodes, `app/owl_admin_client.py`, and an
  `InMemoryStore` profile cache shared by all four nodes. See owl-admin's
  README for the `Internal::` endpoints and the dev-only email inbox this
  feature calls into.
