"""Draws the Culture Bridge app icon and writes every size the web, Android and iOS builds use.

Run from flutter_app/: python3 tool/make_icons.py   (needs Pillow)
Colours come from Palette in lib/ui/core/design_system.dart. Everything is drawn inside the
central 80% circle so the same art works as a maskable/adaptive icon.
"""

from pathlib import Path

from PIL import Image, ImageDraw

PAPER = "#F4EEE0"
MOSS = "#4C5540"
BRICK = "#9E5B4A"
SLATE = "#AEBBBB"

S = 2048  # drawing size; downsampled for smooth edges


def art(background: str | None = PAPER) -> Image.Image:
    img = Image.new("RGBA" if background is None else "RGB", (S, S), background or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 1024

    def box(x0, y0, x1, y1):
        return [x0 * u, y0 * u, x1 * u, y1 * u]

    # Sun rising behind the bridge.
    d.ellipse(box(412, 230, 612, 430), fill=BRICK)
    # Arch whose crown meets the deck; its feet stay inside the maskable safe zone.
    d.arc(box(262, 600, 762, 1040), start=180, end=360, fill=MOSS, width=int(56 * u))
    # Hangers from the deck down to the arch.
    for x, bottom in [(322, 697), (382, 652), (642, 652), (702, 697)]:
        d.rectangle(box(x - 11, 590, x + 11, bottom), fill=MOSS)
    # Deck.
    d.rounded_rectangle(box(182, 544, 842, 600), radius=12 * u, fill=MOSS)
    # Water.
    for y, x0, x1 in [(840, 300, 724), (890, 380, 644)]:
        d.rounded_rectangle(box(x0, y, x1, y + 22), radius=11 * u, fill=SLATE)
    return img


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    big = art()

    def save(size: int, path: str) -> None:
        out = root / path
        out.parent.mkdir(parents=True, exist_ok=True)
        big.resize((size, size), Image.LANCZOS).save(out, optimize=True)

    for name in ["Icon", "Icon-maskable"]:
        save(192, f"web/icons/{name}-192.png")
        save(512, f"web/icons/{name}-512.png")
    save(32, "web/favicon.png")
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(size, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
    ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for icon in (root / ios).glob("Icon-App-*.png"):
        save(Image.open(icon).width, f"{ios}/{icon.name}")
    save(512, "../docs/store/play-icon-512.png")  # Play listing icon: 512x512, no transparency

    # Android 8+ adaptive icon: 108dp layers, only the central 66dp circle is always visible.
    # The art fills an 80% circle, so it is drawn at 108 * 0.61 / 0.8 ≈ 82dp, centred.
    fg = art(background=None)
    for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        size = round(108 * scale)
        inner = round(82 * scale)
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        offset = (size - inner) // 2
        layer.alpha_composite(fg.resize((inner, inner), Image.LANCZOS), (offset, offset))
        layer.save(root / f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png")
    res = root / "android/app/src/main/res"
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{PAPER}</color>\n'
        "</resources>\n"
    )


if __name__ == "__main__":
    main()
