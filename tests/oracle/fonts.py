import json
import re
import sys

import fontTools
import uharfbuzz as hb
from fontTools.ttLib import TTCollection, TTFont

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


SHAPE_CASES = "tests/oracle/shape.rows"
DIRECTIONS = {"auto": 0, "ltr": 1, "rtl": 2}


def unescape(text):
    return re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), text)


def readCases(path):
    rows = []
    with open(path, encoding="utf-8") as source:
        for line in source:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            ident, font, direction, features, text = line.split("\t")
            if direction not in DIRECTIONS:
                sys.exit(f"{path}: {ident}: direction {direction} is not auto, ltr or rtl")
            rows.append((ident, font, direction, features, unescape(text)))
    ids = [row[0] for row in rows]
    if len(set(ids)) != len(ids):
        sys.exit(f"{path}: an id appears twice")
    return rows


def parseFeatures(spec):
    out = []
    if spec == "-":
        return out
    for token in spec.split():
        if token.startswith("-"):
            out.append([token[1:], 0])
        elif token.startswith("+"):
            out.append([token[1:], 1])
        elif "=" in token:
            tag, value = token.split("=")
            out.append([tag, int(value)])
        else:
            sys.exit(f"feature token {token!r} is not -tag, +tag or tag=N")
    return out


def shapeFull(ident, path, direction, spec, text):
    blob = hb.Blob.from_file_path(path)
    face = hb.Face(blob)
    font = hb.Font(face)
    codepoints = [ord(c) for c in text]
    cmap = TTFont(path).getBestCmap()
    missing = [hex(c) for c in codepoints if c not in cmap]
    if missing and not ident.startswith("missing-"):
        sys.exit(f"{SHAPE_CASES}: {ident}: {path} has no glyph for {missing}; "
                 f"a row that wants the missing glyph is named missing-...")
    features = parseFeatures(spec)
    buffer = hb.Buffer()
    buffer.add_codepoints(codepoints)
    buffer.guess_segment_properties()
    if direction != "auto":
        buffer.direction = direction
    hb.shape(font, buffer, {tag: value for tag, value in features})
    glyphs = []
    for info, pos in zip(buffer.glyph_infos or [], buffer.glyph_positions or []):
        glyphs.append([info.codepoint, info.cluster, pos.x_advance, pos.y_advance,
                       pos.x_offset, pos.y_offset])
    return {
        "id": ident,
        "path": path,
        "codepoints": codepoints,
        "features": features,
        "direction": DIRECTIONS[direction],
        "runDirection": buffer.direction,
        "unitsPerEm": face.upem,
        "glyphs": glyphs,
    }


COVERAGE_FONTS = [
    "assets/font.ttf",
    "tests/fonts/NotoSansSC-subset.ttf",
    "tests/fonts/NotoColorEmoji-subset.ttf",
    "tests/fonts/textSymbol.ttf",
    "tests/fonts/cbdtSynthetic.ttf",
    "tests/fonts/sbixSynthetic.ttf",
    "tests/fonts/colrSynthetic.ttf",
    "tests/fonts/symbolCollection.ttc",
]

ABSENT = [0x0, 0x1, 0x378, 0xE01, 0xFFFF, 0x2764, 0x1F600, 0x1F9FF, 0x10FFFF]


def firstFont(path):
    if path.endswith(".ttc"):
        return TTCollection(path).fonts[0]
    return TTFont(path)


def covered(font):
    cmap = font.getBestCmap() or {}
    return sorted(c for c, name in cmap.items() if font.getGlyphID(name) != 0)


def spans(codepoints):
    out = []
    for c in codepoints:
        if out and out[-1][1] == c - 1:
            out[-1][1] = c
        else:
            out.append([c, c])
    return out


def sequences(font):
    rows = []
    for table in font["cmap"].tables:
        if table.format != 14:
            continue
        for selector, pairs in sorted(table.uvsDict.items()):
            for codepoint, glyph in sorted(pairs):
                rows.append([selector, codepoint, 1 if glyph is None else 2])
    return rows


def coverage(path):
    font = firstFont(path)
    have = set(covered(font))
    tables = set(font.keys())
    outlines = ("loca" in tables) if "glyf" in tables else ("CFF " in tables)
    return {
        "path": path,
        "drawable": bool({"cmap", "head", "hhea", "hmtx"} <= tables and outlines),
        "colourBitmap": bool({"CBDT", "CBLC"} <= tables or "sbix" in tables),
        "colourLayers": bool({"COLR", "CPAL"} <= tables),
        "ranges": spans(sorted(have)),
        "absent": [c for c in ABSENT if c not in have],
        "sequences": sequences(font),
    }


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
    write("tests/oracle/shapeFull.json", {
        "generator": "python tests/oracle/fonts.py regen",
        "harfbuzz": hb.version_string(),
        "features": "the font's defaults plus each row's overrides, from tests/oracle/shape.rows",
        "rows": [shapeFull(*row) for row in readCases(SHAPE_CASES)],
    })
    write("tests/oracle/coverage.json", {
        "generator": "python tests/oracle/fonts.py regen",
        "fontTools": fontTools.version,
        "fonts": [coverage(path) for path in COVERAGE_FONTS],
    })
