import argparse
import json
import pathlib
import struct
import zlib


def png_half_alpha():
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff\x80"))
            + chunk(b"IEND", b""))


def generate():
    binary = bytearray()
    views, accessors, meshes, nodes, materials = [], [], [], [], []

    def view(data, stride=None):
        binary.extend(b"\0" * (-len(binary) % 4))
        entry = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
        if stride is not None:
            entry["byteStride"] = stride
        views.append(entry)
        binary.extend(data)
        return len(views) - 1

    def accessor(data, component, shape, count, stride=None, normalized=False):
        entry = {"bufferView": view(data, stride), "componentType": component,
                 "type": shape, "count": count}
        if normalized:
            entry["normalized"] = True
        accessors.append(entry)
        return len(accessors) - 1

    cases = [
        ("opaqueIgnore", "OPAQUE", 0.5, None, False, False, False),
        ("sparseOrdinal", "OPAQUE", 1.0, None, True, False, False),
        ("blendU8Factor", "BLEND", 0.5, None, False, False, False),
        ("blendFloatControl", "BLEND", 1.0, None, False, True, False),
        ("maskOnceKeep", "MASK", 0.5, 0.3, False, False, False),
        ("maskOnceCut", "MASK", 0.5, 0.5, False, False, False),
        ("maskTextureCut", "MASK", 0.5, 0.3, False, False, True),
        ("maskTextureKeep", "MASK", 0.5, 0.1, False, False, True),
        ("blendEndpoints", "BLEND", 1.0, None, False, False, False),
    ]
    for ordinal, (name, mode, factor, cutoff, sparse, floating, textured) in enumerate(cases):
        positions, colors, uvs = [], [], []
        for side in range(2):
            left, right = (-0.9, -0.1) if side == 0 else (0.1, 0.9)
            positions.extend([(left, -0.6, 0), (right, -0.6, 0),
                              (right, 0.6, 0), (left, 0.6, 0)])
            uvs.extend([(0, 0), (1, 0), (1, 1), (0, 1)])
            rgb = (255, 0, 0) if side == 0 else (0, 255, 0)
            alpha = 255
            if mode == "MASK":
                alpha = 191 if side == 0 else 0
            elif name == "opaqueIgnore":
                alpha = 0
            elif name == "blendEndpoints":
                alpha = 0 if side == 0 else 255
            if floating:
                colors.extend([tuple(c / 255 for c in rgb) + (0.5,)] * 4)
            else:
                colors.extend([rgb + (alpha,)] * 4)
        position = accessor(b"".join(struct.pack("<3f", *p) for p in positions),
                            5126, "VEC3", 8)
        normal = accessor(struct.pack("<3f", 0, 0, 1) * 8, 5126, "VEC3", 8)
        indices = accessor(struct.pack("<12H", 0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7),
                           5123, "SCALAR", 12)
        if floating:
            color = accessor(b"".join(struct.pack("<4f", *c) for c in colors),
                             5126, "VEC4", 8)
        else:
            dense = [(0, 0, 255, 255)] * 8 if sparse else colors
            color = accessor(b"".join(bytes(c) + b"\x13\x57\x9b\xdf" for c in dense),
                             5121, "VEC4", 8, 8, True)
        if sparse:
            accessors[color]["sparse"] = {
                "count": 8, "indices": {"bufferView": view(bytes(range(8))),
                                        "componentType": 5121},
                "values": {"bufferView": view(b"".join(bytes(c) for c in colors))},
            }
        attributes = {"POSITION": position, "NORMAL": normal, "COLOR_0": color}
        pbr = {"baseColorFactor": [1, 1, 1, factor]}
        if textured:
            attributes["TEXCOORD_0"] = accessor(
                b"".join(struct.pack("<2f", *uv) for uv in uvs), 5126, "VEC2", 8)
            pbr["baseColorTexture"] = {"index": 0}
        material = {"name": name, "pbrMetallicRoughness": pbr,
                    "alphaMode": mode, "doubleSided": True}
        if cutoff is not None:
            material["alphaCutoff"] = cutoff
        materials.append(material)
        meshes.append({"name": name, "primitives": [{"attributes": attributes,
                       "indices": indices, "material": ordinal}]})
        nodes.append({"name": name, "mesh": ordinal,
                      "translation": [(ordinal % 3 - 1) * 3, 2 - (ordinal // 3) * 2, 0]})
    ground_position = accessor(struct.pack("<12f", -4.7, -3.5, -1, 4.7, -3.5, -1,
                                          4.7, 3.5, -1, -4.7, 3.5, -1),
                               5126, "VEC3", 4)
    ground_normal = accessor(struct.pack("<3f", 0, 0, 1) * 4, 5126, "VEC3", 4)
    ground_color = accessor(bytes([255, 255, 255, 255]) * 4, 5121, "VEC4", 4,
                            stride=4, normalized=True)
    assert views[accessors[ground_color]["bufferView"]].get("byteStride") == 4
    ground_indices = accessor(struct.pack("<6H", 0, 1, 2, 0, 2, 3), 5123, "SCALAR", 6)
    materials.append({"name": "ground", "alphaMode": "OPAQUE",
                      "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]}})
    meshes.append({"name": "ground", "primitives": [{"attributes": {
        "POSITION": ground_position, "NORMAL": ground_normal, "COLOR_0": ground_color},
        "indices": ground_indices, "material": 9}]})
    nodes.append({"name": "ground", "mesh": 9})
    image_view = view(png_half_alpha())
    document = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binary)}],
                "bufferViews": views, "accessors": accessors, "materials": materials,
                "meshes": meshes, "nodes": nodes, "scenes": [{"nodes": list(range(10))}],
                "scene": 0, "images": [{"bufferView": image_view, "mimeType": "image/png"}],
                "textures": [{"source": 0, "sampler": 0}],
                "samplers": [{"magFilter": 9728, "minFilter": 9728,
                              "wrapS": 33071, "wrapT": 33071}]}
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    payload = (struct.pack("<II", len(text), 0x4e4f534a) + text
               + struct.pack("<II", len(binary), 0x004e4942) + binary)
    return struct.pack("<III", 0x46546c67, 2, 12 + len(payload)) + payload, document


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="out/tmp/gltfColourRenderFixture/colourAsymmetric.glb")
    args = parser.parse_args()
    destination = pathlib.Path(args.output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    data, document = generate()
    destination.write_bytes(data)
    print(f"{destination}: {len(data)} bytes, {len(document['meshes'])} imported panels")


if __name__ == "__main__":
    main()
