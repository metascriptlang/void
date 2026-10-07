import io
import struct
import sys
import zlib

from fontTools import subset
from fontTools.colorLib.builder import buildCOLR, buildCPAL
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, TTFont
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

OUT = "tests/fonts/"
PINNED = 3786825600
NOTO_CHARS = [0x1F600, 0x1F44D, 0x2764, 0x1F680, 0x1F389, 0x23, 0xFE0F, 0x200D]
UPEM = 1000
RED = 0xCC3333
BLUE = 0x3366CC
WHITE = 0xFFFFFF


def rgba(value):
    return ((value >> 16) & 255, (value >> 8) & 255, value & 255, 255)


def png(width, height, rows):
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def solid(size, colour, corner=None):
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            inCorner = corner is not None and x < size // 2 and y < size // 2
            row.append(rgba(corner) if inCorner else rgba(colour))
        rows.append(row)
    return png(size, size, rows)


def hexBlock(data):
    return "\n".join(data[i:i + 16].hex() for i in range(0, len(data), 16))


def save(font, name):
    font.recalcTimestamp = False
    font["head"].created = PINNED
    font["head"].modified = PINNED
    font.save(OUT + name)


def squareGlyph(inset, height=700):
    pen = TTGlyphPen(None)
    pen.moveTo((inset, 0))
    pen.lineTo((inset, height))
    pen.lineTo((UPEM - inset, height))
    pen.lineTo((UPEM - inset, 0))
    pen.closePath()
    return pen.glyph()


def base(family, glyphOrder, cmap, glyphs, advance):
    builder = FontBuilder(UPEM, isTTF=True)
    builder.setupGlyphOrder(glyphOrder)
    builder.setupCharacterMap(cmap)
    if glyphs is not None:
        builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({g: (advance, 0) for g in glyphOrder})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({"familyName": family, "styleName": "Regular"})
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    builder.setupPost(keepGlyphNames=False)
    builder.setupHead(unitsPerEm=UPEM, created=PINNED, modified=PINNED)
    return builder


def squares(order):
    glyphs = {g: squareGlyph(100) for g in order}
    glyphs[".notdef"] = squareGlyph(50)
    return glyphs


def importXml(font, xml):
    text = f'<?xml version="1.0"?><ttFont sfntVersion="\\x00\\x01\\x00\\x00">{xml}</ttFont>'
    font.importXML(io.StringIO(text))


def noto(source):
    options = subset.Options()
    options.layout_features = []
    options.name_IDs = ["*"]
    options.hinting = False
    font = TTFont(source)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=NOTO_CHARS)
    subsetter.subset(font)
    save(font, "NotoColorEmoji-subset.ttf")


def textSymbol():
    order = [".notdef", "u1F600", "uni2764"]
    builder = base("Void Text Symbol", order, {0x1F600: "u1F600", 0x2764: "uni2764"},
                   squares(order), 900)
    save(builder.font, "textSymbol.ttf")


def lineMetrics(direction, ascender, descender, widthMax):
    return (f'<sbitLineMetrics direction="{direction}"><ascender value="{ascender}"/>'
            f'<descender value="{descender}"/><widthMax value="{widthMax}"/>'
            '<caretSlopeNumerator value="0"/><caretSlopeDenominator value="0"/>'
            '<caretOffset value="0"/><minOriginSB value="0"/><minAdvanceSB value="0"/>'
            '<maxBeforeBL value="0"/><minAfterBL value="0"/><pad1 value="0"/><pad2 value="0"/>'
            '</sbitLineMetrics>')


