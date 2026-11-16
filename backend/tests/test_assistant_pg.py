from app.assistant.pg_data import PostgresAssistantData
from app.core.auth import CurrentUser
from app.core.config import get_settings
from app.models import User, UserBlock
from app.seed import seed
from app.services import actions

MEI = CurrentUser(id="dev-mei")


def setup(db):
    seed(db, get_settings().demo_content_path)
    db.add(User(id="dev-mei", auth_subject="dev:mei"))
    db.commit()


def test_reads_real_procedures_and_experiences(db):
    setup(db)
    data = PostgresAssistantData(db, MEI)
    assert data.search_actions("ARC", 3)[0].id == "arc"
    assert data.search_actions("工作證怎麼辦", 3)[0].id == "work-permit"
    permit = data.get_action("work-permit")
    assert permit.verification_status == "verified" and permit.last_verified_at
    assert permit.steps[0].en == "Prepare your ARC"
    assert data.get_action("nope") is None

    found = data.search_experiences("教授", None, None, 5)
    assert [e.id for e in found] == ["professor-see"]
    assert found[0].original_voice.en.startswith("My professor")
    assert data.get_experience("nope") is None


def test_progress_and_blocks_follow_the_viewer(db):
    setup(db)
    actions.start_execution(db, MEI, "bank")
    data = PostgresAssistantData(db, MEI)
    [progress] = data.get_in_progress("dev-mei")
    assert progress.action_id == "bank" and progress.steps[0].state == "pending"

    db.add(UserBlock(blocker_id="dev-mei", blocked_id="seed-author-professor-see"))
    db.commit()
    assert data.get_experience("professor-see") is None
    assert "professor-see" not in [e.id for e in data.search_experiences(None, None, None, 10)]
