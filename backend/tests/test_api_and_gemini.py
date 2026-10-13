import pytest
from fastapi.testclient import TestClient
from google.genai import types

from app.api.assistant import get_assistant
from app.assistant.gemini import from_response, to_contents
from app.assistant.llm import LLMError, ModelTurn, ToolCall, ToolResult, ToolResultsTurn, UserTurn
from app.main import app
from tests.conftest import ScriptedLLM, answer, call


@pytest.fixture
def client(make_assistant):
    def use(llm):
        app.dependency_overrides[get_assistant] = lambda: make_assistant(llm)
        return TestClient(app)

    yield use
    app.dependency_overrides.clear()


def test_post_message(client):
    llm = ScriptedLLM(call("get_action", action_id="certificate"), answer("在學證明……"))
    res = client(llm).post("/assistant/message", json={"message": "在學證明", "locale": "zh-Hant"})
    assert res.status_code == 200
    body = res.json()
    assert body["text"] == "在學證明……"
    assert body["cards"][0]["type"] == "action"
    assert body["cards"][0]["verification_status"] == "verified"
    assert body["fallback"] is False
    assert body["conversation_id"]


def test_dev_user_header_reaches_tools(client, data):
    llm = ScriptedLLM(call("get_my_progress"), answer("沒有進行中的流程。"))
    client(llm).post(
        "/assistant/message", json={"message": "我的進度"}, headers={"X-Dev-User-Id": "u9"}
    )
    result = llm.calls[1]["history"][-1].results[0].result
    assert result == {"count": 0, "results": []}


def test_validation_rejects_bad_input(client):
    c = client(ScriptedLLM())
    assert c.post("/assistant/message", json={"message": ""}).status_code == 422
    assert c.post("/assistant/message", json={"message": "hi", "locale": "ja"}).status_code == 422


def test_without_api_key_answers_with_fallback(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    from app.core.config import get_settings

    get_settings.cache_clear()
    get_assistant.cache_clear()
    try:
        res = TestClient(app).post("/assistant/message", json={"message": "hi", "locale": "en"})
    finally:
        get_settings.cache_clear()
        get_assistant.cache_clear()
    assert res.status_code == 200
    assert res.json()["fallback"] is True


def test_clear_endpoint(client):
    assert client(ScriptedLLM()).delete("/assistant/conversations/abc").status_code == 204


def test_gemini_history_conversion_keeps_ids_and_raw_content():
    raw = types.Content(
        role="model",
        parts=[
            types.Part(
                function_call=types.FunctionCall(
                    id="x1", name="get_action", args={"action_id": "arc"}
                ),
                thought_signature=b"sig",
            )
        ],
    )
    contents = to_contents(
        [
            UserTurn("ARC?"),
            ModelTurn(tool_calls=(ToolCall(id="x1", name="get_action", args={}),), raw=raw),
            ToolResultsTurn((ToolResult(id="x1", name="get_action", result={"found": True}),)),
            ModelTurn(text="done"),
        ]
    )
    assert [c.role for c in contents] == ["user", "model", "user", "model"]
    assert contents[1] is raw  # thought signature preserved
    response = contents[2].parts[0].function_response
    assert (response.id, response.name, response.response) == ("x1", "get_action", {"found": True})
    assert contents[3].parts[0].text == "done"


def test_gemini_response_parsing():
    response = types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    role="model",
                    parts=[
                        types.Part(text="thinking...", thought=True),
                        types.Part(text="Let me check. "),
                        types.Part(
                            function_call=types.FunctionCall(
                                id="c1", name="search_actions", args={"query": "ARC"}
                            )
                        ),
                    ],
                )
            )
        ]
    )
    turn = from_response(response)
    assert turn.text == "Let me check."
    assert turn.tool_calls == (ToolCall(id="c1", name="search_actions", args={"query": "ARC"}),)
    assert turn.raw is response.candidates[0].content


def test_gemini_empty_response_is_error():
    with pytest.raises(LLMError):
        from_response(types.GenerateContentResponse(candidates=[]))
