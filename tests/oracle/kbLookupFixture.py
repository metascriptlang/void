"""The lookup fixture of the kb shaper: python tests/oracle/kbLookupFixture.py

Builds a small font whose GSUB and GPOS carry every lookup type and format that
src/void2d/kb/gsub.ms and gpos.ms apply (extension, contextual, chained, reverse chaining, pair
formats 1 and 2, cursive, mark to base, ligature and mark, GDEF classes, mark attachment classes,
mark filtering sets and a GDEF variation store with variation index devices), and writes it as
hex into src/test/kbLookupFixtures.ms next to the word list the pins and the differential run.
Pass --report to print the (table, lookup type, format) set the font reaches.
"""
import os
import sys

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import otTables as ot

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(ROOT, "src", "test", "kbLookupFixtures.ms")
UPEM = 1000
CREATED = 3786825600

BASES = list("abcdefghijklmno")
CAPS = list("ABCDEFGHIJKLMNO")
MARKS = ["acute", "grave", "dot", "tilde"]
LIGS = ["f_i", "f_f_i", "f_l", "a_b", "g_h"]
EXTRA = ["a.1", "a.2", "a.3", "space", "zwnj", "zwj"]
ORDER = [".notdef"] + BASES + CAPS + MARKS + LIGS + EXTRA

CMAP = {}
for name in BASES + CAPS:
    CMAP[ord(name)] = name
CMAP.update({0x301: "acute", 0x300: "grave", 0x307: "dot", 0x303: "tilde", 0x20: "space",
             0x200C: "zwnj", 0x200D: "zwj"})

ADVANCES = {name: 500 + (index * 37) % 300 for index, name in enumerate(ORDER)}
for name in MARKS:
    ADVANCES[name] = 0

