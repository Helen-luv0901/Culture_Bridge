# A-7／A-9：部署到 Cloud Run（網頁版＋後端）

一個 Cloud Run 服務同時提供 `/api` 和 Flutter 網頁版（不存在的路徑會回傳 `index.html`，所以 `/explore`、`/actions/arc` 可以直接開）。映像檔由 repo 根目錄的 `Dockerfile` 建置。

> 指令在 [Cloud Shell](https://shell.cloud.google.com) 執行。主控台選項可能變動，標【確認】的地方請先看過主控台。

> **最快的方式**：在 Cloud Shell 執行 `bash scripts/gcp-setup.sh`，用選單一步一步做完下面的事（每個指令會先顯示、按 Enter 才執行；花錢或刪除前要輸入 `yes`）。以下是它做的事情的詳細說明。

## 0. 先完成

- A-1、A-2：專案 `culture-bridge`、Cloud SQL 執行個體（若已依 [A-3](a3-cloud-sql-migration.md) 搬遷，用新的執行個體）
- A-5：Gemini 金鑰（[步驟](a5-gemini-api-key.md)）

```sh
PROJECT=culture-bridge
REGION=asia-east1
INSTANCE=<Cloud SQL 執行個體名稱>
CONN=$PROJECT:$REGION:$INSTANCE
IMAGE=$REGION-docker.pkg.dev/$PROJECT/culture-bridge/app
gcloud config set project $PROJECT
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com
```

## 1. Firebase 登入（B-6 的設定部分）

1. 到 [Firebase 主控台](https://console.firebase.google.com) →「新增專案」→ 選擇**既有的 Google Cloud 專案 `culture-bridge`**
2. Authentication → Sign-in method → 啟用 **Google**
3. 專案設定 → 一般 →「你的應用程式」→ 新增**網頁應用程式**，記下 `apiKey`、`appId`、`authDomain`、`messagingSenderId`
   （這些是公開識別資訊，不是秘密）
4. Authentication → Settings → **Authorized domains**：部署後把 Cloud Run 網址（和自訂網域）加進去

## 2. 資料庫帳號與秘密

後端用 `postgres` 帳號（資料表的擁有者；A-3 搬遷時設定新密碼），migration 才能修改既有資料表：

```sh
printf '%s' "postgresql+psycopg://postgres:<A-3 設定的密碼>@/culturebridge?host=/cloudsql/$CONN" \
  | gcloud secrets create database-url --data-file=-
# gemini-api-key 已在 A-5 建立
```

建立服務帳戶並給最小權限：

```sh
gcloud iam service-accounts create culture-bridge-run
SA=culture-bridge-run@$PROJECT.iam.gserviceaccount.com
gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA --role=roles/cloudsql.client
for s in database-url gemini-api-key; do
  gcloud secrets add-iam-policy-binding $s --member=serviceAccount:$SA --role=roles/secretmanager.secretAccessor
done
```

## 3. 建置映像檔

```sh
gcloud artifacts repositories create culture-bridge --repository-format=docker --location=$REGION
TAG=$(git rev-parse --short HEAD)
gcloud builds submit --tag $IMAGE:$TAG --machine-type=e2-highcpu-8 .
```

（Flutter 編譯較吃 CPU，`e2-highcpu-8` 大約幾分鐘；預設機型也可以，只是比較慢。）

## 4. 資料表（migration）

用同一個映像檔建立一次性的 Cloud Run Job：

```sh
gcloud run jobs create culture-bridge-migrate --image=$IMAGE:$TAG --region=$REGION \
  --service-account=$SA --set-cloudsql-instances=$CONN \
  --set-secrets=DATABASE_URL=database-url:latest \
  --command=alembic --args=upgrade,head
```

**第一次**：Cloud SQL 是用 `database/schema_postgres.sql` 手動建好的，要先讓 Alembic 知道第一版已存在：

```sh
gcloud run jobs execute culture-bridge-migrate --region=$REGION \
  --args=stamp,0001_initial_schema --wait
gcloud run jobs execute culture-bridge-migrate --region=$REGION --wait   # upgrade head
```

之後每次部署新版本，先 `gcloud run jobs update culture-bridge-migrate --image=$IMAGE:$TAG` 再執行一次 `execute`。
（`0004` 會執行 `CREATE EXTENSION vector`；Cloud SQL 的 `postgres` 帳號屬於 `cloudsqlsuperuser`，可以建立。）

測試站要示範資料時，另建一個執行 `python` 的 job（`gcloud run jobs execute` 只能覆寫參數，不能換指令）：

```sh
gcloud run jobs create culture-bridge-seed --image=$IMAGE:$TAG --region=$REGION \
  --service-account=$SA --set-cloudsql-instances=$CONN \
  --set-secrets=DATABASE_URL=database-url:latest \
  --command=python --args=-m,app.seed,--force
gcloud run jobs execute culture-bridge-seed --region=$REGION --wait
```

第一批官方流程卡草稿（D-8）：`bash scripts/gcp-setup.sh 7`，說明見 [D-8 流程卡](../content/d8-official-procedures.md)。

## 5. 部署服務

```sh
gcloud run deploy culture-bridge --image=$IMAGE:$TAG --region=$REGION \
  --service-account=$SA --add-cloudsql-instances=$CONN --allow-unauthenticated \
  --memory=512Mi --cpu=1 --min-instances=0 --max-instances=2 --concurrency=40 \
  --set-secrets=DATABASE_URL=database-url:latest,GEMINI_API_KEY=gemini-api-key:latest \
  --set-env-vars=APP_ENV=production,FIREBASE_PROJECT_ID=$PROJECT,\
FIREBASE_WEB_API_KEY=<apiKey>,FIREBASE_WEB_APP_ID=<appId>,\
FIREBASE_AUTH_DOMAIN=<authDomain>,FIREBASE_MESSAGING_SENDER_ID=<messagingSenderId>
```

- `max-instances=2`：助理的頻率限制與對話記憶在記憶體裡，執行個體少比較準，也控制費用
- `ASSISTANT_ALLOW_GUESTS` 預設不讓訪客使用助理；團隊決定開放時加 `ASSISTANT_ALLOW_GUESTS=true`
- 部署完把服務網址加到 Firebase **Authorized domains**（第 1 步）

確認：

```sh
URL=$(gcloud run services describe culture-bridge --region=$REGION --format='value(status.url)')
curl $URL/health          # Cloud Run 保留了 /healthz，不會轉給後端
curl $URL/api/config        # firebase 應該有值、environment 是 production
```

## 6. 第一位管理者

1. 用 Google 登入網頁版，到「我的」→「帳號」複製**帳號編號**
2. Cloud SQL Studio（或 psql）執行：`UPDATE users SET role='admin' WHERE id='<帳號編號>';`
3. 之後由管理者在後台把其他組員設為 reviewer：`PUT /api/admin/users/<id>/role`（網頁版之後可加按鈕）

## 7. 網域與 HTTPS（A-4）

擇一：

- **Cloud Run 網域對應**【確認 asia-east1 是否支援】：
  `gcloud beta run domain-mappings create --service=culture-bridge --domain=<你的網域> --region=$REGION`，依指示在網域商加 DNS 紀錄，憑證自動簽發
- **Firebase Hosting 轉發到 Cloud Run**：Hosting 綁網域，`firebase.json` 用 `rewrites: [{"source": "**", "run": {"serviceId": "culture-bridge", "region": "asia-east1"}}]`

網域生效後也要加到 Firebase Authorized domains。

## 8. 監控與費用（A-8）

- **伺服器錯誤**：Cloud Run 的 stdout/stderr 自動進 Cloud Logging；含 stack trace 的錯誤會出現在 **Error Reporting**，可設定 Email 通知
- **服務是否活著**：Monitoring → Uptime checks → 新增 HTTPS 檢查 `<網址>/health`（`/healthz` 被 Cloud Run 保留，不能用），失敗時寄信
- **費用**：帳單 → 預算與快訊，分別為 Cloud Run、Cloud SQL、Gemini 設門檻
- **App 閃退（Android）**：上架前用 Firebase Crashlytics（C-2 之後再接）

## 9. 正式環境（A-7）

正式和測試各建一個服務（例如 `culture-bridge` 與 `culture-bridge-staging`），各自連不同的資料庫與秘密。測試站可加 `--set-env-vars=...` 跑 `app.seed --force`；**正式站不要匯入示範資料**。
