import base64
import hashlib
import json
import math
import sys
from pathlib import Path

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


def capture(request_path, output_path):
    request = Path(request_path).read_bytes()
    if len(request) > 65536:
        raise ValueError("outline capture requests exceed 65536 bytes")
    lines = request.decode("utf-8").splitlines()
    digest = hashlib.sha256(Path(LATIN).read_bytes()).hexdigest()
    if not lines or lines[0] != f"FONT|{digest}|{SUPERSAMPLE}":
        raise ValueError("outline capture font digest or supersampling differs")
    if not 0 < len(lines) - 1 <= 512:
        raise ValueError("outline capture needs 1..512 masks")
    font = TTFont(LATIN)
    cmap = font.getBestCmap()
    masks = []
    seen = set()
    for line in lines[1:]:
        parts = line.split("|")
        if len(parts) != 6 or parts[0] != "MASK":
            raise ValueError(f"invalid outline capture request: {line}")
        key = "|".join(parts[1:])
        if key in seen:
            raise ValueError(f"duplicate outline capture request: {key}")
        seen.add(key)
        codepoint, glyph = int(parts[1]), int(parts[2])
        size, variant, width = float(parts[3]), int(parts[4]), float(parts[5])
        if not math.isfinite(size) or not 0 < size <= 256:
            raise ValueError(f"outline capture reference size outside (0,256]: {key}")
        if variant not in range(4) or not math.isfinite(width) or not 0 <= width <= 32:
            raise ValueError(f"outline capture variant or stroke outside range: {key}")
        if codepoint not in cmap or font.getGlyphID(cmap[codepoint]) != glyph:
            raise ValueError(f"outline capture cmap does not name glyph {glyph}: U+{codepoint:04X}")
        _, box = bounds(LATIN, codepoint)
        if box is None:
            if codepoint != 32:
                raise ValueError(f"unexpected empty outline capture glyph: U+{codepoint:04X}")
            left, top, w, h, data = 0, 0, 0, 0, b""
        else:
            left, top, w, h, data = render(LATIN, codepoint, size, variant, width)
        masks.append({"key": key, "left": left, "top": top, "w": w, "h": h,
                      "data": base64.b64encode(data).decode("ascii")})
    doc = {"format": 1, "fontSha256": digest, "supersample": SUPERSAMPLE,
           "pillow": PIL.__version__, "freetype": features.version("freetype2"),
           "fontTools": fontTools.version,
           "generatorSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
           "requestSha256": hashlib.sha256(request).hexdigest(), "masks": masks}
    Path(output_path).write_text(json.dumps(doc, separators=(",", ":")) + "\n",
                                 encoding="utf-8", newline="\n")
    print(f"{len(masks)} capture masks, {sum(len(m['data']) for m in masks)} base64 bytes")


if __name__ == "__main__":
    if sys.argv[1:] == ["regen"]:
        regen()
    elif len(sys.argv) == 4 and sys.argv[1] == "capture":
        capture(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit("usage: python tests/oracle/outline.py regen | capture requests.txt output.json")
