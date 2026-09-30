import { Vec3, vec3 } from "../math/math3d";
import { Face } from "../gpu/state";
import { Ray } from "../void3d/ray";
import { Bounds3D } from "../void3d/bounds";
import {
	MeshData,
	MeshError,
	Rgba,
	Box,
	LIT_VERTEX_STRIDE,
	LIT_TEXTURED_VERTEX_STRIDE,
	CUBE_VERTICES,
	Uv,
	MAX_MESH_VERTICES,
	BOX_VERTICES,
	addVertex,
	addTexturedVertex,
	addTexturedQuad,
	addTexturedCube,
	addTriangle,
	addQuad,
	addBox,
	addPlane,
	recomputeBounds,
} from "../void3d/meshData";
import { approx } from "./helpers";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const UP: Vec3 = { x: 0.0, y: 1.0, z: 0.0 };

function near(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(a.x, x) && approx(a.y, y) && approx(a.z, z);
}

function positionAt(data: MeshData, index: int32): Vec3 {
	const base: int32 = index * LIT_VERTEX_STRIDE;
	return vec3(data.vertices[base], data.vertices[base + 1], data.vertices[base + 2]);
}

function normalAt(data: MeshData, index: int32): Vec3 {
	const base: int32 = index * LIT_VERTEX_STRIDE;
	return vec3(data.vertices[base + 3], data.vertices[base + 4], data.vertices[base + 5]);
}

function plainBox(height: float32): Box {
	return {
		base: vec3(0.0, 0.0, 0.0),
		size: vec3(2.0, height, 4.0),
		yaw: 0.0,
		tilt: 0.0,
		color: WHITE,
	};
}

test "an empty mesh has no vertices, no indices and empty bounds" {
	const data: MeshData = MeshData.empty();
	assert data.vertexCount() == 0;
	assert data.indexCount() == 0;
	assert data.triangleCount() == 0;
	assert !data.isIndexed();
	assert data.bounds.isEmpty();
}

test "a vertex writes ten floats in the Lit layout and returns its index" {
	let data: MeshData = MeshData.empty();
	const first: Result<int32, MeshError> = addVertex(data, vec3(1.0, 2.0, 3.0), UP, WHITE);
	assert first.ok;
	if (first.ok) { assert first.value == 0; }
	assert (data.vertices.length as int32) == LIT_VERTEX_STRIDE;
	assert data.vertexCount() == 1;
	assert near(positionAt(data, 0), 1.0, 2.0, 3.0);
	assert near(normalAt(data, 0), 0.0, 1.0, 0.0);
	assert approx(data.vertices[6], 1.0) && approx(data.vertices[9], 1.0);
	const second: Result<int32, MeshError> = addVertex(data, vec3(0.0, 0.0, 0.0), UP, WHITE);
	assert second.ok;
	if (second.ok) { assert second.value == 1; }
}

test "vertices grow the bounds as they arrive" {
	let data: MeshData = MeshData.empty();
	assert addVertex(data, vec3(1.0, 2.0, 3.0), UP, WHITE).ok;
	assert addVertex(data, vec3(-1.0, 5.0, 0.0), UP, WHITE).ok;
	assert near(data.bounds.min, -1.0, 2.0, 0.0);
	assert near(data.bounds.max, 1.0, 5.0, 3.0);
}

test "a triangle out of range is rejected and pushes nothing" {
	let data: MeshData = MeshData.empty();
	assert addVertex(data, vec3(0.0, 0.0, 0.0), UP, WHITE).ok;
	const bad: Result<int32, MeshError> = addTriangle(data, 0, 1, 2);
	assert !bad.ok;
	if (!bad.ok) { assert bad.error == MeshError.IndexOutOfRange; }
	assert data.indexCount() == 0;
}

