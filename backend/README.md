# Culture Bridge — Backend

Python 3.12 + FastAPI + SQLAlchemy 2 + PostgreSQL（Cloud SQL，含 pgvector）。所有 API 在 `/api` 底下；正式環境同一個服務也提供 Flutter 網頁版（`WEB_DIR`）。
架構見 [tech-architecture](../docs/tech-architecture.md)；本機安裝見 [dev-setup](../docs/dev-setup.md)；部署見 [A-7 部署步驟](../docs/runbooks/a7-deploy-cloud-run.md)。

## 結構

```
app/
├── main.py            進入點：/api 路由、/api/config、/health（本機另有 /healthz）、網頁版與 /account-deletion
├── web.py             提供 Flutter 網頁版（不存在的路徑回 index.html）
├── api/               路由：me、actions（流程與辦理）、experiences、moderation、assistant、admin
├── services/          商業邏輯：actions、admin_actions、experiences、moderation
├── assistant/         AI 助理：工具呼叫迴圈、工具、知識庫、對話記憶、待確認操作、用量限制
├── rag/               語意搜尋：embedding、建立／移除索引、官方文件切段、檢索品質評估
├── ai/                經驗摘要與翻譯、回報整理（Gemini 結構化輸出）
├── quality/           人工品質檢查用的評分表產生器（D-17、B-22）
├── models/            SQLAlchemy 對應（資料表規則在資料庫的 CHECK 與 trigger）
├── core/              設定、資料庫連線、Firebase 登入驗證、權限、錯誤格式
└── seed.py            匯入 Flutter 示範資料（開發／測試站用）
migrations/            Alembic：0001 = schema_postgres.sql，0002 檢舉／封鎖／操作紀錄／待確認操作，
                       0003 流程英文欄位，0004 語意搜尋（pgvector），0005 使用數據
tests/                 pytest（真的 PostgreSQL；CI 用 pgvector/pgvector:pg16）
```

## 指令

```sh
uv sync
uv run alembic upgrade head          # Cloud SQL 第一次：先 alembic stamp 0001_initial_schema
uv run python -m app.seed            # 示範資料（只在 APP_ENV=development，或加 --force）
uv run uvicorn app.main:app --reload
uv run pytest
uv run ruff check . && uv run ruff format --check .
uv run python -m app.rag.evaluate    # 語意搜尋品質（需要 GEMINI_API_KEY；--fake 可離線跑）
uv run python -m app.quality.assistant_review              # D-17：20 題助理回答 → assistant-review.md 評分表
uv run python -m app.quality.summary_review shares.json    # B-22：真實分享的 AI 摘要 → summary-review.md（shares.json 不進 repo）
```

## 登入與權限

- App 用 Firebase Authentication（Google）登入，送 `Authorization: Bearer <Firebase ID token>`；後端驗證簽章、audience、issuer，第一次登入時建立 `users`（只存 `firebase:<uid>`，不存 Email 或密碼）
- 角色存在我們的資料庫：student（預設）、reviewer、admin；`/api/admin/*` 需要 reviewer 以上，改角色需要 admin
- `APP_ENV=development` 時可用 `Bearer dev:<名字>[:<角色>]` 或 `X-Dev-User-Id: <名字>`；其他環境一律拒絕

## API 一覽

完整規格（OpenAPI）：執行後開 `/api/docs`。

| 分組 | 路徑 | 說明 |
|---|---|---|
| 設定 | `GET /api/config` | 網頁版啟動時讀取的公開設定（Firebase web 設定、環境） |
| 我 | `GET/PATCH/DELETE /api/me` | 個人資料（語言、暱稱、真實姓名）；刪除帳號與所有資料（B-17） |
| 流程 | `GET /api/actions`、`/api/actions/{id}` | 最新已發布版本、驗證狀態、最後驗證日、近 30 天成功數、各步驟卡關數、來源 |
| 辦理 | `POST /api/actions/{id}/executions`、`GET /api/me/executions`、`PUT /api/executions/{id}/steps/{step}`、`POST …/finish`、`POST …/feedback` | 綁定版本的辦理紀錄、步驟進度、結果、卡關／差異回報 |
| 經驗 | `GET /api/experiences`、`/{id}`、`POST /api/experiences`、`PATCH`、`DELETE`、`POST …/summaries`、`POST …/publish`、`POST …/translations`、`PUT/DELETE …/reactions/{kind}`、`PUT/DELETE …/saved`、`GET /api/me/saved`、`GET /api/me/experiences` | 探索、草稿、AI 摘要、作者確認後發布（`author_display`：匿名／暱稱／真名）、翻譯、反應、收藏（私人「想再看」清單）、我的經驗與影響 |
| 搜尋 | `GET /api/search?q=` | 流程與經驗關鍵字搜尋（B-16） |
| 檢舉／封鎖 | `POST /api/reports`、`POST /api/blocks`、`GET /api/me/blocks`、`DELETE /api/me/blocks/{id}` | 3 人檢舉自動隱藏待審；封鎖匿名作者（只回傳不透明 id） |
| 助理 | `POST /api/assistant/message`、`DELETE /api/assistant/conversations/{id}`、`GET/POST /api/assistant/operations/{id}[/confirm|/cancel]` | 見下方 |
| 管理 | `/api/admin/actions`、`/versions/{id}`、`/sources`、`/feedback`、`/actions/{id}/feedback-summary`、`/reports`、`/experiences/{id}/hide|restore`、`/users`、`/users/{id}/role`、`/kb/documents`、`/stats` | 流程編輯與發布、驗證紀錄、回報審查與 AI 整理（D-7，只供參考）、檢舉、角色、官方文件、成效數據（D-19） |

