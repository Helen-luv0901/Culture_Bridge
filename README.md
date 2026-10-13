# App

## Docs
- [Product Map](docs/product-map.md)
- [Experience-Led MVP](docs/experience-led-mvp.md)
- [Database Schema 草案與範例查詢](docs/database-schema.md)
- [SQL Schema（原 SQLite 草案）](database/schema.sql)
- [PostgreSQL Schema（雲端資料庫現行版本）](database/schema_postgres.sql)
- [工作分配表](docs/work-assignment.md)
- [技術架構](docs/tech-architecture.md)
- [Backend（FastAPI＋AI 助理）](backend/README.md)
- [開發環境安裝](docs/dev-setup.md)
- [A-3 Cloud SQL 搬遷步驟](docs/runbooks/a3-cloud-sql-migration.md)
- [A-5 Gemini 金鑰申請步驟](docs/runbooks/a5-gemini-api-key.md)
- [A-7 部署到 Cloud Run](docs/runbooks/a7-deploy-cloud-run.md)
- [手動測試清單](docs/manual-test-checklist.md)
- [PMP 試用任務腳本](docs/pmp-pilot-script.md)
- 草稿（上架前需審閱）：[隱私權政策](docs/drafts/privacy-policy.md)、[服務條款與社群規範](docs/drafts/terms-and-community-guidelines.md)、[商店頁文案](docs/drafts/store-listing.md)

## Database
- 雲端資料庫：Google Cloud SQL（PostgreSQL），資料表以 `database/schema_postgres.sql` 為準
- `database/schema.sql` 是原本的 SQLite 草案，保留作參考
- 連線資訊與帳號請向負責基礎設施的組員索取，不放在 repo

## Prototype
- [Culture Bridge App Mockup](prototype/index.html)

## Flutter frontend

- Current app: `flutter_app/`
- Run: `cd flutter_app`, `flutter pub get`, `flutter run -d chrome --web-port 5174`
- [Current design](design.md)
- [Flutter setup and architecture](flutter_app/README.md)
- [Migration and verification](docs/flutter-migration.md)

## React reference frontend
- React app source: `frontend/`
- Install dependencies in `frontend/`, then run `npm run dev`
- Responsive web app: desktop sidebar, tablet layout, and mobile bottom navigation use the same screens.
- [Responsive UI and verification](docs/responsive-ui.md)
