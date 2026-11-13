"""Generate the 书卷 app icon (a lifted page corner on an orange gradient)."""

import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersampled canvas
OUT_ICON_SET = os.path.join("ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
PREVIEW = os.path.join("build", "icon_preview.png")


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def gradient_bg(size):
    top = (255, 158, 78)
    bottom = (226, 58, 18)
    img = Image.new("RGB", (size, size), bottom)
    d = ImageDraw.Draw(img)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(top, bottom, y / size))
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse(
        [-size * 0.40, -size * 0.50, size * 0.80, size * 0.50], fill=120
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.11))
    return Image.composite(Image.new("RGB", (size, size), (255, 205, 150)), img, glow)


def quadratic(a, b, c, n=260):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * b[0] + t ** 2 * c[0]
        y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * b[1] + t ** 2 * c[1]
        pts.append((x, y))
    return pts


def build():
    img = gradient_bg(S)

    left, top, right, bottom = S * 0.205, S * 0.125, S * 0.795, S * 0.875
    radius = S * 0.033
    page_w = right - left
    page_h = bottom - top

    # ---- soft shadow of the sheet -----------------------------------
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left + S * 0.014, top + S * 0.024, right + S * 0.014, bottom + S * 0.024],
        radius=radius,
        fill=155,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.032))
    img = Image.composite(Image.new("RGB", (S, S), (110, 26, 6)), img, shadow)

    # ---- the sheet ---------------------------------------------------
    sheet = Image.new("RGB", (S, S), (255, 255, 255))
    sd = ImageDraw.Draw(sheet)
    sd.rounded_rectangle([left, top, right, bottom], radius=radius, fill=(252, 250, 244))
    for i in range(80):
        t = i / 80
        sd.rectangle(
            [left, top + page_h * t, right, top + page_h * (t + 0.03)],
            fill=lerp((255, 254, 249), (240, 234, 221), t),
        )
    lx0 = left + page_w * 0.10
    lx1 = right - page_w * 0.10
    y = top + page_h * 0.145
    for i, w in enumerate([1.0, 0.90, 0.97, 0.55]):
        h = page_h * 0.038
        sd.rounded_rectangle(
            [lx0, y, lx0 + (lx1 - lx0) * w, y + h],
            radius=h / 2,
            fill=(198, 190, 176) if i % 2 == 0 else (213, 206, 193),
        )
        y += page_h * 0.088

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [left, top, right, bottom], radius=radius, fill=255
    )
    img.paste(sheet, (0, 0), mask)

    # ---- bookmark ribbon (book cue) ---------------------------------
    rb_w = page_w * 0.085
    rb_x = left + page_w * 0.60
    rib = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rib)
    rib_h = page_h * 0.30
    rd.polygon(
        [
            (rb_x, top),
            (rb_x + rb_w, top),
            (rb_x + rb_w, top + rib_h),
            (rb_x + rb_w / 2, top + rib_h - page_h * 0.045),
            (rb_x, top + rib_h),
        ],
        fill=(243, 88, 40, 255),
    )
    img.paste(rib.convert("RGB"), (0, 0), rib.split()[3])

    # ---- lifted corner ----------------------------------------------
    a = (left + page_w * 0.52, bottom + S * 0.004)
    b = (right + S * 0.004, top + page_h * 0.42)
    ctrl = ((a[0] + b[0]) / 2 + S * 0.055, (a[1] + b[1]) / 2 - S * 0.020)
    crease = quadratic(a, ctrl, b)

    corner = Image.new("L", (S, S), 0)
    ImageDraw.Draw(corner).polygon(
        crease + [(right + 60, bottom + 60), (right + 60, crease[-1][1])], fill=255
    )
    img.paste(gradient_bg(S), (0, 0), corner)

    under = Image.new("L", (S, S), 0)
    ImageDraw.Draw(under).polygon(
        [(x - S * 0.02, y - S * 0.02) for x, y in crease]
        + [(right + 60, bottom + 60)],
        fill=170,
    )
    under = under.filter(ImageFilter.GaussianBlur(S * 0.030))
    img = Image.composite(Image.new("RGB", (S, S), (120, 24, 4)), img, under)

    apex = ((a[0] + b[0]) / 2 - S * 0.175, (a[1] + b[1]) / 2 - S * 0.150)
    edge_out = quadratic(
        a, ((a[0] + apex[0]) / 2, (a[1] + apex[1]) / 2 - S * 0.030), apex
    )
    edge_in = quadratic(
        apex, ((b[0] + apex[0]) / 2 + S * 0.020, (b[1] + apex[1]) / 2 - S * 0.010), b
    )

    flap_pts = crease[::-1] + edge_in[1:] + edge_out[1:]
    flap_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(flap_mask).polygon(flap_pts, fill=255)
    flap_mask = flap_mask.filter(ImageFilter.GaussianBlur(S * 0.0018))

    fsh = Image.new("L", (S, S), 0)
    ImageDraw.Draw(fsh).polygon(
        [(x - S * 0.014, y - S * 0.014) for x, y in flap_pts], fill=140
    )
    fsh = fsh.filter(ImageFilter.GaussianBlur(S * 0.022))
    img = Image.composite(Image.new("RGB", (S, S), (150, 62, 34)), img, fsh)

    flap = Image.new("RGB", (S, S))
    fd = ImageDraw.Draw(flap)
    for y in range(S):
        fd.line(
            [(0, y), (S, y)],
            fill=lerp((255, 255, 255), (208, 199, 182), 0.15 + 0.85 * y / S),
        )
    img.paste(flap, (0, 0), flap_mask)

    d = ImageDraw.Draw(img)
    d.line(crease, fill=(255, 255, 255), width=int(S * 0.005), joint="curve")
    d.line(edge_in + edge_out[1:], fill=(255, 255, 255), width=int(S * 0.0055), joint="curve")

    return img


def main():
    img = build()
    big = img.resize((1024, 1024), Image.LANCZOS)
    os.makedirs("build", exist_ok=True)

    smalls = [big.resize((s, s), Image.LANCZOS) for s in (120, 60, 40, 29)]
    sheet = Image.new("RGB", (1024 + 40 + 4 * 150, 1024), (24, 24, 26))
    sheet.paste(big, (0, 0))
    x = 1064
    for s_img in smalls:
        sheet.paste(s_img.resize((130, 130), Image.NEAREST), (x, 40))
        x += 150
    sheet.save(PREVIEW)

    if not os.path.isdir(OUT_ICON_SET):
        print("icon set not found:", OUT_ICON_SET, file=sys.stderr)
        return 1

    with open(os.path.join(OUT_ICON_SET, "Contents.json")) as f:
        contents = json.load(f)

    written = 0
    for entry in contents.get("images", []):
        fname = entry.get("filename")
        size = entry.get("size", "1024x1024")
        scale = entry.get("scale", "1x")
        if not fname:
            continue
        px = int(round(float(size.split("x")[0]) * int(scale.replace("x", ""))))
        big.resize((px, px), Image.LANCZOS).save(os.path.join(OUT_ICON_SET, fname))
        written += 1

    big.save(os.path.join(OUT_ICON_SET, "Icon-App-1024x1024@1x.png"))
    print("wrote", written, "icons; preview:", PREVIEW)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
