# A-5：申請 Gemini 金鑰並設定用量上限

後端用 Gemini Developer API（`google-genai` 套件、API 金鑰），金鑰只放後端，不放進 App 或 repo。

> 方案、免費額度與資料使用條款會變動，以申請當下 Google 的頁面為準。標【確認】的地方請先看過再做。

## 1. 建立金鑰

1. 到 [Google AI Studio](https://aistudio.google.com) → Get API key → Create API key
2. 專案選 **culture-bridge**，讓用量和費用都歸在同一個 Google Cloud 專案
3. 【確認】方案：免費方案的條款可能允許 Google 用送出的內容改善產品。我們會送出學生分享的原文和助理對話，
   建議改用付費方案（費用從專案的帳單帳戶與試用額度扣），並把結果告訴 D 寫進隱私權政策（D-11）

## 2. 限制金鑰

Google Cloud 主控台 → API 和服務 → 憑證 → 點這把金鑰：

- API 限制：只允許 **Generative Language API**
- 名稱改成 `culture-bridge-backend`，方便日後辨認或撤銷

## 3. 設定用量上限

- Google Cloud 主控台 → API 和服務 → Generative Language API → **配額**：把每日請求數調低到夠開發用就好
- 帳單 → **預算與快訊**：設一個 Gemini 專用預算，達到 50%、90%、100% 時寄信
- 後端另有自己的上限：`ASSISTANT_DAILY_LLM_CALLS`（全體每日呼叫數）、`ASSISTANT_PER_DAY`（每人每日訊息數），
  見 [backend/README.md](../../backend/README.md)

## 4. 測試金鑰

```sh
export GEMINI_API_KEY='<金鑰>'
# 看有哪些模型可用，挑一個設成 GEMINI_MODEL（預設 gemini-2.5-flash）
curl -s https://generativelanguage.googleapis.com/v1beta/models \
  -H "x-goog-api-key: $GEMINI_API_KEY" | grep '"name"'
```

接著實測助理：

```sh
cd backend
cp .env.example .env     # 填入 GEMINI_API_KEY（.env 不會進 repo）
set -a; . ./.env; set +a
uv run uvicorn app.main:app --reload
curl -X POST localhost:8000/assistant/message -H 'content-type: application/json' \
  -H 'X-Dev-User-Id: u1' -d '{"message":"工作證要怎麼申請？","locale":"zh-Hant"}'
```

回覆的 `fallback` 應該是 `false`，`tools_used` 應該有 `search_actions` 或 `get_action`。

## 5. 保管

- 本機：`backend/.env`（已在 .gitignore）
- 正式環境：Secret Manager

```sh
printf '%s' "$GEMINI_API_KEY" | gcloud secrets create gemini-api-key --data-file=- --project=culture-bridge
```

- 金鑰不貼在聊天群組、文件或截圖裡；外流時立刻在「憑證」頁刪除並重建
