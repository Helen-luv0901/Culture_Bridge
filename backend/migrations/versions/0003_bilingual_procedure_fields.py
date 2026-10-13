"""English applicability and location for procedure versions; keep them frozen once published.

Revision ID: 0003_bilingual_procedure_fields
Revises: 0002_moderation_and_assistant
Create Date: 2026-10-13
"""

from alembic import op

revision = "0003_bilingual_procedure_fields"
down_revision = "0002_moderation_and_assistant"
branch_labels = None
depends_on = None

_FROZEN = """
    NEW.action_id IS DISTINCT FROM OLD.action_id OR NEW.version_number IS DISTINCT FROM OLD.version_number OR
    NEW.title_zh IS DISTINCT FROM OLD.title_zh OR NEW.title_en IS DISTINCT FROM OLD.title_en OR
    NEW.description_zh IS DISTINCT FROM OLD.description_zh OR NEW.description_en IS DISTINCT FROM OLD.description_en OR
    NEW.applicable_to IS DISTINCT FROM OLD.applicable_to OR NEW.institution_id IS DISTINCT FROM OLD.institution_id OR
    NEW.location IS DISTINCT FROM OLD.location OR NEW.published_at IS DISTINCT FROM OLD.published_at"""


def _freeze_trigger(extra: str) -> str:
    return f"""
    DROP TRIGGER freeze_version_content ON action_versions;
    CREATE TRIGGER freeze_version_content
      BEFORE UPDATE ON action_versions
      FOR EACH ROW WHEN (OLD.published_at IS NOT NULL AND ({_FROZEN}{extra}))
      EXECUTE FUNCTION reject_published_version_edit();
    """


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE action_versions
          ADD COLUMN applicable_to_en TEXT NOT NULL DEFAULT '',
          ADD COLUMN location_en TEXT;
        """
        + _freeze_trigger(
            " OR\n    NEW.applicable_to_en IS DISTINCT FROM OLD.applicable_to_en OR"
            " NEW.location_en IS DISTINCT FROM OLD.location_en"
        )
    )


def downgrade() -> None:
    op.execute(
        _freeze_trigger("")
        + "ALTER TABLE action_versions DROP COLUMN applicable_to_en, DROP COLUMN location_en;"
    )
