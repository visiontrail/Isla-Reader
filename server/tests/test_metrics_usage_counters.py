from pathlib import Path

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
    yield
    get_metrics_store.cache_clear()
    get_settings.cache_clear()


def _login(client: TestClient) -> None:
    response = client.post("/admin/metrics/login", json={"username": "admin", "password": "test-password"})
    assert response.status_code == 200


def _ingest(client: TestClient, payload: dict) -> None:
    response = client.post("/v1/metrics", json=payload, headers={"x-metrics-key": "ios-test-secret"})
    assert response.status_code == 202


def test_usage_counters_are_reported_without_affecting_api_totals():
    with TestClient(app) as client:
        _login(client)

        _ingest(
            client,
            {
                "interface": "/chat/completions",
                "status_code": 200,
                "latency_ms": 120.0,
                "request_bytes": 420,
                "tokens": 210,
                "source": "start_reading",
            },
        )
        _ingest(
            client,
            {
                "interface": "reader.book_open",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "reader",
            },
        )
        _ingest(
            client,
            {
                "interface": "reader.chapter_open",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "reader",
            },
        )
        _ingest(
            client,
            {
                "interface": "reader.chapter_open",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "reader",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_probe",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 88,
                "source": "ai_knowledge",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_probe",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 90,
                "source": "ai_knowledge",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_hit",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "ai_knowledge",
            },
        )

        response = client.get("/admin/metrics/data", params={"granularity": "day"})
        assert response.status_code == 200
        payload = response.json()
        totals = payload["totals"]

        assert totals["count"] == 1
        assert totals["windowCount"] == 1
        assert totals["totalTokens"] == 210
        assert totals["readerBookOpenCount"] == 1
        assert totals["readerChapterOpenCount"] == 2
        assert totals["readerOpenTotalCount"] == 3
        assert totals["aiKnowledgeProbeCount"] == 2
        assert totals["aiKnowledgeHitCount"] == 1
        assert totals["aiKnowledgeHitRate"] == 0.5

        assert len(payload["interfaces"]) == 1
        assert payload["interfaces"][0]["name"] == "/chat/completions"
        assert len(payload["sources"]) == 1
        assert payload["sources"][0]["name"] == "start_reading"
