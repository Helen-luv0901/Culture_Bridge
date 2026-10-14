# C-2／C-18：Android 版建置、Google 登入與簽署

網頁版已上線；這份是讓 Android 版連上同一個後端並能用 Google 登入的步驟。需要一台裝好 Android Studio（含 Android SDK）的電腦。

> ⚠️ 這份設定還**沒有實際編譯過**：開發環境沒有 Android SDK。第一次照做時請把遇到的錯誤回報，修正後更新本文件。

## 已經在程式裡做好的

- `android/app/src/main/AndroidManifest.xml` 加上 `INTERNET` 權限（Flutter 範本只加在 debug/profile，正式版原本會連不到 API）
- `android/app/build.gradle.kts`：有 `android/key.properties` 時用上傳金鑰簽署正式版，沒有時退回 debug 金鑰
- 登入：非網頁平台用 `signInWithProvider(GoogleAuthProvider())`（`lib/data/auth_service.dart`）
- 設定：App 啟動時先讀 `--dart-define` 的 Firebase 設定，再讀後端 `/api/config`
- 圖示（C-20 暫定版）：`flutter_app/tool/make_icons.py` 畫出橋與日出圖示，產生網頁、Android（含 Android 8+ 的自適應圖示）、iOS 各尺寸，以及 Play 商店用的 `docs/store/play-icon-512.png`。要改設計就改這支程式後重跑 `python3 tool/make_icons.py`（需要 Pillow）

## 1. 在 Firebase 加入 Android App

1. [Firebase 主控台](https://console.firebase.google.com/project/culture-bridge-511321/settings/general) → 專案設定 → 新增應用程式 → Android
2. 套件名稱：`com.culturebridge.culture_bridge`
   **【C-3 待決定】第一次上傳 Google Play 後就不能改**，正式上架前先決定是否沿用
3. 加入 **SHA-1 與 SHA-256** 憑證指紋（Google 登入需要）：

   ```sh
   cd flutter_app/android
   ./gradlew signingReport        # 列出 debug 與（設定 key.properties 後）upload 金鑰的指紋
   ```

   上架後還要加上 Google Play「應用程式簽署金鑰」的指紋（Play Console → 設定 → 應用程式完整性）
4. 記下 Android App 的 **App ID**（格式 `1:689086323045:android:…`）。`google-services.json` 不需要放進 repo

## 2. 建立上傳金鑰（C-18，只做一次，不進 repo）

```sh
keytool -genkey -v -keystore ~/culture-bridge-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

建立 `flutter_app/android/key.properties`（已在 `.gitignore`）：

```properties
storeFile=/絕對路徑/culture-bridge-upload.jks
storePassword=<密碼>
keyAlias=upload
keyPassword=<密碼>
```

金鑰檔和密碼要備份到團隊的安全位置（例如密碼管理器）；遺失的話只能向 Google 申請重設上傳金鑰。

## 3. 建置

Firebase 網頁設定裡的 apiKey、projectId、messagingSenderId 可以共用；**App ID 要用 Android 的**。

```sh
cd flutter_app
DEFINES="--dart-define=API_BASE_URL=https://culture-bridge-z7gcp33vjq-de.a.run.app \
  --dart-define=FIREBASE_API_KEY=<apiKey> \
  --dart-define=FIREBASE_APP_ID=<Android App ID> \
  --dart-define=FIREBASE_PROJECT_ID=culture-bridge-511321 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=689086323045"

flutter run $DEFINES                      # 接實機測試
flutter build appbundle --release $DEFINES   # 上傳 Play 用的 .aab
```

## 4. 實機測試（C-19）

照 [手動測試清單](../manual-test-checklist.md)，至少 3 種機型（建議含一台小螢幕、一台 Android 10）。特別確認：

- Google 登入成功、重開 App 仍保持登入
- 沒有網路時顯示「連不上伺服器」並可重試
- 系統字體放大後畫面沒有被切掉（自動測試已涵蓋 200%，實機再確認一次）

## 待決定

- **最低 Android 版本**：規格原本寫 Android 10（API 29）；目前沿用 Flutter 預設。決定後在 `build.gradle.kts` 把 `minSdk` 改成數字
- **套件名稱**（C-3）：見上方
