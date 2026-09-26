"""The UCD segmentation oracle: python tests/oracle/ucd.py regen

Downloads one pinned Unicode version, then writes
  tests/oracle/ucd/GraphemeBreakTest-<v>.txt   the conformance rows, comments stripped
  tests/oracle/ucd/LineBreakTest-<v>.txt       the conformance rows, comments stripped
  src/void2d/graphemeTable.h                   Grapheme_Cluster_Break, Extended_Pictographic
                                               and Indic_Conjunct_Break, one packed range each
  src/void2d/lineBreakTable.h                  Line_Break resolved by UAX #14 LB1, with the
                                               East Asian, Pi, Pf and unassigned-pictograph flags
The gate needs none of it: the outputs are committed and src/test/ucdOracleCheck.ms reads them.
"""
import os
import sys
import tempfile
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
}

GCB = ["Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator", "Prepend",
       "SpacingMark", "L", "V", "T", "LV", "LVT"]
INCB = ["None", "Linker", "Consonant", "Extend"]
PICTOGRAPHIC = 16
INCB_SHIFT = 5

LB = ["AL", "BK", "CR", "LF", "NL", "SP", "ZW", "ZWJ", "CM", "WJ", "GL", "EX", "CL", "CP",
      "SY", "OP", "QU", "IS", "NS", "B2", "BA", "BB", "HY", "HH", "CB", "IN", "NU", "HL", "PR",
      "PO", "ID", "EB", "EM", "JL", "JV", "JT", "H2", "H3", "RI", "AK", "AP", "AS", "VF", "VI"]
EAST_ASIAN = 1 << 6
INITIAL_PUNCTUATION = 1 << 7
FINAL_PUNCTUATION = 1 << 8
PICTOGRAPH_UNASSIGNED = 1 << 9

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


def graphemeClasses(paths):
    table = {}
    for a, b, f in ranges(paths["GraphemeBreakProperty.txt"], everything):
        for c in range(a, b + 1):
            table[c] = table.get(c, 0) | GCB.index(f[1])
    for c in pictographs(paths):
        table[c] = table.get(c, 0) | PICTOGRAPHIC
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
            "Grapheme_Cluster_Break, bit 4 Extended_Pictographic, bits 5-6 Indic_Conjunct_Break.",
            "The Hangul syllables are computed, so their entry holds 0xFF.",
        ], packedRanges(graphemeClasses(paths), graphemeHangul, 0xFF))
        writeTable(
            "src/void2d/lineBreakTable.h", "kVoid2dLineBreakRanges", "VOID2D_LINE_BREAK_RANGES", 11, [
            "(start << 11) | class, sorted; a range runs to the next start. Class: bits 0-5",
            "Line_Break after LB1, bit 6 East_Asian_Width F/W/H, bit 7 gc=Pi, bit 8 gc=Pf,",
            "bit 9 Extended_Pictographic and gc=Cn. The Hangul syllables are computed: 0x7FF.",
        ], packedRanges(lineBreakClasses(paths), lineBreakHangul, 0x7FF))
        writeRows(paths["GraphemeBreakTest.txt"], "GraphemeBreakTest")
        writeRows(paths["LineBreakTest.txt"], "LineBreakTest")


if __name__ == "__main__":
    if sys.argv[1:] != ["regen"]:
        sys.exit("usage: python tests/oracle/ucd.py regen")
    regen()
