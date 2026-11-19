"""Groq (OpenAI-compatible) as the assistant's first model, Gemini as the backup.

Production 2026-11-19: Gemini's free tier took 10-20 s per answer all evening and every message
failed; Groq's free tier answers in about a second. No network here: httpx is mocked.
"""

import json

import httpx
import pytest

from app.assistant.llm import (
    LLMError,
    ModelTurn,
    ToolCall,
    ToolResult,
    ToolResultsTurn,
    ToolSpec,
    UserTurn,
)
from app.assistant.openai_compat import FallbackLLM, OpenAICompatibleLLM, to_messages

TOOLS = [ToolSpec("search_official_faq", "Search", {"type": "object", "properties": {}})]


def _llm(handler) -> OpenAICompatibleLLM:
    llm = OpenAICompatibleLLM("key", "openai/gpt-oss-120b", "https://groq.test/v1", 5, "low")
    llm._client = httpx.Client(
        base_url="https://groq.test/v1", transport=httpx.MockTransport(handler)
    )
    return llm


def test_a_text_answer_and_the_request_it_came_from():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"message": {"content": " 你好 "}}]})

    turn = _llm(handler).generate("system rules", [UserTurn("學生證不見了")], TOOLS)
    assert turn == ModelTurn(text="你好")
    assert seen["model"] == "openai/gpt-oss-120b"
    assert seen["messages"][0] == {"role": "system", "content": "system rules"}
    assert seen["messages"][1] == {"role": "user", "content": "學生證不見了"}
    assert seen["tools"][0]["function"]["name"] == "search_official_faq"
    assert seen["reasoning_effort"] == "low"


def test_tool_calls_come_back_as_neutral_calls():
    def handler(request: httpx.Request) -> httpx.Response:
        call = {
            "id": "call_1",
            "type": "function",
            "function": {"name": "search_official_faq", "arguments": '{"query": "居留證"}'},
        }
        return httpx.Response(
            200, json={"choices": [{"message": {"content": None, "tool_calls": [call]}}]}
        )

    turn = _llm(handler).generate("s", [UserTurn("q")], TOOLS)
    assert turn.tool_calls == (
        ToolCall(id="call_1", name="search_official_faq", args={"query": "居留證"}),
    )


def test_errors_and_empty_answers_are_llm_errors():
    for response in (
        httpx.Response(429, text="rate limited"),
        httpx.Response(200, json={"choices": [{"message": {"content": ""}}]}),
        httpx.Response(200, json={"choices": []}),
    ):
        with pytest.raises(LLMError):
            _llm(lambda request, r=response: r).generate("s", [UserTurn("q")], TOOLS)


def test_history_from_gemini_without_ids_still_pairs_calls_and_results():
    history = [
        UserTurn("q"),
        ModelTurn(tool_calls=(ToolCall(name="search_official_faq", args={"query": "x"}),)),
        ToolResultsTurn((ToolResult(name="search_official_faq", result={"count": 0}),)),
    ]
    messages = to_messages(history)
    call_id = messages[1]["tool_calls"][0]["id"]
    assert messages[2] == {
        "role": "tool",
        "tool_call_id": call_id,
        "content": json.dumps({"count": 0}),
    }


class _Fails:
    def generate(self, system, history, tools):
        raise LLMError("429")


class _Answers:
    def __init__(self, text: str) -> None:
        self.text = text
        self.calls = 0

    def generate(self, system, history, tools):
        self.calls += 1
        return ModelTurn(text=self.text)


def test_gemini_answers_when_groq_cannot():
    gemini = _Answers("from gemini")
    assert FallbackLLM(_Fails(), gemini).generate("s", [], []).text == "from gemini"


def test_gemini_is_not_asked_when_groq_answers():
    groq, gemini = _Answers("from groq"), _Answers("from gemini")
    assert FallbackLLM(groq, gemini).generate("s", [], []).text == "from groq"
    assert gemini.calls == 0


def test_the_assistant_uses_groq_first_only_when_a_key_is_set(monkeypatch):
    from app.api import assistant as assistant_api
    from app.core.config import get_settings

    monkeypatch.setenv("GEMINI_API_KEY", "g")
    for key, expected in (("", False), ("groq-key", True)):
        monkeypatch.setenv("GROQ_API_KEY", key)
        get_settings.cache_clear()
        assistant_api.get_services.cache_clear()
        try:
            llm = assistant_api.get_services().assistant._llm._llm
            assert isinstance(llm, FallbackLLM) is expected
        finally:
            get_settings.cache_clear()
            assistant_api.get_services.cache_clear()
