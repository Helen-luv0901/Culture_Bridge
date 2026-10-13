"""Reports, blocks, admin audit log and assistant pending operations (B-2).

Revision ID: 0002_moderation_and_assistant
Revises: 0001_initial_schema
Create Date: 2026-10-13
"""

from alembic import op

revision = "0002_moderation_and_assistant"
down_revision = "0001_initial_schema"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE reports (
          id TEXT PRIMARY KEY NOT NULL,
          reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          target_type TEXT NOT NULL CHECK (target_type IN ('experience','execution_feedback')),
          target_id TEXT NOT NULL,
          reason TEXT NOT NULL CHECK (reason IN
            ('spam','harassment','hate','sexual','personal_info','misinformation','other')),
          note TEXT CHECK (note IS NULL OR char_length(note) <= 1000),
          status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','actioned','dismissed')),
          resolved_by TEXT REFERENCES users(id) ON DELETE SET NULL,
          resolved_at TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          CHECK ((status = 'pending') = (resolved_at IS NULL)),
          UNIQUE (reporter_id, target_type, target_id)
        );
        CREATE INDEX idx_reports_queue ON reports(status, created_at);
        CREATE INDEX idx_reports_target ON reports(target_type, target_id);

        CREATE TABLE user_blocks (
          blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          PRIMARY KEY (blocker_id, blocked_id),
          CHECK (blocker_id <> blocked_id)
        );

        CREATE TABLE admin_actions (
          id TEXT PRIMARY KEY NOT NULL,
          actor_id TEXT REFERENCES users(id) ON DELETE SET NULL,
          action TEXT NOT NULL,
          target_type TEXT NOT NULL,
          target_id TEXT NOT NULL,
          detail JSONB NOT NULL DEFAULT '{}'::jsonb,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX idx_admin_actions_target ON admin_actions(target_type, target_id, created_at);

        CREATE TABLE assistant_operations (
          id TEXT PRIMARY KEY NOT NULL,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          type VARCHAR(40) NOT NULL CHECK (type IN ('start_action')),
          target_id TEXT NOT NULL,
          summary TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending'
            CHECK (status IN ('pending','confirmed','cancelled','expired','failed')),
          result JSONB,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          expires_at TIMESTAMPTZ NOT NULL,
          resolved_at TIMESTAMPTZ,
          CHECK (expires_at > created_at)
        );
        CREATE INDEX idx_assistant_operations_user ON assistant_operations(user_id, created_at);
        """
    )


def downgrade() -> None:
    op.execute(
        "DROP TABLE assistant_operations; DROP TABLE admin_actions; "
        "DROP TABLE user_blocks; DROP TABLE reports;"
    )
