"""Official Q&A from the Ministry of Education NISA site replaces the self-researched guides.

- faq_categories / faq_identities: the site's question categories and student identities, with
  their Chinese and English names as the site shows them.
- official_faqs: one row per question. The site has an English version of some questions only,
  so either language may be empty (never both). Rows the site no longer lists are kept but
  inactive. content_hash tells the importer when the text changed and needs embedding again.
- content_embeddings may now hold 'official_faq' rows, so the assistant finds the Q&A by meaning
  and each question can recommend student posts close to it.

Revision ID: 0016_official_faqs
Revises: 0015_store_safety
Create Date: 2026-11-16
"""

from alembic import op

revision = "0016_official_faqs"
down_revision = "0015_store_safety"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE faq_categories (
          id TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{1,64}$'),
          name_zh TEXT NOT NULL CHECK (char_length(name_zh) BETWEEN 1 AND 100),
          name_en TEXT NOT NULL CHECK (char_length(name_en) BETWEEN 1 AND 100),
          position INTEGER NOT NULL
        );

        CREATE TABLE faq_identities (
          id TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{1,64}$'),
          name_zh TEXT NOT NULL CHECK (char_length(name_zh) BETWEEN 1 AND 100),
          name_en TEXT NOT NULL CHECK (char_length(name_en) BETWEEN 1 AND 100),
          position INTEGER NOT NULL
        );

        CREATE TABLE official_faqs (
          id TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{1,64}$'),
          category_id TEXT NOT NULL REFERENCES faq_categories(id),
          identities TEXT[] NOT NULL DEFAULT '{}',
          question_zh TEXT NOT NULL DEFAULT '',
          question_en TEXT NOT NULL DEFAULT '',
          answer_zh TEXT NOT NULL DEFAULT '',
          answer_en TEXT NOT NULL DEFAULT '',
          source_zh TEXT NOT NULL DEFAULT '',
          source_en TEXT NOT NULL DEFAULT '',
          agency_zh TEXT NOT NULL DEFAULT '',
          agency_en TEXT NOT NULL DEFAULT '',
          posted_on DATE,
          url TEXT NOT NULL CHECK (url ~ '^https://'),
          active BOOLEAN NOT NULL DEFAULT true,
          content_hash TEXT NOT NULL,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          CHECK (question_zh <> '' OR question_en <> ''),
          CHECK (answer_zh <> '' OR answer_en <> '')
        );
        CREATE INDEX idx_official_faqs_active ON official_faqs(category_id, posted_on DESC)
          WHERE active;

        ALTER TABLE content_embeddings DROP CONSTRAINT content_embeddings_content_type_check;
        ALTER TABLE content_embeddings ADD CONSTRAINT content_embeddings_content_type_check
          CHECK (content_type IN ('experience', 'execution_feedback', 'official_faq'));
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DELETE FROM content_embeddings WHERE content_type = 'official_faq';
        ALTER TABLE content_embeddings DROP CONSTRAINT content_embeddings_content_type_check;
        ALTER TABLE content_embeddings ADD CONSTRAINT content_embeddings_content_type_check
          CHECK (content_type IN ('experience', 'execution_feedback'));
        DROP TABLE official_faqs;
        DROP TABLE faq_identities;
        DROP TABLE faq_categories;
        """
    )
