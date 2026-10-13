from collections.abc import Callable

import pytest

from app.assistant.agent import Assistant
from app.assistant.data import DemoDataSource
from app.assistant.llm import LLMError, ModelTurn, ToolCall, ToolSpec, Turn
from app.assistant.memory import ConversationStore
from app.assistant.tools import ToolContext, default_registry
from app.core.auth import CurrentUser
from app.core.config import get_settings

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
def make_assistant(data) -> Callable[..., Assistant]:
    def build(llm, max_tool_rounds: int = 5, memory: ConversationStore | None = None) -> Assistant:
        return Assistant(
            llm=llm,
            data=data,
            registry=default_registry(),
            memory=memory or ConversationStore(),
            max_tool_rounds=max_tool_rounds,
        )

    return build


__all__ = ["ScriptedLLM", "call", "answer", "LLMError"]
