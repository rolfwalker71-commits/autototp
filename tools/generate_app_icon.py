#!/usr/bin/env python3
"""Generate a multi-size Fluent 2 app.ico (16/32/48/256) without PIL."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

# Windows Fluent accent blue
BLUE = (0x00, 0x5F, 0xB8, 0xFF)
BLUE_HI = (0x1A, 0x78, 0xD4, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)

MASTER = 256
SIZES = (16, 32, 48, 256)


def lerp(a: tuple[int, int, int, int], b: tuple[int, int, int, int], t: float) -> tuple[int, int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))  # type: ignore[return-value]


def rounded_rect_coverage(x: float, y: float, x0: float, y0: float, x1: float, y1: float, r: float) -> float:
    """Approximate coverage of a pixel center against a rounded rectangle."""
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    if x0 + r <= x <= x1 - r or y0 + r <= y <= y1 - r:
        inside_x = x0 <= x <= x1
        inside_y = y0 <= y <= y1
        if inside_x and inside_y:
            edge = min(x - x0, x1 - x, y - y0, y1 - y)
            return 1.0 if edge >= 0.5 else max(0.0, min(1.0, edge + 0.5))
        return 0.0
    dx = x - cx
    dy = y - cy
    dist = (dx * dx + dy * dy) ** 0.5
    return max(0.0, min(1.0, r + 0.5 - dist))


def rect_coverage(x: float, y: float, x0: float, y0: float, x1: float, y1: float) -> float:
    if x0 + 0.5 <= x <= x1 - 0.5 and y0 + 0.5 <= y <= y1 - 0.5:
        return 1.0
    if x < x0 - 0.5 or x > x1 + 0.5 or y < y0 - 0.5 or y > y1 + 0.5:
        return 0.0
    # Partial coverage on edges
    left = max(0.0, min(1.0, x + 0.5 - x0))
    right = max(0.0, min(1.0, x1 - (x - 0.5)))
    top = max(0.0, min(1.0, y + 0.5 - y0))
    bottom = max(0.0, min(1.0, y1 - (y - 0.5)))
    return max(0.0, min(1.0, min(left, right) * min(top, bottom)))


def blend(dst: list[int], src: tuple[int, int, int, int], a: float) -> None:
    if a <= 0:
        return
    a = min(1.0, a)
    ia = 1.0 - a
    dst[0] = int(round(dst[0] * ia + src[0] * a))
    dst[1] = int(round(dst[1] * ia + src[1] * a))
    dst[2] = int(round(dst[2] * ia + src[2] * a))
    dst[3] = int(round(dst[3] * ia + src[3] * a))


def render_master() -> list[list[list[int]]]:
    pixels = [[[0, 0, 0, 0] for _ in range(MASTER)] for _ in range(MASTER)]
    inset = 10.0
    radius = 52.0
    x0, y0, x1, y1 = inset, inset, MASTER - inset, MASTER - inset

    for y in range(MASTER):
        for x in range(MASTER):
            cov = rounded_rect_coverage(x + 0.5, y + 0.5, x0, y0, x1, y1, radius)
            if cov <= 0:
                continue
            t = (y - y0) / (y1 - y0)
            color = lerp(BLUE_HI, BLUE, max(0.0, min(1.0, t)))
            blend(pixels[y][x], color, cov)

    # Geometric T: wide crossbar + centered stem, readable after 16px downsample
    pad = 58.0
    bar_top = pad
    bar_h = 38.0
    stem_w = 40.0
    stem_bottom = MASTER - pad
    bar_left = pad + 6.0
    bar_right = MASTER - pad - 6.0
    stem_x0 = (MASTER - stem_w) / 2.0
    stem_x1 = stem_x0 + stem_w

    for y in range(MASTER):
        for x in range(MASTER):
            px, py = x + 0.5, y + 0.5
            t_cov = max(
                rect_coverage(px, py, bar_left, bar_top, bar_right, bar_top + bar_h),
                rect_coverage(px, py, stem_x0, bar_top, stem_x1, stem_bottom),
            )
            if t_cov > 0:
                blend(pixels[y][x], WHITE, t_cov)

    return pixels


def downsample(src: list[list[list[int]]], size: int) -> list[list[list[int]]]:
    if size == MASTER:
        return src
    factor = MASTER // size
    out = [[[0, 0, 0, 0] for _ in range(size)] for _ in range(size)]
    for y in range(size):
        for x in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for oy in range(factor):
                for ox in range(factor):
                    p = src[y * factor + oy][x * factor + ox]
                    for i in range(4):
                        acc[i] += p[i]
            n = factor * factor
            out[y][x] = [int(round(v / n)) for v in acc]
    return out


def png_bytes(pixels: list[list[list[int]]]) -> bytes:
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((r, g, b, a))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def ico_from_pngs(pngs: list[bytes], sizes: tuple[int, ...]) -> bytes:
    count = len(pngs)
    header = struct.pack("<HHH", 0, 1, count)
    entries = bytearray()
    offset = 6 + 16 * count
    blobs = bytearray()
    for png, size in zip(pngs, sizes):
        w = 0 if size >= 256 else size
        h = 0 if size >= 256 else size
        entries.extend(struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(png), offset))
        blobs.extend(png)
        offset += len(png)
    return header + bytes(entries) + bytes(blobs)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    assets = root / "src" / "Autototp" / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    master = render_master()
    pngs = []
    for size in SIZES:
        pixels = downsample(master, size)
        png = png_bytes(pixels)
        pngs.append(png)
        (assets / f"app-{size}.png").write_bytes(png)
    ico = ico_from_pngs(pngs, SIZES)
    dest = assets / "app.ico"
    dest.write_bytes(ico)
    print(f"wrote {dest} ({dest.stat().st_size} bytes) sizes={SIZES}")


if __name__ == "__main__":
    main()
