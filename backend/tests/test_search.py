"""The Explore search (/api/search): whole questions work, and the official question or post
*about* the words comes first, without questions that only mention a word in their answer."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event

from app.core.config import get_settings
from app.core.db import get_engine
from app.core.text_search import MAX_UNITS
from app.main import app
from app.official_faq import DEFAULT_PATH, import_faqs, load
from app.seed import seed


@pytest.fixture
def api(db) -> TestClient:
    return TestClient(app)


def faq_ids(api, q: str) -> list[str]:
    return [a["id"] for a in api.get("/api/search", params={"q": q}).json()["faqs"]]


def seed_all(db) -> None:
    seed(db, get_settings().demo_content_path)
    import_faqs(db, load(DEFAULT_PATH))


def post_ids(api, q: str) -> list[str]:
    return [e["id"] for e in api.get("/api/search", params={"q": q}).json()["experiences"]]


def test_a_chinese_question_without_spaces_finds_its_question(api, db):
    seed_all(db)
    assert faq_ids(api, "居留證逾期失效可以在臺灣辦嗎？")[0] == "nisa-934"


def test_an_english_question_ignores_question_words(api, db):
    seed_all(db)
    assert faq_ids(api, "how do I renew my driving license")[0] == "nisa-923"


def test_questions_that_only_mention_the_word_in_their_answer_are_left_out(api, db):
    seed_all(db)
    # Only the question about driving licences is about 駕照.
    assert faq_ids(api, "駕照") == ["nisa-923"]


def test_a_question_finds_the_post_about_it(api, db):
    seed(db, get_settings().demo_content_path)
    assert post_ids(api, "教授說再看看是什麼意思？")[0] == "professor-see"


def test_words_found_nowhere_find_nothing(api, db):
    seed(db, get_settings().demo_content_path)
    import_faqs(db, load(DEFAULT_PATH))
    assert faq_ids(api, "xyzabc") == []
    assert post_ids(api, "xyzabc") == []
    # Only question words: nothing to search for.
    assert faq_ids(api, "怎麼辦") == []


def test_a_long_query_stays_a_small_database_query(api, db):
    seed(db, get_settings().demo_content_path)
    statements: list[str] = []

    def capture(conn, cursor, statement, *args) -> None:
        statements.append(statement)

    event.listen(get_engine(), "before_cursor_execute", capture)
    try:
        found = post_ids(api, ("教授說再看看是什麼意思" * 20)[:200])
    finally:
        event.remove(get_engine(), "before_cursor_execute", capture)
    assert found[0] == "professor-see"
    # Each unit is matched against ten text columns.
    assert max(s.lower().count("ilike") for s in statements) <= MAX_UNITS * 10
