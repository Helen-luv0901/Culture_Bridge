"""English notes for procedure steps.

Step titles were bilingual but the notes under them were Chinese only, so English readers saw
Chinese text in every step. notes_en holds the English notes; the app falls back to the Chinese
notes when a step has none. Published steps stay frozen, so existing guides get English notes
through a new version.

Revision ID: 0011_step_notes_en
Revises: 0010_cultural_differences
Create Date: 2026-10-18
"""

from alembic import op

revision = "0011_step_notes_en"
down_revision = "0010_cultural_differences"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE action_steps ADD COLUMN notes_en TEXT "
        "CHECK (notes_en IS NULL OR char_length(notes_en) <= 2000);"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE action_steps DROP COLUMN notes_en;")
