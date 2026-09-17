"""Calls owl-admin for the few things only it can do: persist a student's
profile (the `users` table) and send a conversation by email. The reverse
direction of OwlApiClient — authenticated with a shared secret rather than
JWT/JWKS, since it's two narrow internal endpoints, not a public API.
"""

import httpx

from app.config import get_settings

TIMEOUT_SECONDS = 10.0


class OwlAdminError(Exception):
    pass


def _headers() -> dict:
    return {"Authorization": f"Bearer {get_settings().owl_internal_secret}"}


def _url(path: str) -> str:
    return f"{get_settings().owl_admin_url}{path}"


def get_user_profile(user_id: str) -> dict:
    """{full_name, email, phone, degrees} — email is always the account email."""
    try:
        response = httpx.get(
            _url(f"/internal/users/{user_id}/profile"),
            headers=_headers(),
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPError as exc:
        raise OwlAdminError(str(exc)) from exc


def update_user_profile(
    user_id: str,
    *,
    full_name: str | None = None,
    phone: str | None = None,
    degrees: list[str] | None = None,
) -> dict:
    """Only non-None fields are sent, so a partial update never clobbers the rest."""
    payload = {
        k: v
        for k, v in {"full_name": full_name, "phone": phone, "degrees": degrees}.items()
        if v is not None
    }
    try:
        response = httpx.patch(
            _url(f"/internal/users/{user_id}/profile"),
            headers=_headers(),
            json=payload,
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPError as exc:
        raise OwlAdminError(str(exc)) from exc


def send_conversation_email(conversation_id: str) -> dict:
    """owl-admin renders + sends the mail itself from its own Message rows —
    the transcript never has to be serialized through owl-api."""
    try:
        response = httpx.post(
            _url(f"/internal/conversations/{conversation_id}/email"),
            headers=_headers(),
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPError as exc:
        raise OwlAdminError(str(exc)) from exc
