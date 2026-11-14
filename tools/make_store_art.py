"""Builds every Play Store / Android graphic from the Blender renders.
   python tools/make_store_art.py            (icons + feature graphic)
   python tools/make_store_art.py shots      (also frames store/raw_shots/*.png into store screenshots)
Outputs:
  assets/android/icon_192.png, adaptive_fg_432.png, adaptive_bg_432.png, adaptive_mono_432.png
  store/icon_512.png, store/feature_graphic_1024x500.png, store/screenshots/*.png
"""
import glob
import math
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "store")
ANDROID = os.path.join(ROOT, "assets", "android")
CHARS = os.path.join(ROOT, "assets", "characters")
FONT = os.path.join(ROOT, "assets", "fonts", "Fredoka.ttf")
os.makedirs(ANDROID, exist_ok=True)
os.makedirs(os.path.join(STORE, "screenshots"), exist_ok=True)

ORANGE = (240, 138, 44)
CREAM = (251, 241, 228)
INK = (74, 58, 53)
TILES = [(242, 155, 178), (143, 209, 158), (245, 200, 92), (140, 184, 238), (185, 155, 230), (245, 164, 107)]


def font(size, weight=650):
    f = ImageFont.truetype(FONT, size)
    try:
        axes = f.get_variation_axes()
        f.set_variation_by_axes([weight if a["name"] in (b"Weight", "Weight") else a["default"] for a in axes])
    except Exception:
        pass
    return f


def gradient(w, h, top, bottom, radial=False):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if radial:
                t = min(1.0, math.hypot(x - w / 2, y - h / 2) / (0.72 * max(w, h)))
            else:
                t = y / (h - 1)
            px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return img.convert("RGBA")


def tiles(img, step, size, alpha, rot=0.0, offset=(0, 0)):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = img.size
    k = 0
    for r in range(-1, h // step + 2):
        for c in range(-1, w // step + 2):
            x = c * step + (r % 2) * step // 2 + offset[0]
            y = r * step + offset[1]
            col = TILES[(r * 3 + c * 5) % len(TILES)]
            d.rounded_rectangle([x, y, x + size, y + size], radius=size // 4, fill=col + (alpha,))
            k += 1
    if rot:
        layer = layer.rotate(rot, resample=Image.BICUBIC)
    return Image.alpha_composite(img, layer)


def shadow(im, radius=14, offset=(0, 10), opacity=0.35):
    a = im.getchannel("A").point(lambda v: int(v * opacity))
    s = Image.new("RGBA", im.size, (60, 30, 15, 0))
    s.putalpha(a)
    s = s.filter(ImageFilter.GaussianBlur(radius))
    out = Image.new("RGBA", (im.width + abs(offset[0]) * 2, im.height + abs(offset[1]) * 2), (0, 0, 0, 0))
    out.alpha_composite(s, (abs(offset[0]) + offset[0], abs(offset[1]) + offset[1]))
    out.alpha_composite(im, (abs(offset[0]), abs(offset[1])))
    return out


def crop_alpha(im, pad=8):
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    l, t, r, b = bbox
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, b + pad)))


def fit(im, w, h):
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def text_outline(d, xy, text, f, fill, outline, width, anchor="la"):
    d.text(xy, text, font=f, fill=fill, anchor=anchor, stroke_width=width, stroke_fill=outline)


def pop(im, sat=1.25, con=1.08):
    rgb = im.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Contrast(rgb).enhance(con)
    out = rgb.convert("RGBA")
    out.putalpha(im.getchannel("A"))
    return out


# ================================================================ icons

