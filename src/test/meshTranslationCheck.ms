import {
	MeshData, MeshError, Rgba, addVertex, addTexturedVertex, addTriangle, addGivenTangents,
	addSkinAttributes, recomputeBounds, translate,
} from "../void3d/meshData";
import { vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { isEmpty } from "../void3d/bounds";
import { Face } from "../gpu/state";

function triangle(layout: int32, skinned: boolean, encoding: int32): MeshData {
	let data = layout == 0 ? MeshData.empty() : MeshData.withUvs();
	const normal = vec3(0.0, 0.0, 1.0);
	const color: Rgba = { red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0 };
	for (let i = 0; i < 3; i++) {
		const point = vec3(i == 1 ? 1.0 : 0.0, i == 2 ? 1.0 : 0.0, 0.0);
		const added = layout == 0 ? addVertex(data, point, normal, color) :
			addTexturedVertex(data, point, normal, { u: 0.25, v: 0.75 }, color);
		if (!added.ok) { unreachable; }
	}
	if (layout == 2) {
		if (!addGivenTangents(data, [1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0]).ok) { unreachable; }
	}
	if (skinned) {
		if (!addSkinAttributes(data, [0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0],
			[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]).ok) {
			unreachable;
		}
	}
	if (encoding == 2) { data.wideIndices = []; }
	if (encoding > 0 && !addTriangle(data, 0, 1, 2).ok) { unreachable; }
	return move data;
}

test "mesh translation bakes positions and bounds without changing attributes or topology" {
	for (const layout of [0, 1, 2]) {
		for (const skinned of [false, true]) {
			for (const encoding of [0, 1, 2]) {
				let data = triangle(layout, skinned, encoding);
				let before: Vec<float32> = data.vertices;
				const width = data.stride();
				assert translate(data, vec3(3.0, -2.0, 5.0)).ok;
				assert data.vertexCount() == 3 && data.stride() == width;
				assert data.hasUvs == (layout > 0) && data.hasTangents == (layout == 2);
				assert data.hasSkin == skinned;
				assert (data.wideIndices !== null) == (encoding == 2);
				assert data.indexCount() == (encoding == 0 ? 0 : 3);
				for (let i = 0; i < data.indexCount(); i++) {
					assert data.indexAt(i) == i as uint32;
				}
				for (let vertex = 0; vertex < 3; vertex++) {
					const at = vertex * width;
					assert data.vertices[at] == before[at] + 3.0;
					assert data.vertices[at + 1] == before[at + 1] - 2.0;
					assert data.vertices[at + 2] == before[at + 2] + 5.0;
					for (let field = 3; field < width; field++) {
						assert data.vertices[at + field] == before[at + field];
					}
				}
				assert data.bounds.min == vec3(3.0, -2.0, 5.0);
				assert data.bounds.max == vec3(4.0, -1.0, 5.0);
				const ray: Ray = { origin: vec3(3.25, -1.75, 6.0), direction: vec3(0, 0, -1) };
				assert data.rayIntersection(ray, Face.Back).distance == 1.0;
				assert translate(data, vec3(-3.0, 2.0, -5.0)).ok;
				for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
			}
		}
	}
}

test "mesh translation keeps empty data empty and mutates only its owned value" {
	let empty = MeshData.empty();
	assert translate(empty, vec3(1.0, 2.0, 3.0)).ok;
	assert empty.vertexCount() == 0 && empty.bounds.isEmpty();
	let original = triangle(2, true, 2);
	let copy = original;
	assert translate(copy, vec3(3.0, -2.0, 5.0)).ok;
	assert original.bounds.min == vec3(0.0, 0.0, 0.0);
	assert original.bounds.max == vec3(1.0, 1.0, 0.0);
	assert original.vertices[0] == 0.0 && copy.vertices[0] == 3.0;
}

test "mesh translation rejects nonfinite offsets before publishing any change" {
	const infinite: float32 = (1.0 / 0.0) as float32;
	const nan: float32 = infinite - infinite;
	for (const value of [infinite, -infinite, nan]) {
		let data = triangle(1, false, 1);
		let before: Vec<float32> = data.vertices;
		const bounds = data.bounds;
		const result = translate(data, vec3(1.0, value, 0.0));
		assert !result.ok;
		if (!result.ok) { assert result.error == MeshError.TranslationOffset; }
		assert data.bounds == bounds;
		for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
	}
}

test "mesh translation preflights a late unrepresentable position atomically" {
	let data = triangle(2, true, 2);
	data.vertices[2 * data.stride()] = 3.0e38;
	recomputeBounds(data);
	let before: Vec<float32> = data.vertices;
	const bounds = data.bounds;
	const result = translate(data, vec3(1.0e38, 1.0, 1.0));
	assert !result.ok;
	if (!result.ok) { assert result.error == MeshError.PositionRange; }
	assert data.bounds == bounds;
	for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
}

test "mesh translation rejects a partial interleaved vertex without changing storage" {
	let data = triangle(0, false, 0);
	data.vertices.push(1.0);
	let before: Vec<float32> = data.vertices;
	const result = translate(data, vec3(1.0, 2.0, 3.0));
	assert !result.ok;
	if (!result.ok) { assert result.error == MeshError.VertexStorage; }
	for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
}
