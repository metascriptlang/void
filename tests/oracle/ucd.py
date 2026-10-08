"""The UCD segmentation oracle: python tests/oracle/ucd.py regen

Downloads one pinned Unicode version, then writes
  tests/oracle/ucd/GraphemeBreakTest-<v>.txt   the conformance rows, comments stripped
  tests/oracle/ucd/LineBreakTest-<v>.txt       the conformance rows, comments stripped
  tests/oracle/ucd/EmojiPresentation-<v>.txt   the Emoji_Presentation ranges, first and last
  src/void2d/graphemeTable.h                   Grapheme_Cluster_Break, Extended_Pictographic,
                                               Indic_Conjunct_Break and Emoji_Presentation,
                                               one packed range each
  src/void2d/lineBreakTable.h                  Line_Break resolved by UAX #14 LB1, with the
                                               East Asian, Pi, Pf and unassigned-pictograph flags
  src/void2d/bidiTable.h                       Bidi_Class with the @missing defaults applied,
                                               Bidi_Paired_Bracket pairs and the exact
                                               Bidi_Mirroring_Glyph pairs (UAX #9)
The gate needs none of it: the outputs are committed and src/test/ucdOracleCheck.ms reads them.
BidiTest.txt and BidiCharacterTest.txt are not written here: setup.sh fetches them into deps/ucd
at a pinned sha256 (docs/TESTING.md, "Why the BiDi rows are fetched").
"""
import os
import sys
import tempfile
import unicodedata
import urllib.request

VERSION = "18.0.0"
BASE = f"https://www.unicode.org/Public/{VERSION}/ucd/"
SOURCES = {
    "GraphemeBreakTest.txt": "auxiliary/GraphemeBreakTest.txt",
    "LineBreakTest.txt": "auxiliary/LineBreakTest.txt",
    "GraphemeBreakProperty.txt": "auxiliary/GraphemeBreakProperty.txt",
    "emoji-data.txt": "emoji/emoji-data.txt",
    "DerivedCoreProperties.txt": "DerivedCoreProperties.txt",
    "LineBreak.txt": "LineBreak.txt",
    "EastAsianWidth.txt": "EastAsianWidth.txt",
    "DerivedGeneralCategory.txt": "extracted/DerivedGeneralCategory.txt",
    "DerivedBidiClass.txt": "extracted/DerivedBidiClass.txt",
    "BidiBrackets.txt": "BidiBrackets.txt",
    "BidiMirroring.txt": "BidiMirroring.txt",
}

GCB = ["Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator", "Prepend",
       "SpacingMark", "L", "V", "T", "LV", "LVT"]
INCB = ["None", "Linker", "Consonant", "Extend"]
PICTOGRAPHIC = 16
INCB_SHIFT = 5
EMOJI_PRESENTATION = 128

LB = ["AL", "BK", "CR", "LF", "NL", "SP", "ZW", "ZWJ", "CM", "WJ", "GL", "EX", "CL", "CP",
      "SY", "OP", "QU", "IS", "NS", "B2", "BA", "BB", "HY", "HH", "CB", "IN", "NU", "HL", "PR",
      "PO", "ID", "EB", "EM", "JL", "JV", "JT", "H2", "H3", "RI", "AK", "AP", "AS", "VF", "VI"]
EAST_ASIAN = 1 << 6
INITIAL_PUNCTUATION = 1 << 7
FINAL_PUNCTUATION = 1 << 8
PICTOGRAPH_UNASSIGNED = 1 << 9

BIDI = ["L", "R", "AL", "EN", "ES", "ET", "AN", "CS", "NSM", "BN", "B", "S", "WS", "ON", "LRE",
        "LRO", "RLE", "RLO", "PDF", "LRI", "RLI", "FSI", "PDI"]
BIDI_MISSING = {
    "Left_To_Right": "L", "Right_To_Left": "R", "Arabic_Letter": "AL",
    "European_Terminator": "ET",
}

