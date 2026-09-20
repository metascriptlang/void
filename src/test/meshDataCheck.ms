import { Vec3, vec3 } from "../math/math3d";
import { Bounds } from "../void3d/bounds";
import {
	MeshData,
	MeshError,
	Rgba,
	Box,
	LIT_VERTEX_STRIDE,
	MAX_MESH_VERTICES,
	BOX_VERTICES,
	addVertex,
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
	const kept: Bounds = data.bounds;
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
