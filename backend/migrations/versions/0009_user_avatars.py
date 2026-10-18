"""Profile photos.

Each account may have one photo, already cropped to a square and re-encoded as a small JPEG by
the API (which also drops EXIF data such as the GPS position). It is stored here rather than in
a bucket: a 256px JPEG is about 20 KB, and this keeps backups, account deletion and access in
one place. The id is random and changes on every upload, so photo URLs reveal nothing about the
account and can be cached forever.

The photo is shown only next to posts and comments the person chose to sign with a name, never
on anonymous ones. Deleting the account deletes the photo (ON DELETE CASCADE).

Revision ID: 0009_user_avatars
Revises: 0008_posts_tags_comments
Create Date: 2026-10-18
"""

from alembic import op

revision = "0009_user_avatars"
down_revision = "0008_posts_tags_comments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE user_avatars (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
          image BYTEA NOT NULL CHECK (octet_length(image) BETWEEN 1 AND 200000),
          content_type TEXT NOT NULL DEFAULT 'image/jpeg' CHECK (content_type = 'image/jpeg'),
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE user_avatars;")
