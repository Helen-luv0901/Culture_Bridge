"""Models behind an OpenAI-compatible Chat Completions API (Groq), and trying a second model when
the first fails.

Groq's free tier answers in about a second, where Gemini's free tier took 10-20 s on busy
evenings (2026-11-19, every message failed). So the assistant asks Groq first and falls back to
Gemini (FallbackLLM): either can be rate-limited or down, and one answering is enough.
"""

import json
import logging
from typing import Any

import httpx

from app.assistant.llm import (
    LLM,
    LLMError,
    ModelTurn,
    ToolCall,
    ToolResultsTurn,
    ToolSpec,
    Turn,
    UserTurn,
)

logger = logging.getLogger(__name__)


class OpenAICompatibleLLM:
    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str,
        timeout_seconds: float,
        reasoning_effort: str = "",
        name: str = "Groq",
    ) -> None:
        self._client = httpx.Client(
            base_url=base_url.rstrip("/"),
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=timeout_seconds,
        )
        self._model = model
        self._reasoning = reasoning_effort
        self._name = name

    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn:
        body: dict[str, Any] = {
            "model": self._model,
            "messages": [{"role": "system", "content": system}, *to_messages(history)],
            "temperature": 0.2,
        }
        if tools:
            body["tools"] = [to_tool(t) for t in tools]
        if self._reasoning:
            body["reasoning_effort"] = self._reasoning
        try:
            response = self._client.post("/chat/completions", json=body)
        except httpx.HTTPError as exc:
            logger.warning("%s request failed: %s", self._name, exc)
            raise LLMError(f"{self._name}: {exc}") from exc
        if response.status_code != 200:
            detail = response.text[:300]
            logger.warning("%s answered %s: %s", self._name, response.status_code, detail)
            raise LLMError(f"{self._name} {response.status_code}: {detail}")
        return from_choice(response.json(), self._name)


def to_tool(tool: ToolSpec) -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.parameters,
        },
    }


def to_messages(history: list[Turn]) -> list[dict[str, Any]]:
    """The provider-neutral history as Chat Completions messages. Every tool call needs an id
    and every result the id of its call; a turn from Gemini may have none, so ids are made up
    in order and results are matched to calls of the same name."""
    messages: list[dict[str, Any]] = []
    pending: list[tuple[str, str]] = []  # (call id, tool name) still waiting for a result
    for index, turn in enumerate(history):
        if isinstance(turn, UserTurn):
            messages.append({"role": "user", "content": turn.text})
        elif isinstance(turn, ToolResultsTurn):
            for result in turn.results:
                call_id = result.id or _claim(pending, result.name) or f"call_{index}"
                if result.id:
                    pending[:] = [p for p in pending if p[0] != result.id]
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": call_id,
                        "content": json.dumps(result.result, ensure_ascii=False, default=str),
                    }
                )
        else:
            message: dict[str, Any] = {"role": "assistant", "content": turn.text or None}
            if turn.tool_calls:
                calls = []
                for position, call in enumerate(turn.tool_calls):
                    call_id = call.id or f"call_{index}_{position}"
                    pending.append((call_id, call.name))
                    calls.append(
                        {
                            "id": call_id,
                            "type": "function",
                            "function": {
                                "name": call.name,
                                "arguments": json.dumps(call.args, ensure_ascii=False),
                            },
                        }
                    )
                message["tool_calls"] = calls
            messages.append(message)
    return messages


def _claim(pending: list[tuple[str, str]], name: str) -> str | None:
    for position, (call_id, call_name) in enumerate(pending):
        if call_name == name:
            del pending[position]
            return call_id
    return None


def from_choice(body: dict[str, Any], name: str = "model") -> ModelTurn:
    choices = body.get("choices") or []
    message = (choices[0] or {}).get("message") if choices else None
    if not message:
        raise LLMError(f"{name} returned no message")
    calls = []
    for call in message.get("tool_calls") or []:
        function = call.get("function") or {}
        try:
            args = json.loads(function.get("arguments") or "{}")
        except json.JSONDecodeError as exc:
            raise LLMError(f"{name} sent unreadable tool arguments") from exc
        calls.append(
            ToolCall(
                id=call.get("id"),
                name=function.get("name") or "",
                args=args if isinstance(args, dict) else {},
            )
        )
    text = (message.get("content") or "").strip()
    if not text and not calls:
        raise LLMError(f"{name} returned an empty answer")
    return ModelTurn(text=text, tool_calls=tuple(calls))


class FallbackLLM:
    """Ask `first`; when it cannot answer (rate limit, outage, bad reply), ask `second`."""

    def __init__(self, first: LLM, second: LLM, first_name: str = "Groq") -> None:
        self._first = first
        self._second = second
        self._first_name = first_name

    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn:
        try:
            return self._first.generate(system, history, tools)
        except LLMError as exc:
            logger.warning("%s could not answer (%s); asking Gemini", self._first_name, exc)
            return self._second.generate(system, history, tools)
