import os
import struct

OUT = "tests/fonts/cmap/"
TRUETYPE = b"\x00\x01\x00\x00"
UNICODE_BMP = (3, 1)
UNICODE_FULL = (3, 10)


def u8(*values):
    return bytes(values)


def u16(*values):
    return b"".join(struct.pack(">H", v) for v in values)


def u24(value):
    return struct.pack(">I", value)[1:]


def u32(*values):
    return b"".join(struct.pack(">I", v) for v in values)


def log2(n):
    return n.bit_length() - 1


def format0(glyphs, length=262):
    array = bytearray(256)
    for codepoint, glyph in glyphs.items():
        array[codepoint] = glyph
    return u16(0, length, 0) + bytes(array)


def format6(first, glyphs):
    return u16(6, 10 + 2 * len(glyphs), 0, first, len(glyphs)) + u16(*glyphs)


def format4(segments):
    count = len(segments)
    ends = u16(*[s[1] for s in segments])
    starts = u16(*[s[0] for s in segments])
    deltas = b"".join(struct.pack(">h", s[2]) for s in segments)
    array = []
    offsets = []
    for i, (_, _, _, glyphs) in enumerate(segments):
        if glyphs is None:
            offsets.append(0)
        else:
            offsets.append(2 * (count - i) + 2 * len(array))
            array.extend(glyphs)
    searchRange = 2 * (1 << log2(count))
    body = (ends + u16(0) + starts + deltas + u16(*offsets) + u16(*array))
    head = u16(4, 14 + len(body), 0, 2 * count, searchRange, log2(count),
               2 * count - searchRange)
    return head + body


def groups(kind, rows):
    body = b"".join(u32(*row) for row in rows)
    return u16(kind, 0) + u32(16 + len(body), 0, len(rows)) + body


def format14(selectors):
    records = b""
    tables = b""
    base = 10 + 11 * len(selectors)
    for selector, defaults, specifics in selectors:
        defaultOffset = specificOffset = 0
        if defaults:
            defaultOffset = base + len(tables)
            tables += u32(len(defaults)) + b"".join(u24(a) + u8(n) for a, n in defaults)
        if specifics:
            specificOffset = base + len(tables)
            tables += u32(len(specifics)) + b"".join(u24(c) + u16(g) for c, g in specifics)
        records += u24(selector) + u32(defaultOffset, specificOffset)
    return u16(14) + u32(10 + len(records) + len(tables), len(selectors)) + records + tables


def cmap(records):
    head = u16(0, len(records))
    pointer = 4 + 8 * len(records)
    entries = b""
    body = b""
    for platform, encoding, table in records:
        if isinstance(table, int):
            entries += u16(platform, encoding) + u32(table)
        else:
            entries += u16(platform, encoding) + u32(pointer + len(body))
            body += table
    return head + entries + body


def sfnt(cmapBytes, magic=TRUETYPE, outlines=("glyf", "loca"), directoryLength=None,
         directoryOffset=None, cff=None, usable=False):
    tables = {"cmap": cmapBytes, "head": bytes(54), "hhea": bytes(36), "hmtx": bytes(4),
              "maxp": u32(0x10000) + u16(64) + bytes(26)}
    for tag in outlines:
        tables[tag] = bytes(8)
    if cff is not None:
        tables["CFF "] = cff
    if usable:
        tables["head"] = bytes(18) + u16(1000) + bytes(34)
        tables["hhea"] = bytes(4) + struct.pack(">hh", 800, -200) + bytes(26) + u16(1)
        tables["hmtx"] = u16(500, 0)
    tags = sorted(tables)
    count = len(tags)
    searchRange = 16 * (1 << log2(count))
    head = magic + u16(count, searchRange, log2(count), 16 * count - searchRange)
    position = 12 + 16 * count
    directory = b""
    body = b""
    for tag in tags:
        data = tables[tag]
        padded = data + bytes(-len(data) % 4)
        offset = position + len(body)
        length = len(data)
        if tag == "cmap" and directoryOffset is not None:
            offset = directoryOffset
        if tag == "cmap" and directoryLength is not None:
            length = directoryLength
        directory += tag.encode().ljust(4) + u32(0, offset, length)
        body += padded
    return head + directory + body


