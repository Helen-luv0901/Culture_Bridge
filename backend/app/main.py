import logging

from fastapi import APIRouter, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.api import (
    actions,
    admin,
    assistant,
    avatars,
    client_errors,
    comments,
    experiences,
    me,
    moderation,
)
from app.core.config import get_settings
from app.core.db import get_engine
from app.core.errors import register_error_handlers
from app.web import mount_web_app

logger = logging.getLogger(__name__)

_dev = get_settings().is_development
app = FastAPI(
    title="Culture Bridge API",
    version="0.2.0",
    # The interactive docs list every route, admin ones included: development only.
    docs_url="/api/docs" if _dev else None,
    openapi_url="/api/openapi.json" if _dev else None,
    redoc_url=None,
)
register_error_handlers(app)

_SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    # No other site may show the app in a frame (clickjacking).
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": "frame-ancestors 'none'",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    for name, value in _SECURITY_HEADERS.items():
        response.headers.setdefault(name, value)
    if not _dev:  # production is HTTPS only (Cloud Run)
        response.headers.setdefault("Strict-Transport-Security", "max-age=31536000")
    return response


if get_settings().is_development:
    # `flutter run -d chrome` serves the app from its own localhost port. Production serves the
    # app from this same origin, so it needs no CORS at all.
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
        allow_methods=["*"],
        allow_headers=["*"],
    )

# Everything lives under /api so the web app can own every other path (/explore, /actions/…).
api = APIRouter(prefix="/api")
api.include_router(me.router)
api.include_router(avatars.router)
api.include_router(actions.router)
api.include_router(experiences.router)
api.include_router(comments.router)
api.include_router(moderation.router)
api.include_router(assistant.router)
api.include_router(admin.router)
api.include_router(client_errors.router)


@api.get("/config", tags=["config"])
def client_config() -> dict:
    """Public settings the app reads at startup (so one build works in every environment)."""
    settings = get_settings()
    return {"environment": settings.env, "firebase": settings.firebase_web}


app.include_router(api)


# Cloud Run reserves /healthz (its own 404 page answers it), so deployed checks use /health.
@app.get("/health", include_in_schema=False)
@app.get("/healthz", include_in_schema=False)
def health() -> JSONResponse:
    """Up and able to reach the database. scripts/deploy.sh only sends traffic to a new
    revision that answers 200 here, and the uptime check alerts on anything else."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except SQLAlchemyError:
        logger.exception("Health check: database unreachable")
        return JSONResponse({"status": "error", "database": "unreachable"}, status_code=503)
    return JSONResponse({"status": "ok", "database": "ok"})


# Last: the web app catches every remaining path.
mount_web_app(app, get_settings().web_dir)