HANGUL_FIRST = 0xAC00
HANGUL_LAST = 0xD7A3


def fetch(directory):
    paths = {}
    for name, remote in SOURCES.items():
        path = os.path.join(directory, name)
        urllib.request.urlretrieve(BASE + remote, path)
        paths[name] = path
    return paths


def ranges(path, want):
    for line in open(path, encoding="utf-8"):
        body = line.split("#")[0].strip()
        if not body:
            continue
        fields = [f.strip() for f in body.split(";")]
        if not want(fields):
            continue
        first, _, last = fields[0].partition("..")
        yield int(first, 16), int(last or first, 16), fields


def everything(fields):
    return True


def pictographs(paths):
    found = set()
    for a, b, f in ranges(paths["emoji-data.txt"], lambda f: f[1] == "Extended_Pictographic"):
        found.update(range(a, b + 1))
    return found


def emojiPresentations(paths):
    found = set()
    for a, b, f in ranges(paths["emoji-data.txt"], lambda f: f[1] == "Emoji_Presentation"):
        found.update(range(a, b + 1))
    return found


def graphemeClasses(paths):
    table = {}
    for a, b, f in ranges(paths["GraphemeBreakProperty.txt"], everything):
        for c in range(a, b + 1):
            table[c] = table.get(c, 0) | GCB.index(f[1])
    for c in pictographs(paths):
        table[c] = table.get(c, 0) | PICTOGRAPHIC
    for c in emojiPresentations(paths):
        table[c] = table.get(c, 0) | EMOJI_PRESENTATION
    conjunct = lambda f: len(f) >= 3 and f[1] == "InCB"
    for a, b, f in ranges(paths["DerivedCoreProperties.txt"], conjunct):
        for c in range(a, b + 1):
            table[c] = table.get(c, 0) | (INCB.index(f[2]) << INCB_SHIFT)
    return table


def lineBreakClasses(paths):
    general = {}
    for a, b, f in ranges(paths["DerivedGeneralCategory.txt"], everything):
        for c in range(a, b + 1):
            general[c] = f[1]
    wide = set()
    for a, b, f in ranges(paths["EastAsianWidth.txt"], lambda f: f[1] in ("F", "W", "H")):
        wide.update(range(a, b + 1))
    unassignedPictographs = {c for c in pictographs(paths) if general.get(c, "Cn") == "Cn"}
    table = {}
    for a, b, f in ranges(paths["LineBreak.txt"], everything):
        for c in range(a, b + 1):
            cls = f[1]
            if cls in ("AI", "SG", "XX"):
                cls = "AL"
            elif cls == "SA":
                cls = "CM" if general.get(c) in ("Mn", "Mc") else "AL"
            elif cls == "CJ":
                cls = "NS"
            table[c] = LB.index(cls)
    for c in range(0, 0x110000):
        value = table.get(c, LB.index("AL"))
        if c in wide:
            value |= EAST_ASIAN
        if general.get(c) == "Pi":
            value |= INITIAL_PUNCTUATION
        if general.get(c) == "Pf":
            value |= FINAL_PUNCTUATION
        if c in unassignedPictographs:
            value |= PICTOGRAPH_UNASSIGNED
        if value:
            table[c] = value
    return table


def bidiClasses(paths):
    table = {}
    for line in open(paths["DerivedBidiClass.txt"], encoding="utf-8"):
        if not line.startswith("# @missing:"):
            continue
        span, _, name = line[len("# @missing:"):].partition(";")
        first, _, last = span.strip().partition("..")
        cls = BIDI_MISSING.get(name.strip())
        if cls is None:
            if name.strip() != "Left_To_Right":
                sys.exit(f"@missing names a Bidi_Class this script has no letter for: {name}")
            cls = "L"
        for c in range(int(first, 16), int(last, 16) + 1):
            table[c] = BIDI.index(cls)
    for a, b, f in ranges(paths["DerivedBidiClass.txt"], everything):
        for c in range(a, b + 1):
            table[c] = BIDI.index(f[1])
    return table


