import io
import json
import math
import sys

import fontTools
import PIL
from fontTools.ttLib import TTFont
from PIL import Image

OUT = "tests/oracle/colour.json"

CBDT_FONTS = [
    ("tests/fonts/NotoColorEmoji-subset.ttf", [6, 13, 13.5, 16, 24, 54.5, 109, 140]),
    ("tests/fonts/cbdtSynthetic.ttf", [4, 8, 12, 16, 24, 40]),
]

FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3


def fnv(data):
    h = FNV_OFFSET
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h


def premultiplied(c, a):
    return (c * a + 127) // 255


def decode(png):
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    width, height = image.size
    data = image.tobytes()
    texels = []
    for i in range(width * height):
        r, g, b, a = data[4 * i:4 * i + 4]
        texels.append((premultiplied(r, a), premultiplied(g, a), premultiplied(b, a), a))
    return width, height, texels


def areaAverage(texels, sw, sh, dw, dh):
    total = sw * sh
    out = []
    for oy in range(dh):
        y0, y1 = oy * sh, oy * sh + sh
        for ox in range(dw):
            x0, x1 = ox * sw, ox * sw + sw
            sums = [0, 0, 0, 0]
            for iy in range(y0 // dh, (y1 - 1) // dh + 1):
                wy = min(y1, (iy + 1) * dh) - max(y0, iy * dh)
                for ix in range(x0 // dw, (x1 - 1) // dw + 1):
                    wx = min(x1, (ix + 1) * dw) - max(x0, ix * dw)
                    texel = texels[iy * sw + ix]
                    for c in range(4):
                        sums[c] += wx * wy * texel[c]
            out.append(tuple((sums[c] + total // 2) // total for c in range(4)))
    return out


def scaled(value, size, ppem):
    return math.floor(value * size / ppem + 0.5)


def word(texel):
    return texel[0] | (texel[1] << 8) | (texel[2] << 16) | (texel[3] << 24)


def chooseStrike(candidates, size):
    bigger = [c for c in candidates if c["ppem"] >= size]
    if bigger:
        return min(bigger, key=lambda c: c["ppem"])
    return max(candidates, key=lambda c: c["ppem"])


def cbdtGlyphs(font):
    cblc, cbdt = font["CBLC"], font["CBDT"]
    byName = {}
    for index, strike in enumerate(cblc.strikes):
        ppem = strike.bitmapSizeTable.ppemY
        for name, bitmap in cbdt.strikeData[index].items():
            m = bitmap.metrics
            byName.setdefault(name, []).append({
                "ppem": ppem,
                "png": bitmap.imageData,
                "width": m.width,
                "height": m.height,
                "bearingX": m.BearingX if hasattr(m, "BearingX") else m.horiBearingX,
                "bearingY": m.BearingY if hasattr(m, "BearingY") else m.horiBearingY,
            })
    return byName


def tileRow(strike, size):
    width = max(1, scaled(strike["width"], size, strike["ppem"]))
    height = max(1, scaled(strike["height"], size, strike["ppem"]))
    left = scaled(strike["bearingX"], size, strike["ppem"])
    top = -scaled(strike["bearingY"], size, strike["ppem"])
    sw, sh, texels = decode(strike["png"])
    assert (sw, sh) == (strike["width"], strike["height"])
    tile = areaAverage(texels, sw, sh, width, height)
    raw = bytes(v for texel in tile for v in texel)
    points = [(0, 0), (width - 1, 0), (width // 2, height // 2), (width - 1, height - 1),
              (width // 3, height // 3), (width // 4, 3 * height // 4)]
    return {
        "size": size,
        "ppem": strike["ppem"],
        "left": left,
        "top": top,
        "right": left + width,
        "bottom": top + height,
        "hash": format(fnv(raw), "016x"),
        "samples": [[x, y, word(tile[y * width + x])] for x, y in points],
    }


def cbdtFont(path, sizes):
    font = TTFont(path)
    cmap = font.getBestCmap()
    glyphs = cbdtGlyphs(font)
    order = font.getGlyphOrder()
    rows = []
    for codepoint, name in sorted(cmap.items()):
        if name not in glyphs:
            continue
        candidates = glyphs[name]
        rows.append({
            "codepoint": codepoint,
            "glyph": order.index(name),
            "advance": font["hmtx"].metrics[name][0],
            "strikes": sorted(c["ppem"] for c in candidates),
            "tiles": [tileRow(chooseStrike(candidates, size), size) for size in sizes],
        })
    return {
        "path": path,
        "unitsPerEm": font["head"].unitsPerEm,
        "ascent": font["hhea"].ascent,
        "descent": font["hhea"].descent,
        "glyphs": rows,
    }


SBIX_FONTS = [
    ("tests/fonts/sbixSynthetic.ttf", [6, 12, 18, 24, 40]),
]


def sbixCandidates(font, name):
    strikes = font["sbix"].strikes
    found, refused = [], False
    for ppem, strike in strikes.items():
        glyph = strike.glyphs.get(name)
        hops = 0
        while glyph is not None and glyph.graphicType == "dupe":
            hops += 1
            assert hops < 8
            glyph = strike.glyphs.get(glyph.referenceGlyphName)
        if glyph is None or not glyph.graphicType:
            continue
        if glyph.graphicType != "png ":
            refused = True
            continue
        width, height = Image.open(io.BytesIO(glyph.imageData)).size
        found.append({
            "ppem": ppem,
            "png": glyph.imageData,
            "width": width,
            "height": height,
            "bearingX": glyph.originOffsetX,
            "bearingY": glyph.originOffsetY + height,
        })
    return found, refused


def sbixFont(path, sizes):
    font = TTFont(path)
    order = font.getGlyphOrder()
    rows = []
    for codepoint, name in sorted(font.getBestCmap().items()):
        found, refused = sbixCandidates(font, name)
        tiles = []
        for size in sizes:
            if found:
                tile = tileRow(chooseStrike(found, size), size)
                tile["status"] = "present"
            else:
                tile = {"size": size, "status": "refused" if refused else "absent"}
            tiles.append(tile)
        rows.append({
            "codepoint": codepoint,
            "glyph": order.index(name),
            "advance": font["hmtx"].metrics[name][0],
            "tiles": tiles,
        })
    return {"path": path, "unitsPerEm": font["head"].unitsPerEm, "glyphs": rows}


def regen():
    document = {
        "generator": "python tests/oracle/colour.py regen",
        "fontTools": fontTools.version,
        "pillow": PIL.__version__,
        "cbdt": [cbdtFont(path, sizes) for path, sizes in CBDT_FONTS],
        "sbix": [sbixFont(path, sizes) for path, sizes in SBIX_FONTS],
    }
    with open(OUT, "w", newline="\n") as handle:
        json.dump(document, handle, indent=1)
        handle.write("\n")


if __name__ == "__main__":
    if sys.argv[1:] != ["regen"]:
        sys.exit("usage: python tests/oracle/colour.py regen")
    regen()
