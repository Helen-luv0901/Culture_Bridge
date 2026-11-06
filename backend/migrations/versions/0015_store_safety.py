"""Terms acceptance, account suspension and reports on AI assistant answers (store review).

- users.terms_version: the version of the terms of use and AI notice this account accepted
  (NULL: never). Posting and commenting need the current one (app.core.terms).
- users.suspended_at: set by an admin; a suspended account can still read but not write.
- assistant_reports: a signed-in person flags an assistant answer as inaccurate, offensive or
  harmful. The question and answer are copied in, because conversations live only in server
  memory. Reports go with the reporter's account (ON DELETE CASCADE).

Revision ID: 0015_store_safety
Revises: 0014_hot_path_indexes
Create Date: 2026-11-07
"""

from alembic import op

revision = "0015_store_safety"
down_revision = "0014_hot_path_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE users
          ADD COLUMN terms_version INTEGER CHECK (terms_version > 0),
          ADD COLUMN suspended_at TIMESTAMPTZ;

        CREATE TABLE assistant_reports (
          id TEXT PRIMARY KEY,
          reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          conversation_id TEXT CHECK (char_length(conversation_id) <= 100),
          question TEXT NOT NULL CHECK (char_length(question) BETWEEN 1 AND 1000),
          answer TEXT NOT NULL CHECK (char_length(answer) BETWEEN 1 AND 4000),
          reason TEXT NOT NULL CHECK (reason IN ('inaccurate', 'offensive', 'harmful', 'other')),
          details TEXT CHECK (char_length(details) <= 1000),
          status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
          resolution_note TEXT CHECK (char_length(resolution_note) <= 1000),
          resolved_by TEXT REFERENCES users(id) ON DELETE SET NULL,
          resolved_at TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX idx_assistant_reports_queue ON assistant_reports(status, created_at DESC);
        CREATE INDEX idx_assistant_reports_reporter ON assistant_reports(reporter_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TABLE assistant_reports;
        ALTER TABLE users DROP COLUMN suspended_at, DROP COLUMN terms_version;
        """
    )
