from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    api_key: str
    client_id: str
    client_secret: str
    allowed_origins: List[str] = []
    require_https: bool = True
    request_ttl_seconds: int = 300
    hsts_max_age: int = 63_072_000  # 2 years

    model_config = SettingsConfigDict(env_file=".env", env_prefix="ISLA_", case_sensitive=False)


@lru_cache
def get_settings() -> Settings:
    return Settings()
