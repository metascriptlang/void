// The DrawContext's mesh tables: what a mesh looks like once its CPU data is uploaded, and
// which meshes come back on their own after a context loss. All of it is arithmetic over the
// tables — nothing here makes a GPU object, and the upload itself is proven by the campfire
// readback (docs/VOID3D.md, M5 as built).

import { Vec3, vec3 } from "../math/math3d";
import { VertexLayout } from "../void3d/gpu3d";
import { MeshData, Rgba, addPlane, addVertex } from "../void3d/meshData";
import { DrawContext, GpuMesh, addMesh, meshFor } from "../void3d/draw";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const UP: Vec3 = { x: 0.0, y: 1.0, z: 0.0 };
const NO_MESH: int32 = -1;

function billboard(): GpuMesh {
	return {
		layout: VertexLayout.Billboard,
		vertexBuffer: 11,
		instanceBuffer: 12,
		indexBuffer: 0,
		vertexCount: 6,
		indexCount: 0,
		instanceCount: 40,
		generation: 3,
	};
}

function planeData(): MeshData {
	let data: MeshData = MeshData.empty();
	const _added: int32 = try addPlane(data, 1.0, WHITE) catch NO_MESH;
	return data;
}

function triangleData(): MeshData {
	let data: MeshData = MeshData.empty();
	const _a: int32 = try addVertex(data, vec3(0.0, 0.0, 0.0), UP, WHITE) catch NO_MESH;
	const _b: int32 = try addVertex(data, vec3(1.0, 0.0, 0.0), UP, WHITE) catch NO_MESH;
	const _c: int32 = try addVertex(data, vec3(0.0, 0.0, 1.0), UP, WHITE) catch NO_MESH;
	return data;
}

test "a mesh built from MeshData is indexed and counts its own elements" {
	const mesh: GpuMesh = meshFor(planeData(), 7, 9, 3);
	assert mesh.layout == VertexLayout.Lit;
	assert mesh.vertexBuffer == (7 as uint32);
	assert mesh.indexBuffer == (9 as uint32);
	assert mesh.vertexCount == 4;
	assert mesh.indexCount == 6;
	assert mesh.instanceCount == 1;
	assert mesh.generation == 3;
	assert mesh.elementCount() == 6;
}

test "MeshData with no indices leaves the index buffer unbound and draws its vertices" {
	// An index buffer handed in is ignored when the data has no indices, so a stale handle
	// from an earlier upload cannot survive into a non-indexed mesh.
	const mesh: GpuMesh = meshFor(triangleData(), 7, 9, 3);
	assert mesh.indexBuffer == (0 as uint32);
	assert mesh.indexCount == 0;
	assert mesh.elementCount() == 3;
}

test "an empty MeshData gives an empty mesh rather than a bad draw" {
	const mesh: GpuMesh = meshFor(MeshData.empty(), 7, 9, 3);
	assert mesh.indexBuffer == (0 as uint32);
	assert mesh.vertexCount == 0 && mesh.elementCount() == 0;
}

test "addMesh keeps the two tables one index space" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	assert (context.meshes.length as int32) == 0 && (context.meshData.length as int32) == 0;
	const first: int32 = addMesh(context, billboard());
	const second: int32 = addMesh(context, billboard());
	assert first == 0 && second == 1;
	assert (context.meshes.length as int32) == (context.meshData.length as int32);
	assert context.meshData[first].vertexCount() == 0;
}

test "a mesh whose buffers the caller keeps is not one the renderer can rebuild" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	assert addMesh(context, billboard()) == 0;
	assert context.rebuildableMeshes() == 0;
	// Not stale on any generation: there is no CPU data to rebuild it from, so the caller owns
	// it and the renderer must not touch it.
	assert context.staleMeshes(3) == 0;
	assert context.staleMeshes(4) == 0;
}

test "a mesh is stale exactly when it has CPU data from an older context" {
	const data: MeshData = planeData();
	const current: GpuMesh = meshFor(data, 7, 9, 3);
	assert !current.isStale(data, 3);
	assert current.isStale(data, 4);
	// The same handles with no CPU data behind them are never stale: nothing here can rebuild
	// them, and re-uploading from an empty MeshData would erase a working mesh.
	assert !current.isStale(MeshData.empty(), 4);
}

test "a mesh never uploaded is stale on every generation the GPU can be on" {
	const data: MeshData = planeData();
	const fresh: GpuMesh = meshFor(data, 0, 0, 0);
	assert fresh.isStale(data, 1);
	assert fresh.isStale(data, 2);
}
