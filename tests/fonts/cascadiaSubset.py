import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = "tests/fonts/cascadiaSubset.ttf"
FAMILY = "Void Code Ligatures"


def build(source):
    font = TTFont(source)
    instancer.instantiateVariableFont(font, {"wght": 400}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.hinting = False
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=range(0x20, 0x7F))
    subsetter.subset(font)
    for record in font["name"].names:
        if record.nameID in (1, 4, 16, 21):
            record.string = FAMILY
        elif record.nameID == 6:
            record.string = FAMILY.replace(" ", "")
    font["head"].created = font["head"].modified = 3786825600
    font.save(OUT)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tests/fonts/cascadiaSubset.py <upstream CascadiaCode.ttf>")
    build(sys.argv[1])
