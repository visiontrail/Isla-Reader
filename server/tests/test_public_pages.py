import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


@pytest.fixture(autouse=True)
def _configure_test_env(monkeypatch: pytest.MonkeyPatch):
    env = {
        "ISLA_API_KEY": "sk-test",
        "ISLA_API_ENDPOINT": "https://example.com/v1",
        "ISLA_AI_MODEL": "gpt-test",
        "ISLA_CLIENT_ID": "ios-test-client",
        "ISLA_CLIENT_SECRET": "ios-test-secret",
        "ISLA_REQUIRE_HTTPS": "false",
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_app_ads_txt_returns_admob_verification_snippet():
    with TestClient(app) as client:
        response = client.get("/app-ads.txt")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert response.text.strip() == "google.com, pub-5587239366359667, DIRECT, f08c47fec0942fa0"
