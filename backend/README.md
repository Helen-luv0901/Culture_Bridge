# Culture Bridge — Backend

Python 3.12 + FastAPI。目前只有 AI 助理（工作分配 A-11、A-12）；core、登入與其他 API 由 B、D 補上。
架構見 [tech-architecture](../docs/tech-architecture.md) 第三、四節。

## 啟動

```sh
cd backend
uv sync
cp .env.example .env              # 填 GEMINI_API_KEY；沒填時助理一律回備用回覆
set -a; . ./.env; set +a
uv run uvicorn app.main:app --reload
```

```sh
curl -X POST localhost:8000/assistant/message \
  -H 'content-type: application/json' \
  -H 'X-Dev-User-Id: u1' \
  -d '{"message":"工作證要怎麼申請？","locale":"zh-Hant","screen":{"route":"/"}}'
```

`X-Dev-User-Id` 只在 `APP_ENV=development` 有效，用來模擬登入的學生；等 B 接上登入服務後移除。

## 檢查

```sh
uv run ruff check . && uv run ruff format --check .
uv run pytest
```

測試用假的模型（`tests/conftest.py` 的 `ScriptedLLM`），不需要 Gemini 金鑰或網路。

## AI 助理架構（app/assistant/）

```
POST /assistant/message
  └─ Assistant.reply()            agent.py   工具呼叫迴圈
       ├─ LLM.generate()          llm.py     與模型無關的介面；gemini.py 是 Gemini 實作
       ├─ ToolRegistry.execute()  tools.py   驗證參數 → 執行工具 → 錯誤變成結果回給模型
       │    └─ AssistantDataSource data.py   目前讀 flutter_app 示範資料，之後換成 Cloud SQL
       └─ ConversationStore       memory.py  依帳號隔離的短期對話記憶
```

1. 載入這個帳號的對話記錄，加上使用者訊息（附目前畫面資訊）。
2. 呼叫 Gemini（關閉 SDK 自動呼叫，由我們自己執行工具）。
3. 模型要求工具 → 驗證參數、執行、把結果（含呼叫 id）送回模型；最多 `ASSISTANT_MAX_TOOL_ROUNDS` 輪，每輪最多 6 個呼叫。
4. 模型給出文字回答 → 存對話、回傳。
5. Gemini 失敗、空回答、超過輪數 → 回備用回覆（`fallback: true`），這次對話不存。

回覆裡的 `cards`（流程卡含驗證狀態、最後驗證日期、近期成功數；經驗卡標示學生經驗）和 `screen_actions`
都是由工具實際讀到的資料產生，不是從模型文字解析，所以模型無法捏造驗證狀態或任意路由。

### 工具

| 工具 | 說明 |
|---|---|
| search_actions | 關鍵字找流程，回傳驗證狀態、最後驗證日期、近期成功數 |
| get_action | 流程詳情：適用對象、步驟、來源；同時產生流程卡 |
| search_experiences | 依關鍵字、主題、身分找公開經驗（不含作者） |
| get_experience | 經驗原文、摘要、提醒；同時產生經驗卡 |
| get_my_progress | 登入使用者的辦理進度；訪客回 `requires_login` |
| open_screen | 白名單畫面動作（open_action、open_experience、open_explore、open_share、open_progress），會檢查目標存在 |

新增工具：在 `tools.py` 寫一個 `ToolArgs` 參數 model 和 handler，加進 `TOOLS`。參數的 JSON schema 由 pydantic 產生。

### 回覆格式

```json
{
  "conversation_id": "…",
  "text": "依據「申請工作證」流程卡（已驗證，最後驗證 2026-08-16，近 30 天 18 人成功）……",
  "cards": [{"type": "action", "action_id": "work-permit", "title": "申請工作證",
             "verification_status": "verified", "last_verified_at": "2026-08-16",
             "recent_success_count": 18, "sources": ["…"]}],
  "screen_actions": [{"type": "open_action", "target_id": "work-permit", "topic": null}],
  "tools_used": ["search_actions", "get_action"],
  "fallback": false
}
```

清除對話：`DELETE /assistant/conversations/{conversation_id}`。

### 還沒做（後續項目）

- A-13/14：回答規則已寫進 system prompt（`prompts.py`），知識庫尚未建立
- A-17：待確認操作（例如開始辦理）
- A-18：登入限制、頻率限制、每日用量上限
- A-19～22：語意搜尋工具 `semantic_search`
- 換成 Cloud SQL 的 `AssistantDataSource`（需要 B 的 SQLAlchemy／搜尋 API）
