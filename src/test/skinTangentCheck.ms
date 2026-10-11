import {
	MeshData,
	MeshError,
	addTexturedVertex,
	addTriangle,
	addTangentsWithSources,
	addSkinAttributes,
} from "../void3d/meshData";
import { vec3 } from "../math/math3d";

function mirrorSeam(): MeshData {
	let data = MeshData.withUvs();
	for (let vertex = 0; vertex < 6; vertex++) {
		const x: float32 = (vertex % 3) as float32;
		const y: float32 = vertex < 3 ? 0.0 : 1.0;
		const added = addTexturedVertex(data, vec3(x, y, 0.0), vec3(0.0, 0.0, 1.0),
			{ u: x == 1.0 ? 0.0 : 1.0, v: 1.0 - y },
			{ red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 });
		if (!added.ok) { unreachable; }
	}
	if (!addTriangle(data, 0, 1, 4).ok || !addTriangle(data, 0, 4, 3).ok ||
		!addTriangle(data, 1, 2, 5).ok || !addTriangle(data, 1, 5, 4).ok) {
		unreachable;
	}
	return move data;
}

test "tangent seam sources preserve canonical influences on each appended vertex" {
	let data = mirrorSeam();
	const original: int32 = data.vertexCount();
	let sources: Vec<int32> = [99];
	const closed = addTangentsWithSources(data, sources);
	assert closed.ok;
	if (!closed.ok) { return; }
	assert closed.value == 8 && sources.length == 2;
	assert sources[0] == 1 && sources[1] == 4;
	let joints: Vec<int32> = [];
	let weights: Vec<float32> = [];
	for (let vertex = 0; vertex < data.vertexCount(); vertex++) {
		const source: int32 = vertex < original ? vertex : sources[vertex - original];
		for (let slot = 0; slot < 4; slot++) {
			joints.push(slot == 0 ? source : 0);
			weights.push(slot == 0 ? 1.0 : 0.0);
		}
	}
	assert addSkinAttributes(data, joints, weights).ok;
	assert data.stride() == 24;
	for (let vertex = 6; vertex < 8; vertex++) {
		const expected: int32 = vertex == 6 ? 1 : 4;
		const at: int32 = vertex * data.stride();
		const base: int32 = expected * data.stride();
		for (let field = 0; field < 12; field++) {
			assert data.vertices[at + field] == data.vertices[base + field];
		}
		assert data.vertices[at + 16] == expected as float32;
		assert data.vertices[at + 20] == 1.0;
	}
}

test "a continuous tangent island replaces old split sources with an empty map" {
	let data = MeshData.withUvs();
	for (let vertex = 0; vertex < 3; vertex++) {
		const x: float32 = vertex == 1 ? 1.0 : 0.0;
		const y: float32 = vertex == 2 ? 1.0 : 0.0;
		assert addTexturedVertex(data, vec3(x, y, 0.0), vec3(0.0, 0.0, 1.0),
			{ u: x, v: 1.0 - y },
			{ red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }).ok;
	}
	assert addTriangle(data, 0, 1, 2).ok;
	let sources: Vec<int32> = [99];
	const closed = addTangentsWithSources(data, sources);
	assert closed.ok;
	if (closed.ok) { assert closed.value == 3; }
	assert sources.length == 0 && data.vertexCount() == 3;
}

test "tangent source publication refuses invalid layouts without changing the caller map" {
	let data = MeshData.empty();
	let sources: Vec<int32> = [99];
	const refused = addTangentsWithSources(data, sources);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == MeshError.UvMismatch; }
	assert sources.length == 1 && sources[0] == 99 && !data.hasTangents;
	data = mirrorSeam();
	assert addTangentsWithSources(data, sources).ok;
	const repeated = addTangentsWithSources(data, sources);
	assert !repeated.ok;
	if (!repeated.ok) { assert repeated.error == MeshError.TangentsAdded; }
	assert sources.length == 2 && sources[0] == 1 && sources[1] == 4;
}
