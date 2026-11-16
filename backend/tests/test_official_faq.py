"""The official NISA Q&A: import, API, keyword and semantic search, related student posts."""

import json

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.assistant.pg_data import PostgresAssistantData
from app.core.config import get_settings
from app.main import app
from app.models import ContentEmbedding, FaqCategory, OfficialFaq
from app.official_faq import (
    DEFAULT_PATH,
    FaqFile,
    embed_missing,
    embedding_text,
    import_faqs,
    load,
)
from app.rag.embedder import HashingEmbedder
from app.rag.index import semantic_search, sync_experience
from app.seed import seed
from app.services.faqs import forget_cache

EMBED = HashingEmbedder()


@pytest.fixture
def api(db) -> TestClient:
    return TestClient(app)


@pytest.fixture
def faq_file() -> FaqFile:
    return load(DEFAULT_PATH)


def loaded(db, faq_file) -> FaqFile:
    import_faqs(db, faq_file)
    return faq_file


def test_the_content_file_is_valid_and_bilingual_where_the_site_is(faq_file):
    assert len(faq_file.faqs) > 200
    assert len(faq_file.categories) == 16
    assert {i.id for i in faq_file.identities} == {
        "foreign",
        "overseas-chinese",
        "hong-kong-macao",
        "mainland",
    }
    both = [f for f in faq_file.faqs if f.question_zh and f.question_en]
    assert len(both) > 100
    assert all(f.url.startswith("https://www.nisa.moe.gov.tw/") for f in faq_file.faqs)


def test_import_is_repeatable_and_retires_what_the_file_drops(db, faq_file):
    first = import_faqs(db, faq_file)
    assert first["new"] == len(faq_file.faqs) and first["retired"] == 0
    again = import_faqs(db, faq_file)
    assert again == {"new": 0, "updated": 0, "unchanged": len(faq_file.faqs), "retired": 0}

    embed_missing(db, EMBED)
    changed = faq_file.model_copy(deep=True)
    dropped = changed.faqs.pop()
    changed.faqs[0].answer_zh += "（更新）"
    counts = import_faqs(db, changed)
    assert counts["updated"] == 1 and counts["retired"] == 1
    assert db.get(OfficialFaq, dropped.id).active is False
    # Changed or retired questions lose their embedding; the next run embeds the changed one.
    embedded = set(
        db.scalars(
            select(ContentEmbedding.content_id).where(
                ContentEmbedding.content_type == "official_faq"
            )
        )
    )
    assert changed.faqs[0].id not in embedded and dropped.id not in embedded
    assert embed_missing(db, EMBED) == 1


def test_bad_files_are_rejected_before_anything_is_written():
    raw = json.loads(DEFAULT_PATH.read_text(encoding="utf-8"))
    raw["faqs"][0]["category"] = "no-such-category"
    with pytest.raises(ValueError, match="unknown category"):
        FaqFile.model_validate(raw)
    raw = json.loads(DEFAULT_PATH.read_text(encoding="utf-8"))
    raw["faqs"][0]["answer_zh"] = raw["faqs"][0]["answer_en"] = ""
    with pytest.raises(ValueError, match="needs a question and an answer"):
        FaqFile.model_validate(raw)


def test_list_and_detail(api, db, faq_file):
    loaded(db, faq_file)
    body = api.get("/api/faqs").json()
    assert len(body["items"]) == len(faq_file.faqs)
    assert sum(c["count"] for c in body["categories"]) == len(faq_file.faqs)
    assert body["categories"][0]["name"] == {
        "zh": "來臺就學",
        "en": "General Questions and Admissions",
    }
    dates = [i["posted_on"] for i in body["items"]]
    assert dates == sorted(dates, reverse=True)

    detail = api.get("/api/faqs/nisa-934").json()
    assert detail["category"]["zh"] == "簽證/居留證"
    assert detail["answer"]["zh"] and detail["answer"]["en"] and detail["has_english"] is True
    assert detail["agency"]["zh"] and detail["publisher"]["zh"] == "教育部 NISA 計畫辦公室"
    assert detail["url"].endswith("/faq.new/view/sn/934/menu_sn/13")

    # Chinese only: English falls back to the Chinese original, and the app is told.
    zh_only = api.get("/api/faqs/nisa-1076").json()
    assert zh_only["has_english"] is False
    assert zh_only["question"]["en"] == zh_only["question"]["zh"]

    assert api.get("/api/faqs/nisa-0").json()["detail"]["code"] == "faq_not_found"


