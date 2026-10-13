from dataclasses import dataclass
from functools import lru_cache
from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response, status

from app.assistant.agent import Assistant, operation_out
from app.assistant.db_operations import DbOperationService
from app.assistant.gemini import GeminiLLM
from app.assistant.limits import BudgetedLLM, DailyBudget, RateLimited, UsageLimiter
from app.assistant.llm import LLM, UnavailableLLM
from app.assistant.memory import ConversationStore
from app.assistant.operations import OperationError
from app.assistant.pg_data import PostgresAssistantData
from app.assistant.schemas import AssistantMessageRequest, AssistantReply, PendingOperationOut
from app.assistant.tools import default_registry
from app.core.auth import OptionalUser
from app.core.config import get_settings
from app.core.db import DbSession
from app.core.errors import ApiError

router = APIRouter(prefix="/assistant", tags=["assistant"])


@dataclass(frozen=True)
class AssistantServices:
    assistant: Assistant
    limiter: UsageLimiter
    allow_guests: bool


@lru_cache
def get_services() -> AssistantServices:
    settings = get_settings()
    llm: LLM = (
        GeminiLLM(settings.gemini_api_key, settings.gemini_model, settings.gemini_timeout_seconds)
        if settings.gemini_api_key
        else UnavailableLLM()
    )
    assistant = Assistant(
        llm=BudgetedLLM(llm, DailyBudget(settings.assistant_daily_llm_calls)),
        data=None,  # each request reads through its own database session
        registry=default_registry(),
        memory=ConversationStore(max_exchanges=settings.assistant_memory_exchanges),
        max_tool_rounds=settings.assistant_max_tool_rounds,
    )
    return AssistantServices(
        assistant=assistant,
        limiter=UsageLimiter(settings.assistant_per_minute, settings.assistant_per_day),
        allow_guests=settings.assistant_allow_guests,
    )


ServicesDep = Annotated[AssistantServices, Depends(get_services)]


@router.post("/message")
def post_message(
    body: AssistantMessageRequest,
    request: Request,
    services: ServicesDep,
    user: OptionalUser,
    db: DbSession,
) -> AssistantReply:
    if user is None and not services.allow_guests:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "login_required")
    key = f"user:{user.id}" if user else f"ip:{request.client.host if request.client else '?'}"
    try:
        services.limiter.check(key)
    except RateLimited as exc:
        raise ApiError(
            status.HTTP_429_TOO_MANY_REQUESTS,
            exc.code,
            headers={"Retry-After": str(exc.retry_after_seconds)},
        ) from exc
    return services.assistant.reply(
        body, user, data=PostgresAssistantData(db, user), operations=DbOperationService(db)
    )


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def clear_conversation(conversation_id: str, services: ServicesDep, user: OptionalUser) -> Response:
    services.assistant.clear(conversation_id, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _operation(action, operation_id: str, user) -> PendingOperationOut:
    try:
        return operation_out(action(operation_id, user))
    except OperationError as exc:
        raise ApiError(exc.status_code, exc.code) from exc


@router.get("/operations/{operation_id}")
def get_operation(operation_id: str, user: OptionalUser, db: DbSession) -> PendingOperationOut:
    return _operation(DbOperationService(db).get, operation_id, user)


@router.post("/operations/{operation_id}/confirm")
def confirm_operation(operation_id: str, user: OptionalUser, db: DbSession) -> PendingOperationOut:
    return _operation(DbOperationService(db).confirm, operation_id, user)


@router.post("/operations/{operation_id}/cancel")
def cancel_operation(operation_id: str, user: OptionalUser, db: DbSession) -> PendingOperationOut:
    return _operation(DbOperationService(db).cancel, operation_id, user)
