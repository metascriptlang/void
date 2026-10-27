"""The kb_text_shape tables and break rules: python tests/oracle/kbTables.py

Reads deps/kb/kb_text_shape.h and writes
  src/void2d/kb/unicodeTables.ms  one const array per data table the shaper reaches (the paged
                                  property tables with their page indices, the parent deltas and
                                  the script extension lists), every element typed as the C declares it
  src/void2d/kb/breakTables.ms    from kbts__BreakAddCodepoint: the line and word break class
                                  numbers, the grapheme transition table and the history rule
                                  switches as match statements
The gate needs none of it: the outputs are committed and src/test/kbUnicodePortCheck.ms and
src/test/kbBreakPortCheck.ms pin them against digests recorded from the C.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HEADER = os.path.join(ROOT, "deps", "kb", "kb_text_shape.h")
OUTPUT = os.path.join(ROOT, "src", "void2d", "kb", "unicodeTables.ms")
BREAK_OUTPUT = os.path.join(ROOT, "src", "void2d", "kb", "breakTables.ms")

TYPES = {"kbts_u8": "uint8", "kbts_u16": "uint16", "kbts_u32": "uint32", "kbts_u64": "uint64", "kbts_s32": "int32"}
FAMILIES = [
    "Decomposition", "WordBreakClass", "LineBreakClass", "GraphemeBreakClass", "SyllabicInfo",
    "Flags", "BidirectionalClass", "JoiningType", "CombiningClass", "ParentInfo", "UseClass",
    "ScriptExtension", "MirrorCodepoint",
]
SINGLES = {"UnicodeParentDeltas": "KB_PARENT_DELTAS", "ScriptExtensions": "KB_SCRIPT_EXTENSIONS"}
PER_ROW = 32
WORD_BITS = r"KBTS_WORD_BREAK_BITS\((\d), (\d)\)"
WORD_SUM = rf"{WORD_BITS}(?: \| {WORD_BITS})*"
LINE_STATEMENTS = {
    re.compile(r"KBTS_LINE_UNBREAK\((\d), (\d)\)"): "rules.unbreaks |= kbLineRequired({0}, {1});",
    re.compile(r"KBTS_LINE_BREAK\((\d), (\d)\)"): "rules.breaks |= kbLineAllowed({0}, {1});",
    re.compile(r"LineBreakHistory = 0"): "rules.history = 0;",
}


def screaming(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).upper()


def tables(text):
    found = {}
    pattern = re.compile(r"^static (kbts_\w+) kbts__(\w+)\[(\d+)\] = \{\n(.*?)^\};", re.S | re.M)
    for m in pattern.finditer(text):
        values = [v.strip() for v in m.group(4).replace("\n", " ").split(",") if v.strip()]
        values = [re.sub(r"ull$", "", v) for v in values]
        if len(values) != int(m.group(3)):
            raise SystemExit(f"{m.group(2)}: declared {m.group(3)} elements, parsed {len(values)}")
        found[m.group(2)] = (TYPES[m.group(1)], values)
    return found


def block(name, kind, values):
    lines = [f"export const {name}: {kind}[] = ["]
    for i in range(0, len(values), PER_ROW):
        lines.append("\t" + ",".join(values[i:i + PER_ROW]) + ",")
    lines.append("];")
    return lines


def enum_values(text, name, prefix):
    m = re.search(r"enum " + name + r"\s*\{(.*?)\};", text, re.S)
    body = re.sub(r"//[^\n]*|/\*.*?\*/", "", m.group(1), flags=re.S)
    entries = [e.strip() for e in body.split(",") if e.strip()]
    if any("=" in e for e in entries):
        raise SystemExit(f"{name}: explicit enum values are not handled")
    return {e[len(prefix):]: i for i, e in enumerate(entries)}


def balanced(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    raise SystemExit("unbalanced braces")


def switch_body(text, head):
    return balanced(text, text.index("{", text.index(head)))


def case_groups(body, classes, width):
    body = re.sub(r"//[^\n]*", "", body)
    piece = re.compile(r"\s*(?:KBTS_C(\d)\(([^)]*)\)\s*:|([^;]+);)")
    out, labels, stmts, at = [], [], [], 0
    while True:
        m = piece.match(body, at)
        if not m:
            break
        at = m.end()
        if m.group(1):
            names = [n.strip() for n in m.group(2).split(",")]
            if len(names) != int(m.group(1)) or len(names) != width:
                raise SystemExit(f"label {m.group(0).strip()}: expected {width} classes")
            if stmts and stmts[-1] == "KBTS__FALLTHROUGH":
                out.append((labels, stmts[:-1], True))
                labels, stmts = [], []
            elif stmts:
                raise SystemExit(f"statements without break before {m.group(0).strip()}")
            key = 0
            for n in names:
                if n not in classes:
                    raise SystemExit(f"unknown class {n}")
                key = key << 8 | classes[n]
            labels.append(key)
        else:
            stmt = " ".join(m.group(3).split())
            if stmt == "break":
                out.append((labels, stmts, False))
                labels, stmts = [], []
            else:
                stmts.append(stmt)
    if body[at:].strip() or labels or stmts:
        raise SystemExit(f"unparsed switch tail: {body[at:at + 60]!r}")
    return [(labels, stmts + (out[i + 1][1] if falls else [])) for i, (labels, stmts, falls) in enumerate(out)]


def word_sum(text):
    return " | ".join(f"kbWordBits({a}, {b})" for a, b in re.findall(WORD_BITS, text))


def statement(stmt, word):
    for pattern, template in LINE_STATEMENTS.items():
        m = pattern.fullmatch(stmt)
        if m and not word:
            return template.format(*m.groups())
    if word:
        m = re.fullmatch(rf"WordUnbreaks \|= ({WORD_SUM})", stmt)
        if m:
            return f"rules.unbreaks |= {word_sum(m.group(1))};"
        m = re.fullmatch(rf"if\(WordBreak2PositionOffset >= 0\) WordUnbreaks \|= ({WORD_SUM})", stmt)
        if m:
            return f"if (wordBreak2PositionOffset >= 0) {{ rules.unbreaks |= {word_sum(m.group(1))}; }}"
        if stmt == "WordBreakHistory = 0":
            return "rules.history = 0;"
    raise SystemExit(f"unhandled rule statement: {stmt}")


def rule_function(name, extra, rules_type, mask, entries, word):
    seen = set()
    lines = [f"export function {name}(ref rules: {rules_type}{extra}): void {{",
             f"\tmatch (rules.history{mask}) {{"]
    for labels, stmts in entries:
        for key in labels:
            if key in seen:
                raise SystemExit(f"{name}: duplicate label {key}")
            seen.add(key)
        row = "\t\t"
        for i, key in enumerate(labels):
            text = str(key) + (" | " if i + 1 < len(labels) else " => {")
            if len(row) + len(text) > 88:
                lines.append(row.rstrip())
                row = "\t\t\t"
            row += text
        lines.append(row)
        lines += [f"\t\t\t{statement(s, word)}" for s in stmts]
        lines.append("\t\t},")
    lines += ["\t\t_ => {},", "\t}", "}"]
    return lines


def break_tables(text):
    start = text.index("static void kbts__BreakAddCodepoint(")
    code = text[start:text.index("KBTS_EXPORT void kbts_BreakEnd", start)]
    line = enum_values(text, "kbts_line_break_class_enum", "KBTS_LINE_BREAK_CLASS_")
    word = enum_values(text, "kbts_word_break_class_enum", "KBTS_WORD_BREAK_CLASS_")
    out = [
        "// Generated by tests/oracle/kbTables.py from deps/kb/kb_text_shape.h. Do not edit.",
        "// A rule label is the class numbers of the history, one byte each, the oldest class highest.",
        "",
        "export struct KbLineRules {",
        "\tbreaks: uint64;",
        "\tunbreaks: uint64;",
        "\thistory: uint32;",
        "}",
        "",
        "export struct KbWordRules {",
        "\tunbreaks: uint32;",
        "\thistory: uint32;",
        "}",
        "",
        "export function kbLineAllowed(priority: uint64, position: uint64): uint64 {",
        "\treturn (((1 as uint64) << (priority + 1)) - 1) << (position * 16);",
        "}",
        "",
        "export function kbLineRequired(priority: uint64, position: uint64): uint64 {",
        "\treturn (((((1 as uint64) << (priority + 1)) - 1) << 6) | kbLineAllowed(priority, 0)) <<",
        "\t\t(position * 16);",
        "}",
        "",
        "export function kbWordBits(priority: uint32, position: uint32): uint32 {",
        "\treturn (((1 as uint32) << (priority + 1)) - 1) << (position * 4);",
        "}",
        "",
    ]
    for prefix, classes in (("LINE", line), ("WORD", word)):
        for name, value in classes.items():
            out.append(f"export const KB_{prefix}_BREAK_CLASS_{name.upper()}: uint8 = {value};")
        out.append("")
    scripts = enum_values(text, "kbts_script_enum", "KBTS_SCRIPT_")
    for name in ("DONT_KNOW", "DEFAULT", "DEFAULT2"):
        out.append(f"export const KB_SCRIPT_{name}: uint32 = {scripts[name]};")
    out.append("")
    transition =re.search(r"kbts_GraphemeBreakTransition\[[^=]*=\s*\{(.*?)^\};", text, re.S | re.M).group(1)
    rows = re.findall(r"/\*\s*(\d+) \*/\s*\{([^}]*)\}", transition)
    cells = [int(v) for _, row in rows for v in row.split(",")]
    if len(rows) != 18 or len(cells) != 18 * 13:
        raise SystemExit(f"grapheme transition table is {len(rows)} rows, {len(cells)} cells")
    out.append("export const KB_GRAPHEME_BREAK_TRANSITION: uint8[] = [")
    for i in range(0, len(cells), 13):
        out.append("\t" + ",".join(str(c) for c in cells[i:i + 13]) + ",")
    out += ["];", ""]
    line_two = case_groups(switch_body(code, "switch(LineBreakHistory & 0xFFFF)"), line, 2)
    line_three = case_groups(switch_body(code, "switch(LineBreakHistory & 0xFFFFFF)"), line, 3)
    line_four = case_groups(switch_body(code, "switch(LineBreakHistory)\n"), line, 4)
    word_two = case_groups(switch_body(code, "switch(WordBreakHistory & 0xFFFF)"), word, 2)
    word_three = case_groups(switch_body(code, "switch(WordBreakHistory & 0xFFFFFF)"), word, 3)
    out += rule_function("kbLineRules2", "", "KbLineRules", " & 0xFFFF", line_two, False) + [""]
    out += rule_function("kbLineRules3", "", "KbLineRules", " & 0xFFFFFF", line_three, False) + [""]
    out += rule_function("kbLineRules4", "", "KbLineRules", "", line_four, False) + [""]
    out += rule_function("kbWordRules2", ", wordBreak2PositionOffset: int32", "KbWordRules", " & 0xFFFF", word_two, True) + [""]
    out += rule_function("kbWordRules3", "", "KbWordRules", " & 0xFFFFFF", word_three, True)
    return out


def main():
    text = open(HEADER, encoding="utf-8").read()
    found = tables(text)
    out = [
        "// Generated by tests/oracle/kbTables.py from deps/kb/kb_text_shape.h. Do not edit.",
        "// Element types are the C's. A paged table is read as DATA[PAGES[cp >> shift] << shift | cp & mask].",
    ]
    for family in FAMILIES:
        for part, suffix in (("PageIndices", "PAGES"), ("Data", "DATA")):
            kind, values = found[f"Unicode{family}_{part}"]
            out += block(f"KB_{screaming(family)}_{suffix}", kind, values)
    for source, name in SINGLES.items():
        kind, values = found[source]
        out += block(name, kind, values)
    open(OUTPUT, "w", newline="\n").write("\n".join(out) + "\n")
    print(f"wrote {OUTPUT}", file=sys.stderr)
    open(BREAK_OUTPUT, "w", newline="\n").write("\n".join(break_tables(text)) + "\n")
    print(f"wrote {BREAK_OUTPUT}", file=sys.stderr)


main()
