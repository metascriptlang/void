import {
	MeshData, MeshError, Rgba, addVertex, addTexturedVertex, addTriangle, addGivenTangents,
	addSkinAttributes, recomputeBounds, scaleUniform,
} from "../void3d/meshData";
import { vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { Face } from "../gpu/state";
import { isEmpty } from "../void3d/bounds";

function scaleTriangle(layout: int32, skinned: boolean, encoding: int32): MeshData {
	let data = layout == 0 ? MeshData.empty() : MeshData.withUvs();
	const color: Rgba = { red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0 };
	for (let i = 0; i < 3; i++) {
		const point = vec3(i == 1 ? 1.0 : 0.0, i == 2 ? 1.0 : 0.0, 0.0);
		const added = layout == 0 ? addVertex(data, point, vec3(0, 0, 1), color) :
			addTexturedVertex(data, point, vec3(0, 0, 1), { u: 0.25, v: 0.75 }, color);
		if (!added.ok) { unreachable; }
	}
	if (layout == 2 && !addGivenTangents(data, [1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0,
		1.0, 0.0, 0.0, 1.0]).ok) { unreachable; }
	if (skinned && !addSkinAttributes(data, [0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0],
		[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]).ok) { unreachable; }
	if (encoding == 2) { data.wideIndices = []; }
	if (encoding > 0 && !addTriangle(data, 0, 1, 2).ok) { unreachable; }
	return move data;
}

test "uniform scale preserves attributes and topology across signed or zero factors" {
	for (const factor of [2.0 as float32, -2.0 as float32, 0.0 as float32, 1.0 as float32]) {
		for (const layout of [0, 1, 2]) {
			for (const skinned of [false, true]) {
				for (const encoding of [0, 1, 2]) {
					let data = scaleTriangle(layout, skinned, encoding);
					let before: Vec<float32> = data.vertices;
					const width = data.stride();
					assert scaleUniform(data, factor).ok;
					assert data.vertexCount() == 3 && data.stride() == width;
					assert data.hasUvs == (layout > 0) && data.hasTangents == (layout == 2);
					assert data.hasSkin == skinned;
					assert data.indexCount() == (encoding == 0 ? 0 : 3);
					assert (data.wideIndices !== null) == (encoding == 2);
					for (let i = 0; i < data.indexCount(); i++) {
						assert data.indexAt(i) == i as uint32;
					}
					for (let vertex = 0; vertex < 3; vertex++) {
						for (let field = 0; field < width; field++) {
							const at = vertex * width + field;
							const expected: float32 = field < 3 ? before[at] * factor : before[at];
							assert data.vertices[at] == expected;
						}
					}
					const low: float32 = factor < 0.0 ? factor : 0.0;
					const high: float32 = factor > 0.0 ? factor : 0.0;
					assert data.bounds.min == vec3(low, low, 0.0);
					assert data.bounds.max == vec3(high, high, 0.0);
					assert !data.bounds.isEmpty();
				}
			}
		}
	}
}

test "uniform scaling reaches position picking and zero scale has no nondegenerate face" {
	for (const factor of [2.0 as float32, -2.0 as float32, 0.0 as float32]) {
		let data = scaleTriangle(0, false, 1);
		assert scaleUniform(data, factor).ok;
		const ray: Ray = {
			origin: vec3(0.25 * factor, 0.25 * factor, 1.0), direction: vec3(0, 0, -1),
		};
		const hit = data.rayIntersection(ray, Face.Back);
		assert hit.uv === null;
		if (factor == 0.0) { assert hit.distance < 0.0; }
		else { assert hit.distance == 1.0; }
	}
}

test "uniform scaling preserves empty data and rejects partial vertices" {
	let empty = MeshData.empty();
	assert scaleUniform(empty, -2.0).ok;
	assert empty.vertexCount() == 0 && empty.bounds.isEmpty();
	let partial = scaleTriangle(0, false, 0);
	partial.vertices.push(1.0);
	let before: Vec<float32> = partial.vertices;
	const result = scaleUniform(partial, 2.0);
	assert !result.ok;
	if (!result.ok) { assert result.error == MeshError.VertexStorage; }
	for (let i = 0; i < before.length; i++) { assert partial.vertices[i] == before[i]; }
}

test "uniform scaling rejects nonfinite factors before mutating positions" {
	const infinite: float32 = (1.0 / 0.0) as float32;
	const nan: float32 = infinite - infinite;
	for (const factor of [infinite, -infinite, nan]) {
		let data = scaleTriangle(2, true, 2);
		let before: Vec<float32> = data.vertices;
		const bounds = data.bounds;
		const result = scaleUniform(data, factor);
		assert !result.ok;
		if (!result.ok) { assert result.error == MeshError.ScaleParameters; }
		assert data.bounds == bounds;
		for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
	}
}

test "uniform scaling preflights late unrepresentable positions atomically" {
	let data = scaleTriangle(2, true, 2);
	data.vertices[2 * data.stride()] = 3.0e38;
	recomputeBounds(data);
	let before: Vec<float32> = data.vertices;
	const bounds = data.bounds;
	const result = scaleUniform(data, 2.0);
	assert !result.ok;
	if (!result.ok) { assert result.error == MeshError.PositionRange; }
	assert data.bounds == bounds;
	for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
}
