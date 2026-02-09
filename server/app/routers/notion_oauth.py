from __future__ import annotations

import re
from threading import Lock
from time import monotonic
from typing import Any, Dict, Optional
from urllib.parse import urlencode
from uuid import uuid4

import httpx
from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import JSONResponse, RedirectResponse
from pydantic import BaseModel, Field

from ..config import Settings, get_settings
from ..logging_utils import get_logger

router = APIRouter(tags=["notion"])
logger = get_logger("notion")

APP_SCHEME = "lanread://notion"
SESSION_TTL_SECONDS = 60
STATE_PATTERN = re.compile(r"^[A-Za-z0-9._~\-]{8,512}$")


class NotionFinalizeRequest(BaseModel):
    session_id: str = Field(..., min_length=1, max_length=128)


class NotionFinalizeError(BaseModel):
    error: str
    message: str


class EphemeralSessionCache:
    """Thread-safe in-memory cache for short-lived OAuth session handoff."""

    def __init__(self, max_entries: int = 10_000) -> None:
        self._store: Dict[str, tuple[float, Dict[str, Any]]] = {}
        self._lock = Lock()
        self._max_entries = max_entries

    def _evict_expired(self, now: float) -> None:
        expired_keys = [key for key, (expires_at, _) in self._store.items() if expires_at <= now]
        for key in expired_keys:
            self._store.pop(key, None)

        if len(self._store) <= self._max_entries:
            return

        overflow = len(self._store) - self._max_entries
        oldest_keys = sorted(self._store.items(), key=lambda item: item[1][0])[:overflow]
        for key, _ in oldest_keys:
            self._store.pop(key, None)

    def set(self, session_id: str, payload: Dict[str, Any], ttl_seconds: int) -> None:
        expires_at = monotonic() + ttl_seconds
        with self._lock:
            self._evict_expired(monotonic())
            self._store[session_id] = (expires_at, dict(payload))

    def pop(self, session_id: str) -> Optional[Dict[str, Any]]:
        now = monotonic()
        with self._lock:
            self._evict_expired(now)
            record = self._store.pop(session_id, None)
        if record is None:
            return None

        expires_at, payload = record
        if expires_at <= now:
            return None
        return payload

    def clear(self) -> None:
        with self._lock:
            self._store.clear()


class StateReplayGuard:
    """Minimal replay guard for OAuth state values."""

    def __init__(self, ttl_seconds: int = 600) -> None:
        self._ttl_seconds = ttl_seconds
        self._seen: Dict[str, float] = {}
        self._lock = Lock()

    def validate_and_mark(self, state: str) -> None:
        now = monotonic()
        cutoff = now - self._ttl_seconds
        with self._lock:
            expired = [key for key, seen_at in self._seen.items() if seen_at < cutoff]
            for key in expired:
                self._seen.pop(key, None)

            if state in self._seen:
                raise ValueError("state_replayed")
            self._seen[state] = now

    def clear(self) -> None:
        with self._lock:
            self._seen.clear()


_SESSION_CACHE = EphemeralSessionCache()
_STATE_GUARD = StateReplayGuard()


def _build_app_redirect(path: str, **query: str) -> str:
    filtered = {key: value for key, value in query.items() if value}
    if not filtered:
        return f"{APP_SCHEME}/{path}"
    return f"{APP_SCHEME}/{path}?{urlencode(filtered)}"


def _redirect_error(message: str, state: Optional[str] = None) -> RedirectResponse:
    safe_message = " ".join(message.split())[:180] or "Unknown error"
    location = _build_app_redirect("error", msg=safe_message, state=state or "")
    return RedirectResponse(
        url=location,
        status_code=status.HTTP_302_FOUND,
        headers={"Cache-Control": "no-store"},
    )


def _validate_state_or_raise(state: Optional[str]) -> str:
    normalized = (state or "").strip()
    if not normalized or not STATE_PATTERN.fullmatch(normalized):
        raise ValueError("invalid_state")
    _STATE_GUARD.validate_and_mark(normalized)
    return normalized


def _resolve_callback_uri(request: Request, settings: Settings) -> str:
    if settings.notion_redirect_uri:
        return settings.notion_redirect_uri.strip()

    forwarded_proto = request.headers.get("x-forwarded-proto", "").split(",")[0].strip()
    forwarded_host = request.headers.get("x-forwarded-host", "").split(",")[0].strip()
    proto = forwarded_proto or request.url.scheme
    host = forwarded_host or request.headers.get("host") or request.url.netloc
    return f"{proto}://{host}{request.url.path}"


