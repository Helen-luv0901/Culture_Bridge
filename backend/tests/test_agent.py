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
    # Search results (if any) come first; the screen context sits right above the question.
    assert text.endswith(
        '[screen context: {"route": "/actions/arc", "action_id": "arc"}]\n這個流程要帶什麼？'
    )


def test_memory_trims_at_user_turns():
    store = ConversationStore(max_exchanges=2)
    turns = []
    for i in range(4):
        turns += [UserTurn(f"q{i}"), call("search_actions", query="x"), ModelTurn(text=f"a{i}")]
    store.save("o", "c", turns)
    kept = store.load("o", "c")
    assert kept[0] == UserTurn("q2") and len(kept) == 6


def test_searches_run_up_front_so_one_model_call_answers(make_assistant):
    llm = ScriptedLLM(answer("依據「申請工作證」流程卡（已驗證）……"))
    reply = make_assistant(llm).reply(ask("工作證要怎麼申請？"), USER)

    assert len(llm.calls) == 1 and reply.tools_used == []
    message = llm.calls[0]["history"][-1].text
    assert message.startswith("[Search results for this message")
    assert message.endswith("工作證要怎麼申請？")
    assert '"action_id": "work-permit"' in message and '"steps"' in message
    # The answer names the procedure, so its card shows as if get_action had run.
    assert [c.model_dump()["action_id"] for c in reply.cards] == ["work-permit"]


def test_prefetched_procedures_not_named_get_no_card(make_assistant):
    reply = make_assistant(ScriptedLLM(answer("目前沒有相關資料。"))).reply(
        ask("工作證要怎麼申請？"), USER
    )
    assert reply.cards == []


def test_nothing_found_leaves_the_message_as_written(make_assistant):
    llm = ScriptedLLM(answer("hi"))
    make_assistant(llm).reply(ask("zzzz qqqq"), USER)
    assert llm.calls[0]["history"] == [UserTurn("zzzz qqqq")]


def test_thinking_level_maps_to_gemini_config():
    from app.assistant.gemini import thinking_config

    assert thinking_config("") is None
    assert thinking_config("low").thinking_level.value == "LOW"
    assert thinking_config("minimal").thinking_level.value == "MINIMAL"


def test_answers_show_the_closest_student_posts(make_assistant):
    reply = make_assistant(ScriptedLLM(answer("租屋前先看合約。"))).reply(
        ask("租房子要注意什麼？"), USER
    )
    posts = [c.model_dump() for c in reply.cards if c.type == "experience"]
    assert 1 <= len(posts) <= 2
    assert posts[0]["experience_id"] == "first-rental"
    assert posts[0]["title"] and posts[0]["excerpt"]


def test_at_most_two_posts_and_none_when_nothing_matches(make_assistant):
    reply = make_assistant(ScriptedLLM(answer("ok"))).reply(ask("居留證 租屋 夜市 教授"), USER)
    assert len([c for c in reply.cards if c.type == "experience"]) <= 2
    nothing = make_assistant(ScriptedLLM(answer("hi"))).reply(ask("zzzz qqqq"), USER)
    assert [c for c in nothing.cards if c.type == "experience"] == []


def test_fallback_answers_show_no_posts(make_assistant):
    reply = make_assistant(ScriptedLLM(LLMError("quota"))).reply(ask("租房子要注意什麼？"), USER)
    assert reply.fallback is True and reply.cards == []
