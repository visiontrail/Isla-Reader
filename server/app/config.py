import json
from functools import lru_cache
from typing import Any, List

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
    client_id: str
    client_secret: str
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

    def get_allowed_origins(self) -> List[str]:
        """Get parsed allowed origins list."""
        return _parse_origins(self.allowed_origins)


@lru_cache
def get_settings() -> Settings:
    return Settings()