FEATURES = """
languagesystem DFLT dflt;
languagesystem latn dflt;

@bases = [%(bases)s];
@ligs = [%(ligs)s];
@marks = [%(marks)s];
@topMarks = [acute grave];
@maA = [acute];
@maB = [grave dot];

table GDEF {
    GlyphClassDef @bases, @ligs, @marks, ;
} GDEF;

markClass [acute grave tilde] <anchor 250 700> @TOP;
markClass dot <anchor 250 0> @BOT;
markClass grave <anchor 0 120> @TOPMARK;

lookup nestedUpper { sub b by B; sub c by C; sub e by E; } nestedUpper;
lookup nestedNext { sub i by I; sub d by D; } nestedNext;
lookup nestedKern { pos a <-30 10 -20 0>; pos b <40 -10 50 0>; pos c <0 0 10 10>; } nestedKern;
lookup nestedKern2 { pos d <5 5 5 5>; pos f <-9 -9 -9 -9>; } nestedKern2;

feature ss01 { sub [m n o] by [M N O]; } ss01;
feature ss02 { sub a by C; sub b by A; sub c by B; sub k by K; } ss02;
feature ss03 { sub f_i by f i; sub a_b by a b; sub g_h by g h; sub m by m n o; } ss03;
feature ss04 { sub a from [a.1 a.2 a.3]; sub b from [B C]; } ss04;
feature ss05 {
    sub f f i by f_f_i;
    sub f i by f_i;
    sub f l by f_l;
    sub a b by a_b;
    sub g h by g_h;
} ss05;
feature ss06 { lookupflag IgnoreMarks; sub f i by f_i; sub a b by a_b; } ss06;
feature ss07 { lookupflag MarkAttachmentType @maA; sub f i by f_i; sub g h by g_h; } ss07;
feature ss08 { lookupflag UseMarkFilteringSet [acute]; sub f i by f_i; sub a b by a_b; } ss08;
feature ss09 { lookupflag IgnoreLigatures; sub a b by a_b; sub f l by f_l; } ss09;
feature ss10 { lookupflag IgnoreBaseGlyphs; sub acute dot by tilde; } ss10;

feature ss11 { sub a' lookup nestedUpper b' lookup nestedNext c; } ss11;
feature ss12 { sub @bases' lookup nestedUpper @marks' lookup nestedNext; } ss12;
feature ss13 { sub a b' lookup nestedUpper c' lookup nestedNext d; } ss13;
feature ss14 { sub [a b] [c d]' lookup nestedUpper e; sub e' lookup nestedNext [a b]; } ss14;
feature ss15 {
    lookupflag IgnoreMarks;
    sub a' lookup nestedUpper b' lookup nestedNext;
} ss15;
feature ss16 { sub [a b c]' lookup nestedUpper [d e]'; } ss16;
feature ss17 { sub @bases' lookup nestedUpper; } ss17;
feature ss18 { rsub a' b by B; rsub [c d] e' by E; } ss18;
feature ss19 { rsub @bases' @marks by @caps; } ss19;
lookup extSingle useExtension { sub [a b c] by [A B C]; } extSingle;
feature ss20 { lookup extSingle; } ss20;
lookup extLig useExtension { sub f i by f_i; sub f f i by f_f_i; } extLig;
feature ss21 { lookup extLig; } ss21;
lookup extCtx useExtension { sub a' lookup nestedUpper b' lookup nestedNext; } extCtx;
feature ss22 { lookup extCtx; } ss22;

feature kern {
    pos a b -50;
    pos f i -30;
    pos A B -80;
    subtable;
    pos [a b c] [d e] -20;
    pos [m n] [o] 15;
    pos @bases [f g h] -5;
} kern;
feature ss23 { pos a <10 0 20 0>; pos [b c] <5 5 5 5>; } ss23;
feature ss24 { pos d <1 2 3 4>; pos e <5 6 7 8>; pos f <-1 -2 -3 -4>; } ss24;
feature ss25 { pos a <1 2 3 4> b <5 6 7 8>; pos a <0 0 0 0> c <3 3 3 3>; } ss25;
feature ss26 { lookupflag IgnoreMarks; pos a b -40; } ss26;
feature ss27 { pos a <-40 0 0 0> b <20 0 0 0>; } ss27;

feature curs { pos cursive g <anchor 0 0> <anchor 400 40>; pos cursive h <anchor 20 -10> <anchor 380 30>; pos cursive j <anchor NULL> <anchor 300 0>; pos cursive k <anchor 10 10> <anchor NULL>; } curs;
feature ss28 { lookupflag RightToLeft; pos cursive g <anchor 0 0> <anchor 400 40>; pos cursive h <anchor 20 -10> <anchor 380 30>; } ss28;
feature ss29 { lookupflag RightToLeft IgnoreMarks; pos cursive g <anchor 0 0> <anchor 400 40>; pos cursive h <anchor 20 -10> <anchor 380 30>; } ss29;

feature mark {
    pos base [a e i o] <anchor 250 650> mark @TOP;
    pos base [a e] <anchor 250 -10> mark @BOT;
    pos base [b c d] <anchor 300 700> mark @TOP;
} mark;
feature ss30 { pos ligature f_i <anchor 100 700> mark @TOP <anchor 100 0> mark @BOT ligComponent <anchor 400 700> mark @TOP <anchor 400 0> mark @BOT; pos ligature a_b <anchor 100 700> mark @TOP <anchor 100 0> mark @BOT ligComponent <anchor 500 700> mark @TOP <anchor 500 0> mark @BOT; } ss30;
feature mkmk { pos mark grave <anchor 0 400> mark @TOPMARK; } mkmk;
feature ss31 { lookupflag IgnoreMarks; pos base a <anchor 250 650> mark @TOP; } ss31;
feature ss32 { lookupflag UseMarkFilteringSet [acute grave]; pos base [a e] <anchor 250 650> mark @TOP; } ss32;

feature ss33 { pos a' lookup nestedKern b' lookup nestedKern2; } ss33;
feature ss34 { pos @bases' lookup nestedKern @marks' lookup nestedKern2; } ss34;
feature ss35 { pos a b' lookup nestedKern c' lookup nestedKern2 d; } ss35;
feature ss36 { pos [a b] [c d]' lookup nestedKern e; pos e' lookup nestedKern2 [a b]; } ss36;
lookup extPair useExtension { pos a b -77; pos f i 33; } extPair;
feature ss37 { lookup extPair; } ss37;
lookup extMark useExtension { pos base a <anchor 250 650> mark @TOP; } extMark;
feature ss38 { lookup extMark; } ss38;
"""


