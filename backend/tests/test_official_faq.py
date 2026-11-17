"""The official NISA Q&A: import, API, keyword and semantic search, related student posts."""

import json
import random

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
    ReviewIn,
    embed_missing,
    embedding_text,
    import_faqs,
    load,
    load_review,
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
    assert first["new"] == shown(faq_file) and first["retired"] == 0
    again = import_faqs(db, faq_file)
    assert again == {
        "new": 0,
        "updated": 0,
        "unchanged": shown(faq_file),
        "retired": 0,
        "relabelled": 0,
        "school_hidden": len(faq_file.faqs) - shown(faq_file),
    }

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
    assert len(body["items"]) == shown(faq_file)
    assert sum(c["count"] for c in body["categories"]) == shown(faq_file)
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
    # The hashing test embedder spreads other questions unevenly; place them all around.
    _scatter(
        db,
        rental,
        [f.id for f in faq_file.faqs if f.id != "nisa-934" and vector("official_faq", f.id)],
    )
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


def test_the_job_waits_and_retries_when_gemini_refuses_a_batch(db, faq_file):
    from app.rag.embedder import EmbeddingUnavailable

    loaded(db, faq_file)
    calls: list[int] = []
    waits: list[float] = []

    class Flaky(HashingEmbedder):
        def embed_documents(self, texts):
            calls.append(len(texts))
            if len(calls) == 2:  # the second batch hits the per-minute quota once
                raise EmbeddingUnavailable("429")
            return super().embed_documents(texts)

    done = embed_missing(db, Flaky(), batch=100, pause=5, retries=2, sleep=waits.append)
    assert done == shown(faq_file)
    rest = shown(faq_file) - 100
    assert calls[:3] == [100, rest, rest]  # the refused batch is sent again
    assert waits[:2] == [5, 65.0]  # the pause before batch two, then the minute after refusal

    always = HashingEmbedder()
    always.embed_documents = lambda texts: (_ for _ in ()).throw(EmbeddingUnavailable("down"))
    db.execute(ContentEmbedding.__table__.delete())
    db.commit()
    with pytest.raises(EmbeddingUnavailable):
        embed_missing(db, always, retries=1, sleep=lambda _: None)


def test_embedded_text_keeps_only_the_opening_of_long_answers(db, faq_file):
    loaded(db, faq_file)
    faq = max(db.scalars(select(OfficialFaq)), key=lambda f: len(f.answer_zh))
    text = embedding_text(faq, db.get(FaqCategory, faq.category_id))
    fixed = len(faq.question_zh) + len(faq.question_en) + 120  # category names, line breaks
    assert len(faq.answer_zh) > 600
    assert faq.answer_zh[:600] in text and faq.answer_zh[600:] not in text
    assert len(text) <= fixed + 2 * 600


# ---------- reviewed labels (migration 0017) ----------


def test_reviewed_labels_are_imported_and_shown(api, db, faq_file):
    review = load_review()
    school = {i for i, a in review.audience.items() if a == "school"} & {
        f.id for f in faq_file.faqs
    }
    counts = import_faqs(db, faq_file)
    assert school and counts["school_hidden"] == len(school)
    assert counts["new"] == len(faq_file.faqs) - len(school)

    flagged = next(r for r in review.reviews if r.superseded_by)
    body = api.get(f"/api/faqs/{flagged.id}").json()
    assert body["review"]["kind"] == "superseded"
    assert body["review"]["superseded_by"] == flagged.superseded_by
    assert body["review"]["note"]["zh"] == flagged.note_zh
    assert api.get("/api/faqs/nisa-934").json()["review"] is None

    # Relabelling touches no text, so nothing is re-embedded.
    embed_missing(db, EMBED)
    changed = review.model_copy(deep=True)
    changed.reviews.append(ReviewIn(id="nisa-934", kind="conflict", note_zh="說法不一"))
    again = import_faqs(db, faq_file, changed)
    assert again["relabelled"] == 1 and again["updated"] == 0
    assert embed_missing(db, EMBED) == 0


def test_school_administration_questions_are_never_shown(api, db, faq_file):
    """Only checked guidance published by Feng Chia University may cover school
    administration; the MOE answers to other schools' staff are kept out everywhere."""
    review = load_review()
    school = sorted(
        {i for i, a in review.audience.items() if a == "school"} & {f.id for f in faq_file.faqs}
    )
    assert school
    import_faqs(db, faq_file)
    embed_missing(db, EMBED)
    listed = {f["id"] for f in api.get("/api/faqs").json()["items"]}
    assert not listed & set(school)
    assert all(api.get(f"/api/faqs/{i}").status_code == 404 for i in school)
    embedded = set(
        db.scalars(
            select(ContentEmbedding.content_id).where(
                ContentEmbedding.content_type == "official_faq"
            )
        )
    )
    assert not embedded & set(school)
    for i in school[:5]:
        question = next(f for f in faq_file.faqs if f.id == i).question_zh
        if question:
            found = api.get("/api/search", params={"q": question[:40]}).json()["faqs"]
            assert i not in [f["id"] for f in found]

    # A row an earlier import showed is retired, not counted as a dropped question.
    db.add(OfficialFaq(**{**_row_values(faq_file, school[0]), "active": True}))
    db.commit()
    again = import_faqs(db, faq_file)
    assert again["retired"] == 0
    assert db.get(OfficialFaq, school[0]).active is False


