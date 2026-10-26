"""Keyword ranking shared by the Explore search and the assistant's search tools.

A query becomes match units: CJK runs are cut into bigrams (Chinese has no spaces, so
「工作證怎麼辦」 must still match 「工作證」) and Latin words into stems, with question words
dropped. Each document is a (heading, body) pair; heading hits count double, so the document
*about* a topic beats ones that only mention it.
"""

import re

_CJK = re.compile(r"[㐀-鿿豈-﫿]")

# Question words carry no topic, so they must not make every document "match".
_STOPWORDS = frozenset(
    "a an and are can do does for how i in is it me mean my of on the to what where why you".split()
)
_CJK_FILLER = set("的了嗎呢吧什麼怎哪我你他她是要")

# A result must score at least this share of the best one: a guide that only mentions a word
# in one step should not fill the list next to the guide that is about it. Body-only matches
# score at most 1 and a full title match at least 2, so above half keeps them apart.
RELEVANCE_SHARE = 0.6

# Every result needs this much on its own, or a lone post that says 學生 once would be the
# "best" match for 「學生證」: some of the words in the title, or most of them in the body.
MIN_SCORE = 0.6


def search_units(query: str) -> list[str]:
    """Query -> match units. CJK runs become bigrams so 「工作證怎麼辦」 still matches 「工作證」;
    Latin words are cut to a stem so "sharing" matches "share" and "anonymously" "anonymous"."""
    units: list[str] = []
    for token in re.findall(r"[a-z0-9]+|[^\sa-z0-9]+", query.lower()):
        if not re.search(r"\w", token):
            continue  # punctuation alone ("?", "！") is not something to match
        if _CJK.search(token):
            token = re.sub(r"\W", "", token)  # 「處理？」 -> 「處理」
            if len(token) <= 2:
                units.append(token)
                continue
            bigrams = (token[i : i + 2] for i in range(len(token) - 1))
            units.extend(b for b in bigrams if not _CJK_FILLER.intersection(b))
        elif token not in _STOPWORDS:
            units.append(token if len(token) <= 4 else token[: max(4, len(token) - 3)])
    return units


def _matches(unit: str, haystack: str) -> bool:
    if _CJK.search(unit):
        return unit in haystack
    return re.search(rf"\b{re.escape(unit)}", haystack) is not None


def score(units: list[str], haystack: str) -> float:
    if not units:
        return 1.0
    return sum(1 for unit in units if _matches(unit, haystack)) / len(units)


def _scored[T](items: list[tuple[T, str, str]], units: list[str]) -> list[tuple[T, float]]:
    scored = [(item, 2 * score(units, head) + score(units, body)) for item, head, body in items]
    scored = [pair for pair in scored if pair[1] > 0]
    scored.sort(key=lambda pair: pair[1], reverse=True)
    return scored


def rank[T](items: list[tuple[T, str, str]], query: str, limit: int) -> list[T]:
    """Rank (item, heading, body) triples, best first. An empty query keeps every item."""
    return [item for item, _ in _scored(items, search_units(query))[:limit]]


def relevant[T](items: list[tuple[T, str, str]], query: str, limit: int) -> list[T]:
    """Like rank, for people searching: a query with nothing to match finds nothing, and
    weak results, or ones far weaker than the best, are left out."""
    units = search_units(query)
    if not units:
        return []
    scored = _scored(items, units)
    if not scored:
        return []
    floor = max(scored[0][1] * RELEVANCE_SHARE, MIN_SCORE)
    return [item for item, value in scored if value >= floor][:limit]
