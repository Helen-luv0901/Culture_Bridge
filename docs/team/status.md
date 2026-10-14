# 目前進度與剩下的工作（2026-10-14）

對照[工作分配表](work-assignment.md)。程式能做的都已完成並合併到 `main`；下面列的是**還沒完成**、而且大多要由人來做或決定的事。

## 已上線

網址 https://culture-bridge-z7gcp33vjq-de.a.run.app （Cloud Run `culture-bridge`，資料庫 Cloud SQL `culturebridge-db`）：

- 流程卡、辦理進度、卡關／差異回報、學生經驗（AI 整理、翻譯、反應、「我的經驗不同」）
- AI 助理（工具呼叫、語意搜尋、待確認操作）
- Google 登入、刪除帳號、檢舉與封鎖、管理介面、數據
- 18 張官方流程卡**草稿**（還不公開）
- 收藏想再看的經驗、暱稱／真名與發文署名、新 App 圖示
- AI 模型 `gemini-3.8-flash`（原本的 2.5-flash 已不開放給新使用者）

**合併到 `main` 且 CI 通過就會自動部署**（GitHub → Actions → Deploy）。要暫停：把 GitHub 變數 `AUTO_DEPLOY` 改成 `false`；手動部署：`bash scripts/deploy.sh`。

## A（基礎設施、AI）

- [x] 自動部署（2026-10-14 設定完成，Deploy #6 成功）
- [ ] 刪除已合併的舊分支：`claude/assistant-next`、`claude/backend-api`、`docs/cloud-sql-and-work-plan`、`fix/gcp-setup-runbook-fixes`（GitHub → Branches；都已併入 `main`）
- [ ] A-10 分支保護：`main` 要求 PR 且 CI 通過（GitHub → Settings → Branches）
- [ ] A-4 網域與 HTTPS：決定是否買網域（目前用 `run.app`，已有 HTTPS）
- [ ] A-5 Gemini 方案：原本的付費金鑰預付額度已用完（2026-10-14，AI 回 402）。不付費就改用免費金鑰：`bash scripts/set-gemini-key.sh`（[步驟](../runbooks/a5-gemini-api-key.md#不付費改用免費金鑰)）。免費方案可能被 Google 用來改善產品，會影響隱私權政策與 Play「資料安全性」；也有次數限制
- [ ] A-8 App 閃退監控：Android 版做出來後再接 Crashlytics（伺服器監控與 Email 警報已完成）
- [ ] A-18 訪客能不能用 AI 助理：目前正式環境只有登入者能用
- [ ] A-24 檢索品質測試在正式資料上跑一次：`uv run python -m app.rag.evaluate`（需要 Gemini 金鑰）

## B（後端）

- [ ] B-22 AI 摘要品質：收集 20 則真實分享，跑 `uv run python -m app.quality.summary_review shares.json -o summary-review.md`，逐則檢查
- [x] B-23 審查用帳號：不用另外準備，任何 Google 帳號都能登入（見 [Play 其他聲明](../drafts/play-console-declarations.md)）

## C（App）

- [ ] C-2 Android 實際編譯、設定最低 Android 版本（[說明](../runbooks/c2-android-build.md)）
- [ ] C-3 套件名稱定案（`com.culturebridge.culture_bridge`；第一次上傳 Play 後不能改）
- [ ] C-18 建立上傳金鑰並打包 AAB
- [ ] C-19 至少 3 種機型實機測試（[手動測試清單](../engineering/manual-test-checklist.md)）
- [ ] C-20 圖示與截圖目前是暫定版（`docs/store/`），上架前用正式流程卡重拍
- [ ] C-21 PMP 試用與共創工作坊（[任務腳本](pmp-pilot-script.md)）

## D（內容、上架、營運）

- [ ] **D-8 審查 18 張流程卡**：網頁版「管理 → 流程」對照官方來源修正後發布（[清單與注意事項](../content/d8-official-procedures.md)）
- [ ] D-9 申請 Play 開發者帳號並完成身分驗證
- [ ] D-10 內部／封閉測試軌道（個人開發者帳號需 12 位測試者連續 14 天）
- [ ] D-11 隱私權政策、服務條款定稿，並放到公開網址（Play 必填）
- [ ] D-12 在 Play Console 填資料安全性、內容分級、廣告聲明（草稿已備好）
- [ ] D-13 商店頁文案定稿（草稿已備好）
- [ ] D-14 送審正式版
- [ ] D-17 AI 助理 20 題品質測試：`uv run python -m app.quality.assistant_review`，逐題檢查並回報 A
- [ ] D-18 日常處理檢舉與待審回報（管理介面）
- [ ] D-19 成效數據：管理介面「數據」分頁，或 `GET /api/admin/stats`

## 要大家一起決定

套件名稱、最低 Android 版本、Gemini 方案、正式網域、目標年齡層（是否有未滿 18 歲的使用者）、商店頁能不能寫逢甲大學、訪客能不能用 AI 助理。
