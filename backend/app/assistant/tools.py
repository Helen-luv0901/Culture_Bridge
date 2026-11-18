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
    AssistantDataSource,
    ExperienceRecord,
    FaqRecord,
    IdentityType,
    Locale,
    TopicId,
)
from app.assistant.knowledge import default_knowledge_base
from app.assistant.llm import ToolCall, ToolResult, ToolSpec
from app.assistant.operations import OperationStore, PendingOperation
from app.assistant.schemas import Card, ExperienceCard, FaqCard, ScreenAction, ScreenActionType
from app.core.auth import CurrentUser

logger = logging.getLogger(__name__)

EXPERIENCE_NOTICE = "Personal student experience, not verified fact."
FAQ_NOTICE = (
    "Official answers from government agencies, published on the Ministry of Education NISA "
    "site. Cite the answering agency and date. Questions were asked by school staff, so some "
    "answers talk about what schools must do."
)


@dataclass
class ToolContext:
    """Per-request state shared by the tools; the agent reads cards and screen actions after."""

    data: AssistantDataSource
    locale: Locale
    user: CurrentUser | None
    operations: OperationStore | None = None
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


def _faq_brief(faq: FaqRecord, locale: Locale) -> dict[str, Any]:
    return {
        "faq_id": faq.id,
        "question": faq.question.get(locale),
        "category": faq.category.get(locale),
        "posted_on": faq.posted_on,
    }


# Some answers run to 3,000+ characters; past this the model gets the opening and the link.
ANSWER_CHARS = 1500


def faq_detail(faq: FaqRecord, locale: Locale, clip: int | None = None) -> dict[str, Any]:
    answer = faq.answer.get(locale) or ""
    detail: dict[str, Any] = _faq_brief(faq, locale)
    # The warning goes before the answer, so nothing that shortens the block can lose it.
    if faq.review_kind and faq.review_note:
        detail["warning"] = {
            "kind": faq.review_kind,
            "note": faq.review_note.get(locale),
            "superseded_by": faq.superseded_by,
        }
    if clip is not None and len(answer) > clip:
        answer = answer[:clip].rstrip() + " …"
        detail["answer_clipped"] = "Only the opening is shown; get_official_faq has the rest."
    detail |= {
        "answer": answer,
        "answering_agency": faq.agency.get(locale),
        "source": faq.source.get(locale),
        "url": faq.url,
        "applies_to": list(faq.identities),
    }
    if locale == "en" and not faq.has_english:
        detail["note"] = "Only the Chinese original exists; translate it in your answer."
    return detail


def _experience_summary(experience: ExperienceRecord, locale: Locale) -> dict[str, Any]:
    return {
        "experience_id": experience.id,
        "kind": "student_experience",
        "topic": experience.topic_id,
        "identity_type": experience.identity_type,
        "summary": experience.summary.get(locale),
    }


EXCERPT_CHARS = 80


def _excerpt(text: str) -> str:
    text = " ".join(text.split())
    return text if len(text) <= EXCERPT_CHARS else text[:EXCERPT_CHARS].rstrip() + "…"


def experience_card(experience: ExperienceRecord, locale: Locale) -> ExperienceCard:
    """A student post as a card in the reader's language: title, opening words, category."""
    title = experience.title.get(locale) or experience.summary.get(locale)
    excerpt = _excerpt(experience.original_voice.get(locale))
    return ExperienceCard(
        experience_id=experience.id,
        reminder=experience.reminder.get(locale),
        title=title or excerpt,
        excerpt=excerpt,
        category=experience.category,
    )


def faq_card(faq: FaqRecord, locale: Locale) -> FaqCard:
    return FaqCard(
        faq_id=faq.id,
        question=faq.question.get(locale),
        category=faq.category.get(locale),
        answering_agency=faq.agency.get(locale),
        posted_on=faq.posted_on,
        excerpt=_excerpt(faq.answer.get(locale)),
        url=faq.url,
    )


# ---------- tools ----------


class SearchFaqArgs(ToolArgs):
    query: str = Field(min_length=1, max_length=200, description="Keywords, e.g. 工讀 or ARC")
    limit: int = Field(default=5, ge=1, le=10)


