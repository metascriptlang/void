import sys
from fontTools import subset
from fontTools.ttLib import TTFont

SOURCE = "assets/font.ttf"
OUT = "tests/fonts/"


def small(text):
    options = subset.Options()
    options.name_IDs = ["*"]
    options.hinting = False
    options.layout_features = []
    font = TTFont(SOURCE)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    return font


def rename(font, family):
    for record in font["name"].names:
        if record.nameID in (1, 4, 16, 21):
            record.string = family
        elif record.nameID == 6:
            record.string = family.replace(" ", "")


def zeroedWithVersion1():
    font = small("Hx")
    font["post"].underlinePosition = 0
    font["post"].underlineThickness = 0
    os2 = font["OS/2"]
    os2.yStrikeoutPosition = 0
    os2.yStrikeoutSize = 0
    os2.version = 1
    os2.fsSelection &= 0x7F
    for field in ("sxHeight", "sCapHeight", "usDefaultChar", "usBreakChar", "usMaxContext",
                  "usLowerOpticalPointSize", "usUpperOpticalPointSize"):
        if hasattr(os2, field):
            delattr(os2, field)
    rename(font, "Void Zeroed Decorations")
    font.save(OUT + "zeroedDecorations.ttf")


def thicknessOnlyBroken():
    font = small("H")
    font["post"].underlineThickness = 0
    os2 = font["OS/2"]
    os2.yStrikeoutSize = 0
    os2.sxHeight = 0
    os2.sCapHeight = 0
    rename(font, "Void Zero Thickness")
    font.save(OUT + "zeroThickness.ttf")


def zeroLineHeight():
    font = small("H")
    hhea = font["hhea"]
    hhea.ascent = 0
    hhea.descent = 0
    hhea.lineGap = 0
    rename(font, "Void Zero Line Height")
    font.save(OUT + "zeroLineHeight.ttf")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        SOURCE = sys.argv[1]
    zeroedWithVersion1()
    thicknessOnlyBroken()
    zeroLineHeight()
