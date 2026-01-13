import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from .config import Settings


def _resolve_path(path: str) -> Path:
    path_obj = Path(path)
    if not path_obj.is_absolute():
        path_obj = Path(__file__).resolve().parent / path_obj
    return path_obj


def configure_logging(settings: Settings) -> logging.Logger:
    """
    Configure a shared application logger that writes to both stdout and a rotating file.
    Subsequent calls are no-ops to avoid duplicate handlers.
    """
    logger = logging.getLogger("isla")
    if logger.handlers:
        return logger

    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    logger.setLevel(level)
    formatter = logging.Formatter(
        fmt="%(asctime)s %(levelname)s [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    log_path = _resolve_path(settings.log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    file_handler = RotatingFileHandler(
        log_path,
        maxBytes=settings.log_max_bytes,
        backupCount=settings.log_backup_count,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    logger.propagate = False
    logger.info("Logging initialized at %s (level=%s)", log_path, logging.getLevelName(level))
    return logger


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(f"isla.{name}")
