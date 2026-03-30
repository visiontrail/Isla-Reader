from pathlib import Path
from datetime import datetime, timedelta, timezone

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


def test_usage_counters_are_reported_by_mode_without_affecting_api_totals():
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
                "interface": "reader.summary_open",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "reader",
            },
        )
        _ingest(
            client,
            {
                "interface": "reader.skimming_chapter_open",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "reader",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_probe.summary",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 88,
                "source": "ai_knowledge",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_probe.skimming",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 90,
                "source": "ai_knowledge",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_hit.summary",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "ai_knowledge",
            },
        )
        _ingest(
            client,
            {
                "interface": "ai.knowledge_hit.skimming",
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
        assert totals["serverApiCallCount"] == 0
        assert totals["aiModelCallCount"] == 1
        assert totals["totalTokens"] == 210
        assert totals["readerBookOpenCount"] == 1
        assert totals["readerChapterOpenCount"] == 2
        assert totals["readerSummaryOpenCount"] == 1
        assert totals["readerSkimmingChapterOpenCount"] == 1
        assert totals["readerOpenTotalCount"] == 5
        assert totals["aiKnowledgeProbeCount"] == 2
        assert totals["aiKnowledgeHitCount"] == 2
        assert totals["aiKnowledgeHitRate"] == 1.0
        assert totals["aiSummaryKnowledgeProbeCount"] == 1
        assert totals["aiSummaryKnowledgeHitCount"] == 1
        assert totals["aiSummaryKnowledgeHitRate"] == 1.0
        assert totals["aiSkimmingKnowledgeProbeCount"] == 1
        assert totals["aiSkimmingKnowledgeHitCount"] == 1
        assert totals["aiSkimmingKnowledgeHitRate"] == 1.0

        assert len(payload["interfaces"]) == 1
        assert payload["interfaces"][0]["name"] == "/chat/completions"
        assert len(payload["sources"]) == 1
        assert payload["sources"][0]["name"] == "start_reading"


def test_legacy_knowledge_interfaces_are_still_counted_as_summary():
    with TestClient(app) as client:
        _login(client)

        _ingest(
            client,
            {
                "interface": "ai.knowledge_probe",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 42,
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
        totals = response.json()["totals"]

        assert totals["aiKnowledgeProbeCount"] == 1
        assert totals["aiKnowledgeHitCount"] == 1
        assert totals["aiSummaryKnowledgeProbeCount"] == 1
        assert totals["aiSummaryKnowledgeHitCount"] == 1
        assert totals["aiSkimmingKnowledgeProbeCount"] == 0
        assert totals["aiSkimmingKnowledgeHitCount"] == 0
        assert totals["serverApiCallCount"] == 0
        assert totals["aiModelCallCount"] == 0


def test_server_api_and_ai_model_calls_are_counted_separately():
    with TestClient(app) as client:
        _login(client)

        _ingest(
            client,
            {
                "interface": "/v1/keys/ai",
                "status_code": 200,
                "latency_ms": 21.0,
                "request_bytes": 128,
                "source": "secure_config",
            },
        )
        _ingest(
            client,
            {
                "interface": "/chat/completions",
                "status_code": 200,
                "latency_ms": 112.0,
                "request_bytes": 256,
                "source": "start_reading",
            },
        )

        response = client.get("/admin/metrics/data", params={"granularity": "day"})
        assert response.status_code == 200
        totals = response.json()["totals"]

        assert totals["windowCount"] == 2
        assert totals["serverApiCallCount"] == 1
        assert totals["aiModelCallCount"] == 1


def test_ads_calls_are_excluded_from_total_calls_and_reported_separately():
    with TestClient(app) as client:
        _login(client)

        _ingest(
            client,
            {
                "interface": "/v1/keys/ai",
                "status_code": 200,
                "latency_ms": 25.0,
                "request_bytes": 128,
                "source": "secure_config",
            },
        )
        _ingest(
            client,
            {
                "interface": "admob_banner_load",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "ads",
            },
        )
        _ingest(
            client,
            {
                "interface": "admob_interstitial_load",
                "status_code": 500,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "ads",
            },
        )
        _ingest(
            client,
            {
                "interface": "admob_rewarded_interstitial_load",
                "status_code": 200,
                "latency_ms": 0,
                "request_bytes": 0,
                "source": "ads",
            },
        )

        response = client.get("/admin/metrics/data", params={"granularity": "day"})
        assert response.status_code == 200
        payload = response.json()
        totals = payload["totals"]

        assert totals["windowCount"] == 1
        assert totals["serverApiCallCount"] == 1
        assert totals["aiModelCallCount"] == 0
        assert totals["adsCallCount"] == 3
        assert totals["adsSuccessCount"] == 2
        assert totals["adsFailureCount"] == 1

        ads_by_placement = {row["name"]: row for row in totals["adsByPlacement"]}
        assert ads_by_placement["admob_banner_load"]["success"] == 1
        assert ads_by_placement["admob_banner_load"]["failure"] == 0
        assert ads_by_placement["admob_interstitial_load"]["success"] == 0
        assert ads_by_placement["admob_interstitial_load"]["failure"] == 1
        assert ads_by_placement["admob_rewarded_interstitial_load"]["success"] == 1
        assert ads_by_placement["admob_rewarded_interstitial_load"]["failure"] == 0


def test_granularity_window_uses_expected_day_week_month_starts():
    with TestClient(app) as client:
        _login(client)

        _ingest(
            client,
            {
                "interface": "/v1/keys/ai",
                "status_code": 200,
                "latency_ms": 18.0,
                "request_bytes": 64,
                "source": "secure_config",
            },
        )

        for granularity in ("day", "week", "month"):
            response = client.get("/admin/metrics/data", params={"granularity": granularity})
            assert response.status_code == 200
            meta = response.json()["meta"]

            window_end = datetime.fromisoformat(meta["windowEnd"]).astimezone(timezone.utc)
            window_start = datetime.fromisoformat(meta["windowStart"]).astimezone(timezone.utc)

            day_start = window_end.replace(hour=0, minute=0, second=0, microsecond=0)
            if granularity == "day":
                expected_start = day_start
            elif granularity == "week":
                expected_start = day_start - timedelta(days=6)
            else:
                expected_start = day_start.replace(day=1)

            assert window_start == expected_start


def test_granularity_window_respects_client_timezone_offset():
    with TestClient(app) as client:
        _login(client)

        _ingest(
            client,
            {
                "interface": "/v1/keys/ai",
                "status_code": 200,
                "latency_ms": 15.0,
                "request_bytes": 64,
                "source": "secure_config",
            },
        )

        response = client.get("/admin/metrics/data", params={"granularity": "day", "tz_offset_minutes": -480})
        assert response.status_code == 200
        meta = response.json()["meta"]

        window_end = datetime.fromisoformat(meta["windowEnd"]).astimezone(timezone.utc)
        window_start = datetime.fromisoformat(meta["windowStart"]).astimezone(timezone.utc)
        local_tz = timezone(timedelta(hours=8))
        local_day_start = window_end.astimezone(local_tz).replace(hour=0, minute=0, second=0, microsecond=0)

        assert window_start == local_day_start.astimezone(timezone.utc)
        assert meta["windowTimezone"] == "UTC+08:00"
