// The DrawContext's mesh tables: what a mesh looks like once its CPU data is uploaded, and
// which meshes come back on their own after a context loss. All of it is arithmetic over the
// tables — nothing here makes a GPU object, and the upload itself is proven by the campfire
// readback (docs/VOID3D.md, M5 as built).

import { Vec3, vec3 } from "../math/math3d";
import { VertexLayout } from "../void3d/gpu3d";
import { MeshData, MeshError, Rgba, addPlane, addVertex } from "../void3d/meshData";
import {
	DrawContext,
	GpuMesh,
	StreamError,
	STREAM_INSTANCE_STRIDE,
	addMesh,
	staleMeshes,
	writeStream,
} from "../void3d/draw";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const UP: Vec3 = { x: 0.0, y: 1.0, z: 0.0 };
function billboard(): GpuMesh {
	return GpuMesh.external(VertexLayout.Billboard, 11, 12, 6, 40);
}

function planeData(): MeshData {
	let data: MeshData = MeshData.empty();
	const _added: Result<int32, MeshError> = addPlane(data, 1.0, WHITE);
	return data;
}

function triangleData(): MeshData {
	let data: MeshData = MeshData.empty();
	const _a: Result<int32, MeshError> = addVertex(data, vec3(0.0, 0.0, 0.0), UP, WHITE);
	const _b: Result<int32, MeshError> = addVertex(data, vec3(1.0, 0.0, 0.0), UP, WHITE);
	const _c: Result<int32, MeshError> = addVertex(data, vec3(0.0, 0.0, 1.0), UP, WHITE);
	return data;
}

test "a mesh built from MeshData is indexed and counts its own elements" {
	const mesh: GpuMesh = planeData().meshFor(7, 9, 3);
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
	const mesh: GpuMesh = triangleData().meshFor(7, 9, 3);
	assert mesh.indexBuffer == (0 as uint32);
	assert mesh.indexCount == 0;
	assert mesh.elementCount() == 3;
}

test "an empty MeshData describes a mesh that draws nothing" {
	const mesh: GpuMesh = MeshData.empty().meshFor(7, 9, 3);
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
	// Not stale on any generation: the sentinel says the caller owns the buffers, and the
	// renderer must not touch them.
	assert staleMeshes(context, 3) == 0;
	assert staleMeshes(context, 4) == 0;
}

test "a mesh is stale exactly when its generation is neither external nor current" {
	const data: MeshData = planeData();
	const current: GpuMesh = data.meshFor(7, 9, 3);
	assert !current.isStale(3);
	assert current.isStale(4);
	// An external mesh is never stale whatever the generation: re-uploading it from the empty
	// MeshData it carries would zero handles its owner still holds.
	assert !billboard().isStale(3);
	assert !billboard().isStale(4);
}

test "a mesh never uploaded is stale on every generation the GPU can be on" {
	const data: MeshData = planeData();
	const fresh: GpuMesh = data.meshFor(0, 0, 0);
	assert fresh.isStale(1);
	assert fresh.isStale(2);
}

test "a stream mesh draws nothing until written and is the only kind with a capacity" {
	const stream: GpuMesh = GpuMesh.streamMesh(64, 11, 12, 1);
	assert stream.isStream();
	assert stream.layout == VertexLayout.Billboard;
	assert stream.instanceCount == 0;
	assert stream.instanceCapacity == 64;
	assert stream.elementCount() == 6;
	assert !stream.isStale(1);
	assert stream.isStale(2);
	assert !billboard().isStream();
	assert !planeData().meshFor(7, 9, 3).isStream();
}

function streamError(result: Result<int32, StreamError>): StreamError {
	return result.ok ? StreamError.BufferRefused : result.error;
}

test "a stream write is refused before the driver when it names the wrong mesh or too much" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const plain: int32 = addMesh(context, billboard());
	const stream: int32 = addMesh(context, GpuMesh.streamMesh(4, 11, 12, 1));
	const four: Vec<float32> = new Array(4 * STREAM_INSTANCE_STRIDE);
	assert streamError(writeStream(context, 9, four, 1)) == StreamError.MeshOutOfRange;
	assert streamError(writeStream(context, plain, four, 1)) == StreamError.NotAStream;
	assert streamError(writeStream(context, stream, four, 5)) == StreamError.OverCapacity;
	assert streamError(writeStream(context, stream, four, -1)) == StreamError.OverCapacity;
	assert streamError(writeStream(context, stream, four[0..8], 2)) == StreamError.ShortInstances;
	assert context.meshes[stream].instanceCount == 0;
}
