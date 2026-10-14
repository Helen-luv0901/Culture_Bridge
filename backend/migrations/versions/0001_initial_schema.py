"""Initial schema: the PostgreSQL version of the original SQLite draft, as of 2026-10-12.

The Cloud SQL database was created by running that file by hand, so on it run
`alembic stamp 0001_initial_schema` once instead of upgrading through this revision.

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-10-13
"""

from pathlib import Path

from alembic import op

revision = "0001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None

SQL = Path(__file__).with_name("0001_initial_schema.sql")


def upgrade() -> None:
    # exec_driver_sql runs the whole script, including the $$-quoted trigger functions.
    op.get_bind().exec_driver_sql(SQL.read_text(encoding="utf-8-sig"))


def downgrade() -> None:
    raise NotImplementedError("The initial schema cannot be downgraded")
