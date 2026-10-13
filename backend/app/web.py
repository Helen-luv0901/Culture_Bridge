"""Serve the built Flutter web app next to the API (A-9): one Cloud Run service, one origin.

Files from WEB_DIR are served as they are; any other path that is not /api returns index.html so
deep links such as /explore or /actions/arc load the app, which then routes on the client.
"""

from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, HTMLResponse, Response

STATIC = Path(__file__).with_name("static")
_NO_CACHE = {"Cache-Control": "no-cache"}


def mount_web_app(app: FastAPI, web_dir: Path | None) -> None:
    @app.get("/account-deletion", include_in_schema=False)
    def account_deletion() -> HTMLResponse:
        # Public page Google Play requires: how to delete an account and its data (B-17).
        return HTMLResponse((STATIC / "account-deletion.html").read_text(encoding="utf-8"))

    if web_dir is None or not (web_dir / "index.html").is_file():
        return
    root = web_dir.resolve()

    @app.get("/{path:path}", include_in_schema=False)
    def web(path: str, request: Request) -> Response:
        if path.startswith("api/") or path == "api":
            return Response(status_code=404)
        candidate = (root / path).resolve()
        if path and candidate.is_file() and candidate.is_relative_to(root):
            # Flutter's own files carry no content hash, so let browsers revalidate them.
            headers = _NO_CACHE if candidate.suffix in (".html", ".js", ".json") else None
            return FileResponse(candidate, headers=headers)
        return FileResponse(root / "index.html", headers=_NO_CACHE)
