import asyncio
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.routers import notion_oauth


@pytest.fixture(autouse=True)
def _configure_test_env(monkeypatch: pytest.MonkeyPatch):
    env = {
        "ISLA_API_KEY": "sk-test",
        "ISLA_API_ENDPOINT": "https://example.com/v1",
        "ISLA_AI_MODEL": "gpt-test",
        "ISLA_CLIENT_ID": "ios-test-client",
        "ISLA_CLIENT_SECRET": "ios-test-secret",
        "ISLA_REQUIRE_HTTPS": "false",
        "NOTION_CLIENT_ID": "notion-client-id",
        "NOTION_CLIENT_SECRET": "notion-client-secret",
        "NOTION_REDIRECT_URI": "https://example.com/notion/callback",
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    get_settings.cache_clear()
    notion_oauth._SESSION_CACHE.clear()
    notion_oauth._STATE_GUARD.clear()
    yield
    notion_oauth._SESSION_CACHE.clear()
    notion_oauth._STATE_GUARD.clear()
    get_settings.cache_clear()


def test_callback_rejects_invalid_state():
    with TestClient(app) as client:
        response = client.get(
            "/notion/callback",
            params={"code": "oauth-code", "state": "bad state"},
            follow_redirects=False,
        )

    assert response.status_code == 302
    assert response.headers.get("cache-control") == "no-store"
    location = response.headers["location"]
    parsed = urlparse(location)
    query = parse_qs(parsed.query)

    assert parsed.scheme == "lanread"
    assert parsed.netloc == "notion"
    assert parsed.path == "/error"
    assert "msg" in query


def test_callback_redirects_error_when_notion_rejects_code(monkeypatch: pytest.MonkeyPatch):
    async def _mock_notion_exchange(**kwargs):
        request = httpx.Request("POST", "https://api.notion.com/v1/oauth/token")
        return httpx.Response(
            status_code=400,
            json={"error": "invalid_grant", "error_description": "Authorization code is invalid"},
            request=request,
        )

    monkeypatch.setattr(notion_oauth, "_exchange_code_with_notion", _mock_notion_exchange)
    with TestClient(app) as client:
        response = client.get(
            "/notion/callback",
            params={"code": "oauth-code", "state": "stateAbc123XYZ"},
            follow_redirects=False,
        )

    assert response.status_code == 302
    assert response.headers.get("cache-control") == "no-store"
    location = response.headers["location"]
    parsed = urlparse(location)
    query = parse_qs(parsed.query)
    assert parsed.path == "/error"
    assert "Notion OAuth failed" in query["msg"][0]


def test_callback_success_and_finalize_is_one_time(monkeypatch: pytest.MonkeyPatch):
    notion_payload = {
        "access_token": "secret-access-token",
        "workspace_id": "workspace-123",
        "workspace_name": "Workspace Name",
        "workspace_icon": "https://example.com/icon.png",
        "bot_id": "bot-123",
        "owner": {"type": "user", "user": {"id": "user-1"}},
    }

    async def _mock_notion_exchange(**kwargs):
        request = httpx.Request("POST", "https://api.notion.com/v1/oauth/token")
        return httpx.Response(status_code=200, json=notion_payload, request=request)

    monkeypatch.setattr(notion_oauth, "_exchange_code_with_notion", _mock_notion_exchange)
    with TestClient(app) as client:
        callback_response = client.get(
            "/notion/callback",
            params={"code": "oauth-code", "state": "stateAbc123XYZ"},
            follow_redirects=False,
        )

        assert callback_response.status_code == 302
        assert callback_response.headers.get("cache-control") == "no-store"

        callback_location = callback_response.headers["location"]
        parsed = urlparse(callback_location)
        query = parse_qs(parsed.query)
        session_id = query["session"][0]
        returned_state = query["state"][0]

        assert parsed.scheme == "lanread"
        assert parsed.netloc == "notion"
        assert parsed.path == "/finish"
        assert returned_state == "stateAbc123XYZ"
        assert session_id

        finalize_response = client.post("/v1/oauth/finalize", json={"session_id": session_id})
        assert finalize_response.status_code == 200
        assert finalize_response.headers.get("cache-control") == "no-store"
        assert finalize_response.json() == notion_payload

        reused_response = client.post("/v1/oauth/finalize", json={"session_id": session_id})
        assert reused_response.status_code == 400
        assert reused_response.json()["error"] == "session_expired"


def test_finalize_rejects_expired_or_missing_session():
    notion_oauth._SESSION_CACHE.set(
        "session-expired",
        {"access_token": "tmp"},
        ttl_seconds=0,
    )
    with TestClient(app) as client:
        expired = client.post("/v1/oauth/finalize", json={"session_id": "session-expired"})
        missing = client.post("/v1/oauth/finalize", json={"session_id": "missing-session"})

    assert expired.status_code == 400
    assert expired.json()["error"] == "session_expired"
    assert missing.status_code == 400
    assert missing.json()["error"] == "session_expired"


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
            redirect_uri="https://example.com/notion/callback",
            client_id="notion-client-id",
            client_secret="notion-client-secret",
            token_url="https://api.notion.com/v1/oauth/token",
        )
    )

    assert captured["url"] == "https://api.notion.com/v1/oauth/token"
    assert captured["auth"] == ("notion-client-id", "notion-client-secret")
    assert captured["json"]["grant_type"] == "authorization_code"
