from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import actions, admin, assistant, experiences, me, moderation
from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.web import mount_web_app

app = FastAPI(
    title="Culture Bridge API",
    version="0.2.0",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
)
register_error_handlers(app)

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
api.include_router(actions.router)
api.include_router(experiences.router)
api.include_router(moderation.router)
api.include_router(assistant.router)
api.include_router(admin.router)


@api.get("/config", tags=["config"])
def client_config() -> dict:
    """Public settings the app reads at startup (so one build works in every environment)."""
    settings = get_settings()
    return {"environment": settings.env, "firebase": settings.firebase_web}


app.include_router(api)


# Cloud Run reserves /healthz (its own 404 page answers it), so deployed checks use /health.
@app.get("/health", include_in_schema=False)
@app.get("/healthz", include_in_schema=False)
def health() -> dict[str, str]:
    return {"status": "ok"}


# Last: the web app catches every remaining path.
mount_web_app(app, get_settings().web_dir)
