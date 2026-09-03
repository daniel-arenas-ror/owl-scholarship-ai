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

## Layout

| Path | Purpose |
| --- | --- |
| `app/main.py` | App factory, router wiring, startup (`CREATE EXTENSION vector`). |
| `app/config.py` | Env-driven settings (`pydantic-settings`). |
| `app/schemas.py` | Wire contracts shared with owl-admin. |
| `app/routers/health.py` | `GET /health`. |
| `app/routers/scholarships.py` | `POST /v1/scholarships/ingest` (stub). |
| `app/routers/agent.py` | `POST /v1/agent/respond` (stub). |
| `app/security.py` | Shared-secret guard; becomes JWT/JWKS in Phase 1. |

## Roadmap

- **Phase 1** — real ingest (chunk + embed + upsert into pgvector) and a single
  retrieval chain behind `/v1/agent/respond`; LangSmith tracing.
- **Phase 2** — `/v1/agent/respond` becomes an SSE stream.
- **Phase 4** — LangGraph supervisor + per-scholarship expert agent; eval suite.
