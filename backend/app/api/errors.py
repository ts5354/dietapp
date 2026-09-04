from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class ApiError(Exception):
    def __init__(
        self,
        *,
        status_code: int,
        code: str,
        message: str,
        details: list[dict[str, str]] | None = None,
    ) -> None:
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


def validation_error(
    *, field: str, message: str = "The request contains invalid values."
) -> ApiError:
    return ApiError(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        code="VALIDATION_ERROR",
        message="The request contains invalid values.",
        details=[{"field": field, "message": message}],
    )


def _error_response(error: ApiError) -> JSONResponse:
    body: dict[str, Any] = {"error": {"code": error.code, "message": error.message}}
    if error.details is not None:
        body["error"]["details"] = error.details
    return JSONResponse(status_code=error.status_code, content=body)


def _field_path(location: tuple[str | int, ...]) -> str:
    path = (
        location[1:]
        if location and location[0] in {"body", "path", "query"}
        else location
    )
    return ".".join(str(part) for part in path) or "request"


def _validation_message(error: dict[str, Any]) -> str:
    error_type = error.get("type", "")
    context = error.get("ctx") or {}
    if error_type == "greater_than":
        return f"Value must be greater than {context.get('gt')}."
    if error_type == "less_than_equal":
        return f"Value must be less than or equal to {context.get('le')}."
    if error_type == "greater_than_equal":
        return f"Value must be greater than or equal to {context.get('ge')}."
    if error_type == "string_too_long":
        return f"Value must contain at most {context.get('max_length')} characters."
    if error_type == "extra_forbidden":
        return "Extra fields are not permitted."
    if error_type == "missing":
        return "Field is required."
    return "Value is invalid."


async def api_error_handler(_request: Request, error: ApiError) -> JSONResponse:
    return _error_response(error)


async def request_validation_error_handler(
    _request: Request, error: RequestValidationError
) -> JSONResponse:
    details = [
        {
            "field": _field_path(tuple(item["loc"])),
            "message": _validation_message(item),
        }
        for item in error.errors()
    ]
    return _error_response(
        ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="VALIDATION_ERROR",
            message="The request contains invalid values.",
            details=details,
        )
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, api_error_handler)
    app.add_exception_handler(RequestValidationError, request_validation_error_handler)
