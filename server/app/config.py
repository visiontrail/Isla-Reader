import json
from functools import lru_cache
from typing import Any, List, Optional

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _parse_origins(value: Any) -> List[str]:
    """Parse allowed_origins from various formats: JSON array, comma-separated, or single value."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return []
        # Try JSON array first
        try:
            parsed = json.loads(stripped)
            if isinstance(parsed, list):
                return parsed
        except json.JSONDecodeError:
            pass
        # Fall back to comma-separated or single value
        if "," in stripped:
            return [part.strip() for part in stripped.split(",") if part.strip()]
        return [stripped]
    return []


class Settings(BaseSettings):
    api_key: str
    api_endpoint: str
    ai_model: str
    client_id: str
    client_secret: str
    metrics_ingest_token: Optional[str] = None
    metrics_data_file: str = "data/metrics.jsonl"
    metrics_max_events: int = 5000
    log_file: str = "logs/server.log"
    log_level: str = "INFO"
    log_max_bytes: int = 1_000_000
    log_backup_count: int = 5
    dashboard_username: str = "admin"
    dashboard_password: str = "lanread"
    dashboard_session_secret: Optional[str] = None
    dashboard_session_ttl_seconds: int = 86_400  # 24h
    # Use str type to prevent pydantic-settings from attempting JSON parsing before validator
    allowed_origins: str = ""
    require_https: bool = True
    request_ttl_seconds: int = 300
    hsts_max_age: int = 63_072_000  # 2 years

    model_config = SettingsConfigDict(env_file=".env", env_prefix="ISLA_", case_sensitive=False)

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def parse_allowed_origins(cls, value) -> str:
        # This validator just passes through; actual parsing happens in get_allowed_origins()
        if value is None:
            return ""
        return str(value)

    @field_validator("log_level", mode="before")
    @classmethod
    def normalize_log_level(cls, value) -> str:
        if value is None:
            return "INFO"
        return str(value).upper()

    def get_allowed_origins(self) -> List[str]:
        """Get parsed allowed origins list."""
        return _parse_origins(self.allowed_origins)

    def resolved_metrics_token(self) -> str:
        """Use dedicated metrics token when provided; fall back to client_secret."""
        return self.metrics_ingest_token or self.client_secret

    def resolved_dashboard_secret(self) -> str:
        return self.dashboard_session_secret or self.client_secret


@lru_cache
def get_settings() -> Settings:
    return Settings()
