"""Answers are shown as plain text; Markdown the model writes despite the prompt is taken out.

The prompt asks for plain text (prompts.py), but the backup models don't always listen: on
2026-11-05 gemini-3.1-flash-lite wrote "1. **首次申請外僑居留證**:" and the app showed the stars.
Only what is unambiguous Markdown goes: a ** (or ***) pair on one line that does not touch a
letter or digit outside it (so 2**3 stays), and heading markers at a line's start. Lists,
single asterisks, __names__ and #hashtags stay as written.
"""

import re

_BOLD = re.compile(
    r"(?<![A-Za-z0-9_*])\*\*\*?(?=[^\s*])([^\n*]+?)(?<=[^\s*])\*\*\*?(?![A-Za-z0-9_*])"
)
_HEADING = re.compile(r"^[ \t]{0,3}#{1,6}[ \t]+", re.MULTILINE)


def plain_text(text: str) -> str:
    without_bold = _BOLD.sub(r"\1", text)
    return _HEADING.sub("", without_bold)
