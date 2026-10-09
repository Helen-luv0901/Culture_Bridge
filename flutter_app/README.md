# Culture Bridge — Flutter

同一套 Flutter 原生 UI 支援響應式 Web、Android 與 iOS。設計見 [design.md](../design.md)。

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

## 架構

- lib/domain：Freezed 不可變 model。
- lib/data：內容與本機偏好 repository。
- lib/ui/view_models：語系、草稿、篩選與操作狀態。
- lib/ui/core：紙張視覺、共用 Widget、響應式導覽。
- lib/ui/features：九個流程頁。
- assets：原版資料、植物、SVG、附授權本機字型。

語言與分享草稿保存在本機。操作回饋與步驟只保留在本次執行；數字與故事為示例。尚未接 SQL、登入、AI 摘要或發布 API；預覽確認不會發布到網路。
