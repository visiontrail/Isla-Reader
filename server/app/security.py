from datetime import datetime, timezone
import hashlib
import hmac

from fastapi import HTTPException, status

from .config import Settings


def verify_signed_request(*, client_id: str, nonce: str, timestamp: int, signature: str, settings: Settings) -> None:
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
