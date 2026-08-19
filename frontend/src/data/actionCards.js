export const actionCards = [
  {
    id: "work-permit",
    icon: "工",
    title: "申請工作證",
    description: "依照目前的申請流程準備文件並送出申請。",
    status: "Recently Verified",
    lastVerified: "3 days ago",
    recentCompletions: 18,
    location: "Feng Chia University / Taiwan",
    applicableTo: "International students",
    sources: ["Official source", "PMP Q&A"],
    steps: ["準備 ARC", "準備學生證", "申請在學證明", "線上送出申請", "等待審核"],
  },
  {
    id: "arc",
    icon: "居",
    title: "申請或更新 ARC",
    description: "確認居留證申請、更新與必備文件。",
    status: "Recently Verified",
    lastVerified: "5 days ago",
    recentCompletions: 12,
  },
  {
    id: "insurance",
    icon: "保",
    title: "加入健保",
    description: "了解國際生健保資格與辦理步驟。",
    status: "Needs Review",
    lastVerified: "21 days ago",
    recentCompletions: 6,
  },
  {
    id: "bank", icon: "銀", title: "開銀行帳戶", description: "準備開戶所需文件與常見差異。", status: "Recently Verified", lastVerified: "1 week ago", recentCompletions: 9,
  },
  {
    id: "certificate", icon: "校", title: "申請在學證明", description: "取得校務流程所需的在學證明。", status: "Recently Verified", lastVerified: "4 days ago", recentCompletions: 22,
  },
  {
    id: "transport", icon: "交", title: "從機場到校園", description: "第一次抵台的交通與行李安排。", status: "Community Supported", lastVerified: "8 days ago", recentCompletions: 15,
  },
];

export const primaryAction = actionCards[0];
