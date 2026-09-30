"""Writes texturedScene.glb, the M23 fixture, from the glTF 2.0.1 specification alone.

Nothing here shares code with src/void3d/gltf.ms or src/assets/image.ms: the PNG is deflated
by zlib and the container is packed by struct, so the decoder is checked against a second
reading of the same specification.

Nodes, left to right on the x axis, all facing the camera at +z:
  factorQuad          untextured, COLOR_0 (1, 0.5, 0.5) times baseColorFactor (0.5, 0.5, 1, 1)
  cube                the 2x2 texture (red, green / blue, yellow) on every face, nearest, clamp
  doubleQuad          doubleSided, turned half a turn about y: the camera sees its back
  doubleTexturedQuad  the same with the texture, seen mirrored from behind
  singleQuad          untextured and single-sided, turned the same way: its back is culled

Run: python tests/fixtures/gltf/makeTexturedGlb.py
"""

import json
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
HALF = 0.6
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def png_rgba(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def face(normal, up):
    right = cross(up, normal)
    centre = [c * HALF for c in normal]

    def corner(sx, sy):
        return tuple(centre[i] + (sx * right[i] + sy * up[i]) * HALF for i in range(3))

    corners = [corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)]
    uvs = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
    return corners, uvs


def cube():
    faces = [
        ((0, 0, 1), (0, 1, 0)), ((0, 0, -1), (0, 1, 0)),
        ((1, 0, 0), (0, 1, 0)), ((-1, 0, 0), (0, 1, 0)),
        ((0, 1, 0), (0, 0, -1)), ((0, -1, 0), (0, 0, 1)),
    ]
    positions, normals, uvs, indices = [], [], [], []
    for normal, up in faces:
        corners, face_uvs = face(normal, up)
        base = len(positions)
        positions += corners
        normals += [normal] * 4
        uvs += face_uvs
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    return positions, normals, uvs, indices


def quad():
    corners, uvs = face((0, 0, 1), (0, 1, 0))
    return corners, [(0, 0, 1)] * 4, uvs, [0, 1, 2, 0, 2, 3]


class Buffer:
    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accessors = []

    def view(self, payload, target=None):
        while len(self.data) % 4:
            self.data.append(0)
        view = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(payload)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        self.data += payload
        return len(self.views) - 1

    def floats(self, rows, kind):
        flat = [v for row in rows for v in row]
        accessor = {"bufferView": self.view(struct.pack("<%df" % len(flat), *flat), ARRAY_BUFFER),
                    "componentType": 5126, "count": len(rows), "type": kind}
        if kind == "VEC3" and rows and len(rows[0]) == 3:
            accessor["min"] = [min(r[i] for r in rows) for i in range(3)]
            accessor["max"] = [max(r[i] for r in rows) for i in range(3)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def indices(self, values):
        packed = struct.pack("<%dH" % len(values), *values)
        self.accessors.append({"bufferView": self.view(packed, ELEMENT_ARRAY_BUFFER),
                               "componentType": 5123, "count": len(values), "type": "SCALAR"})
        return len(self.accessors) - 1


def main():
    buffer = Buffer()
    positions, normals, uvs, indices = cube()
    cube_mesh = {"primitives": [{"attributes": {
        "POSITION": buffer.floats(positions, "VEC3"),
        "NORMAL": buffer.floats(normals, "VEC3"),
        "TEXCOORD_0": buffer.floats(uvs, "VEC2")},
        "indices": buffer.indices(indices), "material": 0}]}
    quad_positions, quad_normals, quad_uvs, quad_indices = quad()
    quad_attributes = {"POSITION": buffer.floats(quad_positions, "VEC3"),
                       "NORMAL": buffer.floats(quad_normals, "VEC3")}
    textured_quad = dict(quad_attributes, TEXCOORD_0=buffer.floats(quad_uvs, "VEC2"))
    quad_index = buffer.indices(quad_indices)
    tinted = dict(quad_attributes, COLOR_0=buffer.floats([(1.0, 0.5, 0.5)] * 4, "VEC3"))
    texture = png_rgba(2, 2, [[255, 0, 0, 255, 0, 255, 0, 255],
                              [0, 0, 255, 255, 255, 255, 0, 255]])
    image_view = buffer.view(texture)
    while len(buffer.data) % 4:
        buffer.data.append(0)
    turned = [0.0, 1.0, 0.0, 0.0]
    document = {
        "asset": {"version": "2.0", "generator": "tests/fixtures/gltf/makeTexturedGlb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0, 1, 2, 3, 4]}],
        "nodes": [
            {"name": "factorQuad", "mesh": 1, "translation": [-3.2, 0.0, 0.0]},
            {"name": "cube", "mesh": 0, "translation": [-1.4, 0.0, 0.0]},
            {"name": "doubleQuad", "mesh": 2, "translation": [0.4, 0.0, 0.0], "rotation": turned},
            {"name": "doubleTexturedQuad", "mesh": 4, "translation": [2.0, 0.0, 0.0],
             "rotation": turned},
            {"name": "singleQuad", "mesh": 3, "translation": [3.6, 0.0, 0.0], "rotation": turned},
        ],
        "meshes": [
            cube_mesh,
            {"primitives": [{"attributes": tinted, "indices": quad_index, "material": 1}]},
            {"primitives": [{"attributes": quad_attributes, "indices": quad_index, "material": 2}]},
            {"primitives": [{"attributes": quad_attributes, "indices": quad_index, "material": 3}]},
            {"primitives": [{"attributes": textured_quad, "indices": quad_index, "material": 4}]},
        ],
        "materials": [
            {"name": "texel", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                                                      "metallicFactor": 0.0}},
            {"name": "factor", "pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.5, 1.0, 1.0],
                                                       "metallicFactor": 0.0}},
            {"name": "double", "doubleSided": True,
             "pbrMetallicRoughness": {"metallicFactor": 0.0}},
            {"name": "single", "pbrMetallicRoughness": {"metallicFactor": 0.0}},
            {"name": "doubleTexel", "doubleSided": True,
             "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0}},
        ],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"bufferView": image_view, "mimeType": "image/png"}],
        "accessors": buffer.accessors,
        "bufferViews": buffer.views,
        "buffers": [{"byteLength": len(buffer.data)}],
    }
    text = json.dumps(document, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary = bytes(buffer.data)
    chunks = (struct.pack("<II", len(text), 0x4E4F534A) + text
              + struct.pack("<II", len(binary), 0x004E4942) + binary)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + len(chunks)) + chunks
    with open(os.path.join(HERE, "texturedScene.glb"), "wb") as out:
        out.write(glb)
    print("texturedScene.glb", len(glb), "bytes")


if __name__ == "__main__":
    main()
