"""Semantic search for the assistant (A-19): pgvector, official documents and content embeddings.

Revision ID: 0004_semantic_search
Revises: 0003_bilingual_procedure_fields
Create Date: 2026-10-13
"""

from alembic import op

revision = "0004_semantic_search"
down_revision = "0003_bilingual_procedure_fields"
branch_labels = None
depends_on = None

DIMENSIONS = 768


def upgrade() -> None:
    op.execute(
        f"""
        CREATE EXTENSION IF NOT EXISTS vector;

        -- Official source documents collected for procedure cards (A-21).
        CREATE TABLE kb_documents (
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT NOT NULL,
          url TEXT NOT NULL,
          publisher TEXT NOT NULL,
          document_date DATE,
          action_id TEXT REFERENCES actions(id),
          active BOOLEAN NOT NULL DEFAULT true,
          created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE kb_chunks (
          id TEXT PRIMARY KEY NOT NULL,
          document_id TEXT NOT NULL REFERENCES kb_documents(id) ON DELETE CASCADE,
          position INTEGER NOT NULL CHECK (position > 0),
          content TEXT NOT NULL,
          embedding vector({DIMENSIONS}) NOT NULL,
          UNIQUE (document_id, position)
        );
        CREATE INDEX idx_kb_chunks_embedding ON kb_chunks USING hnsw (embedding vector_cosine_ops);

        -- Public user content (A-20). No author column: the index never stores who wrote what.
        CREATE TABLE content_embeddings (
          content_type TEXT NOT NULL CHECK (content_type IN ('experience','execution_feedback')),
          content_id TEXT NOT NULL,
          content TEXT NOT NULL,
          embedding vector({DIMENSIONS}) NOT NULL,
          published_at TIMESTAMPTZ,
          indexed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          PRIMARY KEY (content_type, content_id)
        );
        CREATE INDEX idx_content_embeddings_embedding
          ON content_embeddings USING hnsw (embedding vector_cosine_ops);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE content_embeddings; DROP TABLE kb_chunks; DROP TABLE kb_documents;")