def draw(name):
    pen = TTGlyphPen(None)
    advance = ADVANCES[name]
    pen.moveTo((50, 0))
    pen.lineTo((50, 600))
    pen.lineTo((max(advance, 100) - 50, 600))
    pen.lineTo((max(advance, 100) - 50, 0))
    pen.closePath()
    return pen.glyph()


def add_variation_store(font):
    from fontTools.varLib import builder

    gdef = font["GDEF"].table
    regions = [
        {"wght": (0.0, 1.0, 1.0)},
        {"wght": (-1.0, -1.0, 0.0), "wdth": (0.0, 0.5, 1.0)},
        {"wght": (0.0, 0.5, 1.0), "wdth": (-1.0, -0.5, 0.0)},
    ]
    region_list = builder.buildVarRegionList(regions, ["wght", "wdth"])
    data0 = builder.buildVarData([0, 1, 2], [[20, -30, 4], [-7, 50, 100], [300, 5, -9]], optimize=False)
    data1 = builder.buildVarData([0, 2], [[11, -12], [60, 70]], optimize=False)
    gdef.VarStore = builder.buildVarStore(region_list, [data0, data1])
    gdef.Version = 0x00010003


def device(outer, inner):
    table = ot.Device()
    table.StartSize = outer
    table.EndSize = inner
    table.DeltaFormat = 0x8000
    return table


def attach_variation_devices(font):
    gpos = font["GPOS"].table
    changed = 0
    for lookup in gpos.LookupList.Lookup:
        for subtable in lookup.SubTable:
            if lookup.LookupType == 9:
                subtable = subtable.ExtSubTable
            if subtable.LookupType == 4:
                for record in subtable.BaseArray.BaseRecord:
                    for anchor in record.BaseAnchor:
                        if anchor is not None and changed < 6:
                            anchor.Format = 3
                            anchor.XDeviceTable = device(0, changed % 2)
                            anchor.YDeviceTable = device(1, changed % 3 % 2)
                            changed += 1
                for record in subtable.MarkArray.MarkRecord:
                    anchor = record.MarkAnchor
                    if changed < 10:
                        anchor.Format = 3
                        anchor.XDeviceTable = device(1, 0)
                        anchor.YDeviceTable = None
                        changed += 1
            elif subtable.LookupType == 1:
                value = subtable.Value if subtable.Format == 1 else None
                if value is not None:
                    value.XAdvDevice = device(0, 1)
                    value.XPlaDevice = device(1, 1)
                    value.ValueFormat = value.getEffectiveFormat() | 0x0040 | 0x0010
    return changed


def record(cls, sequence_index, lookup_index):
    item = cls()
    item.SequenceIndex = sequence_index
    item.LookupListIndex = lookup_index
    return item


def coverage(glyphs):
    item = ot.Coverage()
    item.glyphs = glyphs
    return item


def class_def(mapping):
    item = ot.ClassDef()
    item.classDefs = mapping
    return item


def find_single(lookups, glyph):
    for index, lookup in enumerate(lookups):
        if lookup.LookupType == 1 and glyph in getattr(lookup.SubTable[0], "mapping", {}):
            return index
    raise SystemExit("no single substitution lookup for " + glyph)


def find_single_pos(lookups, glyph):
    for index, lookup in enumerate(lookups):
        if lookup.LookupType == 1 and glyph in lookup.SubTable[0].Coverage.glyphs:
            return index
    raise SystemExit("no single positioning lookup for " + glyph)


