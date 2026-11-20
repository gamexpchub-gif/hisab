"""Cuts the Products-screen artwork out of tool/reference/products.webp
(851 px wide) into assets/products/*.png. The banner background has its
text and chips removed (OpenCV inpainting) so live values can be drawn on it."""
import os
import numpy as np
from PIL import Image, ImageDraw

try:
    import cv2
except ImportError:  # pip install opencv-python-headless
    cv2 = None

here = os.path.dirname(os.path.abspath(__file__))
src_img = Image.open(os.path.join(here, "reference", "products.webp")).convert("RGBA")
out_dir = os.path.join(here, "..", "assets", "products")
os.makedirs(out_dir, exist_ok=True)
UP = 2


def save(name, img):
    img.resize((img.width * UP, img.height * UP), Image.LANCZOS).save(os.path.join(out_dir, name + ".png"), optimize=True)


def round_mask(img, radius):
    w, h = img.size
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius * 4, fill=255)
    img.putalpha(m.resize((w, h), Image.LANCZOS))
    return img


def circle(name, cx, cy, r, feather=0.12, src=None):
    img = (src or src_img).crop((cx - r, cy - r, cx + r, cy + r))
    w, h = img.size
    y, x = np.mgrid[0:h, 0:w]
    d = np.sqrt(((x + .5 - w / 2) / (w / 2)) ** 2 + ((y + .5 - h / 2) / (h / 2)) ** 2)
    a = np.clip((1 - d) / feather, 0, 1)
    arr = np.array(img)
    arr[..., 3] = (arr[..., 3] * a).astype(np.uint8)
    save(name, Image.fromarray(arr))


# ---- small icons (before the banner is cleaned)
circle("chip_chart", 92, 260, 14, 0.25)
circle("cube_small", 88, 396, 20, 0.2)

# ---- banner background with text removed
box = (35, 205, 823, 443)
rgb = np.array(src_img.convert("RGB"))
if cv2 is not None:
    mask = np.zeros(rgb.shape[:2], np.uint8)
    for (x0, y0, x1, y1) in [(58, 233, 300, 287), (60, 292, 272, 372), (62, 372, 292, 421),
                             (684, 222, 814, 291), (686, 287, 812, 320)]:
        mask[y0:y1, x0:x1] = 255
    rgb = cv2.inpaint(rgb, mask, 9, cv2.INPAINT_TELEA)
    # the left/top-right of the banner is a smooth gradient: replace the
    # repaired areas with a heavily blurred version so no blotches remain
    soft = cv2.GaussianBlur(rgb, (0, 0), 28)
    k = cv2.GaussianBlur(cv2.dilate(mask, np.ones((25, 25), np.uint8)).astype(np.float32) / 255, (0, 0), 10)
    region = np.zeros_like(k)
    region[205:443, 35:430] = 1  # left text column
    region[205:330, 670:823] = 1  # +12% chip corner
    region = cv2.GaussianBlur(region, (0, 0), 12)
    w = np.clip(np.maximum(k, region * 0.0) * region + k * (region > 0.98), 0, 1)
    w = np.clip(np.maximum(w, region * (rgb.mean(2) > 0) * 0) , 0, 1)
    left = np.zeros_like(k); left[205:443, 35:400] = 1; left = cv2.GaussianBlur(left, (0, 0), 14)
    w = np.maximum(w, left)
    rgb = (rgb * (1 - w[..., None]) + soft * w[..., None]).astype(np.uint8)
banner = Image.fromarray(rgb).convert("RGBA").crop(box)
save("banner_bg", round_mask(banner, 40))

# ---- stat tile orbs
for name, cx in [("orb_out", 126), ("orb_low", 327), ("orb_in", 528), ("orb_alert", 728)]:
    circle(name, cx, 512, 40)

# ---- product tile placeholders (iPhone, MacBook, AirPods)
tile_bg = tuple(np.median(rgb[1300:1310, 70:190].reshape(-1, 3), 0).astype(int))
save("tile_mobile", round_mask(src_img.crop((58, 1128, 203, 1293)), 22))
def padded(box, top_pad):
    t = Image.new("RGBA", (145, 165), tile_bg + (255,))
    t.paste(src_img.crop(box), (0, top_pad))
    return round_mask(t, 22)


save("tile_laptop", padded((58, 1356, 203, 1506), 7))
save("tile_accessory", padded((58, 1563, 203, 1682), 14))

# ---- navigation cube icon
circle("nav_cube", 528, 1750, 24, 0.15)
print("assets written to", os.path.abspath(out_dir))
