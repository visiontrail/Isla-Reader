from datetime import datetime, timezone
import hashlib
import hmac
from threading import Lock
from typing import Dict, Optional

from fastapi import HTTPException, status

from .config import Settings


class NonceStore:
    """Simple in-memory nonce store with TTL-based eviction to prevent replays."""

    def __init__(self, max_entries: int = 10_000):
        self._seen: Dict[str, int] = {}
        self._lock = Lock()
        self._max_entries = max_entries

    def _evict(self, cutoff: int) -> None:
        expired = [nonce for nonce, ts in self._seen.items() if ts < cutoff]
        for nonce in expired:
            self._seen.pop(nonce, None)

        if len(self._seen) <= self._max_entries:
            return

        # Drop oldest nonces to keep memory bounded
        overflow = len(self._seen) - self._max_entries
        for nonce, _ in sorted(self._seen.items(), key=lambda item: item[1])[:overflow]:
            self._seen.pop(nonce, None)

    def validate_and_store(self, nonce: str, timestamp: int, ttl_seconds: int) -> None:
        now_ts = int(datetime.now(timezone.utc).timestamp())
        cutoff = now_ts - ttl_seconds
        with self._lock:
            self._evict(cutoff)
            existing_ts = self._seen.get(nonce)
            if existing_ts is not None and existing_ts >= cutoff:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Nonce already used")

            self._seen[nonce] = timestamp


# Global nonce store shared across process to reject replays within TTL window.
_NONCE_STORE = NonceStore()


def verify_signed_request(
    *,
    client_id: str,
    nonce: str,
    timestamp: int,
    signature: str,
    settings: Settings,
    nonce_store: Optional[NonceStore] = None,
) -> None:
    if client_id != settings.client_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid client credentials")

    now = datetime.now(timezone.utc)
    request_time = datetime.fromtimestamp(timestamp, tz=timezone.utc)
    delta_seconds = abs((now - request_time).total_seconds())
    if delta_seconds > settings.request_ttl_seconds:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Request timestamp expired")

    payload = f"{client_id}.{nonce}.{timestamp}"
    expected_signature = hmac.new(
        settings.client_secret.encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(expected_signature, signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature")

    store = nonce_store or _NONCE_STORE
    store.validate_and_store(nonce, timestamp, settings.request_ttl_seconds)
