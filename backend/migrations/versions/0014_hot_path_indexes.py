"""Indexes for the newest-first feed, a post's guide link and the feedback queue.

Explore and search list published posts by published_at DESC, id; every list of posts looks up
each post's guide by experience_id (the link's key starts with action_id); the review queue
filters feedback by review_state and date, and deleting an account finds feedback by
execution_id. Each of these scanned the whole table before.

The tables are small, so a plain CREATE INDEX (a short write lock) is fine inside the
migration's transaction.

Revision ID: 0014_hot_path_indexes
Revises: 0013_usage_counters
Create Date: 2026-11-05
"""

from alembic import op

revision = "0014_hot_path_indexes"
down_revision = "0013_usage_counters"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE INDEX idx_experiences_published ON experiences(status, published_at DESC, id);
        CREATE INDEX idx_action_experience_links_experience
          ON action_experience_links(experience_id);
        CREATE INDEX idx_feedback_review_queue ON execution_feedback(review_state, created_at);
        CREATE INDEX idx_feedback_execution ON execution_feedback(execution_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX idx_feedback_execution;
        DROP INDEX idx_feedback_review_queue;
        DROP INDEX idx_action_experience_links_experience;
        DROP INDEX idx_experiences_published;
        """
    )
