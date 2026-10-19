"""Serve the built Flutter web app next to the API (A-9): one Cloud Run service, one origin.

Files from WEB_DIR are served as they are; any other path that is not /api returns index.html so
deep links such as /explore or /actions/arc load the app, which then routes on the client.

The app is large (main.dart.js, CanvasKit, fonts), so two things keep it quick to open:
- The image build stores a gzipped copy next to each big file (main.dart.js.gz), sent to
  browsers that accept gzip: a third to two thirds of the size.
- Flutter's files carry no content hash, so browsers check back on each visit ("no-cache"), but
  a file they already have is answered with 304 Not Modified instead of being sent again.
"""

import mimetypes
import os
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, HTMLResponse, Response

STATIC = Path(__file__).with_name("static")
_NO_CACHE = {"Cache-Control": "no-cache"}
GZIP_SUFFIX = ".gz"


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
            return _send(candidate, request)
        return _send(root / "index.html", request)


def _send(file: Path, request: Request) -> Response:
    """The file (or its gzipped copy), or 304 when the browser already has this version."""
    headers = dict(_NO_CACHE)
    packed = file.with_name(file.name + GZIP_SUFFIX)
    if _accepts_gzip(request.headers.get("accept-encoding", "")) and packed.is_file():
        headers |= {"Content-Encoding": "gzip", "Vary": "Accept-Encoding"}
        media_type = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        response = FileResponse(
            packed, headers=headers, media_type=media_type, stat_result=os.stat(packed)
        )
    else:
        response = FileResponse(file, headers=headers, stat_result=os.stat(file))
    etag = response.headers["etag"]
    if etag in _tags(request.headers.get("if-none-match", "")):
        return Response(status_code=304, headers={**headers, "ETag": etag})
    return response


def _accepts_gzip(accept_encoding: str) -> bool:
    for item in accept_encoding.split(","):
        name, _, params = item.partition(";")
        if name.strip().lower() != "gzip":
            continue
        quality = params.strip().removeprefix("q=")
        try:
            return not params.strip() or float(quality) > 0
        except ValueError:
            return True
    return False


def _tags(if_none_match: str) -> set[str]:
    return {tag.strip().removeprefix("W/") for tag in if_none_match.split(",") if tag.strip()}
