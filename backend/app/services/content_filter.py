"""A small keyword filter for what people publish (store rule: objectionable content is filtered).

Checked on post titles, text and tags, comments, nicknames and real names; a match refuses the
whole write with 422 content_not_allowed and nothing is stored. Reports and blocks remain the
main tool: this list only catches the plainest slurs, sexual insults and threats, and is kept
short on purpose so ordinary student posts (renting, ARC, night markets, 機車, 吃辣) never trip it.

Matching is case-insensitive after NFKC normalisation (full-width letters count as ASCII).
English entries match whole words only (so "Scunthorpe" and "assessment" pass), also right next
to Chinese characters ("他說fuck"). Chinese entries match anywhere in the text, so they are
phrases rather than single characters (幹 alone is also 能幹 and 幹部).
"""

import re
import unicodedata

from app.core.errors import ApiError

# Whole words. Plurals and -ing forms are listed where they are common.
_ENGLISH = (
    # sexual insults and explicit terms
    "fuck",
    "fucks",
    "fucked",
    "fucker",
    "fuckers",
    "fucking",
    "motherfucker",
    "motherfuckers",
    "cunt",
    "cunts",
    "slut",
    "sluts",
    "whore",
    "whores",
    "blowjob",
    # slurs
    "nigger",
    "niggers",
    "nigga",
    "niggas",
    "faggot",
    "faggots",
    "fag",
    "fags",
    "retard",
    "retards",
    "chink",
    "chinks",
    "spic",
    "spics",
    "tranny",
    # threats and self-harm baiting
    "kill yourself",
    "kys",
    "i will kill you",
    "i'll kill you",
)

# Substrings (Traditional and Simplified forms where they differ).
_CHINESE = (
    # sexual insults and explicit terms
    "幹你娘",
    "干你娘",
    "操你媽",
    "操你妈",
    "肏",
    "屄",
    "雞掰",
    "機掰",
    "鸡掰",
    "雞巴",
    "鸡巴",
    "婊子",
    "賤貨",
    "贱货",
    "約砲",
    "约炮",
    "强奸",
    "輪姦",
    "轮奸",
    # slurs
    "黑鬼",
    "支那豬",
    "支那猪",
    "死娘炮",
    "外勞滾",
    # threats and self-harm baiting
    "杀了你",
    "砍死你",
    "去死吧",
    "你去死",
)


# Invisible characters people slip into a word to get past a filter.
_INVISIBLE = dict.fromkeys(map(ord, "\u00ad\u200b\u200c\u200d\u2060\ufeff"))


def _normalise(text: str) -> str:
    plain = unicodedata.normalize("NFKC", text).translate(_INVISIBLE)
    # Curly apostrophes count as straight ones ("I’ll").
    return plain.replace("\u2019", "'").replace("\u2018", "'").casefold()


_WORDS = re.compile(
    r"(?<![a-z0-9])(?:"
    + "|".join(re.escape(w).replace(r"\ ", r"\s+") for w in sorted(_ENGLISH, key=len, reverse=True))
    + r")(?![a-z0-9])",
)
_PHRASES = tuple(_normalise(p) for p in _CHINESE)


def contains_blocked_words(text: str | None) -> bool:
    if not text:
        return False
    normal = _normalise(text)
    # Chinese phrases also match with spaces between the characters (幹 你 娘).
    joined = re.sub(r"\s+", "", normal)
    return bool(_WORDS.search(normal)) or any(p in joined for p in _PHRASES)


def check(*texts: str | None) -> None:
    """Refuse the write if any of the texts contains a blocked word."""
    if any(contains_blocked_words(t) for t in texts):
        raise ApiError(422, "content_not_allowed")
