from collections.abc import Callable

import pytest
from fastapi.testclient import TestClient

from app.api.assistant import AssistantServices, get_services
from app.assistant.agent import Assistant
from app.assistant.data import DemoDataSource
from app.assistant.limits import UsageLimiter
from app.assistant.llm import LLMError, ModelTurn, ToolCall, ToolSpec, Turn
from app.assistant.memory import ConversationStore
from app.assistant.operations import DemoExecutionWriter, OperationService
from app.assistant.tools import ToolContext, default_registry
from app.core.auth import CurrentUser
from app.core.config import get_settings
from app.main import app

Step = ModelTurn | Exception | Callable[[list[Turn]], ModelTurn]


class ScriptedLLM:
    """Plays back model turns in order and records what the model was shown."""

    def __init__(self, *steps: Step) -> None:
        self.steps = list(steps)
        self.calls: list[dict] = []

    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn:
        self.calls.append({"system": system, "history": list(history), "tools": tools})
        if not self.steps:
            raise AssertionError("ScriptedLLM ran out of steps")
        step = self.steps.pop(0)
        if isinstance(step, Exception):
            raise step
        return step(history) if callable(step) else step


def call(name: str, **args) -> ModelTurn:
    return ModelTurn(tool_calls=(ToolCall(id=f"call-{name}", name=name, args=args),))


def answer(text: str) -> ModelTurn:
    return ModelTurn(text=text)


@pytest.fixture
def data() -> DemoDataSource:
    return DemoDataSource.from_file(get_settings().demo_content_path)


@pytest.fixture
def ctx(data) -> ToolContext:
    return ToolContext(data=data, locale="zh-Hant", user=CurrentUser(id="u1"))


@pytest.fixture
def operations(data) -> OperationService:
    return OperationService(data=data, writer=DemoExecutionWriter(data))


@pytest.fixture
def make_assistant(data, operations) -> Callable[..., Assistant]:
    def build(llm, max_tool_rounds: int = 5, memory: ConversationStore | None = None) -> Assistant:
        return Assistant(
            llm=llm,
            data=data,
            registry=default_registry(),
            memory=memory or ConversationStore(),
            max_tool_rounds=max_tool_rounds,
            operations=operations,
        )

    return build


@pytest.fixture
def client(make_assistant, operations):
    def use(llm, allow_guests: bool = True, limiter: UsageLimiter | None = None):
        services = AssistantServices(
            assistant=make_assistant(llm),
            operations=operations,
            limiter=limiter or UsageLimiter(per_minute=100, per_day=1000),
            allow_guests=allow_guests,
        )
        app.dependency_overrides[get_services] = lambda: services
        return TestClient(app)

    yield use
    app.dependency_overrides.clear()


__all__ = ["ScriptedLLM", "call", "answer", "LLMError"]