def new_lookup(lookup_type, flag, subtable):
    lookup = ot.Lookup()
    lookup.LookupType = lookup_type
    lookup.LookupFlag = flag
    lookup.SubTable = [subtable]
    lookup.SubTableCount = 1
    return lookup


def add_context_lookups(font):
    gsub = font["GSUB"].table.LookupList.Lookup
    gpos = font["GPOS"].table.LookupList.Lookup
    upper = find_single(gsub, "b")
    nxt = find_single(gsub, "i")
    kern = find_single_pos(gpos, "a")
    kern2 = find_single_pos(gpos, "d")

    def gsub_rules(cls_set, cls_rule, sets_attr, rule_attr, first, rest, lookups):
        rule_set = cls_set()
        rule = cls_rule()
        rule.Input = rest
        rule.SubstLookupRecord = [record(ot.SubstLookupRecord, i, l) for i, l in lookups]
        setattr(rule_set, rule_attr, [rule])
        return rule_set

    st = ot.ContextSubst()
    st.Format = 1
    st.Coverage = coverage(["a", "f"])
    st.SubRuleSet = [
        gsub_rules(ot.SubRuleSet, ot.SubRule, "", "SubRule", "a", ["b", "c"], [(0, upper), (2, nxt)]),
        gsub_rules(ot.SubRuleSet, ot.SubRule, "", "SubRule", "f", ["i"], [(1, upper)]),
    ]
    gsub.append(new_lookup(5, 0, st))

    st = ot.ContextSubst()
    st.Format = 1
    st.Coverage = coverage(["a", "d"])
    st.SubRuleSet = [
        gsub_rules(ot.SubRuleSet, ot.SubRule, "", "SubRule", "a", ["b"], [(0, upper), (1, nxt)]),
        gsub_rules(ot.SubRuleSet, ot.SubRule, "", "SubRule", "d", ["e", "e"], [(0, nxt)]),
    ]
    gsub.append(new_lookup(5, 8, st))

    st = ot.ContextSubst()
    st.Format = 2
    st.Coverage = coverage(["a", "b", "c", "d"])
    st.ClassDef = class_def({"a": 1, "b": 2, "c": 2, "d": 1, "e": 3})
    rule = ot.SubClassRule()
    rule.Class = [2, 3]
    rule.SubstLookupRecord = [record(ot.SubstLookupRecord, 0, upper), record(ot.SubstLookupRecord, 2, nxt)]
    rule2 = ot.SubClassRule()
    rule2.Class = [1]
    rule2.SubstLookupRecord = [record(ot.SubstLookupRecord, 1, upper)]
    class_set = ot.SubClassSet()
    class_set.SubClassRule = [rule, rule2]
    class_set2 = ot.SubClassSet()
    class_set2.SubClassRule = [rule2]
    st.SubClassSet = [None, class_set, class_set2, None]
    gsub.append(new_lookup(5, 0, st))

    st = ot.ChainContextSubst()
    st.Format = 2
    st.Coverage = coverage(["b", "c", "d"])
    st.BacktrackClassDef = class_def({"a": 1, "e": 2})
    st.InputClassDef = class_def({"b": 1, "c": 2, "d": 1})
    st.LookAheadClassDef = class_def({"a": 1, "e": 2, "f": 1})
    rule = ot.ChainSubClassRule()
    rule.Backtrack = [1]
    rule.Input = [2]
    rule.LookAhead = [2, 1]
    rule.SubstLookupRecord = [record(ot.SubstLookupRecord, 0, nxt), record(ot.SubstLookupRecord, 1, upper)]
    rule2 = ot.ChainSubClassRule()
    rule2.Backtrack = []
    rule2.Input = [1]
    rule2.LookAhead = [1]
    rule2.SubstLookupRecord = [record(ot.SubstLookupRecord, 0, upper)]
    set1 = ot.ChainSubClassSet()
    set1.ChainSubClassRule = [rule, rule2]
    set2 = ot.ChainSubClassSet()
    set2.ChainSubClassRule = [rule2]
    st.ChainSubClassSet = [None, set1, set2]
    gsub.append(new_lookup(6, 0, st))

    st = ot.ContextPos()
    st.Format = 1
    st.Coverage = coverage(["a", "f"])
    rule = ot.PosRule()
    rule.Input = ["b", "c"]
    rule.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern), record(ot.PosLookupRecord, 2, kern2)]
    rule2 = ot.PosRule()
    rule2.Input = ["i"]
    rule2.PosLookupRecord = [record(ot.PosLookupRecord, 1, kern)]
    set1 = ot.PosRuleSet()
    set1.PosRule = [rule]
    set2 = ot.PosRuleSet()
    set2.PosRule = [rule2]
    st.PosRuleSet = [set1, set2]
    gpos.append(new_lookup(7, 0, st))

    st = ot.ContextPos()
    st.Format = 2
    st.Coverage = coverage(["a", "b", "c", "d"])
    st.ClassDef = class_def({"a": 1, "b": 2, "c": 2, "d": 1, "e": 3})
    rule = ot.PosClassRule()
    rule.Class = [2, 3]
    rule.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern), record(ot.PosLookupRecord, 2, kern2)]
    rule2 = ot.PosClassRule()
    rule2.Class = [1]
    rule2.PosLookupRecord = [record(ot.PosLookupRecord, 1, kern)]
    class_set = ot.PosClassSet()
    class_set.PosClassRule = [rule, rule2]
    class_set2 = ot.PosClassSet()
    class_set2.PosClassRule = [rule2]
    st.PosClassSet = [None, class_set, class_set2, None]
    gpos.append(new_lookup(7, 0, st))

    st = ot.ContextPos()
    st.Format = 3
    st.Coverage = [coverage(["a", "b"]), coverage(["c", "d", "e"])]
    st.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern), record(ot.PosLookupRecord, 1, kern2)]
    gpos.append(new_lookup(7, 0, st))

    st = ot.ChainContextPos()
    st.Format = 2
    st.Coverage = coverage(["b", "c", "d"])
    st.BacktrackClassDef = class_def({"a": 1, "e": 2})
    st.InputClassDef = class_def({"b": 1, "c": 2, "d": 1})
    st.LookAheadClassDef = class_def({"a": 1, "e": 2, "f": 1})
    rule = ot.ChainPosClassRule()
    rule.Backtrack = [1]
    rule.Input = [2]
    rule.LookAhead = [2, 1]
    rule.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern2), record(ot.PosLookupRecord, 1, kern)]
    rule2 = ot.ChainPosClassRule()
    rule2.Backtrack = []
    rule2.Input = [1]
    rule2.LookAhead = [1]
    rule2.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern)]
    set1 = ot.ChainPosClassSet()
    set1.ChainPosClassRule = [rule, rule2]
    set2 = ot.ChainPosClassSet()
    set2.ChainPosClassRule = [rule2]
    st.ChainPosClassSet = [None, set1, set2]
    gpos.append(new_lookup(8, 0, st))

    st = ot.ChainContextPos()
    st.Format = 1
    st.Coverage = coverage(["b", "d"])
    rule = ot.ChainPosRule()
    rule.Backtrack = ["a"]
    rule.Input = ["c"]
    rule.LookAhead = ["d"]
    rule.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern), record(ot.PosLookupRecord, 1, kern2)]
    rule2 = ot.ChainPosRule()
    rule2.Backtrack = []
    rule2.Input = ["e"]
    rule2.LookAhead = []
    rule2.PosLookupRecord = [record(ot.PosLookupRecord, 0, kern2)]
    set1 = ot.ChainPosRuleSet()
    set1.ChainPosRule = [rule]
    set2 = ot.ChainPosRuleSet()
    set2.ChainPosRule = [rule2]
    st.ChainPosRuleSet = [set1, set2]
    gpos.append(new_lookup(8, 0, st))


