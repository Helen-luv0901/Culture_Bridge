"""Uniform error format: {"detail": {"code": "...", "message": "..."}}.

Every error the API returns has this shape (the app reads detail.code), including invalid
requests, unknown routes, write conflicts and unexpected failures.
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)
_UNIQUE_VIOLATION = "23505"


class ApiError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.headers = headers


def not_found(code: str = "not_found") -> ApiError:
    return ApiError(404, code)


def forbidden(code: str = "forbidden") -> ApiError:
    return ApiError(403, code)


def conflict(code: str, message: str | None = None) -> ApiError:
    return ApiError(409, code, message)


def _error(
    status_code: int, code: str, message: str | None = None, headers: dict[str, str] | None = None
) -> JSONResponse:
    detail = {"code": code} | ({"message": message} if message else {})
    return JSONResponse({"detail": detail}, status_code=status_code, headers=headers)


def _first_problem(exc: RequestValidationError) -> str:
    errors = exc.errors()
    if not errors:
        return "invalid request"
    first = errors[0]
    where = ".".join(str(part) for part in first.get("loc", ()) if part != "body")
    return f"{where}: {first.get('msg', 'invalid')}" if where else str(first.get("msg"))


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(_: Request, exc: ApiError) -> JSONResponse:
        return _error(exc.status_code, exc.code, exc.message, exc.headers)

    @app.exception_handler(RequestValidationError)
    async def handle_invalid_request(_: Request, exc: RequestValidationError) -> JSONResponse:
        return _error(422, "invalid_request", _first_problem(exc))

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = "not_found" if exc.status_code == 404 else f"http_{exc.status_code}"
        return _error(exc.status_code, code, headers=getattr(exc, "headers", None))

    @app.exception_handler(IntegrityError)
    async def handle_conflict(request: Request, exc: IntegrityError) -> JSONResponse:
        # A duplicate is usually the same write sent twice at once (a double tap); the first
        # one won. Any other broken rule (NOT NULL, CHECK, foreign key) is a bug: 500.
        if getattr(exc.orig, "sqlstate", None) != _UNIQUE_VIOLATION:
            logger.error(
                "Database rule broken on %s %s", request.method, request.url.path, exc_info=exc
            )
            return _error(500, "internal_error")
        logger.warning("Duplicate write on %s %s: %s", request.method, request.url.path, exc.orig)
        return _error(409, "conflict")

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled error on %s %s", request.method, request.url.path)
        return _error(500, "internal_error")
