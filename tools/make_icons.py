"""Generate the addon's UI icons as uncompressed TGA (white shapes, alpha antialiased): play/stop/next
32x32, addon icon 64x64.

WoW reads .tga textures from the addon folder by path; tint them in Lua with SetVertexColor.
    python3 tools/make_icons.py
"""

from __future__ import annotations

import struct
from pathlib import Path

SAMPLES = 4  # supersampling per axis for antialiasing
OUT = Path(__file__).resolve().parent.parent / "addon" / "ForeverSpeech" / "media"


import math


def play(x: float, y: float) -> bool:
    # right-pointing triangle, y measured from the top
    return 9 <= x <= 25 and abs(y - 16) <= (x - 9) * 0.5 * -1 + 8 + 0.0001


def stop(x: float, y: float) -> bool:
    return 9 <= x <= 23 and 9 <= y <= 23


def next_(x: float, y: float) -> bool:
    """Skip forward: a triangle and a bar."""
    if 8 <= x <= 20 and abs(y - 16) <= (20 - x) * 7 / 12 + 0.0001:
        return True
    return 21 <= x <= 24 and 9 <= y <= 23


def speaker(x: float, y: float) -> bool:
    """Addon icon on a 64 grid: a speaker with two sound waves."""
    if 12 <= x <= 22 and 25 <= y <= 39:  # body
        return True
    if 22 <= x <= 34 and abs(y - 32) <= 7 + (x - 22) * (11 / 12):  # cone
        return True
    dx, dy = x - 34, y - 32
    r, angle = math.hypot(dx, dy), math.degrees(math.atan2(dy, dx))
    if dx > 0 and abs(angle) <= 50:
        return 10 <= r <= 14 or 19 <= r <= 23
    return False


def render(shape, size: int = 32) -> bytes:
    pixels = bytearray()
    for row in range(size - 1, -1, -1):  # TGA origin is bottom-left
        for col in range(size):
            hits = sum(
                shape(col + (i + 0.5) / SAMPLES, row + (j + 0.5) / SAMPLES)
                for i in range(SAMPLES) for j in range(SAMPLES)
            )
            alpha = round(255 * hits / SAMPLES**2)
            pixels += bytes((255, 255, 255, alpha))  # BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    return header + bytes(pixels)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, shape, size in (("play", play, 32), ("stop", stop, 32), ("next", next_, 32), ("icon", speaker, 64)):
        (OUT / f"{name}.tga").write_bytes(render(shape, size))
        print(f"wrote {OUT / name}.tga")


if __name__ == "__main__":
    main()