def build():
    font = FontBuilder(UPEM, isTTF=True)
    font.setupGlyphOrder(ORDER)
    font.setupCharacterMap(CMAP)
    font.setupGlyf({name: draw(name) for name in ORDER})
    font.setupHorizontalMetrics({name: (ADVANCES[name], 0) for name in ORDER})
    font.setupHorizontalHeader(ascent=800, descent=-200)
    font.setupNameTable({"familyName": "Void Lookup Fixture", "styleName": "Regular"})
    font.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    font.setupPost()
    font.updateHead(created=CREATED, modified=CREATED)
    text = FEATURES % {"bases": " ".join(BASES), "ligs": " ".join(LIGS), "marks": " ".join(MARKS)}
    text = text.replace("@caps", "[%s]" % " ".join(CAPS))
    addOpenTypeFeaturesFromString(font.font, text)
    add_variation_store(font.font)
    attach_variation_devices(font.font)
    add_context_lookups(font.font)
    return font.font


def report(font):
    seen = {}
    for tag in ("GSUB", "GPOS"):
        for lookup in font[tag].table.LookupList.Lookup:
            for subtable in lookup.SubTable:
                kind = lookup.LookupType
                if kind == (7 if tag == "GSUB" else 9):
                    kind = "ext(%d)" % subtable.ExtSubTable.LookupType
                    subtable = subtable.ExtSubTable
                key = (tag, kind, getattr(subtable, "Format", 0))
                seen[key] = seen.get(key, 0) + 1
    for key in sorted(seen, key=str):
        print(key, seen[key])
    print("lookups", len(font["GSUB"].table.LookupList.Lookup), len(font["GPOS"].table.LookupList.Lookup))
    print("glyphs", len(font.getGlyphOrder()))


