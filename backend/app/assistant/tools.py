"""Tools the assistant calls to read real data before answering.

Every tool returns a JSON object. A tool that finds nothing says so (`found: false` or an empty
`results`) so the model can tell the user instead of guessing. Tool failures come back as
`{"error": ...}` results rather than exceptions, so one bad call never breaks the conversation.
"""

import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.assistant.data import (
    ActionRecord,
    AssistantDataSource,
    ExperienceRecord,
    IdentityType,
    Locale,
    TopicId,
)
from app.assistant.knowledge import default_knowledge_base
from app.assistant.llm import ToolCall, ToolResult, ToolSpec
from app.assistant.operations import OPERATION_TTL, OperationService, PendingOperation
from app.assistant.schemas import ActionCard, Card, ExperienceCard, ScreenAction, ScreenActionType
from app.core.auth import CurrentUser

logger = logging.getLogger(__name__)

EXPERIENCE_NOTICE = "Personal student experience, not verified fact."


@dataclass
class ToolContext:
    """Per-request state shared by the tools; the agent reads cards and screen actions after."""

    data: AssistantDataSource
    locale: Locale
    user: CurrentUser | None
    operations: OperationService | None = None
    cards: dict[str, Card] = field(default_factory=dict)
    screen_actions: list[ScreenAction] = field(default_factory=list)
    proposed_operations: list[PendingOperation] = field(default_factory=list)


