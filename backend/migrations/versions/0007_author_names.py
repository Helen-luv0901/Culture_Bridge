"""Optional nickname and real name, and how each experience is signed.

Both names are optional and only shown on experiences whose author chose to sign with them;
every experience published before this migration stays anonymous. The name shown is read
from the account when the experience is displayed, so editing or clearing a name updates (or
anonymizes) the author's experiences, and deleting the account removes both.

Revision ID: 0007_author_names
Revises: 0006_saved_experiences
Create Date: 2026-10-14
"""

from alembic import op

revision = "0007_author_names"
down_revision = "0006_saved_experiences"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE users
          ADD COLUMN nickname TEXT CHECK (char_length(nickname) BETWEEN 1 AND 30),
          ADD COLUMN real_name TEXT CHECK (char_length(real_name) BETWEEN 1 AND 50);

        ALTER TABLE experiences
          ADD COLUMN author_display TEXT NOT NULL DEFAULT 'anonymous'
            CHECK (author_display IN ('anonymous', 'nickname', 'real_name'));
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE experiences DROP COLUMN author_display;
        ALTER TABLE users DROP COLUMN real_name, DROP COLUMN nickname;
        """
    )
