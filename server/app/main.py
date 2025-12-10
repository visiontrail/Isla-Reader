from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import Settings, get_settings
from .routers import key

app = FastAPI(
    title="Isla Reader Server",
    version="0.1.0",
    description="Secure backend for Isla Reader API key delivery and future user services.",
)


def _is_https(request: Request) -> bool:
    forwarded_proto = request.headers.get("x-forwarded-proto", "")
    return request.url.scheme == "https" or forwarded_proto == "https"


@app.middleware("http")
async def enforce_https(request: Request, call_next):
    settings = get_settings()
    if settings.require_https and not _is_https(request):
        return JSONResponse(status_code=400, content={"detail": "HTTPS is required for this endpoint"})

    response = await call_next(request)
    response.headers.setdefault(
        "Strict-Transport-Security",
        f"max-age={settings.hsts_max_age}; includeSubDomains",
    )
    response.headers.setdefault("Cache-Control", "no-store")
    return response


def _configure_cors(app: FastAPI, settings: Settings) -> None:
    origins = settings.get_allowed_origins()
    if not origins:
        return

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_methods=["POST", "OPTIONS", "GET"],
        allow_headers=["*"],
        max_age=600,
    )


@app.on_event("startup")
async def startup_event():
    settings = get_settings()
    _configure_cors(app, settings)


@app.get("/health")
async def health(settings: Settings = Depends(get_settings)) -> dict:
    return {
        "status": "ok",
        "require_https": settings.require_https,
    }


app.include_router(key.router)
