"""The latest migration can be rolled back and applied again."""

from pathlib import Path

from alembic import command as alembic_command
from alembic.config import Config as AlembicConfig
from sqlalchemy import text

from app.core.db import get_engine
from tests.conftest import TEST_URL

INDEXES = {
    "idx_experiences_published",
    "idx_action_experience_links_experience",
    "idx_feedback_review_queue",
    "idx_feedback_execution",
}


def _indexes() -> set[str]:
    with get_engine().connect() as conn:
        return set(
            conn.execute(text("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'"))
            .scalars()
            .all()
        )


def test_latest_migration_downgrades_and_upgrades():
    config = AlembicConfig(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", TEST_URL)
    assert INDEXES <= _indexes()

    alembic_command.downgrade(config, "0013_usage_counters")
    assert not INDEXES & _indexes()

    alembic_command.upgrade(config, "head")
    assert INDEXES <= _indexes()
