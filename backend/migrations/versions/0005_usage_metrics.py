"""Usage metrics for the MVP success signals (D-19): active days and experience views.

Only what the signals need is stored: which day an account used the app, and which day a
signed-in reader opened an experience. Both rows disappear with the account or the experience.

Revision ID: 0005_usage_metrics
Revises: 0004_semantic_search
Create Date: 2026-10-13
"""

from alembic import op

revision = "0005_usage_metrics"
down_revision = "0004_semantic_search"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE user_activity_days (
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          day DATE NOT NULL,
          PRIMARY KEY (user_id, day)
        );
        CREATE INDEX idx_activity_day ON user_activity_days(day);

        CREATE TABLE experience_views (
          experience_id TEXT NOT NULL REFERENCES experiences(id) ON DELETE CASCADE,
          viewer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          day DATE NOT NULL,
          PRIMARY KEY (experience_id, viewer_id, day)
        );
        CREATE INDEX idx_experience_views_day ON experience_views(day);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE experience_views; DROP TABLE user_activity_days;")