def search_official_faq(args: SearchFaqArgs, ctx: ToolContext) -> dict[str, Any]:
    found = ctx.data.search_faqs(args.query, args.limit)
    return {"count": len(found), "results": [_faq_brief(f, ctx.locale) for f in found]}


class GetFaqArgs(ToolArgs):
    faq_id: str = Field(min_length=1, max_length=100)


def get_official_faq(args: GetFaqArgs, ctx: ToolContext) -> dict[str, Any]:
    faq = ctx.data.get_faq(args.faq_id)
    if faq is None:
        return {"found": False, "faq_id": args.faq_id}
    ctx.cards[f"faq:{faq.id}"] = faq_card(faq, ctx.locale)
    return {"found": True, "notice": FAQ_NOTICE, "faq": faq_detail(faq, ctx.locale)}


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
    ctx.cards[f"experience:{experience.id}"] = experience_card(experience, ctx.locale)
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


class OpenScreenArgs(ToolArgs):
    screen: ScreenActionType
    target_id: str | None = Field(
        default=None,
        max_length=100,
        description="faq_id for open_faq, experience_id for open_experience",
    )
    topic: TopicId | None = Field(default=None, description="Optional filter for open_explore")


def open_screen(args: OpenScreenArgs, ctx: ToolContext) -> dict[str, Any]:
    if args.screen in ("open_action", "open_progress"):
        raise ToolError("Procedure guides were replaced by the official Q&A; use open_faq")
    if args.screen == "open_faq":
        if not args.target_id or ctx.data.get_faq(args.target_id) is None:
            raise ToolError("open_faq needs an existing faq_id from search_official_faq")
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


class SemanticSearchArgs(ToolArgs):
    query: str = Field(min_length=1, max_length=300, description="The user's question in words")
    limit: int = Field(default=4, ge=1, le=8)


def semantic_search(args: SemanticSearchArgs, ctx: ToolContext) -> dict[str, Any]:
    found = ctx.data.semantic_search(args.query, args.limit)
    if found is None:
        raise ToolError("Semantic search is unavailable right now; use the keyword tools.")
    # Official answers go through the same record as everywhere else, so review warnings
    # (superseded, time_limited) reach the model and outdated ones come last.
    faqs = [ctx.data.get_faq(f["faq_id"]) for f in found.pop("official_faqs", None) or []]
    faqs = [f for f in faqs if f is not None]
    found["official_faqs"] = [
        faq_detail(f, ctx.locale, clip=ANSWER_CHARS)
        for f in [f for f in faqs if not f.demoted] + [f for f in faqs if f.demoted]
    ]
    return {
        **found,
        "notice": "official_faqs are government answers: cite the answering agency and date. "
        "Official passages: cite title, publisher and date. Student content is unverified "
        "personal experience, ranked after the official answers; if it disagrees with them, "
        "follow the official answer and suggest checking with the school.",
    }


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


TOOLS: list[Tool] = [
    Tool(
        "search_official_faq",
        "Find official questions and answers from the Ministry of Education NISA site by keyword "
        "(visa and ARC, part-time work permits, health insurance, scholarships, working in Taiwan "
        "after graduation...). Answered by government agencies.",
        SearchFaqArgs,
        search_official_faq,
    ),
    Tool(
        "get_official_faq",
        "Read one official question in full: the answer, answering agency, date, source and link.",
        GetFaqArgs,
        get_official_faq,
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
        "open_screen",
        "Ask the app to navigate after your answer. Only use when the user wants to go somewhere; "
        "ids must come from earlier tool results.",
        OpenScreenArgs,
        open_screen,
    ),
    Tool(
        "semantic_search",
        "Search by meaning across the official Q&A, official source documents and public student "
        "content, for questions keyword search misses. Returns citations.",
        SemanticSearchArgs,
        semantic_search,
    ),
    Tool(
        "search_app_help",
        "Explain how to use the Culture Bridge app: tabs, screens, buttons, sharing, privacy, "
        "what the assistant can do. Never use it for facts about visas, work, insurance or other "
        "rules.",
        SearchAppHelpArgs,
        search_app_help,
    ),
]


def default_registry() -> ToolRegistry:
    return ToolRegistry(TOOLS)