def test_review_file_must_name_real_questions(faq_file):
    from app.official_faq import ReviewFile

    bad = ReviewFile(audience={"nisa-0": "school"})
    with pytest.raises(ValueError, match="unknown questions"):
        bad.check(faq_file)


def test_outdated_questions_come_after_in_explore_search(api, db, faq_file):
    import_faqs(db, faq_file)
    labels = {f["id"]: f for f in api.get("/api/faqs").json()["items"]}
    found = api.get("/api/search", params={"q": "居留證"}).json()["faqs"]
    flags = [
        labels[f["id"]]["audience"] == "school"
        or (labels[f["id"]]["review"] or {}).get("kind") in ("superseded", "time_limited")
        for f in found
    ]
    assert flags == sorted(flags)


# ---------- mutual recommendations ----------


def _set_vector(db, content_type: str, content_id: str, vector) -> None:
    row = db.scalar(
        select(ContentEmbedding).where(
            ContentEmbedding.content_type == content_type,
            ContentEmbedding.content_id == content_id,
        )
    )
    row.embedding = list(vector)


def test_a_post_close_to_everything_is_recommended_only_where_it_fits_best(api, db, faq_file):
    """Production 2026-11-18: one short post was 'near' 224 of 227 questions."""
    seed(db, get_settings().demo_content_path)
    loaded(db, faq_file)
    embed_missing(db, EMBED)
    sync_experience(db, EMBED, "first-rental")
    rental = list(
        db.scalar(
            select(ContentEmbedding.embedding).where(ContentEmbedding.content_id == "first-rental")
        )
    )
    # The post sits exactly on one question and fairly close to every other one.
    others = db.scalars(
        select(ContentEmbedding.content_id).where(
            ContentEmbedding.content_type == "official_faq",
            ContentEmbedding.content_id != "nisa-934",
        )
    ).all()
    _set_vector(db, "official_faq", "nisa-934", rental)
    _scatter(db, rental, others)
    db.commit()

    showing = [
        faq_id
        for faq_id in ["nisa-934", *others]
        if api.get(f"/api/faqs/{faq_id}/related-posts").json()
    ]
    assert "nisa-934" in showing
    assert len(showing) <= 3  # K_FAQS: only where it fits best

    # The other direction: the post lists that question (it is a student question).
    related = api.get("/api/experiences/first-rental/related-faqs").json()
    assert related[0]["id"] == "nisa-934"
    assert api.get("/api/experiences/no-such-post/related-faqs").status_code == 404


def test_a_post_that_fits_no_question_better_than_the_rest_is_recommended_nowhere(
    api, db, faq_file
):
    """Production rescan 2026-11-18: with few posts, "Place to Go?" was still some question's
    nearest post. Equally close to everything, it stands out nowhere."""
    seed(db, get_settings().demo_content_path)
    loaded(db, faq_file)
    embed_missing(db, EMBED)
    sync_experience(db, EMBED, "first-rental")
    rental = list(
        db.scalar(
            select(ContentEmbedding.embedding).where(ContentEmbedding.content_id == "first-rental")
        )
    )
    faqs = db.scalars(
        select(ContentEmbedding.content_id).where(ContentEmbedding.content_type == "official_faq")
    ).all()
    _scatter(db, rental, faqs)
    db.commit()
    assert api.get("/api/experiences/first-rental/related-faqs").json() == []
    assert not [f for f in faqs if api.get(f"/api/faqs/{f}/related-posts").json()]


def _scatter(db, around: list[float], faq_ids) -> None:
    """Each question at about the same distance from `around`, in a random direction."""
    rng = random.Random(7)
    for faq_id in faq_ids:
        noise = [rng.gauss(0, 1) for _ in around]
        scale = 0.03 / max(1e-9, (sum(n * n for n in noise) / len(noise)) ** 0.5)
        _set_vector(
            db, "official_faq", faq_id, [a + scale * n for a, n in zip(around, noise, strict=True)]
        )


def test_related_faqs_leave_out_outdated_questions(api, db, faq_file):
    seed(db, get_settings().demo_content_path)
    loaded(db, faq_file)
    embed_missing(db, EMBED)
    sync_experience(db, EMBED, "first-rental")
    rental = db.scalar(
        select(ContentEmbedding.embedding).where(ContentEmbedding.content_id == "first-rental")
    )
    ended = next(r.id for r in load_review().reviews if r.kind == "time_limited")
    _set_vector(db, "official_faq", ended, rental)
    db.commit()
    assert ended not in [
        f["id"] for f in api.get("/api/experiences/first-rental/related-faqs").json()
    ]


def test_an_unindexed_post_has_no_related_questions(api, db, faq_file):
    seed(db, get_settings().demo_content_path)
    loaded(db, faq_file)
    assert api.get("/api/experiences/first-rental/related-faqs").json() == []


def _row_values(faq_file, faq_id: str) -> dict:
    item = next(f for f in faq_file.faqs if f.id == faq_id)
    values = item.model_dump(exclude={"id", "category"})
    return {**values, "id": faq_id, "category_id": item.category, "content_hash": "old"}


def shown(faq_file) -> int:
    """Questions the app shows: all but school administration."""
    school = {i for i, a in load_review().audience.items() if a == "school"}
    return sum(f.id not in school for f in faq_file.faqs)
