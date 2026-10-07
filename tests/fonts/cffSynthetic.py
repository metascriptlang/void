from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen

OUT = "tests/fonts/cffSynthetic.otf"
UNITS = 1000


def blob():
    pen = T2CharStringPen(600, None)
    pen.moveTo((100, 0))
    pen.curveTo((100, 400), (500, 700), (500, 0))
    pen.closePath()
    return pen.getCharString()


def box():
    pen = T2CharStringPen(600, None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 600))
    pen.lineTo((500, 600))
    pen.lineTo((500, 0))
    pen.closePath()
    return pen.getCharString()


def empty():
    return T2CharStringPen(600, None).getCharString()


builder = FontBuilder(UNITS, isTTF=False)
builder.setupGlyphOrder([".notdef", "A", "B"])
builder.setupCharacterMap({65: "A", 66: "B"})
builder.setupCFF("VoidCffSynthetic", {"FullName": "Void Cff Synthetic"},
                 {".notdef": empty(), "A": blob(), "B": box()}, {})
builder.setupHorizontalMetrics({".notdef": (600, 0), "A": (600, 100), "B": (600, 100)})
builder.setupHorizontalHeader(ascent=800, descent=-200)
builder.setupNameTable({"familyName": "Void Cff Synthetic", "styleName": "Regular"})
builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
builder.setupPost()
builder.save(OUT)