def collection(offset):
    return b"ttcf" + u32(0x00010000, 1, offset) + bytes(16)


def save(name, data):
    os.makedirs(OUT, exist_ok=True)
    with open(OUT + name, "wb") as f:
        f.write(data)


def latinSegments():
    return [(0x41, 0x43, 1 - 0x41, None), (0xFFFF, 0xFFFF, 1, None)]


def saveCmap(name, records, **options):
    save(name, sfnt(cmap(records), **options))


def hostile():
    control4 = format4(latinSegments())
    control12 = groups(12, [(0x1F600, 0x1F602, 10)])
    control14 = format14([(0xFE0F, [(0x2700, 2)], [(0x1F600, 7)])])
    saveCmap("controlFormat4.ttf", [(*UNICODE_BMP, control4)])
    saveCmap("controlFormat12.ttf", [(*UNICODE_FULL, control12)])
    saveCmap("controlFormat14.ttf", [(0, 3, control12), (0, 5, control14)])

    saveCmap("offsetNear2G.ttf", [(*UNICODE_BMP, 0x7FFFFFFE)])
    saveCmap("offsetNegative.ttf", [(*UNICODE_BMP, 0xFFFFFFF0)])
    saveCmap("offsetAtEnd.ttf", [(*UNICODE_BMP, 12)])
    saveCmap("offsetLastByte.ttf", [(*UNICODE_BMP, 11)])
    save("recordCountHuge.ttf", sfnt(u16(0, 0xFFFF) + u16(*UNICODE_BMP) + u32(0)))

    saveCmap("format4SegcountHuge.ttf",
             [(*UNICODE_BMP, u16(4, 32, 0, 0xFFFE, 0x20, 4, 0x1E) + bytes(18))])
    saveCmap("format6CountHuge.ttf", [(*UNICODE_BMP, u16(6, 14, 0, 0, 0xFFFF) + u16(1, 2))])
    saveCmap("format12GroupsHuge.ttf",
             [(*UNICODE_FULL, u16(12, 0) + u32(28, 0, 0xFFFFFFFF) + u32(0x1F600, 0x1F602, 10))])
    hostile14 = u16(14) + u32(21, 1) + u24(0xFE0F) + u32(0xFFFFFFF0, 0x7FFFFFFE)
    saveCmap("format14OffsetsOutside.ttf", [(0, 3, control12), (0, 5, hostile14)])
    saveCmap("format14CountHuge.ttf",
             [(0, 3, control12), (0, 5, u16(14) + u32(10, 0xFFFFFFFF))])

    save("directoryWraps.ttf", sfnt(cmap([(*UNICODE_BMP, control4)]),
                                    directoryOffset=0xFFFFFFF8, directoryLength=0x20))
    save("collectionOffsetHuge.ttc", collection(0x7FFFFFF8))
    save("collectionOffsetNegative.ttc", collection(0xFFFFFFFC))

    save("truncatedInRecords.ttf", sfnt(cmap([(*UNICODE_BMP, control4),
                                              (*UNICODE_FULL, control12)])[:17]))
    save("truncatedFormat4.ttf", sfnt(cmap([(*UNICODE_BMP, control4)])[:12 + 20]))
    save("truncatedFormat12.ttf", sfnt(cmap([(*UNICODE_FULL, groups(
        12, [(0x41, 0x43, 1), (0x1F600, 0x1F602, 10)]))])[:12 + 16 + 12 + 5]))
    save("truncatedFormat14.ttf",
         sfnt(cmap([(0, 3, control12), (0, 5, control14)])[:-9]))


def cffWithType1Charstrings():
    name = u16(1) + u8(1) + u8(1, 2) + b"x"
    top = u8(0x8C, 0x0C, 0x06)
    topIndex = u16(1) + u8(1) + u8(1, 1 + len(top)) + top
    return u8(1, 0, 4, 1) + name + topIndex + u16(0) + u16(0)


