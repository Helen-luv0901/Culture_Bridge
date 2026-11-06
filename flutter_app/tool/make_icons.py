"""App icons from the team's official logo mark (purple on white).

    python tool/make_icons.py      (from flutter_app; needs Pillow)

Reads docs/brand/culture-bridge-mark-1024.png and writes the Android icons (legacy and the
Android 8+ adaptive layers), every iOS AppIcon size and docs/store/play-icon-512.png. The web
icons (web/icons, web/favicon.png) are not touched.
"""

import json
from pathlib import Path

from PIL import Image

app = Path(__file__).resolve().parent.parent  # flutter_app
mark_src = app.parent / "docs/brand/culture-bridge-mark-1024.png"
mark = Image.open(mark_src).convert("RGBA")
mark = mark.crop(mark.getbbox())  # just the drawing
WHITE = (255, 255, 255, 255)


def tile(size: int, fraction: float, background=WHITE) -> Image.Image:
    """The mark centred on a square, its wider side `fraction` of the square."""
    canvas = Image.new("RGBA", (size, size), background)
    scale = fraction * size / max(mark.size)
    w, h = round(mark.width * scale), round(mark.height * scale)
    art = mark.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(art, ((size - w) // 2, (size - h) // 2))
    return canvas


res = app / "android/app/src/main/res"
for folder, legacy, fg in [
    ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
]:
    # Older Android: a full square icon.
    tile(legacy, 0.78).convert("RGB").save(res / f"mipmap-{folder}/ic_launcher.png", optimize=True)
    # Android 8+: the launcher masks a 108dp layer to its own shape; the safe zone is the
    # middle 66dp circle, so the mark spans 58% of the layer.
    tile(fg, 0.58, (0, 0, 0, 0)).save(res / f"mipmap-{folder}/ic_launcher_foreground.png", optimize=True)

(res / "values/ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n',
    encoding="utf-8",
)

# iOS: opaque squares (Apple rounds the corners itself; no transparency allowed).
icons = app / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for image in json.loads((icons / "Contents.json").read_text(encoding="utf-8"))["images"]:
    side = float(image["size"].split("x")[0]) * int(image["scale"].rstrip("x"))
    tile(round(side), 0.76).convert("RGB").save(icons / image["filename"], optimize=True)

# Play Store listing icon (512, opaque).
tile(512, 0.76).convert("RGB").save(app.parent / "docs/store/play-icon-512.png", optimize=True)
print("icons written")
