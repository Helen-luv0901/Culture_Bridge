# Culture Bridge 產品地圖

> The experience-led MVP direction is now defined in [Experience-Led MVP](experience-led-mvp.md). The Action Card model below remains a later supporting layer for verified administrative information, not the primary MVP home experience.

## 0. 產品一句話定義

Culture Bridge 是一個「由真實國際生執行結果持續更新的生活任務平台」。

產品不是要取代 ChatGPT，也不是單純提供資訊，而是：

> 將國際生實際執行生活任務時產生的成功、卡關、差異與經驗，轉化為持續更新、可追溯的在地知識，提供下一位學生更可靠的行動指引。

核心價值不是 AI 本身，而是：

**Local Execution Data × Community Feedback Loop × Action Workflow**

---

# 1. 核心問題

一般 AI 可以回答：

* ARC 怎麼申請？
* 工作證需要什麼？
* 健保怎麼辦？
* 怎麼開銀行帳戶？

但無法穩定回答：

* 這個流程現在還能不能用？
* 最近真的有人照這個流程成功嗎？
* 哪一步最近最多人卡住？
* 逢甲國際生實際辦理時有沒有額外要求？
* 我的情況和其他學生哪裡不同？

Culture Bridge 要補的是這一層。

---

# 2. 核心產品閉環

```text
User 有一件事情要完成
        ↓
搜尋 / 選擇 Action Card
        ↓
按照步驟實際執行
        ↓
回報：
成功 / 卡住 / 流程不同
        ↓
產生 Execution Signal
        ↓
AI 協助整理回饋
        ↓
來源確認 / 管理者複核
        ↓
更新 Action Card
        ↓
下一位 User 取得更準確資訊
```

產品循環：

```text
ASK
 ↓
ACT
 ↓
REPORT
 ↓
VERIFY
 ↓
UPDATE
 ↓
HELP NEXT USER
 ↺
```

---

# 3. 產品四層架構

## Layer 1｜Action

使用者真正想做的事情。

例如：

* Apply for Work Permit
* Renew ARC
* Get Health Insurance
* Open a Bank Account
* Take a Leave
* Get from Airport to Campus

首頁應優先呈現「我要完成什麼」，而不是：

* 社群
* AI
* 影片

---

## Layer 2｜Community

讓使用者在正常使用過程中留下低成本回饋。

不要求 User 主動「維護知識庫」。

主要訊號：

### 制度型資訊

* 我也是這樣辦
* 和我的情況不同
* 我卡在這一步
* 這個資訊可能過時

### 經驗型資訊

* 我也遇過
* 對我有幫助
* 我的經驗不同

---

## Layer 3｜Knowledge

將零散資訊整理成結構化知識。

主要內容：

* Action Card
* Verified Knowledge
* User Execution Records
* Community Experience
* Source Evidence
* Update History

---

## Layer 4｜AI

AI 不是產品核心。

AI 主要負責：

1. 搜尋適合的 Action Card
2. 根據 Knowledge Base 回答問題
3. 將 User 回饋整理成結構化資訊
4. 摘要多人回報中的共同問題
5. 找出可能過時或衝突的資訊
6. 協助管理員更新內容

AI 不直接把任何 User Post 視為事實。

---

# 4. 使用者類型

## User A｜第一年來台國際生

主要需求：

* 解決生活問題
* 知道下一步做什麼
* 確認資訊是否仍適用
* 查看其他學生的實際經驗

---

## User B｜已經辦理過的學生／學長姐

主要行為：

* 回報自己是否成功
* 補充不同流程
* 分享經驗
* 回答其他人的問題

不要求其主動當 Fact Checker。

---

## User C｜管理員／PMP／合作單位

主要行為：

* 管理 Action Card
* 確認來源
* 處理衝突資訊
* 更新制度型內容
* 查看近期異常

---

# 5. 內容必須分成兩種類型

這是核心資料模型，不可混在一起。

## A. FACT / PROCEDURE

可以被驗證的資訊。

例如：

* 工作證
* ARC
* 健保
* 校務系統
* 銀行帳戶
* 在學證明

可以具有：

```text
Verified
Needs Review
Outdated
Context-specific
```

---

## B. EXPERIENCE

沒有唯一正確答案的內容。

例如：

* 敬語
* 教授互動
* 租屋
* 飲食
* 文化差異
* 交友
* 台灣人的說話方式

不可標記：

```text
Correct / Wrong
```

應使用：

```text
I experienced this too
Helpful
My experience was different
```

---

# 6. 核心物件：Action Card

