from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.update_policy_store import get_update_policy_store


@pytest.fixture(autouse=True)
def _configure_test_env(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    update_policy_file = tmp_path / "update-policy.json"
    env = {
        "ISLA_API_KEY": "sk-test",
        "ISLA_API_ENDPOINT": "https://example.com/v1",
        "ISLA_AI_MODEL": "gpt-test",
        "ISLA_CLIENT_ID": "ios-test-client",
        "ISLA_CLIENT_SECRET": "ios-test-secret",
        "ISLA_REQUIRE_HTTPS": "false",
        "ISLA_DASHBOARD_USERNAME": "admin",
        "ISLA_DASHBOARD_PASSWORD": "test-password",
        "ISLA_UPDATE_POLICY_FILE": str(update_policy_file),
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    get_settings.cache_clear()
    get_update_policy_store.cache_clear()
    yield update_policy_file
    get_update_policy_store.cache_clear()
    get_settings.cache_clear()


def _login(client: TestClient) -> None:
    response = client.post("/admin/metrics/login", json={"username": "admin", "password": "test-password"})
    assert response.status_code == 200


def test_public_update_policy_returns_defaults():
    with TestClient(app) as client:
        response = client.get("/v1/app/update-policy", params={"platform": "ios"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["enabled"] is False
    assert payload["mode"] == "soft"
    assert payload["latest_version"] == ""
    assert payload["minimum_supported_version"] == ""
    assert payload["app_store_url"] == ""
    assert payload["remind_interval_hours"] == 24


def test_admin_update_policy_requires_login():
    with TestClient(app) as client:
        get_response = client.get("/admin/update-policy/config")
        put_response = client.put("/admin/update-policy/config", json={})

    assert get_response.status_code == 401
    assert put_response.status_code == 401


def test_admin_can_update_policy_and_public_endpoint_reflects_change(_configure_test_env):
    update_policy_file: Path = _configure_test_env
    payload = {
        "enabled": True,
        "mode": "hard",
        "latest_version": "1.1.0",
        "minimum_supported_version": "1.0.2",
        "title": "Please update",
        "message": "New build available.",
        "app_store_url": "itms-apps://itunes.apple.com/app/id1234567890",
        "remind_interval_hours": 12,
    }

    with TestClient(app) as client:
        _login(client)

        save_response = client.put("/admin/update-policy/config", json=payload)
        assert save_response.status_code == 200
        saved = save_response.json()
        assert saved["enabled"] is True
        assert saved["mode"] == "hard"
        assert saved["latest_version"] == "1.1.0"
        assert saved["minimum_supported_version"] == "1.0.2"
        assert saved["remind_interval_hours"] == 12

        public_response = client.get("/v1/app/update-policy", params={"platform": "ios", "current_version": "1.0.0"})
        assert public_response.status_code == 200
        public_payload = public_response.json()
        assert public_payload["enabled"] is True
        assert public_payload["mode"] == "hard"
        assert public_payload["latest_version"] == "1.1.0"
        assert public_payload["minimum_supported_version"] == "1.0.2"
        assert public_payload["app_store_url"] == "itms-apps://itunes.apple.com/app/id1234567890"

    assert update_policy_file.exists()
    text = update_policy_file.read_text(encoding="utf-8")
    assert '"latest_version":"1.1.0"' in text or '"latest_version": "1.1.0"' in text
