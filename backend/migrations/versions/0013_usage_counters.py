"""Daily usage counters in the database.

Caps on Gemini calls, assistant messages, tag suggestions, photo uploads and blocks were counted
in process memory, so they reset on every cold start and doubled with two Cloud Run instances.
One row per (Taiwan day, key); rows older than 30 days are deleted as new days start.

Revision ID: 0013_usage_counters
Revises: 0012_block_personas
Create Date: 2026-10-27
"""

from alembic import op

revision = "0013_usage_counters"
down_revision = "0012_block_personas"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE usage_counters (
          day DATE NOT NULL,
          key TEXT NOT NULL CHECK (char_length(key) <= 200),
          count INTEGER NOT NULL CHECK (count >= 0),
          PRIMARY KEY (day, key)
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE usage_counters;")
