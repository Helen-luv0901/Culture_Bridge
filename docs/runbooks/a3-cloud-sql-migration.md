# A-3：Cloud SQL 從免費試用執行個體搬到最小規格執行個體

期限：**2026-11-10 前**（試用執行個體約在此時到期）。建議 **11/3 前**完成，留一週緩衝。

做法：把試用執行個體的資料匯出到 Cloud Storage，再匯入新建的 Enterprise 最小規格執行個體。
以下指令在 [Cloud Shell](https://shell.cloud.google.com) 執行（已登入、已裝 gcloud）。

> 主控台與指令選項可能隨 Google 更新而改變，執行前請對照主控台畫面。標【確認】的地方請先在主控台看過再做。

## 0. 先確認

1. 【確認】Cloud SQL 主控台 → 試用執行個體頁面上，是否有「升級」或「編輯版本」的選項。如果可以直接改成
   Enterprise 版、最小規格並保留資料，就不需要搬遷；先評估費用再決定。以下是不能就地升級時的做法。
2. 通知組員搬遷時段：匯出到切換完成之間不要寫入資料庫。

## 1. 設定變數

```sh
PROJECT=culture-bridge
REGION=asia-east1
OLD=<試用執行個體名稱>          # Cloud SQL 主控台看得到
NEW=culturebridge-db
DB=culturebridge
BUCKET=gs://${PROJECT}-sql-migration
gcloud config set project $PROJECT
gcloud sql instances describe $OLD --format="value(databaseVersion,settings.edition,settings.tier)"
```

記下 `databaseVersion`（例如 `POSTGRES_16`），新執行個體用同一個版本。

## 2. 匯出

```sh
gcloud storage buckets create $BUCKET --location=$REGION --uniform-bucket-level-access
OLD_SA=$(gcloud sql instances describe $OLD --format="value(serviceAccountEmailAddress)")
gcloud storage buckets add-iam-policy-binding $BUCKET \
  --member=serviceAccount:$OLD_SA --role=roles/storage.objectAdmin
gcloud sql export sql $OLD $BUCKET/$DB.sql.gz --database=$DB
```

## 3. 建新執行個體

```sh
gcloud sql instances create $NEW \
  --database-version=POSTGRES_16 \
  --edition=ENTERPRISE \
  --tier=db-f1-micro \
  --region=$REGION \
  --availability-type=zonal \
  --storage-size=10 \
  --backup-start-time=18:00        # UTC 18:00 = 台北 02:00
gcloud sql databases create $DB --instance=$NEW
```

- `--database-version` 換成第 1 步看到的版本
- `db-f1-micro` 是共用核心的最小規格，適合 MVP；【確認】建立前主控台顯示的每月估價

## 4. 帳號（匯入前）

SQL 匯出不包含帳號密碼。舊執行個體的資料表屬於 `postgres`，新執行個體也沿用 `postgres` 當擁有者——匯入、migration、後端都用它，權限才一致（另外建的帳號沒有這些資料表的權限，ALTER TABLE 也會失敗）：

```sh
gcloud sql users list --instance=$OLD          # 確認只有 postgres（或建表的帳號）
gcloud sql users set-password postgres --instance=$NEW --password='<新密碼>'
```

新密碼存進 Secret Manager 的 `database-url`（A-7），需要直接連資料庫的組員再私下給，不要貼在群組或 repo。

## 5. 匯入

```sh
NEW_SA=$(gcloud sql instances describe $NEW --format="value(serviceAccountEmailAddress)")
gcloud storage buckets add-iam-policy-binding $BUCKET \
  --member=serviceAccount:$NEW_SA --role=roles/storage.objectViewer
gcloud sql import sql $NEW $BUCKET/$DB.sql.gz --database=$DB --user=postgres
```

## 6. 連線設定

```sh
# 會取代整份清單，把所有組員的 IP 一起列上
gcloud sql instances patch $NEW --authorized-networks=<IP1>/32,<IP2>/32
gcloud sql instances describe $NEW --format="value(ipAddresses[0].ipAddress)"
```

## 7. 驗證

用 psql 或 pgAdmin 連到新執行個體：

```sql
SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';   -- 和舊的一樣
SELECT tgname FROM pg_trigger WHERE NOT tgisinternal ORDER BY 1;                -- 觸發器都在
SELECT table_name FROM information_schema.views WHERE table_schema = 'public';  -- public_experiences、latest_published_actions
SELECT count(*) FROM topics;                                                    -- 每張有資料的表都和舊的比對
```

再確認：主控台 → 新執行個體 → 備份：自動備份已開啟。

## 8. 切換與收尾

1. 把新的連線位址交給組員；之後放 Secret Manager 的設定也改成新位址
2. 所有人確認新資料庫能用之後，再刪掉試用執行個體
3. 刪掉 `$BUCKET` 裡的匯出檔，裡面有完整資料，不要留著
4. 帳單 → 預算與快訊：確認費用警報有包含 Cloud SQL
