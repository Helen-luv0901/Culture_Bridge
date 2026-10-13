from fastapi import APIRouter, FastAPI

from app.api import actions, admin, assistant, experiences, me, moderation
from app.core.errors import register_error_handlers

app = FastAPI(
    title="Culture Bridge API",
    version="0.2.0",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
)
register_error_handlers(app)

# Everything lives under /api so the web app can own every other path (/explore, /actions/…).
api = APIRouter(prefix="/api")
api.include_router(me.router)
api.include_router(actions.router)
api.include_router(experiences.router)
api.include_router(moderation.router)
api.include_router(assistant.router)
api.include_router(admin.router)
app.include_router(api)


@app.get("/healthz", include_in_schema=False)
def healthz() -> dict[str, str]:
    return {"status": "ok"}