def cbdtSynthetic():
    order = [".notdef", "u1F600", "uni2764"]
    builder = base("Void CBDT Synthetic", order, {0x1F600: "u1F600", 0x2764: "uni2764"},
                   None, 1000)
    font = builder.font
    uvs = CmapSubtable.newSubtable(14)
    uvs.platformID, uvs.platEncID, uvs.language = 0, 5, 0
    uvs.cmap = {}
    uvs.uvsDict = {0xFE0F: [(0x2764, None), (0x1F600, None)]}
    font["cmap"].tables.append(uvs)
    strikes, data = [], []
    for index, ppem in enumerate([8, 16]):
        strikes.append(
            f'<strike index="{index}"><bitmapSizeTable>{lineMetrics("hori", ppem, 0, ppem)}'
            f'{lineMetrics("vert", ppem, 0, ppem)}<colorRef value="0"/>'
            '<startGlyphIndex value="1"/><endGlyphIndex value="2"/>'
            f'<ppemX value="{ppem}"/><ppemY value="{ppem}"/><bitDepth value="32"/>'
            '<flags value="1"/></bitmapSizeTable>'
            '<eblc_index_sub_table_1 imageFormat="17" firstGlyphIndex="1" lastGlyphIndex="2">'
            '<glyphLoc id="1" name="u1F600"/><glyphLoc id="2" name="uni2764"/>'
            '</eblc_index_sub_table_1></strike>')
        items = []
        for name, colour, corner in [("u1F600", RED, None), ("uni2764", BLUE, WHITE)]:
            image = solid(ppem, colour, corner)
            items.append(
                f'<cbdt_bitmap_format_17 name="{name}"><SmallGlyphMetrics>'
                f'<height value="{ppem}"/><width value="{ppem}"/><BearingX value="0"/>'
                f'<BearingY value="{ppem}"/><Advance value="{ppem}"/></SmallGlyphMetrics>'
                f'<rawimagedata>\n{hexBlock(image)}\n</rawimagedata></cbdt_bitmap_format_17>')
        data.append(f'<strikedata index="{index}">{"".join(items)}</strikedata>')
    importXml(font, f'<CBLC><header version="3.0"/>{"".join(strikes)}</CBLC>')
    importXml(font, f'<CBDT><header version="3.0"/>{"".join(data)}</CBDT>')
    save(font, "cbdtSynthetic.ttf")


def rectPng(width, height, colour):
    return png(width, height, [[rgba(colour)] * width for _ in range(height)])


def bigMetrics(height, width, bearingX, bearingY):
    return ('<BigGlyphMetrics>'
            f'<height value="{height}"/><width value="{width}"/>'
            f'<horiBearingX value="{bearingX}"/><horiBearingY value="{bearingY}"/>'
            f'<horiAdvance value="{width}"/><vertBearingX value="0"/>'
            f'<vertBearingY value="0"/><vertAdvance value="{height}"/></BigGlyphMetrics>')


def smallMetrics(height, width, bearingX, bearingY):
    return ('<SmallGlyphMetrics>'
            f'<height value="{height}"/><width value="{width}"/>'
            f'<BearingX value="{bearingX}"/><BearingY value="{bearingY}"/>'
            f'<Advance value="{width}"/></SmallGlyphMetrics>')


def cbdtFormats():
    order = [".notdef", "u1F600", "uni2764", "u1F44D"]
    builder = base("Void CBDT Formats", order,
                   {0x1F600: "u1F600", 0x2764: "uni2764", 0x1F44D: "u1F44D"}, None, 1000)
    font = builder.font
    names = order[1:]
    colours = [RED, BLUE, WHITE]
    strikes, data = [], []
    shapes = {
        8: (2, 19, [(8, 8, 1, 7)] * 3),
        16: (3, 18, [(14, 16, 2, 13), (16, 12, -1, 15), (16, 16, 0, 16)]),
        24: (3, 17, [(24, 20, 3, 22), (18, 24, -2, 20), (24, 24, 0, 24)]),
        32: (1, 18, [(32, 28, 1, 30), (26, 32, 0, 27), (32, 32, -3, 31)]),
    }
    for index, (ppem, (indexFormat, imageFormat, boxes)) in enumerate(shapes.items()):
        images = [rectPng(w, h, c) for (h, w, _, _), c in zip(boxes, colours)]
        if indexFormat == 2:
            height, width, bx, by = boxes[0]
            fixed = f'<imageSize value="{max(len(i) for i in images) + 4}"/>' + bigMetrics(height, width, bx, by)
        else:
            fixed = ""
        glyphLocs = "".join(f'<glyphLoc id="{i + 1}" name="{n}"/>' for i, n in enumerate(names))
        strikes.append(
            f'<strike index="{index}"><bitmapSizeTable>{lineMetrics("hori", ppem, 0, ppem)}'
            f'{lineMetrics("vert", ppem, 0, ppem)}<colorRef value="0"/>'
            '<startGlyphIndex value="1"/><endGlyphIndex value="3"/>'
            f'<ppemX value="{ppem}"/><ppemY value="{ppem}"/><bitDepth value="32"/>'
            '<flags value="1"/></bitmapSizeTable>'
            f'<eblc_index_sub_table_{indexFormat} imageFormat="{imageFormat}" '
            f'firstGlyphIndex="1" lastGlyphIndex="3">{fixed}{glyphLocs}'
            f'</eblc_index_sub_table_{indexFormat}></strike>')
        items = []
        for name, image, (height, width, bx, by) in zip(names, images, boxes):
            if imageFormat == 17:
                metrics = smallMetrics(height, width, bx, by)
            elif imageFormat == 18:
                metrics = bigMetrics(height, width, bx, by)
            else:
                metrics = ""
            items.append(f'<cbdt_bitmap_format_{imageFormat} name="{name}">{metrics}'
                         f'<rawimagedata>\n{hexBlock(image)}\n</rawimagedata>'
                         f'</cbdt_bitmap_format_{imageFormat}>')
        data.append(f'<strikedata index="{index}">{"".join(items)}</strikedata>')
    importXml(font, f'<CBLC><header version="3.0"/>{"".join(strikes)}</CBLC>')
    importXml(font, f'<CBDT><header version="3.0"/>{"".join(data)}</CBDT>')
    save(font, "cbdtFormats.ttf")


