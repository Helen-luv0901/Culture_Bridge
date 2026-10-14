# 交接：Google Cloud 剩下的步驟（給操作瀏覽器的 Claude 或組員）

狀態（2026-10-14）：
- 專案 ID：`culture-bridge-511321`，區域 `asia-east1`
- ✅ 步驟 0 專案與 API
- ✅ 步驟 2 資料庫搬遷：新執行個體 `culturebridge-db`（PostgreSQL 18、db-f1-micro），資料庫 `culturebridge`，帳號 `postgres`；連線字串在 Secret Manager `database-url`；筆數比對全部一致（`bash scripts/compare-migration.sh`）
- ✅ 步驟 3 Gemini 金鑰：存在 Secret Manager `gemini-api-key`（第一次執行時金鑰被印到畫面上，已手動換新；腳本已修正，不會再印出）
- ✅ 步驟 4 Firebase 登入：Google 登入已啟用，公開名稱「Culture Bridge」；兩個 `run.app` 網域都已加入 Authorized domains
- ✅ 步驟 5 部署：第一次 revision `culture-bridge-00001-j21`（`bf91e54`）；2026-10-14 重新部署 `main` 為 `culture-bridge-00002-bx2`（`986a231`，含 migration `0005_usage_metrics`）
- ✅ 再部署 `culture-bridge-00003-bmt`（`main` `47a8220`）；✅ 步驟 7 第一次匯入 11 張官方流程卡草稿
- ✅ 步驟 6 監控：uptime check `culture-bridge-uptime`（檢查 `/api/config`），Email 警報政策「culture-bridge is down」
- ✅ 步驟 1 費用警報：每月 1000TWD
- ✅ 第 6 節 第一位管理者：已設定
- ✅ 第 7 節 舊試用執行個體 `free-trial-first-project` 已刪除（刪前確認 `postgres` 資料庫沒有資料表），匯出用的 bucket 也一併刪除；目前只剩 `culturebridge-db`，備份靠它的每日自動備份
- 以後重新部署：`git checkout main && git pull` 後執行 `bash scripts/gcp-setup.sh 5`，「第一次接 Alembic 嗎？」要回答 **N**；Cloud Shell 出現 `You do not currently have an active account selected` 時，重新整理頁面並在「授權 Cloud Shell」按授權

2026-10-14 實際執行時遇到、已在腳本修正的問題（下一個人照跑就不會再遇到）：
- `gcloud services api-keys create --format=none` 仍會印出 `keyString`：步驟 3 現在把輸出藏起來，失敗時只顯示遮掉金鑰的錯誤
- 新專案的 Cloud Build 用 `<專案編號>-compute@developer.gserviceaccount.com` 執行，`gcloud builds submit` 會 403 `storage.objects.get`：步驟 5c 先授予 `roles/cloudbuild.builds.builder`
- Cloud Run 保留了 `/healthz`（回 Google 自己的 404，不會到後端）：健康檢查改用 `/health`。目前線上版本（`986a231`）還沒有 `/health`，這個修正合併進 `main` 並重新部署之後才能用；在那之前 uptime check 維持 `/api/config`

## 下一次要做的（A 在 Cloud Shell 執行）

`main` 之後又合併了：第二批 7 張流程卡（共 18 張）、引用來源去重、編輯器保留步驟備註、助理說明新增條目、管理介面與助理面板的大字體修正、新的 App 圖示。照順序：

```bash
cd ~/Culture_Bridge && git checkout main && git pull
bash scripts/gcp-setup.sh 5          # 「第一次接 Alembic 嗎？」回答 N；部署確認輸入 yes
AUTO=1 bash scripts/gcp-setup.sh 7   # 更新原本 11 張草稿（引用去重）並新增 7 張
curl -s https://culture-bridge-z7gcp33vjq-de.a.run.app/health   # 應該看到 {"status":"ok"}
```

