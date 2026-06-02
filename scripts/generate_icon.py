#!/usr/bin/env python3
"""Material flat icon: bell + floppy disk.

Generates two files:
  assets/icon/icon.png            — full icon (for iOS / legacy Android)
  assets/icon/icon_foreground.png — transparent foreground for Android adaptive icon
"""

import os
from PIL import Image, ImageDraw

SIZE = 1024
OUT_FULL = os.path.join(os.path.dirname(__file__), "../assets/icon/icon.png")
OUT_FG   = os.path.join(os.path.dirname(__file__), "../assets/icon/icon_foreground.png")

BG      = (63, 81, 181)   # Material Indigo 500
WHITE   = (255, 255, 255)
LABEL   = (63, 81, 181)   # same as bg, for the diskette label window


def rounded_rect(draw, x0, y0, x1, y1, r, fill):
    draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)
    for cx, cy in [(x0 + r, y0 + r), (x1 - r, y0 + r),
                   (x0 + r, y1 - r), (x1 - r, y1 - r)]:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def draw_bell(draw, cx, cy, s):
    """Flat geometric bell centred at (cx, cy), sized by s."""
    dome_r   = int(0.23 * s)
    body_bot = cy + int(0.18 * s)
    body_hw  = int(0.28 * s)   # half-width at base
    body_top = cy - int(0.04 * s)

    # dome (semicircle)
    dome_top = cy - int(0.27 * s)
    draw.ellipse([cx - dome_r, dome_top,
                  cx + dome_r, dome_top + dome_r * 2], fill=WHITE)

    # trapezoidal body
    draw.polygon([
        (cx - int(0.09 * s), body_top),
        (cx - body_hw,       body_bot),
        (cx + body_hw,       body_bot),
        (cx + int(0.09 * s), body_top),
    ], fill=WHITE)

    # rim
    rim_h = int(0.045 * s)
    rounded_rect(draw,
                 cx - body_hw - rim_h, body_bot,
                 cx + body_hw + rim_h, body_bot + rim_h,
                 rim_h // 2, WHITE)

    # handle / stem on top
    stem_w  = int(0.045 * s)
    stem_t  = dome_top - int(0.08 * s)
    rounded_rect(draw,
                 cx - stem_w, stem_t,
                 cx + stem_w, dome_top + int(0.06 * s),
                 stem_w, WHITE)

    # clapper
    clap_r = int(0.055 * s)
    clap_y = body_bot + rim_h + int(0.02 * s)
    draw.ellipse([cx - clap_r, clap_y,
                  cx + clap_r, clap_y + clap_r * 2], fill=WHITE)


def draw_floppy(draw, cx, cy, s, label_color=None):
    """Flat geometric 3.5-inch floppy disk centred at (cx, cy)."""
    if label_color is None:
        label_color = BG
    hw = int(0.22 * s)
    hh = int(0.22 * s)
    corner = int(0.03 * s)

    x0, y0 = cx - hw, cy - hh
    x1, y1 = cx + hw, cy + hh

    # body
    rounded_rect(draw, x0, y0, x1, y1, corner, WHITE)

    # top notch (cut corner, top-right)
    notch = int(0.10 * s)
    draw.polygon([
        (x1 - notch, y0),
        (x1,         y0 + notch),
        (x1,         y0),
    ], fill=label_color)

    # label window (upper centre)
    lw = int(0.28 * s)
    lh = int(0.18 * s)
    lx0 = cx - lw // 2
    lx1 = cx + lw // 2
    ly0 = y0 + int(0.04 * s)
    ly1 = ly0 + lh
    rounded_rect(draw, lx0, ly0, lx1, ly1, int(0.015 * s), label_color)

    # shutter (bottom centre)
    sh_w = int(0.12 * s)
    sh_h = int(0.22 * s)
    sh_x0 = cx - sh_w // 2
    sh_x1 = cx + sh_w // 2
    sh_y0 = y1 - sh_h
    sh_y1 = y1
    rounded_rect(draw, sh_x0, sh_y0, sh_x1, sh_y1, int(0.012 * s), label_color)

    # shutter slot line
    slot_y = sh_y0 + int(0.06 * s)
    slot_h = int(0.025 * s)
    rounded_rect(draw, sh_x0 + int(0.02 * s), slot_y,
                 sh_x1 - int(0.02 * s), slot_y + slot_h,
                 slot_h // 2, WHITE)


def draw_icons(draw, size, scale, label_color):
    """Draw bell + floppy onto draw. label_color used for floppy internals."""
    s  = size
    bell_cx   = int(s * 0.38)
    bell_cy   = int(s * 0.42)
    floppy_cx = int(s * 0.66)
    floppy_cy = int(s * 0.63)
    draw_bell(draw, bell_cx, bell_cy, s * scale)
    draw_floppy(draw, floppy_cx, floppy_cy, s * scale, label_color)


def main():
    os.makedirs(os.path.dirname(OUT_FULL), exist_ok=True)

    # --- full icon (rounded bg + icons) for iOS / legacy ---
    full = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(full)
    rounded_rect(d, 0, 0, SIZE, SIZE, int(0.22 * SIZE), BG)
    draw_icons(d, SIZE, 0.55, BG)
    full.save(OUT_FULL, "PNG")
    print(f"Saved → {OUT_FULL}")

    # --- foreground for Android adaptive icon ---
    # Adaptive safe zone = 66% of canvas; we scale icons to fit inside that.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(fg)
    # scale down so artwork stays within the 66 % safe zone
    draw_icons(d2, SIZE, 0.55 * 0.72, (0, 0, 0, 0))
    fg.save(OUT_FG, "PNG")
    print(f"Saved → {OUT_FG}")


if __name__ == "__main__":
    main()
