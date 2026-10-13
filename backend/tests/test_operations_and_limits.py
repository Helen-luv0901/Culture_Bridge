from datetime import UTC, date, datetime, timedelta

import pytest

from app.assistant.limits import BudgetedLLM, DailyBudget, RateLimited, UsageLimiter
from app.assistant.llm import LLMError
from app.assistant.operations import DemoExecutionWriter, OperationError, OperationService
from app.assistant.schemas import AssistantMessageRequest
from app.core.auth import CurrentUser
from tests.conftest import ScriptedLLM, answer, call

ALICE = CurrentUser(id="alice")
BOB = CurrentUser(id="bob")


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 10, 13, 4, 0, tzinfo=UTC)

    def __call__(self) -> datetime:
        return self.now


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def service(data, clock) -> OperationService:
    return OperationService(data=data, writer=DemoExecutionWriter(data), clock=clock)


# ---------- pending operations ----------


def test_confirm_writes_once(service, data):
    op = service.propose_start_action(ALICE, "arc", "開始辦理「ARC」")
    assert data.get_in_progress("alice") == []

    confirmed = service.confirm(op.id, ALICE)
    again = service.confirm(op.id, ALICE)

    assert confirmed.status == again.status == "confirmed"
    assert again.result == confirmed.result
    progress = data.get_in_progress("alice")
    assert len(progress) == 1 and progress[0].action_id == "arc"
    assert all(step.state == "pending" for step in progress[0].steps)


def test_only_owner_can_see_or_confirm(service):
    op = service.propose_start_action(ALICE, "arc", "s")
    for action in (service.get, service.confirm, service.cancel):
        with pytest.raises(OperationError) as exc:
            action(op.id, BOB)
        assert (exc.value.code, exc.value.status_code) == ("operation_not_found", 404)
        with pytest.raises(OperationError) as exc:
            action(op.id, None)
        assert exc.value.status_code == 401
    assert service.get(op.id, ALICE).status == "pending"


def test_expires_after_five_minutes(service, clock, data):
    op = service.propose_start_action(ALICE, "arc", "s")
    clock.now += timedelta(minutes=4, seconds=59)
    assert service.get(op.id, ALICE).status == "pending"
    clock.now += timedelta(seconds=1)
    with pytest.raises(OperationError) as exc:
        service.confirm(op.id, ALICE)
    assert exc.value.code == "operation_expired"
    assert data.get_in_progress("alice") == []


def test_cancel_then_confirm_is_rejected(service, data):
    op = service.propose_start_action(ALICE, "arc", "s")
    assert service.cancel(op.id, ALICE).status == "cancelled"
    assert service.cancel(op.id, ALICE).status == "cancelled"
    with pytest.raises(OperationError) as exc:
        service.confirm(op.id, ALICE)
    assert (exc.value.code, exc.value.status_code) == ("operation_cancelled", 409)
    assert data.get_in_progress("alice") == []


def test_confirm_rechecks_target(service, data):
    op = service.propose_start_action(ALICE, "arc", "s")
    del data.actions["arc"]  # e.g. archived between proposal and confirmation
    result = service.confirm(op.id, ALICE)
    assert result.status == "failed"
    assert result.result == {"reason": "action_unavailable"}


def test_starting_twice_reuses_execution(service, data):
    first = service.confirm(service.propose_start_action(ALICE, "arc", "s").id, ALICE)
    second = service.confirm(service.propose_start_action(ALICE, "arc", "s").id, ALICE)
    assert second.result == {"execution_id": first.result["execution_id"], "already_started": True}
    assert len(data.get_in_progress("alice")) == 1


def test_assistant_proposes_but_does_not_write(make_assistant, data):
    llm = ScriptedLLM(
        call("propose_start_action", action_id="bank"),
        answer("請在 5 分鐘內按「確認」開始辦理。"),
    )
    reply = make_assistant(llm).reply(AssistantMessageRequest(message="幫我開始辦銀行帳戶"), ALICE)

    tool_result = llm.calls[1]["history"][-1].results[0].result
    assert tool_result["status"] == "awaiting_user_confirmation"
    [op] = reply.pending_operations
    assert (op.type, op.target_id, op.status) == ("start_action", "bank", "pending")
    assert op.summary == "開始辦理「開銀行帳戶」"
    assert data.get_in_progress("alice") == []


