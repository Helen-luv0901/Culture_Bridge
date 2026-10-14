import json
from datetime import UTC, datetime

from fastapi.testclient import TestClient

from app.main import app
from app.official_content import DEFAULT_PATH, _importer, import_card

REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}
WHEN = datetime(2026, 10, 14, tzinfo=UTC)
CARD = {
    "slug": "arc-extension",
    "title_zh": "居留證延期",
    "title_en": "Extend your ARC",
    "description_zh": "到期前申請延期[1]。",
    "description_en": "Apply before it expires.",
    "applicable_to": "外國學生",
    "applicable_to_en": "Foreign students",
    "location": "線上申辦",
    "location_en": "Online",
    "steps": [
        {
            "title_zh": "準備在學證明",
            "title_en": "Get an enrollment certificate",
            "notes": "一個月內[1][2]",
        },
        {"title_zh": "線上送出", "title_en": "Apply online", "notes": None},
    ],
    "sources": [
        {
            "title": "送件須知",
            "url": "https://www.immigration.gov.tw/example.pdf",
            "publisher": "內政部移民署",
            "kind": "official",
            "evidence_note": "文件與期限",
        },
        {
            "title": "國際處說明",
            "url": "https://www.fcu.edu.tw/example",
            "publisher": "逢甲大學國際處",
            "kind": "institution",
            "evidence_note": "在學證明",
        },
    ],
}


def test_import_creates_unpublished_drafts_with_sources(db):
    _importer(db)
    assert import_card(db, CARD, WHEN) == "new draft"
    assert import_card(db, CARD, WHEN) == "skipped (a draft is already open)"

    api = TestClient(app)
    assert api.get("/api/actions/arc-extension").status_code == 404  # not public until published
    [draft] = api.get("/api/admin/actions/arc-extension/versions", headers=REVIEWER).json()
    assert draft["published_at"] is None and draft["verification_status"] == "unverified"
    assert draft["description_zh"] == "到期前申請延期（內政部移民署）。"
    assert draft["steps"][0]["notes"] == "一個月內（內政部移民署、逢甲大學國際處）"
    assert {s["url"] for s in draft["sources"]} == {s["url"] for s in CARD["sources"]}

    # After a reviewer publishes, a re-import opens v2 and reuses the same sources.
    api.post(f"/api/admin/versions/{draft['id']}/publish", headers=REVIEWER)
    assert import_card(db, CARD, WHEN) == "new draft v2"
    assert len(api.get("/api/admin/sources", headers=REVIEWER).json()) == 2


def test_bundled_cards_import_cleanly(db):
    """The researched first batch (D-8) imports as drafts; nothing becomes public."""
    data = json.loads(DEFAULT_PATH.read_text(encoding="utf-8"))
    slugs = [c["slug"] for c in data["cards"]]
    assert len(slugs) == len(set(slugs)) >= 8
    when = datetime.fromisoformat(data["accessed_at"])
    _importer(db)
    for card in data["cards"]:
        assert card["sources"] and all(s["url"].startswith("https://") for s in card["sources"])
        assert import_card(db, card, when) == "new draft"
        assert import_card(db, card, when).startswith("skipped")

    api = TestClient(app)
    assert api.get("/api/actions").json() == []
    versions = api.get("/api/admin/actions/work-permit/versions", headers=REVIEWER).json()
    assert "[" not in versions[0]["steps"][0]["notes"]  # markers became publisher names
    urls = {s["url"] for c in data["cards"] for s in c["sources"]}
    assert len(api.get("/api/admin/sources", headers=REVIEWER).json()) == len(urls)  # shared
