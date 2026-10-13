"""database/test_schema.py ported to PostgreSQL (B-1): the integrity rules the triggers enforce."""

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError


@pytest.fixture
def seeded(db):
    db.execute(
        text(
            "INSERT INTO users(id,auth_subject,role) VALUES"
            "('author','a','student'),('other','o','student'),('reviewer','r','reviewer')"
        )
    )
    db.execute(text("INSERT INTO actions VALUES('permit','work-permit',NULL)"))
    for n in (1, 2):
        db.execute(
            text(
                "INSERT INTO action_versions(id,action_id,version_number,title_zh,title_en,"
                "applicable_to,created_by) VALUES(:v,'permit',:n,'工作證','Work permit',"
                "'International students','reviewer')"
            ),
            {"v": f"v{n}", "n": n},
        )
        db.execute(
            text("INSERT INTO action_steps VALUES(:s,:v,1,'準備文件','Prepare documents',NULL)"),
            {"s": f"step-v{n}", "v": f"v{n}"},
        )
    db.execute(
        text(
            "INSERT INTO experiences(id,author_id,topic_id,identity_type,original_voice) "
            "VALUES('e1','author','culture_communication','degree_student','My original voice')"
        )
    )
    db.execute(
        text(
            "INSERT INTO experience_summaries(id,experience_id,version_number,source_voice,"
            "situation,feeling_or_attempt,reminder,model_name) VALUES('s1','e1',1,"
            "'My original voice','Situation','Feeling','Reminder','test-model')"
        )
    )
    db.commit()
    return db


def rejected(db, sql: str) -> bool:
    try:
        with db.begin_nested():
            db.execute(text(sql))
    except DBAPIError:
        return True
    return False


PUBLISH = (
    "UPDATE experiences SET status='published',confirmed_summary_id='s1',"
    "published_at='2026-10-10T00:00:00Z' WHERE id='e1'"
)


def test_publication_requires_current_voice_author_confirmation(seeded):
    db = seeded
    assert rejected(db, PUBLISH)
    confirm_by_other = "UPDATE experience_summaries SET confirmed_by='other',confirmed_at=now()"
    db.execute(text(f"{confirm_by_other} WHERE id='s1'"))
    assert rejected(db, PUBLISH)
    db.execute(text("UPDATE experience_summaries SET confirmed_by='author' WHERE id='s1'"))
    db.execute(text(PUBLISH))
    assert db.scalar(text("SELECT count(*) FROM public_experiences")) == 1
    assert rejected(db, "UPDATE experiences SET original_voice='Changed' WHERE id='e1'")
    assert rejected(db, "UPDATE experience_summaries SET situation='Changed' WHERE id='s1'")
    db.commit()


def test_verification_requires_reviewer_and_source(seeded):
    db = seeded
    verify = "UPDATE action_versions SET verification_status='verified' WHERE id='v1'"
    assert rejected(db, verify)
    db.execute(
        text(
            "INSERT INTO sources VALUES('source','Official document','https://example.org/doc',"
            "'Example institution','official',now())"
        )
    )
    db.execute(text("INSERT INTO action_version_sources VALUES('v1','source','Check documents')"))
    db.execute(
        text(
            "INSERT INTO verification_records(id,action_version_id,source_id,reviewer_id,"
            "decision,note) VALUES('review','v1','source','reviewer','verified','Reviewed')"
        )
    )
    db.execute(text(verify))
    assert db.scalar(text("SELECT verification_status FROM action_versions WHERE id='v1'")) == (
        "verified"
    )


def test_execution_pins_steps_to_its_version(seeded):
    db = seeded
    start = (
        "INSERT INTO executions(id,user_id,action_version_id,identity_type) "
        "VALUES('attempt','author','v1','degree_student')"
    )
    assert rejected(db, start)
    db.execute(text("UPDATE action_versions SET published_at=now() WHERE id='v1'"))
    db.execute(text(start))
    step = (
        "INSERT INTO execution_steps(execution_id,action_version_id,step_id,state) "
        "VALUES('attempt','v1','{}','done')"
    )
    assert rejected(db, step.format("step-v2"))
    db.execute(text(step.format("step-v1")))
    assert rejected(db, "UPDATE action_steps SET title_en='Changed' WHERE id='step-v1'")
    assert rejected(db, "UPDATE action_versions SET title_en='Changed' WHERE id='v1'")
    db.commit()


def test_reactions_are_unique_and_views_hide_drafts(seeded):
    db = seeded
    assert db.scalar(text("SELECT count(*) FROM public_experiences")) == 0
    react = (
        "INSERT INTO experience_reactions(experience_id,user_id,kind) "
        "VALUES('e1','other','helpful')"
    )
    db.execute(text(react))
    assert rejected(db, react)
