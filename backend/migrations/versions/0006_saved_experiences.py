"""Saved experiences: a private "read later" list.

Only the reader sees what they saved; nothing about saves is shown to authors or counted in
public numbers. Rows disappear with the account or the experience.

Revision ID: 0006_saved_experiences
Revises: 0005_usage_metrics
Create Date: 2026-10-14
"""

from alembic import op

revision = "0006_saved_experiences"
down_revision = "0005_usage_metrics"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE saved_experiences (
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          experience_id TEXT NOT NULL REFERENCES experiences(id) ON DELETE CASCADE,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          PRIMARY KEY (user_id, experience_id)
        );
        CREATE INDEX idx_saved_experiences_user ON saved_experiences(user_id, created_at DESC);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE saved_experiences;")