def cbdtUnicodeLast():
    font = TTFont(OUT + "cbdtSynthetic.ttf")
    font.recalcTimestamp = False
    cmap = font["cmap"]
    keep = [t for t in cmap.tables if (t.platformID, t.platEncID) == (0, 5)]
    wide = CmapSubtable.newSubtable(12)
    wide.platformID, wide.platEncID, wide.language = 0, 4, 0
    wide.cmap = {0x1F600: "u1F600", 0x2764: "uni2764"}
    cmap.tables = [wide] + keep
    save(font, "cbdtUvsLast.ttf")


def sbixGlyph(name, kind, ox, oy, payload):
    return (f'<glyph name="{name}" graphicType="{kind}" originOffsetX="{ox}" '
            f'originOffsetY="{oy}"><hexdata>\n{hexBlock(payload)}\n</hexdata></glyph>')


def sbixDupe(name, target):
    return (f'<glyph name="{name}" graphicType="dupe" originOffsetX="0" originOffsetY="0">'
            f'<ref glyphname="{target}"/></glyph>')


def sbixSynthetic():
    order = [".notdef", "u1F600", "uni2764", "u1F44D", "uni2665"]
    cmap = {0x1F600: "u1F600", 0x2764: "uni2764", 0x1F44D: "u1F44D", 0x2665: "uni2665"}
    font = base("Void SBIX Synthetic", order, cmap, squares(order), 1000).font
    small = (sbixGlyph("u1F600", "png ", 0, 0, solid(12, RED))
             + sbixGlyph("uni2764", "png ", 1, -2, solid(12, BLUE))
             + sbixDupe("uni2665", "uni2764"))
    large = (sbixGlyph("u1F600", "png ", 0, 0, solid(24, RED))
             + sbixGlyph("uni2764", "png ", 2, -4, solid(24, BLUE))
             + sbixGlyph("u1F44D", "jpg ", 0, 0, b"\xff\xd8\xff\xd9")
             + sbixDupe("uni2665", "uni2764"))
    strikes = (f'<strike><ppem value="12"/><resolution value="72"/>{small}</strike>'
               f'<strike><ppem value="24"/><resolution value="72"/>{large}</strike>')
    importXml(font, f'<sbix><version value="1"/><flags value="1"/>{strikes}</sbix>')
    save(font, "sbixSynthetic.ttf")


def colrBase(family):
    order = [".notdef", "u1F600", "layerA", "layerB", "layerC"]
    glyphs = squares(order[:2])
    for index, name in enumerate(order[2:]):
        pen = TTGlyphPen(None)
        left = 100 + index * 100
        top = 700 - index * 100
        pen.moveTo((left, 0))
        pen.lineTo((left, top))
        pen.lineTo((left + 400, top))
        pen.lineTo((left + 400, 0))
        pen.closePath()
        glyphs[name] = pen.glyph()
    font = base(family, order, {0x1F600: "u1F600"}, glyphs, 1000).font
    palette = [(0.8, 0.2, 0.2, 1.0), (0.2, 0.4, 0.8, 1.0), (0.2, 0.7, 0.3, 0.5)]
    font["CPAL"] = buildCPAL([palette])
    return font


