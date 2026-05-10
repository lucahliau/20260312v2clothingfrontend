"""Generate Clothedd app icon + launch image in the app's pop-art style.

Run from repo root:
    python3 scripts/generate_brand_art.py
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT / "20260312v2clothingfrontend" / "Fonts"
ASSETS = ROOT / "20260312v2clothingfrontend" / "Assets.xcassets"

PINK = (255, 46, 158)            # appNeonPink
BLUE = (36, 71, 184)             # appPopArtBlue
CYAN = (51, 242, 255)
MAGENTA = (217, 38, 242)
BLACK = (15, 15, 18)
WHITE = (255, 255, 255)


def halftone_layer(size: int, step: int, dot: int, palette, alpha: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    row = 0
    y = step // 2
    while y < size + step:
        col = 0
        x = step // 2 + (step // 2 if row % 2 else 0)
        while x < size + step:
            c = palette[(row + col) % len(palette)]
            draw.ellipse((x, y, x + dot, y + dot), fill=(c[0], c[1], c[2], alpha))
            x += step
            col += 1
        y += step
        row += 1
    return layer


def make_icon(size: int = 1024) -> Image.Image:
    img = Image.new("RGB", (size, size), PINK)

    # Ben-Day halftone overlay (subtle, on-brand)
    dots = halftone_layer(size, step=int(size * 0.052), dot=int(size * 0.022),
                          palette=[CYAN, WHITE, MAGENTA, BLUE], alpha=85)
    img = Image.alpha_composite(img.convert("RGBA"), dots)

    # Pop-art panel: black drop-shadow + white card + thick black stroke
    panel_w = int(size * 0.68)
    panel_h = int(size * 0.68)
    panel_x = (size - panel_w) // 2
    panel_y = (size - panel_h) // 2
    shadow_offset = int(size * 0.032)
    radius = int(size * 0.08)
    stroke = max(int(size * 0.018), 4)

    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle(
        (panel_x + shadow_offset, panel_y + shadow_offset,
         panel_x + panel_w + shadow_offset, panel_y + panel_h + shadow_offset),
        radius=radius, fill=BLACK
    )
    od.rounded_rectangle(
        (panel_x, panel_y, panel_x + panel_w, panel_y + panel_h),
        radius=radius, fill=WHITE, outline=BLACK, width=stroke
    )
    img = Image.alpha_composite(img, overlay)

    # Bodoni Moda 'C' centered inside the panel.
    font_path = FONTS / "BodoniModa-Variable.ttf"
    # PIL doesn't fully expose variable-axis selection; the file's default
    # instance renders heavy enough at this size. Pick size empirically.
    font_size = int(panel_h * 0.92)
    font = ImageFont.truetype(str(font_path), font_size)

    draw = ImageDraw.Draw(img)
    text = "C"
    # Use the font's actual bounding box for tight centering.
    bbox = font.getbbox(text)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    tx = panel_x + (panel_w - text_w) // 2 - bbox[0]
    ty = panel_y + (panel_h - text_h) // 2 - bbox[1]
    draw.text((tx, ty), text, font=font, fill=BLACK)

    # Tiny accent pink dot inside the C's negative space for a wink of color.
    dot_r = int(size * 0.035)
    dot_cx = panel_x + int(panel_w * 0.66)
    dot_cy = panel_y + int(panel_h * 0.50)
    ImageDraw.Draw(img).ellipse(
        (dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r),
        fill=PINK, outline=BLACK, width=max(stroke // 2, 2)
    )

    return img.convert("RGB")


def make_launch_wordmark(scale: int = 3) -> Image.Image:
    """Transparent-bg wordmark panel sized for iOS launch screen centering.

    iOS centers a UILaunchScreen UIImageName at its native point size, so this
    must be sized in *points*, not screen pixels: @1x ~280pt wide is sensible.
    """
    target_w_pt = 280  # points
    target_h_pt = 96
    width = target_w_pt * scale
    height = target_h_pt * scale

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    font_path = FONTS / "BodoniModa-Variable.ttf"
    font_size = int(height * 0.55)
    font = ImageFont.truetype(str(font_path), font_size)
    text = "Clothedd"
    bbox = font.getbbox(text)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    pad_x = int(text_w * 0.12)
    pad_y = int(text_h * 0.45)
    panel_w = text_w + pad_x * 2
    panel_h = text_h + pad_y * 2
    panel_x = (width - panel_w) // 2
    panel_y = (height - panel_h) // 2
    radius = int(panel_h * 0.18)
    stroke = max(int(panel_h * 0.055), 3)
    shadow_offset = int(panel_h * 0.08)

    od = ImageDraw.Draw(img)
    od.rounded_rectangle(
        (panel_x + shadow_offset, panel_y + shadow_offset,
         panel_x + panel_w + shadow_offset, panel_y + panel_h + shadow_offset),
        radius=radius, fill=BLACK
    )
    od.rounded_rectangle(
        (panel_x, panel_y, panel_x + panel_w, panel_y + panel_h),
        radius=radius, fill=WHITE, outline=BLACK, width=stroke
    )

    tx = panel_x + pad_x - bbox[0]
    ty = panel_y + pad_y - bbox[1]
    od.text((tx, ty), text, font=font, fill=BLACK)

    return img


def write_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"wrote {path.relative_to(ROOT)} ({img.size[0]}x{img.size[1]})")


def main() -> None:
    icon = make_icon(1024)
    write_png(icon, ASSETS / "AppIcon.appiconset" / "AppIcon-1024.png")

    # Tinted + Dark variants — for now just reuse the same image so the slots
    # in Contents.json resolve. Easy to swap later for hand-tuned variants.
    write_png(icon, ASSETS / "AppIcon.appiconset" / "AppIcon-1024-dark.png")
    write_png(icon, ASSETS / "AppIcon.appiconset" / "AppIcon-1024-tinted.png")

    # Mac sizes — just downsample.
    for px in (16, 32, 128, 256, 512):
        for scale, suffix in ((1, ""), (2, "@2x")):
            target = px * scale
            resized = icon.resize((target, target), Image.LANCZOS)
            write_png(resized, ASSETS / "AppIcon.appiconset" / f"mac-{px}{suffix}.png")

    # Launch wordmark at @1x / @2x / @3x point sizes for crisp centering.
    for scale, suffix in ((1, "@1x"), (2, "@2x"), (3, "@3x")):
        wm = make_launch_wordmark(scale=scale)
        write_png(wm, ASSETS / "LaunchLogo.imageset" / f"LaunchLogo{suffix}.png")


if __name__ == "__main__":
    main()
