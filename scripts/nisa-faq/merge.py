"""Merge the zh and en NISA FAQ scrapes (scrape.py) into backend/app/content/nisa_faq.json."""

import json
import sys
from pathlib import Path

SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2])

# Site order (faq_class value -> slug, zh, en), from the search form in both languages.
CATEGORIES = [
    ("admissions", "來臺就學", "General Questions and Admissions"),
    ("credentials", "學歷採認", "Recognition of Academic Records and Credentials"),
    ("visa-arc", "簽證/居留證", "Visa and ARC"),
    ("arrival-departure", "入出境", "Arrival and Departure"),
    ("part-time-work", "在學期間工讀", "Part-time Job and Work Permits"),
    ("health-insurance", "健保/保險", "Health and Insurance"),
    ("scholarships", "獎學金/助學金", "Scholarships and Financial aids"),
    ("taxes", "稅務", "Taxes"),
    ("nationality", "國籍", "Residency and Naturalization"),
    ("military-service", "兵役", "Military Service"),
    ("advising", "輔導", "Advising"),
    ("internship", "實習", "Internship"),
    ("life", "在臺生活", "Life Style"),
    ("work-after-graduation", "畢業後留臺工作", "Staying in Taiwan for Employment"),
    ("internship-after-graduation", "畢業後在臺實習", "Internship after Graduation"),
    ("privacy", "個資保護", "Personal Informational Protection Act related"),
    ("disease-control", "疾病管理", "Disease Control"),
    ("notarization", "公證書驗證", "Notarial Certificate"),
    ("covid-19", "新型冠狀病毒", "COVID-19 Prevention"),
    ("other", "其他", "Other"),
    ("labor-exploitation", "勞動剝削", "Labor Exploitation"),
]
IDENTITIES = [
    ("foreign", "外國學生", "Foreign Student"),
    ("overseas-chinese", "僑生", "Overseas Chinese Student"),
    ("hong-kong-macao", "港澳生", "Students from Hong Kong and Macao"),
    ("mainland", "陸生", "Mainland Chinese Student"),
]
CAT_BY = {name: slug for slug, zh, en in CATEGORIES for name in (zh, en)}
ID_BY = {name: slug for slug, zh, en in IDENTITIES for name in (zh, en)}

zh = {x["sn"]: x for x in json.loads((SRC / "nisa_faq.json").read_text(encoding="utf-8"))}
en = {x["sn"]: x for x in json.loads((SRC / "nisa_faq_en.json").read_text(encoding="utf-8"))}


def identities(raw: str) -> list[str]:
    out = []
    for part in raw.replace("，", ",").split(","):
        part = part.strip()
        if part:
            out.append(ID_BY[part])  # KeyError = a new identity on the site: add it above
    return out


faqs = []
for sn in sorted(set(zh) | set(en), reverse=True):
    z, e = zh.get(sn), en.get(sn)
    base = z or e
    cat = CAT_BY[base["category"]]
    if z and e:
        assert CAT_BY[e["category"]] == cat, (sn, z["category"], e["category"])
    faqs.append(
        {
            "id": f"nisa-{sn}",
            "category": cat,
            "identities": identities(base["identity"]),
            "question_zh": z["question"] if z else "",
            "question_en": e["question"] if e else "",
            "answer_zh": z["answer"] if z else "",
            "answer_en": e["answer"] if e else "",
            "source_zh": z["source"] if z else "",
            "source_en": e["source"] if e else "",
            "agency_zh": z["agency"] if z else "",
            "agency_en": e["agency"] if e else "",
            "posted_on": base["date"],
            "url": base["url"],
        }
    )

used = {f["category"] for f in faqs}
data = {
    "accessed_at": __import__('datetime').datetime.now().astimezone().isoformat(timespec='seconds'),
    "source": {
        "title_zh": "大專校院境外學生輔導人員支援體系計畫（NISA）常見問答",
        "title_en": "NISA (Network for International Student Advisors) FAQ",
        "publisher_zh": "教育部 NISA 計畫辦公室",
        "publisher_en": "Ministry of Education NISA Office",
        "url": "https://www.nisa.moe.gov.tw/faq.new/index/menu_sn/13",
    },
    "categories": [
        {"id": slug, "zh": zh_, "en": en_} for slug, zh_, en_ in CATEGORIES if slug in used
    ],
    "identities": [{"id": slug, "zh": zh_, "en": en_} for slug, zh_, en_ in IDENTITIES],
    "faqs": faqs,
}
OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(len(faqs), "faqs;", len(data["categories"]), "categories;",
      sum(bool(f["question_zh"] and f["question_en"]) for f in faqs), "bilingual;",
      sum(not f["question_en"] for f in faqs), "zh only;", sum(not f["question_zh"] for f in faqs), "en only")
