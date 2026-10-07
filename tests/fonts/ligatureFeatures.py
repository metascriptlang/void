from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

OUT = "tests/fonts/ligatureFeatures.ttf"
FAMILY = "Void Ligature Features"
UPEM = 1000
CREATED = 3786825600

ADVANCES = {
    ".notdef": 500,
    "f": 500,
    "i": 300,
    "a": 600,
    "b": 600,
    "f_i": 750,
    "a_b": 1000,
}

CMAP = {0x61: "a", 0x62: "b", 0x66: "f", 0x69: "i"}

FEATURES = """
languagesystem DFLT dflt;
languagesystem latn dflt;

@bases = [a b f i];
@ligatures = [f_i a_b];

table GDEF {
    GlyphClassDef @bases, @ligatures, , ;
} GDEF;

feature liga { sub f i by f_i; } liga;
feature clig { sub a b by a_b; } clig;
feature kern { pos f_i <300 400 0 0>; } kern;
"""


def draw(name):
    pen = TTGlyphPen(None)
    advance = ADVANCES[name]
    pen.moveTo((50, 0))
    pen.lineTo((50, 600))
    pen.lineTo((advance - 50, 600))
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