class ToolArgs(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ToolError(Exception):
    """Expected failure a tool reports back to the model, e.g. an unknown id."""


@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    args_model: type[ToolArgs]
    handler: Callable[[Any, ToolContext], dict[str, Any]]

    def spec(self) -> ToolSpec:
        schema = self.args_model.model_json_schema()
        schema.pop("title", None)
        schema.pop("additionalProperties", None)  # extra args are rejected by pydantic instead
        schema["properties"] = {
            name: _plain_property(prop) for name, prop in schema.get("properties", {}).items()
        }
        return ToolSpec(name=self.name, description=self.description, parameters=schema)


def _plain_property(prop: dict[str, Any]) -> dict[str, Any]:
    """Drop pydantic titles and `anyOf: [X, null]`; `required` already marks optional args."""
    prop = {k: v for k, v in prop.items() if k != "title"}
    variants = prop.pop("anyOf", None)
    if variants:
        non_null = [v for v in variants if v.get("type") != "null"]
        if len(non_null) == 1:
            prop = {**non_null[0], **prop}
        else:
            prop["anyOf"] = variants
    if prop.get("default") is None:
        prop.pop("default", None)
    return prop


class ToolRegistry:
    def __init__(self, tools: list[Tool]) -> None:
        self._tools = {tool.name: tool for tool in tools}

    def specs(self) -> list[ToolSpec]:
        return [tool.spec() for tool in self._tools.values()]

    def execute(self, call: ToolCall, ctx: ToolContext) -> ToolResult:
        return ToolResult(id=call.id, name=call.name, result=self._run(call, ctx))

    def _run(self, call: ToolCall, ctx: ToolContext) -> dict[str, Any]:
        tool = self._tools.get(call.name)
        if tool is None:
            return {"error": f"Unknown tool '{call.name}'. Available: {sorted(self._tools)}"}
        try:
            args = tool.args_model.model_validate(call.args)
        except ValidationError as exc:
            problems = [
                f"{'.'.join(map(str, e['loc'])) or 'args'}: {e['msg']}" for e in exc.errors()
            ]
            return {"error": "Invalid arguments", "details": problems}
        try:
            return tool.handler(args, ctx)
        except ToolError as exc:
            return {"error": str(exc)}
        except Exception:
            logger.exception("Tool %s failed", call.name)
            return {"error": "The tool failed. Tell the user the data is unavailable right now."}


# ---------- serializers: locale-resolved, never include author fields ----------


def _action_summary(action: ActionRecord, locale: Locale) -> dict[str, Any]:
    return {
        "action_id": action.id,
        "title": action.title.get(locale),
        "verification_status": action.verification_status,
        "last_verified_at": action.last_verified_at,
        "recent_success_count": action.recent_success_count,
    }


def _action_detail(action: ActionRecord, locale: Locale) -> dict[str, Any]:
    return {
        **_action_summary(action, locale),
        "description": action.description.get(locale),
        "applicable_to": action.applicable_to.get(locale),
        "location": action.location.get(locale),
        "steps": [{"position": i, "title": s.get(locale)} for i, s in enumerate(action.steps, 1)],
        "sources": [
            {"title": s.title.get(locale), "url": s.url, "publisher": s.publisher, "kind": s.kind}
            for s in action.sources
        ],
    }


def _experience_summary(experience: ExperienceRecord, locale: Locale) -> dict[str, Any]:
    return {
        "experience_id": experience.id,
        "kind": "student_experience",
        "topic": experience.topic_id,
        "identity_type": experience.identity_type,
        "summary": experience.summary.get(locale),
    }


def _action_card(action: ActionRecord, locale: Locale) -> ActionCard:
    return ActionCard(
        action_id=action.id,
        title=action.title.get(locale),
        verification_status=action.verification_status,
        last_verified_at=action.last_verified_at,
        recent_success_count=action.recent_success_count,
        sources=[s.title.get(locale) for s in action.sources],
    )


# ---------- tools ----------


class SearchActionsArgs(ToolArgs):
    query: str = Field(min_length=1, max_length=200, description="Keywords, e.g. 工作證 or bank")
    limit: int = Field(default=5, ge=1, le=10)


def search_actions(args: SearchActionsArgs, ctx: ToolContext) -> dict[str, Any]:
    found = ctx.data.search_actions(args.query, args.limit)
    return {"count": len(found), "results": [_action_summary(a, ctx.locale) for a in found]}


class GetActionArgs(ToolArgs):
    action_id: str = Field(min_length=1, max_length=100)


def get_action(args: GetActionArgs, ctx: ToolContext) -> dict[str, Any]:
    action = ctx.data.get_action(args.action_id)
    if action is None:
        return {"found": False, "action_id": args.action_id}
    ctx.cards[f"action:{action.id}"] = _action_card(action, ctx.locale)
    return {"found": True, "action": _action_detail(action, ctx.locale)}


class SearchExperiencesArgs(ToolArgs):
    query: str | None = Field(default=None, max_length=200, description="Optional keywords")
    topic: TopicId | None = None
    identity_type: IdentityType | None = None
    limit: int = Field(default=5, ge=1, le=10)


def search_experiences(args: SearchExperiencesArgs, ctx: ToolContext) -> dict[str, Any]:
    found = ctx.data.search_experiences(args.query, args.topic, args.identity_type, args.limit)
    return {
        "count": len(found),
        "notice": EXPERIENCE_NOTICE,
        "results": [_experience_summary(e, ctx.locale) for e in found],
    }


class GetExperienceArgs(ToolArgs):
    experience_id: str = Field(min_length=1, max_length=100)


def get_experience(args: GetExperienceArgs, ctx: ToolContext) -> dict[str, Any]:
    experience = ctx.data.get_experience(args.experience_id)
    if experience is None:
        return {"found": False, "experience_id": args.experience_id}
    reminder = experience.reminder.get(ctx.locale)
    ctx.cards[f"experience:{experience.id}"] = ExperienceCard(
        experience_id=experience.id, reminder=reminder
    )
    return {
        "found": True,
        "notice": EXPERIENCE_NOTICE,
        "experience": {
            **_experience_summary(experience, ctx.locale),
            "original_voice": experience.original_voice.get(ctx.locale),
            "reminder": reminder,
            "helpful_count": experience.helpful_count,
            "different_experience_count": experience.different_count,
        },
    }


class GetMyProgressArgs(ToolArgs):
    pass


def get_my_progress(_: GetMyProgressArgs, ctx: ToolContext) -> dict[str, Any]:
    if ctx.user is None:
        return {"requires_login": True, "results": []}
    records = ctx.data.get_in_progress(ctx.user.id)
    return {
        "count": len(records),
        "results": [
            {
                "execution_id": r.execution_id,
                "action_id": r.action_id,
                "title": r.action_title.get(ctx.locale),
                "started_at": r.started_at,
                "steps": [
                    {"position": s.position, "title": s.title.get(ctx.locale), "state": s.state}
                    for s in r.steps
                ],
            }
            for r in records
        ],
    }


class OpenScreenArgs(ToolArgs):
    screen: ScreenActionType
    target_id: str | None = Field(
        default=None,
        max_length=100,
        description="action_id for open_action/open_progress, experience_id for open_experience",
    )
    topic: TopicId | None = Field(default=None, description="Optional filter for open_explore")


def open_screen(args: OpenScreenArgs, ctx: ToolContext) -> dict[str, Any]:
    if args.screen in ("open_action", "open_progress"):
        if not args.target_id or ctx.data.get_action(args.target_id) is None:
            raise ToolError(f"{args.screen} needs an existing action_id from search_actions")
    elif args.screen == "open_experience":
        if not args.target_id or ctx.data.get_experience(args.target_id) is None:
            raise ToolError("open_experience needs an existing experience_id")
    action = ScreenAction(
        type=args.screen,
        target_id=args.target_id if args.screen not in ("open_explore", "open_share") else None,
        topic=args.topic if args.screen == "open_explore" else None,
    )
    if action not in ctx.screen_actions:
        ctx.screen_actions.append(action)
    return {"ok": True, "queued": action.model_dump()}


class SearchAppHelpArgs(ToolArgs):
    query: str = Field(min_length=1, max_length=200, description="e.g. 怎麼分享, verified meaning")
    limit: int = Field(default=3, ge=1, le=5)


def search_app_help(args: SearchAppHelpArgs, ctx: ToolContext) -> dict[str, Any]:
    kb = default_knowledge_base()
    found = kb.search(args.query, args.limit)
    return {
        "guide_version": kb.version,
        "count": len(found),
        "results": [kb.as_result(e, ctx.locale) for e in found],
    }


class ProposeStartActionArgs(ToolArgs):
    action_id: str = Field(min_length=1, max_length=100)


def propose_start_action(args: ProposeStartActionArgs, ctx: ToolContext) -> dict[str, Any]:
    if ctx.user is None:
        return {"requires_login": True}
    if ctx.operations is None:
        raise ToolError("Starting procedures from the assistant is not available.")
    action = ctx.data.get_action(args.action_id)
    if action is None:
        raise ToolError("Unknown action_id; find it with search_actions first")
    title = action.title.get(ctx.locale)
    summary = f"開始辦理「{title}」" if ctx.locale == "zh-Hant" else f"Start “{title}”"
    operation = ctx.operations.propose_start_action(ctx.user, action.id, summary)
    ctx.proposed_operations.append(operation)
    return {
        "status": "awaiting_user_confirmation",
        "operation_id": operation.id,
        "summary": summary,
        "expires_in_minutes": int(OPERATION_TTL.total_seconds() // 60),
        "note": "Nothing has been written yet. Ask the user to tap confirm in the app.",
    }


TOOLS: list[Tool] = [
    Tool(
        "search_actions",
        "Find official procedures (action cards) such as work permit, ARC, health insurance or "
        "bank account by keyword. Returns verification status and recent successful completions.",
        SearchActionsArgs,
        search_actions,
    ),
    Tool(
        "get_action",
        "Read one procedure: who it applies to, steps, sources, verification status, last "
        "verified date and successful completions in the last 30 days.",
        GetActionArgs,
        get_action,
    ),
    Tool(
        "search_experiences",
        "Find public student experiences by keyword, topic or identity type. These are personal "
        "experiences, never facts.",
        SearchExperiencesArgs,
        search_experiences,
    ),
    Tool(
        "get_experience",
        "Read one public student experience: original words, author-confirmed summary and "
        "reminder for the next student.",
        GetExperienceArgs,
        get_experience,
    ),
    Tool(
        "get_my_progress",
        "Read the signed-in user's procedures in progress and their step states.",
        GetMyProgressArgs,
        get_my_progress,
    ),
    Tool(
        "open_screen",
        "Ask the app to navigate after your answer. Only use when the user wants to go somewhere "
        "or start something; ids must come from earlier tool results.",
        OpenScreenArgs,
        open_screen,
    ),
    Tool(
        "search_app_help",
        "Explain how to use the Culture Bridge app: tabs, screens, buttons, sharing, privacy, "
        "what verification statuses mean, what the assistant can do. Never use it for procedure "
        "facts such as steps, documents, fees or dates.",
        SearchAppHelpArgs,
        search_app_help,
    ),
    Tool(
        "propose_start_action",
        "When the user asks to start a procedure, prepare it for their confirmation. This does "
        "not start anything: the app shows a confirm card and the user decides.",
        ProposeStartActionArgs,
        propose_start_action,
    ),
]


def default_registry() -> ToolRegistry:
    return ToolRegistry(TOOLS)
