# A-5：申請 Gemini 金鑰並設定用量上限

後端用 Gemini Developer API（`google-genai` 套件、API 金鑰），金鑰只放後端，不放進 App 或 repo。

> 方案、免費額度與資料使用條款會變動，以申請當下 Google 的頁面為準。標【確認】的地方請先看過再做。

## 1. 建立金鑰

1. 到 [Google AI Studio](https://aistudio.google.com) → Get API key → Create API key
2. 專案選 **culture-bridge**，讓用量和費用都歸在同一個 Google Cloud 專案
3. 【確認】方案：免費方案的條款可能允許 Google 用送出的內容改善產品。我們會送出學生分享的原文和助理對話，
   建議改用付費方案（費用從專案的帳單帳戶與試用額度扣），並把結果告訴 D 寫進隱私權政策（D-11）

### 不付費：改用免費金鑰

正式專案 `culture-bridge-511321` 已連結帳單（Cloud Run 需要），所以在它底下建的金鑰都走付費方案；預付額度用完時 Gemini 會回 `402 RESOURCE_EXHAUSTED ... prepayment credits are depleted`。不想付費時：

1. [Google AI Studio](https://aistudio.google.com) → API keys → **Create API key** → 選 **Create project**（新專案，**不要**連結帳單）
2. 在 API keys 列表確認這把金鑰的方案是 **Free tier**
3. 在 Cloud Shell 執行 `cd ~/Culture_Bridge && git pull && bash scripts/set-gemini-key.sh`，把金鑰貼上（畫面不會顯示）。
   指令會先測試這把金鑰能用哪個模型，確定能用才存進 Secret Manager、設定 `GEMINI_MODEL` 並重新啟動服務；不需要重新部署
4. `bash scripts/check-ai.sh`，第 4、5 步顯示 OK 就完成

免費方案的代價：

- 每分鐘、每天的次數有限制（每個模型分開算，見 AI Studio → Usage → Rate limit）。`GEMINI_MODEL` 用完時後端自動改用 `GEMINI_FALLBACK_MODELS`（預設 `gemini-3.1-flash-lite`，額度和 3.5 Flash Lite 一樣；再來是 `gemini-2.5-flash-lite`，每天 20 次），全部用完才會暫時無法使用（`429`），隔天恢復。免費方案常遇到 `503`（Google 端忙碌，2026-10-27 實測 3.1 Flash Lite 10 次只有 6 次在 4 次內成功）：後端會在同一個模型再試 2 次、再換下一個，一個請求最多等 45 秒。`bash scripts/check-ai.sh` 第 4b 步會一起測備用模型
- Google 可能用送出的內容改善產品：上架前要在隱私權政策寫清楚，Play「資料安全性」也要重新評估（D-11、D-12）

## 2. 限制金鑰

Google Cloud 主控台 → API 和服務 → 憑證 → 點這把金鑰：

- API 限制：只允許 **Generative Language API**
- 名稱改成 `culture-bridge-backend`，方便日後辨認或撤銷

## 3. 設定用量上限

- Google Cloud 主控台 → API 和服務 → Generative Language API → **配額**：把每日請求數調低到夠開發用就好
- 帳單 → **預算與快訊**：設一個 Gemini 專用預算，達到 50%、90%、100% 時寄信
- 後端另有自己的上限（存在資料庫，重啟不會歸零）：`GEMINI_DAILY_CALLS`（所有 Gemini 呼叫每日總數，含翻譯與 embedding）、`ASSISTANT_DAILY_LLM_CALLS`（助理每日呼叫數）、`ASSISTANT_PER_DAY`（每人每日訊息數），
  見 [backend/README.md](../../backend/README.md)

## 4. 測試金鑰

```sh
export GEMINI_API_KEY='<金鑰>'
# 看有哪些模型可用，挑一個設成 GEMINI_MODEL（預設 gemini-3.8-flash；Google 會停止提供舊模型給新使用者，出現 404 NOT_FOUND 時就換成錯誤訊息建議的模型）
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
