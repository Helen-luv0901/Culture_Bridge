"""Uniform error format: {"detail": {"code": "...", "message": "..."}}."""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


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


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(_: Request, exc: ApiError) -> JSONResponse:
        detail = {"code": exc.code} | ({"message": exc.message} if exc.message else {})
        return JSONResponse({"detail": detail}, status_code=exc.status_code, headers=exc.headers)
