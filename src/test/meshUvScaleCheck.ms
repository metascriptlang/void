import {
	MeshData, MeshError, Rgba, Uv, addTexturedVertex, addTriangle, addGivenTangents,
	addSkinAttributes, scaleUvs,
} from "../void3d/meshData";
import { vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { Face } from "../gpu/state";
import { isEmpty } from "../void3d/bounds";

function uvTriangle(tangented: boolean, skinned: boolean, encoding: int32): MeshData {
	let data = MeshData.withUvs();
	const color: Rgba = { red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0 };
	for (let i = 0; i < 3; i++) {
		const point = vec3(i == 1 ? 1.0 : 0.0, i == 2 ? 1.0 : 0.0, 0.0);
		const uv: Uv = i == 1 ? { u: 1.0, v: -0.5 } : { u: 0.25, v: 0.75 };
		if (!addTexturedVertex(data, point, vec3(0.0, 0.0, 1.0), uv, color).ok) { unreachable; }
	}
	if (tangented && !addGivenTangents(data, [1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0,
		1.0, 0.0, 0.0, 1.0]).ok) { unreachable; }
	if (skinned && !addSkinAttributes(data, [0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0],
		[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]).ok) { unreachable; }
	if (encoding == 2) { data.wideIndices = []; }
	if (encoding > 0 && !addTriangle(data, 0, 1, 2).ok) { unreachable; }
	return move data;
}

test "UV scaling changes only UV0 across layouts storage and signed or zero factors" {
	const factors: Vec<Uv> = [{ u: 2.0, v: 3.0 }, { u: -2.0, v: 0.5 }, { u: 0.0, v: 0.0 }];
	for (const factor of factors) {
		for (const tangented of [false, true]) {
			for (const skinned of [false, true]) {
				for (const encoding of [0, 1, 2]) {
					let data = uvTriangle(tangented, skinned, encoding);
					let before: Vec<float32> = data.vertices;
					const bounds = data.bounds;
					const width = data.stride();
					assert scaleUvs(data, factor.u, factor.v).ok;
					assert data.hasUvs && data.hasTangents == tangented && data.hasSkin == skinned;
					assert data.stride() == width && data.bounds == bounds;
					assert data.indexCount() == (encoding == 0 ? 0 : 3);
					assert (data.wideIndices !== null) == (encoding == 2);
					for (let i = 0; i < data.indexCount(); i++) {
						assert data.indexAt(i) == i as uint32;
					}
					for (let vertex = 0; vertex < 3; vertex++) {
						for (let field = 0; field < width; field++) {
							const at = vertex * width + field;
							const expected: float32 = field == 6 ? before[at] * factor.u :
								(field == 7 ? before[at] * factor.v : before[at]);
							assert data.vertices[at] == expected;
						}
					}
				}
			}
		}
	}
}

test "UV scaling reaches CPU picked coordinates without moving geometry" {
	let data = uvTriangle(true, false, 1);
	assert scaleUvs(data, 2.0, 3.0).ok;
	const ray: Ray = { origin: vec3(0.25, 0.25, 1.0), direction: vec3(0, 0, -1) };
	const hit = data.rayIntersection(ray, Face.Back);
	assert hit.distance == 1.0 && hit.uv !== null;
	if (hit.uv !== null) { assert hit.uv.u == 0.875 && hit.uv.v == 1.3125; }
}

test "UV scaling retains empty data and refuses missing UV or partial vertex storage" {
	let empty = MeshData.withUvs();
	assert scaleUvs(empty, 2.0, 3.0).ok;
	assert empty.vertexCount() == 0 && empty.bounds.isEmpty();
	let missing = MeshData.empty();
	const absent = scaleUvs(missing, 2.0, 3.0);
	assert !absent.ok;
	if (!absent.ok) { assert absent.error == MeshError.UvMismatch; }
	let partial = uvTriangle(false, false, 0);
	partial.vertices.push(1.0);
	let before: Vec<float32> = partial.vertices;
	const malformed = scaleUvs(partial, 2.0, 3.0);
	assert !malformed.ok;
	if (!malformed.ok) { assert malformed.error == MeshError.VertexStorage; }
	for (let i = 0; i < before.length; i++) { assert partial.vertices[i] == before[i]; }
}

test "UV scaling rejects nonfinite factors without publishing changes" {
	const infinite: float32 = (1.0 / 0.0) as float32;
	const nan: float32 = infinite - infinite;
	for (const factor of [infinite, nan]) {
		for (const axis of [0, 1]) {
			let data = uvTriangle(true, true, 2);
			let before: Vec<float32> = data.vertices;
			const result = scaleUvs(data, axis == 0 ? factor : 1.0, axis == 1 ? factor : 1.0);
			assert !result.ok;
			if (!result.ok) { assert result.error == MeshError.UvScaleParameters; }
			for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
		}
	}
}

test "UV scaling preflights a late unrepresentable UV before any write" {
	let data = uvTriangle(true, true, 2);
	data.vertices[2 * data.stride() + 6] = 3.0e38;
	let before: Vec<float32> = data.vertices;
	const bounds = data.bounds;
	const result = scaleUvs(data, 2.0, 1.0);
	assert !result.ok;
	if (!result.ok) { assert result.error == MeshError.UvRange; }
	assert data.bounds == bounds;
	for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
}
