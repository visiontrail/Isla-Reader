from __future__ import annotations

from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from threading import Lock
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from .logging_utils import get_logger


class UpdatePolicy(BaseModel):
    enabled: bool = False
    mode: Literal["soft", "hard"] = "soft"
    latest_version: str = ""
    minimum_supported_version: str = ""
    title: str = ""
    message: str = ""
    app_store_url: str = ""
    remind_interval_hours: int = Field(default=24, ge=1, le=24 * 30)
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @field_validator(
        "latest_version",
        "minimum_supported_version",
        "title",
        "message",
        "app_store_url",
        mode="before",
    )
    @classmethod
    def _strip_string(cls, value: object) -> str:
        if value is None:
            return ""
        return str(value).strip()

    @field_validator("updated_at", mode="before")
    @classmethod
    def _normalize_updated_at(cls, value: object) -> datetime:
        if isinstance(value, datetime):
            dt = value
        else:
            dt = datetime.now(timezone.utc)
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)


class UpdatePolicyStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._logger = get_logger("update_policy_store")
        self._lock = Lock()
        self._policy = UpdatePolicy()
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            self._logger.info("Update policy file not found at %s; using defaults", self.path)
            return

        try:
            raw = self.path.read_text(encoding="utf-8").strip()
            if raw:
                self._policy = UpdatePolicy.model_validate_json(raw)
                self._logger.info("Loaded update policy from %s", self.path)
        except Exception as exc:
            self._logger.error("Failed to load update policy from %s: %s", self.path, exc)
            self._policy = UpdatePolicy()

    def _persist(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(self._policy.model_dump_json(indent=2), encoding="utf-8")

    def get(self) -> UpdatePolicy:
        with self._lock:
            return UpdatePolicy.model_validate(self._policy.model_dump())

    def set(self, policy: UpdatePolicy) -> UpdatePolicy:
        with self._lock:
            updated = policy.model_copy(update={"updated_at": datetime.now(timezone.utc)})
            self._policy = updated
            self._persist()
            self._logger.info(
                "Saved update policy enabled=%s mode=%s latest=%s minimum=%s",
                updated.enabled,
                updated.mode,
                updated.latest_version,
                updated.minimum_supported_version,
            )
            return UpdatePolicy.model_validate(updated.model_dump())


@lru_cache
def get_update_policy_store(path: str) -> UpdatePolicyStore:
    path_obj = Path(path)
    if not path_obj.is_absolute():
        path_obj = Path(__file__).resolve().parent / path_obj
    return UpdatePolicyStore(path_obj)
