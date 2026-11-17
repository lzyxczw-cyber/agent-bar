import os
from PIL import Image, ImageDraw

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "icon")
os.makedirs(OUT, exist_ok=True)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# background: rounded square, soft vertical gradient
bg_top, bg_bottom = (32, 36, 46), (11, 13, 18)
grad = Image.new("RGB", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    gd.line([(0, y), (S, y)], fill=lerp(bg_top, bg_bottom, y / (S - 1)))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=228, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(icon, "RGBA")

# ---- agent bar across the top ----
strip_h = 196
d.rectangle([0, 0, S, strip_h], fill=(24, 27, 35, 255))
d.rectangle([0, 0, S, 6], fill=(58, 64, 78, 255))
d.line([(0, strip_h - 1), (S, strip_h - 1)], fill=(64, 70, 84, 255), width=2)

# simulated camera housing
notch_w, notch_h = 306, strip_h
nx = (S - notch_w) // 2
d.rounded_rectangle([nx, -60, nx + notch_w, notch_h + 14], radius=52, fill=(4, 5, 7, 255))
# camera lens
cx, cy, r = S // 2, 104, 18
d.ellipse([cx - r - 6, cy - r - 6, cx + r + 6, cy + r + 6], fill=(30, 33, 40, 255))
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(5, 7, 10, 255))
d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(66, 92, 128, 255))

# pixel mascots on the wings (rough blobs with eyes)
def mascot(draw, x, y, body, accent, eye=(255, 255, 255, 255), flip=False):
    draw.rounded_rectangle([x, y, x + 62, y + 56], radius=16, fill=body)
    draw.rectangle([x + 10, y - 14, x + 28, y + 4], fill=accent)
    draw.rectangle([x + 36, y - 8, x + 48, y + 4], fill=accent)
    ex = x + 16 if not flip else x + 40
    draw.rectangle([ex, y + 20, ex + 10, y + 30], fill=eye)
    draw.rectangle([x + 14, y + 42, x + 48, y + 46], fill=accent)

mascot(d, 92, 74, (58, 120, 232, 255), (120, 185, 255, 255))
mascot(d, 176, 82, (98, 190, 110, 255), (230, 205, 90, 255), flip=True)
mascot(d, 786, 82, (238, 190, 70, 255), (255, 232, 130, 255))
mascot(d, 870, 74, (110, 160, 200, 255), (170, 210, 240, 255), flip=True)

# status dots on the bar
def dot(draw, x, y, color):
    draw.ellipse([x - 9, y - 9, x + 9, y + 9], fill=color)

dot(d, 62, 128, (70, 165, 255, 255))
dot(d, 300, 128, (255, 195, 70, 255))
dot(d, S - 62, 128, (90, 225, 155, 255))

# ---- three agent cards below ----
card_w, card_h = 760, 150
card_x = (S - card_w) // 2
cards = [
    (240, (58, 120, 232, 255), (70, 165, 255, 255)),   # running blue
    (430, (238, 190, 70, 255), (255, 195, 70, 255)),   # waiting amber
    (620, (98, 190, 110, 255), (90, 225, 155, 255)),   # done green
]
for (cy, body, status) in cards:
    d.rounded_rectangle([card_x, cy, card_x + card_w, cy + card_h], radius=34, fill=(28, 32, 41, 255))
    d.rounded_rectangle([card_x, cy, card_x + card_w, cy + card_h], radius=34, outline=(255, 255, 255, 22), width=2)
    # mascot
    mascot(d, card_x + 34, cy + 36, body, tuple(min(255, c + 40) for c in body[:3]) + (255,))
    # text bars
    d.rounded_rectangle([card_x + 150, cy + 42, card_x + 430, cy + 70], radius=14, fill=(200, 210, 228, 235))
    d.rounded_rectangle([card_x + 150, cy + 86, card_x + 560, cy + 108], radius=11, fill=(96, 104, 122, 255))
    # status chip
    d.rounded_rectangle([card_x + card_w - 150, cy + 48, card_x + card_w - 46, cy + 96], radius=24, fill=tuple(int(c * 0.22) for c in status[:3]) + (255,))
    d.ellipse([card_x + card_w - 132, cy + 62, card_x + card_w - 112, cy + 82], fill=status)

# inner highlight
border = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(border).rounded_rectangle([3, 3, S - 4, S - 4], radius=225, outline=(255, 255, 255, 26), width=3)
icon = Image.alpha_composite(icon, border)
icon = Image.composite(icon, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)

icon.save(os.path.join(OUT, "icon_1024.png"))

iconset = os.path.join(OUT, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
for size in [16, 32, 64, 128, 256, 512]:
    icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
    icon.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
print("icon written")
