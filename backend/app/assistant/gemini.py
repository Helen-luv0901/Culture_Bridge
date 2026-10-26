"""Gemini adapter: manual function calling so the agent loop owns every tool execution."""

import logging

from google import genai
from google.genai import types

from app.ai.calls import call_gemini
from app.assistant.llm import (
    LLMError,
    ModelTurn,
    ToolCall,
    ToolResultsTurn,
    ToolSpec,
    Turn,
    UserTurn,
)

logger = logging.getLogger(__name__)


def thinking_config(level: str) -> types.ThinkingConfig | None:
    """Less thinking answers much faster; the assistant mostly reads search results it is given."""
    if not level:
        return None
    return types.ThinkingConfig(thinking_level=types.ThinkingLevel(level.upper()))


class GeminiLLM:
    def __init__(
        self, api_key: str, model: str, timeout_seconds: float, thinking_level: str = ""
    ) -> None:
        self._client = genai.Client(
            api_key=api_key,
            http_options=types.HttpOptions(timeout=int(timeout_seconds * 1000)),
        )
        self._model = model
        self._thinking = thinking_config(thinking_level)

    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn:
        config = types.GenerateContentConfig(
            system_instruction=system,
            temperature=0.2,
            tools=[types.Tool(function_declarations=[to_declaration(t) for t in tools])],
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            thinking_config=self._thinking,
        )
        try:
            response = call_gemini(
                lambda: self._client.models.generate_content(
                    model=self._model, contents=to_contents(history), config=config
                )
            )
        except Exception as exc:  # SDK errors or the daily budget; all mean "no answer".
            logger.warning("Gemini request failed: %s", exc)
            raise LLMError(str(exc)) from exc
        return from_response(response)


def to_declaration(tool: ToolSpec) -> types.FunctionDeclaration:
    return types.FunctionDeclaration(
        name=tool.name,
        description=tool.description,
        parameters_json_schema=tool.parameters,
    )


def to_contents(history: list[Turn]) -> list[types.Content]:
    contents: list[types.Content] = []
    for turn in history:
        if isinstance(turn, UserTurn):
            contents.append(
                types.Content(role="user", parts=[types.Part.from_text(text=turn.text)])
            )
        elif isinstance(turn, ToolResultsTurn):
            parts = [
                types.Part(
                    function_response=types.FunctionResponse(
                        id=r.id, name=r.name, response=r.result
                    )
                )
                for r in turn.results
            ]
            contents.append(types.Content(role="user", parts=parts))
        elif isinstance(turn.raw, types.Content):
            contents.append(turn.raw)
        else:
            parts = [types.Part.from_text(text=turn.text)] if turn.text else []
            parts += [
                types.Part(function_call=types.FunctionCall(id=c.id, name=c.name, args=c.args))
                for c in turn.tool_calls
            ]
            contents.append(types.Content(role="model", parts=parts))
    return contents


def from_response(response: types.GenerateContentResponse) -> ModelTurn:
    candidate = response.candidates[0] if response.candidates else None
    content = candidate.content if candidate else None
    if content is None or not content.parts:
        reason = candidate.finish_reason if candidate else response.prompt_feedback
        raise LLMError(f"Gemini returned no content ({reason})")
    calls = tuple(
        ToolCall(
            id=p.function_call.id,
            name=p.function_call.name or "",
            args=dict(p.function_call.args or {}),
        )
        for p in content.parts
        if p.function_call
    )
    text = "".join(p.text for p in content.parts if p.text and not p.thought)
    return ModelTurn(text=text.strip(), tool_calls=calls, raw=content)