def colrSynthetic():
    font = colrBase("Void COLR Synthetic")
    font["COLR"] = buildCOLR({"u1F600": [("layerA", 0), ("layerB", 1), ("layerC", 2)]},
                             version=0)
    save(font, "colrSynthetic.ttf")


def colrUnion():
    layers = [
        ("layerCentre", (400, 300, 600, 500), 0),
        ("layerLeft", (100, 300, 300, 500), 1),
        ("layerRight", (700, 300, 900, 500), 2),
        ("layerTop", (400, 600, 600, 800), 1),
        ("layerBottom", (400, -200, 600, 0), 0),
    ]
    order = [".notdef", "u1F600"] + [name for name, _, _ in layers]
    glyphs = squares(order[:2])
    for name, (left, bottom, right, top), _ in layers:
        pen = TTGlyphPen(None)
        pen.moveTo((left, bottom))
        pen.lineTo((left, top))
        pen.lineTo((right, top))
        pen.lineTo((right, bottom))
        pen.closePath()
        glyphs[name] = pen.glyph()
    font = base("Void COLR Union", order, {0x1F600: "u1F600"}, glyphs, 1000).font
    palette = [(0.8, 0.2, 0.2, 1.0), (0.2, 0.4, 0.8, 1.0), (0.2, 0.7, 0.3, 0.5)]
    font["CPAL"] = buildCPAL([palette])
    font["COLR"] = buildCOLR({"u1F600": [(name, index) for name, _, index in layers]}, version=0)
    save(font, "colrUnion.ttf")


def colrForeground():
    font = colrBase("Void COLR Foreground")
    font["COLR"] = buildCOLR({"u1F600": [("layerA", 0), ("layerB", 0xFFFF)]}, version=0)
    save(font, "colrForeground.ttf")


def colrV1Only():
    font = colrBase("Void COLR V1")
    paint = {
        "Format": ot.PaintFormat.PaintGlyph,
        "Glyph": "layerA",
        "Paint": {"Format": ot.PaintFormat.PaintSolid, "PaletteIndex": 0, "Alpha": 1.0},
    }
    font["COLR"] = buildCOLR({"u1F600": paint}, version=1)
    save(font, "colrV1Only.ttf")


def collection():
    fonts = [TTFont(OUT + "textSymbol.ttf"), TTFont(OUT + "cbdtSynthetic.ttf")]
    for font in fonts:
        font.recalcTimestamp = False
    ttc = TTCollection()
    ttc.fonts = fonts
    ttc.save(OUT + "symbolCollection.ttc")


def tableOffset(data, tag):
    for i in range(struct.unpack(">H", data[4:6])[0]):
        record = data[12 + 16 * i:28 + 16 * i]
        if record[:4] == tag:
            return struct.unpack(">I", record[8:12])[0]
    raise KeyError(tag)


def cbdtDepths(name, strikes):
    data = bytearray(open(OUT + "cbdtSynthetic.ttf", "rb").read())
    for strike in strikes:
        data[tableOffset(data, b"CBLC") + 8 + 48 * strike + 46] = 8
    open(OUT + name, "wb").write(bytes(data))


def cbdtBroken():
    cbdtDepths("cbdtBroken.ttf", [0, 1])
    cbdtDepths("cbdtMixedDepth.ttf", [0])


def sbixLoop():
    data = bytearray(open(OUT + "sbixSynthetic.ttf", "rb").read())
    table = tableOffset(data, b"sbix")
    for strike in range(struct.unpack(">I", data[table + 4:table + 8])[0]):
        start = table + struct.unpack(">I", data[table + 8 + 4 * strike:table + 12 + 4 * strike])[0]
        glyph = 4
        record = start + struct.unpack(">I", data[start + 4 + 4 * glyph:start + 8 + 4 * glyph])[0]
        assert data[record + 4:record + 8] == b"dupe"
        data[record + 8:record + 10] = struct.pack(">H", glyph)
    open(OUT + "sbixLoop.ttf", "wb").write(bytes(data))


def main():
    if sys.argv[1:] == ["broken"]:
        cbdtBroken()
        sbixLoop()
        colrForeground()
        colrV1Only()
        return
    noto(sys.argv[1])
    textSymbol()
    cbdtSynthetic()
    cbdtFormats()
    cbdtUnicodeLast()
    cbdtBroken()
    sbixSynthetic()
    sbixLoop()
    colrSynthetic()
    colrUnion()
    colrForeground()
    colrV1Only()
    collection()


if __name__ == "__main__":
    main()