test "a negative vertex index is rejected as firmly as one past the end" {
	let data: MeshData = MeshData.empty();
	assert addVertex(data, vec3(0.0, 0.0, 0.0), UP, WHITE).ok;
	assert addVertex(data, vec3(1.0, 0.0, 0.0), UP, WHITE).ok;
	assert addVertex(data, vec3(0.0, 0.0, 1.0), UP, WHITE).ok;
	const negative: Result<int32, MeshError> = addTriangle(data, 0, -1, 2);
	assert !negative.ok;
	if (!negative.ok) { assert negative.error == MeshError.IndexOutOfRange; }
	assert data.indexCount() == 0;
	const good: Result<int32, MeshError> = addTriangle(data, 0, 1, 2);
	assert good.ok;
	if (good.ok) { assert good.value == 0; }
	assert data.indexCount() == 3;
}

test "a quad is four vertices and two triangles sharing two corners" {
	let data: MeshData = MeshData.empty();
	const added: Result<int32, MeshError> = addQuad(
		data,
		vec3(0.0, 0.0, 0.0),
		vec3(1.0, 0.0, 0.0),
		vec3(1.0, 0.0, 1.0),
		vec3(0.0, 0.0, 1.0),
		UP,
		WHITE,
	);
	assert added.ok;
	assert data.vertexCount() == 4;
	assert data.indexCount() == 6;
	assert data.triangleCount() == 2;
	assert data.isIndexed();
	assert data.indices[0] == (0 as uint16) && data.indices[1] == (1 as uint16);
	assert data.indices[2] == (2 as uint16) && data.indices[3] == (0 as uint16);
	assert data.indices[4] == (2 as uint16) && data.indices[5] == (3 as uint16);
}

test "a second quad indexes its own vertices, not the first quad's" {
	let data: MeshData = MeshData.empty();
	assert addPlane(data, 1.0, WHITE).ok;
	assert addPlane(data, 2.0, WHITE).ok;
	assert data.vertexCount() == 8;
	assert data.indexCount() == 12;
	assert data.indices[6] == (4 as uint16);
	assert data.indices[11] == (7 as uint16);
}

test "the plane spans halfSize on both axes and faces up" {
	let data: MeshData = MeshData.empty();
	assert addPlane(data, 40.0, WHITE).ok;
	assert near(data.bounds.min, -40.0, 0.0, -40.0);
	assert near(data.bounds.max, 40.0, 0.0, 40.0);
	assert near(normalAt(data, 0), 0.0, 1.0, 0.0);
}

test "a box is five quads, twenty vertices and thirty indices" {
	let data: MeshData = MeshData.empty();
	assert addBox(data, plainBox(3.0)).ok;
	assert data.vertexCount() == 20;
	assert data.indexCount() == 30;
	assert data.triangleCount() == 10;
}

test "an unturned box stands on its base and spans its size" {
	let data: MeshData = MeshData.empty();
	assert addBox(data, plainBox(3.0)).ok;
	assert near(data.bounds.min, -1.0, 0.0, -2.0);
	assert near(data.bounds.max, 1.0, 3.0, 2.0);
	assert near(data.bounds.size(), 2.0, 3.0, 4.0);
}

test "a box at a base is the same box moved there" {
	let atOrigin: MeshData = MeshData.empty();
	let moved: MeshData = MeshData.empty();
	assert addBox(atOrigin, plainBox(3.0)).ok;
	assert addBox(moved, { ...plainBox(3.0), base: vec3(10.0, 0.0, -5.0) }).ok;
	assert near(moved.bounds.min, 9.0, 0.0, -7.0);
	assert near(moved.bounds.max, 11.0, 3.0, -3.0);
	const spread: Vec3 = atOrigin.bounds.size();
	assert near(moved.bounds.size(), spread.x, spread.y, spread.z);
}

test "a quarter-turn yaw swaps the box's X and Z extents" {
	let data: MeshData = MeshData.empty();
	assert addBox(data, { ...plainBox(3.0), yaw: 1.5707963 }).ok;
	assert near(data.bounds.size(), 4.0, 3.0, 2.0);
}