def unloadable():
    saveCmap("coversButUnloadable.otf", [(*UNICODE_FULL, groups(12, [(0x1F600, 0x1F602, 1)]))],
             magic=b"OTTO", outlines=(), cff=cffWithType1Charstrings())


def joiners():
    table = groups(12, [(0x200D, 0x200D, 1), (0xFE0F, 0xFE0F, 2)])
    saveCmap("joiners.ttf", [(*UNICODE_FULL, table)], usable=True)


def formats():
    saveCmap("format0Full.ttf", [(0, 3, format0({0x41: 5, 0x50: 6, 0xFF: 7}))])
    saveCmap("format0Short.ttf", [(0, 3, format0({0x41: 5, 0x4F: 6, 0x50: 7}, length=86))])
    saveCmap("format6.ttf", [(0, 3, format6(0x30, [1, 2, 0])),
                             (1, 0, format6(0x30, [7, 7, 7, 7]))])
    saveCmap("format4.ttf", [(*UNICODE_BMP, format4([
        (0x41, 0x43, 1 - 0x41, None),
        (0x61, 0x62, 0, [3, 0]),
        (0x200, 0x201, 1 - 0x200, None),
        (0xFFFF, 0xFFFF, 1, None),
    ]))])
    saveCmap("format4NoTerminal.ttf", [(*UNICODE_BMP, format4([
        (0x41, 0x43, 1 - 0x41, None),
        (0x61, 0x62, 0, [3, 0]),
    ])), (1, 0, format6(0x30, [7, 7, 7, 7]))])
    saveCmap("format12.ttf", [(*UNICODE_FULL, groups(12, [
        (0x300, 0x3FF, 0), (0x1F600, 0x1F602, 10), (0x20000, 0x20002, 20)]))])
    saveCmap("format13.ttf", [(*UNICODE_FULL, groups(13, [
        (0x100, 0x1FF, 3), (0x300, 0x3FF, 0)]))])
    saveCmap("format2.ttf", [(0, 3, u16(2, 6, 0))])
    saveCmap("format10.ttf", [(0, 3, u16(10, 0) + u32(22, 0, 0x41, 1) + u16(5))])

    a = format6(0x41, [1])
    b = format6(0x42, [1])
    c = format6(0x43, [1])
    saveCmap("choiceMsThenUnicode.ttf", [(3, 1, a), (0, 3, b)])
    saveCmap("choiceUnicodeThenMs.ttf", [(0, 3, b), (3, 1, a)])
    saveCmap("choiceUnicodeTwice.ttf", [(0, 3, b), (0, 4, c)])
    saveCmap("choiceMsFullThenBmp.ttf", [(3, 10, b), (3, 1, a)])
    saveCmap("choiceMsBmpThenFull.ttf", [(3, 1, a), (3, 10, b)])
    saveCmap("choiceMacThenMsFull.ttf", [(1, 0, b), (3, 10, a)])
    saveCmap("choiceIgnored.ttf", [(3, 0, a), (3, 2, b), (1, 0, c), (1, 1, c), (1, 10, b)])

    base = groups(12, [(0x41, 0x43, 1)])
    sequences = format14([
        (0xFE0E, [(0x2700, 2), (0x2764, 0)], [(0x1F600, 7), (0x1F601, 0)]),
        (0xFE0F, [(0x2700, 2)], [(0x2701, 9)]),
        (0xE0100, [(0x41, 0)], []),
    ])
    saveCmap("sequences.ttf", [(0, 5, sequences), (3, 10, base)])
    saveCmap("sequenceNotFormat14.ttf", [(0, 5, u16(12) + sequences[2:]), (3, 10, base)])
    saveCmap("sequenceWrongEncoding.ttf", [(0, 4, sequences), (3, 10, base)])
    saveCmap("sequenceWrongPlatform.ttf", [(1, 5, sequences), (3, 10, base)])


if __name__ == "__main__":
    hostile()
    formats()
    unloadable()
    joiners()
