from typing import Any, Dict, Optional

import httpx
from fastapi import APIRouter, Depends, Response, status, HTTPException
from pydantic import BaseModel, Field

from ..config import Settings, get_settings
from ..logging_utils import get_logger
from ..security import verify_signed_request

router = APIRouter(prefix="/v1/oauth/notion", tags=["notion"])
logger = get_logger("notion")


class NotionExchangeRequest(BaseModel):
    client_id: str = Field(..., alias="client_id")
    nonce: str
    timestamp: int
    signature: str
    code: str
    redirect_uri: str


class NotionExchangeResponse(BaseModel):
    access_token: str
    workspace_id: Optional[str] = None
    workspace_name: Optional[str] = None
    bot_id: Optional[str] = None
    notion_owner: Optional[Dict[str, Any]] = None


async def _exchange_code_with_notion(
    *,
    code: str,
    redirect_uri: str,
    client_id: str,
    client_secret: str,
    token_url: str,
) -> httpx.Response:
    payload = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
    }
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "IslaReader-Server/0.1",
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        return await client.post(token_url, json=payload, headers=headers, auth=(client_id, client_secret))


@router.post(
    "/exchange",
    response_model=NotionExchangeResponse,
    status_code=status.HTTP_200_OK,
    summary="Exchange Notion OAuth code for access token (server-side)",
)
async def exchange_notion_code(
    payload: NotionExchangeRequest,
    response: Response,
    settings: Settings = Depends(get_settings),
) -> NotionExchangeResponse | Dict[str, Any]:
    logger.info(
        "Notion exchange request received path=/v1/oauth/notion/exchange client_id=%s nonce=%s ts=%s",
        payload.client_id,
        payload.nonce,
        payload.timestamp,
    )
    try:
        verify_signed_request(
            client_id=payload.client_id,
            nonce=payload.nonce,
            timestamp=payload.timestamp,
            signature=payload.signature,
            settings=settings,
        )
    except HTTPException as exc:
        logger.warning(
            "Notion exchange rejected during verification status=%s detail=%s nonce=%s",
            exc.status_code,
            exc.detail,
            payload.nonce,
        )
        response.headers["Cache-Control"] = "no-store"
        raise

    notion_client_id = settings.notion_client_id or settings.client_id
    notion_client_secret = settings.notion_client_secret or settings.client_secret
    token_url = settings.notion_token_url

    try:
        notion_resp = await _exchange_code_with_notion(
            code=payload.code,
            redirect_uri=payload.redirect_uri,
            client_id=notion_client_id,
            client_secret=notion_client_secret,
            token_url=token_url,
        )
    except httpx.RequestError as exc:
        logger.error("Notion token request failed (network): %s", exc)
        response.headers["Cache-Control"] = "no-store"
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {
            "error": "network_error",
            "error_description": "Failed to reach Notion token endpoint",
            "status_code": status.HTTP_503_SERVICE_UNAVAILABLE,
        }

    response.headers["Cache-Control"] = "no-store"

    if notion_resp.status_code >= 400:
        error_body: Dict[str, Any] = {}
        try:
            error_body = notion_resp.json()
        except Exception:
            error_body = {}

        error = error_body.get("error") or "notion_error"
        description = error_body.get("error_description") or error_body.get("message")
        logger.warning(
            "Notion token exchange failed status=%s error=%s",
            notion_resp.status_code,
            error,
        )
        response.status_code = notion_resp.status_code
        return {
            "error": error,
            "error_description": description,
            "status_code": notion_resp.status_code,
        }

    try:
        data = notion_resp.json()
    except Exception:
        logger.error("Notion token response not JSON parseable status=%s", notion_resp.status_code)
        response.status_code = status.HTTP_502_BAD_GATEWAY
        return {
            "error": "invalid_response",
            "error_description": "Unexpected response format from Notion",
            "status_code": status.HTTP_502_BAD_GATEWAY,
        }

    # Avoid logging sensitive fields (code/access_token).
    logger.info(
        "Notion token exchange succeeded status=%s workspace_id=%s workspace_name=%s bot_id=%s",
        notion_resp.status_code,
        data.get("workspace_id"),
        data.get("workspace_name"),
        data.get("bot_id"),
    )

    return NotionExchangeResponse(
        access_token=data.get("access_token"),
        workspace_id=data.get("workspace_id"),
        workspace_name=data.get("workspace_name"),
        bot_id=data.get("bot_id"),
        notion_owner=data.get("owner"),
    )
