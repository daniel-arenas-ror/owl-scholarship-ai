"""Auth helpers for owl-api.

Phase 0: a shared secret on the owl-admin -> owl-api path.
Phase 1: swap `require_internal_token` for RS256 JWT verification against
owl-admin's published JWKS (`OWL_ADMIN_JWKS_URL`).
"""

import secrets

from fastapi import Header, HTTPException, status

from app.config import get_settings


def require_internal_token(authorization: str = Header(default="")) -> None:
    expected = get_settings().owl_internal_token
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not secrets.compare_digest(token, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid internal token",
        )
