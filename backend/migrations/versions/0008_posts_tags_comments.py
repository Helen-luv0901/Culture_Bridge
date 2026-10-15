"""Posts as written: titles, six categories, tags, comments and "what to bring" lists.

The redesign publishes a student's post exactly as written. The AI only suggests tags, so new
posts carry an author-confirmed "verbatim" summary with empty parts to keep the publication gate
(validate_experience_publication) unchanged. Older posts keep their AI summaries.

- experiences.title: the author's one-line title (older posts have none).
- experiences.category: one of six; older posts are filed under life or culture by topic.
- experiences.tags: up to eight "#tag" strings the author chose.
- experience_translations.title: the title in the other language.
- action_versions.documents: the guide's "what to bring" checklist, frozen once published.
- experience_comments / comment_likes: comments under posts, one level of replies.
- reports may now target a comment.

Revision ID: 0008_posts_tags_comments
Revises: 0007_author_names
Create Date: 2026-10-15
"""

from alembic import op

revision = "0008_posts_tags_comments"
down_revision = "0007_author_names"
branch_labels = None
depends_on = None

_FROZEN = """
    NEW.action_id IS DISTINCT FROM OLD.action_id OR NEW.version_number IS DISTINCT FROM OLD.version_number OR
    NEW.title_zh IS DISTINCT FROM OLD.title_zh OR NEW.title_en IS DISTINCT FROM OLD.title_en OR
    NEW.description_zh IS DISTINCT FROM OLD.description_zh OR NEW.description_en IS DISTINCT FROM OLD.description_en OR
    NEW.applicable_to IS DISTINCT FROM OLD.applicable_to OR NEW.institution_id IS DISTINCT FROM OLD.institution_id OR
    NEW.location IS DISTINCT FROM OLD.location OR NEW.published_at IS DISTINCT FROM OLD.published_at OR
    NEW.applicable_to_en IS DISTINCT FROM OLD.applicable_to_en OR NEW.location_en IS DISTINCT FROM OLD.location_en"""


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
        ALTER TABLE experiences
          ADD COLUMN title TEXT CHECK (title IS NULL OR char_length(btrim(title)) BETWEEN 1 AND 80),
          ADD COLUMN category TEXT CHECK (category IS NULL OR category IN
            ('life','food','housing','transit','study','culture')),
          ADD COLUMN tags TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(tags) <= 8);
        UPDATE experiences
          SET category = CASE topic_id WHEN 'culture_communication' THEN 'culture' ELSE 'life' END;
        CREATE INDEX idx_experiences_category ON experiences(status, category, published_at);
        CREATE INDEX idx_experiences_tags ON experiences USING gin (tags);

        ALTER TABLE experience_translations ADD COLUMN title TEXT;

        ALTER TABLE action_versions
          ADD COLUMN documents JSONB NOT NULL DEFAULT '[]'::jsonb
            CHECK (jsonb_typeof(documents) = 'array');

        CREATE TABLE experience_comments (
          id TEXT PRIMARY KEY NOT NULL,
          experience_id TEXT NOT NULL REFERENCES experiences(id) ON DELETE CASCADE,
          author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          reply_to_id TEXT REFERENCES experience_comments(id) ON DELETE CASCADE,
          body TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 1000),
          author_display TEXT NOT NULL DEFAULT 'anonymous'
            CHECK (author_display IN ('anonymous','nickname')),
          status TEXT NOT NULL DEFAULT 'visible' CHECK (status IN ('visible','hidden')),
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          CHECK (reply_to_id IS NULL OR reply_to_id <> id)
        );
        CREATE INDEX idx_comments_post ON experience_comments(experience_id, created_at);
        CREATE INDEX idx_comments_author ON experience_comments(author_id);

        CREATE TABLE comment_likes (
          comment_id TEXT NOT NULL REFERENCES experience_comments(id) ON DELETE CASCADE,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          PRIMARY KEY (comment_id, user_id)
        );

        ALTER TABLE reports DROP CONSTRAINT reports_target_type_check;
        ALTER TABLE reports ADD CONSTRAINT reports_target_type_check
          CHECK (target_type IN ('experience','execution_feedback','comment'));
        """
        + _freeze_trigger(" OR\n    NEW.documents IS DISTINCT FROM OLD.documents")
    )


def downgrade() -> None:
    op.execute(
        _freeze_trigger("")
        + """
        DELETE FROM reports WHERE target_type = 'comment';
        ALTER TABLE reports DROP CONSTRAINT reports_target_type_check;
        ALTER TABLE reports ADD CONSTRAINT reports_target_type_check
          CHECK (target_type IN ('experience','execution_feedback'));
        DROP TABLE comment_likes;
        DROP TABLE experience_comments;
        ALTER TABLE action_versions DROP COLUMN documents;
        ALTER TABLE experience_translations DROP COLUMN title;
        DROP INDEX idx_experiences_tags;
        DROP INDEX idx_experiences_category;
        ALTER TABLE experiences DROP COLUMN tags, DROP COLUMN category, DROP COLUMN title;
        """
    )
