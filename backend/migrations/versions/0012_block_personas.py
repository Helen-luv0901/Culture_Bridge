"""Blocks per persona, with random ids.

Block ids were a hash of (blocker, blocked author), so blocking several anonymous posts showed
whether they shared an author. A block also hid everything the author wrote, so blocking a
named author revealed which anonymous posts were theirs. Now each block has a random id and a
persona (anonymous | named) and hides only that persona.

Existing blocks keep persona NULL and go on hiding both, as before. The id has a database
default and each existing pair stays one row, so the previous release still works on this
schema while a deploy is checked or rolled back.

Revision ID: 0012_block_personas
Revises: 0011_step_notes_en
Create Date: 2026-10-27
"""

from alembic import op

revision = "0012_block_personas"
down_revision = "0011_step_notes_en"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE user_blocks
          ADD COLUMN id TEXT NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),
          ADD COLUMN persona TEXT CHECK (persona IN ('anonymous', 'named')),
          DROP CONSTRAINT user_blocks_pkey,
          ADD PRIMARY KEY (id),
          ADD CONSTRAINT user_blocks_persona_key UNIQUE (blocker_id, blocked_id, persona);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DELETE FROM user_blocks a USING user_blocks b
          WHERE a.blocker_id = b.blocker_id AND a.blocked_id = b.blocked_id AND a.id > b.id;
        ALTER TABLE user_blocks
          DROP CONSTRAINT user_blocks_persona_key,
          DROP CONSTRAINT user_blocks_pkey,
          DROP COLUMN persona,
          DROP COLUMN id,
          ADD PRIMARY KEY (blocker_id, blocked_id);
        """
    )
