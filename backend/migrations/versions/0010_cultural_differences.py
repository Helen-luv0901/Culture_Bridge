"""A seventh post category: 文化差異 (cultural differences).

Revision ID: 0010_cultural_differences
Revises: 0009_user_avatars
Create Date: 2026-10-18
"""

from alembic import op

revision = "0010_cultural_differences"
down_revision = "0009_user_avatars"
branch_labels = None
depends_on = None

_OLD = "('life','food','housing','transit','study','culture')"
_NEW = "('life','food','housing','transit','study','culture','difference')"


def _categories(allowed: str) -> None:
    op.execute(
        f"""
        ALTER TABLE experiences DROP CONSTRAINT experiences_category_check;
        ALTER TABLE experiences ADD CONSTRAINT experiences_category_check
          CHECK (category IS NULL OR category IN {allowed});
        """
    )


def upgrade() -> None:
    _categories(_NEW)


def downgrade() -> None:
    op.execute("UPDATE experiences SET category = 'culture' WHERE category = 'difference';")
    _categories(_OLD)
