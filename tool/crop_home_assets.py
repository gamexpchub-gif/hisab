"""Cuts the home-screen illustrations out of the reference design
(tool/reference/home.webp) into assets/home/*.png with soft alpha edges.
Coordinates are pixels in the 849px-wide reference screenshot."""
import os
import numpy as np
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
src = Image.open(os.path.join(here, "reference", "home.webp")).convert("RGBA")
out_dir = os.path.join(here, "..", "assets", "home")
os.makedirs(out_dir, exist_ok=True)
UP = 2  # upscale for smoother rendering on high-density screens


def save(name, img):
    img = img.resize((img.width * UP, img.height * UP), Image.LANCZOS)
    img.save(os.path.join(out_dir, name + ".png"), optimize=True)


def ellipse(name, box, feather=0.18):
    """Elliptical crop whose edge fades out (keeps glow & shadows)."""
    img = src.crop(box)
    w, h = img.size
    y, x = np.mgrid[0:h, 0:w]
    d = np.sqrt(((x + .5 - w / 2) / (w / 2)) ** 2 + ((y + .5 - h / 2) / (h / 2)) ** 2)
    a = np.clip((1 - d) / feather, 0, 1)
    arr = np.array(img)
    arr[..., 3] = (arr[..., 3] * a).astype(np.uint8)
    save(name, Image.fromarray(arr))


def circle(name, cx, cy, r, feather=0.12):
    ellipse(name, (cx - r, cy - r, cx + r, cy + r), feather)


def rounded(name, box, radius):
    img = src.crop(box)
    w, h = img.size
    m = Image.new("L", (w * 4, h * 4), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius * 4, fill=255)
    img.putalpha(m.resize((w, h), Image.LANCZOS))
    save(name, img)


def fade_left(name, box, fade):
    img = src.crop(box)
    arr = np.array(img)
    w = arr.shape[1]
    ramp = np.clip(np.arange(w) / fade, 0, 1)
    arr[..., 3] = (arr[..., 3] * ramp[None, :]).astype(np.uint8)
    save(name, Image.fromarray(arr))


rounded("logo", (31, 88, 131, 189), 20)
ellipse("wave", (50, 247, 108, 302), 0.25)
fade_left("hero", (478, 198, 849, 353), 70)
# stat card illustrations
ellipse("cart", (278, 398, 412, 528))
ellipse("box", (692, 400, 812, 528))
ellipse("calendar", (288, 608, 402, 732))
ellipse("moneybag", (690, 606, 808, 732))
# stat card head icons
circle("ic_sales", 82, 417, 25)
circle("ic_purchase", 483, 416, 25)
circle("ic_yesterday", 82, 628, 24)
circle("ic_due", 486, 628, 24)
# pill icons
circle("pill_sales", 84, 524, 12, 0.3)
circle("pill_purchase", 482, 524, 12, 0.3)
circle("pill_yesterday", 81, 734, 12, 0.3)
circle("pill_due", 484, 734, 12, 0.3)
# quick action orbs
for name, cx, cy in [("qa_purchase", 125, 847), ("qa_ledger", 327, 849), ("qa_product", 526, 849),
                     ("qa_expense", 726, 849), ("qa_sales", 125, 1001), ("qa_customer", 327, 1002),
                     ("qa_supplier", 526, 1002), ("qa_bank", 726, 1002)]:
    circle(name, cx, cy, 44)
# overview, activity, grow
ellipse("ov_icon", (58, 1135, 94, 1170), 0.25)
ellipse("ov_art", (660, 1180, 790, 1295), 0.2)
circle("clock", 79, 1459, 23, 0.15)
circle("act_cart", 95, 1522, 42)
ellipse("rocket", (50, 1590, 145, 1680), 0.2)
print("assets written to", os.path.abspath(out_dir))
