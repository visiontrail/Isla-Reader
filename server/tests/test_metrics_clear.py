from pathlib import Path
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.metrics_store import get_metrics_store


@pytest.fixture(autouse=True)
def _configure_test_env(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    metrics_file = tmp_path / "metrics.jsonl"
    env = {
        "ISLA_API_KEY": "sk-test",
        "ISLA_API_ENDPOINT": "https://example.com/v1",
        "ISLA_AI_MODEL": "gpt-test",
        "ISLA_CLIENT_ID": "ios-test-client",
        "ISLA_CLIENT_SECRET": "ios-test-secret",
        "ISLA_METRICS_INGEST_TOKEN": "ios-test-secret",
        "ISLA_REQUIRE_HTTPS": "false",
        "ISLA_DASHBOARD_USERNAME": "admin",
        "ISLA_DASHBOARD_PASSWORD": "test-password",
        "ISLA_METRICS_DATA_FILE": str(metrics_file),
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    get_settings.cache_clear()
    get_metrics_store.cache_clear()
    yield metrics_file
    get_metrics_store.cache_clear()
    get_settings.cache_clear()


def _login(client: TestClient) -> None:
    response = client.post("/admin/metrics/login", json={"username": "admin", "password": "test-password"})
    assert response.status_code == 200


def test_metrics_clear_requires_login():
    with TestClient(app) as client:
        response = client.post("/admin/metrics/clear")

    assert response.status_code == 401
    assert response.json()["detail"] == "Not authenticated"


def test_metrics_clear_removes_retained_events_and_persisted_file(_configure_test_env):
    metrics_file: Path = _configure_test_env
    payload = {
        "interface": "start_reading",
        "status_code": 200,
        "latency_ms": 186.2,
        "request_bytes": 512,
        "source": "start_reading",
    }

    with TestClient(app) as client:
        _login(client)

        ingest_response = client.post("/v1/metrics", json=payload, headers={"x-metrics-key": "ios-test-secret"})
        assert ingest_response.status_code == 202

        before_clear = client.get("/admin/metrics/data", params={"granularity": "day"})
        assert before_clear.status_code == 200
        assert before_clear.json()["totals"]["count"] == 1
        before_meta = before_clear.json()["meta"]
        assert before_meta["windowTimezone"] == "UTC"
        assert datetime.fromisoformat(before_meta["windowStart"]) < datetime.fromisoformat(before_meta["windowEnd"])

        clear_response = client.post("/admin/metrics/clear")
        assert clear_response.status_code == 200
        assert clear_response.json() == {"ok": True, "cleared": 1, "retained": 0}

        after_clear = client.get("/admin/metrics/data", params={"granularity": "day"})
        assert after_clear.status_code == 200
        assert after_clear.json()["totals"]["count"] == 0
        assert after_clear.json()["meta"]["retained"] == 0
        assert "windowStart" in after_clear.json()["meta"]
        assert "windowEnd" in after_clear.json()["meta"]

    assert metrics_file.exists()
    assert metrics_file.read_text(encoding="utf-8") == ""
