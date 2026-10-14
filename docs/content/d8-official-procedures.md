# D-8 官方流程卡（草稿，待審查）

資料檔：[`backend/app/content/official_procedures.json`](../../backend/app/content/official_procedures.json)（2026-10-14 整理）

> **這些還不是已驗證的內容。** 政府與學校網站無法從開發環境直接連線，內容是用網路搜尋讀取官方頁面後整理的，沒有逐字核對原文。每張卡都附官方來源；匯入後是**未發布草稿**，必須由審查者打開每個來源核對、修正後才發布，並在後台記錄驗證。

## 怎麼匯入與審查

1. 匯入（部署後在 Cloud Shell 執行；只建立草稿，不會公開）：`bash scripts/gcp-setup.sh 7`
   本機：`cd backend && uv run python -m app.official_content`（`--dry-run` 只檢查格式）
2. 審查者到網頁版「管理 → 流程」打開每張草稿，逐一點開來源核對步驟、費用、期限；處理下面「需要確認」的項目
3. 修正後按「發布」，再到「驗證」選來源記錄 verified／needs_review
4. 發布後學生就看得到；助理也會引用這些流程卡

## 流程卡一覽

| 流程卡 | 批次 | 步驟 | 來源 |
|---|---|---|---|
| 外國學生首次申請外僑居留證（ARC）（`arc-first`） | 1 | 6 | 5 |
| 外國學生外僑居留證延期（`arc-extension`） | 1 | 5 | 4 |
| 外僑居留證遺失或污損補發（`arc-replacement`） | 1 | 4 | 3 |
| 外籍生居留健康檢查與新生健檢（`health-check`） | 1 | 5 | 12 |
| 加入全民健康保險（健保）與申辦健保卡（`nhi`） | 1 | 6 | 13 |
| 申請外國留學生工作許可（工讀）（`work-permit`） | 1 | 6 | 12 |
| 申請逢甲大學在學證明書（`enrollment-certificate`） | 1 | 4 | 8 |
| 外籍學生在臺開立銀行／郵局帳戶（`bank-account`） | 1 | 6 | 14 |
| 在MyFCU登錄撥款銀行帳戶（`fcu-bank-binding`） | 1 | 5 | 7 |
| 逢甲大學學生請假（`leave-request`） | 1 | 5 | 5 |
| 補發逢甲學生證（逢甲卡）（`student-id-replacement`） | 1 | 4 | 3 |
| 境外新生報到（國際事務處）（`fcu-newcomer-registration`） | 2 | 6 | 6 |
| MyFCU 新生報到檢核表（`myfcu-checklist`） | 2 | 5 | 6 |
| 停留簽證改辦就學居留簽證（`visitor-to-resident-visa`） | 2 | 5 | 6 |
| 華語生申請居留（外僑居留證）（`mandarin-student-residence`） | 2 | 5 | 4 |
| 外僑居留證異動登記（住址變更等）（`arc-address-change`） | 2 | 4 | 4 |
| 加入健保前的學生醫療保險（醫保／僑保）（`student-medical-insurance`） | 2 | 5 | 5 |
| 畢業後延期居留在臺覓職（`post-graduation-stay`） | 2 | 5 | 7 |

第一批涵蓋工作分配 D-8 指定的 8 項；第二批（2026-10-14 補）是研究時發現的常見流程：停留簽證改辦居留、華語生居留、住址變更登記、畢業後延期居留、境外新生報到、MyFCU 檢核表、健保前的學生醫療保險。

## 需要確認的地方（審查時優先處理）

### 外國學生首次申請外僑居留證（ARC）

- 部分大學網頁寫入境後15日內申請，與移民署送件須知的「入國翌日起30日內」不一致；卡片採移民署的30日。
- 學生線上申辦系統網址只在大學轉載資料看到，未在移民署頁面直接確認，所以卡片沒有寫網址。
- 「外國學生不再受理臨櫃申請」只見於大學轉載，未確認；卡片沒有寫能否臨櫃。
- 逢甲大學（西屯區）學生應由哪個服務站負責無法確定；第一服務站只是示例。
- 逢甲國際處某頁面寫居留證3,000元（美籍4,000元），推測是停留簽證改辦的情況，需要確認。
- 居留健康檢查的項目來自教育部與疾管署資料，不是移民署原文，未寫入步驟。
- 以上依搜尋引擎讀取官方文件整理，沒有逐字核對PDF全文。

來源：

