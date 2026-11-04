"""Request body size limits, checked before a body is read.

Pydantic's max_length only applies once the whole JSON has been read, and Cloud Run accepts
bodies up to 32 MiB, also on routes anyone may call (/api/client-errors). Every API body fits
in a few KB except a profile photo (base64, up to ~8.1 MB) and the admin's official documents
(up to 200,000 characters). A larger body gets 413 in the usual error shape.

With a Content-Length the header decides. Without one (chunked), the body is read here up to
the limit and handed on, so a stream that never ends is cut off at the limit as well.
"""

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

DEFAULT_LIMIT = 64 * 1024
# Path prefix -> limit; the first match wins.
LIMITS = (
    ("/api/me/avatar", 8_500_000),
    ("/api/admin/", 2_000_000),  # documents: 200,000 characters, 3 bytes each in UTF-8
)


def limit_for(path: str) -> int:
    return next((size for prefix, size in LIMITS if path.startswith(prefix)), DEFAULT_LIMIT)


class BodyLimitMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = limit_for(scope["path"])
        length = dict(scope["headers"]).get(b"content-length")
        if length is not None and length.isdigit():
            if int(length) > limit:
                await _too_large(scope, receive, send)
                return
            await self.app(scope, receive, send)  # the server stops reading at that length
            return
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] != "http.request":  # the client went away
                return
            body += message.get("body", b"")
            if len(body) > limit:
                await _too_large(scope, receive, send)
                return
            if not message.get("more_body", False):
                break
        await self.app(scope, _replay(bytes(body), receive), send)


def _replay(body: bytes, receive: Receive) -> Receive:
    sent = False

    async def replay() -> Message:
        nonlocal sent
        if sent:
            return await receive()  # waits for a disconnect, as the server's own would
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    return replay


async def _too_large(scope: Scope, receive: Receive, send: Send) -> None:
    response = JSONResponse({"detail": {"code": "request_too_large"}}, status_code=413)
    await response(scope, receive, send)
