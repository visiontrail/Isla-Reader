from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from pydantic import BaseModel, Field
from .logging_utils import get_logger


DEFAULT_GRANULARITY = "day"
GRANULARITY_CONFIG: Dict[str, Dict[str, object]] = {
    "day": {
        "bucket": "hour",
        "label": "Today",
        "timeline_label": "Hourly buckets (today)",
    },
    "week": {
        "bucket": "day",
        "label": "This week",
        "timeline_label": "Daily buckets (this week)",
    },
    "month": {
        "bucket": "day",
        "label": "This month",
        "timeline_label": "Daily buckets (this month)",
    },
}

COUNTER_INTERFACES = {
    "reader.book_open",
    "reader.chapter_open",
    "reader.summary_open",
    "reader.skimming_chapter_open",
    "ai.knowledge_probe",
    "ai.knowledge_hit",
    "ai.knowledge_probe.summary",
    "ai.knowledge_hit.summary",
    "ai.knowledge_probe.skimming",
    "ai.knowledge_hit.skimming",
}

SUMMARY_PROBE_INTERFACES = {"ai.knowledge_probe", "ai.knowledge_probe.summary"}
SUMMARY_HIT_INTERFACES = {"ai.knowledge_hit", "ai.knowledge_hit.summary"}
SKIMMING_PROBE_INTERFACES = {"ai.knowledge_probe.skimming"}
SKIMMING_HIT_INTERFACES = {"ai.knowledge_hit.skimming"}
SERVER_API_INTERFACE_PREFIXES = ("/v1/", "/admin/")
AI_MODEL_INTERFACE_PATH = "/chat/completions"
AD_LOAD_INTERFACES = (
    "admob_banner_load",
    "admob_interstitial_load",
    "admob_rewarded_interstitial_load",
)


def _isoformat_seconds(ts: datetime) -> str:
    normalized = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    return normalized.astimezone(timezone.utc).isoformat(timespec="seconds")


def _resolve_granularity(name: Optional[str]) -> Tuple[str, Dict[str, object]]:
    key = (name or "").lower()
    if key not in GRANULARITY_CONFIG:
        key = DEFAULT_GRANULARITY
    return key, GRANULARITY_CONFIG[key]


def _bucket_start(ts: datetime, bucket: str) -> datetime:
    ts_utc = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    ts_utc = ts_utc.astimezone(timezone.utc)
    if bucket == "hour":
        return ts_utc.replace(minute=0, second=0, microsecond=0)
    return ts_utc.replace(hour=0, minute=0, second=0, microsecond=0)


def _timezone_from_offset_minutes(offset_minutes: Optional[int]) -> timezone:
    if offset_minutes is None:
        return timezone.utc
    clamped = max(-14 * 60, min(14 * 60, offset_minutes))
    return timezone(timedelta(minutes=-clamped))


