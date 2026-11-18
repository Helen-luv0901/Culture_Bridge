"""Scrape the MOE NISA FAQ (https://www.nisa.moe.gov.tw/faq.new/index/menu_sn/13) in one language.

    python scripts/nisa-faq/scrape.py <out_dir>          # Chinese -> <out_dir>/nisa_faq.json
    python scripts/nisa-faq/scrape.py <out_dir> en       # English -> <out_dir>/nisa_faq_en.json

Then merge both into the app content: python scripts/nisa-faq/merge.py <out_dir> backend/app/content/nisa_faq.json
Requests are spaced out (~0.5 s) to stay gentle on the site. Standard library only.
"""

import csv, html, json, re, sys, time, urllib.request, http.cookiejar

BASE = "https://www.nisa.moe.gov.tw"
OUT = sys.argv[1]
UA = {"User-Agent": "Mozilla/5.0 (FAQ archiver)"}
LANG = sys.argv[2] if len(sys.argv) > 2 else "zh_TW"
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def get(url):
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers=UA)
            return OPENER.open(req, timeout=30).read().decode("utf-8", "replace")
        except Exception as e:
            print("retry", url, e, file=sys.stderr)
            time.sleep(2 + i * 3)
    raise RuntimeError(url)


def text(fragment):
    fragment = re.sub(r"<br\s*/?>|</p>|</li>|</div>|</tr>", "\n", fragment, flags=re.I)
    fragment = re.sub(r"<li[^>]*>", "• ", fragment, flags=re.I)
    t = html.unescape(re.sub(r"<[^>]+>", "", fragment)).replace("\xa0", " ")
    lines = [re.sub(r"[ \t]+", " ", l).strip() for l in t.split("\n")]
    return "\n".join(l for l in lines if l)


ALIAS = {"Respond": "答覆", "Files": "相關檔案", "Resource": "資料來源", "Responding Unit": "回復機關", "Posted": "發布日期", "Viewed": "點閱次數"}

row_re = re.compile(
    r'<tr>\s*<td class="text-secondary">(.*?)</td>\s*<td class="mobile-hide text-secondary">(.*?)</td>\s*'
    r'<td><a href="(/faq\.new/view/sn/(\d+)/menu_sn/13)"\s*title="(.*?)">.*?</a></td>\s*'
    r'<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>', re.S)

get(f"{BASE}/default/counselor?pt=6")
print(get(f"{BASE}/counselor/ajax.lang/lang/{LANG}"), file=sys.stderr)
items, seen, page = [], set(), 1
while True:
    url = f"{BASE}/default/faq.new/index/menu_sn/13/page/{page}"
    rows = row_re.findall(get(url))
    new = [r for r in rows if r[3] not in seen]
    if not new:
        break
    for cat, ident, path, sn, q, date, views in new:
        seen.add(sn)
        items.append({"sn": int(sn), "category": text(cat), "identity": text(ident),
                      "question": html.unescape(q).strip(), "date": text(date),
                      "url": BASE + path})
    print(f"page {page}: {len(new)} items (total {len(items)})", file=sys.stderr)
    page += 1
    time.sleep(0.5)

# The English list leaves out many questions whose own page does have an English version
# (2026-11-19: 104 listed, 126 with English). So in English mode every Chinese question's page
# is opened too; one without an English version shows the Chinese text and is skipped below.
english = LANG != "zh_TW"
if english:
    try:
        with open(f"{OUT}/nisa_faq.json", encoding="utf-8") as f:
            chinese = json.load(f)
    except FileNotFoundError:
        sys.exit("Scrape the Chinese version first: it lists the questions to open in English.")
    for z in chinese:
        if str(z["sn"]) not in seen:
            seen.add(str(z["sn"]))
            items.append({k: z[k] for k in ("sn", "category", "identity", "date", "url")} | {"question": ""})

for n, it in enumerate(items, 1):
    s = get(it["url"])
    fields = dict()
    labels = set()
    for label, val in re.findall(r"<tr>\s*<td>\s*(.*?)\s*</td>\s*<td>(.*?)</td>\s*</tr>", s, re.S):
        labels.add(text(label))
        fields[ALIAS.get(text(label), text(label))] = val
    it["has_version"] = not english or "Respond" in labels  # Chinese labels = no English version
    heading = re.search(r"<h4>(.*?)</h4>", s, re.S)
    if english and heading and it["has_version"]:
        it["question"] = text(heading.group(1))
    it["answer"] = text(fields.get("答覆", ""))
    files = re.findall(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>', fields.get("相關檔案", ""), re.S)
    it["files"] = [{"name": text(nm), "url": (BASE + h if h.startswith("/") else h)} for h, nm in files]
    it["source"] = text(fields.get("資料來源", ""))
    it["agency"] = text(fields.get("回復機關", ""))
    it["views"] = text(fields.get("點閱次數", ""))
    if n % 20 == 0:
        print(f"detail {n}/{len(items)}", file=sys.stderr)
    time.sleep(0.4)

items = [it for it in items if it.pop("has_version") and it["question"] and it["answer"]]
SUF = "" if LANG == "zh_TW" else "_" + LANG
with open(f"{OUT}/nisa_faq{SUF}.json", "w", encoding="utf-8") as f:
    json.dump(items, f, ensure_ascii=False, indent=2)
with open(f"{OUT}/nisa_faq{SUF}.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["sn", "問題分類", "身份別", "問題", "答覆", "資料來源", "回復機關", "發布日期", "點閱次數", "相關檔案", "網址"])
    for it in items:
        w.writerow([it["sn"], it["category"], it["identity"], it["question"], it["answer"], it["source"],
                    it["agency"], it["date"], it["views"], " ; ".join(x["url"] for x in it["files"]), it["url"]])
with open(f"{OUT}/nisa_faq{SUF}.md", "w", encoding="utf-8") as f:
    f.write(f"# NISA 常見問答（共 {len(items)} 題）\n\n來源：{BASE}/faq.new/index/menu_sn/13\n\n")
    for it in items:
        f.write(f"## {it['question']}\n\n- 分類：{it['category']}｜身份別：{it['identity']}｜回復機關：{it['agency']}｜日期：{it['date']}\n- 連結：{it['url']}\n\n{it['answer']}\n\n")
        for x in it["files"]:
            f.write(f"- 附件：[{x['name']}]({x['url']})\n")
        f.write("\n")
print("done", len(items), file=sys.stderr)