1. [外國學生與僑生線上申請居留或延期居留及異動登記送件須知（1150506版）](https://www.immigration.gov.tw/media/118853/0929%E5%A4%96%E5%9C%8B%E5%AD%B8%E7%94%9F%E8%88%87%E5%83%91%E7%94%9F%E7%B7%9A%E4%B8%8A%E7%94%B3%E8%AB%8B%E5%B1%85%E7%95%99%E6%88%96%E5%BB%B6%E6%9C%9F%E5%B1%85%E7%95%99%E5%8F%8A%E7%95%B0%E5%8B%95%E7%99%BB%E8%A8%98%E9%80%81%E4%BB%B6%E9%A0%88%E7%9F%A5-1150506.pdf)（內政部移民署）
2. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
3. [Guidelines for Online Application for Residence, Extension of Residence and Registration of Changes for Foreign Students and Overseas Compatriot Students](https://www.immigration.gov.tw/5475/5478/141465/141808/417829/cp_news)（內政部移民署）
4. [外國學生與僑生線上申請居留或延期居留及異動登記送件須知（前一版）](https://www.immigration.gov.tw/media/101057/0929%E5%A4%96%E5%9C%8B%E5%AD%B8%E7%94%9F%E8%88%87%E5%83%91%E7%94%9F%E7%B7%9A%E4%B8%8A%E7%94%B3%E8%AB%8B%E5%B1%85%E7%95%99%E6%88%96%E5%BB%B6%E6%9C%9F%E5%B1%85%E7%95%99%E5%8F%8A%E7%95%B0%E5%8B%95%E7%99%BB%E8%A8%98%E9%80%81%E4%BB%B6%E9%A0%88%E7%9F%A5.pdf)（內政部移民署）
5. [移民署申辦地點（服務站）](https://www.immigration.gov.tw/5385/7445/7889/7892/50767/)（內政部移民署）

### 外國學生外僑居留證延期

- 申請時點：移民署送件須知寫「效期屆滿前三個月內」，但多所大學與一份服務站簡報寫「到期前30日內」；卡片採移民署的三個月。
- 延期是否須上傳現持居留證、是否須再附健康檢查，學生版須知摘錄中未確認。
- 每次延期核給的效期長度（一年或依在學期間）未能確認。
- 華語生延期另須最近一學期出缺勤紀錄（見國際生流程總覽研究），本卡未列入，需確認是否加註。
- 以上依搜尋引擎讀取官方文件整理，沒有逐字核對PDF全文。

來源：

1. [外國學生與僑生線上申請居留或延期居留及異動登記送件須知（1150506版）](https://www.immigration.gov.tw/media/118853/0929%E5%A4%96%E5%9C%8B%E5%AD%B8%E7%94%9F%E8%88%87%E5%83%91%E7%94%9F%E7%B7%9A%E4%B8%8A%E7%94%B3%E8%AB%8B%E5%B1%85%E7%95%99%E6%88%96%E5%BB%B6%E6%9C%9F%E5%B1%85%E7%95%99%E5%8F%8A%E7%95%B0%E5%8B%95%E7%99%BB%E8%A8%98%E9%80%81%E4%BB%B6%E9%A0%88%E7%9F%A5-1150506.pdf)（內政部移民署）
2. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
3. [Guidelines for Online Application for Residence, Extension of Residence and Registration of Changes for Foreign Students and Overseas Compatriot Students](https://www.immigration.gov.tw/5475/5478/141465/141808/417829/cp_news)（內政部移民署）
4. [外國學生與僑生線上申請居留或延期居留及異動登記送件須知（前一版）](https://www.immigration.gov.tw/media/101057/0929%E5%A4%96%E5%9C%8B%E5%AD%B8%E7%94%9F%E8%88%87%E5%83%91%E7%94%9F%E7%B7%9A%E4%B8%8A%E7%94%B3%E8%AB%8B%E5%B1%85%E7%95%99%E6%88%96%E5%BB%B6%E6%9C%9F%E5%B1%85%E7%95%99%E5%8F%8A%E7%95%B0%E5%8B%95%E7%99%BB%E8%A8%98%E9%80%81%E4%BB%B6%E9%A0%88%E7%9F%A5.pdf)（內政部移民署）

### 外僑居留證遺失或污損補發

- 外國學生能否用學生線上申辦系統辦理遺失補發未能確認；補發文件與流程依一般外國人公告頁整理。
- 處理天數、污損補發是否須繳回原證、遺失具結書是否有官方範本，都未能確認。
- 以上依搜尋引擎讀取官方文件整理，沒有逐字核對原文。

來源：

1. [外國學生與僑生線上申請居留或延期居留及異動登記送件須知（1150506版）](https://www.immigration.gov.tw/media/118853/0929%E5%A4%96%E5%9C%8B%E5%AD%B8%E7%94%9F%E8%88%87%E5%83%91%E7%94%9F%E7%B7%9A%E4%B8%8A%E7%94%B3%E8%AB%8B%E5%B1%85%E7%95%99%E6%88%96%E5%BB%B6%E6%9C%9F%E5%B1%85%E7%95%99%E5%8F%8A%E7%95%B0%E5%8B%95%E7%99%BB%E8%A8%98%E9%80%81%E4%BB%B6%E9%A0%88%E7%9F%A5-1150506.pdf)（內政部移民署）
2. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
3. [外國人居留證將屆期或遺失之延期、補發申請方式](https://www.immigration.gov.tw/5385/7229/7232/368785/cp_news)（內政部移民署）

### 外籍生居留健康檢查與新生健檢

- 衛福部健康檢查參考事項最新版中，短期研修生的月數門檻與入境後照X光規定未能確認。
- 臺中指定醫院名單是搜尋時的快照，各院效期不同，請以疾管署最新名單為準。
- 逢甲首次申辦居留證頁面的3,000元（美籍4,000元）是健檢費還是簽證規費無法確認。
- 移民署具結書（30日內補正健檢報告）是否適用外籍學生未確認。
- 2026學年度逢甲新生健檢日期與費用尚未找到正式公告；文中是2025年資料。

來源：

1. [外籍人士(含陸配)居留健檢](https://www.cdc.gov.tw/Category/MPage/stSVgprnEAjd3LmsXeCTLA)（衛生福利部疾病管制署）
2. [居留或定居健康檢查項目表 Health Certificate for Residence Application](https://www.cdc.gov.tw/Uploads/files/%E5%B1%85%E7%95%99%E6%88%96%E5%AE%9A%E5%B1%85%E5%81%A5%E5%BA%B7%E6%AA%A2%E6%9F%A5%E9%A0%85%E7%9B%AE%E8%A1%A8.pdf)（衛生福利部疾病管制署）
3. [Items Required for Health Certificate for Residence in Taiwan](https://www.cdc.gov.tw/En/Category/ListContent/C4w0xUaCBCKzdd6BxDGWcA?uaid=y9n9sbUrcg_Pj6lGlPVDCA)（衛生福利部疾病管制署）
4. [外國人健檢指定醫院名單(國內)](https://www.cdc.gov.tw/Category/Page/nU7y97g0GqJbB3kn5B-nPg)（衛生福利部疾病管制署）
5. [外籍學位生(含陸生)健檢](https://www.cdc.gov.tw/Category/MPage/NUbynnEb1y3sP6gVFFhDSg)（衛生福利部疾病管制署）
6. [外籍短期研修生(含陸生)健檢](https://www.cdc.gov.tw/Category/MPage/nrbBMmzmDq3ntpCtW4MTDQ)（衛生福利部疾病管制署）
7. [外國學生申請居留簽證手續說明](https://www.boca.gov.tw/fp-9-186-c060a-1.html)（外交部領事事務局）
8. [在臺健康檢查具結書](https://www.immigration.gov.tw/media/19227/%E5%9C%A8%E8%87%BA%E5%81%A5%E5%BA%B7%E6%AA%A2%E6%9F%A5%E5%85%B7%E7%B5%90%E6%9B%B8.pdf)（內政部移民署）
9. [Apply for an Alien Resident Certificate (ARC)](https://oia.fcu.edu.tw/en/overseas-students/new/first-arc/)（逢甲大學國際事務處）
10. [Instruction for health checkup (Mandatory! On-Campus Health Checkup for Freshmen)](https://oia.fcu.edu.tw/en/overseas-students/new-fall/health-fall/)（逢甲大學國際事務處）
11. [境外新生健康檢查（秋季班）](https://freshman.fcu.edu.tw/overseas-students/health-fall/)（逢甲大學新生專區）
12. [外籍學生居留健康檢查問答輯](https://www.cdc.gov.tw/Uploads/files/91acc138-eb08-46b2-921d-c1356f9223e9.pdf)（衛生福利部疾病管制署）

### 加入全民健康保險（健保）與申辦健保卡

- 每月826元是健保署自110年起的標準，2026年是否調整無法確認。
- 衛福部曾研議取消外籍生須居留滿6個月才能加保的限制，查不到正式施行公告，仍以6個月為準。
- 逢甲國際學生醫療保險的費用與理賠上限未標示適用學年，可能已調整。
- 首次申領健保卡是否免工本費、製卡天數，未在官方頁面確認。
- 罰鍰3,000至5,000元取自逢甲網頁，沒有直接核對健保法條文。

來源：

1. [在臺僑生、外籍生參加全民健康保險須知](https://www.nhi.gov.tw/ch/dl-72718-2f56651c5a814b4cae4b8176333914e7-1.pdf)（衛生福利部中央健康保險署）
2. [在學僑生、外籍生應繳納多少保險費，如何繳納？](https://www.nhi.gov.tw/ch/cp-3791-61e1b-3246-1.html)（衛生福利部中央健康保險署）
3. [Foreign Nationals from Hong Kong, Macau, China, or Other Countries who Reside in Taiwan with an ARC](https://eng.nhi.gov.tw/en/cp-49-fb4a6-24-2.html)（衛生福利部中央健康保險署）
4. [Examples for foreign nationals to calculate their length of stay in order to enroll in the NHI](https://www.nhi.gov.tw/en/cp-614-41d3b-113-2.html)（衛生福利部中央健康保險署）
5. [如何申辦健保卡](https://www.nhi.gov.tw/ch/np-2667-1.html)（衛生福利部中央健康保險署）
6. [請領健保卡申請表](https://www.nhi.gov.tw/ch/dl-67284-06928126dbb24356977da6fa1de1dae3-1.pdf)（衛生福利部中央健康保險署）
7. [The NHIA Reminds Foreign Nationals to Renew their ARCs to Ensure their NHI Rights](https://www.nhi.gov.tw/en/cp-1169-2d460-8-2.html)（衛生福利部中央健康保險署）
8. [外國學生來臺就學辦法](https://law.moj.gov.tw/LawClass/LawAll.aspx?PCode=H0110001)（教育部（全國法規資料庫））
9. [境外學生保險](https://oia.fcu.edu.tw/overseas-students/insurance/)（逢甲大學國際事務處）
10. [Insurance for Overseas Students](https://oia.fcu.edu.tw/en/overseas-students/insurance/)（逢甲大學國際事務處）
11. [購買保險及清寒證明申請](https://oia.fcu.edu.tw/overseas-students/new/lowincome/)（逢甲大學國際事務處）
12. [Overseas students stay in Taiwan after graduation](https://oia.fcu.edu.tw/en/overseas-students/stayintaiwan/)（逢甲大學國際事務處）
13. [Health 醫療資訊（華語教學中心）](https://clc.fcu.edu.tw/en/health/)（逢甲大學華語教學中心）

### 申請外國留學生工作許可（工讀）

- 許可效期：現行辦法第54條、勞動部問答集與逢甲國際處都寫最長1年，但較舊新聞稿寫最長6個月；卡片採1年，以系統核定迄日為準。
- 學生工作許可的審核天數官方未寫明，所以卡片沒有寫。
- 交換學生是否適用、是否另有限制，未取得原文確認。
- 逢甲華語中心頁面寫華語生第一年不得工作、每週最多12小時，與現行法規（語言生滿6個月、每週20小時）不一致，疑為舊資料，需向華語中心或國際處確認。
- 逢甲國際處寫核發後3至5天到國際處領取，與電子許可函流程的關係未確認。
- 臺灣Pay繳費依據是2023年版操作手冊，現行介面未確認。

來源：

1. [外國人在臺工作服務網－在臺求學期間工讀](https://ezworktaiwan.wda.gov.tw/cp.aspx?n=99329239A3FBA2BB)（勞動部勞動力發展署）
2. [僑外學生申請工作許可全面網路線上申辦問答集](https://ezworktaiwan.wda.gov.tw/News_Content.aspx?n=77054B15FD1F5128&sms=2E02279676D3E77B&s=5C73DC0C790B04D9)（勞動部勞動力發展署）
3. [雇主聘僱外國人許可及管理辦法 第五章 第四類外國人聘僱許可之申請](https://laws.mol.gov.tw/FLAW/FLAWDAT0201.aspx?id=FL028065&beginpos=5)（勞動部）
4. [就業服務法申請案件審查費及證照費收費標準](https://laws.mol.gov.tw/FLAW/FLAWDAT0202.aspx?id=FL028068)（勞動部）
5. [就業服務法 第68條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?FLNO=68&Pcode=N0090001)（法務部全國法規資料庫）
6. [僑外生申請工作許可，寒暑打工不限每週20小時](https://www.wda.gov.tw/News_Content.aspx?n=31&s=3868)（勞動部勞動力發展署）
7. [友善在臺僑外學生，簡化申請工作許可文件](https://www.mol.gov.tw/1607/1632/1640/20278/)（勞動部）
8. [僑外學生申請工作許可以電子公文方式送達工作許可函問答集（學生版）](https://ezwp.wda.gov.tw/wcfonline/wSite/download/ForeignStudents_OfficialDocumentsElectronization(Q&A)-Student.pdf)（勞動部勞動力發展署）
9. [Work Permit（境外生工作證）](https://oia.fcu.edu.tw/en/overseas-students/work-permit/)（逢甲大學國際事務處）
10. [大陸學生是否可申請學生工作證？](https://ezworktaiwan.wda.gov.tw/News_Content.aspx?n=77054B15FD1F5128&sms=2E02279676D3E77B&s=A4A553DE179ED96F)（勞動部勞動力發展署）
11. [No 20-hour limit on summer vacation jobs for overseas Chinese and international students with working permits](https://www.wda.gov.tw/en/News_Content.aspx?n=179&sms=10373&s=13639)（勞動部勞動力發展署）
12. [外國專業人員工作許可申辦網操作手冊](https://ezwp.wda.gov.tw/wcfonline/wSite/download/std20230311_060101.pdf)（勞動部勞動力發展署）

### 申請逢甲大學在學證明書

- 在校生申請在學證明的實際方式（臨櫃、線上或自助機）官方頁面沒有說明。
- 註冊課務組核發需要多久，官方未寫。
- 收費標準頁面可能是舊資料，送件前建議再確認。
- 境外學位生是否可以改向國際事務處申請，沒有官方資料。

來源：

1. [收費標準－註冊課務組](https://registration.fcu.edu.tw/%E9%A6%96%E9%A0%81-2/%E6%9C%8D%E5%8B%99%E5%B0%8D%E8%B1%A1/%E6%94%B6%E8%B2%BB%E6%A8%99%E6%BA%96/)（逢甲大學教務處註冊課務組）
2. [註冊課務組首頁](https://registration.fcu.edu.tw/en/)（逢甲大學教務處註冊課務組）
3. [業務職掌－註冊課務組](https://registration.fcu.edu.tw/en/%E9%A6%96%E9%A0%81-2/team/)（逢甲大學教務處註冊課務組）
4. [成績列印全自動繳費系統啟用（2009年逢甲週報）](https://www.fcu.edu.tw/fcuweekly/en/news/2009111914/)（逢甲大學）
5. [學籍及成績網路申請作業](https://service132-sds.fcu.edu.tw/w3119/alumniLogin.aspx)（逢甲大學）
6. [Alien Resident Certificate (ARC)](https://oia.fcu.edu.tw/en/overseas-students/arc/)（逢甲大學國際事務處）
7. [Work Permit（境外生工作證）](https://oia.fcu.edu.tw/en/overseas-students/work-permit/)（逢甲大學國際事務處）
8. [ADMISSIONS（華語中心）](https://clc.fcu.edu.tw/en/admissions-2/)（逢甲大學華語教學中心）

### 外籍學生在臺開立銀行／郵局帳戶

- 沒有統一規定「居留未滿6個月不得開戶」，只確認了個別銀行門檻（台新臨櫃3個月、Richart距到期90天）；其他銀行可能不同。
- 開戶需要臺灣手機號碼並非法規明文，只是國發會網站建議。
- 郵局暫停受理護照加基資表開戶的措施何時恢復，沒有找到公告。
- 逢甲國際處沒有專門開戶指南，學校沒有指定撥款銀行。
- 台新外籍客戶開戶須知約兩年前更新，現行條件請向分行確認。

來源：

1. [銀行局業務問答集（114年7月版，外籍學生開戶）](https://www.banking.gov.tw/websitedowndoc?file=chbanking%2F202507281654100.pdf&filedisplay=1140724+%E6%9C%AC%E5%B1%80QA%E5%95%8F%E9%A1%8C%E9%9B%86.pdf)（金融監督管理委員會銀行局）
2. [銀行辦理來臺就學之海外學生開設非支票存款之一般存款帳戶規定](https://law.fsc.gov.tw/LawContent.aspx?id=FE220621)（金融監督管理委員會）
3. [Opening of Deposit Account](https://www.banking.gov.tw/en/home.jsp?id=201&parentpath=0,179)（金融監督管理委員會銀行局）
4. [外籍客戶開戶須知](https://www.taishinbank.com.tw/TSB/personal/common/important-notice/TSBankImportantNotice-001191/)（台新國際商業銀行）
5. [活期性存款](https://www.taishinbank.com.tw/TSB/personal/deposit/twd/demand-deposit/TSBankGridPage-000034-00001/)（台新國際商業銀行）
6. [分行據點（逢甲分行）](https://www.taishinbank.com.tw/TSB/service-and-support/branch-finder/?page=12)（台新國際商業銀行）
7. [新生上傳銀行帳本說明](https://freshman.fcu.edu.tw/upload_bankbook_cover/)（逢甲大學）
8. [儲匯專區－開戶及憑辦文件](https://www.post.gov.tw/post/internet/B_saving/index.jsp?ID=3010102)（中華郵政股份有限公司）
9. [存款帳戶及其疑似不法或顯屬異常交易管理辦法](https://law.fsc.gov.tw/LawContent.aspx?id=FL039015)（金融監督管理委員會）
10. [Banking and Finance（Guide to Taiwan）](https://goldcard.nat.gov.tw/en/guide-to-taiwan/banking-and-finance/)（國家發展委員會）
11. [Apply for an Alien Resident Certificate (ARC)](https://oia.fcu.edu.tw/en/overseas-students/new/first-arc/)（逢甲大學國際事務處）
12. [金管會持續推動友善外國人在臺之金融服務措施](https://www.fsc.gov.tw/ch/home.jsp?id=96&parentpath=0%2C2&mcustomize=news_view.jsp&dataserno=202302090004&dtable=News)（金融監督管理委員會）
13. [115學年度碩士在職專班開學前應辦事項檢核表（銀行帳號登錄）](https://webadmi.fcu.edu.tw/115/research/army/115master_army_P02.pdf)（逢甲大學）
14. [Richart 重要公告（外籍人士數位帳戶申請資格）](https://richart.tw/TSDIB_RichartWeb/announcements/details?type=important&announceNo=34327)（台新國際商業銀行）

### 在MyFCU登錄撥款銀行帳戶

- 出納組分機有2361與2301兩個版本，未確認現行分機，所以卡片只寫總機。
- 學雜費退費是否也匯入這個帳戶，沒有找到明文。
- 是否接受外幣帳戶、純數位帳戶要上傳什麼文件，未確認。
- 部分路徑說明來自2017、2023年的文件，MyFCU選單名稱可能已調整。
- 審核需要多少工作天，沒有找到。

來源：

1. [新生上傳銀行帳本說明](https://freshman.fcu.edu.tw/upload_bankbook_cover/)（逢甲大學）
2. [建立逢甲大學個人帳戶示範（網頁版）](https://service825.fcu.edu.tw/infofiles/F2017019080.pdf)（逢甲大學）
3. [115學年度碩士在職專班開學前應辦事項檢核表](https://webadmi.fcu.edu.tw/115/research/army/115master_army_P02.pdf)（逢甲大學）
4. [112學年度寒假轉學生開學前應辦事項重要日程檢核表](https://webadmi.fcu.edu.tw/113/college/transfer/112transfer_05.pdf)（逢甲大學註冊課務組）
5. [生活助學金](https://student.fcu.edu.tw/%E7%94%9F%E6%B4%BB%E5%8A%A9%E5%AD%B8%E9%87%91/)（逢甲大學學務處生活輔導組）
6. [出納組](https://ga.fcu.edu.tw/%E5%87%BA%E7%B4%8D%E7%B5%84/)（逢甲大學財務處）
7. [MyFCU](https://its.fcu.edu.tw/myfcu-0)（逢甲大學資訊處）

### 逢甲大學學生請假

- 沒有找到境外生學期中出境（離開臺灣）的請假或通報規定，建議向國際事務處確認。
- 華語生出缺勤（請假也計入缺課，不得超過總時數1/4）會影響居留，華語中心是否另有請假規定未確認。
- 心理健康假（新聞報導每學期3天）沒有在官方頁面確認。
- 生理假天數上限、請假是否影響扣考，沒有逐字確認。

來源：

1. [學生請假](https://student.fcu.edu.tw/en/%E5%AD%B8%E7%94%9F%E8%AB%8B%E5%81%87/)（逢甲大學學務處）
2. [逢甲大學學生請假辦法（1130708核定公布）](https://s3.ap-southeast-1.amazonaws.com/web-content.fcu.edu.tw/wp-content/uploads/sites/93/2024/09/24170319/%E9%80%A2%E7%94%B2%E5%A4%A7%E5%AD%B8%E5%AD%B8%E7%94%9F%E8%AB%8B%E5%81%87%E8%BE%A6%E6%B3%95_1130708%E6%A0%B8%E5%AE%9A%E5%85%AC%E5%B8%83.pdf)（逢甲大學）
3. [逢甲大學學生請假辦法（2021年舊版）](https://s3.ap-southeast-1.amazonaws.com/web-content.fcu.edu.tw/wp-content/uploads/sites/45/2021/11/03145006/f1511167899122.pdf)（逢甲大學）
4. [學生公假申請流程（由教職員申請）](https://s3.ap-southeast-1.amazonaws.com/web-content.fcu.edu.tw/wp-content/uploads/sites/93/2021/05/16102901/%E5%85%AC%E5%81%87%E7%94%B3%E8%AB%8B%E6%B5%81%E7%A8%8B.pdf)（逢甲大學學務處）
5. [教師批核學生假單流程](https://s3.ap-southeast-1.amazonaws.com/web-content.fcu.edu.tw/wp-content/uploads/sites/93/2021/05/16102902/%E6%95%99%E5%B8%AB%E6%89%B9%E6%A0%B8%E6%B5%81%E7%A8%8B.pdf)（逢甲大學學務處）

### 補發逢甲學生證（逢甲卡）

- 補發所需工作天數、領取地點、繳費方式，官方資料沒有寫。
- 補發是否要重新上傳照片，未確認。
- 悠遊卡餘額能否轉移、是否要另外向悠遊卡公司掛失，沒有找到逢甲說明。
- 收費標準頁面沒有更新日期。

來源：

1. [逢甲卡](https://its.fcu.edu.tw/fcucard)（逢甲大學資訊處）
2. [收費標準－註冊課務組](https://registration.fcu.edu.tw/%E9%A6%96%E9%A0%81-2/%E6%9C%8D%E5%8B%99%E5%B0%8D%E8%B1%A1/%E6%94%B6%E8%B2%BB%E6%A8%99%E6%BA%96/)（逢甲大學教務處註冊課務組）
3. [業務職掌－註冊課務組](https://registration.fcu.edu.tw/en/%E9%A6%96%E9%A0%81-2/team/)（逢甲大學教務處註冊課務組）

### 境外新生報到（國際事務處）

- 2026秋季班的確切報到日期與時段未能確認；秋季班時段表可能是2025年的。
- 國際處 email 有兩個版本，未確認現行信箱。
- 港澳生證明文件名稱中英文不一致；「滿20歲」計算日未說明。

來源：

1. [境外新生報到（秋季班）](https://oia.fcu.edu.tw/overseas-students/new-fall/registration-fall/)（逢甲大學國際事務處）
2. [Registration (Spring Semester)](https://oia.fcu.edu.tw/en/overseas-students/new-spring/registration-spring/)（逢甲大學國際事務處）
3. [New Overseas Students](https://freshman.fcu.edu.tw/en/overseas-students/)（逢甲大學新生專區）
4. [Alien Resident Certificate (ARC)](https://oia.fcu.edu.tw/en/overseas-students/arc/)（逢甲大學國際事務處）
5. [More Than 4,000 Freshmen Gather at Feng Chia University](https://ga.fcu.edu.tw/en/news-detail/?id=51940)（逢甲大學）
6. [New Overseas Students (Fall Semester)](https://oia.fcu.edu.tw/en/overseas-students/new-fall/)（逢甲大學國際事務處）

### MyFCU 新生報到檢核表

- 檢核表完整項目清單未取得，各學年可能不同，請以 MyFCU 實際顯示為準。
- 選單名稱英文版本寫法不一（For New Student／New Students）。
- 2026秋季班的照片、繳費、健檢期限未確認；參考頁面多為2025秋季班。

來源：

1. [Review the registration checklist](https://freshman.fcu.edu.tw/en/overseas-students/myfcu-checklist/)（逢甲大學新生專區）
2. [新生報到流程檢核說明](https://freshman.fcu.edu.tw/news/new_st_checklist/)（逢甲大學新生專區）
3. [Registration (Spring Semester)](https://oia.fcu.edu.tw/en/overseas-students/new-spring/registration-spring/)（逢甲大學國際事務處）
4. [境外新生報到（秋季班）](https://oia.fcu.edu.tw/overseas-students/new-fall/registration-fall/)（逢甲大學國際事務處）
5. [境外新生健康檢查（秋季班）](https://freshman.fcu.edu.tw/overseas-students/health-fall/)（逢甲大學新生專區）
6. [境外新生繳交學雜費](https://oia.fcu.edu.tw/overseas-students/new/payment/)（逢甲大學國際事務處）

### 停留簽證改辦就學居留簽證

- 美國護照在國內改辦居留簽證的確切金額未查證。
- 正式班學位生是否一律直接向移民署申請、不必再向領務局改辦，官方寫「得」，兩條管道可能並存，請向國際處確認。
- 持停留簽證直接向移民署申請居留時是否加收2,200元，只看到摘要。
- 有學校網頁寫7個工作天，本卡採領務局的8個工作天。

來源：

1. [外國學生申請居留簽證手續說明（正式班外國學生）](https://www.boca.gov.tw/cp-402-185-35222-1.html)（外交部領事事務局）
2. [Resident Visas for Foreign Students](https://www.boca.gov.tw/cp-166-283-c4da3-2.html)（外交部領事事務局）
3. [外國護照簽證收費標準](https://www.boca.gov.tw/cp-212-4293-63c3a-1.html)（外交部領事事務局）
4. [外交部中部辦事處](https://www.boca.gov.tw/cp-105-203-40dfe-1.html)（外交部領事事務局）
5. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
6. [Alien Resident Certificate (ARC)](https://oia.fcu.edu.tw/en/overseas-students/arc/)（逢甲大學國際事務處）

### 華語生申請居留（外僑居留證）

- 延期居留是否每次都要附出席紀錄，未看到全文確認。
- 直接向移民署申請時是否必附財力證明、研習計畫書，無法確認。
- 規費1,000元／加收2,200元是否適用華語生，未看到全文確認。
- 華語中心「到期前10天內延期」未與移民署現行規定交叉核對。

來源：

1. [外籍人士在台研習中文申請居留簽證手續說明](https://www.boca.gov.tw/cp-402-190-93573-1.html)（外交部領事事務局）
2. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
3. [Student Visa 簽證（華語中心）](https://clc.fcu.edu.tw/student-visa/)（逢甲大學華語教學中心）
4. [臺中市第一服務站](https://servicestation.immigration.gov.tw/1473/)（內政部移民署）

### 外僑居留證異動登記（住址變更等）

- 單純變更住址是否免費，須知沒有明確寫。
- 借住時的文件要求可能出自一般外國人須知，未確認是否為學生專用。
- 轉學是否要辦異動登記、要附哪些文件，沒有查到。
- 逢甲畢業生搬遷頁與舊版須知寫15日，本卡採移民署現行30日。

來源：

1. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
2. [外國人於居留期間，須於幾日內辦理變更居留住址或服務處所？](https://www.immigration.gov.tw/5385/12162/12197/371903/)（內政部移民署）
3. [Alien Resident Certificate (ARC)](https://oia.fcu.edu.tw/en/overseas-students/arc/)（逢甲大學國際事務處）
4. [臺中市第一服務站](https://servicestation.immigration.gov.tw/1473/)（內政部移民署）

### 加入健保前的學生醫療保險（醫保／僑保）

- 逢甲保險頁面未標示更新日期；較舊資料寫醫保 NT$2,500，本卡採國際處現行頁面的 NT$3,000。
- 醫保保費的繳交方式與時間（是否隨學雜費代收）未確認。
- 理賠申請期限與不保事項未確認。
- 僑保自付金額可能依僑委會通知每年調整。

來源：

1. [外國學生來臺就學辦法（第22條）](https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=H0110001)（法務部全國法規資料庫）
2. [境外學生保險](https://oia.fcu.edu.tw/overseas-students/insurance/)（逢甲大學國際事務處）
3. [Insurance for Overseas Students](https://oia.fcu.edu.tw/en/overseas-students/insurance/)（逢甲大學國際事務處）
4. [僑務委員會僑生傷病醫療保險作業要點](https://law.ocac.gov.tw/law/LawContent.aspx?id=GL000156)（僑務委員會）
5. [在臺僑生、外籍生參加全民健康保險須知](https://www.nhi.gov.tw/ch/dl-72718-2f56651c5a814b4cae4b8176333914e7-1.pdf)（衛生福利部中央健康保險署）

### 畢業後延期居留在臺覓職

- 延期長度：舊版教育部與移民署問答寫「6個月加1次，最長1年」，較新的教育部、國發會、勞動部與逢甲說明是「1年加1次，最長2年」；本卡採新版。
- 申請期限：逢甲頁面同時寫領取畢業證書後10日內與15天內，官方只說居留期限屆滿前。
- 延期居留規費、能否用學生線上系統申請（逢甲說要臨櫃），未確認。
- 畢業後第6類投保依搜尋摘要整理，未看到原頁全文。

來源：

1. [境外學生輔導資訊交流平台常見問答：畢業後延期居留](https://www.nisa.moe.gov.tw/faq.new/view/menu_sn/0/sn/895)（教育部）
2. [2026年起僑外生畢業2年內工作免許可](https://www.ndc.gov.tw/nc_16183_39953)（國家發展委員會）
3. [應屆畢業生延期居留期間免申請工作許可](https://ezworktaiwan.wda.gov.tw/cp.aspx?n=511766BD9E956242)（勞動部勞動力發展署）
4. [Overseas students stay in Taiwan after graduation](https://oia.fcu.edu.tw/en/overseas-students/stayintaiwan/)（逢甲大學國際事務處）
5. [外國學生與僑生線上申請居留或延期居留及異動登記（移民署居留業務頁）](https://www.immigration.gov.tw/5385/7244/7250/7317/%E5%B1%85%E7%95%99/362168/)（內政部移民署）
6. [境外學生輔導資訊交流平台常見問答：僑外生畢業後健保](https://www.nisa.moe.gov.tw/faq.new/view/menu_sn/0/sn/807)（教育部）
7. [在臺僑生、外籍生參加全民健康保險須知](https://www.nhi.gov.tw/ch/dl-72718-2f56651c5a814b4cae4b8176333914e7-1.pdf)（衛生福利部中央健康保險署）

## 研究中發現的說法不一致

- 居留證申請期限：部分大學與舊資料寫 15 日，移民署送件須知與逢甲國際處寫入國翌日起 30 日 → 卡片採 30 日
- 居留證延期時點：移民署寫到期前 3 個月內，部分學校寫 30 日內 → 卡片採 3 個月
- 工作許可效期：現行辦法與逢甲寫最長 1 年，舊新聞稿寫 6 個月 → 卡片採 1 年
- 華語生工作許可：法規是語言生滿 6 個月、每週 20 小時；逢甲華語中心頁面寫第一年不得工作、每週 12 小時（疑為舊資料）
- 畢業後覓職延期：舊版問答寫 6 個月可延一次，教育部、國發會、勞動部新資料寫 1 年可延一次（最長 2 年），且 2026 年起延期期間免工作許可 → 卡片採新版
- 住址變更期限：舊版須知與逢甲畢業生頁寫 15 日，移民署現行寫 30 日 → 卡片採 30 日
