"""Original glTF 2 skin fixture and GPU-free numeric oracle; Python standard library only.

Default writes adjacent explicit-IBM GLB and expectations for both variants.
--omit-ibm --output out/tmp/skinFixture/omitted.glb writes identity-IBM variant.
--probe validates container/accessor bytes and discriminates named numeric controls.
Oracle uses column-vector glTF TRS and pointwise quaternion rotation, never Void code.
"""

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import struct

HERE = Path(__file__).resolve().parent
JOINT_NODES = [3, 2]
POSITIONS = [(-0.75, 0.25, 0.125), (0.25, 0.375, 0.125),
             (-0.5, 1.375, 0.375), (0.625, -0.25, -0.375),
             (1.875, 0.0, -0.125), (1.0, 0.875, -0.25)]
JOINTS = [(0, 0, 0, 0), (0, 1, 0, 0), (1, 0, 0, 0),
          (1, 0, 0, 0), (0, 1, 0, 0), (1, 0, 0, 0)]
WEIGHTS = [(1, 0, 0, 0), (0.75, 0.25, 0, 0), (0.625, 0.375, 0, 0),
           (1, 0, 0, 0), (0.25, 0.75, 0, 0), (0.5, 0.5, 0, 0)]
PRIMITIVE_MATERIALS = [1, 0]
CLONES = [("cloneA", 0.375, [-2.0, 0.0, 0.0]),
          ("cloneB", 1.625, [2.0, 0.0, 0.0])]
RUNTIME_SCALES = {"base": [1, 1, 1], "nonuniform": [1.4, 0.65, 1.1],
                  "mirror": [-1.4, 0.65, 1.1], "rankTwo": [1.4, 0.65, 0]}
TOLERANCE = 0.0001


def add(a, b):
    return [x + y for x, y in zip(a, b)]


def sub(a, b):
    return [x - y for x, y in zip(a, b)]


def scaled(a, factor):
    return [x * factor for x in a]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0]]


def unit(a):
    length = math.sqrt(dot(a, a))
    if length == 0 or not math.isfinite(length):
        raise ValueError("zero or nonfinite direction")
    return scaled(a, 1 / length)


def quat(axis, degrees):
    angle = math.radians(degrees) / 2
    return scaled(unit(axis), math.sin(angle)) + [math.cos(angle)]


def rotate(p, q):
    twice_cross = scaled(cross(q[:3], p), 2)
    return add(add(p, scaled(twice_cross, q[3])), cross(q[:3], twice_cross))


def point_trs(p, trs):
    return add(rotate([p[i] * trs["scale"][i] for i in range(3)], trs["rotation"]),
               trs["translation"])


def inverse_trs(p, trs):
    turned = rotate(sub(p, trs["translation"]), scaled(trs["rotation"][:3], -1)
                    + [trs["rotation"][3]])
    return [turned[i] / trs["scale"][i] for i in range(3)]


def trs(translation, rotation, scale=(1, 1, 1)):
    return {"translation": list(translation), "rotation": list(rotation), "scale": list(scale)}