def icon_background(size):
    bg = gradient(size, size, (255, 190, 110), (238, 120, 40), radial=True)
    return tiles(bg, step=size // 4, size=size // 6, alpha=38, rot=12)


def make_icons():
    cat = Image.open(os.path.join(CHARS, "cat_icon.png")).convert("RGBA")
    cat = crop_alpha(cat, 2)
    # Play Store icon 512 (full bleed square; Play applies the rounded mask itself)
    icon = icon_background(512)
    head = shadow(fit(cat, 430, 430), 12, (0, 10), 0.35)
    icon.alpha_composite(head, ((512 - head.width) // 2, (512 - head.height) // 2 + 8))
    icon.convert("RGB").save(os.path.join(STORE, "icon_512.png"))
    icon.resize((192, 192), Image.LANCZOS).save(os.path.join(ANDROID, "icon_192.png"))
    # adaptive icon layers (432; the visible safe zone is the middle ~66%)
    icon_background(432).save(os.path.join(ANDROID, "adaptive_bg_432.png"))
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    head = shadow(fit(cat, 270, 270), 8, (0, 6), 0.3)
    fg.alpha_composite(head, ((432 - head.width) // 2, (432 - head.height) // 2 + 4))
    fg.save(os.path.join(ANDROID, "adaptive_fg_432.png"))
    mono = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    m = fit(cat, 270, 270).getchannel("A")
    white = Image.new("RGBA", m.size, (255, 255, 255, 255))
    white.putalpha(m)
    mono.alpha_composite(white, ((432 - m.width) // 2, (432 - m.height) // 2))
    mono.save(os.path.join(ANDROID, "adaptive_mono_432.png"))
    print("icons done")


# ================================================================ feature graphic

def make_feature():
    W, H = 1024, 500
    fg = gradient(W, H, (255, 236, 214), (252, 205, 160))
    fg = tiles(fg, step=96, size=60, alpha=45, rot=-8)
    d = ImageDraw.Draw(fg)
    # title block
    text_outline(d, (60, 120), "Whisker", font(112, 700), ORANGE, (255, 255, 255), 8)
    text_outline(d, (60, 230), "Grid", font(112, 700), ORANGE, (255, 255, 255), 8)
    d.text((66, 365), "Find the hidden friends!", font=font(36, 560), fill=INK)
    x = 66
    for label, col in (("100 levels", (143, 209, 158)), ("Daily puzzle", (140, 184, 238)), ("3D friends", (242, 155, 178))):
        f = font(24, 600)
        w = d.textlength(label, font=f)
        d.rounded_rectangle([x, 420, x + w + 32, 460], radius=20, fill=col)
        d.text((x + 16, 440), label, font=f, fill=(255, 255, 255), anchor="lm")
        x += w + 46
    # mini board behind the characters
    bx, by, cs = 610, 70, 70
    board = Image.new("RGBA", (cs * 5 + 24, cs * 5 + 24), (0, 0, 0, 0))
    bd = ImageDraw.Draw(board)
    bd.rounded_rectangle([0, 0, board.width - 1, board.height - 1], radius=30, fill=(255, 250, 243, 235))
    regions = [[0, 0, 1, 1, 1], [0, 2, 2, 1, 3], [4, 2, 2, 3, 3], [4, 4, 5, 5, 3], [4, 5, 5, 5, 3]]
    for r in range(5):
        for c in range(5):
            x0, y0 = 12 + c * cs + 4, 12 + r * cs + 4
            bd.rounded_rectangle([x0, y0, x0 + cs - 8, y0 + cs - 8], radius=14, fill=TILES[regions[r][c]])
    board = board.rotate(-6, resample=Image.BICUBIC, expand=True)
    fg.alpha_composite(shadow(board, 14, (0, 10), 0.25), (bx, by - 30))
    # the four friends
    spots = [("bunny", 730, 18, 290), ("mouse", 868, 140, 240), ("dog", 575, 165, 255), ("cat", 700, 150, 320)]
    for cid, x, y, h in spots:
        im = pop(crop_alpha(Image.open(os.path.join(STORE, "art", f"{cid}_full.png")).convert("RGBA")))
        im = shadow(fit(im, h, h), 10, (0, 8), 0.3)
        fg.alpha_composite(im, (x, y))
    fg.convert("RGB").save(os.path.join(STORE, "feature_graphic_1024x500.png"))
    print("feature graphic done")


# ================================================================ screenshots

CAPTIONS = {
    "1_board": ("Find the hidden friends", "One per row, column & colour"),
    "2_levels": ("100 levels", "From easy 4×4 to genius 10×10"),
    "3_win": ("Celebrate every win", "Earn up to 3 stars per level"),
    "4_friends": ("Unlock cute friends", "Cat, dog, bunny & mouse"),
    "5_night": ("Pick your cozy theme", "Four themes, day or night"),
    "6_home": ("A new puzzle every day", "Relaxing music, no timers to beat"),
}


def make_shots():
    raw = sorted(glob.glob(os.path.join(STORE, "raw_shots", "*.png")))
    W, H = 1080, 1920
    for path in raw:
        key = os.path.splitext(os.path.basename(path))[0]
        if key not in CAPTIONS:
            continue
        night = key == "5_night"
        bg = gradient(W, H, (40, 48, 92) if night else (255, 226, 196), (24, 30, 62) if night else (250, 186, 128))
        bg = tiles(bg, step=150, size=90, alpha=30 if night else 45, rot=-8)
        d = ImageDraw.Draw(bg)
        title, sub = CAPTIONS[key]
        text_outline(d, (W // 2, 150), title, font(86, 700), (255, 173, 77) if night else ORANGE, (255, 255, 255) if not night else (28, 34, 64), 6, "mm")
        d.text((W // 2, 245), sub, font=font(46, 520), fill=(240, 236, 230) if night else INK, anchor="mm")
        shot = Image.open(path).convert("RGBA")
        shot = fit(shot, 860, 1560)
        mask = Image.new("L", shot.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius=54, fill=255)
        framed = Image.new("RGBA", (shot.width + 28, shot.height + 28), (0, 0, 0, 0))
        ImageDraw.Draw(framed).rounded_rectangle([0, 0, framed.width - 1, framed.height - 1], radius=66, fill=(40, 30, 28, 255))
        shot.putalpha(mask)
        framed.alpha_composite(shot, (14, 14))
        framed = shadow(framed, 24, (0, 18), 0.4)
        bg.alpha_composite(framed, ((W - framed.width) // 2, 320))
        bg.convert("RGB").save(os.path.join(STORE, "screenshots", f"{key}.png"))
        print("screenshot", key)


make_icons()
make_feature()
if "shots" in sys.argv:
    make_shots()