def canonicalOpener(c):
    whole = unicodedata.normalize("NFC", chr(c))
    return ord(whole) if len(whole) == 1 else c


def bidiBrackets(paths):
    found = []
    for a, b, f in ranges(paths["BidiBrackets.txt"], everything):
        pair = int(f[1], 16)
        opens = f[2].split("#")[0].strip() == "o"
        found.append((a, (canonicalOpener(a) if opens else canonicalOpener(pair)) << 1 | opens))
    return sorted(found)


def bidiMirrors(paths):
    found = []
    for line in open(paths["BidiMirroring.txt"], encoding="utf-8"):
        body, _, comment = line.partition("#")
        if not body.strip() or "[BEST FIT]" in comment:
            continue
        a, b = (int(v, 16) for v in body.split(";"))
        found.append((a, b))
    exact = dict(found)
    for a, b in found:
        if exact.get(b) != a:
            sys.exit(f"U+{a:04X} mirrors to U+{b:04X}, which does not mirror back")
    return sorted(found)


def writeBidiTable(path, classes, brackets, mirrors):
    starts = []
    previous = None
    for c in range(0, 0x110000):
        value = classes.get(c, BIDI.index("L"))
        if value != previous:
            starts.append((c << 5) | value)
            previous = value
    lines = [f"// Generated by tests/oracle/ucd.py from UCD {VERSION}. Do not edit."]
    lines += [
        "// kVoid2dBidiClassRanges: (start << 5) | Bidi_Class, sorted; a range runs to the next",
        "// start. The @missing defaults of DerivedBidiClass.txt are applied.",
        "// kVoid2dBidiBrackets: codepoint, then (canonical opener << 1) | is-opening, sorted.",
        "// kVoid2dBidiMirrors: codepoint, then its exact Bidi_Mirroring_Glyph, sorted; the",
        "// [BEST FIT] pairs are left out, because UAX #9 L4 mirrors only exact pairs.",
        "#pragma once",
        "#include <stdint.h>",
        f"#define VOID2D_BIDI_CLASS_RANGES {len(starts)}",
        f"#define VOID2D_BIDI_BRACKETS {len(brackets)}",
        f"#define VOID2D_BIDI_MIRRORS {len(mirrors)}",
    ]

    def block(array, macro, values):
        out = [f"static const uint32_t {array}[{macro}] = {{"]
        row = []
        for v in values:
            row.append(f"0x{v:08X}u")
            if len(row) == 6:
                out.append("\t" + ", ".join(row) + ",")
                row = []
        if row:
            out.append("\t" + ", ".join(row) + ",")
        out.append("};")
        return out

    lines += block("kVoid2dBidiClassRanges", "VOID2D_BIDI_CLASS_RANGES", starts)
    flat = [v for pair in brackets for v in pair]
    lines += block("kVoid2dBidiBrackets", "VOID2D_BIDI_BRACKETS * 2", flat)
    flat = [v for pair in mirrors for v in pair]
    lines += block("kVoid2dBidiMirrors", "VOID2D_BIDI_MIRRORS * 2", flat)
    open(path, "w", newline="\n").write("\n".join(lines) + "\n")


def packedRanges(table, hangul, computed):
    for c in range(HANGUL_FIRST, HANGUL_LAST + 1):
        if table.get(c, 0) != hangul(c):
            sys.exit(f"U+{c:04X} is not the Hangul syllable the lookup computes")
    starts = []
    previous = None
    for c in range(0, 0x110000):
        value = computed if HANGUL_FIRST <= c <= HANGUL_LAST else table.get(c, 0)
        if value != previous:
            starts.append((c, value))
            previous = value
    return starts