Action Card 是 MVP 最重要的產品物件。

範例：

```text
Apply for a Work Permit

Status:
🟢 Recently Verified

Applicable to:
International Students

Location:
Feng Chia University / Taiwan

Last verified:
2026-08-16

Recent activity:
17 students completed this recently
3 students reported differences

Completion rate:
82%

Steps:

1. Prepare ARC
   [Done] [I'm stuck]

2. Prepare Student ID
   [Done] [I'm stuck]

3. Prepare Enrollment Certificate
   [Done] [I'm stuck]

4. Submit online application
   [Done] [I'm stuck]

5. Wait for approval
   [Done] [I'm stuck]

After completion:

[✓ I successfully completed this]

[△ My process was different]

[!] I couldn't complete it
```

---

# 7. Action Card 資訊結構

```text
ActionCard
├── id
├── title
├── description
├── category
├── target_user
├── location
├── institution
├── status
├── last_verified_at
├── source
│
├── steps[]
│   ├── step_number
│   ├── title
│   ├── description
│   ├── required_documents[]
│   └── notes
│
├── recent_success_count
├── recent_failure_count
├── difference_report_count
├── completion_rate
│
├── related_experiences[]
└── update_history[]
```

---

# 8. Execution Record

每次 User 實際使用 Action Card，都可以產生 Execution Record。

```text
ExecutionRecord
├── id
├── user_id
├── action_card_id
├── started_at
├── completed_at
├── current_step
│
├── result
│   ├── SUCCESS
│   ├── FAILED
│   └── DIFFERENT
│
├── stuck_step
├── feedback
└── context
```

User 不需要填完整表單。

資料應從正常操作中自然取得。

---

# 9. 最重要的 UX：低成本回饋

避免：

```text
Please provide additional information:
[_______________________________]
```

應設計成 Progressive Disclosure。

例如：

```text
Was the process the same for you?

[Yes]

[Some things were different]
```

選擇：

```text
Some things were different
```

才出現：

```text
What was different?

[Documents]

[Fee]

[Location]

[Process]

[Eligibility]

[Other]
```

例如 User 選：

```text
Documents
```

再詢問：

```text
What additional document did you need?

[Enrollment Certificate]
```

AI 可整理成：

```text
You reported:

"I was additionally asked to provide an
Enrollment Certificate."

[Confirm]
```

使用者不需要寫完整內容。

---

# 10. Community Post

社群依然存在，但不是產品核心首頁。

Post 建立時必須選：

```text
Post Type

[Ask about a procedure]

[Ask about experience]
```

---

## Procedure Post

例如：

```text
Do I need ARC before applying for a work permit?
```

可回應：

```text
Same for me
Different for me
Possibly outdated
```

---

## Experience Post

例如：

```text
Is saying 「蛤？」considered rude in Taiwan?
```

可回應：

```text
I experienced this too
Helpful
My experience was different
```

---

# 11. Verified Knowledge

Community Post 不直接進 Knowledge Base。

流程：

```text
Community Post
      ↓
Community Signals
      ↓
Candidate Knowledge
      ↓
AI Structuring
      ↓
Source / Admin Verification
      ↓
Verified Knowledge
      ↓
Action Card / AI
```

---

# 12. Knowledge 狀態機

```text
UNVERIFIED
    ↓
COMMUNITY_SUPPORTED
    ↓
NEEDS_REVIEW
    ↓
VERIFIED
    ↓
OUTDATED
    ↓
NEEDS_REVIEW
```

制度資訊至少需要：

```text
status
last_verified_at
applicable_context
source
```

---

# 13. Knowledge Card

不是所有知識都要成為 Action Card。

例如：

```text
WORK PERMIT DOCUMENT REQUIREMENTS

Type:
FACT

Status:
Verified

Applicable:
International Student / FCU

Last Verified:
2026-08-16

Sources:
- Official source
- PMP Q&A

Community signals:
14 same
2 different

Related Action:
Apply for Work Permit
```

Knowledge Card 是後端知識單位。

Action Card 是前端任務單位。

---

# 14. AI Assistant

AI Assistant 不能只是一般聊天框。

回答格式應包含：

```text
Answer

Based on:
Culture Bridge Knowledge #WP001

Status:
Recently Verified

Last verified:
2026-08-16

Recent users:
17 successful completions

[Start this Action]

[View Sources]
```

---

# 15. AI 回答優先順序

```text
1. Verified Knowledge
2. Action Card
3. Official Sources
4. Community Experience
5. Unverified Community Post
```

第 5 類只能作補充，不能直接當作確定事實。

---

