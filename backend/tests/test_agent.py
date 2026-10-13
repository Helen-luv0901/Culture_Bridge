from app.assistant.llm import LLMError, ModelTurn, ToolCall, ToolResultsTurn, UserTurn
from app.assistant.memory import ConversationStore
from app.assistant.schemas import AssistantMessageRequest, ScreenContext
from app.core.auth import CurrentUser
from tests.conftest import ScriptedLLM, answer, call

USER = CurrentUser(id="u1")


def ask(message: str, **kwargs) -> AssistantMessageRequest:
    return AssistantMessageRequest(message=message, **kwargs)


def test_search_then_detail_then_answer(make_assistant):
    llm = ScriptedLLM(
        call("search_actions", query="工作證"),
        call("get_action", action_id="work-permit"),
        answer("依據「申請工作證」流程卡（已驗證，2026-08-16）……"),
    )
    reply = make_assistant(llm).reply(ask("工作證要怎麼申請？"), USER)

    assert reply.fallback is False
    assert reply.tools_used == ["search_actions", "get_action"]
    assert [c.model_dump()["action_id"] for c in reply.cards] == ["work-permit"]
    assert reply.cards[0].recent_success_count == 18

    # The model saw each tool result paired with its call id before answering.
    results = llm.calls[2]["history"][-1]
    assert isinstance(results, ToolResultsTurn)
    assert results.results[0].id == "call-get_action"
    assert results.results[0].result["action"]["title"] == "申請工作證"


def test_system_prompt_follows_locale(make_assistant):
    llm = ScriptedLLM(answer("Hi"))
    make_assistant(llm).reply(ask("hi", locale="en"), None)
    assert "Reply in English." in llm.calls[0]["system"]
    assert "Today is" in llm.calls[0]["system"]
    assert {t.name for t in llm.calls[0]["tools"]} >= {"search_actions", "open_screen"}


def test_parallel_calls_all_get_results(make_assistant):
    llm = ScriptedLLM(
        ModelTurn(
            tool_calls=(
                ToolCall(id="a", name="get_action", args={"action_id": "arc"}),
                ToolCall(id="b", name="get_experience", args={"experience_id": "first-rental"}),
            )
        ),
        answer("ok"),
    )
    reply = make_assistant(llm).reply(ask("ARC 和租屋"), USER)
    results = llm.calls[1]["history"][-1].results
    assert [r.id for r in results] == ["a", "b"]
    assert {c.type for c in reply.cards} == {"action", "experience"}


def test_too_many_calls_in_one_round_are_refused(make_assistant):
    calls = tuple(
        ToolCall(id=str(i), name="search_actions", args={"query": "arc"}) for i in range(8)
    )
    llm = ScriptedLLM(ModelTurn(tool_calls=calls), answer("ok"))
    make_assistant(llm).reply(ask("x"), USER)
    results = llm.calls[1]["history"][-1].results
    assert len(results) == 8
    assert "error" in results[-1].result and "error" not in results[0].result


def test_model_error_returns_fallback_and_forgets_exchange(make_assistant):
    memory = ConversationStore()
    llm = ScriptedLLM(call("search_actions", query="arc"), LLMError("quota"))
    reply = make_assistant(llm, memory=memory).reply(ask("ARC?", conversation_id="c1"), USER)

    assert reply.fallback is True
    assert reply.cards == []
    assert "暫時無法回答" in reply.text
    assert memory.load("user:u1", "c1") == []


def test_empty_answer_is_fallback(make_assistant):
    reply = make_assistant(ScriptedLLM(answer(""))).reply(ask("hi", locale="en"), None)
    assert reply.fallback is True
    assert reply.text.startswith("The assistant can't answer")


def test_tool_round_limit(make_assistant):
    llm = ScriptedLLM(*[call("search_actions", query="arc") for _ in range(3)])
    reply = make_assistant(llm, max_tool_rounds=2).reply(ask("loop"), USER)
    assert reply.fallback is True
    assert reply.tools_used == ["search_actions", "search_actions"]
    assert len(llm.calls) == 3


def test_screen_action_comes_from_validated_tool_call(make_assistant):
    llm = ScriptedLLM(
        call("open_screen", screen="open_progress", target_id="arc"),
        answer("已幫你打開 ARC 進度。"),
    )
    reply = make_assistant(llm).reply(ask("帶我去 ARC 進度"), USER)
    assert [a.model_dump() for a in reply.screen_actions] == [
        {"type": "open_progress", "target_id": "arc", "topic": None}
    ]


def test_memory_carries_follow_ups_and_is_per_account(make_assistant):
    assistant = make_assistant(
        ScriptedLLM(
            call("search_actions", query="證明"),
            answer("找到：1. 申請在學證明 2. 申請工作證"),
            answer("第二個是申請工作證。"),
            answer("你想問哪個流程？"),
        )
    )
    first = assistant.reply(ask("有哪些證明要辦？"), USER)
    llm = assistant._llm

    assistant.reply(ask("第二個要多久？", conversation_id=first.conversation_id), USER)
    follow_up_history = llm.calls[2]["history"]
    assert isinstance(follow_up_history[0], UserTurn)
    assert any(isinstance(t, ToolResultsTurn) for t in follow_up_history)
    assert follow_up_history[-1] == UserTurn("第二個要多久？")

    # Another account reusing the id gets a fresh conversation, not u1's history.
    assistant.reply(ask("第二個？", conversation_id=first.conversation_id), CurrentUser(id="u2"))
    assert llm.calls[3]["history"] == [UserTurn("第二個？")]


def test_clear_conversation(make_assistant):
    assistant = make_assistant(ScriptedLLM(answer("a"), answer("b")))
    first = assistant.reply(ask("hi"), USER)
    assistant.clear(first.conversation_id, USER)
    assistant.reply(ask("again", conversation_id=first.conversation_id), USER)
    assert assistant._llm.calls[1]["history"] == [UserTurn("again")]


def test_screen_context_is_passed_as_data(make_assistant):
    llm = ScriptedLLM(answer("ok"))
    make_assistant(llm).reply(
        ask("這個流程要帶什麼？", screen=ScreenContext(route="/actions/arc", action_id="arc")),
        USER,
    )
    text = llm.calls[0]["history"][-1].text
    assert text.startswith('[screen context: {"route": "/actions/arc", "action_id": "arc"}]')
    assert text.endswith("這個流程要帶什麼？")


def test_memory_trims_at_user_turns():
    store = ConversationStore(max_exchanges=2)
    turns = []
    for i in range(4):
        turns += [UserTurn(f"q{i}"), call("search_actions", query="x"), ModelTurn(text=f"a{i}")]
    store.save("o", "c", turns)
    kept = store.load("o", "c")
    assert kept[0] == UserTurn("q2") and len(kept) == 6
