#!/usr/bin/env python3
"""Renders the Blinker app icon and regenerates Assets/Blinker.icns.

Concept J "Eclipse": a lit amber disc caught mid-blink behind a dark
occluder — the name Blinker frozen in the act of blinking. Amber is the
name's native color (a turn signal), replacing the traffic-light palette
of the earlier window-centric marks.

Usage:
    python3 Scripts/render-app-icon.py

Requires Pillow (`pip install Pillow`) and macOS `iconutil`. All geometry
is expressed as ratios of the canvas so every icns size is re-rendered
crisp instead of downscaled; fine details are dropped at tiny sizes.
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET_DIR = os.path.join(REPO_ROOT, "Assets", "Blinker.iconset")
ICNS_PATH = os.path.join(REPO_ROOT, "Assets", "Blinker.icns")

# Colors (concept J, amber eclipse on ink).
INK_TOP = (25, 26, 32)       # tile gradient top
INK_BOT = (12, 13, 17)       # tile gradient bottom
AMBER_PALE = (255, 228, 175)
AMBER_DEEP = (255, 128, 0)
OCCLUDER = (20, 21, 26)      # slightly lighter than the tile so it reads as mass
TILE_STROKE = (255, 255, 255, 20)
SHEEN = (255, 255, 255, 13)

# Geometry as canvas ratios (design basis: 1024px).
TILE_MARGIN = 22 / 1024
TILE_RADIUS = 220 / 1024
TILE_STROKE_W = 3 / 1024
DISC_R = 236 / 1024
DISC_STEPS = 64              # concentric-circle radial gradient resolution
OCCLUDER_DX = 98 / 1024
OCCLUDER_DY = -80 / 1024
OCCLUDER_R_FACTOR = 0.97
CORONA_R_FACTOR = 1.85
CORONA_ALPHA = 58
CORONA_BLUR = 72 / 1024
RIM_W = 5 / 1024             # amber rim light along the occluder's lit edge
RIM_ALPHA = 130
RIM_HALF_SPAN = 64           # degrees around the light-facing direction
SHEEN_BLUR = 44 / 1024


def px(size: int, ratio: float) -> float:
    return ratio * size


def lerp(a: tuple, b: tuple, t: float) -> tuple:
    t = max(0.0, min(1.0, t))
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    grad = Image.new("RGBA", (1, size))
    for y in range(size):
        grad.putpixel((0, y), lerp(top, bottom, y / (size - 1)) + (255,))
    return grad.resize((size, size))


def render_master(size: int) -> Image.Image:
    """Renders the icon at `size`; fine details are dropped when tiny."""
    detailed = size >= 128
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    def overlay(draw: ImageDraw.ImageDraw) -> Image.Image:
        layer_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        shapes = ImageDraw.Draw(layer_img)
        draw(shapes)
        return Image.alpha_composite(base, layer_img)

    # Ink squircle tile: vertical gradient clipped by the squircle mask.
    m = px(size, TILE_MARGIN)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [m, m, size - m, size - m], radius=px(size, TILE_RADIUS), fill=255)
    base.paste(vertical_gradient(size, INK_TOP, INK_BOT), (0, 0), mask)

    if detailed:
        # Faint top sheen, clipped to the tile.
        sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(sheen).ellipse(
            [size * 0.18, -size * 0.34, size * 0.82, size * 0.42], fill=SHEEN)
        sheen = sheen.filter(ImageFilter.GaussianBlur(px(size, SHEEN_BLUR)))
        sheen.putalpha(ImageChops.multiply(sheen.getchannel("A"), mask))
        base = Image.alpha_composite(base, sheen)

        def tile_rim(shapes: ImageDraw.ImageDraw) -> None:
            shapes.rounded_rectangle(
                [m + 1.5, m + 1.5, size - m - 1.5, size - m - 1.5],
                radius=px(size, TILE_RADIUS) - 1.5,
                outline=TILE_STROKE,
                width=max(1, round(px(size, TILE_STROKE_W))),
            )

        base = overlay(tile_rim)

    cx = cy = size / 2
    radius = px(size, DISC_R)

    # Corona halo behind the lit disc (skip at tiny sizes).
    if detailed:
        corona = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        cr = radius * CORONA_R_FACTOR
        ImageDraw.Draw(corona).ellipse(
            [cx - cr, cy - cr, cx + cr, cy + cr],
            fill=(255, 176, 60, CORONA_ALPHA))
        corona = corona.filter(ImageFilter.GaussianBlur(px(size, CORONA_BLUR)))
        base = Image.alpha_composite(base, corona)

    # Lit disc: radial gradient via concentric circles (pale core, deep edge).
    steps = max(8, round(DISC_STEPS * size / 1024))

    def disc(shapes: ImageDraw.ImageDraw) -> None:
        for i in range(steps, 0, -1):
            t = i / steps
            rr = radius * t
            shapes.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                           fill=lerp(AMBER_PALE, AMBER_DEEP, t * 1.15 - 0.08)
                           + (255,))

    base = overlay(disc)

    # Dark occluder sliding over the light: the blink itself.
    ox, oy = cx + px(size, OCCLUDER_DX), cy + px(size, OCCLUDER_DY)
    orr = radius * OCCLUDER_R_FACTOR

    def occluder(shapes: ImageDraw.ImageDraw) -> None:
        shapes.ellipse([ox - orr, oy - orr, ox + orr, oy + orr],
                       fill=OCCLUDER + (255,))

    base = overlay(occluder)

    if detailed:
        # Amber atmosphere line where the light grazes the occluder's edge.
        facing = math.degrees(math.atan2(cy - oy, cx - ox))

        def rim(shapes: ImageDraw.ImageDraw) -> None:
            shapes.arc([ox - orr, oy - orr, ox + orr, oy + orr],
                       facing - RIM_HALF_SPAN, facing + RIM_HALF_SPAN,
                       fill=AMBER_PALE + (RIM_ALPHA,),
                       width=max(1, round(px(size, RIM_W))))

        base = overlay(rim)

    return base


# (filename, render size) — the full icns size family.
ICONSET = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def main() -> int:
    if not shutil.which("iconutil"):
        print("error: iconutil not found (macOS only)", file=sys.stderr)
        return 1

    os.makedirs(ICONSET_DIR, exist_ok=True)
    for filename, size in ICONSET:
        render_master(size).save(os.path.join(ICONSET_DIR, filename))

    subprocess.run(["iconutil", "-c", "icns", ICONSET_DIR, "-o", ICNS_PATH], check=True)
    shutil.rmtree(ICONSET_DIR)
    print(f"rendered: {ICNS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