test "the box's first quad is its top face, normal up" {
	let data: MeshData = MeshData.empty();
	assert addBox(data, plainBox(3.0)).ok;
	assert near(normalAt(data, 0), 0.0, 1.0, 0.0);
	assert approx(positionAt(data, 0).y, 3.0);
}

test "recomputeBounds agrees with the bounds the builders kept" {
	let data: MeshData = MeshData.empty();
	assert addBox(data, { ...plainBox(2.5), yaw: 0.7, tilt: -0.3 }).ok;
	const kept: Bounds3D = data.bounds;
	recomputeBounds(data);
	assert near(data.bounds.min, kept.min.x, kept.min.y, kept.min.z);
	assert near(data.bounds.max, kept.max.x, kept.max.y, kept.max.z);
}

test "hasRoomFor counts against the uint16 index cap" {
	let data: MeshData = MeshData.empty();
	assert data.hasRoomFor(MAX_MESH_VERTICES);
	assert !data.hasRoomFor(MAX_MESH_VERTICES + 1);
	assert addPlane(data, 1.0, WHITE).ok;
	assert data.hasRoomFor(MAX_MESH_VERTICES - 4);
	assert !data.hasRoomFor(MAX_MESH_VERTICES - 3);
}

// A builder that cannot fit has to add nothing at all: `try` propagates out of a half-written
// quad, and every caller reads an err as "nothing was added".
test "a builder that does not fit leaves the mesh exactly as it was" {
	let data: MeshData = MeshData.empty();
	const room: int32 = MAX_MESH_VERTICES - BOX_VERTICES + 1;
	for (let i = 0; i < room; i++) {
		if (!addVertex(data, vec3(0.0, 0.0, 0.0), UP, WHITE).ok) { break; }
	}
	assert data.vertexCount() == room;
	const before: int32 = data.vertexCount();
	const indicesBefore: int32 = data.indexCount();
	const rejected: Result<int32, MeshError> = addBox(data, plainBox(1.0));
	assert !rejected.ok;
	if (!rejected.ok) { assert rejected.error == MeshError.TooManyVertices; }
	assert data.vertexCount() == before;
	assert data.indexCount() == indicesBefore;
}

// The byte-identity of the campfire rests on addBox producing the floats the deleted spike
// produced, and the baselines that would catch a change live in gitignored out/tmp. These
// literals are the half of that contract which survives losing them: at `approx`'s tolerance
// they catch the geometry moving — someone expressing the placement as a Mat4 in M6, say —
// while a change of the last ulp still only shows up in the capture comparison.
test "the box builder still produces the spike's vertex floats" {
	let data: MeshData = MeshData.empty();
	const leaning: Box = {
		base: vec3(0.5, 0.0, -0.25),
		size: vec3(0.16, 0.95, 0.16),
		yaw: 0.4,
		tilt: -0.85,
		color: WHITE,
	};
	assert addBox(data, leaning).ok;
	// Top face, first corner and third corner, and the top face's rotated normal.
	assert near(positionAt(data, 0), 0.12782013, 0.56688148, -0.92485362);
	assert near(positionAt(data, 2), 0.31631139, 0.68708634, -0.88989902);
	assert near(normalAt(data, 0), -0.29256237, 0.65998310, -0.69197506);
	assert near(data.bounds.min, 0.12782013, -0.06010243, -0.98716056);
	assert near(data.bounds.max, 0.59424561, 0.68708634, -0.17021576);
}

test "every index a builder writes is within the vertex count" {
	let data: MeshData = MeshData.empty();
	assert addPlane(data, 40.0, WHITE).ok;
	assert addBox(data, { ...plainBox(1.0), base: vec3(2.0, 0.0, 2.0), tilt: 0.4 }).ok;
	const count: int32 = data.vertexCount();
	for (const index of data.indices) {
		assert (index as int32) < count;
	}
	assert data.indexCount() == 36;
}

