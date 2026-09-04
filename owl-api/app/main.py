import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.db import create_tables, ensure_pgvector
from app.routers import agent, health, scholarships

logger = logging.getLogger("owl_api")
logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    try:
        ensure_pgvector()
        create_tables()
        logger.info("pgvector ready, tables ensured")
    except Exception as exc:  # noqa: BLE001 - log and continue so /health can report it
        logger.warning("could not prepare the database: %s", exc)
    if settings.langsmith_tracing:
        logger.info("LangSmith tracing enabled for project %s", settings.langsmith_project)
    yield


app = FastAPI(title="owl-api", version="0.0.1", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in get_settings().owl_web_origins.split(",") if o.strip()],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(scholarships.router)
app.include_router(agent.router)


@app.get("/")
def root() -> dict:
    return {"service": "owl-api", "docs": "/docs"}