def test_explore_search_lists_official_questions(api, db, faq_file):
    loaded(db, faq_file)
    body = api.get("/api/search", params={"q": "居留證逾期"}).json()
    assert body["faqs"][0]["id"] == "nisa-934"
    assert body["actions"] == []  # older app builds still read this field
    only_posts = api.get("/api/search", params={"q": "居留證", "kind": "experiences"}).json()
    assert only_posts["faqs"] == []


def test_semantic_search_returns_official_answers(db, faq_file):
    loaded(db, faq_file)
    embed_missing(db, EMBED)
    # The hashing test embedder only matches shared characters, so ask with the indexed text
    # itself: this checks the plumbing (join, visibility, payload), not ranking quality.
    faq = db.get(OfficialFaq, "nisa-934")
    query = embedding_text(faq, db.get(FaqCategory, faq.category_id))
    top = semantic_search(db, EMBED, query, None)["official_faqs"][0]
    assert top["faq_id"] == "nisa-934" and top["distance"] < 0.01
    assert top["answering_agency"] and top["url"].startswith("https://")
    assert len(top["answer"]) <= 1201

    faq.active = False
    db.commit()
    again = semantic_search(db, EMBED, query, None)
    assert "nisa-934" not in {f["faq_id"] for f in again["official_faqs"]}


def test_assistant_reads_the_imported_questions(db, faq_file):
    loaded(db, faq_file)
    forget_cache()
    data = PostgresAssistantData(db=db, viewer=None, embedder=EMBED)
    assert data.search_faqs("駕照", 1)[0].id == "nisa-923"
    faq = data.get_faq("nisa-934")
    assert faq.category.en == "Visa and ARC" and faq.agency.zh


def test_related_posts_are_the_posts_closest_to_the_question(api, db, faq_file):
    seed(db, get_settings().demo_content_path)
    loaded(db, faq_file)
    embed_missing(db, EMBED)
    for experience_id in ("first-rental", "professor-see"):
        sync_experience(db, EMBED, experience_id)

    def vector(content_type: str, content_id: str):
        return db.scalar(
            select(ContentEmbedding).where(
                ContentEmbedding.content_type == content_type,
                ContentEmbedding.content_id == content_id,
            )
        )

    # Make one question mean exactly what the rental post means, and the other post the opposite.
    rental = list(vector("experience", "first-rental").embedding)
    vector("official_faq", "nisa-934").embedding = rental
    vector("experience", "professor-see").embedding = [-x for x in rental]
    db.commit()
    posts = api.get("/api/faqs/nisa-934/related-posts").json()
    assert posts[0]["id"] == "first-rental"
    assert "professor-see" not in [p["id"] for p in posts]  # too far from the question
    assert all("author_id" not in p for p in posts)

    # A viewer who blocked the author doesn't get it.
    kai = {"Authorization": "Bearer dev:kai"}
    api.post("/api/blocks", json={"experience_id": "first-rental"}, headers=kai)
    blocked = api.get("/api/faqs/nisa-934/related-posts", headers=kai).json()
    assert "first-rental" not in [p["id"] for p in blocked]
    assert api.get("/api/faqs/nisa-0/related-posts").status_code == 404


def test_related_posts_fall_back_to_keywords_before_embedding(api, db, faq_file):
    seed(db, get_settings().demo_content_path)
    loaded(db, faq_file)
    assert db.scalar(select(func.count()).select_from(ContentEmbedding)) == 0
    assert api.get("/api/faqs/nisa-934/related-posts").status_code == 200
