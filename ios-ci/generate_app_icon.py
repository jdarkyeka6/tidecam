#!/usr/bin/env python3
"""Generate TideCam's temporary 1024px App Store icon without external deps.

This is intentionally simple and deterministic so GitHub Actions can create
an opaque PNG before Xcode compiles the asset catalog. Replace it later with
the final designed icon asset.
"""

from pathlib import Path
import math
import struct
import zlib

SIZE = 1024
OUT = Path("TideCam/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def pixel(x: int, y: int) -> tuple[int, int, int]:
    # Deep ocean gradient background.
    t = (x + y) / (2 * (SIZE - 1))
    r = int(4 + 8 * t)
    g = int(24 + 65 * t)
    b = int(52 + 102 * t)

    cx = cy = SIZE / 2
    d = math.hypot(x - cx, y - cy)

    # Camera/lens mark. No alpha, which App Store icons require.
    if 252 <= d <= 302:
        return (245, 250, 255)
    if d < 214:
        # Lens glass with a subtle radial highlight.
        k = max(0.0, 1.0 - d / 214)
        return (
            int(22 + 25 * k),
            int(128 + 76 * k),
            int(176 + 65 * k),
        )

    # Small highlight dot in the upper-right of the lens.
    if math.hypot(x - 624, y - 400) < 48:
        return (245, 250, 255)

    return (r, g, b)


raw = bytearray()
for y in range(SIZE):
    raw.append(0)  # PNG filter: None
    for x in range(SIZE):
        raw.extend(pixel(x, y))

png = bytearray(b"\x89PNG\r\n\x1a\n")
png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)))
png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), level=9)))
png.extend(chunk(b"IEND", b""))

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(png)
print(f"Generated {OUT} ({len(png)} bytes)")
