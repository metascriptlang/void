// The DrawContext's mesh tables: what a mesh looks like once its CPU data is uploaded, and
// which meshes come back on their own after a context loss. All of it is arithmetic over the
// tables — nothing here makes a GPU object, and the upload itself is proven by the campfire
// readback (docs/VOID3D.md, M5 as built).

import { Vec3, vec3 } from "../math/math3d";
import { VertexLayout, layoutFloats, layoutPerInstance, drawsQuads } from "../void3d/gpu3d";
import {
	MeshData,
	MeshError,
	Rgba,
	LIT_VERTEX_STRIDE,
	addPlane,
	addVertex,
} from "../void3d/meshData";
import { PARTICLE_INSTANCE_STRIDE } from "../void3d/particles";
import { BILLBOARD_INSTANCE_STRIDE } from "../void3d/billboard";
import { added } from "./drawHelpers";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	StreamError,
	STREAM_INSTANCE_STRIDE,
	QUAD_VERTEX_COUNT,
	releaseMesh,
	staleMeshes,
	writeStream,
} from "../void3d/draw";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const UP: Vec3 = { x: 0.0, y: 1.0, z: 0.0 };
function billboard(): GpuMesh {
	return GpuMesh.billboards(12, 40);
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
	const first: MeshId = added(context, billboard());
	const second: MeshId = added(context, billboard());
	assert first.index == 0 && second.index == 1;
	assert first.generation == 1 && context.hasMesh(first) && context.hasMesh(second);
	assert (context.meshes.length as int32) == (context.meshData.length as int32);
	assert context.meshData[first.index].vertexCount() == 0;
}

test "a mesh whose buffers the caller keeps is not one the renderer can rebuild" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	assert added(context, billboard()).index == 0;
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
	const stream: GpuMesh = GpuMesh.streamMesh(64, 12, 1);
	assert stream.isStream();
	assert stream.layout == VertexLayout.Particle;
	assert stream.instanceCount == 0;
	assert stream.instanceCapacity == 64;
	assert stream.elementCount() == 6;
	assert !stream.isStale(1);
	assert stream.isStale(2);
	assert !billboard().isStream();
	assert !planeData().meshFor(7, 9, 3).isStream();
}

test "a billboard or stream draws its instances on the quad, the screen triangle its vertices" {
	const screen: GpuMesh = GpuMesh.fullscreen(12, 3);
	assert screen.layout == VertexLayout.Fullscreen;
	assert screen.vertexBuffer == (12 as uint32) && screen.instanceBuffer == (0 as uint32);
	assert screen.elementCount() == 3 && screen.instanceCount == 1;
	assert !screen.isQuadShaped() && !screen.hasNothingToDraw();
	const quads: GpuMesh = billboard();
	assert quads.layout == VertexLayout.Billboard;
	assert quads.vertexBuffer == (0 as uint32) && quads.instanceBuffer == (12 as uint32);
	assert quads.instanceCount == 40 && quads.elementCount() == QUAD_VERTEX_COUNT;
	assert quads.isQuadShaped() && !quads.hasNothingToDraw();
	const stream: GpuMesh = GpuMesh.streamMesh(64, 12, 1);
	assert stream.vertexBuffer == (0 as uint32) && stream.instanceBuffer == (12 as uint32);
	assert stream.isQuadShaped() && stream.hasNothingToDraw();
}

test "a quad mesh is off its shape with a vertex buffer, or instances and no buffer for them" {
	const cornered: GpuMesh = { ...billboard(), vertexBuffer: 7 };
	const strip: GpuMesh = { ...billboard(), vertexCount: 4 };
	assert !cornered.isQuadShaped() && !strip.isQuadShaped();
	assert !GpuMesh.billboards(0, 1).isQuadShaped();
	assert GpuMesh.billboards(0, 0).isQuadShaped() && GpuMesh.billboards(0, 0).hasNothingToDraw();
	assert GpuMesh.streamMesh(4, 0, 0).isQuadShaped();
}

test "the quad layouts are the layouts whose one buffer steps per instance" {
	const layouts: Vec<VertexLayout> = [
		VertexLayout.Lit,
		VertexLayout.Particle,
		VertexLayout.Billboard,
		VertexLayout.Fullscreen,
	];
	for (const layout of layouts) {
		assert drawsQuads(layout) == layoutPerInstance(layout);
		assert layoutFloats(layout, 1) == 0;
	}
	assert drawsQuads(VertexLayout.Particle) && drawsQuads(VertexLayout.Billboard);
}

function streamError(result: Result<int32, StreamError>): StreamError {
	return result.ok ? StreamError.BufferRefused : result.error;
}

test "a stream write is refused before the driver when it names the wrong mesh or too much" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const plain: MeshId = added(context, billboard());
	const stream: MeshId = added(context, GpuMesh.streamMesh(4, 12, 1));
	const four: Vec<float32> = new Array(4 * STREAM_INSTANCE_STRIDE);
	const never: MeshId = { index: 9, generation: 1 };
	assert streamError(writeStream(context, never, four, 1)) == StreamError.StaleMesh;
	const gone: MeshId = added(context, GpuMesh.streamMesh(4, 13, 1));
	assert releaseMesh(context, gone).ok;
	assert streamError(writeStream(context, gone, four, 1)) == StreamError.StaleMesh;
	assert streamError(writeStream(context, plain, four, 1)) == StreamError.NotAStream;
	assert streamError(writeStream(context, stream, four, 5)) == StreamError.OverCapacity;
	assert streamError(writeStream(context, stream, four, -1)) == StreamError.OverCapacity;
	assert streamError(writeStream(context, stream, four[0..8], 2)) == StreamError.ShortInstances;
	assert context.meshes[stream.index].instanceCount == 0;
}

test "every vertex layout carries the floats its writers write, per vertex and per instance" {
	assert layoutFloats(VertexLayout.Lit, 0) == LIT_VERTEX_STRIDE;
	assert layoutFloats(VertexLayout.Particle, 0) == STREAM_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.Particle, 0) == PARTICLE_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.Billboard, 0) == BILLBOARD_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.Fullscreen, 0) == 2;
}
