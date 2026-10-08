import base64
import json
import math
import sys

import fontTools
import PIL
from fontTools.pens.boundsPen import ControlBoundsPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont, features

OUT = "tests/oracle/outline.json"
SUPERSAMPLE = 8

LATIN = "assets/font.ttf"
CJK = "tests/fonts/NotoSansSC-subset.ttf"
CFF = "tests/fonts/cffSynthetic.otf"

SIZES = [13.0, 26.0]
SHAPES = [(0, 0.0), (0, 0.5), (3, 1.0), (0, 2.0), (2, 3.5)]


def subjects():
    out = [(LATIN, ord(c)) for c in "IgW@Rs"]
    cmap = sorted(TTFont(CJK).getBestCmap())
    out += [(CJK, cmap[len(cmap) // 3]), (CJK, cmap[2 * len(cmap) // 3])]
    out += [(CFF, ord("A"))]
    return out


def bounds(path, codepoint):
    font = TTFont(path)
    name = font.getBestCmap()[codepoint]
    pen = ControlBoundsPen(font.getGlyphSet())
    font.getGlyphSet()[name].draw(pen)
    return font["head"].unitsPerEm, pen.bounds


def render(path, codepoint, size, variant, width):
    units, (xmin, ymin, xmax, ymax) = bounds(path, codepoint)
    scale = size / units
    shift = variant / 4.0
    pad = math.ceil(width) + 2
    left = math.floor(xmin * scale + shift) - pad
    right = math.ceil(xmax * scale + shift) + pad
    top = math.floor(-ymax * scale) - pad
    bottom = math.ceil(-ymin * scale) + pad
    w, h = right - left, bottom - top
    s = SUPERSAMPLE
    image = Image.new("L", (w * s, h * s), 0)
    font = ImageFont.truetype(path, size * s)
    draw = ImageDraw.Draw(image)
    origin = ((shift - left) * s, -top * s)
    draw.text(origin, chr(codepoint), font=font, fill=255, anchor="ls",
              stroke_width=width * s, stroke_fill=255)
    small = image.resize((w, h), Image.BOX)
    return left, top, w, h, small.tobytes()


def regen():
    cases = []
    for path, codepoint in subjects():
        for size in SIZES:
            for variant, width in SHAPES:
                left, top, w, h, data = render(path, codepoint, size, variant, width)
                cases.append({
                    "path": path,
                    "codepoint": codepoint,
                    "size": size,
                    "variant": variant,
                    "width": width,
                    "left": left,
                    "top": top,
                    "w": w,
                    "h": h,
                    "data": base64.b64encode(data).decode("ascii"),
                })
    doc = {
        "generator": "python tests/oracle/outline.py regen",
        "pillow": PIL.__version__,
        "freetype": features.version("freetype2"),
        "fontTools": fontTools.version,
        "supersample": SUPERSAMPLE,
        "cases": cases,
    }
    with open(OUT, "w", newline="\n") as f:
        json.dump(doc, f, separators=(",", ":"))
        f.write("\n")
    print(f"{len(cases)} cases, {sum(len(c['data']) for c in cases)} base64 bytes")


if __name__ == "__main__":
    if sys.argv[1:] != ["regen"]:
        raise SystemExit("usage: python tests/oracle/outline.py regen")
    regen()
