# Flutter 前端移植

## 流程

1. 先建立 [design.md](../design.md)，固定剪貼簿設計、尺寸與流程。
2. 安裝並閱讀官方 [Flutter agent-plugins](https://github.com/flutter/agent-plugins) 的架構、響應式、路由、Widget 測試四個技能。
3. 建立 flutter_app，保留 frontend 作為參考。
4. 搬移雙語資料、植物、SVG 與字型，以原生 Widget 重建紙邊、膠帶與介面。
5. 採 UI／ViewModel／Repository／Model 分層，以 go_router 建立九個流程頁；本機偏好儲存語言與草稿。
6. 驗證尺寸與操作，再編譯 Web。

768px 以下為底部導覽，以上為側欄；1100px 以上首頁可呈現雙欄。閱讀內容最大 760px；個人頁影響數字加大至 48px。支援鍵盤焦點與文字放大。

## 驗證

flutter analyze 無問題，48 個測試通過。涵蓋 320、375、768、1024、1440px 八個可直接進入的頁面，以及表單驗證、確認後修改保留草稿、語系切換、手機導覽、步驟操作與 200% 文字放大。確認頁透過有效草稿進入測試。Flutter Web 編譯成功。

Android／iOS 已建立平台工程，尚未驗證原生編譯；iOS 必須在 macOS 編譯。SQL 尚未接線；發布、來源驗證與 AI 摘要維持預覽流程。

啟動與部署設定見 [Flutter README](../flutter_app/README.md)。

瀏覽器已檢查 1440px 桌面首頁與 375px 手機個人頁，未出現 JavaScript 頁面錯誤。截圖：[桌面](previews/flutter-desktop.png)、[手機](previews/flutter-mobile.png)。

