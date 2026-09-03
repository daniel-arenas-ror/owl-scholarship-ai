from fastapi import APIRouter

from app.db import ping

router = APIRouter(tags=["meta"])


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "database": "up" if ping() else "down"}
