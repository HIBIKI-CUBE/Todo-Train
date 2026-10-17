#!/usr/bin/env python3
"""Crop ticket-bundle regions from full screenshots (logical layout on iPhone 17)."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def warm_score(px: tuple[int, int, int]) -> bool:
    r, g, b = px
    if 200 < r < 252 and 185 < g < 245 and 160 < b < 230 and r + g + b < 720:
        return True
    # Mars ticket paper (light blue-gray)
    return 145 < r < 238 and 155 < g < 248 and 175 < b < 252 and r + g + b < 720


def ink_score(px: tuple[int, int, int]) -> bool:
    return sum(px) < 120


def ticket_pixel(px: tuple[int, int, int]) -> bool:
    return warm_score(px) or ink_score(px)


def find_horizontal_band(im: Image.Image, y_start: int, y_end: int, min_warm_frac: float = 0.02) -> tuple[int, int] | None:
    w, h = im.size
    best = None
    best_score = 0
    step = max(1, (y_end - y_start) // 80)
    for y in range(y_start, y_end, step):
        warm = sum(1 for x in range(0, w, 6) if warm_score(im.getpixel((x, y))))
        samples = (w // 6) + 1
        if warm / samples >= min_warm_frac and warm > best_score:
            best_score = warm
            best = y
    if best is None:
        return None
    y0 = max(0, best - int(h * 0.04))
    y1 = min(h, best + int(h * 0.10))
    return y0, y1


def warm_bbox(im: Image.Image, y_start: int, y_end: int) -> tuple[int, int, int, int] | None:
    w, h = im.size
    xs: list[int] = []
    ys: list[int] = []
    for y in range(y_start, y_end):
        for x in range(0, w, 3):
            if ticket_pixel(im.getpixel((x, y))):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    pad_x = int(w * 0.03)
    pad_y = int(h * 0.012)
    return (
        max(0, min(xs) - pad_x),
        max(0, min(ys) - pad_y),
        min(w, max(xs) + pad_x),
        min(h, max(ys) + pad_y),
    )


def crop_shutdown(path: Path, out: Path) -> None:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    box = warm_bbox(im, int(h * 0.48), int(h * 0.86))
    if box is None:
        box = (int(w * 0.06), int(h * 0.58), int(w * 0.94), int(h * 0.82))
    im.crop(box).save(out)
    print(f"OK shutdown crop {path.name} -> {out.name} {box}")


def crop_history_day(path: Path, out: Path) -> None:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    band = find_horizontal_band(im, int(h * 0.22), int(h * 0.45), min_warm_frac=0.012)
    if band is None:
        band = (int(h * 0.28), int(h * 0.38))
    y0, y1 = band
    pad_x = int(w * 0.03)
    pad_y = int(h * 0.01)
    box = (pad_x, max(0, y0 - pad_y), w - pad_x, min(h, y1 + pad_y))
    im.crop(box).save(out)
    print(f"OK history-day crop {path.name} -> {out.name} {box}")


def crop_viewer(path: Path, out: Path) -> None:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    band = find_horizontal_band(im, int(h * 0.08), int(h * 0.55), min_warm_frac=0.02)
    if band is None:
        band = (int(h * 0.12), int(h * 0.55))
    y0, y1 = band
    pad_x = int(w * 0.05)
    pad_y = int(h * 0.02)
    box = (pad_x, max(0, y0 - pad_y), w - pad_x, min(h, y1 + pad_y))
    im.crop(box).save(out)
    print(f"OK viewer crop {path.name} -> {out.name} {box}")


def verify_crop(path: Path) -> None:
    im = Image.open(path).convert("RGB")
    pixels = list(im.getdata())
    warm = sum(1 for p in pixels if ticket_pixel(p))
    dark = sum(1 for p in pixels if sum(p) < 90)
    if warm < len(pixels) * 0.01 and dark < len(pixels) * 0.02:
        raise SystemExit(f"FAIL {path.name}: no ticket ink (warm={warm})")


def main() -> None:
    mode = sys.argv[1]
    src = Path(sys.argv[2])
    out = Path(sys.argv[3])
    if mode == "shutdown":
        crop_shutdown(src, out)
    elif mode == "history-day":
        crop_history_day(src, out)
    elif mode == "viewer":
        crop_viewer(src, out)
    else:
        raise SystemExit(f"unknown mode {mode}")
    verify_crop(out)


if __name__ == "__main__":
    main()
