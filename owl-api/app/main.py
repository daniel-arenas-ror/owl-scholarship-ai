import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.db import create_tables, ensure_pgvector
from app.graph import close_graph, init_graph
from app.routers import agent, health, scholarships

logger = logging.getLogger("owl_api")
logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    try:
        ensure_pgvector()
        create_tables()
        init_graph()
        logger.info("pgvector ready, tables ensured, graph checkpointer ready")
    except Exception as exc:  # noqa: BLE001 - log and continue so /health can report it
        logger.warning("could not prepare the database or graph: %s", exc)
    if settings.langsmith_tracing:
        logger.info("LangSmith tracing enabled for project %s", settings.langsmith_project)
    yield
    close_graph()


# No CORS middleware: owl-api is reached only by owl-admin (server-to-server),
# never by a browser. The one trust boundary is the RS256 JWT in app/security.py.
app = FastAPI(title="owl-api", version="0.0.1", lifespan=lifespan)

app.include_router(health.router)
app.include_router(scholarships.router)
app.include_router(agent.router)


@app.get("/")
def root() -> dict:
    return {"service": "owl-api", "docs": "/docs"}
