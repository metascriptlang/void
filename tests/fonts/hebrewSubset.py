import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = "tests/fonts/notoSansHebrewSubset.ttf"

HEBREW = "אבגדהוזחטיכךלמםנןסעפףצץקרשת"
POINTS = "ְִַָּׁׂ"
LATIN = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
PUNCTUATION = " !\"%&'()*+,-./:;<=>?[]{}_…"
SAMPLES = [
    HEBREW, "שלום עולם", "בראשית", "ספר" + POINTS, LATIN, PUNCTUATION,
]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tests/fonts/hebrewSubset.py hebrew.ttf  "
                 "(ofl/notosanshebrew/NotoSansHebrew[wdth,wght].ttf from google/fonts)")
    font = TTFont(sys.argv[1])
    instancer.instantiateVariableFont(font, {"wght": 400, "wdth": 100}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.hinting = False
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=" ".join(SAMPLES))
    subsetter.subset(font)
    font["head"].created = font["head"].modified = 3786825600
    font.save(OUT)
