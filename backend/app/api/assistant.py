from functools import lru_cache
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.assistant.agent import Assistant
from app.assistant.data import DemoDataSource
from app.assistant.gemini import GeminiLLM
from app.assistant.llm import LLM, UnavailableLLM
from app.assistant.memory import ConversationStore
from app.assistant.schemas import AssistantMessageRequest, AssistantReply
from app.assistant.tools import default_registry
from app.core.auth import CurrentUser, get_optional_user
from app.core.config import get_settings

router = APIRouter(prefix="/assistant", tags=["assistant"])


@lru_cache
def get_assistant() -> Assistant:
    settings = get_settings()
    llm: LLM = (
        GeminiLLM(settings.gemini_api_key, settings.gemini_model, settings.gemini_timeout_seconds)
        if settings.gemini_api_key
        else UnavailableLLM()
    )
    return Assistant(
        llm=llm,
        data=DemoDataSource.from_file(settings.demo_content_path),
        registry=default_registry(),
        memory=ConversationStore(max_exchanges=settings.assistant_memory_exchanges),
        max_tool_rounds=settings.assistant_max_tool_rounds,
    )


AssistantDep = Annotated[Assistant, Depends(get_assistant)]
UserDep = Annotated[CurrentUser | None, Depends(get_optional_user)]


@router.post("/message")
def post_message(
    body: AssistantMessageRequest, assistant: AssistantDep, user: UserDep
) -> AssistantReply:
    return assistant.reply(body, user)


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def clear_conversation(conversation_id: str, assistant: AssistantDep, user: UserDep) -> Response:
    assistant.clear(conversation_id, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
