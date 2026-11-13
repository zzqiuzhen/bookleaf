"""书卷 app icon: an open book with one folded corner, on a warm orange field.

Why this design:
  * the folded top-right corner is the cue that makes it read as *bound paper*
    instead of two white cards, and it survives down to 29 px because it is a
    notch in the silhouette, not a shading detail
  * no drop shadow and no grain: those are what made the first version look
    cheap and muddy when iOS shrinks the asset
  * strictly mirror-symmetric pages, rounded with a single mask blur so both
    halves have identical corners
"""

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4096
ICON_SET = os.path.join("ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
PREVIEW = os.path.join("build", "icon_preview.png")

PAPER_TOP = (255, 253, 248)
PAPER_BOTTOM = (243, 235, 222)
FOLD = (226, 213, 193)
FOLD_EDGE = (208, 192, 168)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def bez(p0, p1, p2, p3, n=140):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def background(size):
    s = size
    img = Image.new("RGB", (s, s), (231, 72, 30))
    d = ImageDraw.Draw(img)
    for y in range(s):
        d.line([(0, y), (s, y)], fill=lerp((255, 166, 92), (231, 72, 30), (y / s) ** 0.9))
    glow = Image.new("L", (s, s), 0)
    ImageDraw.Draw(glow).ellipse([-s * 0.42, -s * 0.52, s * 0.78, s * 0.46], fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.12))
    return Image.composite(Image.new("RGB", (s, s), (255, 216, 170)), img, glow)


def geometry(s):
    """Control points shared by the mask, the fold and the shading."""
    return dict(
        spine_top=(0.500 * s, 0.232 * s),
        spine_bottom=(0.500 * s, 0.772 * s),
        outer_top=(0.106 * s, 0.284 * s),
        outer_bottom=(0.124 * s, 0.726 * s),
        gap=0.0215 * s,
    )


def left_outline(s, g):
    """Points of the left page, from the spine top around to the spine bottom."""
    pts = []
    pts += bez(g["spine_top"], (0.40 * s, 0.196 * s), (0.24 * s, 0.206 * s), g["outer_top"])
    pts += bez(g["outer_top"], (0.106 * s, 0.430 * s), (0.116 * s, 0.580 * s), g["outer_bottom"])
    pts += bez(g["outer_bottom"], (0.250 * s, 0.756 * s), (0.400 * s, 0.800 * s), g["spine_bottom"])
    return pts


def _reflect(p, a, b):
    """Mirror point p across the line through a and b."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy)
    fx, fy = ax + t * dx, ay + t * dy
    return (2 * fx - p[0], 2 * fy - p[1])


def fold_triangle(s, g):
    """Corner peel on the right page: (corner C, cut A on outer edge, cut B on
    top edge, folded tip T). C is removed, A-B-T is the flap that shows."""
    ox, oy = s - g["outer_top"][0], g["outer_top"][1]
    corner = (ox, oy)
    a = (ox - 0.006 * s, oy + 0.106 * s)   # down the outer edge
    b = (ox - 0.106 * s, oy + 0.006 * s)   # in along the top edge
    tip = _reflect(corner, a, b)
    return corner, a, b, tip


def page_mask(s):
    g = geometry(s)
    mask = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(mask)

    left = left_outline(s, g)
    poly_left = left + [
        (g["spine_bottom"][0] - g["gap"], g["spine_bottom"][1] - g["gap"] * 0.15),
        (g["spine_top"][0] - g["gap"], g["spine_top"][1] + g["gap"] * 0.35),
    ]
    d.polygon(poly_left, fill=255)

    right = [(s - x, y) for (x, y) in poly_left]
    d.polygon(right, fill=255)
    corner, a, b, tip = fold_triangle(s, g)
    d.polygon([a, b, corner], fill=0)

    rounded = mask.filter(ImageFilter.GaussianBlur(s * 0.0135))
    return rounded.point(lambda v: 255 if v > 138 else 0)


def paper(s):
    img = Image.new("RGB", (s, s), PAPER_TOP)
    d = ImageDraw.Draw(img)
    for y in range(s):
        t = min(max((y / s - 0.20) / 0.62, 0.0), 1.0)
        d.line([(0, y), (s, y)], fill=lerp(PAPER_TOP, PAPER_BOTTOM, t))
    return img


def build():
    s = S
    g = geometry(s)
    img = background(s)
    mask = page_mask(s)
    img.paste(paper(s), (0, 0), mask)

    d = ImageDraw.Draw(img, "RGBA")

    # folded corner: the flap (paper back) plus the crease it folded along.
    # Painted through the page mask so no sliver of flap can stick out past the
    # page silhouette.
    corner, a, b, tip = fold_triangle(s, g)
    flap = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flap)
    fd.polygon([a, b, tip], fill=FOLD + (255,))
    fd.line([a, b], fill=FOLD_EDGE + (255,), width=int(s * 0.0040))
    fd.line([a, tip], fill=FOLD_EDGE + (200,), width=int(s * 0.0026))
    fd.line([b, tip], fill=FOLD_EDGE + (200,), width=int(s * 0.0026))
    alpha = Image.composite(flap.split()[3], Image.new("L", (s, s), 0), mask)
    flap.putalpha(alpha)
    img = Image.alpha_composite(img.convert("RGBA"), flap).convert("RGB")
    d = ImageDraw.Draw(img, "RGBA")

    # hinge shadow, symmetric, right where the two pages meet
    for i in range(16):
        alpha = int(38 * (1 - i / 16) ** 1.35)
        off = i * s * 0.0012
        w = max(1, int(s * 0.0015))
        for sign in (-1, 1):
            x = 0.5 * s + sign * (g["gap"] + off)
            d.line([(x, 0.252 * s), (x, 0.760 * s)], fill=(120, 72, 38, alpha), width=w)

    return img


def main():
    big = build().resize((1024, 1024), Image.LANCZOS)
    os.makedirs("build", exist_ok=True)

    sheet = Image.new("RGB", (1024 + 40 + 4 * 150, 1024), (22, 22, 24))
    sheet.paste(big, (0, 0))
    x = 1064
    for px in (120, 60, 40, 29):
        sheet.paste(
            big.resize((px, px), Image.LANCZOS).resize((130, 130), Image.NEAREST),
            (x, 40),
        )
        x += 150
    sheet.save(PREVIEW)

    with open(os.path.join(ICON_SET, "Contents.json")) as f:
        contents = json.load(f)
    for entry in contents.get("images", []):
        name = entry.get("filename")
        if not name:
            continue
        size = float(entry.get("size", "1024x1024").split("x")[0])
        scale = int(entry.get("scale", "1x").replace("x", ""))
        big.resize((int(round(size * scale)),) * 2, Image.LANCZOS).save(
            os.path.join(ICON_SET, name)
        )
    big.save(os.path.join(ICON_SET, "Icon-App-1024x1024@1x.png"))
    print("icons written ->", PREVIEW)


if __name__ == "__main__":
    raise SystemExit(main())
