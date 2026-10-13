"""Provider-neutral conversation turns and the model interface the agent loop talks to."""

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    parameters: dict[str, Any]


@dataclass(frozen=True)
class ToolCall:
    name: str
    args: dict[str, Any]
    id: str | None = None


@dataclass(frozen=True)
class ToolResult:
    name: str
    result: dict[str, Any]
    id: str | None = None


@dataclass(frozen=True)
class UserTurn:
    text: str


@dataclass(frozen=True)
class ModelTurn:
    text: str = ""
    tool_calls: tuple[ToolCall, ...] = ()
    # Provider-native message, re-sent verbatim so data such as Gemini thought signatures survives.
    raw: Any = field(default=None, compare=False)


@dataclass(frozen=True)
class ToolResultsTurn:
    results: tuple[ToolResult, ...]


Turn = UserTurn | ModelTurn | ToolResultsTurn


class LLMError(Exception):
    """The model could not produce a turn (network, quota, safety block, empty reply)."""


class LLM(Protocol):
    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn: ...


class UnavailableLLM:
    """Used when no Gemini key is configured, so the API still answers with the safe fallback."""

    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn:
        raise LLMError("GEMINI_API_KEY is not configured")