# 16. AI 不允許做的事情

AI 不應：

* 因為多人按 Like 就認定資訊正確
* 自動把 Community Post 變成 Verified
* 自動修改制度型 Action Card
* 把 Experience 當 Fact
* 沒有來源卻顯示 Verified
* 使用單純「多數決」判定制度資訊

---

# 17. 首頁資訊架構

首頁核心 CTA：

```text
What do you need to do in Taiwan?
```

下方：

```text
🪪 Renew ARC

💼 Apply for Work Permit

🏥 Get Health Insurance

🏦 Open a Bank Account

🏫 Take a Leave

🚌 Get Around Taiwan
```

Action Card Preview：

```text
Apply for Work Permit

🟢 Recently Verified

18 students completed recently

Updated 3 days ago

[Start]
```

---

# 18. Bottom Navigation

MVP 建議：

```text
Home
Community
Ask AI
Profile
```

其中：

Home = Action

Community = Experience / Questions

Ask AI = Knowledge Interface

Profile = My Actions / Contribution

---

# 19. Action Detail Screen

```text
Header
↓
Title
↓
Verification Status
↓
Recent Completion Data
↓
Applicability
↓
Step-by-step Process
↓
Related Experiences
↓
Sources
↓
Feedback
```

最重要 CTA：

```text
[Start Action]
```

---

# 20. 使用中的 Action

User 點 Start 後：

```text
My Action

Apply for Work Permit

Progress: 2 / 5

✓ Prepare ARC

✓ Prepare Student ID

○ Enrollment Certificate

○ Submit Application

○ Wait for Approval
```

每一步：

```text
[Done]

[I'm stuck]
```

---

# 21. Stuck Flow

User 點：

```text
I'm stuck
```

系統詢問：

```text
What happened?

[I don't understand the step]

[Required document is different]

[I can't find the location]

[Website doesn't work]

[Other]
```

這筆資料同時具有兩個用途：

1. 幫 User
2. 改善 Knowledge Base

---

# 22. 完成 Action

完成後：

```text
Did you successfully complete this?

[Yes]

[No]

[The process was different]
```

如果 Yes：

產生：

```text
ExecutionRecord.result = SUCCESS
```

如果 Different：

進入差異回報。

---

# 23. 真正的產品資料資產

Culture Bridge 最重要的資料不是 Chat Logs。

而是：

```text
Action
×
Step
×
Context
×
Execution Result
×
Time
```

例如：

```text
Apply Work Permit
Step 3
FCU International Student
SUCCESS
2026-08-15
```

長期可以得到：

```text
Where users get stuck
What changed recently
Which processes work
Which context causes differences
```

這才是與一般 LLM 的主要差異。

---

# 24. MVP Scope

## P0｜一定要完成

### Authentication

* Login
* Basic profile

### Action Card

* Action list
* Action detail
* Step checklist
* Start Action
* Complete Action

### Execution Feedback

* Success
* Stuck
* Different

### Community

* Create Post
* Reply
* Fact / Experience classification

### Community Signal

* Same
* Different
* Helpful

### Admin

* Create/Edit Action Card
* Review feedback
* Update verification status

### AI

* Search Action Card
* Answer based on Knowledge Base
* Summarize user feedback

---

# 25. P1｜有時間再做

* Short Video
* AI-generated summaries
* Source comparison
* Personalized Action recommendation
* Contribution badges
* Notifications
* Follow-up verification
* Translation
* Semantic search

---

# 26. P2｜先不要做

第一版不要做：

* 複雜排行榜
* 完整 Gamification
* Social Following
* Friend System
* 私訊
* Full TikTok Feed
* AI Fine-tuning
* Recommendation Algorithm
* 大型內容審核系統

先驗證核心閉環。

---

# 27. MVP 第一批 Action Cards

建議直接從 PMP 現有高頻問題開始：

1. Apply for Work Permit
2. Apply / Renew ARC
3. Get National Health Insurance
4. Open a Bank Account
5. Get Enrollment Certificate
6. Take a Leave
7. Link Bank Account to FCU
8. Lost Student ID / ARC

---

# 28. Database 初步 Entity

```text
User

ActionCard

ActionStep

ExecutionRecord

StepFeedback

CommunityPost

CommunityReply

CommunitySignal

KnowledgeItem

Source

VerificationRecord

AIConversation
```

---

# 29. Entity Relationship

```text
User
 │
 ├── ExecutionRecord
 │       │
 │       └── ActionCard
 │               │
 │               └── ActionStep
 │
 ├── CommunityPost
 │       │
 │       ├── CommunityReply
 │       └── CommunitySignal
 │
 └── AIConversation


KnowledgeItem
 │
 ├── Source
 ├── VerificationRecord
 └── ActionCard
```

