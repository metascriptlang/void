import json
import struct
import sys
import zlib

import resvg_py

CASES = "tests/oracle/svg.rows"
SVG_DIR = "tests/oracle/svg/"
OUTPUT = "tests/oracle/svg.json"


def readCases():
    rows = []
    for line in open(CASES, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        rowId, name, side = line.split("\t")
        rows.append((rowId, name, int(side)))
    return rows


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def alphaOfPng(png):
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    pos, data, header = 8, b"", None
    while pos < len(png):
        length, kind = struct.unpack(">I4s", png[pos:pos + 8])
        body = png[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            data += body
        pos += 12 + length
    width, height, depth, colour, _, _, interlace = header
    assert depth == 8 and colour == 6 and interlace == 0, "resvg should give 8-bit RGBA"
    raw = zlib.decompress(data)
    stride = width * 4
    rows, previous = [], bytearray(stride)
    for y in range(height):
        base = y * (stride + 1)
        filt, line = raw[base], bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = previous[i]
            upLeft = previous[i - 4] if i >= 4 else 0
            if filt == 1:
                line[i] = (line[i] + left) & 255
            elif filt == 2:
                line[i] = (line[i] + up) & 255
            elif filt == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif filt == 4:
                line[i] = (line[i] + paeth(left, up, upLeft)) & 255
        rows.append(line)
        previous = line
    return width, height, bytes(line[i] for line in rows for i in range(3, stride, 4))


def regen():
    rows = []
    for rowId, name, side in readCases():
        svg = open(SVG_DIR + name, encoding="utf-8").read()
        png = bytes(resvg_py.svg_to_bytes(svg_string=svg, width=side, height=side))
        width, height, alpha = alphaOfPng(png)
        assert width == side and height == side
        rows.append({"id": rowId, "file": name, "side": side, "alpha": alpha.hex()})
    out = {
        "generator": "python tests/oracle/svg.py regen",
        "resvg": resvg_py.__resvg_version__,
        "resvgPy": resvg_py.__version__,
        "alpha": "the 8-bit alpha plane, row by row from the top, two hex digits a pixel",
        "rows": rows,
    }
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, separators=(",", ":"))
        f.write("\n")
    print("wrote %s: %d rows, resvg %s" % (OUTPUT, len(rows), resvg_py.__resvg_version__))


if __name__ == "__main__":
    if sys.argv[1:] == ["regen"]:
        regen()
    else:
        sys.exit("usage: python tests/oracle/svg.py regen")