- 步驟 7 只會更新**沒有人動過**的草稿；D 已經編輯過的卡會顯示 `skipped`，不會被覆蓋
- `/health` 回 `{"status":"ok"}` 之後，可以把 uptime check 從 `/api/config` 改成 `/health`：主控台 → Monitoring → Uptime checks → `culture-bridge-uptime` → 編輯路徑

所有指令在 Google Cloud Shell（https://shell.cloud.google.com ，帳號 candy950712@gmail.com）的 `~/Culture_Bridge` 執行。腳本以 `main` 為準。

## 規則

- 一次貼一行，等它跑完回到 `$` 再貼下一行
- **不要把密碼、金鑰、`gcloud secrets versions access` 的輸出貼到任何對話或截圖**
- 出現 `確定請輸入 yes` 時：步驟 5 的部署可以輸入 `yes`；步驟 9（刪除）要先問過 A 本人
- 出現紅字錯誤就停下來，把錯誤訊息（不含密碼）回報

## 1. 更新腳本

```bash
cd ~/Culture_Bridge && git checkout main && git pull
```

第 2–5 節已在 2026-10-14 完成，留著當重做時的參考。

## 2. Gemini 金鑰與 Firebase（步驟 3、4）✅

```bash
AUTO=1 bash scripts/gcp-setup.sh 3 4
```

- 會看到「已存入 Secret Manager：gemini-api-key」「已取得 Firebase 網頁設定」
- 最後停在「完成後按 Enter」：先到
  https://console.firebase.google.com/project/culture-bridge-511321/authentication/providers
  → （第一次）開始使用 → Google → 啟用 → 專案支援電子郵件選 candy950712@gmail.com → 儲存
  確認 Google 顯示「已啟用」後，回 Cloud Shell 按 Enter

## 3. 部署（步驟 5，建置約 5–10 分鐘）✅

```bash
AUTO=1 bash scripts/gcp-setup.sh 5
```

- 問「這個資料庫是用 database/schema_postgres.sql 手動建的、而且第一次接 Alembic 嗎？(y/N)」→ 輸入 `y`
- 出現部署確認 → 輸入 `yes`
- 最後會印出「網址：https://…run.app」、「檢查：」後面有回應（不是「尚未回應」）、設定裡 `"environment":"production"` 且 firebase 有值

## 4. 監控（步驟 6）✅

```bash
AUTO=1 bash scripts/gcp-setup.sh 6
```

然後到主控台 Monitoring → Alerting，為 uptime check `culture-bridge-uptime` 建立寄到 candy950712@gmail.com 的通知。

## 5. 費用警報（步驟 1）✅

```bash
bash scripts/gcp-setup.sh 1
```

- 「每月預算」輸入例如 `1000TWD`（幣別要和帳單帳戶相同；不確定先問 A）

## 5.5 匯入官方流程卡草稿（D-8，部署後；新增卡片後再跑一次）

```bash
AUTO=1 bash scripts/gcp-setup.sh 7
```

只建立未發布草稿；審查與發布方式見 [D-8 流程卡](../content/d8-official-procedures.md)。

## 6. 第一位管理者

1. 用 Google 登入步驟 5 印出的網址 →「我的」→「帳號」複製帳號編號
2. 主控台 → SQL → `culturebridge-db` → Cloud SQL Studio（資料庫 `culturebridge`、使用者 `postgres`，密碼由 A 用 `gcloud secrets versions access latest --secret=database-url` 自己查）
3. 執行 `UPDATE users SET role='admin' WHERE id='<帳號編號>';`

## 7. 刪除舊試用執行個體（步驟 9，期限 2026-11-10，先問 A）

刪之前確認舊執行個體的 `postgres` 資料庫沒有組員誤放的資料表：

```bash
gcloud sql export sql free-trial-first-project gs://culture-bridge-511321-sql-migration/postgres-db.sql.gz --database=postgres --quiet
gcloud storage cat gs://culture-bridge-511321-sql-migration/postgres-db.sql.gz | gunzip | grep -c '^CREATE TABLE'
```

結果是 `0` 才執行 `bash scripts/gcp-setup.sh 9`（要輸入 `yes`，無法復原）。
