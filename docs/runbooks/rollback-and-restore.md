# 退回上一版與還原資料庫

出事時照這份做。指令在 [Cloud Shell](https://shell.cloud.google.com) 執行；先設定：

```sh
PROJECT=culture-bridge-511321
REGION=asia-east1
SERVICE=culture-bridge
INSTANCE=culturebridge-db
gcloud config set project $PROJECT
```

## 1. 部署時會自動擋下壞掉的版本

`scripts/deploy.sh`（合併到 `main` 後 GitHub Actions 也是跑它）的部署步驟：

1. 先跑 migration（Alembic）
2. 新版本部署成 **不給流量** 的修訂版本，掛上 `candidate` 標籤
3. 對 `candidate` 網址打 `/health`：程式有啟動**而且連得到資料庫**才回 200
4. 通過才把流量切過去；沒通過就停在這裡，流量留在舊版本，使用者不受影響
5. 切換後再檢查一次正式網址，失敗就自動把流量退回舊版本

部署失敗時，GitHub Actions → Deploy 的記錄會寫出新、舊修訂版本名稱。原因到 Cloud Run → `culture-bridge` → 修訂版本 → 該版本 → 記錄查。

## 2. 手動退回上一版程式

上線後才發現問題（健康檢查不會發現的錯，例如某個按鈕壞了）：

```sh
# 列出修訂版本，最新的在最上面
gcloud run revisions list --service=$SERVICE --region=$REGION --limit=5
# 全部流量給指定的舊版本（幾秒內生效）
gcloud run services update-traffic $SERVICE --region=$REGION --to-revisions=<舊修訂版本名稱>=100
```

修好、重新部署時，`deploy.sh` 會自動把流量改回「最新版本」。

> 退回的版本比資料表舊時（中間有 migration），先看那個 migration 檔開頭的說明。例如 `0012_block_personas` 之後，同一位使用者對同一位作者同時有「匿名」和「具名」兩筆封鎖時，0012 以前的版本讀那位作者的留言會出錯；只退回幾小時通常沒關係，要長時間停在舊版就先執行 `downgrade`（第 3 節）。

> 部署暫停：GitHub → Settings → Secrets and variables → Actions → Variables，把 `AUTO_DEPLOY` 改成 `false`。

## 3. Migration 的規則

migration 在新版本上線**之前**執行，所以舊版本必須能在新資料表上繼續跑（退回上一版時也是）：

- 只**新增**欄位、資料表、索引；新欄位要可以是空的或有預設值
- 不要在同一次改名或刪除舊程式還在用的欄位。要刪的話，先上線不再使用它的版本，下一次再刪

真的要把資料表退回上一版（很少需要，會丟掉新欄位的資料）：

```sh
gcloud run jobs execute culture-bridge-migrate --region=$REGION --args=downgrade,-1 --wait
```

## 4. 還原資料庫

先確認已開啟每日備份和時間點還原：`bash scripts/gcp-setup.sh 10`（只要做一次）。

### 4a. 時間點還原（誤刪、資料被改壞）

可以回到過去 7 天內的任一秒。**先還原到一個新的執行個體**，確認後再決定怎麼用，原本的資料庫不會被動到：

```sh
# 時間用 UTC（台灣時間減 8 小時），選出事前一刻
gcloud sql instances clone $INSTANCE ${INSTANCE}-restore --point-in-time='2026-10-27T03:00:00Z'
```

接著用 Cloud SQL Studio 打開 `${INSTANCE}-restore` 確認資料，然後二選一：

- **只救回部分資料**（最常見）：從還原的執行個體把需要的資料列查出來、在原本的資料庫補回去
- **整個換過去**：把 Secret Manager 的 `database-url` 改成指向新執行個體，並更新服務的 Cloud SQL 連線：

  ```sh
  gcloud run services update $SERVICE --region=$REGION \
    --set-cloudsql-instances=$PROJECT:$REGION:${INSTANCE}-restore
  ```

用完的還原執行個體要刪掉，不然會一直計費：`gcloud sql instances delete ${INSTANCE}-restore`

### 4b. 從每日備份還原（整個執行個體壞掉）

```sh
gcloud sql backups list --instance=$INSTANCE
# 注意：會覆蓋目標執行個體上的所有資料
gcloud sql backups restore <BACKUP_ID> --restore-instance=$INSTANCE
```

## 5. 演練

每學期做一次，確認真的救得回來：照 4a 複製一份到 `${INSTANCE}-restore`，用 Cloud SQL Studio 查 `SELECT count(*) FROM experiences;`，和正式資料庫比對，然後刪掉複本。

## 6. 監控

- 監控的 uptime check（`gcp-setup.sh` 步驟 6）每 5 分鐘打 `/health`，資料庫連不上也會回 503 並觸發通知。
  早期建立的 `culture-bridge-uptime` 打的是 `/api/config`（不碰資料庫），改成 `/health`：

  ```sh
  gcloud monitoring uptime update culture-bridge-uptime --path=/health --project=$PROJECT
  ```
- App 在使用者裝置上發生的錯誤會寫進 Cloud Logging：記錄檢視器搜尋 `App error on`
