"""Verifies the RS256 JWTs owl-admin issues (aud: owl-api), against the public
key it publishes at OWL_ADMIN_JWKS_URL. No secret is shared between the two
services — only the public key.
"""

import json
import time

import httpx
import jwt
from fastapi import Header, HTTPException, status
from jwt.algorithms import RSAAlgorithm

from app.config import get_settings

_JWKS_TTL_SECONDS = 300
_jwks_cache: dict = {"keys": [], "fetched_at": 0.0}


def _fetch_jwks(force: bool = False) -> list[dict]:
    now = time.time()
    if force or now - _jwks_cache["fetched_at"] > _JWKS_TTL_SECONDS or not _jwks_cache["keys"]:
        settings = get_settings()
        response = httpx.get(settings.owl_admin_jwks_url, timeout=5.0)
        response.raise_for_status()
        _jwks_cache["keys"] = response.json()["keys"]
        _jwks_cache["fetched_at"] = now
    return _jwks_cache["keys"]


def _public_key_for(kid: str):
    for force in (False, True):  # retry once in case the signing key rotated
        for key in _fetch_jwks(force=force):
            if key.get("kid") == kid:
                return RSAAlgorithm.from_jwk(json.dumps(key))
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unknown signing key")


def require_service_auth(authorization: str = Header(default="")) -> dict:
    """FastAPI dependency: verifies the bearer JWT and returns its claims."""
    settings = get_settings()
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="missing bearer token")

    try:
        header = jwt.get_unverified_header(token)
        key = _public_key_for(header["kid"])
        return jwt.decode(
            token,
            key=key,
            algorithms=["RS256"],
            audience=settings.owl_jwt_audience,
            issuer=settings.owl_jwt_issuer,
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=f"invalid token: {exc}"
        ) from exc
