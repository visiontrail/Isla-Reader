from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional

from pydantic import BaseModel, Field
from .logging_utils import get_logger


class MetricEvent(BaseModel):
    interface: str
    status_code: int
    latency_ms: float
    request_bytes: int
    tokens: Optional[int] = None
    retry_count: int = 0
    source: str
    request_id: Optional[str] = None
    error_reason: Optional[str] = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    def to_public_dict(self) -> Dict[str, object]:
        return {
            "timestamp": self.timestamp.isoformat(),
            "interface": self.interface,
            "statusCode": self.status_code,
            "latencyMs": round(self.latency_ms, 2),
            "requestBytes": self.request_bytes,
            "tokens": self.tokens,
            "retryCount": self.retry_count,
            "source": self.source,
            "requestId": self.request_id,
            "errorReason": self.error_reason,
        }


class MetricsOverview(BaseModel):
    totals: Dict[str, object]
    interfaces: List[Dict[str, object]]
    sources: List[Dict[str, object]]
    timeline: List[Dict[str, object]]
    recent: List[Dict[str, object]]
    meta: Dict[str, object]


class MetricsStore:
    def __init__(self, path: Path, max_events: int = 5000) -> None:
        self.path = path
        self.max_events = max_events
        self._events: List[MetricEvent] = []
        self._logger = get_logger("metrics_store")
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            self._logger.info("Metrics file not found at %s; starting with empty store", self.path)
            return

        try:
            raw = self.path.read_text(encoding="utf-8").splitlines()
            for line in raw:
                if not line.strip():
                    continue
                event = MetricEvent.model_validate_json(line)
                self._events.append(event)
            self._logger.info("Loaded %s retained metrics events from %s", len(self._events), self.path)
        except Exception as exc:
            # Corrupted metric data should not prevent the service from starting.
            self._logger.error("Failed to load metrics from %s: %s", self.path, exc)
            self._events = []

    def _persist(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            content = "\n".join(event.model_dump_json() for event in self._events)
            self.path.write_text(content, encoding="utf-8")
        except Exception as exc:
            self._logger.error("Failed to persist metrics to %s: %s", self.path, exc)
            raise

    def add(self, event: MetricEvent) -> None:
        self._events.append(event)
        if len(self._events) > self.max_events:
            self._events = self._events[-self.max_events :]
        self._persist()
        self._logger.debug(
            "Added metric event interface=%s status=%s source=%s total=%s",
            event.interface,
            event.status_code,
            event.source,
            len(self._events),
        )

    def list_recent(self, limit: int = 30) -> List[MetricEvent]:
        return list(self._events[-limit:])

    def list_since(self, since: datetime) -> List[MetricEvent]:
        return [event for event in self._events if event.timestamp >= since]

    def overview(self) -> MetricsOverview:
        events = list(self._events)
        total = len(events)
        successes = sum(1 for e in events if 200 <= e.status_code < 300)
        avg_latency = sum(e.latency_ms for e in events) / total if total else 0.0
        total_tokens = sum(e.tokens or 0 for e in events)
        total_bytes = sum(e.request_bytes for e in events)

        now = datetime.now(timezone.utc)
        last_24h_cutoff = now - timedelta(hours=24)
        recent_cutoff = now - timedelta(days=7)
        rps_window = timedelta(minutes=5)
        rps_cutoff = now - rps_window
        last_24h = [e for e in events if e.timestamp >= last_24h_cutoff]
        recent_events = [e for e in events if e.timestamp >= recent_cutoff]
        rps_events = [e for e in events if e.timestamp >= rps_cutoff]
        rps = len(rps_events) / rps_window.total_seconds() if rps_events else 0.0

        interface_stats: Dict[str, Dict[str, object]] = {}
        for e in events:
            stats = interface_stats.setdefault(
                e.interface,
                {
                    "latencies": [],
                    "count": 0,
                    "failures": 0,
                    "sourceCounts": {},
                },
            )
            stats["latencies"].append(e.latency_ms)
            stats["count"] += 1
            if not (200 <= e.status_code < 300):
                stats["failures"] += 1
            source_counts: Dict[str, int] = stats["sourceCounts"]  # type: ignore[assignment]
            source_counts[e.source] = source_counts.get(e.source, 0) + 1
            stats["lastStatus"] = e.status_code

        interfaces: List[Dict[str, object]] = []
        for name, stats in interface_stats.items():
            latencies = sorted(stats["latencies"])  # type: ignore[index]
            p95 = latencies[int(len(latencies) * 0.95) - 1] if latencies else 0.0
            interfaces.append(
                {
                    "name": name,
                    "count": stats["count"],
                    "successRate": 1 - (stats["failures"] / stats["count"] if stats["count"] else 0),
                    "avgLatencyMs": sum(latencies) / len(latencies) if latencies else 0.0,
                    "p95LatencyMs": p95,
                    "errors": stats["failures"],
                    "sources": stats["sourceCounts"],
                    "lastStatus": stats.get("lastStatus", 0),
                }
            )

        source_stats: Dict[str, Dict[str, object]] = {}
        for e in events:
            stats = source_stats.setdefault(
                e.source,
                {
                    "count": 0,
                    "failures": 0,
                    "latencies": [],
                },
            )
            stats["count"] += 1
            stats["latencies"].append(e.latency_ms)
            if not (200 <= e.status_code < 300):
                stats["failures"] += 1

        sources: List[Dict[str, object]] = []
        for name, stats in source_stats.items():
            latencies = stats["latencies"]  # type: ignore[index]
            sources.append(
                {
                    "name": name,
                    "count": stats["count"],
                    "successRate": 1 - (stats["failures"] / stats["count"] if stats["count"] else 0),
                    "avgLatencyMs": sum(latencies) / len(latencies) if latencies else 0.0,
                }
            )

        timeline_buckets: Dict[str, Dict[str, int]] = {}
        for e in last_24h:
            bucket = e.timestamp.replace(minute=0, second=0, microsecond=0, tzinfo=timezone.utc)
            key = bucket.isoformat()
            entry = timeline_buckets.setdefault(key, {"count": 0, "failures": 0})
            entry["count"] += 1
            if not (200 <= e.status_code < 300):
                entry["failures"] += 1

        timeline = [
            {"bucket": key, "count": value["count"], "failures": value["failures"]}
            for key, value in sorted(timeline_buckets.items())
        ]

        recent = [event.to_public_dict() for event in reversed(recent_events)]

        return MetricsOverview(
            totals={
                "count": total,
                "successRate": (successes / total) if total else 0.0,
                "avgLatencyMs": round(avg_latency, 2),
                "totalTokens": total_tokens,
                "totalBytes": total_bytes,
                "last24h": len(last_24h),
                "rps": round(rps, 3),
            },
            interfaces=interfaces,
            sources=sources,
            timeline=timeline,
            recent=recent,
            meta={
                "retained": len(events),
                "maxRetained": self.max_events,
                "recentRangeHours": 24 * 7,
                "recentCount": len(recent_events),
                "rpsWindowSeconds": int(rps_window.total_seconds()),
            },
        )


@lru_cache
def get_metrics_store(path: str, max_events: int) -> MetricsStore:
    path_obj = Path(path)
    if not path_obj.is_absolute():
        path_obj = Path(__file__).resolve().parent / path_obj
    return MetricsStore(path=path_obj, max_events=max_events)
