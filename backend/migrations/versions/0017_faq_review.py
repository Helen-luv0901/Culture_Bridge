"""Who each official question is for, and a warning when its answer may be outdated.

- official_faqs.audience: 'student' (a rule or procedure a student can act on) or 'school'
  (international-office administration: staff systems, requests to agencies). School questions
  stay readable but rank after student ones and carry a label.
- review_kind / review_note_zh / review_note_en / superseded_by: from a reviewed consistency pass
  over the whole set (app/content/nisa_faq_review.json): 'superseded' (a newer answer changed
  the rule), 'conflict' (two answers disagree) or 'time_limited' (a temporary measure that has
  ended). The app shows the note above the answer and links the newer question.

Revision ID: 0017_faq_review
Revises: 0016_official_faqs
Create Date: 2026-11-18
"""

from alembic import op

revision = "0017_faq_review"
down_revision = "0016_official_faqs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE official_faqs
          ADD COLUMN audience TEXT NOT NULL DEFAULT 'student'
            CHECK (audience IN ('student', 'school')),
          ADD COLUMN review_kind TEXT
            CHECK (review_kind IN ('superseded', 'conflict', 'time_limited')),
          ADD COLUMN review_note_zh TEXT NOT NULL DEFAULT '',
          ADD COLUMN review_note_en TEXT NOT NULL DEFAULT '',
          ADD COLUMN superseded_by TEXT,
          ADD CONSTRAINT official_faqs_review_has_note
            CHECK (review_kind IS NULL OR review_note_zh <> '');
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE official_faqs
          DROP CONSTRAINT official_faqs_review_has_note,
          DROP COLUMN superseded_by,
          DROP COLUMN review_note_en,
          DROP COLUMN review_note_zh,
          DROP COLUMN review_kind,
          DROP COLUMN audience;
        """
    )