def float32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def rounded(value):
    if isinstance(value, dict):
        return {k: rounded(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [rounded(v) for v in value]
    return float32(value)


def rest_nodes():
    return [dict(trs([0.75, 1.25, -0.5], quat([0, 1, 0], 30)),
                 name="duplicate", children=[1, 2]),
            dict(trs([7, -3, 4], quat([0, 1, 0], 70), [1.2, 0.8, 1.1]),
                 name="duplicate", mesh=0, skin=0),
            dict(trs([0.5, 0.25, 0.75], quat([0, 0, 1], -25)),
                 name="joint", children=[3]),
            dict(trs([0.75, 0.5, 0.25], quat([1, 0, 0], 40)), name="joint")]


def tracks():
    return [{"node": 2, "path": "translation", "times": [0, 0.5, 2],
             "values": [[0.5, 0.25, 0.75], [1.125, 0.5, 0.375], [0.25, 0.875, -0.25]]},
            {"node": 3, "path": "rotation", "times": [0, 1.5, 2.5],
             "values": [quat([1, 0, 0], 40), quat([1, 2, 1], 115), quat([0, 1, 1], -55)]},
            {"node": 2, "path": "scale", "times": [0.25, 1.25, 2.75],
             "values": [[1, 1, 1], [1.25, 0.75, 1.125], [0.875, 1.375, 0.75]]}]


def sample(track, time):
    times, values = track["times"], track["values"]
    if time <= times[0]:
        return values[0][:]
    if time >= times[-1]:
        return values[-1][:]
    right = next(i for i, t in enumerate(times) if t >= time)
    left = right - 1
    alpha = (time - times[left]) / (times[right] - times[left])
    a, b = values[left][:], values[right][:]
    if track["path"] != "rotation":
        return add(scaled(a, 1 - alpha), scaled(b, alpha))
    a, b = unit(a), unit(b)
    cosine = dot(a, b)
    if cosine < 0:
        b, cosine = scaled(b, -1), -cosine
    angle = math.acos(min(1, cosine))
    if angle < 1e-8:
        return unit(add(scaled(a, 1 - alpha), scaled(b, alpha)))
    return unit(add(scaled(a, math.sin((1 - alpha) * angle) / math.sin(angle)),
                    scaled(b, math.sin(alpha * angle) / math.sin(angle))))


def posed_nodes(nodes, time, channels):
    result = copy.deepcopy(nodes)
    for track in channels:
        result[track["node"]][track["path"]] = sample(track, time)
    return result


def joint_world(p, node, nodes):
    if node == 3:
        p = point_trs(p, nodes[3])
    return point_trs(point_trs(p, nodes[2]), nodes[0])


def affine_columns(transform):
    origin = transform([0, 0, 0])
    axes = [sub(transform([int(i == j) for i in range(3)]), origin) for j in range(3)]
    return [v for axis in axes for v in axis + [0]] + origin + [1]


def ibm_columns(node, nodes):
    def inverse(p):
        p = inverse_trs(inverse_trs(p, nodes[0]), nodes[2])
        return inverse_trs(p, nodes[3]) if node == 3 else p
    return rounded(affine_columns(inverse))


def affine_point(p, columns):
    return [sum(p[j] * columns[4 * j + i] for j in range(3)) + columns[12 + i]
            for i in range(3)]


class Buffer:
    def __init__(self):
        self.data, self.views, self.accessors = bytearray(), [], []

    def accessor(self, rows, kind, component=5126, target=None, extrema=False):
        size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
        if not rows or any(len(row) != size for row in rows):
            raise ValueError("accessor row shape")
        values = [v for row in rows for v in row]
        if not all(math.isfinite(v) for v in values):
            raise ValueError("nonfinite accessor")
        code = {5126: "f", 5123: "H", 5121: "B"}[component]
        payload = struct.pack("<" + code * len(values), *values)
        self.data += b"\0" * (-len(self.data) % 4)
        view = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(payload)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        self.data += payload
        accessor = {"bufferView": len(self.views) - 1, "componentType": component,
                    "count": len(rows), "type": kind}
        if extrema:
            actual = struct.unpack("<" + code * len(values), payload)
            accessor["min"] = [min(actual[i::size]) for i in range(size)]
            accessor["max"] = [max(actual[i::size]) for i in range(size)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1


def fixture(omit_ibm=False):
    buffer = Buffer()
    nodes, channels = rest_nodes(), tracks()
    ibms = [ibm_columns(node, nodes) for node in JOINT_NODES]
    primitives = []
    for primitive in range(2):
        start = primitive * 3
        points = POSITIONS[start:start + 3]
        normal = unit(cross(sub(points[1], points[0]), sub(points[2], points[0])))
        attributes = {"POSITION": buffer.accessor(points, "VEC3", target=34962, extrema=True),
                      "NORMAL": buffer.accessor([normal] * 3, "VEC3", target=34962),
                      "TEXCOORD_0": buffer.accessor([(0, 1), (1, 1), (0, 0)], "VEC2", target=34962),
                      "JOINTS_0": buffer.accessor(JOINTS[start:start + 3], "VEC4", 5121, 34962),
                      "WEIGHTS_0": buffer.accessor(WEIGHTS[start:start + 3], "VEC4", target=34962)}
        primitives.append({"attributes": attributes,
                           "indices": buffer.accessor([(0,), (1,), (2,)], "SCALAR", 5123, 34963),
                           "material": PRIMITIVE_MATERIALS[primitive], "mode": 4})
    skin = {"joints": JOINT_NODES[:], "skeleton": 0}
    if not omit_ibm:
        skin["inverseBindMatrices"] = buffer.accessor(ibms, "MAT4")
    samplers, targets = [], []
    for track in channels:
        samplers.append({"input": buffer.accessor([(t,) for t in track["times"]], "SCALAR", extrema=True),
                         "output": buffer.accessor(track["values"], "VEC4" if track["path"] == "rotation" else "VEC3"),
                         "interpolation": "LINEAR"})
        targets.append({"sampler": len(samplers) - 1,
                        "target": {"node": track["node"], "path": track["path"]}})
    document = {"asset": {"version": "2.0", "generator": "generateSkinnedAsymmetric.py (original synthetic)"},
                "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
                "meshes": [{"name": "asymmetric", "primitives": primitives}], "skins": [skin],
                "materials": [{"name": "sameMaterialName", "doubleSided": True,
                               "pbrMetallicRoughness": {"baseColorFactor": [0.125, 0.75, 0.25, 1], "metallicFactor": 0}},
                              {"name": "sameMaterialName", "doubleSided": True,
                               "pbrMetallicRoughness": {"baseColorFactor": [0.875, 0.125, 0.0625, 1], "metallicFactor": 0}}],
                "animations": [{"name": "independentTRS", "samplers": samplers, "channels": targets}],
                "buffers": [{"byteLength": len(buffer.data)}], "bufferViews": buffer.views,
                "accessors": buffer.accessors}
    text = json.dumps(document, separators=(",", ":"), allow_nan=False).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary = bytes(buffer.data) + b"\0" * (-len(buffer.data) % 4)
    chunks = struct.pack("<II", len(text), 0x4E4F534A) + text
    chunks += struct.pack("<II", len(binary), 0x004E4942) + binary
    return struct.pack("<III", 0x46546C67, 2, len(chunks) + 12) + chunks


def decode(glb):
    magic, version, total = struct.unpack_from("<III", glb)
    assert (magic, version, total) == (0x46546C67, 2, len(glb)), "GLB header"
    cursor, chunks = 12, []
    while cursor < total:
        length, kind = struct.unpack_from("<II", glb, cursor)
        assert length % 4 == 0 and cursor + 8 + length <= total, "chunk bounds/alignment"
        chunks.append((kind, glb[cursor + 8:cursor + 8 + length]))
        cursor += 8 + length
    assert cursor == total and [c[0] for c in chunks] == [0x4E4F534A, 0x004E4942], "chunk order"
    document, binary = json.loads(chunks[0][1]), chunks[1][1]
    byte_length = document["buffers"][0]["byteLength"]
    assert 0 <= len(binary) - byte_length <= 3 and not any(binary[byte_length:]), "BIN padding"
    rows = []
    for accessor in document["accessors"]:
        view = document["bufferViews"][accessor["bufferView"]]
        size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[accessor["type"]]
        code, width = {5126: ("f", 4), 5123: ("H", 2), 5121: ("B", 1)}[accessor["componentType"]]
        offset = view["byteOffset"] + accessor.get("byteOffset", 0)
        length = accessor["count"] * size * width
        assert view["buffer"] == 0 and offset % width == 0 and view["byteOffset"] % 4 == 0, "accessor alignment"
        assert length == view["byteLength"] and offset + length <= byte_length, "accessor bounds"
        flat = struct.unpack_from("<" + code * (accessor["count"] * size), binary, offset)
        assert all(math.isfinite(v) for v in flat), "finite accessor"
        if "min" in accessor:
            assert accessor["min"] == [min(flat[i::size]) for i in range(size)], "accessor min"
            assert accessor["max"] == [max(flat[i::size]) for i in range(size)], "accessor max"
        rows.append([list(flat[i:i + size]) for i in range(0, len(flat), size)])
    return document, rows


def oracle_inputs(glb):
    document, rows = decode(glb)
    skin = document["skins"][0]
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    ibms = rows[skin["inverseBindMatrices"]] if "inverseBindMatrices" in skin else [identity[:], identity[:]]
    channels = []
    for channel in document["animations"][0]["channels"]:
        sampler = document["animations"][0]["samplers"][channel["sampler"]]
        channels.append(dict(channel["target"], times=[r[0] for r in rows[sampler["input"]]],
                             values=rows[sampler["output"]]))
    positions, joints, weights, normals = [], [], [], []
    for primitive in document["meshes"][0]["primitives"]:
        attrs = primitive["attributes"]
        positions.extend(rows[attrs["POSITION"]])
        joints.extend(rows[attrs["JOINTS_0"]])
        weights.extend(rows[attrs["WEIGHTS_0"]])
        normals.extend(rows[attrs["NORMAL"]])
    return document, channels, ibms, positions, joints, weights, normals


def deform(inputs, time, host, control=None):
    document, channels, ibms, positions, joints, weights, _ = inputs
    nodes = posed_nodes(document["nodes"], time, channels)
    result = []
    for p, slots, amounts in zip(positions, joints, weights):
        total = [0, 0, 0]
        for slot, amount in zip(slots, amounts):
            if amount == 0:
                continue
            if control == "canonicalGpuRemap":
                slot = 1 - slot
            node = JOINT_NODES[slot]
            if control == "ibmOrder":
                placed = point_trs(affine_point(joint_world(p, node, nodes), ibms[slot]), host)
            else:
                placed = point_trs(joint_world(affine_point(p, ibms[slot]), node, nodes), host)
            total = add(total, scaled(placed, amount))
        if control == "omittedConsumer":
            total = point_trs(p, host)
        if control == "doubleModel":
            total = point_trs(total, nodes[1])
        result.append(total)
    return result


def surface_normals(inputs, time, host):
    source_normals = inputs[6]
    origin_inputs = list(inputs)
    origin_inputs[3] = [[0, 0, 0] for _ in POSITIONS]
    origins = deform(origin_inputs, time, host)
    axes = []
    for axis in range(3):
        axis_inputs = list(inputs)
        axis_inputs[3] = [[int(i == axis) for i in range(3)] for _ in POSITIONS]
        axes.append([sub(p, origin) for p, origin in zip(deform(axis_inputs, time, host), origins)])
    result = []
    for vertex, normal in enumerate(source_normals):
        x, y, z = [axis[vertex] for axis in axes]
        determinant = dot(x, cross(y, z))
        cofactors = [cross(y, z), cross(z, x), cross(x, y)]
        cofactor_normal = [sum(cofactors[j][i] * normal[j] for j in range(3)) for i in range(3)]
        signed = scaled(cofactor_normal, -1 if determinant < 0 else 1)
        result.append({"blendedDeterminant": determinant, "cofactorNormal": cofactor_normal,
                       "signedNormalDirection": unit(signed) if dot(signed, signed) > 1e-20 else None})
    return result


def bounds(points):
    return {"min": [min(p[i] for p in points) for i in range(3)],
            "max": [max(p[i] for p in points) for i in range(3)]}


def ray_hit(origin, direction, triangle):
    a, b, c = triangle
    edge1, edge2 = sub(b, a), sub(c, a)
    h = cross(direction, edge2)
    determinant = dot(edge1, h)
    if abs(determinant) < 1e-12:
        return None
    delta = sub(origin, a)
    u = dot(delta, h) / determinant
    q = cross(delta, edge1)
    v = dot(direction, q) / determinant
    distance = dot(edge2, q) / determinant
    return distance if u >= 0 and v >= 0 and u + v <= 1 and distance >= 0 else None


def landmarks(points):
    triangles = []
    for primitive in range(2):
        triangle = points[primitive * 3:primitive * 3 + 3]
        centroid = scaled(add(add(triangle[0], triangle[1]), triangle[2]), 1 / 3)
        area = cross(sub(triangle[1], triangle[0]), sub(triangle[2], triangle[0]))
        normal = unit(area)
        origin, direction = add(centroid, scaled(normal, 3.25)), scaled(normal, -1)
        hits = [ray_hit(origin, direction, points[i:i + 3]) for i in (0, 3)]
        assert hits[primitive] is not None and abs(hits[primitive] - 3.25) < 1e-9, "ray centroid"
        assert all(h is None or h >= 3.25 - 1e-9 for h in hits), "nearest ray landmark"
        shadows = [[p[0] - (p[1] + 2) / 2, -2, p[2] - (p[1] + 2) / 4] for p in triangle]
        triangles.append({"sourceNode": 1, "sourceMesh": 0, "sourcePrimitive": primitive,
                          "sourceMaterial": PRIMITIVE_MATERIALS[primitive],
                          "centroid": centroid, "geometricNormal": normal, "twiceArea": math.sqrt(dot(area, area)),
                          "ray": {"origin": origin, "direction": direction, "distance": 3.25,
                                  "point": centroid, "barycentric": [1 / 3] * 3, "uv": [1 / 3, 2 / 3]},
                          "shadowVertices": shadows, "shadowCentroid": scaled(add(add(shadows[0], shadows[1]), shadows[2]), 1 / 3),
                          "bounds": bounds(triangle)})
    return {"positions": points, "bounds": bounds(points), "triangles": triangles}


def maximum_delta(a, b):
    return max(abs(x - y) for pa, pb in zip(a, b) for x, y in zip(pa, pb))


def expectations():
    variants = []
    for omit in (False, True):
        glb = fixture(omit)
        inputs = oracle_inputs(glb)
        cases, controls = [], []
        for scale_name, scale in RUNTIME_SCALES.items():
            for name, time, translation in CLONES:
                host = trs(translation, quat([0, 0, 1], 15), scale)
                points = deform(inputs, time, host)
                cases.append(dict(landmarks(points), id=scale_name + "/" + name,
                                  time=time, hostTRS=host,
                                  vertexNormals=surface_normals(inputs, time, host),
                                  sampledChannels=[dict(node=t["node"], path=t["path"], value=sample(t, time)) for t in inputs[1]]))
        for name in ("ibmOrder", "canonicalGpuRemap", "omittedConsumer", "doubleModel", "cloneSharedPose"):
            case = cases[1]
            wrong_time = CLONES[0][1] if name == "cloneSharedPose" else case["time"]
            wrong = deform(inputs, wrong_time, case["hostTRS"], None if name == "cloneSharedPose" else name)
            delta = maximum_delta(case["positions"], wrong)
            if omit and name == "ibmOrder":
                continue
            assert delta > 0.05, (name, delta)
            controls.append({"id": name, "case": case["id"], "assertion": "positions[*][*] absolute error <= 0.0001",
                             "wrongPositions": wrong, "maximumAbsoluteError": delta})
        variants.append({"id": "omittedIBM" if omit else "explicitIBM", "glbBytes": len(glb),
                         "sha256": hashlib.sha256(glb).hexdigest(), "inverseBindMatricesColumnMajor": inputs[2],
                         "cases": cases, "controls": controls})
    return {"formatVersion": 1, "acceptance": "UNVERIFIED; importer/render/pick/shadow NOTRUN",
            "oracle": "Python float64, glTF column-vector pointwise TRS, float32 accessor bytes; no Void math imports",
            "absoluteTolerance": TOLERANCE,
            "explicitBindPosePositionsHostIdentity": POSITIONS,
            "exportedScales": "positive; runtime host variants never modify importer acceptance",
            "runtimeHostPlacement": "attach model-root host above source node 0, not ignored skinned mesh node 1",
            "rankTwoContract": "finite world positions, nonzero triangle areas, exact posed bounds; zero determinant cofactor direction recorded without inferring consumer singular policy",
            "normalContract": "cofactor of each blended linear transform; multiply by determinant sign when negative, normalize when nonzero; geometricNormal separately follows triangle winding",
            "shadowContract": {"towardLight": [1, 2, 0.5], "receiverY": -2,
                               "projection": "p - towardLight * ((p.y - receiverY) / towardLight.y)"},
            "identity": {"sceneRoots": [0], "nonJointAncestor": 0, "skinnedSourceNode": 1,
                         "jointSourceNodesInSkinOrder": JOINT_NODES, "jointParent": {"3": 2, "2": 0},
                         "duplicateNodeNames": [[0, 1], [2, 3]], "primitiveMaterialIndices": PRIMITIVE_MATERIALS,
                         "expectedExpandedDrawables": 2, "originalSourceNodeCount": 4,
                         "materialFactorsLinear": [[0.125, 0.75, 0.25, 1], [0.875, 0.125, 0.0625, 1]],
                         "gpuSlotToCanonicalControl": [1, 0]},
            "controlRecipes": {"ibmOrder": "column-vector IBM * jointWorld instead of jointWorld * IBM (Void row-vector reverse)",
                               "canonicalGpuRemap": "use [1,0] remapped GPU joint slots as canonical indices without corresponding palette remap",
                               "omittedConsumer": "submit undeformed source positions instead of current skin geometry",
                               "doubleModel": "apply source node 1 direct mesh TRS after world-space skin deformation",
                               "cloneSharedPose": "sample clone B at clone A time 0.375 instead of 1.625; retain B host"},
            "variants": variants}


def probe(expected, glb):
    document, rows = decode(glb)
    assert document["skins"][0]["joints"] == [3, 2], "shuffled joint table"
    assert document["nodes"][2]["name"] == document["nodes"][3]["name"], "duplicate joints"
    assert [p["material"] for p in document["meshes"][0]["primitives"]] == [1, 0], "material identity"
    for primitive in document["meshes"][0]["primitives"]:
        attrs = primitive["attributes"]
        assert rows[primitive["indices"]] == [[0], [1], [2]], "triangle bytes"
        for slots, weights in zip(rows[attrs["JOINTS_0"]], rows[attrs["WEIGHTS_0"]]):
            assert sum(weights) == 1 and all(0 <= j < 2 for j in slots), "influence bytes"
            active = [j for j, w in zip(slots, weights) if w > 0]
            assert len(set(active)) == len(active), "duplicate positive joint"
    for variant in expected["variants"]:
        candidate = fixture(variant["id"] == "omittedIBM")
        inputs = oracle_inputs(candidate)
        assert hashlib.sha256(candidate).hexdigest() == variant["sha256"], "variant bytes"
        if variant["id"] == "explicitIBM":
            rest = deform(inputs, 0, trs([0, 0, 0], [0, 0, 0, 1]))
            assert maximum_delta(rest, POSITIONS) < 1e-6, "bind pose independent landmark"
            translated_inputs = list(inputs)
            translated_inputs[3] = [[0, 0, 0] for _ in inputs[3]]
            translated_host = trs([2, 0, 0], [0, 0, 0, 1])
            translated = deform(translated_inputs, 0, translated_host, "ibmOrder")
            host_only = [[2, 0, 0] for _ in inputs[3]]
            assert maximum_delta(translated, host_only) < 1e-6, "IBM control preserves host"
        for case in variant["cases"]:
            assert maximum_delta(deform(inputs, case["time"], case["hostTRS"]), case["positions"]) < 1e-12, "expected pose"
            assert all(math.isfinite(v) for p in case["positions"] for v in p), "finite geometry"
        for control in variant["controls"]:
            assert control["maximumAbsoluteError"] > TOLERANCE, "control must miss numeric assertion"
        print(variant["id"], variant["glbBytes"], "bytes;", len(variant["cases"]), "cases;",
              len(variant["controls"]), "discriminating controls")
        for control in variant["controls"]:
            print(" ", control["id"], "maxError=%.9f" % control["maximumAbsoluteError"])
    print("GPU-free container/accessor/numeric probes only; importer/GPU acceptance NOTRUN")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--omit-ibm", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected", type=Path)
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    if args.omit_ibm and args.output is None:
        parser.error("--omit-ibm requires --output; do not overwrite explicit fixture")
    output = args.output or HERE / "skinnedAsymmetric.glb"
    expected_path = args.expected or (output.parent / "skinnedAsymmetricExpected.json")
    glb, expected = fixture(args.omit_ibm), expectations()
    if args.probe:
        probe(expected, glb)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(glb)
    expected_path.parent.mkdir(parents=True, exist_ok=True)
    expected_path.write_bytes((json.dumps(expected, indent=2, allow_nan=False) + "\n")
                              .replace("\n", "\r\n").encode("utf-8"))
    print(output.name, len(glb), "bytes;", expected_path.name)


if __name__ == "__main__":
    main()
