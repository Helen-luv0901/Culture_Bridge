# 交接：Google Cloud 剩下的步驟（給操作瀏覽器的 Claude 或組員）

狀態（2026-10-13）：
- 專案 ID：`culture-bridge-511321`，區域 `asia-east1`
- ✅ 步驟 0 專案與 API
- ✅ 步驟 2 資料庫搬遷：新執行個體 `culturebridge-db`（PostgreSQL 18、db-f1-micro），資料庫 `culturebridge`，帳號 `postgres`；連線字串在 Secret Manager `database-url`；筆數比對全部一致（`bash scripts/compare-migration.sh`）
- ⬜ 3 Gemini 金鑰 → 4 Firebase 登入 → 5 部署 → 6 監控 → 1 費用警報 → 9 刪除舊試用執行個體

所有指令在 Google Cloud Shell（https://shell.cloud.google.com ，帳號 candy950712@gmail.com）的 `~/Culture_Bridge` 執行。腳本在分支 `claude/awesome-mayer-6q7cq2`。

## 規則

- 一次貼一行，等它跑完回到 `$` 再貼下一行
- **不要把密碼、金鑰、`gcloud secrets versions access` 的輸出貼到任何對話或截圖**
- 出現 `確定請輸入 yes` 時：步驟 5 的部署可以輸入 `yes`；步驟 9（刪除）要先問過 A 本人
- 出現紅字錯誤就停下來，把錯誤訊息（不含密碼）回報

## 1. 更新腳本

```bash
cd ~/Culture_Bridge && git fetch origin claude/awesome-mayer-6q7cq2 && git checkout -B claude/awesome-mayer-6q7cq2 origin/claude/awesome-mayer-6q7cq2
```

## 2. Gemini 金鑰與 Firebase（步驟 3、4）

```bash
AUTO=1 bash scripts/gcp-setup.sh 3 4
```

- 會看到「已存入 Secret Manager：gemini-api-key」「已取得 Firebase 網頁設定」
- 最後停在「完成後按 Enter」：先到
  https://console.firebase.google.com/project/culture-bridge-511321/authentication/providers
  → （第一次）開始使用 → Google → 啟用 → 專案支援電子郵件選 candy950712@gmail.com → 儲存
  確認 Google 顯示「已啟用」後，回 Cloud Shell 按 Enter

## 3. 部署（步驟 5，建置約 5–10 分鐘）

```bash
AUTO=1 bash scripts/gcp-setup.sh 5
```

- 問「這個資料庫是用 database/schema_postgres.sql 手動建的、而且第一次接 Alembic 嗎？(y/N)」→ 輸入 `y`
- 出現部署確認 → 輸入 `yes`
- 最後會印出「網址：https://…run.app」、「檢查：」後面有回應（不是「尚未回應」）、設定裡 `"environment":"production"` 且 firebase 有值

## 4. 監控（步驟 6）

```bash
AUTO=1 bash scripts/gcp-setup.sh 6
```

然後到主控台 Monitoring → Alerting，為 uptime check `culture-bridge-healthz` 建立寄到 candy950712@gmail.com 的通知。

## 5. 費用警報（步驟 1）

```bash
bash scripts/gcp-setup.sh 1
```

- 「每月預算」輸入例如 `1000TWD`（幣別要和帳單帳戶相同；不確定先問 A）

## 5.5 匯入第一批官方流程卡草稿（D-8，部署後）

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
