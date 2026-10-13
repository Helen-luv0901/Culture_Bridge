from fastapi import FastAPI

from app.api import assistant

app = FastAPI(title="Culture Bridge API", version="0.1.0")
app.include_router(assistant.router)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}