def test_guest_cannot_propose(make_assistant):
    llm = ScriptedLLM(call("propose_start_action", action_id="bank"), answer("請先登入。"))
    reply = make_assistant(llm).reply(AssistantMessageRequest(message="開始"), None)
    assert llm.calls[1]["history"][-1].results[0].result == {"requires_login": True}
    assert reply.pending_operations == []


def test_operation_endpoints(client):
    llm = ScriptedLLM(call("propose_start_action", action_id="arc"), answer("請確認。"))
    c = client(llm)
    alice = {"X-Dev-User-Id": "alice"}
    reply = c.post("/api/assistant/message", json={"message": "開始 ARC"}, headers=alice).json()
    op_id = reply["pending_operations"][0]["id"]

    assert c.get(f"/api/assistant/operations/{op_id}", headers=alice).json()["status"] == "pending"
    other = c.post(f"/api/assistant/operations/{op_id}/confirm", headers={"X-Dev-User-Id": "bob"})
    assert other.status_code == 404 and other.json()["detail"] == {"code": "operation_not_found"}
    assert c.post(f"/api/assistant/operations/{op_id}/confirm").status_code == 401

    confirmed = c.post(f"/api/assistant/operations/{op_id}/confirm", headers=alice).json()
    assert confirmed["status"] == "confirmed" and confirmed["result"]["execution_id"]
    cancel = c.post(f"/api/assistant/operations/{op_id}/cancel", headers=alice)
    assert cancel.status_code == 409 and cancel.json()["detail"] == {"code": "operation_confirmed"}


# ---------- access control and limits ----------


def test_guests_blocked_when_not_allowed(client):
    c = client(ScriptedLLM(answer("hi")), allow_guests=False)
    res = c.post("/api/assistant/message", json={"message": "hi"})
    assert res.status_code == 401 and res.json()["detail"] == {"code": "login_required"}
    ok = c.post("/api/assistant/message", json={"message": "hi"}, headers={"X-Dev-User-Id": "u1"})
    assert ok.status_code == 200


def test_rate_limit_returns_429_with_retry_after(client):
    c = client(
        ScriptedLLM(answer("a"), answer("b")), limiter=UsageLimiter(per_minute=2, per_day=50)
    )
    headers = {"X-Dev-User-Id": "u1"}
    for _ in range(2):
        assert (
            c.post("/api/assistant/message", json={"message": "x"}, headers=headers).status_code
            == 200
        )
    res = c.post("/api/assistant/message", json={"message": "x"}, headers=headers)
    assert res.status_code == 429
    assert res.json()["detail"] == {"code": "rate_limited"}
    assert int(res.headers["Retry-After"]) > 0


def test_limiter_window_and_daily_cap():
    t = [0.0]
    day = [date(2026, 10, 13)]
    limiter = UsageLimiter(per_minute=2, per_day=3, monotonic=lambda: t[0], today=lambda: day[0])
    limiter.check("a")
    limiter.check("a")
    with pytest.raises(RateLimited, match="rate_limited"):
        limiter.check("a")
    limiter.check("b")  # other callers are unaffected

    t[0] = 60.0
    limiter.check("a")
    t[0] = 200.0
    with pytest.raises(RateLimited, match="daily_limit_reached"):
        limiter.check("a")

    day[0] = date(2026, 10, 14)
    limiter.check("a")


def test_daily_llm_budget_turns_into_fallback():
    day = [date(2026, 10, 13)]
    llm = BudgetedLLM(ScriptedLLM(answer("1"), answer("2")), DailyBudget(1, today=lambda: day[0]))
    assert llm.generate("s", [], []).text == "1"
    with pytest.raises(LLMError):
        llm.generate("s", [], [])
    day[0] = date(2026, 10, 14)
    assert llm.generate("s", [], []).text == "2"


def test_budget_exhaustion_still_answers_200(client):
    c = client(ScriptedLLM(LLMError("daily Gemini call budget reached")))
    res = c.post("/api/assistant/message", json={"message": "hi"})
    assert res.status_code == 200 and res.json()["fallback"] is True


def test_guest_rate_limit_is_per_ip(client):
    c = client(ScriptedLLM(answer("a")), limiter=UsageLimiter(per_minute=1, per_day=50))
    assert c.post("/api/assistant/message", json={"message": "x"}).status_code == 200
    assert c.post("/api/assistant/message", json={"message": "x"}).status_code == 429
