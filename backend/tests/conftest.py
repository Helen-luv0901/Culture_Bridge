"""Shared fixtures. Tests run against a real PostgreSQL (the schema's rules live in triggers).

TEST_DATABASE_ADMIN_URL points at a server where we may create databases; each test session
builds a fresh `culturebridge_test` database with `alembic upgrade head`.
"""

import os
from collections.abc import Callable, Iterator

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

ADMIN_URL = os.getenv(
    "TEST_DATABASE_ADMIN_URL", "postgresql+psycopg://postgres@localhost:5432/postgres"
)
TEST_URL = (
    make_url(ADMIN_URL).set(database="culturebridge_test").render_as_string(hide_password=False)
)
os.environ["DATABASE_URL"] = TEST_URL
os.environ.setdefault("APP_ENV", "development")
os.environ.pop("GEMINI_API_KEY", None)
os.environ.pop("FIREBASE_PROJECT_ID", None)

from pathlib import Path

import pytest
from alembic import command as alembic_command
from alembic.config import Config as AlembicConfig
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.api.assistant import AssistantServices, get_services
from app.assistant.agent import Assistant
from app.assistant.data import DemoDataSource
from app.assistant.limits import UsageLimiter
from app.assistant.llm import LLMError, ModelTurn, ToolCall, ToolSpec, Turn
from app.assistant.memory import ConversationStore
from app.assistant.operations import DemoExecutionWriter, OperationService
from app.assistant.pg_data import forget_cached_actions
from app.assistant.tools import ToolContext, default_registry
from app.core.auth import CurrentUser
from app.core.config import get_settings
from app.core.db import get_engine, get_sessionmaker
from app.main import app

KEEP_TABLES = {"alembic_version", "topics"}


def _create_test_database() -> None:
    admin = create_engine(ADMIN_URL, isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        conn.execute(text("DROP DATABASE IF EXISTS culturebridge_test WITH (FORCE)"))
        conn.execute(text("CREATE DATABASE culturebridge_test"))
    admin.dispose()
    config = AlembicConfig(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", TEST_URL)
    alembic_command.upgrade(config, "head")


@pytest.fixture(scope="session", autouse=True)
def database() -> Iterator[None]:
    _create_test_database()
    yield
    get_engine().dispose()


@pytest.fixture(autouse=True)
def clean_tables(database) -> Iterator[None]:
    yield
    forget_cached_actions()
    with get_engine().begin() as conn:
        tables = conn.execute(
            text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
        ).scalars()
        names = ", ".join(t for t in tables if t not in KEEP_TABLES)
        conn.execute(text(f"TRUNCATE {names} CASCADE"))


@pytest.fixture
def db() -> Iterator[Session]:
    with get_sessionmaker()() as session:
        yield session


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
def client(make_assistant, db):
    """The assistant API over the seeded demo database, with a scripted model."""
    from app.seed import seed

    seed(db, get_settings().demo_content_path)

    def use(llm, allow_guests: bool = True, limiter: UsageLimiter | None = None):
        services = AssistantServices(
            assistant=make_assistant(llm),
            limiter=limiter or UsageLimiter(per_minute=100, per_day=1000),
            allow_guests=allow_guests,
        )
        app.dependency_overrides[get_services] = lambda: services
        return TestClient(app)

    yield use
    app.dependency_overrides.clear()


__all__ = ["ScriptedLLM", "call", "answer", "LLMError"]
