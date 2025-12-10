from datetime import datetime, timezone

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from ..config import Settings, get_settings
from ..security import verify_signed_request

router = APIRouter(prefix="/v1", tags=["keys"])


class KeyRequest(BaseModel):
    client_id: str = Field(..., alias="client_id")
    nonce: str
    timestamp: int
    signature: str


class KeyResponse(BaseModel):
    api_key: str
    expires_in: int
    issued_at: datetime
    nonce: str


@router.post(
    "/keys/ai",
    response_model=KeyResponse,
    status_code=status.HTTP_200_OK,
    summary="Return AI API Key after verifying signed request",
)
async def issue_ai_key(payload: KeyRequest, settings: Settings = Depends(get_settings)) -> KeyResponse:
    verify_signed_request(
        client_id=payload.client_id,
        nonce=payload.nonce,
        timestamp=payload.timestamp,
        signature=payload.signature,
        settings=settings,
    )

    issued_at = datetime.now(timezone.utc)
    return KeyResponse(
        api_key=settings.api_key,
        expires_in=settings.request_ttl_seconds,
        issued_at=issued_at,
        nonce=payload.nonce,
    )