async def _exchange_code_with_notion(
    *,
    code: str,
    redirect_uri: str,
    client_id: str,
    client_secret: str,
    token_url: str,
) -> httpx.Response:
    payload: Dict[str, str] = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
    }
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "IslaReader-Server/0.1",
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        return await client.post(token_url, json=payload, headers=headers, auth=(client_id, client_secret))


@router.get(
    "/notion/callback",
    status_code=status.HTTP_302_FOUND,
    summary="Handle Notion OAuth callback and redirect back to app",
)
async def notion_oauth_callback(
    request: Request,
    code: Optional[str] = Query(default=None),
    state: Optional[str] = Query(default=None),
    settings: Settings = Depends(get_settings),
) -> RedirectResponse:
    try:
        verified_state = _validate_state_or_raise(state)
    except ValueError as exc:
        logger.warning("Notion callback rejected: invalid state reason=%s", str(exc))
        return _redirect_error("Invalid OAuth state")

    if not code:
        logger.warning("Notion callback rejected: missing code state=%s", verified_state)
        return _redirect_error("Missing authorization code", verified_state)

    notion_client_id = settings.notion_client_id
    notion_client_secret = settings.notion_client_secret
    if not notion_client_id or not notion_client_secret:
        logger.error("Notion callback failed: missing client_id/client_secret in environment")
        return _redirect_error("Server OAuth configuration is incomplete", verified_state)

    try:
        notion_resp = await _exchange_code_with_notion(
            code=code,
            redirect_uri=_resolve_callback_uri(request, settings),
            client_id=notion_client_id,
            client_secret=notion_client_secret,
            token_url=settings.notion_token_url,
        )
    except httpx.RequestError as exc:
        logger.error("Notion token request failed (network): %s", exc)
        return _redirect_error("Failed to reach Notion API", verified_state)

    response_body: Dict[str, Any]
    try:
        response_body = notion_resp.json()
    except Exception:
        response_body = {}

    if notion_resp.status_code >= 400:
        error_msg = (
            str(response_body.get("error_description") or response_body.get("message") or response_body.get("error"))
            if response_body
            else f"HTTP {notion_resp.status_code}"
        )
        logger.warning(
            "Notion token exchange failed status=%s error=%s",
            notion_resp.status_code,
            error_msg,
        )
        return _redirect_error(f"Notion OAuth failed: {error_msg}", verified_state)

    if not isinstance(response_body, dict):
        logger.error("Notion token response had unexpected payload type=%s", type(response_body).__name__)
        return _redirect_error("Invalid response from Notion", verified_state)

    access_token = response_body.get("access_token")
    if not isinstance(access_token, str) or not access_token.strip():
        logger.error("Notion token response missing access_token status=%s", notion_resp.status_code)
        return _redirect_error("Notion response missing access_token", verified_state)

    session_id = str(uuid4())
    _SESSION_CACHE.set(session_id, response_body, SESSION_TTL_SECONDS)
    logger.info(
        "Notion OAuth callback succeeded workspace_id=%s workspace_name=%s bot_id=%s session_ttl=%ss",
        response_body.get("workspace_id"),
        response_body.get("workspace_name"),
        response_body.get("bot_id"),
        SESSION_TTL_SECONDS,
    )

    redirect_url = _build_app_redirect("finish", session=session_id, state=verified_state)
    return RedirectResponse(
        url=redirect_url,
        status_code=status.HTTP_302_FOUND,
        headers={"Cache-Control": "no-store"},
    )


@router.post(
    "/v1/oauth/finalize",
    responses={400: {"model": NotionFinalizeError}},
    summary="Finalize OAuth and fetch one-time Notion token payload",
)
async def finalize_notion_oauth(payload: NotionFinalizeRequest) -> JSONResponse:
    session_id = payload.session_id.strip()
    if not session_id:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "invalid_session", "message": "session_id is required"},
            headers={"Cache-Control": "no-store"},
        )

    token_payload = _SESSION_CACHE.pop(session_id)
    if token_payload is None:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "session_expired", "message": "Session not found or expired"},
            headers={"Cache-Control": "no-store"},
        )

    return JSONResponse(
        status_code=status.HTTP_200_OK,
        content=token_payload,
        headers={"Cache-Control": "no-store"},
    )
