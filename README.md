# Culture Bridge

幫國際生在台灣辦事、生活的 App：**官方流程卡**告訴你步驟和依據，**學生經驗**讓你知道別人遇過什麼，**AI 助理**依真實資料回答並標明依據與驗證狀態。

> 目前是 MVP 開發中：網頁版先上線（Google Cloud Run），Android 版之後上架 Google Play。

## 主要功能

| 功能 | 說明 |
|---|---|
| 制度流程 | 工作證、居留證、健保、開戶等流程卡；每個版本有官方來源、驗證狀態與最後驗證日；可「開始辦理」記錄步驟進度、回報卡關或「流程不同」 |
| 學生經驗 | 用一句話分享經驗 → AI 整理成情境／感受／提醒 → 作者確認後才匿名發布；中英 AI 翻譯、「有幫助」「我也遇過」、「我的經驗不同」 |
| AI 助理 | 浮動在每一頁的小助手；每次回答都透過工具查流程與經驗（含語意搜尋），沒有資料就直說；會寫入資料的要求先產生待確認操作 |
| 審查後台 | 流程編輯與版本發布、來源與驗證紀錄、回報審查（含 AI 整理）、檢舉處理、官方文件、權限與成效數據 |
| 安全與隱私 | Google 登入（Firebase）、對外匿名、檢舉與封鎖、刪除帳號與所有資料 |

## 技術架構

```
瀏覽器 / Android ── Flutter（flutter_app/）
        │  /api
        ▼
Cloud Run：FastAPI 後端（backend/）＋同一個服務提供 Flutter 網頁版
        ├─ Cloud SQL for PostgreSQL（pgvector 語意搜尋）
        ├─ Gemini（經驗摘要、翻譯、助理、embedding）
        └─ Firebase Authentication（Google 登入）
```

細節與決策紀錄見 [技術架構](docs/tech-architecture.md)。

## 專案結構

| 路徑 | 內容 |
|---|---|
| `flutter_app/` | 現行 App（網頁、Android、iOS 共用）— [說明](flutter_app/README.md) |
| `backend/` | Python 3.12 FastAPI 後端、AI 助理、Alembic migration — [說明](backend/README.md) |
| `database/` | PostgreSQL schema（`schema_postgres.sql` 為第一版 migration）與 SQLite 草案 |
| `scripts/` | Google Cloud 一步步設定腳本 `gcp-setup.sh`、搬遷筆數比對 `compare-migration.sh` |
| `docs/` | 產品、資料庫、分工、runbook、測試清單、上架文件草稿 |
| `Dockerfile` | 建置網頁版＋後端的單一映像檔（Cloud Run 用） |
| `frontend/`、`prototype/` | 早期的 React 版與靜態 mockup，只保留作參考 |

## 本機快速開始

需要 Python 3.12＋[uv](https://docs.astral.sh/uv/)、Docker、Flutter 3.47.7。完整步驟見 [開發環境安裝](docs/dev-setup.md)。

```sh
# 資料庫（含 pgvector）
docker run -d --name cb-postgres -p 5432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust pgvector/pgvector:pg16
docker exec cb-postgres createdb -U postgres culturebridge

# 後端 → http://localhost:8000/api/docs
cd backend && uv sync && cp .env.example .env && set -a && . ./.env && set +a
uv run alembic upgrade head && uv run python -m app.seed && uv run uvicorn app.main:app --reload

# 網頁版（另開終端機）
cd flutter_app && flutter pub get
flutter run -d chrome --web-port 5174 --dart-define=API_BASE_URL=http://localhost:8000
```

開發環境不用 Firebase：登入頁輸入名字即可（`dev:<名字>`，審查者 `dev:<名字>:reviewer`）。

## 測試

| 範圍 | 指令 |
|---|---|
| 後端 | `cd backend && uv run pytest && uv run ruff check . && uv run ruff format --check .` |
| Flutter | `cd flutter_app && flutter analyze && flutter test` |
| Schema | `python database/test_schema.py` |

每個 PR 會由 GitHub Actions（`.github/workflows/ci.yml`）自動跑以上檢查。

## 部署

在 [Google Cloud Shell](https://shell.cloud.google.com) 執行 `bash scripts/gcp-setup.sh`，依選單完成專案、資料庫、Gemini 金鑰、Firebase、部署與監控。

- [A-3 Cloud SQL 搬遷](docs/runbooks/a3-cloud-sql-migration.md)
- [A-5 Gemini 金鑰](docs/runbooks/a5-gemini-api-key.md)
- [A-7 部署到 Cloud Run](docs/runbooks/a7-deploy-cloud-run.md)
- [剩下的 Google Cloud 步驟（交接）](docs/runbooks/next-steps-gcp.md)

密碼與金鑰只放在 Secret Manager，不要寫進 repo 或貼到群組。

## 文件

- 產品：[Product Map](docs/product-map.md)、[Experience-Led MVP](docs/experience-led-mvp.md)、[設計](design.md)、[響應式 UI](docs/responsive-ui.md)
- 資料：[Database Schema 與範例查詢](docs/database-schema.md)、[PostgreSQL Schema](database/schema_postgres.sql)
- 團隊：[工作分配表](docs/work-assignment.md)、[Flutter 遷移紀錄](docs/flutter-migration.md)
- 測試與試用：[手動測試清單](docs/manual-test-checklist.md)、[PMP 試用任務腳本](docs/pmp-pilot-script.md)
- 上架草稿（需審閱）：[隱私權政策](docs/drafts/privacy-policy.md)、[服務條款與社群規範](docs/drafts/terms-and-community-guidelines.md)、[商店頁文案](docs/drafts/store-listing.md)

## 協作規則

- `main` 只透過 PR 合併，PR 由另一位組員檢查
- 改資料表一律新增 Alembic migration（`backend/migrations/versions/`），不要直接改雲端資料庫
