"""The assistant's tool-calling loop.

    user message -> model -> (tool calls -> tool results -> model)* -> answer

The loop runs every tool itself (no SDK auto-calling), caps the number of rounds, and turns any
model failure into a safe fallback reply. Cards and screen actions come from what the tools
actually returned, never from the model's text.
"""

import logging
import time
import uuid
from datetime import UTC, date, datetime, timedelta, timezone

from app.assistant.data import AssistantDataSource, Locale
from app.assistant.llm import (
    LLM,
    LLMError,
    ModelTurn,
    ToolCall,
    ToolResult,
    ToolResultsTurn,
    Turn,
    UserTurn,
)
from app.assistant.memory import ConversationStore
from app.assistant.operations import OperationStore, PendingOperation
from app.assistant.prefetch import Prefetched, cite_named_procedures, prefetch
from app.assistant.prompts import build_system_prompt, build_user_message, message_locale
from app.assistant.related import parse_related, related_cards
from app.assistant.schemas import AssistantMessageRequest, AssistantReply, PendingOperationOut
from app.assistant.tools import ToolContext, ToolRegistry
from app.core.auth import CurrentUser

logger = logging.getLogger(__name__)

TAIPEI = timezone(timedelta(hours=8))
MAX_CALLS_PER_ROUND = 6

FALLBACK_TEXT: dict[Locale, str] = {
    "zh-Hant": "助理暫時無法回答，請稍後再試，或直接到流程頁查看步驟與來源。",
    "en": "The assistant can't answer right now. Please try again later, or open the procedure "
    "page to see its steps and sources.",
}


def taipei_today() -> date:
    return datetime.now(UTC).astimezone(TAIPEI).date()


def operation_out(operation: PendingOperation) -> PendingOperationOut:
    return PendingOperationOut(
        id=operation.id,
        type=operation.type,
        target_id=operation.target_id,
        summary=operation.summary,
        status=operation.status,
        expires_at=operation.expires_at,
        result=operation.result,
    )


# One message, all its model rounds together; with one round's own limit it stays under
# the app's 120 s wait (lib/data/culture_repository.dart).
DEADLINE_SECONDS = 60.0


def conversation_owner(user: CurrentUser | None) -> str:
    return f"user:{user.id}" if user else "guest"


class Assistant:
    def __init__(
        self,
        llm: LLM,
        data: AssistantDataSource | None,
        registry: ToolRegistry,
        memory: ConversationStore,
        max_tool_rounds: int = 5,
        operations: OperationStore | None = None,
        deadline_seconds: float = DEADLINE_SECONDS,
    ) -> None:
        self._llm = llm
        self._data = data
        self._registry = registry
        self._memory = memory
        self._max_tool_rounds = max_tool_rounds
        self._operations = operations
        self._deadline_seconds = deadline_seconds

    def reply(
        self,
        request: AssistantMessageRequest,
        user: CurrentUser | None,
        data: AssistantDataSource | None = None,
        operations: OperationStore | None = None,
    ) -> AssistantReply:
        """Answer one message. `data`/`operations` are per-request (the caller's DB session);
        the constructor's are the defaults used by unit tests."""
        owner = conversation_owner(user)
        conversation_id = request.conversation_id or uuid.uuid4().hex
        history: list[Turn] = self._memory.load(owner, conversation_id)

        source = data or self._data
        assert source is not None, "Assistant needs a data source"
        # Cards and fallback text follow the language of the question, not the app's setting.
        locale = message_locale(request.message, request.locale)
        ctx = ToolContext(
            data=source,
            locale=locale,
            user=user,
            operations=operations or self._operations,
        )
        # Run the obvious searches now, so most questions need one model call instead of several.
        found = prefetch(request.message, ctx)
        history.append(
            UserTurn(
                found.attach(build_user_message(request.message, request.screen, request.locale))
            )
        )
        system = build_system_prompt(request.locale, taipei_today())
        specs = self._registry.specs()
        tools_used: list[str] = []

        # The extra iteration lets the model answer after its last allowed round of tool calls.
        started = time.monotonic()
        for round_number in range(self._max_tool_rounds + 1):
            if round_number and time.monotonic() - started > self._deadline_seconds:
                # A slow or busy model: answer now rather than past the app's 120 s wait.
                logger.warning("Assistant fallback: deadline reached after %s", tools_used)
                return self._fallback(conversation_id, locale, tools_used)
            source.release()
            try:
                turn = self._llm.generate(system, history, specs)
            except LLMError as exc:
                logger.warning("Assistant fallback: %s", exc)
                return self._fallback(conversation_id, locale, tools_used)
            history.append(turn)
            if not turn.tool_calls:
                return self._finish(owner, conversation_id, history, turn, ctx, tools_used, found)
            if round_number == self._max_tool_rounds:
                break
            results = tuple(
                self._execute(call, ctx, index) for index, call in enumerate(turn.tool_calls)
            )
            tools_used.extend(call.name for call in turn.tool_calls)
            history.append(ToolResultsTurn(results))

        logger.warning("Assistant fallback: tool round limit reached (%s)", tools_used)
        return self._fallback(conversation_id, locale, tools_used)

    def _execute(self, call: ToolCall, ctx: ToolContext, index: int) -> ToolResult:
        # Every call still gets a result (the model expects one per call), but only a few run.
        if index >= MAX_CALLS_PER_ROUND:
            return ToolResult(
                id=call.id, name=call.name, result={"error": "Too many tool calls in one step."}
            )
        return self._registry.execute(call, ctx)

    def forget_user(self, user: CurrentUser) -> None:
        """Drop every conversation of this account (account deletion)."""
        self._memory.clear_owner(conversation_owner(user))

    def clear(self, conversation_id: str, user: CurrentUser | None) -> None:
        self._memory.clear(conversation_owner(user), conversation_id)

    def _finish(
        self,
        owner: str,
        conversation_id: str,
        history: list[Turn],
        turn: ModelTurn,
        ctx: ToolContext,
        tools_used: list[str],
        found: Prefetched,
    ) -> AssistantReply:
        related = parse_related(turn.text or "")
        if not related.text:
            logger.warning("Assistant fallback: model returned an empty answer")
            return self._fallback(conversation_id, ctx.locale, tools_used)
        cite_named_procedures(related.text, found, ctx)
        related_cards(related, ctx)
        self._memory.save(owner, conversation_id, history)
        return AssistantReply(
            conversation_id=conversation_id,
            text=related.text,
            cards=list(ctx.cards.values()),
            screen_actions=ctx.screen_actions,
            pending_operations=[operation_out(op) for op in ctx.proposed_operations],
            tools_used=tools_used,
        )

    @staticmethod
    def _fallback(conversation_id: str, locale: Locale, tools_used: list[str]) -> AssistantReply:
        # The failed exchange is not saved, so the next message starts from a clean history.
        return AssistantReply(
            conversation_id=conversation_id,
            text=FALLBACK_TEXT[locale],
            tools_used=tools_used,
            fallback=True,
        )