---

# 30. Verification Score 不要直接等於 Truth Score

可以有 Internal Confidence。

例如：

```text
confidence =
recent_execution_signal
+ source_quality
+ admin_verification
+ consistency
```

但 UI 不需要直接顯示：

```text
Truth Score: 87%
```

建議 UI 顯示：

```text
Recently Verified

Needs Review

Possibly Outdated
```

避免製造虛假的精準度。

---

# 31. MVP 成功條件

第一輪不是驗證：

> AI 回答得準不準。

而是驗證：

### User 是否會使用 Action Card

```text
Action Start Rate
```

### User 是否願意留下低成本回饋

```text
Feedback Rate
```

### User 是否真的完成任務

```text
Completion Rate
```

### 哪些步驟造成卡關

```text
Step Failure Rate
```

### User 是否願意回報差異

```text
Difference Report Rate
```

---

# 32. 核心 KPI

建議至少追蹤：

```text
Action View → Start Conversion

Action Completion Rate

Feedback Participation Rate

Stuck Rate by Step

Difference Report Rate

Return Usage Rate

Knowledge Update Count
```

---

# 33. 產品真正的 Network Effect

不是：

```text
越多人 → 貼文越多
```

而是：

```text
越多人執行
↓
Execution Data 越多
↓
Action Card 越準
↓
下一個 User 更容易完成
↓
更多 User 願意使用
```

形成：

```text
Usage
 ↓
Execution Data
 ↓
Better Knowledge
 ↓
Better Action Guidance
 ↓
More Usage
```

---

# 34. 與 ChatGPT 的產品差異

| ChatGPT       | Culture Bridge            |
| ------------- | ------------------------- |
| 回答問題          | 協助完成任務                    |
| 通用知識          | 在地執行資料                    |
| 不知道 User 是否成功 | 記錄完成結果                    |
| 不知道哪一步卡住      | 有 Step-level feedback     |
| 不知道近期流程是否改變   | 有 Recent Execution Signal |
| 單次問答          | 持續更新閉環                    |
| AI 是產品核心      | AI 是知識介面                  |

---

# 35. Codex 開發優先順序

## Sprint 1

建立：

```text
User
ActionCard
ActionStep
ExecutionRecord
```

完成：

```text
Home
Action List
Action Detail
Action Progress
```

---

## Sprint 2

加入：

```text
Done
Stuck
Different
Success
```

完成 Execution Feedback Loop。

---

## Sprint 3

建立：

```text
CommunityPost
CommunityReply
CommunitySignal
```

完成 Fact / Experience 分類。

---

## Sprint 4

建立：

```text
Admin Dashboard
Verification
KnowledgeItem
Sources
```

---

## Sprint 5

加入 AI：

```text
User Question
↓
Retrieve Knowledge
↓
Retrieve Action Card
↓
Generate Answer
↓
Show Source + Status
```

---

# 36. Codex 開發原則

實作時請遵守：

1. Action Card 是核心，不要先做 Chat UI。
2. 不使用 Like / Dislike 判定真實性。
3. FACT 與 EXPERIENCE 資料模型必須分開。
4. 所有制度資訊必須支援 last_verified_at。
5. Execution Record 必須保存時間。
6. Feedback 應低摩擦，不使用長表單。
7. AI 不得直接修改 Verified Knowledge。
8. AI 回答要能追溯 Knowledge Item。
9. Community 是 Knowledge Input，不是唯一產品核心。
10. 第一版優先讓完整閉環跑通，而不是追求功能數量。

---

# 37. 最終產品心智模型

Culture Bridge 不是：

> International Student ChatGPT

也不是：

> International Student Reddit

也不是：

> International Student FAQ

而是：

> **A living action guide continuously updated by real student experiences.**

中文：

> **由真實學生執行結果持續更新的國際生生活行動指南。**

產品核心：

```text
ACTION
+
REAL EXECUTION
+
COMMUNITY SIGNAL
+
VERIFIED KNOWLEDGE
+
AI INTERFACE
```

AI 可以被替換。

模型可以從 GPT 換成 Gemini、Claude 或其他模型。

但真正應該累積、無法被大型語言模型直接取代的是：

```text
誰
在什麼情境
什麼時間
做了什麼
在哪一步卡住
最後有沒有成功
實際流程和原本資訊有什麼不同
```

這才是 Culture Bridge 應該長期建立的產品資產。
