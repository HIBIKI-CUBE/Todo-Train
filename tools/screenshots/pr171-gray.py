#!/usr/bin/env python3
"""Grayscale the seal gallery and stack it under the color shot."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def main() -> None:
    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    color = Image.open(src).convert("RGB")
    gray = color.convert("L").convert("RGB")
    gray_path = out_dir / "seal-gallery-gray.png"
    gray.save(gray_path)

    gap = 8
    canvas = Image.new("RGB", (color.width, color.height * 2 + gap), (255, 255, 255))
    canvas.paste(color, (0, 0))
    canvas.paste(gray, (0, color.height + gap))
    stacked = out_dir / "seal-gallery-color-and-gray.png"
    canvas.save(stacked)
    print(f"OK gray {gray_path.name} stacked {stacked.name} {color.size}")


if __name__ == "__main__":
    main()