def _timezone_label(tzinfo: timezone) -> str:
    offset = tzinfo.utcoffset(None) or timedelta(0)
    total_minutes = int(offset.total_seconds() // 60)
    if total_minutes == 0:
        return "UTC"
    sign = "+" if total_minutes > 0 else "-"
    abs_minutes = abs(total_minutes)
    hours = abs_minutes // 60
    minutes = abs_minutes % 60
    return f"UTC{sign}{hours:02d}:{minutes:02d}"


def _window_start(now: datetime, granularity: str) -> datetime:
    now_with_tz = now if now.tzinfo else now.replace(tzinfo=timezone.utc)
    day_start = now_with_tz.replace(hour=0, minute=0, second=0, microsecond=0)

    if granularity == "day":
        return day_start
    if granularity == "week":
        return day_start - timedelta(days=day_start.weekday())
    if granularity == "month":
        return day_start.replace(day=1)
    return day_start


def _is_counter_interface(interface: str) -> bool:
    return interface in COUNTER_INTERFACES


def _is_server_api_interface(interface: str) -> bool:
    return interface.startswith(SERVER_API_INTERFACE_PREFIXES)


def _is_ai_model_interface(interface: str) -> bool:
    return AI_MODEL_INTERFACE_PATH in interface


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

    def clear(self) -> int:
        cleared = len(self._events)
        self._events = []
        self._persist()
        self._logger.info("Cleared %s retained metrics events from %s", cleared, self.path)
        return cleared

    def list_recent(self, limit: int = 30) -> List[MetricEvent]:
        return list(self._events[-limit:])

    def list_since(self, since: datetime) -> List[MetricEvent]:
        return [event for event in self._events if event.timestamp >= since]

    def overview(self, granularity: str = DEFAULT_GRANULARITY, tz_offset_minutes: Optional[int] = None) -> MetricsOverview:
        events = list(self._events)
        granularity_key, granularity_config = _resolve_granularity(granularity)
        bucket = str(granularity_config["bucket"])
        window_label = granularity_config.get("label", "")
        timeline_label = granularity_config.get("timeline_label", "")

        window_tz = _timezone_from_offset_minutes(tz_offset_minutes)
        local_now = datetime.now(window_tz)
        now = local_now.astimezone(timezone.utc)
        window_start = _window_start(local_now, granularity_key).astimezone(timezone.utc)
        window_duration = max(now - window_start, timedelta(0))
        recent_cutoff = now - timedelta(days=7)
        rps_window = timedelta(minutes=5)
        rps_cutoff = now - rps_window

        window_events = [e for e in events if window_start <= e.timestamp <= now]
        recent_events = [e for e in events if recent_cutoff <= e.timestamp <= now]
        api_window_events = [e for e in window_events if not _is_counter_interface(e.interface)]
        ads_window_events = [e for e in api_window_events if e.source == "ads"]
        non_ads_api_window_events = [e for e in api_window_events if e.source != "ads"]
        rps_events = [e for e in non_ads_api_window_events if e.timestamp >= rps_cutoff]

        total = len(non_ads_api_window_events)
        server_api_call_count = sum(1 for e in non_ads_api_window_events if _is_server_api_interface(e.interface))
        ai_model_call_count = sum(1 for e in non_ads_api_window_events if _is_ai_model_interface(e.interface))
        successes = sum(1 for e in non_ads_api_window_events if 200 <= e.status_code < 300)
        avg_latency = sum(e.latency_ms for e in non_ads_api_window_events) / total if total else 0.0
        total_tokens = sum(e.tokens or 0 for e in non_ads_api_window_events)
        total_bytes = sum(e.request_bytes for e in non_ads_api_window_events)
        rps = len(rps_events) / rps_window.total_seconds() if rps_events else 0.0

        interface_stats: Dict[str, Dict[str, object]] = {}
        for e in non_ads_api_window_events:
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
        for e in non_ads_api_window_events:
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
        for e in non_ads_api_window_events:
            bucket_start = _bucket_start(e.timestamp, bucket)
            key = bucket_start.isoformat()
            entry = timeline_buckets.setdefault(key, {"count": 0, "failures": 0})
            entry["count"] += 1
            if not (200 <= e.status_code < 300):
                entry["failures"] += 1

        ad_type_stats: Dict[str, Dict[str, int]] = {
            name: {"success": 0, "failure": 0} for name in AD_LOAD_INTERFACES
        }
        for event in ads_window_events:
            placement_name = event.interface or "unknown"
            stats = ad_type_stats.setdefault(placement_name, {"success": 0, "failure": 0})
            if 200 <= event.status_code < 300:
                stats["success"] += 1
            else:
                stats["failure"] += 1

        ad_placement_priority = {name: index for index, name in enumerate(AD_LOAD_INTERFACES)}
        ad_placement_stats = [
            {
                "name": name,
                "success": stats["success"],
                "failure": stats["failure"],
                "count": stats["success"] + stats["failure"],
            }
            for name, stats in sorted(
                ad_type_stats.items(),
                key=lambda item: (ad_placement_priority.get(item[0], len(AD_LOAD_INTERFACES)), item[0]),
            )
        ]
        ad_success_count = sum(stats["success"] for stats in ad_type_stats.values())
        ad_failure_count = sum(stats["failure"] for stats in ad_type_stats.values())

        reader_book_open_count = sum(1 for e in window_events if e.interface == "reader.book_open")
        reader_chapter_open_count = sum(1 for e in window_events if e.interface == "reader.chapter_open")
        reader_summary_open_count = sum(1 for e in window_events if e.interface == "reader.summary_open")
        reader_skimming_chapter_open_count = sum(
            1 for e in window_events if e.interface == "reader.skimming_chapter_open"
        )
        ai_summary_probe_count = sum(1 for e in window_events if e.interface in SUMMARY_PROBE_INTERFACES)
        ai_summary_hit_count = sum(1 for e in window_events if e.interface in SUMMARY_HIT_INTERFACES)
        ai_skimming_probe_count = sum(1 for e in window_events if e.interface in SKIMMING_PROBE_INTERFACES)
        ai_skimming_hit_count = sum(1 for e in window_events if e.interface in SKIMMING_HIT_INTERFACES)
        ai_knowledge_probe_count = ai_summary_probe_count + ai_skimming_probe_count
        ai_knowledge_hit_count = ai_summary_hit_count + ai_skimming_hit_count

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
                "rps": round(rps, 3),
                "windowCount": total,
                "serverApiCallCount": server_api_call_count,
                "aiModelCallCount": ai_model_call_count,
                "adsCallCount": len(ads_window_events),
                "adsSuccessCount": ad_success_count,
                "adsFailureCount": ad_failure_count,
                "adsByPlacement": ad_placement_stats,
                "readerBookOpenCount": reader_book_open_count,
                "readerChapterOpenCount": reader_chapter_open_count,
                "readerSummaryOpenCount": reader_summary_open_count,
                "readerSkimmingChapterOpenCount": reader_skimming_chapter_open_count,
                "readerOpenTotalCount": (
                    reader_book_open_count
                    + reader_chapter_open_count
                    + reader_summary_open_count
                    + reader_skimming_chapter_open_count
                ),
                "aiKnowledgeProbeCount": ai_knowledge_probe_count,
                "aiKnowledgeHitCount": ai_knowledge_hit_count,
                "aiKnowledgeHitRate": (
                    ai_knowledge_hit_count / ai_knowledge_probe_count if ai_knowledge_probe_count else 0.0
                ),
                "aiSummaryKnowledgeProbeCount": ai_summary_probe_count,
                "aiSummaryKnowledgeHitCount": ai_summary_hit_count,
                "aiSummaryKnowledgeHitRate": (
                    ai_summary_hit_count / ai_summary_probe_count if ai_summary_probe_count else 0.0
                ),
                "aiSkimmingKnowledgeProbeCount": ai_skimming_probe_count,
                "aiSkimmingKnowledgeHitCount": ai_skimming_hit_count,
                "aiSkimmingKnowledgeHitRate": (
                    ai_skimming_hit_count / ai_skimming_probe_count if ai_skimming_probe_count else 0.0
                ),
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
                "granularity": granularity_key,
                "windowLabel": window_label,
                "windowStart": _isoformat_seconds(window_start),
                "windowEnd": _isoformat_seconds(now),
                "windowTimezone": _timezone_label(window_tz),
                "windowHours": int(window_duration.total_seconds() // 3600),
                "timelineBucket": bucket,
                "timelineLabel": timeline_label,
                "availableGranularities": list(GRANULARITY_CONFIG.keys()),
            },
        )

    def ad_load_summary(self, window_hours: int = 24 * 7) -> Dict[str, object]:
        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(hours=window_hours)
        events = [event for event in self._events if event.source == "ads" and event.timestamp >= cutoff]

        placements: Dict[str, Dict[str, object]] = {}
        for event in events:
            stats = placements.setdefault(
                event.interface,
                {"success": 0, "failure": 0, "failureReasons": {}},
            )
            success = 200 <= event.status_code < 300
            if success:
                stats["success"] = stats.get("success", 0) + 1
            else:
                stats["failure"] = stats.get("failure", 0) + 1
                reason = (event.error_reason or "unknown").strip() or "unknown"
                failure_reasons: Dict[str, int] = stats["failureReasons"]  # type: ignore[assignment]
                failure_reasons[reason] = failure_reasons.get(reason, 0) + 1

        total_success = sum(stats.get("success", 0) for stats in placements.values())
        total_failure = sum(stats.get("failure", 0) for stats in placements.values())

        recent_failures = [
            {
                "timestamp": event.timestamp.isoformat(),
                "placement": event.interface,
                "statusCode": event.status_code,
                "reason": event.error_reason,
            }
            for event in reversed(events)
            if not (200 <= event.status_code < 300)
        ][:50]

        placement_list = [
            {
                "placement": name,
                "success": stats.get("success", 0),
                "failure": stats.get("failure", 0),
                "successRate": (
                    stats["success"] / (stats["success"] + stats["failure"])
                    if (stats.get("success", 0) + stats.get("failure", 0))
                    else 0.0
                ),
                "failureReasons": stats.get("failureReasons", {}),
            }
            for name, stats in placements.items()
        ]

        return {
            "totals": {
                "success": total_success,
                "failure": total_failure,
                "successRate": (total_success / (total_success + total_failure)) if (total_success + total_failure) else 0.0,
            },
            "placements": placement_list,
            "recentFailures": recent_failures,
            "windowHours": window_hours,
            "eventCount": len(events),
            "retained": len(self._events),
        }


@lru_cache
def get_metrics_store(path: str, max_events: int) -> MetricsStore:
    path_obj = Path(path)
    if not path_obj.is_absolute():
        path_obj = Path(__file__).resolve().parent / path_obj
    return MetricsStore(path=path_obj, max_events=max_events)
