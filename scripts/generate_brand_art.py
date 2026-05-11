"""Generate Clothedd app icon + launch image in a bold pop-art style.

Run from repo root:
    python3 scripts/generate_brand_art.py

Design notes:
- Full-bleed orange (Warhol-pop), not pink. Gender-neutral, warm, energetic.
- Big white t-shirt silhouette with thick black outline (Lichtenstein-style).
- A few cobalt blue halftone dots on one shoulder for pop-art shading
  (echoes the app's existing PopArtHalftoneBackground in cobalt).
- No internal frame, no text in the icon (iOS shows the app name beneath).
- Launch image: same color field + chunky comic-style wordmark with the
  t-shirt motif above it.
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT / "20260312v2clothingfrontend" / "Fonts"
ASSETS = ROOT / "20260312v2clothingfrontend" / "Assets.xcassets"

# Palette
ORANGE = (255, 106, 26)          # Warhol pop orange
ORANGE_DARK = (191, 64, 8)       # for dark-mode icon background
COBALT = (36, 71, 184)           # echoes appPopArtBlue
BLACK = (15, 15, 18)
WHITE = (255, 255, 255)
INK = (28, 28, 32)


def tshirt_polygon(cx: float, cy: float, w: float, h: float) -> list[tuple[float, float]]:
    """Symmetric pop-art t-shirt outline centered at (cx, cy), sized w×h.

    Coordinates are absolute pixels. Includes a V-ish neckline notch.
    """
    x0 = cx - w / 2
    y0 = cy - h / 2

    def p(nx: float, ny: float) -> tuple[float, float]:
        return (x0 + nx * w, y0 + ny * h)

    return [
        p(0.34, 0.08),  # left shoulder top
        p(0.44, 0.08),  # neckline left edge
        p(0.47, 0.17),  # neckline dip-left
        p(0.50, 0.20),  # neckline bottom
        p(0.53, 0.17),  # neckline dip-right
        p(0.56, 0.08),  # neckline right edge
        p(0.66, 0.08),  # right shoulder top
        p(0.90, 0.20),  # right sleeve top-outer
        p(0.96, 0.40),  # right sleeve bottom-outer
        p(0.78, 0.46),  # right armpit
        p(0.76, 0.96),  # body bottom-right
        p(0.24, 0.96),  # body bottom-left
        p(0.22, 0.46),  # left armpit
        p(0.04, 0.40),  # left sleeve bottom-outer
        p(0.10, 0.20),  # left sleeve top-outer
    ]


def draw_tshirt(img: Image.Image, cx: float, cy: float, w: float, h: float,
                fill=WHITE, stroke=BLACK, stroke_width: int = 28,
                shadow_offset: int = 0, shadow_color=BLACK,
                accent_dots: bool = True) -> None:
    """Draw a t-shirt onto img with optional offset drop shadow + halftone accent."""
    draw = ImageDraw.Draw(img)

    if shadow_offset > 0:
        shadow_poly = [(x + shadow_offset, y + shadow_offset)
                       for (x, y) in tshirt_polygon(cx, cy, w, h)]
        draw.polygon(shadow_poly, fill=shadow_color)

    poly = tshirt_polygon(cx, cy, w, h)
    # Fill then stroke (PIL's polygon outline is 1px; we draw a thick polyline manually).
    draw.polygon(poly, fill=fill)
    closed = poly + [poly[0]]
    for i in range(len(closed) - 1):
        draw.line([closed[i], closed[i + 1]], fill=stroke,
                  width=stroke_width, joint="curve")
    # Smooth the corners with stroke-radius circles.
    r = stroke_width // 2
    for (x, y) in poly:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=stroke)

    if accent_dots:
        # Ben-Day dots on the left chest area, clipped to the t-shirt outline.
        dots_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        dd = ImageDraw.Draw(dots_layer)
        step = int(w * 0.075)
        dot = int(w * 0.038)
        x_start = cx - w * 0.34
        x_end = cx - w * 0.04
        y_start = cy - h * 0.16
        y_end = cy + h * 0.18
        row = 0
        y = y_start
        while y < y_end:
            x = x_start + (step // 2 if row % 2 else 0)
            while x < x_end:
                dd.ellipse((x, y, x + dot, y + dot), fill=COBALT + (255,))
                x += step
            y += step
            row += 1

        # Clip the dots to the t-shirt polygon by multiplying alpha channels.
        poly_mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(poly_mask).polygon(poly, fill=255)
        dots_alpha = dots_layer.split()[3]
        dots_layer.putalpha(ImageChops.multiply(dots_alpha, poly_mask))
        img.alpha_composite(dots_layer)


def background_burst(size: int, base_color, accent_color, alpha: int = 32) -> Image.Image:
    """Subtle radiating Ben-Day dot field across the whole canvas — keeps the
    icon from feeling totally flat without competing with the t-shirt."""
    img = Image.new("RGB", (size, size), base_color)
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    step = int(size * 0.046)
    dot = int(size * 0.014)
    row = 0
    y = step // 2
    while y < size + step:
        x = step // 2 + (step // 2 if row % 2 else 0)
        while x < size + step:
            draw.ellipse((x, y, x + dot, y + dot),
                         fill=(accent_color[0], accent_color[1], accent_color[2], alpha))
            x += step
        y += step
        row += 1
    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


def make_icon(size: int = 1024, bg=ORANGE, accent=BLACK) -> Image.Image:
    img = background_burst(size, base_color=bg, accent_color=accent, alpha=32)

    # Centered t-shirt occupying ~70% of the canvas. iOS masks corners
    # at ~22%, so keep all content well inside the safe square.
    cx = size / 2
    cy = size / 2 + size * 0.02  # nudge down a hair for optical balance
    shirt_w = size * 0.74
    shirt_h = size * 0.78
    stroke_w = max(int(size * 0.045), 6)
    shadow_off = int(size * 0.022)

    img = img.convert("RGBA")
    draw_tshirt(img, cx, cy, shirt_w, shirt_h,
                fill=WHITE, stroke=BLACK, stroke_width=stroke_w,
                shadow_offset=shadow_off, shadow_color=BLACK,
                accent_dots=True)
    return img.convert("RGB")


def make_icon_dark(size: int = 1024) -> Image.Image:
    return make_icon(size, bg=ORANGE_DARK, accent=WHITE)


def make_icon_tinted(size: int = 1024) -> Image.Image:
    """Grayscale form for the iOS tinted-icon mode. System will recolor."""
    # Black field + white t-shirt — system tints the lighter parts.
    img = Image.new("RGB", (size, size), INK)
    cx = size / 2
    cy = size / 2 + size * 0.02
    shirt_w = size * 0.74
    shirt_h = size * 0.78
    stroke_w = max(int(size * 0.045), 6)
    img = img.convert("RGBA")
    draw_tshirt(img, cx, cy, shirt_w, shirt_h,
                fill=(220, 220, 220), stroke=INK, stroke_width=stroke_w,
                shadow_offset=0, accent_dots=False)
    return img.convert("RGB")


def make_launch_wordmark(scale: int = 3) -> Image.Image:
    """Transparent-bg wordmark + small t-shirt sized for iOS launch centering.

    iOS centers a UILaunchScreen UIImageName at native point size, so this is
    sized in *points*. Target ~300×180 pt: shirt above wordmark.
    """
    target_w_pt = 300
    target_h_pt = 200
    width = target_w_pt * scale
    height = target_h_pt * scale

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    # Small t-shirt at the top.
    shirt_w = width * 0.38
    shirt_h = shirt_w * 1.05
    shirt_cx = width / 2
    shirt_cy = shirt_h / 2 + height * 0.02
    shirt_stroke = max(int(shirt_w * 0.06), 4)
    draw_tshirt(img, shirt_cx, shirt_cy, shirt_w, shirt_h,
                fill=WHITE, stroke=BLACK, stroke_width=shirt_stroke,
                shadow_offset=int(shirt_w * 0.04), accent_dots=False)

    # Bold sans wordmark — Montserrat Black, white-fill black-outline (pop lettering).
    font_path = FONTS / "Montserrat-Variable.ttf"
    font_size = int(height * 0.26)
    font = ImageFont.truetype(str(font_path), font_size)
    text = "Clothedd"
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font, stroke_width=int(font_size * 0.10))
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    tx = (width - text_w) // 2 - bbox[0]
    ty = int(height * 0.62) - bbox[1]
    draw.text((tx, ty), text, font=font, fill=WHITE,
              stroke_width=int(font_size * 0.10), stroke_fill=BLACK)

    return img


def write_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"wrote {path.relative_to(ROOT)} ({img.size[0]}x{img.size[1]})")


def main() -> None:
    light = make_icon(1024)
    dark = make_icon_dark(1024)
    tinted = make_icon_tinted(1024)

    write_png(light, ASSETS / "AppIcon.appiconset" / "AppIcon-1024.png")
    write_png(dark, ASSETS / "AppIcon.appiconset" / "AppIcon-1024-dark.png")
    write_png(tinted, ASSETS / "AppIcon.appiconset" / "AppIcon-1024-tinted.png")

    for px in (16, 32, 128, 256, 512):
        for scale, suffix in ((1, ""), (2, "@2x")):
            target = px * scale
            resized = light.resize((target, target), Image.LANCZOS)
            write_png(resized, ASSETS / "AppIcon.appiconset" / f"mac-{px}{suffix}.png")

    for scale, suffix in ((1, "@1x"), (2, "@2x"), (3, "@3x")):
        wm = make_launch_wordmark(scale=scale)
        write_png(wm, ASSETS / "LaunchLogo.imageset" / f"LaunchLogo{suffix}.png")


if __name__ == "__main__":
    main()
