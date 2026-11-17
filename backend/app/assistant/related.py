"""Which official questions and student posts appear as cards under an answer.

The model judges relevance, not a search score: short posts often look "close" to unrelated
questions by wording or meaning alone. It ends its answer with one line naming what directly
helps, e.g. ``RELATED: faq:nisa-1070, post:3f2a…`` or ``RELATED: none``. That line is removed
from the text the user sees. Every id is checked against real data, at most two of each kind are
shown, and an answer without the line shows no student posts.
"""

import re
from dataclasses import dataclass

from app.assistant.tools import ToolContext, experience_card, faq_card

MAX_EACH = 2
_LINE = re.compile(r"^[ \t]*RELATED[ \t]*[:：][^\n]*$", re.IGNORECASE | re.MULTILINE)
_ITEM = re.compile(r"\b(faq|post)\s*:\s*([A-Za-z0-9_-]+)", re.IGNORECASE)


@dataclass(frozen=True)
class Related:
    text: str  # the answer without the RELATED line
    listed: bool  # whether the model wrote the line at all
    faqs: tuple[str, ...] = ()
    posts: tuple[str, ...] = ()


def parse_related(answer: str) -> Related:
    lines = _LINE.findall(answer)
    text = _LINE.sub("", answer).strip()
    if not lines:
        return Related(text=text, listed=False)
    faqs: list[str] = []
    posts: list[str] = []
    for kind, item_id in _ITEM.findall(" ".join(lines)):
        target = faqs if kind.lower() == "faq" else posts
        if item_id not in target:
            target.append(item_id)
    return Related(text=text, listed=True, faqs=tuple(faqs), posts=tuple(posts))


def related_cards(related: Related, ctx: ToolContext) -> None:
    """Replace the cards with the questions and posts the model listed (checked to exist).

    Without the line, question cards already earned by quoting or opening a question stay, and
    no student posts are shown: an unrelated post is worse than none.
    """
    if not related.listed:
        for key in [k for k in ctx.cards if k.startswith("experience:")]:
            del ctx.cards[key]
        return
    named = {k: v for k, v in ctx.cards.items() if k.startswith("faq:")}
    ctx.cards.clear()
    for faq_id in related.faqs[:MAX_EACH]:
        faq = ctx.data.get_faq(faq_id)
        if faq is not None:
            ctx.cards[f"faq:{faq.id}"] = faq_card(faq, ctx.locale)
    # A question the answer quotes is relevant even if the model forgot to list it.
    for key, card in named.items():
        if key[len("faq:") :] in related.faqs or _named_in(card.question, related.text):
            ctx.cards.setdefault(key, card)
    for post_id in related.posts[:MAX_EACH]:
        post = ctx.data.get_experience(post_id)
        if post is not None:
            ctx.cards[f"experience:{post.id}"] = experience_card(post, ctx.locale)


def _named_in(title: str, text: str) -> bool:
    return bool(title) and title in text
