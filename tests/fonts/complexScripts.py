import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = "tests/fonts/"

FACES = [
    ("devanagari", "notoSansDevanagariSubset.ttf", True,
     ["कि हिन्दी क्षत्रिय", "नमस्ते", "विद्यार्थी", "कर्म", "पुस्तकालय", "ज्ञान", "श्रीमान्"]),
    ("thai", "notoSansThaiSubset.ttf", False,
     ["สวัสดี", "ประเทศไทย", "ที่นี่", "ก้า", "น้ำ"]),
    ("arabic", "notoSansArabicSubset.ttf", True,
     ["مرحبا", "السلام عليكم", "لا", "كتاب", "محمد"]),
    ("khmer", "notoSansKhmerSubset.ttf", True,
     ["ខ្ញុំ", "កម្ពុជា", "ស្រុក", "ភាសាខ្មែរ"]),
]


def build(source, out, pin, samples):
    font = TTFont(source)
    if pin:
        instancer.instantiateVariableFont(font, {"wght": 400, "wdth": 100}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.hinting = False
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=" ".join(samples))
    subsetter.subset(font)
    font["head"].created = font["head"].modified = 3786825600
    font.save(OUT + out)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tests/fonts/complexScripts.py <dir holding devanagari.ttf, thai.ttf, "
                 "arabic.ttf, khmer.ttf from google/fonts ofl/notosans*>")
    for key, out, pin, samples in FACES:
        build(f"{sys.argv[1]}/{key}.ttf", out, pin, samples)
