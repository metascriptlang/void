"""The shape config fixture of the kb shaper: python tests/oracle/kbConfigFixture.py

Builds a small variable font whose GSUB and GPOS reach what src/void2d/kb/shapeConfig.ms bakes and
the repository fonts do not: GSUB FeatureVariations (condition sets over wght and wdth, with the
substituted feature lists), fvar with an avar that remaps, scripts of every shaper including the
Indic3 tags, the languages TRK and ROM, a Syriac script with no rclt, the syllable features of the
Indic shapers, a virama and a locl on it, the Thai and Lao nikhahit and sara aa, more than 32 user
features in one language system and lookups shared by several features. It writes the font as hex
into src/test/kbConfigFixtures.ms.
"""
import io
import os
import sys

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont, newTable

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(ROOT, "src", "test", "kbConfigFixtures.ms")
UPEM = 1000
CREATED = 3786825600

LATIN = ["a", "b", "c", "d", "a.alt", "b.alt", "i", "i.alt", "ab", "space"]
MARKS = ["acute", "grave"]
INDIC = ["virama", "virama.alt", "ka", "kha", "ra", "ka.half", "ra.reph", "ka.below", "ka.post"]
THAI = ["nikhahit", "saraAa", "thaiKo", "laoNikhahit", "laoSaraAa"]
ARABIC = ["alef", "lam", "alef.fina", "lam.init", "lamAlef"]
OTHER = ["dotted", "myanmarKa", "asat"]
ORDER = [".notdef"] + LATIN + MARKS + INDIC + THAI + ARABIC + OTHER

CMAP = {
    0x61: "a", 0x62: "b", 0x63: "c", 0x64: "d", 0x69: "i", 0x20: "space",
    0x301: "acute", 0x300: "grave",
    0x94D: "virama", 0x915: "ka", 0x916: "kha", 0x930: "ra",
    0xE4D: "nikhahit", 0xE32: "saraAa", 0xE01: "thaiKo", 0xECD: "laoNikhahit", 0xEB2: "laoSaraAa",
    0x627: "alef", 0x644: "lam",
    0x25CC: "dotted", 0x1000: "myanmarKa", 0x103A: "asat",
}

SCRIPTS = ["DFLT dflt", "latn dflt", "latn TRK", "latn ROM", "deva dflt", "dev3 dflt", "arab dflt",
           "syrc dflt", "thai dflt", "lao dflt", "mymr dflt", "khmr dflt", "hebr dflt", "hang dflt",
           "mym3 dflt", "beng dflt"]

USER_FEATURES = ["ss%02d" % n for n in range(1, 21)] + ["cv%02d" % n for n in range(1, 21)]


def user_blocks():
    lines = []
    for index, tag in enumerate(USER_FEATURES):
        target = "a" if index % 2 == 0 else "b"
        alternate = "a.alt" if target == "a" else "b.alt"
        if index % 5 == 4:
            lines.append("feature %s { lookup shared; } %s;" % (tag, tag))
        else:
            lines.append("feature %s { sub %s by %s; } %s;" % (tag, target, alternate, tag))
    return "\n".join(lines)


FEATURES = """
%(languagesystems)s

@marks = [acute grave];
@latin = [a b c d i];

table GDEF { GlyphClassDef @latin, , @marks, ; } GDEF;
markClass [acute grave] <anchor 250 700> @TOP;

lookup shared { sub c by d; } shared;
lookup heavyLiga { sub a b by ab; } heavyLiga;
lookup heavyWide { sub i by i.alt; } heavyWide;

feature ccmp { sub a by a.alt; } ccmp;
feature liga { sub a b by ab; } liga;
feature calt { sub b' a by b.alt; } calt;
feature rlig { sub i by i.alt; } rlig;
feature clig { lookup shared; } clig;
feature kern { pos a b -50; pos c d -20; } kern;
feature mark { pos base [a b] <anchor 250 650> mark @TOP; } mark;

feature locl {
    script latn; language TRK; sub i by i.alt;
    script latn; language ROM; sub i by i.alt; sub a by a.alt;
    script deva; language dflt; sub virama by virama.alt;
    script dev3; language dflt; sub virama by virama.alt;
    script beng; language dflt; sub virama by virama.alt;
} locl;

feature rphf { script deva; sub ra virama by ra.reph; script dev3; sub ra virama by ra.reph; } rphf;
feature half { script deva; sub ka virama by ka.half; script dev3; sub ka virama by ka.half; } half;
feature blwf { script deva; sub virama ka by ka.below; script dev3; sub virama ka by ka.below; } blwf;
feature pref { script deva; sub virama ra by ra.reph; } pref;
feature pstf { script deva; sub virama kha by ka.post; } pstf;
feature vatu { script deva; sub ka ra by ka.half; } vatu;
feature rclt { script arab; sub lam alef by lamAlef; script deva; sub ka by ka.half; } rclt;
feature init { script arab; sub lam by lam.init; script syrc; sub lam by lam.init; } init;
feature fina { script arab; sub alef by alef.fina; script syrc; sub alef by alef.fina; } fina;
feature calt { script syrc; sub lam alef by lamAlef; } calt;

%(user)s

conditionset heavy { wght 600 900; } heavy;
conditionset wideHeavy { wght 500 900; wdth 90 125; } wideHeavy;
conditionset slanted { slnt -12 -6; } slanted;
conditionset lightOnly { wght 100 300; } lightOnly;

variation liga heavy { lookup heavyLiga; } liga;
variation rlig wideHeavy { lookup heavyWide; } rlig;
variation calt slanted { sub a by a.alt; } calt;
variation kern lightOnly { pos a b -90; } kern;
variation ss01 heavy { sub b by b.alt; } ss01;
"""


