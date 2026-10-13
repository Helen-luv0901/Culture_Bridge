import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select, text

from app.ai.experience_ai import get_experience_ai
from app.assistant.pg_data import PostgresAssistantData
from app.core.auth import CurrentUser
from app.core.config import get_settings
from app.main import app
from app.models import ContentEmbedding, KbChunk
from app.rag.embedder import HashingEmbedder, get_embedder
from app.rag.index import add_document, chunk_text, semantic_search, sync_experience
from app.seed import seed
from tests.test_experiences import FakeAI, publish_new

KAI = {"Authorization": "Bearer dev:kai"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}
EMBED = HashingEmbedder()

WORK_PERMIT_DOC = """外國留學生工作許可申請

在學外國留學生得申請工作許可，每週工作時數最長為二十小時。寒暑假期間不受此限。

申請時應檢附：護照影本、居留證影本、在學證明、學校推薦函。

申請費用為新臺幣一百元，許可期間最長六個月。"""


@pytest.fixture
def api():
    app.dependency_overrides[get_experience_ai] = FakeAI
    app.dependency_overrides[get_embedder] = lambda: EMBED
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def fake_embedder(monkeypatch):
    # The hashing embedder spreads related texts wider than Gemini does.
    monkeypatch.setenv("SEMANTIC_MAX_DISTANCE", "0.9")
    get_settings.cache_clear()
    # Background tasks call get_embedder() directly, not through FastAPI dependencies.
    monkeypatch.setattr("app.api.experiences.get_embedder", lambda: EMBED)
    monkeypatch.setattr("app.api.admin.get_embedder", lambda: EMBED)
    yield
    get_settings.cache_clear()


def test_chunking_keeps_paragraphs_and_limits_size():
    chunks = chunk_text(WORK_PERMIT_DOC, max_chars=80, overlap=10)
    assert all(len(c) <= 80 for c in chunks)
    assert any("二十小時" in c for c in chunks)
    long = chunk_text("句子。" * 400, max_chars=200, overlap=20)
    assert len(long) > 5 and all(len(c) <= 200 for c in long)
    assert chunk_text("   ") == []


def test_official_documents_rank_and_retire(db):
    seed(db, get_settings().demo_content_path)
    doc = add_document(
        db,
        EMBED,
        title="外國留學生工作許可須知",
        url="https://example.gov.tw/work-permit",
        publisher="勞動部",
        document_date=None,
        action_id="work-permit",
        text=WORK_PERMIT_DOC,
        created_by=None,
    )
    found = semantic_search(db, EMBED, "工作許可每週可以工作幾小時", None)
    top = found["official_passages"][0]
    assert top["document_title"] == "外國留學生工作許可須知" and "二十小時" in top["text"]
    assert top["related_action_id"] == "work-permit"

    doc.active = False
    db.commit()
    assert semantic_search(db, EMBED, "工作許可每週可以工作幾小時", None)["official_passages"] == []


def test_user_content_indexed_on_publish_and_removed_on_takedown(api, db):
    published = publish_new(api, original_voice="租房子的時候房東要我押三個月，我不知道正不正常")
    eid = published["id"]
    assert db.scalar(select(func.count()).select_from(ContentEmbedding)) == 1

    found = semantic_search(db, EMBED, "房東 押金 三個月", None)
    [hit] = found["student_content"]
    assert hit["content_id"] == eid and hit["label"] == "student_shared_unverified"
    assert "author" not in str(hit)

    # Blocking the author hides it from that viewer at query time.
    api.post("/api/blocks", json={"experience_id": eid}, headers=KAI)
    assert (
        semantic_search(db, EMBED, "房東 押金", CurrentUser(id="dev-kai"))["student_content"] == []
    )

    # A reviewer hides it: gone from the index immediately.
    api.post(f"/api/admin/experiences/{eid}/hide", headers=REVIEWER)
    assert db.scalar(select(func.count()).select_from(ContentEmbedding)) == 0
    # Restored: indexed again in the background.
    api.post(f"/api/admin/experiences/{eid}/restore", headers=REVIEWER)
    assert db.scalar(select(func.count()).select_from(ContentEmbedding)) == 1

    api.delete(f"/api/experiences/{eid}", headers={"Authorization": "Bearer dev:mei"})
    assert db.scalar(select(func.count()).select_from(ContentEmbedding)) == 0


def test_stale_index_rows_never_leak(db):
    seed(db, get_settings().demo_content_path)
    sync_experience(db, EMBED, "professor-see")
    db.execute(text("UPDATE experiences SET status='hidden' WHERE id='professor-see'"))
    db.commit()
    # Row still in the index (e.g. a crash between steps) but filtered at query time.
    assert db.scalar(select(func.count()).select_from(ContentEmbedding)) == 1
    assert semantic_search(db, EMBED, "教授 再看看", None)["student_content"] == []


def test_reviewed_feedback_words_become_searchable(api, db):
    seed(db, get_settings().demo_content_path)
    mei = {"Authorization": "Bearer dev:mei"}
    execution = api.post("/api/actions/bank/executions", json={}, headers=mei).json()
    api.post(
        f"/api/executions/{execution['id']}/feedback",
        json={
            "kind": "different",
            "category": "documents",
            "original_voice": "銀行說開戶還要附上在學證明正本",
        },
        headers=mei,
    )
    assert semantic_search(db, EMBED, "開戶 在學證明", None)["student_content"] == []
    [item] = api.get("/api/admin/feedback", headers=REVIEWER).json()
    api.post(
        f"/api/admin/feedback/{item['id']}", json={"review_state": "reviewed"}, headers=REVIEWER
    )
    [hit] = semantic_search(db, EMBED, "開戶 在學證明", None)["student_content"]
    assert hit["content_type"] == "execution_feedback"


def test_admin_documents_endpoint_and_assistant_data(api, db):
    seed(db, get_settings().demo_content_path)
    body = {
        "title": "工作許可須知",
        "url": "https://example.gov.tw/wp",
        "publisher": "勞動部",
        "document_date": "2026-09-01",
        "action_id": "work-permit",
        "text": WORK_PERMIT_DOC,
    }
    assert api.post("/api/admin/kb/documents", json=body, headers=KAI).status_code == 403
    created = api.post("/api/admin/kb/documents", json=body, headers=REVIEWER).json()
    assert created["chunk_count"] == db.scalar(select(func.count()).select_from(KbChunk)) > 0

    data = PostgresAssistantData(db, None, embedder=EMBED)
    result = data.semantic_search("申請工作許可要帶什麼文件", 3)
    assert result["official_passages"][0]["document_date"] == "2026-09-01"

    api.post(f"/api/admin/kb/documents/{created['id']}/active?active=false", headers=REVIEWER)
    assert api.get("/api/admin/kb/documents", headers=REVIEWER).json()[0]["active"] is False


def test_evaluation_harness(db):
    from app.rag.evaluate import DEFAULT_CASES, evaluate

    seed(db, get_settings().demo_content_path)
    for eid in ("professor-see", "first-rental", "class-invitation"):
        sync_experience(db, EMBED, eid)
    import json

    cases = json.loads(DEFAULT_CASES.read_text(encoding="utf-8"))
    report = evaluate(db, EMBED, cases, k=3)
    assert report.cases == len(cases)
    # Even the crude hashing embedder finds most demo experiences; Gemini should find all.
    assert report.hits >= len(cases) // 2
    assert report.expected_distances