WORDS = [
    "fi", "ffi", "fl", "ab", "gh", "fii", "ffl", "abab", "ghgh", "fí", "f́i", "ab̀",
    "á", "é", "á̀", "ȧ", "ė́", "á̇", "fí̇",
    "aḃ", "abc", "abcd", "abcde", "bcd", "cde", "mno", "mmno", "ggh", "ghh", "gh́gh",
    "ghjk", "gghhjjkk", "kjhg", "jk", "kj", "g‌h", "g‍h", "f‍i", "f‌i", "a‍b",
    "a͏b", "ab ", "a b", "eí", "ibaa", "baab", "aabb", "bb", "cc", "dd", "ee", "ff",
    "fff", "ffff", "aéi", "oá", "áa", "́a", "́̀a", "á́",
    "à́", "ã", "aã", "ã́", "í̇", "fi̇", "fĺ",
    "fl̇", "gḣ", "mn", "no", "nm", "om", "gf", "ag", "bh", "df", "cf", "ef",
]


def js_string(text):
    return "".join("\\u%04x" % ord(ch) if ord(ch) > 126 or ord(ch) < 32 else ch for ch in text)


def write(font):
    import io

    buffer = io.BytesIO()
    font.save(buffer)
    data = buffer.getvalue()
    lines = [
        "// The lookup fixture of tests/oracle/kbLookupFixture.py, embedded so the pins also run where no",
        "// file can be read.",
        "export const KB_LOOKUP_FIXTURE_HEX: string = \"%s\";" % data.hex(),
        "",
        "export const KB_LOOKUP_WORDS: string[] = [",
    ]
    for word in WORDS:
        lines.append("\t\"%s\"," % js_string(word))
    lines.append("];")
    with open(OUTPUT, "w", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return data


if __name__ == "__main__":
    built = build()
    if "--report" in sys.argv:
        report(TTFont(__import__("io").BytesIO(write(built))))
    else:
        write(built)
