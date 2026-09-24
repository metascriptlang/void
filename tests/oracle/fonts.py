import json
import sys

import fontTools
import uharfbuzz as hb
from fontTools.ttLib import TTFont

FONTS = [
    "assets/font.ttf",
    "tests/fonts/NotoSansSC-subset.ttf",
    "tests/fonts/zeroedDecorations.ttf",
    "tests/fonts/zeroThickness.ttf",
]

SHAPE_ROWS = [
    ("assets/font.ttf", "AV"),
    ("assets/font.ttf", "AVA"),
    ("assets/font.ttf", "To Ty Wa Yo"),
    ("assets/font.ttf", "LT P. F, r."),
    ("assets/font.ttf", "Hello, World"),
    ("assets/font.ttf", "Type 1.0 AVAWAY"),
    ("assets/font.ttf", "fn main() { return 42; }"),
    ("assets/font.ttf", "The quick brown fox jumps over the lazy dog"),
    ("tests/fonts/NotoSansSC-subset.ttf", "你好世界"),
    ("tests/fonts/NotoSansSC-subset.ttf", "AV To，。（）"),
]

GSUB_OFF = ["ccmp", "locl", "rlig", "rclt", "calt", "clig", "liga", "dlig"]


def glyphBox(font, name):
    glyph = font["glyf"][name]
    if getattr(glyph, "numberOfContours", 0) == 0:
        return None
    return glyph.xMin, glyph.yMin, glyph.xMax, glyph.yMax


def glyphHeight(font, codepoint):
    name = font.getBestCmap().get(codepoint)
    box = glyphBox(font, name) if name else None
    return float(box[3] - box[1]) if box else 0.0


def asciiExtent(font):
    cmap = font.getBestCmap()
    top, bottom, widest = 0, 0, 0
    for c in range(32, 127):
        name = cmap.get(c)
        if not name:
            continue
        widest = max(widest, font["hmtx"][name][0])
        box = glyphBox(font, name)
        if box:
            top = max(top, box[3])
            bottom = min(bottom, box[1])
    return float(top - bottom), float(widest)


def ideographWidth(font):
    name = font.getBestCmap().get(0x6C34)
    if not name:
        return 0.0
    advance = font["hmtx"][name][0]
    box = glyphBox(font, name)
    if box and box[2] - box[0] > advance:
        return 0.0
    return float(advance)


def metrics(path):
    font = TTFont(path)
    hhea = font["hhea"]
    os2 = font["OS/2"] if "OS/2" in font else None
    post = font["post"] if "post" in font else None
    ascent, descent, lineGap = hhea.ascent, hhea.descent, hhea.lineGap

    if os2 is not None and os2.version >= 2:
        cap, ex = float(os2.sCapHeight), float(os2.sxHeight)
    else:
        cap, ex = glyphHeight(font, ord("H")), glyphHeight(font, ord("x"))
    capEstimate = cap if cap > 0 else 0.75 * ascent
    exEstimate = ex if ex > 0 else 0.75 * capEstimate
    ic = ideographWidth(font)
    asciiHeight, cellWidth = asciiExtent(font)
    if asciiHeight <= 0:
        asciiHeight = 1.5 * capEstimate
    icEstimate = ic if ic > 0 else min(asciiHeight, 2 * cellWidth)

    underlinePosition = post.underlinePosition if post else 0
    underlineSize = post.underlineThickness if post else 0
    underlineThickness = float(underlineSize) if underlineSize > 0 else 0.15 * exEstimate
    brokenUnderline = post is None or (underlineSize == 0 and underlinePosition == 0)
    underlineTop = -underlineThickness if brokenUnderline else float(underlinePosition)

    strikeSize = os2.yStrikeoutSize if os2 is not None else 0
    strikePosition = os2.yStrikeoutPosition if os2 is not None else 0
    strikeThickness = float(strikeSize) if strikeSize > 0 else underlineThickness
    brokenStrike = os2 is None or (strikeSize == 0 and strikePosition == 0)
    strikeTop = (exEstimate + strikeThickness) * 0.5 if brokenStrike else float(strikePosition)

    return {
        "path": path,
        "unitsPerEm": font["head"].unitsPerEm,
        "ascent": float(ascent),
        "descent": float(-descent),
        "lineGap": float(lineGap),
        "underlineTop": -underlineTop,
        "underlineThickness": underlineThickness,
        "strikethroughTop": -strikeTop,
        "strikethroughThickness": strikeThickness,
        "icWidth": ic,
        "exHeight": max(ex, 0.0),
        "capHeight": max(cap, 0.0),
        "icWidthEstimate": icEstimate,
        "exHeightEstimate": exEstimate,
        "capHeightEstimate": capEstimate,
        "lineHeight": float(ascent - descent + lineGap),
    }


def shape(path, text):
    blob = hb.Blob.from_file_path(path)
    face = hb.Face(blob)
    font = hb.Font(face)
    buffer = hb.Buffer()
    buffer.add_str(text)
    buffer.guess_segment_properties()
    features = {tag: False for tag in GSUB_OFF}
    features["kern"] = True
    hb.shape(font, buffer, features)
    glyphs, xs, pen = [], [], 0
    for info, pos in zip(buffer.glyph_infos, buffer.glyph_positions):
        glyphs.append(info.codepoint)
        xs.append(pen + pos.x_offset)
        pen += pos.x_advance
    return {"path": path, "text": text, "unitsPerEm": face.upem, "glyphs": glyphs, "x": xs}


def write(path, value):
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        json.dump(value, out, ensure_ascii=False, indent=1)
        out.write("\n")


if __name__ == "__main__":
    if sys.argv[1:] != ["regen"]:
        print("usage: python tests/oracle/fonts.py regen")
        sys.exit(2)
    write("tests/oracle/metrics.json", {
        "generator": "python tests/oracle/fonts.py regen",
        "fontTools": fontTools.version,
        "fonts": [metrics(path) for path in FONTS],
    })
    write("tests/oracle/shape.json", {
        "generator": "python tests/oracle/fonts.py regen",
        "harfbuzz": hb.version_string(),
        "features": "every GSUB feature off, kern on",
        "rows": [shape(path, text) for path, text in SHAPE_ROWS],
    })
