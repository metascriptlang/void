from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

OUT = "tests/fonts/shapeFixture.ttf"
FAMILY = "Void Shape Fixture"
UPEM = 1000
CREATED = 3786825600

ADVANCES = {
    ".notdef": 500,
    "space": 300,
    "f": 500,
    "i": 300,
    "f_i": 750,
    "A": 700,
    "V": 700,
    "a": 600,
    "b": 600,
    "b.alt": 650,
    "e": 600,
    "eacute": 600,
    "acutecomb": 0,
}

HEIGHTS = {
    ".notdef": 700,
    "f": 700,
    "i": 650,
    "f_i": 720,
    "A": 700,
    "V": 690,
    "a": 500,
    "b": 720,
    "b.alt": 600,
    "e": 500,
    "eacute": 500,
    "acutecomb": 120,
}

CMAP = {
    0x20: "space",
    0x41: "A",
    0x56: "V",
    0x61: "a",
    0x62: "b",
    0x65: "e",
    0x66: "f",
    0x69: "i",
    0xE9: "eacute",
    0x301: "acutecomb",
}

FEATURES = """
languagesystem DFLT dflt;
languagesystem latn dflt;

@bases = [A V a b b.alt e eacute f i];
@ligatures = [f_i];
@marks = [acutecomb];

table GDEF {
    GlyphClassDef @bases, @ligatures, @marks, ;
} GDEF;

markClass acutecomb <anchor 0 500> @top;

feature ccmp {
    sub eacute by e acutecomb;
} ccmp;

feature liga {
    sub f i by f_i;
} liga;

feature calt {
    sub a b' by b.alt;
} calt;

feature kern {
    pos A V -100;
} kern;

feature mark {
    pos base e <anchor 300 700> mark @top;
} mark;
"""


def draw(name):
    pen = TTGlyphPen(None)
    if name == "space" or ADVANCES[name] == 0 and name != "acutecomb":
        return pen.glyph()
    advance = ADVANCES[name]
    height = HEIGHTS[name]
    if name == "acutecomb":
        pen.moveTo((0, 500))
        pen.lineTo((0, 500 + height))
        pen.lineTo((120, 500 + height))
        pen.lineTo((120, 500))
        pen.closePath()
        return pen.glyph()
    pen.moveTo((50, 0))
    pen.lineTo((50, height))
    pen.lineTo((advance - 50, height))
    pen.lineTo((advance - 50, 0))
    pen.closePath()
    return pen.glyph()


def build():
    order = list(ADVANCES)
    font = FontBuilder(UPEM, isTTF=True)
    font.setupGlyphOrder(order)
    font.setupCharacterMap(CMAP)
    font.setupGlyf({name: draw(name) for name in order})
    font.setupHorizontalMetrics({name: (ADVANCES[name], 0) for name in order})
    font.setupHorizontalHeader(ascent=800, descent=-200)
    font.setupNameTable({"familyName": FAMILY, "styleName": "Regular"})
    font.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    font.setupPost()
    font.updateHead(created=CREATED, modified=CREATED)
    addOpenTypeFeaturesFromString(font.font, FEATURES)
    font.save(OUT)


if __name__ == "__main__":
    build()
