#!/usr/bin/env python3
"""Build app.ico, size PNGs, and default-logo.png from logo #18.

Large sizes resample the source art. 16px (and a fallback 32px) use a
simplified OTP + 6 pips + wand silhouette so the tray stays readable.
"""

from __future__ import annotations

import io
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SOURCE_REL = Path("docs/logos/round3/18-badge-pips-wand.png")
SIZES = (16, 32, 48, 256)
MASTER = 256

BLUE = (0x00, 0x78, 0xD4, 0xFF)
BLUE_HI = (0x1A, 0x8A, 0xE8, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
STAR_GLOW = (0xE0, 0xF7, 0xFF, 0x90)


def png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


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


def lerp(a: tuple[int, int, int, int], b: tuple[int, int, int, int], t: float) -> tuple[int, int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))  # type: ignore[return-value]


def rounded_rect(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], radius: float, fill) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def four_point_star(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    outer: float,
    inner: float,
    fill,
) -> None:
    pts: list[tuple[float, float]] = []
    for i in range(8):
        ang = math.radians(-90 + i * 45)
        r = outer if i % 2 == 0 else inner
        pts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r))
    draw.polygon(pts, fill=fill)


def try_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ):
        path = Path(name)
        if path.is_file():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def render_simplified(size: int) -> Image.Image:
    """Crisp OTP + 6 pips + wand, rendered at MASTER then scaled."""
    img = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    inset = 8.0
    radius = 54.0
    x0, y0, x1, y1 = inset, inset, MASTER - inset, MASTER - inset

    # Soft vertical gradient on the squircle.
    mask = Image.new("L", (MASTER, MASTER), 0)
    ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=255)
    grad = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(MASTER):
        color = lerp(BLUE_HI, BLUE, (y - y0) / (y1 - y0))
        gdraw.line([(0, y), (MASTER, y)], fill=color)
    img.paste(grad, (0, 0), mask)

    font = try_font(92)
    text = "OTP"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (MASTER - tw) / 2 - bbox[0]
    ty = 58 - bbox[1]
    draw.text((tx, ty), text, font=font, fill=WHITE)

    pip_y = 168
    pip_r = 9.5
    gap = 28
    total = 5 * gap
    start_x = (MASTER - total) / 2
    for i in range(6):
        cx = start_x + i * gap
        draw.ellipse((cx - pip_r, pip_y - pip_r, cx + pip_r, pip_y + pip_r), fill=WHITE)

    # Wand: thicker diagonal + glowing 4-point star (upper-right).
    glow = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    four_point_star(g, 204, 52, 28, 10, STAR_GLOW)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=4))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)
    draw.line((148, 118, 198, 58), fill=WHITE, width=10)
    four_point_star(draw, 204, 52, 22, 8, WHITE)

    if size == MASTER:
        return img
    return img.resize((size, size), Image.Resampling.LANCZOS)


def resample_source(source: Image.Image, size: int) -> Image.Image:
    rgba = source.convert("RGBA")
    return rgba.resize((size, size), Image.Resampling.LANCZOS)


def is_too_soft(image: Image.Image) -> bool:
    """True when a tiny resample is mostly a flat blue blob."""
    gray = image.convert("L")
    extrema = gray.getextrema()
    if extrema is None:
        return True
    lo, hi = extrema
    return (hi - lo) < 40


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    source_path = root / SOURCE_REL
    if not source_path.is_file():
        raise SystemExit(f"missing source logo: {source_path}")

    source = Image.open(source_path)
    assets = root / "src" / "Autototp" / "Assets"
    assets.mkdir(parents=True, exist_ok=True)

    pngs: list[bytes] = []
    for size in SIZES:
        if size <= 32:
            pixels = render_simplified(size)
        else:
            pixels = resample_source(source, size)
            if size <= 48 and is_too_soft(pixels):
                pixels = render_simplified(size)
        png = png_bytes(pixels)
        pngs.append(png)
        dest = assets / f"app-{size}.png"
        dest.write_bytes(png)
        print(f"wrote {dest} ({dest.stat().st_size} bytes)")

    default = resample_source(source, 256)
    default_path = assets / "default-logo.png"
    default_path.write_bytes(png_bytes(default))
    print(f"wrote {default_path} ({default_path.stat().st_size} bytes)")

    ico = ico_from_pngs(pngs, SIZES)
    dest = assets / "app.ico"
    dest.write_bytes(ico)
    print(f"wrote {dest} ({dest.stat().st_size} bytes) sizes={SIZES}")


if __name__ == "__main__":
    main()