錯誤一律是 `{"detail": {"code": "...", "message": "..."}}`（驗證錯誤為 FastAPI 預設的 422 格式）。

## AI 助理（app/assistant/）

```
POST /api/assistant/message
  └─ Assistant.reply()            agent.py   工具呼叫迴圈（關閉 SDK 自動執行，由我們執行工具）
       ├─ LLM.generate()          llm.py     與模型無關的介面；gemini.py 是 Gemini 實作；limits.py 每日總量
       ├─ ToolRegistry.execute()  tools.py   驗證參數 → 執行工具 → 錯誤變成結果回給模型
       │    ├─ PostgresAssistantData pg_data.py  流程、經驗、辦理進度、語意搜尋（依觀看者套用封鎖）
       │    └─ DbOperationService db_operations.py  待確認操作（assistant_operations）
       └─ ConversationStore       memory.py  依帳號隔離的短期對話記憶（只在記憶體）
```

工具：`search_actions`、`get_action`、`search_experiences`、`get_experience`、`get_my_progress`、`open_screen`（白名單畫面動作）、`semantic_search`、`search_app_help`（App 使用說明知識庫）、`propose_start_action`（只產生待確認操作）。

回覆的 `cards`（流程卡含驗證狀態、最後驗證日、近期成功數；經驗卡標示學生經驗）、`screen_actions`、`pending_operations` 都由工具實際讀到的資料產生，模型無法捏造「已驗證」或任意路由。Gemini 失敗、空回答、超過輪數或超過每日總量時回備用回覆（`fallback: true`）。

## 語意搜尋（app/rag/）

- 官方文件：`/api/admin/kb/documents` 貼全文 → 依段落切塊 → Gemini embedding（768 維）→ `kb_chunks`；過時文件停用
- 使用者內容：經驗發布（翻譯後）、回報經審查採納後建立索引；隱藏、刪除、檢舉下架、刪除帳號時同步移除；索引不含作者
- 查詢時再次檢查可見性與封鎖；官方段落排在前、學生內容標示未經驗證
- `SEMANTIC_MAX_DISTANCE` 控制相似度門檻，用 `python -m app.rag.evaluate` 在真實 embedding 上調整

## 設定（環境變數）

| 變數 | 預設 | 說明 |
|---|---|---|
| `APP_ENV` | development | production 時關閉開發登入與 CORS |
| `DATABASE_URL` | 本機 culturebridge | Cloud SQL：`postgresql+psycopg://postgres:<pw>@/culturebridge?host=/cloudsql/<專案>:<區域>:<執行個體>` |
| `FIREBASE_PROJECT_ID` | — | 驗證 ID token 的 audience |
| `FIREBASE_WEB_API_KEY`、`FIREBASE_WEB_APP_ID`、`FIREBASE_AUTH_DOMAIN`、`FIREBASE_MESSAGING_SENDER_ID` | — | 經 `/api/config` 給網頁版 |
| `GEMINI_API_KEY`、`GEMINI_MODEL`、`EMBEDDING_MODEL` | —、gemini-2.5-flash、gemini-embedding-001 | 沒有金鑰時 AI 功能回「暫時無法使用」 |
| `AI_SUMMARIES_PER_DAY` | 20 | 每人每日 AI 摘要次數 |
| `ASSISTANT_ALLOW_GUESTS` | development 時 true | 訪客能否使用助理（待團隊決定） |
| `ASSISTANT_PER_MINUTE`、`ASSISTANT_PER_DAY`、`ASSISTANT_DAILY_LLM_CALLS` | 10、100、3000 | 助理頻率與用量上限 |
| `SEMANTIC_MAX_DISTANCE` | 0.6 | 語意搜尋門檻 |
| `WEB_DIR` | — | Flutter 網頁版建置結果，設定時由後端提供 |
