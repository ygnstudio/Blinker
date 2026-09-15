#!/usr/bin/env python3
"""Renders the Blinker app icon and regenerates Assets/Blinker.icns.

Concept B: dark graphite tile, an inset rounded window, and the traffic
lights on its titlebar — with the green light enlarged and glowing as a
nod to Blinker's hover-zoom feature.

Usage:
    python3 Scripts/render-app-icon.py

Requires Pillow (`pip install Pillow`) and macOS `iconutil`. All geometry
is expressed as ratios of the canvas so every icns size is re-rendered
crisp instead of downscaled; fine details are dropped at tiny sizes.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET_DIR = os.path.join(REPO_ROOT, "Assets", "Blinker.iconset")
ICNS_PATH = os.path.join(REPO_ROOT, "Assets", "Blinker.icns")

# Colors (concept B, dark graphite).
TILE = (43, 43, 48)          # graphite squircle
TILE_STROKE = (255, 255, 255, 30)   # 12% rim highlight
WINDOW_BG = (58, 58, 65)     # inset window plate
WINDOW_STROKE = (87, 87, 95)
BAR = (75, 75, 84)           # window content placeholder bars
RED = (255, 95, 87)
YELLOW = (255, 189, 46)
GREEN = (40, 200, 64)
LIGHT_HIGHLIGHT = (255, 255, 255, 92)   # 36% top gloss

# Geometry as canvas ratios (design basis: 1024px).
TILE_MARGIN = 22 / 1024
TILE_RADIUS = 220 / 1024
WIN_X, WIN_Y = 206 / 1024, 165 / 1024
WIN_W, WIN_H = 612 / 1024, 653 / 1024
WIN_RADIUS = 109 / 1024
LIGHT_CY = 295 / 1024
# Lights share a left edge with the content bars below them.
LIGHT_XS = (340 / 1024, 460 / 1024, 580 / 1024)
LIGHT_R = 44 / 1024
GREEN_R = 52 / 1024
# Smooth radial glow: one solid disc, Gaussian-blurred, under the green light.
GLOW_R = 88 / 1024
GLOW_ALPHA = 64
GLOW_BLUR = 36 / 1024
BAR_X = 296 / 1024
BAR_YS = (435 / 1024, 545 / 1024, 655 / 1024)
BAR_WS = (440 / 1024, 300 / 1024, 370 / 1024)
BAR_H = 48 / 1024
BAR_R = 24 / 1024
STROKE_W = 4 / 1024


def px(size: int, ratio: float) -> float:
    return ratio * size


def render_master(size: int) -> Image.Image:
    """Renders the icon at `size`; fine details are dropped when tiny."""
    detailed = size >= 128
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    def overlay(draw: ImageDraw.ImageDraw) -> Image.Image:
        layer_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        shapes = ImageDraw.Draw(layer_img)
        draw(shapes)
        return Image.alpha_composite(base, layer_img)

    # Graphite squircle tile.
    def tile(shapes: ImageDraw.ImageDraw) -> None:
        m = px(size, TILE_MARGIN)
        shapes.rounded_rectangle(
            [m, m, size - m, size - m],
            radius=px(size, TILE_RADIUS),
            fill=TILE + (255,),
            outline=TILE_STROKE if detailed else None,
            width=max(1, round(px(size, 8 / 1024))) if detailed else 0,
        )

    base = overlay(tile)

    # Inset window plate.
    def window_plate(shapes: ImageDraw.ImageDraw) -> None:
        x0, y0 = px(size, WIN_X), px(size, WIN_Y)
        shapes.rounded_rectangle(
            [x0, y0, x0 + px(size, WIN_W), y0 + px(size, WIN_H)],
            radius=px(size, WIN_RADIUS),
            fill=WINDOW_BG + (255,),
            outline=WINDOW_STROKE + (255,) if detailed else None,
            width=max(1, round(px(size, STROKE_W))) if detailed else 0,
        )

    base = overlay(window_plate)

    # Green glow halo (skip at tiny sizes).
    if detailed:
        glow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow_layer)
        gx, gy = px(size, LIGHT_XS[2]), px(size, LIGHT_CY)
        r = px(size, GLOW_R)
        glow_draw.ellipse([gx - r, gy - r, gx + r, gy + r], fill=GREEN + (GLOW_ALPHA,))
        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(px(size, GLOW_BLUR)))
        base = Image.alpha_composite(base, glow_layer)

    # Traffic lights.
    def lights(shapes: ImageDraw.ImageDraw) -> None:
        cy = px(size, LIGHT_CY)
        radii = (px(size, LIGHT_R), px(size, LIGHT_R), px(size, GREEN_R))
        colors = (RED, YELLOW, GREEN)
        for x_ratio, r, color in zip(LIGHT_XS, radii, colors):
            cx = px(size, x_ratio)
            shapes.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))

    base = overlay(lights)

    if detailed:
        # Top gloss on each light.
        def gloss(shapes: ImageDraw.ImageDraw) -> None:
            cy = px(size, LIGHT_CY)
            for x_ratio, r in zip(LIGHT_XS, (LIGHT_R, LIGHT_R, GREEN_R)):
                cx = px(size, x_ratio)
                hw, hh = r * 0.55, r * 0.24
                shapes.ellipse(
                    [cx - hw, cy - r * 0.66, cx + hw, cy - r * 0.66 + 2 * hh],
                    fill=LIGHT_HIGHLIGHT,
                )

        base = overlay(gloss)

        # Window content placeholder bars.
        def bars(shapes: ImageDraw.ImageDraw) -> None:
            for y_ratio, w_ratio in zip(BAR_YS, BAR_WS):
                x0, y0 = px(size, BAR_X), px(size, y_ratio)
                shapes.rounded_rectangle(
                    [x0, y0, x0 + px(size, w_ratio), y0 + px(size, BAR_H)],
                    radius=px(size, BAR_R),
                    fill=BAR + (255,),
                )

        base = overlay(bars)

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
