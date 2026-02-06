import asyncio
import hashlib
import hmac
from datetime import datetime, timezone
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.routers import notion_oauth

TEST_CLIENT_ID = "ios-test-client"
TEST_CLIENT_SECRET = "ios-test-secret"


@pytest.fixture(autouse=True)
def _configure_test_env(monkeypatch: pytest.MonkeyPatch):
    env = {
        "ISLA_API_KEY": "sk-test",
        "ISLA_API_ENDPOINT": "https://example.com/v1",
        "ISLA_AI_MODEL": "gpt-test",
        "ISLA_CLIENT_ID": TEST_CLIENT_ID,
        "ISLA_CLIENT_SECRET": TEST_CLIENT_SECRET,
        "ISLA_REQUIRE_HTTPS": "false",
        "ISLA_REQUEST_TTL_SECONDS": "300",
        "NOTION_CLIENT_ID": "notion-client-id",
        "NOTION_CLIENT_SECRET": "notion-client-secret",
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _sign_payload(*, client_id: str, nonce: str, timestamp: int, secret: str) -> str:
    payload = f"{client_id}.{nonce}.{timestamp}"
    return hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()


def _build_payload(*, timestamp: int | None = None, signature: str | None = None) -> dict:
    ts = timestamp or int(datetime.now(timezone.utc).timestamp())
    nonce = f"nonce-{uuid4().hex}"
    signed = signature or _sign_payload(
        client_id=TEST_CLIENT_ID,
        nonce=nonce,
        timestamp=ts,
        secret=TEST_CLIENT_SECRET,
    )
    return {
        "client_id": TEST_CLIENT_ID,
        "nonce": nonce,
        "timestamp": ts,
        "signature": signed,
        "code": "test-oauth-code",
        "redirect_uri": "lanread://oauth/notion",
    }


def test_exchange_rejects_invalid_signature(monkeypatch: pytest.MonkeyPatch):
    async def _should_not_call_notion(**kwargs):
        pytest.fail(f"Notion endpoint should not be called, kwargs={kwargs}")

    monkeypatch.setattr(notion_oauth, "_exchange_code_with_notion", _should_not_call_notion)

    payload = _build_payload(signature="invalid-signature")
    with TestClient(app) as client:
        response = client.post("/v1/oauth/notion/exchange", json=payload)

    assert response.status_code == 401
    assert response.headers.get("cache-control") == "no-store"
    assert response.json() == {
        "error": "request_verification_failed",
        "error_description": "Invalid signature",
        "status_code": 401,
    }


def test_exchange_rejects_expired_timestamp(monkeypatch: pytest.MonkeyPatch):
    async def _should_not_call_notion(**kwargs):
        pytest.fail(f"Notion endpoint should not be called, kwargs={kwargs}")

    monkeypatch.setattr(notion_oauth, "_exchange_code_with_notion", _should_not_call_notion)

    expired_timestamp = int(datetime.now(timezone.utc).timestamp()) - 301
    payload = _build_payload(timestamp=expired_timestamp)

    with TestClient(app) as client:
        response = client.post("/v1/oauth/notion/exchange", json=payload)

    assert response.status_code == 401
    assert response.headers.get("cache-control") == "no-store"
    assert response.json() == {
        "error": "request_verification_failed",
        "error_description": "Request timestamp expired",
        "status_code": 401,
    }


def test_exchange_returns_notion_error_payload(monkeypatch: pytest.MonkeyPatch):
    async def _mock_notion_exchange(**kwargs):
        request = httpx.Request("POST", "https://api.notion.com/v1/oauth/token")
        return httpx.Response(
            status_code=400,
            json={"error": "invalid_grant", "error_description": "Authorization code is invalid"},
            request=request,
        )

    monkeypatch.setattr(notion_oauth, "_exchange_code_with_notion", _mock_notion_exchange)

    payload = _build_payload()
    with TestClient(app) as client:
        response = client.post("/v1/oauth/notion/exchange", json=payload)

    assert response.status_code == 400
    assert response.headers.get("cache-control") == "no-store"
    assert response.json() == {
        "error": "invalid_grant",
        "error_description": "Authorization code is invalid",
        "status_code": 400,
    }


def test_exchange_success_returns_access_token(monkeypatch: pytest.MonkeyPatch):
    async def _mock_notion_exchange(**kwargs):
        request = httpx.Request("POST", "https://api.notion.com/v1/oauth/token")
        return httpx.Response(
            status_code=200,
            json={
                "access_token": "secret-access-token",
                "workspace_id": "workspace-123",
                "workspace_name": "Workspace Name",
                "bot_id": "bot-123",
                "owner": {"type": "user", "user": {"id": "user-1"}},
            },
            request=request,
        )

    monkeypatch.setattr(notion_oauth, "_exchange_code_with_notion", _mock_notion_exchange)

    payload = _build_payload()
    with TestClient(app) as client:
        response = client.post("/v1/oauth/notion/exchange", json=payload)

    assert response.status_code == 200
    assert response.headers.get("cache-control") == "no-store"
    assert response.json() == {
        "access_token": "secret-access-token",
        "workspace_id": "workspace-123",
        "workspace_name": "Workspace Name",
        "bot_id": "bot-123",
        "notion_owner": {"type": "user", "user": {"id": "user-1"}},
    }


def test_exchange_with_notion_uses_http_basic_auth(monkeypatch: pytest.MonkeyPatch):
    captured: dict = {}

    async def _mock_post(self, url, json, headers, auth):
        captured["url"] = url
        captured["json"] = json
        captured["headers"] = headers
        captured["auth"] = auth
        request = httpx.Request("POST", url)
        return httpx.Response(status_code=200, json={"ok": True}, request=request)

    monkeypatch.setattr(httpx.AsyncClient, "post", _mock_post)

    asyncio.run(
        notion_oauth._exchange_code_with_notion(
            code="oauth-code",
            redirect_uri="lanread://oauth/notion",
            client_id="notion-client-id",
            client_secret="notion-client-secret",
            token_url="https://api.notion.com/v1/oauth/token",
        )
    )

    assert captured["url"] == "https://api.notion.com/v1/oauth/token"
    assert captured["auth"] == ("notion-client-id", "notion-client-secret")
    assert captured["json"]["grant_type"] == "authorization_code"
