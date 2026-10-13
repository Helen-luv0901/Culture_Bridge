# 開發環境安裝（B-20）

在自己電腦上把後端、資料庫和網頁版跑起來。

## 需要的工具

| 工具 | 版本 | 用途 |
|---|---|---|
| Python | 3.12 | 後端 |
| [uv](https://docs.astral.sh/uv/) | 0.11 以上 | Python 套件 |
| Docker | 任一近期版本 | 本機 PostgreSQL（含 pgvector） |
| Flutter | 3.47.7 stable（Dart 3.13） | App 與網頁版 |

## 1. 資料庫

```sh
docker run -d --name cb-postgres -p 5432:5432 \
  -e POSTGRES_HOST_AUTH_METHOD=trust pgvector/pgvector:pg16
docker exec cb-postgres createdb -U postgres culturebridge
```

## 2. 後端

```sh
cd backend
uv sync
cp .env.example .env          # 開發不需要填金鑰；沒有 GEMINI_API_KEY 時 AI 功能回「暫時無法使用」
set -a; . ./.env; set +a
uv run alembic upgrade head
uv run python -m app.seed     # 匯入示範流程與經驗
uv run uvicorn app.main:app --reload
```

- API 文件：<http://localhost:8000/api/docs>
- 開發環境登入：`Authorization: Bearer dev:<名字>`，要審查者權限用 `dev:<名字>:reviewer`、管理者 `dev:<名字>:admin`
- 測試：`uv run pytest`（會自己建立 `culturebridge_test` 資料庫）；`uv run ruff check . && uv run ruff format --check .`

## 3. 網頁版

開發時（熱重載，連本機後端）：

```sh
cd flutter_app
flutter pub get
flutter run -d chrome --web-port 5174 --dart-define=API_BASE_URL=http://localhost:8000
```

沒有設定 Firebase 時，登入頁會顯示「開發模式」，輸入名字即可登入（只有開發環境的後端接受）。

或跟正式環境一樣由後端提供網頁版：

```sh
cd flutter_app && flutter build web --no-web-resources-cdn
cd ../backend && WEB_DIR=../flutter_app/build/web uv run uvicorn app.main:app
# 打開 http://localhost:8000
```

測試：`flutter analyze`、`flutter test`、`dart format lib test`

## 4. 用 Firebase 登入測試（選用）

在後端 `.env` 加上 `FIREBASE_PROJECT_ID`、`FIREBASE_WEB_API_KEY`、`FIREBASE_WEB_APP_ID`、`FIREBASE_AUTH_DOMAIN`、`FIREBASE_MESSAGING_SENDER_ID`，網頁版啟動時會從 `/api/config` 讀到並改用 Google 登入。Firebase 主控台的 Authorized domains 要有 `localhost`。

## 5. 常見問題

| 狀況 | 處理 |
|---|---|
| `connection refused` 5432 | 資料庫容器沒開：`docker start cb-postgres` |
| `type "vector" does not exist` | 用的不是 pgvector 映像檔，換成 `pgvector/pgvector:pg16` |
| 網頁版顯示「連不上伺服器」 | 後端沒開，或 `API_BASE_URL` 寫錯 |
| 修改 `ShareDraft` 等 Freezed model 後編譯失敗 | `dart run build_runner build --delete-conflicting-outputs` |
