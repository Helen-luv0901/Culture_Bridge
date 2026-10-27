"""Cuts a Chinese font down to the characters the app needs, so the site opens fast.

Run from flutter_app/: uv run --no-project --with fonttools python tool/subset_chinese_font.py [sans|serif]

sans (the app's font): Noto Sans TC from google/fonts,
  https://github.com/google/fonts/raw/main/ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf (12 MB), saved
  as tool/fonts/NotoSansTC-Variable.ttf. Its weight axis is cut to 400-700, the weights the app uses.
serif: Noto Serif TC (tool/fonts/, 16.9 MB), used by the earlier notebook look.

The full fonts are not shipped. The app gets a copy with the common Traditional Chinese
characters (Big5 level 1, about 5,400), punctuation, and every character in the app's own text
and official guides. Rarer characters in student posts are drawn by Flutter's automatic fallback
font. Run again after adding official content with rare characters.
"""

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

APP = Path(__file__).resolve().parents[1]
FONTS = {
    "sans": ("NotoSansTC-Variable.ttf", "NotoSansTC-Subset.ttf", (400, 700)),
    "serif": ("NotoSerifTC-Variable.ttf", "NotoSerifTC-Subset.ttf", None),
}
TEXT_FILES = [
    *sorted((APP / "lib").rglob("*.dart")),
    *sorted((APP / "assets" / "data").glob("*.json")),
    *sorted((APP.parent / "backend" / "app" / "content").glob("*.json")),
]
RANGES = [
    (0x20, 0x7E),  # ASCII
    (0xA0, 0xFF),  # Latin-1
    (0x2000, 0x206F),  # general punctuation (dashes, quotes, ellipsis)
    (0x3000, 0x303F),  # CJK punctuation
    (0x3100, 0x312F),  # bopomofo
    (0xFE30, 0xFE4F),  # CJK compatibility forms
    (0xFF00, 0xFFEF),  # full-width forms
]


def big5_level_one() -> set[str]:
    """Big5's frequently used characters: lead bytes 0xA4-0xC6."""
    found: set[str] = set()
    trails = [*range(0x40, 0x7F), *range(0xA1, 0xFF)]
    for lead in range(0xA4, 0xC7):
        for trail in trails:
            try:
                found.add(bytes([lead, trail]).decode("big5"))
            except UnicodeDecodeError:
                continue
    return found


def characters() -> set[str]:
    chars = big5_level_one()
    for start, end in RANGES:
        chars |= {chr(code) for code in range(start, end + 1)}
    for path in TEXT_FILES:
        chars |= set(path.read_text(encoding="utf-8"))
    return {c for c in chars if c.isprintable()}


def main() -> None:
    name = sys.argv[1] if len(sys.argv) > 1 else "sans"
    source_name, target_name, weights = FONTS[name]
    source = APP / "tool" / "fonts" / source_name
    target = APP / "assets" / "fonts" / target_name
    chars = characters()
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    font = TTFont(str(source))
    subsetter = subset.Subsetter(options)
    subsetter.populate(text="".join(sorted(chars)))
    subsetter.subset(font)
    if weights is not None:
        # After subsetting: fewer glyphs, and the axis cut keeps only what is left.
        font = instancer.instantiateVariableFont(font, {"wght": weights})
    subset.save_font(font, str(target), options)
    size = target.stat().st_size / 1_000_000
    print(f"{len(chars)} characters -> {target.relative_to(APP)} ({size:.1f} MB)")


if __name__ == "__main__":
    main()
