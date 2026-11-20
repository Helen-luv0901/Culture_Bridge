"""Official questions under each procedure card (hand-picked, app/content/procedure_faqs.json)."""

import json

from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.official_faq import import_faqs, load, load_review
from app.seed import seed
from app.services import faqs as faq_service
from app.services.faqs import PROCEDURE_FAQS_PATH


def test_every_picked_question_is_a_shown_student_question():
    data = json.loads(PROCEDURE_FAQS_PATH.read_text(encoding="utf-8"))["procedures"]
    file = load(faq_service.Path(__file__).resolve().parent.parent / "app/content/nisa_faq.json")
    known = {f.id for f in file.faqs}
    review = load_review()
    school = {i for i, a in review.audience.items() if a == "school"}
    outdated = {r.id for r in review.reviews if r.kind in ("superseded", "time_limited")}
    picked = {i for ids in data.values() for i in ids}
    assert picked <= known
    assert not picked & (school | outdated)
    assert all(1 <= len(ids) <= 3 for ids in data.values())


def test_a_procedure_lists_its_questions_and_skips_hidden_ones(db, monkeypatch):
    seed(db, get_settings().demo_content_path)
    api = TestClient(app)
    import_faqs(
        db, load(faq_service.Path(__file__).resolve().parent.parent / "app/content/nisa_faq.json")
    )
    school = next(i for i, a in load_review().audience.items() if a == "school")
    monkeypatch.setattr(
        faq_service, "_procedure_faq_ids", lambda: {"bank": ["nisa-1002", school, "nisa-0"]}
    )
    found = api.get("/api/actions/bank/related-faqs").json()
    assert [f["id"] for f in found] == ["nisa-1002"]  # school-only and unknown ids left out
    assert api.get("/api/actions/no-such-card/related-faqs").status_code == 404