def draw(name):
    pen = TTGlyphPen(None)
    pen.moveTo((50, 0))
    pen.lineTo((50, 600))
    pen.lineTo((450, 600))
    pen.lineTo((450, 0))
    pen.closePath()
    return pen.glyph()


def add_avar(font):
    avar = newTable("avar")
    avar.segments = {
        "wght": {-1.0: -1.0, -0.5: -0.25, 0.0: 0.0, 0.5: 0.75, 1.0: 1.0},
        "wdth": {-1.0: -1.0, 0.0: 0.0, 1.0: 1.0},
        "slnt": {-1.0: -1.0, -0.25: -0.5, 0.0: 0.0, 1.0: 1.0},
    }
    font["avar"] = avar


def build():
    font = FontBuilder(UPEM, isTTF=True)
    font.setupGlyphOrder(ORDER)
    font.setupCharacterMap(CMAP)
    font.setupGlyf({name: draw(name) for name in ORDER})
    font.setupHorizontalMetrics({name: (500, 0) for name in ORDER})
    font.setupHorizontalHeader(ascent=800, descent=-200)
    font.setupNameTable({"familyName": "Void Config Fixture", "styleName": "Regular"})
    font.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    font.setupPost()
    font.updateHead(created=CREATED, modified=CREATED)
    font.setupFvar(
        [("wght", 100, 400, 900, "Weight"), ("wdth", 75, 100, 125, "Width"),
         ("slnt", -12, 0, 0, "Slant")],
        [])
    add_avar(font.font)
    text = FEATURES % {
        "languagesystems": "\n".join("languagesystem %s;" % entry for entry in SCRIPTS),
        "user": user_blocks(),
    }
    addOpenTypeFeaturesFromString(font.font, text)
    return font.font


def report(font):
    gsub = font["GSUB"].table
    print("lookups", len(gsub.LookupList.Lookup), "features", len(gsub.FeatureList.FeatureRecord))
    print("scripts", [record.ScriptTag for record in gsub.ScriptList.ScriptRecord])
    variations = getattr(gsub, "FeatureVariations", None)
    print("feature variations", variations and len(variations.FeatureVariationRecord))


VECTORS = [
    [400, 100, 0], [100, 75, -12], [900, 125, 0], [700, 100, 0], [650, 110, -8],
    [500, 90, 0], [300, 100, 0], [200, 80, -6], [1200, 200, 5], [0, 0, -20], [850, 125, -12],
    [550, 95, -9],
]


def write(font):
    buffer = io.BytesIO()
    font.save(buffer)
    data = buffer.getvalue()
    lines = [
        "// The config fixture of tests/oracle/kbConfigFixture.py, embedded so the pins also run where",
        "// no file can be read.",
        "export const KB_CONFIG_FIXTURE_HEX: string = \"%s\";" % data.hex(),
        "",
        "export const KB_CONFIG_FIXTURE_VECTORS: float32[][] = [",
    ]
    for vector in VECTORS:
        lines.append("\t[%s]," % ", ".join(str(float(value)) for value in vector))
    lines.append("];")
    with open(OUTPUT, "w", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return data


if __name__ == "__main__":
    built = build()
    data = write(built)
    if "--report" in sys.argv:
        report(TTFont(io.BytesIO(data)))