function uvAt(data: MeshData, index: int32): Uv {
	let base: int32 = index * data.stride();
	return { u: data.vertices[base + 6], v: data.vertices[base + 7] };
}

function texturedPositionAt(data: MeshData, index: int32): Vec3 {
	let base: int32 = index * data.stride();
	return vec3(data.vertices[base], data.vertices[base + 1], data.vertices[base + 2]);
}

function texturedNormalAt(data: MeshData, index: int32): Vec3 {
	let base: int32 = index * data.stride();
	return vec3(data.vertices[base + 3], data.vertices[base + 4], data.vertices[base + 5]);
}

function isUv(uv: Uv, u: float32, v: float32): boolean {
	return uv.u == u && uv.v == v;
}

test "a vertex of a mesh with uvs is twelve floats: position, normal, uv, then colour" {
	let data: MeshData = MeshData.withUvs();
	let red: Rgba = { red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5 };
	let added: Result<int32, MeshError> =
		addTexturedVertex(data, vec3(1.0, 2.0, 3.0), UP, { u: 0.25, v: 0.75 }, red);
	assert added.ok;
	assert data.stride() == LIT_TEXTURED_VERTEX_STRIDE;
	assert MeshData.empty().stride() == LIT_VERTEX_STRIDE;
	assert (data.vertices.length as int32) == LIT_TEXTURED_VERTEX_STRIDE;
	assert data.vertexCount() == 1;
	assert near(texturedPositionAt(data, 0), 1.0, 2.0, 3.0);
	assert near(texturedNormalAt(data, 0), 0.0, 1.0, 0.0);
	assert isUv(uvAt(data, 0), 0.25, 0.75);
	assert data.vertices[8] == 1.0 && data.vertices[9] == 0.0 && data.vertices[11] == 0.5;
	assert near(data.bounds.min, 1.0, 2.0, 3.0);
}

test "a vertex without a uv is refused on a mesh with uvs, and one with a uv on a mesh without" {
	let textured: MeshData = MeshData.withUvs();
	let plain: Result<int32, MeshError> = addVertex(textured, vec3(0.0, 0.0, 0.0), UP, WHITE);
	assert !plain.ok && plain.error == MeshError.UvMismatch;
	let flatQuad: Result<int32, MeshError> = addQuad(
		textured, vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0),
		vec3(0.0, 1.0, 0.0), UP, WHITE,
	);
	assert !flatQuad.ok && flatQuad.error == MeshError.UvMismatch;
	assert textured.vertexCount() == 0 && textured.indexCount() == 0 && textured.bounds.isEmpty();
	let untextured: MeshData = MeshData.empty();
	let withUv: Result<int32, MeshError> =
		addTexturedVertex(untextured, vec3(0.0, 0.0, 0.0), UP, { u: 0.0, v: 0.0 }, WHITE);
	assert !withUv.ok && withUv.error == MeshError.UvMismatch;
	let quad: Result<int32, MeshError> = addTexturedQuad(
		untextured, vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0),
		vec3(0.0, 1.0, 0.0), UP, WHITE,
	);
	assert !quad.ok && quad.error == MeshError.UvMismatch;
	let cube: Result<int32, MeshError> =
		addTexturedCube(untextured, vec3(1.0, 1.0, 1.0), true, WHITE);
	assert !cube.ok && cube.error == MeshError.UvMismatch;
	assert untextured.vertexCount() == 0 && untextured.indexCount() == 0;
}

