"""Point every test run at a database named *_test, derived from whatever
OWL_API_DATABASE_URL already resolves to (dev default, docker-compose, or
CI's own value) — never the dev database. Must run before app.config /
app.db are imported, so this has to live in conftest.py, not a fixture.
"""

import os

_base = os.environ.get(
    "OWL_API_DATABASE_URL", "postgresql+psycopg://owl:owl@localhost:5432/owl_api"
)
_root, _, _db_name = _base.rpartition("/")
if not _db_name.endswith("_test"):
    os.environ["OWL_API_DATABASE_URL"] = f"{_root}/{_db_name}_test"

import pytest  # noqa: E402 - must follow the env-var patch above
from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture(scope="module")
def client():
    # The `with` form runs the app's lifespan (ensure_pgvector + create_tables)
    # before any test executes — plain TestClient(app) would skip it.
    with TestClient(app) as c:
        yield c
