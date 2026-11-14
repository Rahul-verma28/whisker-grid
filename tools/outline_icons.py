"""Adds a soft cartoon silhouette outline + drop shadow to the character icons.
Run after blender/make_characters.py:   python tools/outline_icons.py
"""
import glob
import os
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTLINE = (77, 46, 30)
for path in glob.glob(os.path.join(ROOT, "assets", "characters", "*_icon.png")):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    pad = 16
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    alpha = Image.new("L", canvas.size, 0)
    alpha.paste(im.getchannel("A"), (pad, pad))
    # outline ring: grow the silhouette, then smooth its edge
    ring = alpha.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1.2))
    shadow = alpha.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(6)).point(lambda v: v * 0.35)
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", canvas.size, (60, 30, 20, 255)), (0, 8), shadow)
    out.paste(Image.new("RGBA", canvas.size, OUTLINE + (255,)), (0, 0), ring)
    out.alpha_composite(im, (pad, pad))
    out.save(path)
    print("outlined", os.path.basename(path))
