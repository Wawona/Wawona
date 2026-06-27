"""
Wawona icon — orange→purple vertical gradient, angular W, bear-claw scratches.
"""

import math

from PIL import Image, ImageDraw

SIZE = 1024
OUTPUT = "wawona_icon.png"
C = SIZE / 2

ORANGE_TOP = (0xf5, 0xa8, 0x5c)
PURPLE_BOTTOM = (0x5c, 0x42, 0x8a)

DISC_R = 368

W_TOP = C - 148
W_VALLEY = C + 132
W_HALF = 168
VALLEY_INSET = 0.38
STROKE_WIDE = 76
STROKE_NARROW = 54

SCRATCHES = (
    (C - 210, C - 118, -38, 148, 4, 11),
    (C + 198, C - 108, -32, 136, 4, 10),
    (C - 92, C + 42, -42, 118, 3, 9),
    (C + 118, C + 58, -35, 124, 3, 10),
    (C - 28, C - 198, -48, 102, 3, 8),
    (C + 44, C - 186, -40, 96, 3, 8),
)


def blend(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(x * t + y * (1 - t))) for x, y in zip(a, b))


def vertical_gradient(width, height, top_rgb, bottom_rgb):
    img = Image.new("RGB", (width, height))
    px = img.load()
    denom = max(1, height - 1)
    for y in range(height):
        row = blend(top_rgb, bottom_rgb, y / denom)
        for x in range(width):
            px[x, y] = row
    return img


def stroke_poly(p0, p1, w0, w1, lean=0):
    x0, y0 = p0
    x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    if length < 1:
        return []
    tx, ty = dx / length, dy / length
    nx, ny = -dy / length, dx / length
    h0, h1 = w0 / 2, w1 / 2
    return [
        (x0 + nx * h0 - tx * lean, y0 + ny * h0 - ty * lean),
        (x1 + nx * h1 + tx * lean, y1 + ny * h1 + ty * lean),
        (x1 - nx * h1 + tx * lean, y1 - ny * h1 + ty * lean),
        (x0 - nx * h0 - tx * lean, y0 - ny * h0 - ty * lean),
    ]


def w_points():
    left = C - W_HALF
    right = C + W_HALF
    valley_dx = W_HALF * VALLEY_INSET
    return (
        (left, W_TOP),
        (C - valley_dx, W_VALLEY),
        (C, W_TOP - 8),
        (C + valley_dx, W_VALLEY),
        (right, W_TOP),
    )


def claw_poly(cx, cy, angle_deg, length, count, spacing, width=9):
    angle = math.radians(angle_deg)
    dx, dy = math.cos(angle), math.sin(angle)
    nx, ny = -dy, dx
    half = (count - 1) * spacing / 2
    polys = []
    for i in range(count):
        off = i * spacing - half
        x0 = cx + nx * off - dx * length * 0.45
        y0 = cy + ny * off - dy * length * 0.45
        x1 = cx + nx * off + dx * length * 0.55
        y1 = cy + ny * off + dy * length * 0.55
        w = width * (0.85 + 0.15 * (i == count // 2))
        polys.append(stroke_poly((x0, y0), (x1, y1), w, w * 0.7))
    return polys


def apply_scratches(alpha: Image.Image):
    d = ImageDraw.Draw(alpha)
    for cx, cy, angle, length, count, spacing in SCRATCHES:
        for poly in claw_poly(cx, cy, angle, length, count, spacing):
            if poly:
                d.polygon(poly, fill=0)


def masked_gradient_layer(gradient: Image.Image, mask: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.paste(gradient, (0, 0))
    layer.putalpha(mask)
    return layer


def draw_icon() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gradient = vertical_gradient(SIZE, SIZE, ORANGE_TOP, PURPLE_BOTTOM)

    disc_alpha = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(disc_alpha)
    d.ellipse((C - DISC_R, C - DISC_R, C + DISC_R, C + DISC_R), fill=255)
    apply_scratches(disc_alpha)
    img.alpha_composite(masked_gradient_layer(gradient, disc_alpha))

    a, b, c_pt, d_pt, e = w_points()
    strokes = (
        (a, b, STROKE_WIDE, STROKE_NARROW, 8),
        (b, c_pt, STROKE_NARROW, STROKE_WIDE, -7),
        (c_pt, d_pt, STROKE_WIDE, STROKE_NARROW, 7),
        (d_pt, e, STROKE_NARROW, STROKE_WIDE, -8),
    )
    for p0, p1, w0, w1, lean in strokes:
        poly = stroke_poly(p0, p1, w0, w1, lean)
        if not poly:
            continue
        mask = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(mask).polygon(poly, fill=255)
        img.alpha_composite(masked_gradient_layer(gradient, mask))

    return img


def main():
    draw_icon().save(OUTPUT)
    print(f"Saved {OUTPUT}")


if __name__ == "__main__":
    main()
