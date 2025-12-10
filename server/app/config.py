import json
from functools import lru_cache
from typing import List

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _lenient_json_loads(value: str):
    if value is None:
        return value
    if isinstance(value, (list, dict)):
        return value
    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return []
        try:
            return json.loads(stripped)
        except json.JSONDecodeError:
            if "," in stripped:
                return [part.strip() for part in stripped.split(",") if part.strip()]
            return [stripped]
    return value


class Settings(BaseSettings):
    api_key: str
    client_id: str
    client_secret: str
    allowed_origins: List[str] = []
    require_https: bool = True
    request_ttl_seconds: int = 300
    hsts_max_age: int = 63_072_000  # 2 years

    model_config = SettingsConfigDict(env_file=".env", env_prefix="ISLA_", case_sensitive=False)

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def parse_allowed_origins(cls, value):
        parsed = _lenient_json_loads(value)
        return [] if parsed is None else parsed


@lru_cache
def get_settings() -> Settings:
    return Settings()
