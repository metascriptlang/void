import {
	MeshData, MeshError, Rgba, addVertex, addTexturedVertex, addTriangle, addGivenTangents,
	addSkinAttributes, recomputeNormals,
} from "../void3d/meshData";
import { Vec3, vec3 } from "../math/math3d";

function normalFixture(layout: int32, skinned: boolean, encoding: int32): MeshData {
	const o = vec3(0, 0, 0);
	const a = vec3(2, 0, 0);
	const b = vec3(0, 2, 0);
	const c = vec3(0, 0, 1);
	const points: Vec<Vec3> = encoding == 0 ? [o, a, b, o, c, a] : [o, a, b, c];
	let data = layout == 0 ? MeshData.empty() : MeshData.withUvs();
	const color: Rgba = { red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0 };
	for (const point of points) {
		const result = layout == 0 ? addVertex(data, point, vec3(1, 0, 0), color)
			: addTexturedVertex(data, point, vec3(1, 0, 0), { u: 0.25, v: 0.75 }, color);
		if (!result.ok) { unreachable; }
	}
	let tangents: Vec<float32> = [];
	let joints: Vec<int32> = [];
	let weights: Vec<float32> = [];
	for (let i = 0; i < points.length; i++) {
		for (const value of [1.0 as float32, 0.0 as float32, 0.0 as float32, 1.0 as float32]) {
			tangents.push(value);
		}
		for (let j = 0; j < 4; j++) {
			joints.push(j == 0 ? i : 0);
			weights.push(j == 0 ? 1.0 : 0.0);
		}
	}
	if (layout == 2 && !addGivenTangents(data, tangents).ok) { unreachable; }
	if (skinned && !addSkinAttributes(data, joints, weights).ok) { unreachable; }
	if (encoding == 2) { data.wideIndices = []; }
	if (encoding > 0) {
		if (!addTriangle(data, 0, 1, 2).ok || !addTriangle(data, 0, 3, 1).ok) { unreachable; }
	}
	return move data;
}

test "normal rebuild is area weighted by stored vertex IDs and retains all other words" {
	for (const layout of [0, 1, 2]) {
		for (const skinned of [false, true]) {
			for (const encoding of [0, 1, 2]) {
				let data = normalFixture(layout, skinned, encoding);
				let before: Vec<float32> = data.vertices;
				const bounds = data.bounds;
				const width = data.stride();
				assert recomputeNormals(data).ok;
				assert data.bounds == bounds;
				assert data.vertexCount() == (encoding == 0 ? 6 : 4);
				assert data.indexCount() == (encoding == 0 ? 0 : 6);
				assert (data.wideIndices !== null) == (encoding == 2);
				const indices: Vec<uint32> = [0, 1, 2, 0, 3, 1];
				for (let i = 0; i < data.indexCount(); i++) {
					assert data.indexAt(i) == indices[i];
				}
				for (let vertex = 0; vertex < data.vertexCount(); vertex++) {
					const at = vertex * width;
					const shared: boolean = encoding > 0 && vertex < 2;
					const yFace: boolean = encoding == 0 ? vertex >= 3 : vertex == 3;
					const y: float32 = shared ? 0.4472136 : (yFace ? 1.0 : 0.0);
					const z: float32 = shared ? 0.8944272 : (yFace ? 0.0 : 1.0);
					assert data.vertices[at + 3] == 0.0;
					assert Math.abs(data.vertices[at + 4] - y) < 0.000001;
					assert Math.abs(data.vertices[at + 5] - z) < 0.000001;
					for (let field = 0; field < width; field++) {
						if (field >= 3 && field < 6) { continue; }
						assert data.vertices[at + field] == before[at + field];
					}
				}
			}
		}
	}
}

test "direct rich assert normal rebuild publishes ref mutation to its caller" {
	let data = normalFixture(0, false, 1);
	assert recomputeNormals(data).ok;
	assert data.vertices[3] == 0.0;
	assert Math.abs(data.vertices[4] - (0.4472136 as float32)) < 0.000001;
}

test "opposite winding and degenerate faces cancel without welding or stale normals" {
	for (const encoding of [1, 2]) {
		let data = normalFixture(0, false, encoding);
		data.indices = [];
		if (encoding == 2) { data.wideIndices = []; }
		for (const triangle of [0, 1]) {
			const added = addTriangle(data, 0, triangle == 0 ? 1 : 2, triangle == 0 ? 2 : 1);
			if (!added.ok) { unreachable; }
		}
		if (!addTriangle(data, 0, 0, 1).ok) { unreachable; }
		assert recomputeNormals(data).ok;
		for (let vertex = 0; vertex < data.vertexCount(); vertex++) {
			const at = vertex * data.stride();
			assert data.vertices[at + 3] == 0.0;
			assert data.vertices[at + 4] == 0.0;
			assert data.vertices[at + 5] == 0.0;
		}
	}
}

test "primary Float64 accumulation and EPSILON2 apply before normal word narrowing" {
	for (const extent of [1.0 as float32, 1.0e20 as float32, 1.0e-6 as float32]) {
		let data = normalFixture(0, false, 1);
		data.indices = [0, 1, 2];
		data.vertices[data.stride()] = extent;
		data.vertices[2 * data.stride() + 1] = extent;
		assert recomputeNormals(data).ok;
		assert data.vertices[3] == 0.0 && data.vertices[4] == 0.0;
		assert data.vertices[5] == (extent < 0.00001 ? 0.0 : 1.0);
		const unused = 3 * data.stride();
		assert data.vertices[unused + 3] == 0.0 && data.vertices[unused + 4] == 0.0;
		assert data.vertices[unused + 5] == 0.0;
	}
}

test "normal rebuilding preserves empty data and rejects storage or index faults atomically" {
	let empty = MeshData.empty();
	assert recomputeNormals(empty).ok;
	assert empty.vertexCount() == 0;
	for (const fault of [0, 1, 2]) {
		let data = normalFixture(2, true, 2);
		if (fault == 0) { data.vertices.push(1.0); }
		if (fault == 1) { data.indices.push(0); }
		if (fault == 2 && data.wideIndices !== null) { data.wideIndices[0] = 0x80000000; }
		let before: Vec<float32> = data.vertices;
		const bounds = data.bounds;
		const result = recomputeNormals(data);
		assert !result.ok;
		if (!result.ok) {
			const expected = fault == 0 ? MeshError.VertexStorage :
				(fault == 1 ? MeshError.IndexStorage : MeshError.IndexOutOfRange);
			assert result.error == expected;
		}
		assert data.bounds == bounds;
		for (let i = 0; i < before.length; i++) { assert data.vertices[i] == before[i]; }
	}
}

test "normal rebuilding rejects late nonfinite positions before changing any normal" {
	const infinite: float32 = (1.0 / 0.0) as float32;
	for (const invalid of [infinite, -infinite, infinite - infinite]) {
		let data = normalFixture(0, false, 1);
		data.vertices[3 * data.stride()] = invalid;
		let before: Vec<float32> = data.vertices;
		const result = recomputeNormals(data);
		assert !result.ok;
		if (!result.ok) { assert result.error == MeshError.PositionRange; }
		for (let i = 0; i < before.length; i++) {
			assert data.vertices[i] == before[i]
				|| (Number.isNaN(data.vertices[i]) && Number.isNaN(before[i]));
		}
	}
}
