"""English names of the agencies and offices that official guides cite."""

PUBLISHERS_EN = {
    "中華郵政股份有限公司": "Chunghwa Post",
    "僑務委員會": "Overseas Community Affairs Council",
    "內政部移民署": "National Immigration Agency",
    "勞動部": "Ministry of Labor",
    "勞動部勞動力發展署": "Workforce Development Agency",
    "台新國際商業銀行": "Taishin Bank",
    "國家發展委員會": "National Development Council",
    "外交部領事事務局": "Bureau of Consular Affairs",
    "教育部": "Ministry of Education",
    "教育部外國專業人員工作許可": "Work Permit Online Application (EZ Work Permit)",
    "教育部（全國法規資料庫）": "Ministry of Education (Laws & Regulations Database)",
    "法務部全國法規資料庫": "Laws & Regulations Database",
    "衛生福利部中央健康保險署": "National Health Insurance Administration",
    "衛生福利部疾病管制署": "Taiwan CDC",
    "逢甲大學": "FCU",
    "逢甲大學國際事務處": "FCU Office of International Affairs",
    "逢甲大學國際處": "FCU Office of International Affairs",
    "逢甲大學學務處": "FCU Office of Student Affairs",
    "逢甲大學學務處生活輔導組": "FCU Student Life Section",
    "逢甲大學學生事務處": "FCU Office of Student Affairs",
    "逢甲大學宿舍服務": "FCU Housing Services",
    "逢甲大學教務處註冊課務組": "FCU Registration Section",
    "逢甲大學新生專區": "FCU New Students",
    "逢甲大學華語教學中心": "FCU Chinese Language Center",
    "逢甲大學註冊課務組": "FCU Registration Section",
    "逢甲大學總務處": "FCU Office of General Affairs",
    "逢甲大學財務處": "FCU Office of Finance",
    "逢甲大學資訊處": "FCU Information Technology Office",
    "金融監督管理委員會": "Financial Supervisory Commission",
    "金融監督管理委員會銀行局": "FSC Banking Bureau",
}


def publisher_en(name: str) -> str:
    """The English name, or the original when there is none."""
    return PUBLISHERS_EN.get(name, name)
