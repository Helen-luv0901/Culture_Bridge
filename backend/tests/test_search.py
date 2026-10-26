"""The Explore search (/api/search): whole questions work, and the guide or post *about* the
words comes first, without guides that only mention a word somewhere in a step."""

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.seed import seed


@pytest.fixture
def api(db) -> TestClient:
    return TestClient(app)


def guide_ids(api, q: str) -> list[str]:
    return [a["id"] for a in api.get("/api/search", params={"q": q}).json()["actions"]]


def post_ids(api, q: str) -> list[str]:
    return [e["id"] for e in api.get("/api/search", params={"q": q}).json()["experiences"]]


def test_a_chinese_question_without_spaces_finds_its_guide(api, db):
    seed(db, get_settings().demo_content_path)
    assert guide_ids(api, "在學證明要去哪裡申請？")[0] == "certificate"


def test_an_english_question_ignores_question_words(api, db):
    seed(db, get_settings().demo_content_path)
    assert guide_ids(api, "how do I open a bank account")[0] == "bank"


def test_guides_that_only_mention_the_words_in_a_step_are_left_out(api, db):
    seed(db, get_settings().demo_content_path)
    # 「申請工作證」 has a step called 「申請在學證明」; it is not about the certificate.
    assert guide_ids(api, "申請在學證明") == ["certificate"]


def test_a_common_word_lists_the_guides_about_it_not_every_guide(api, db):
    seed(db, get_settings().demo_content_path)
    # Every demo guide is "for international students"; only titles count here.
    found = guide_ids(api, "apply")
    assert set(found) == {"work-permit", "arc"}


def test_a_question_finds_the_post_about_it(api, db):
    seed(db, get_settings().demo_content_path)
    assert post_ids(api, "教授說再看看是什麼意思？")[0] == "professor-see"


def test_words_found_nowhere_find_nothing(api, db):
    seed(db, get_settings().demo_content_path)
    assert guide_ids(api, "xyzabc") == []
    assert post_ids(api, "xyzabc") == []
    # Only question words: nothing to search for.
    assert guide_ids(api, "怎麼辦") == []