def writeTable(path, array, macro, shift, header, entries):
    lines = [f"// Generated by tests/oracle/ucd.py from UCD {VERSION}. Do not edit."]
    lines += [f"// {line}" for line in header]
    lines += [
        "#pragma once",
        "#include <stdint.h>",
        f"#define {macro} {len(entries)}",
        f"static const uint32_t {array}[{macro}] = {{",
    ]
    row = []
    for c, v in entries:
        row.append(f"0x{(c << shift) | v:08X}u")
        if len(row) == 6:
            lines.append("\t" + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("\t" + ", ".join(row) + ",")
    lines.append("};")
    open(path, "w", newline="\n").write("\n".join(lines) + "\n")


def writeRows(source, name):
    out = [f"# {name}-{VERSION}.txt, the data rows of {BASE}auxiliary/{name}.txt with the"
           " comments stripped by tests/oracle/ucd.py"]
    for line in open(source, encoding="utf-8"):
        body = line.split("#")[0].strip()
        if body:
            out.append(body)
    os.makedirs("tests/oracle/ucd", exist_ok=True)
    path = f"tests/oracle/ucd/{name}-{VERSION}.txt"
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


def writeEmojiPresentation(paths):
    spans = []
    for c in sorted(emojiPresentations(paths)):
        if spans and spans[-1][1] == c - 1:
            spans[-1][1] = c
        else:
            spans.append([c, c])
    out = [f"# Emoji_Presentation-{VERSION}.txt, the ranges of {BASE}emoji/emoji-data.txt"
           " written by tests/oracle/ucd.py: first and last codepoint, hex"]
    out += [f"{a:X} {b:X}" for a, b in spans]
    path = f"tests/oracle/ucd/EmojiPresentation-{VERSION}.txt"
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


def graphemeHangul(c):
    return GCB.index("LV") if (c - HANGUL_FIRST) % 28 == 0 else GCB.index("LVT")


def lineBreakHangul(c):
    cls = LB.index("H2") if (c - HANGUL_FIRST) % 28 == 0 else LB.index("H3")
    return cls | EAST_ASIAN


def regen():
    with tempfile.TemporaryDirectory() as directory:
        paths = fetch(directory)
        writeTable(
            "src/void2d/graphemeTable.h", "kVoid2dGraphemeRanges", "VOID2D_GRAPHEME_RANGES", 8, [
            "(start << 8) | class, sorted; a range runs to the next start. Class: bits 0-3",
            "Grapheme_Cluster_Break, bit 4 Extended_Pictographic, bits 5-6 Indic_Conjunct_Break,",
            "bit 7 Emoji_Presentation.",
            "The Hangul syllables are computed, so their entry holds 0xFF.",
        ], packedRanges(graphemeClasses(paths), graphemeHangul, 0xFF))
        writeTable(
            "src/void2d/lineBreakTable.h", "kVoid2dLineBreakRanges", "VOID2D_LINE_BREAK_RANGES", 11, [
            "(start << 11) | class, sorted; a range runs to the next start. Class: bits 0-5",
            "Line_Break after LB1, bit 6 East_Asian_Width F/W/H, bit 7 gc=Pi, bit 8 gc=Pf,",
            "bit 9 Extended_Pictographic and gc=Cn. The Hangul syllables are computed: 0x7FF.",
        ], packedRanges(lineBreakClasses(paths), lineBreakHangul, 0x7FF))
        writeBidiTable(
            "src/void2d/bidiTable.h", bidiClasses(paths), bidiBrackets(paths),
            bidiMirrors(paths))
        writeRows(paths["GraphemeBreakTest.txt"], "GraphemeBreakTest")
        writeRows(paths["LineBreakTest.txt"], "LineBreakTest")
        writeEmojiPresentation(paths)


if __name__ == "__main__":
    if sys.argv[1:] != ["regen"]:
        sys.exit("usage: python tests/oracle/ucd.py regen")
    regen()
