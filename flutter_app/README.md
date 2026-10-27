# Culture Bridge — Flutter

同一套 Flutter 原生 UI 支援響應式 Web、Android 與 iOS。設計見 [design.md](../docs/product/design.md)。

## 啟動

在本目錄執行：

```sh
flutter pub get
flutter run -d chrome --web-port 5174
flutter devices
flutter run -d <device-id>
```

iOS 需要 macOS 與 Xcode。Android／iOS 平台已建立，尚未驗證原生編譯。

## 驗證與部署

```sh
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
flutter build apk --debug
# 修改 Freezed model 後
 dart run build_runner build
```

Web 產物位於 build/web。伺服器必須將不存在的路徑回傳 index.html，以支援直接開啟 /explore 等 URL。子目錄部署需指定 --base-href。

## 連接後端

App 透過 `/api` 讀寫資料（後端見 [backend/README.md](../backend/README.md)）。

```sh
# 開發：連本機後端（開發模式登入：輸入名字即可）
flutter run -d chrome --web-port 5174 --dart-define=API_BASE_URL=http://localhost:8000
```

- 網頁版正式環境由後端同源提供，不需要 `API_BASE_URL`
- 登入：Firebase Authentication（Google）。網頁版啟動時從 `/api/config` 讀 Firebase 設定；Android 用 `--dart-define=FIREBASE_API_KEY=… FIREBASE_APP_ID=… FIREBASE_PROJECT_ID=… FIREBASE_MESSAGING_SENDER_ID=…`
- 沒有 Firebase 設定且後端是開發環境時，使用開發登入（`dev:<名字>`）

## 架構

- lib/domain：API 資料模型（`api_models.dart`、`admin_models.dart`）、分享草稿（Freezed）、API id 與介面字串對應。
- lib/data：`ApiClient`、`CultureRepository`（API 版）、`AdminRepository`、登入（`auth_service.dart`）、介面字串、本機偏好。
- lib/ui/view_models：`BridgeViewModel`：語系、登入、載入中／錯誤狀態、分享流程、助理對話。
- lib/ui/core：紙張視覺、共用 Widget、響應式導覽、載入與錯誤畫面。
- lib/ui/features：首頁與看板、流程與辦理、分享與我的、登入、浮動 AI 助理、審查後台（`/admin`）。
- test：以記憶體中的假 API（`fake_repository.dart`）測試畫面與流程。

語言與分享草稿保存在本機；其他資料都在後端。
