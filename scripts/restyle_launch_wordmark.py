"""Re-typeset the launch screen wordmark in Montserrat Black — nothing else.

Keeps the existing hoodie artwork and the orange `LaunchBackground` exactly as
they are; only the "Clothedd" wordmark below the hoodie is re-rendered in
Montserrat Black (wght 900 — the same weight `UIFont.appDisplay` uses for every
nav title and tab label), so the launch screen matches the app's own headers.

The source hoodie is the top portion of the current LaunchLogo@3x; the wordmark
sits in the transparent band beneath it. Idempotent: re-running reads the hoodie
(rows above HOODIE_CUT) and redraws only the text below it.

Run from repo root:
    python3 scripts/restyle_launch_wordmark.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = ROOT / "20260312v2clothingfrontend" / "Fonts" / "Montserrat-Variable.ttf"
IMGSET = ROOT / "20260312v2clothingfrontend" / "Assets.xcassets" / "LaunchLogo.imageset"
SRC_3X = IMGSET / "LaunchLogo@3x.png"

TEXT = "Clothedd"
INK = (33, 33, 33, 255)        # matches the existing wordmark ink + the hoodie outline
HOODIE_CUT = 557               # rows 0..556 of the @3x art are the hoodie (transparent gap 547-561)
TEXT_CENTER = (300, 595)       # @3x canvas is 600x635; old wordmark occupied rows ~562..627
MAX_W, MAX_H = 520, 66         # fit box for the wordmark on the @3x canvas

# (filename, width, height) for each scale — matches the existing imageset exactly.
SCALES = [
    ("LaunchLogo@3x.png", 600, 635),
    ("LaunchLogo@2x.png", 400, 424),
    ("LaunchLogo@1x.png", 200, 211),
]


def montserrat_black(size: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(FONT_PATH), size)
    try:
        font.set_variation_by_axes([900])           # Weight axis → Black
    except Exception:
        try:
            font.set_variation_by_name("Black")
        except Exception:
            pass
    return font


def fit_font(text: str, max_w: int, max_h: int) -> ImageFont.FreeTypeFont:
    """Largest Montserrat Black that fits the wordmark inside (max_w, max_h)."""
    probe = montserrat_black(100)
    l, t, r, b = ImageDraw.Draw(Image.new("RGBA", (1, 1))).textbbox((0, 0), text, font=probe)
    scale = min(max_w / (r - l), max_h / (b - t))
    return montserrat_black(max(int(100 * scale), 8))


def render_wordmark(canvas: Image.Image) -> None:
    font = fit_font(TEXT, MAX_W, MAX_H)
    draw = ImageDraw.Draw(canvas)
    l, t, r, b = draw.textbbox((0, 0), TEXT, font=font)
    tw, th = r - l, b - t
    glyphs = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ImageDraw.Draw(glyphs).text((-l, -t), TEXT, font=font, fill=INK)
    cx, cy = TEXT_CENTER
    canvas.alpha_composite(glyphs, (cx - tw // 2, cy - th // 2))


def main() -> None:
    src = Image.open(SRC_3X).convert("RGBA")
    w, h = src.size

    # Fresh transparent canvas + the hoodie pixels, untouched.
    art = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    art.alpha_composite(src.crop((0, 0, w, HOODIE_CUT)), (0, 0))

    render_wordmark(art)

    for name, sw, sh in SCALES:
        out = art if (sw, sh) == (w, h) else art.resize((sw, sh), Image.LANCZOS)
        path = IMGSET / name
        out.save(path, "PNG", optimize=True)
        print(f"wrote {path.relative_to(ROOT)} ({sw}x{sh})")


if __name__ == "__main__":
    main()