test "a textured quad spans the whole texture, its first row along its top edge" {
	let data: MeshData = MeshData.withUvs();
	let added: Result<int32, MeshError> = addTexturedQuad(
		data, vec3(0.0, 0.0, 0.0), vec3(2.0, 0.0, 0.0), vec3(2.0, 1.0, 0.0),
		vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	assert added.ok;
	assert isUv(uvAt(data, 0), 0.0, 1.0) && isUv(uvAt(data, 1), 1.0, 1.0);
	assert isUv(uvAt(data, 2), 1.0, 0.0) && isUv(uvAt(data, 3), 0.0, 0.0);
	assert data.indexCount() == 6;
	assert data.indices[0] == 0 && data.indices[1] == 1 && data.indices[2] == 2;
	assert data.indices[3] == 0 && data.indices[4] == 2 && data.indices[5] == 3;
}

test "a textured cube is Heaps' Cube with addUVs: 24 vertices, each face the whole texture" {
	let data: MeshData = MeshData.withUvs();
	let added: Result<int32, MeshError> =
		addTexturedCube(data, vec3(1.0, 2.0, 4.0), true, WHITE);
	assert added.ok;
	if (added.ok) { assert added.value == 0; }
	assert data.vertexCount() == CUBE_VERTICES && data.indexCount() == 36;
	assert near(data.bounds.min, -0.5, -1.0, -2.0) && near(data.bounds.max, 0.5, 1.0, 2.0);
	for (let face = 0; face < 6; face++) {
		let a: Vec3 = texturedPositionAt(data, face * 4);
		let b: Vec3 = texturedPositionAt(data, face * 4 + 1);
		let c: Vec3 = texturedPositionAt(data, face * 4 + 2);
		let d: Vec3 = texturedPositionAt(data, face * 4 + 3);
		let normal: Vec3 = texturedNormalAt(data, face * 4);
		let winding: Vec3 = (b - a).cross(c - a).normalized();
		assert near(winding, normal.x, normal.y, normal.z);
		let centre: Vec3 = (a + c).scaled(0.5);
		assert centre.dot(normal) > 0.0;
		assert isUv(uvAt(data, face * 4), 0.0, 1.0) && isUv(uvAt(data, face * 4 + 3), 0.0, 0.0);
		assert isUv(uvAt(data, face * 4 + 1), 1.0, 1.0) && isUv(uvAt(data, face * 4 + 2), 1.0, 0.0);
		if (normal.y > 0.5) {
			assert d.z < a.z;
		} else if (normal.y < -0.5) {
			assert d.z > a.z;
		} else {
			assert d.y > a.y;
		}
	}
	let corner: MeshData = MeshData.withUvs();
	assert addTexturedCube(corner, vec3(1.0, 2.0, 4.0), false, WHITE).ok;
	assert near(corner.bounds.min, 0.0, 0.0, 0.0) && near(corner.bounds.max, 1.0, 2.0, 4.0);
}

test "bounds and picking read a mesh with uvs at its own stride" {
	let data: MeshData = MeshData.withUvs();
	assert addTexturedCube(data, vec3(1.0, 1.0, 1.0), true, WHITE).ok;
	let kept: Bounds3D = data.bounds;
	recomputeBounds(data);
	assert near(data.bounds.min, kept.min.x, kept.min.y, kept.min.z);
	assert near(data.bounds.max, kept.max.x, kept.max.y, kept.max.z);
	let toward: Ray = { origin: vec3(0.1, 0.2, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(data.rayIntersection(toward, Face.Back), 4.5);
	let beside: Ray = { origin: vec3(2.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert data.rayIntersection(beside, Face.Back) == -1.0;
}

test "a builder with uvs that does not fit leaves the mesh exactly as it was" {
	let data: MeshData = MeshData.withUvs();
	let room: int32 = MAX_MESH_VERTICES - CUBE_VERTICES + 1;
	for (let i = 0; i < room; i++) {
		let uv: Uv = { u: 0.0, v: 0.0 };
		if (!addTexturedVertex(data, vec3(0.0, 0.0, 0.0), UP, uv, WHITE).ok) { break; }
	}
	assert data.vertexCount() == room;
	let rejected: Result<int32, MeshError> =
		addTexturedCube(data, vec3(1.0, 1.0, 1.0), true, WHITE);
	assert !rejected.ok && rejected.error == MeshError.TooManyVertices;
	assert data.vertexCount() == room && data.indexCount() == 0;
}
