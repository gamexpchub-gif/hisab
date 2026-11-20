"""Draws the GameX launcher icon into tool/android_res/mipmap-*/ic_launcher.png."""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
here = os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, stops, diagonal=True):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = ((x + y) / (2 * size)) if diagonal else y / size
            for i in range(len(stops) - 1):
                p0, c0 = stops[i]
                p1, c1 = stops[i + 1]
                if p0 <= t <= p1:
                    px[x, y] = lerp(c0, c1, (t - p0) / (p1 - p0 or 1))
                    break
    return img


bg = gradient(S, [(0, (0x1B, 0x1F, 0x4B)), (1, (0x0B, 0x0D, 0x24))])
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(bg, (0, 0), mask)

# G ring
ring = gradient(S, [(0, (0x4F, 0xC3, 0xFF)), (0.5, (0x7B, 0x5C, 0xFF)), (1, (0xE0, 0x40, 0xFB))])
gmask = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(gmask)
cx, cy, r, w = 512, 450, 270, 110
d.arc([cx - r, cy - r, cx + r, cy + r], start=40, end=320, fill=255, width=w)
# horizontal bar + short down stroke
d.rounded_rectangle([cx + 10, cy - 10, cx + r + 8, cy + w - 10], radius=40, fill=255)
glow = gmask.filter(ImageFilter.GaussianBlur(28))
glow_layer = Image.new("RGBA", (S, S), (123, 92, 255, 0))
glow_layer.putalpha(glow.point(lambda v: int(v * 0.55)))
icon = Image.alpha_composite(icon, glow_layer)
ring_rgba = ring.convert("RGBA")
ring_rgba.putalpha(gmask)
icon = Image.alpha_composite(icon, ring_rgba)

# label
try:
    font = ImageFont.truetype("DejaVuSans-Bold.ttf", 120)
except OSError:
    font = ImageFont.load_default()
td = ImageDraw.Draw(icon)
tw = td.textlength("GameX", font=font)
td.text(((S - tw) / 2, 790), "GameX", font=font, fill=(255, 255, 255, 255))

for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    out = os.path.join(here, "android_res", f"mipmap-{folder}")
    os.makedirs(out, exist_ok=True)
    icon.resize((px, px), Image.LANCZOS).save(os.path.join(out, "ic_launcher.png"))
icon.resize((512, 512), Image.LANCZOS).save(os.path.join(here, "icon-512.png"))
print("ok")
