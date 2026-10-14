# Culture Bridge 隱私權政策（草稿）

> **草稿，尚未生效。** 由工作分配 D-11 準備的初稿，依目前程式實際蒐集與處理的資料撰寫。上架前請團隊確認：聯絡方式、營運主體、年齡限制、Gemini 方案（是否用於改善模型），並建議請熟悉《個人資料保護法》的人審閱。標【待確認】處必須補上。

最後更新：【待確認】

## 1. 我們是誰

Culture Bridge 是協助在台國際學生辦理生活流程、分享生活經驗的服務，由【待確認：團隊／學校／單位名稱】營運。聯絡方式：【待確認】。

## 2. 我們蒐集哪些資料、為什麼

| 資料 | 來源 | 用途 |
|---|---|---|
| 登入識別碼（Firebase 帳號的內部 ID）；Google 帳號的 Email 與名稱 | 你用 Google 登入時 | 辨識你的帳號。登入由 Google 的 Firebase Authentication 處理，Email 與名稱存在 Firebase，用於登入；我們的資料庫只存內部 ID，**不存**你的密碼、Email 或姓名，App 也不顯示。刪除帳號時一併刪除 Firebase 登入資料 |
| 語言偏好 | 你在 App 中設定 | 顯示介面語言 |
| 你分享的經驗（原話、主題、身分類型）與 AI 整理、翻譯 | 你在「分享」輸入 | 匿名公開給其他使用者；用於搜尋與 AI 助理引用 |
| 反應（有幫助、我也遇過）、「我的經驗不同」 | 你的操作 | 顯示統計、讓你看到自己的影響 |
| 收藏的經驗 | 你的操作 | 讓你之後再看；只有你看得到，不計入任何公開數字 |
| 辦理進度、卡關與差異回報（含你填寫的說明） | 你的操作 | 記錄你的進度；經審查後用來改善流程內容，回報中的原話經審查採納後可能被助理以「學生回報」引用 |
| 檢舉、封鎖名單 | 你的操作 | 維護社群安全；封鎖只影響你看到的內容 |
| AI 助理對話 | 你在助理輸入 | 產生回答。對話只暫存在伺服器記憶體中（約 2 小時、最近幾輪），**不寫入資料庫** |
| 伺服器紀錄（IP 位址、請求時間、錯誤） | 自動產生 | 防止濫用（頻率限制）、排除故障 |
| 使用日期、開過哪些經驗（只記日期，不記時間與停留長度） | 你登入後使用 App、打開經驗詳情時 | 計算整體成效（例如回訪率、經驗閱讀率），只以統計數字呈現給管理者；作者本人看自己的經驗不記錄 |

我們不蒐集精確位置、聯絡人、照片或裝置上的其他資料，也不投放廣告。

## 3. 公開與匿名

你分享的經驗會公開給所有使用者，但**不會顯示**你的姓名、學校、帳號或任何可以把多則經驗連到同一人的資訊。請不要在原話中寫入可識別你或他人的資料（姓名、電話、學號等）；AI 整理時也會被要求省略這類資訊，但你的原話會照你寫的內容公開。

## 4. AI 處理（Google Gemini）

以下內容會傳送給 Google 的 Gemini API 處理：

- 你要求 AI 整理的經驗原話（產生摘要）、發布後的經驗（翻譯成另一種語言）
- 你對 AI 助理的提問與助理查詢到的資料
- 公開經驗與審查後回報的文字（轉換成向量以供語意搜尋）

【待確認：使用的 Gemini 方案。若為付費方案，Google 依其服務條款不會用這些內容訓練模型；若為免費方案，Google 可能用於改善其產品，須在此明確告知並取得同意。】

AI 產生的摘要在你確認前不會公開；翻譯會標示「AI 翻譯」，並保留你的原文。

## 5. 資料存放與保存

- 資料存放於 Google Cloud（台灣 asia-east1 區域）的資料庫，傳輸一律使用 HTTPS
- 帳號存在期間保存你的資料；刪除帳號後立即刪除（見第 6 點）
- 伺服器紀錄保留【待確認：天數，Cloud Logging 預設 30 天】
- 資料庫自動備份保留【待確認：天數】，備份會在保留期滿後覆寫

## 6. 你的權利

- **查閱與更正**：在「我的」查看你分享的經驗；可在發布前修改，或刪除已發布的經驗
- **刪除帳號**：在「我的」→「帳號」→「刪除帳號」，會刪除帳號與上述所有資料（經驗、反應、收藏、辦理紀錄、回報、檢舉、封鎖、助理對話）。說明頁：`/account-deletion`
- 若你是審查者，你對官方流程的審查紀錄會保留但改為不具名，以維持流程驗證可追溯
- 無法登入時可來信要求刪除：【待確認：聯絡方式】，我們會在 30 天內處理

依《個人資料保護法》第 3 條，你可以請求查詢、閱覽、製給複製本、補充或更正、停止蒐集處理利用、刪除你的個人資料。

## 7. 兒少

本服務以大專院校國際學生為對象，【待確認：最低年齡，例如 16 歲或 18 歲】以下請勿使用。

## 8. 政策變更

重大變更會在 App 內公告，並更新最後更新日期。

---

# Culture Bridge Privacy Policy (draft)

> **Draft, not in effect.** Prepared for D-11 from what the code actually collects. Fill in every [TBC] and have the team (ideally someone familiar with Taiwan's Personal Data Protection Act) review it before publishing.

Last updated: [TBC]

**Who we are.** Culture Bridge helps international students in Taiwan with everyday procedures and shared experiences, operated by [TBC]. Contact: [TBC].

**What we collect and why.** Your Firebase sign-in ID (Google sign-in is handled by Firebase Authentication, which keeps your Google email and name for signing in; our database stores only the internal ID, never your password, email or name, and deleting your account also removes the Firebase login); your language preference; experiences you share (published anonymously) with their AI summary and translation; your reactions and "different experience" answers; experiences you save to read later (visible only to you); your procedure progress and reports (reviewed reports may be quoted by the assistant as student reports); your content reports and blocked authors; assistant conversations (kept only in server memory for about two hours, never written to the database); server logs (IP address, time, errors) for abuse prevention and troubleshooting; and, once you are signed in, the dates you used the app and which experiences you opened (dates only), counted only as totals for the team (for example return and reading rates). No precise location, contacts, photos or advertising.

**Anonymity.** Shared experiences are public but never show your name, school, account, or anything linking several posts to the same person. Please do not write identifying details in your words.

**AI processing (Google Gemini).** Words you ask the AI to organize, published experiences (for translation), assistant questions and the data it looks up, and public text indexed for semantic search are sent to the Gemini API. [TBC: Gemini plan and whether Google may use the content.] Nothing AI-generated is published until you confirm it, and translations are labeled.

**Storage and retention.** Google Cloud, Taiwan (asia-east1), HTTPS only. Kept while your account exists, deleted when you delete it. Logs: [TBC] days. Backups: [TBC] days.

**Your rights.** View and delete your experiences in "My"; delete your account under My → Account (deletes everything listed above; reviewers' verification records are kept without their identity). Page: `/account-deletion`. If you can't sign in, contact [TBC]; we act within 30 days.

**Children.** For university students; not for anyone under [TBC].

**Changes.** Announced in the app with a new date.
