"""Which guides and student posts appear as cards under an answer.

The model judges relevance, not a search score: short posts often look "close" to unrelated
questions by wording or meaning alone. It ends its answer with one line naming what directly
helps, e.g. ``RELATED: action:arc-first, post:3f2a…`` or ``RELATED: none``. That line is
removed from the text the user sees. Every id is checked against real data, at most two of each
kind are shown, and an answer without the line shows no student posts.
"""

import re
from dataclasses import dataclass

from app.assistant.tools import ToolContext, _action_card, experience_card

MAX_EACH = 2
_LINE = re.compile(r"^[ \t]*RELATED[ \t]*[:：][^\n]*$", re.IGNORECASE | re.MULTILINE)
_ITEM = re.compile(r"\b(action|post)\s*:\s*([A-Za-z0-9_-]+)", re.IGNORECASE)


@dataclass(frozen=True)
class Related:
    text: str  # the answer without the RELATED line
    listed: bool  # whether the model wrote the line at all
    actions: tuple[str, ...] = ()
    posts: tuple[str, ...] = ()


def parse_related(answer: str) -> Related:
    lines = _LINE.findall(answer)
    text = _LINE.sub("", answer).strip()
    if not lines:
        return Related(text=text, listed=False)
    actions: list[str] = []
    posts: list[str] = []
    for kind, item_id in _ITEM.findall(" ".join(lines)):
        target = actions if kind.lower() == "action" else posts
        if item_id not in target:
            target.append(item_id)
    return Related(text=text, listed=True, actions=tuple(actions), posts=tuple(posts))


def related_cards(related: Related, ctx: ToolContext) -> None:
    """Replace the cards with the guides and posts the model listed (checked to exist).

    Without the line, guide cards already earned by naming or opening a guide stay, and no
    student posts are shown: an unrelated post is worse than none.
    """
    if not related.listed:
        for key in [k for k in ctx.cards if k.startswith("experience:")]:
            del ctx.cards[key]
        return
    named = {k: v for k, v in ctx.cards.items() if k.startswith("action:")}
    ctx.cards.clear()
    for action_id in related.actions[:MAX_EACH]:
        action = ctx.data.get_action(action_id)
        if action is not None:
            ctx.cards[f"action:{action.id}"] = _action_card(action, ctx.locale)
    # A guide the answer names is relevant even if the model forgot to list it.
    for key, card in named.items():
        if key[len("action:") :] in related.actions or _named_in(card.title, related.text):
            ctx.cards.setdefault(key, card)
    for post_id in related.posts[:MAX_EACH]:
        post = ctx.data.get_experience(post_id)
        if post is not None:
            ctx.cards[f"experience:{post.id}"] = experience_card(post, ctx.locale)


def _named_in(title: str, text: str) -> bool:
    return bool(title) and title in text
