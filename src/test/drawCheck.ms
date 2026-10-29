// The DrawContext's mesh tables: what a mesh looks like once its CPU data is uploaded, and
// which meshes come back on their own after a context loss. All of it is arithmetic over the
// tables — nothing here makes a GPU object, and the upload itself is proven by the campfire
// readback (docs/VOID3D.md, M5 as built).

import { IndexType } from "../gpu/pipeline";
import { RenderState, BlendMode } from "../gpu/state";
import { SWAPCHAIN_LAYOUT } from "../gpu/target";
import { Vec3, vec3, identity, translation } from "../math/math3d";
import {
	VertexLayout, layoutFloats, layoutPerInstance, drawsQuads, readsInstanceRows,
	ProgramKey, Program,
} from "../void3d/gpu3d";
import {
	PARTICLE_INSTANCE_STRIDE, PARTICLE_VISUAL_INSTANCE_STRIDE,
} from "../void3d/particleWriter";
import {
	MeshData,
	MeshError,
	Rgba,
	LIT_VERTEX_STRIDE,
	LIT_TEXTURED_VERTEX_STRIDE,
	addPlane,
	addVertex,
} from "../void3d/meshData";
import { BILLBOARD_INSTANCE_STRIDE } from "../void3d/billboard";
import { added } from "./drawHelpers";
import { NO_UNIFORMS, UniformBlock } from "../void3d/material";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	DrawItem,
	NO_MATERIAL,
	EXTERNAL_GENERATION,
	StreamError,
	STREAM_INSTANCE_STRIDE,
	MESH_INSTANCE_STRIDE,
	QUAD_VERTEX_COUNT,
	releaseMesh,
	staleMeshes,
	writeStream,
	addStreamMesh,
	PipelineMemo,
	SlotApply,
	holds,
	stillBound,
	takeListRows,
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

test "wide index metadata survives mesh upload description and context rebuild description" {
	let data = MeshData.empty();
	data.vertices = new Array(65539 * LIT_VERTEX_STRIDE);
	data.wideIndices = [0, 1, 2, 65536, 65537, 65538];
	const first = data.meshFor(7, 9, 3);
	const rebuilt = data.meshFor(11, 13, 4);
	assert first.index32 && rebuilt.index32;
	assert first.indexType() == IndexType.Uint32 && rebuilt.indexType() == IndexType.Uint32;
	assert first.elementCount() == 6 && rebuilt.elementCount() == 6;
	assert rebuilt.vertexCount == 65539 && rebuilt.generation == 4 && rebuilt.indexBuffer == 13;
	assert data.validIndices();
}

test "legacy GPU mesh literals default to uint16 and nonindexed buffers ignore width" {
	const legacy: GpuMesh = {
		layout: VertexLayout.Lit, vertexBuffer: 7, instanceBuffer: 0, indexBuffer: 9,
		vertexCount: 4, indexCount: 6, instanceCount: 1, instanceCapacity: 0,
		generation: 3, writtenFrame: 0,
	};
	assert !legacy.index32 && legacy.indexType() == IndexType.Uint16;
	const unindexed: GpuMesh = { ...legacy, indexBuffer: 0, index32: true };
	assert unindexed.indexType() == IndexType.None && unindexed.elementCount() == 4;
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

test "quad layouts step their one buffer per instance, mesh layouts read a row in slot 1" {
	const layouts: Vec<VertexLayout> = [
		VertexLayout.Lit,
		VertexLayout.Particle,
		VertexLayout.Billboard,
		VertexLayout.ParticleVisual,
		VertexLayout.Fullscreen,
		VertexLayout.LitTextured,
		VertexLayout.LitTexturedTangent,
		VertexLayout.SkinLit,
		VertexLayout.SkinLitTextured,
		VertexLayout.SkinLitTexturedTangent,
		VertexLayout.LitTexturedUvB,
		VertexLayout.LitTexturedTangentUvB,
		VertexLayout.SkinLitTexturedUvB,
		VertexLayout.SkinLitTexturedTangentUvB,
	];
	for (const layout of layouts) {
		assert drawsQuads(layout) == layoutPerInstance(layout, 0);
		const rows: boolean = readsInstanceRows(layout);
		assert layoutFloats(layout, 1) == (rows ? MESH_INSTANCE_STRIDE : 0);
		assert rows == layoutPerInstance(layout, 1);
		assert !(rows && drawsQuads(layout));
	}
	assert drawsQuads(VertexLayout.Particle) && drawsQuads(VertexLayout.Billboard);
	assert readsInstanceRows(VertexLayout.Lit) && readsInstanceRows(VertexLayout.SkinLit);
	assert !readsInstanceRows(VertexLayout.Fullscreen);
	assert layoutFloats(VertexLayout.LitTextured, 0) == 12;
}

function streamError(result: Result<int32, StreamError>): StreamError {
	return result.ok ? StreamError.BufferRefused : result.error;
}

test "a stream write is refused before the driver when it names the wrong mesh or too much" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const plain: MeshId = added(context, billboard());
	const stream: MeshId = added(context, GpuMesh.streamMesh(4, 12, 1));
	const four: Vec<float32> = new Array(4 * STREAM_INSTANCE_STRIDE);
	const never: MeshId = { store: context.serial, index: 9, generation: 1 };
	assert streamError(writeStream(context, never, four, 1)) == StreamError.StaleMesh;
	const foreign: MeshId = { ...stream, store: context.serial + 1 };
	assert streamError(writeStream(context, foreign, four, 1)) == StreamError.ForeignMesh;
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
	assert layoutFloats(VertexLayout.LitTextured, 0) == LIT_TEXTURED_VERTEX_STRIDE;
	assert layoutFloats(VertexLayout.Particle, 0) == STREAM_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.Particle, 0) == PARTICLE_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.ParticleVisual, 0) == PARTICLE_VISUAL_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.Billboard, 0) == BILLBOARD_INSTANCE_STRIDE;
	assert layoutFloats(VertexLayout.Fullscreen, 0) == 2;
}

test "a mesh uploaded from data with uvs is drawn on the LitTextured layout, without on Lit" {
	assert MeshData.withUvs().meshFor(1, 2, 1).layout == VertexLayout.LitTextured;
	assert MeshData.empty().meshFor(1, 2, 1).layout == VertexLayout.Lit;
}

test "particleVisual streams reject eight-float writes and overflowing capacity before GPU" {
	let context = DrawContext.withUniformCapacity(8);
	const stream = added(context, GpuMesh.streamMesh(2, 12, 1, VertexLayout.ParticleVisual));
	const oldRows: Vec<float32> = new Array(16);
	assert streamError(writeStream(context, stream, oldRows, 2)) == StreamError.ShortInstances;
	assert context.meshes[stream.index].layout == VertexLayout.ParticleVisual;
	assert context.meshes[stream.index].instanceCount == 0;
	const excessive = addStreamMesh(context, 134217728, VertexLayout.ParticleVisual);
	assert !excessive.ok && excessive.error == StreamError.OverCapacity;
}

test "a mesh program draws a run of a MeshInstances stream in place of its row, a skin none" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = added(context, {
		layout: VertexLayout.LitTextured, vertexBuffer: 7, instanceBuffer: 0, indexBuffer: 0,
		vertexCount: 3, indexCount: 0, instanceCount: 1, instanceCapacity: 0,
		generation: EXTERNAL_GENERATION, writtenFrame: 0,
	});
	const stream: MeshId = added(context, {
		...GpuMesh.streamMesh(8, 5, 1, VertexLayout.MeshInstances), instanceCount: 6,
	});
	const textured: ProgramKey = ProgramKey.of(Program.LitTextured);
	const item: DrawItem = {
		mesh: mesh, material: NO_MATERIAL, world: identity(),
		instances: { stream: stream, first: 2, count: 4 },
	};
	assert item.validInstances(context, textured);
	assert item.validInstances(context, ProgramKey.of(Program.Lit));
	assert !item.validInstances(context, { ...textured, skinned: true });
	assert !item.validInstances(context, ProgramKey.of(Program.Particle));
	const none: DrawItem = { ...item, instances: null };
	assert none.validInstances(context, textured);
	assert none.validInstances(context, { ...textured, skinned: true });
	const past: DrawItem = { ...item, instances: { stream: stream, first: 3, count: 4 } };
	assert !past.validInstances(context, textured);
	const notStream: DrawItem = { ...item, instances: { stream: mesh, first: 0, count: 1 } };
	assert !notStream.validInstances(context, textured);
	const visual: MeshId = added(context, {
		...GpuMesh.streamMesh(8, 6, 1, VertexLayout.ParticleVisual), instanceCount: 6,
	});
	const wrong: DrawItem = { ...item, instances: { stream: visual, first: 0, count: 1 } };
	assert !wrong.validInstances(context, textured);
}

test "neighbours batch when only their world matrices differ" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = added(context, billboard());
	const other: MeshId = added(context, billboard());
	const item: DrawItem = { mesh: mesh, material: NO_MATERIAL, world: identity() };
	const moved: DrawItem = { ...item, world: translation(1.0, 0.0, 0.0) };
	assert item.sameBatch(moved) && moved.sameBatch(item);
	assert !item.sameBatch({ ...item, mesh: other });
	assert !item.sameBatch({ ...item, range: { base: 0, count: 3 } });
	const run: DrawItem = { ...item, instances: { stream: mesh, first: 0, count: 1 } };
	assert !item.sameBatch(run) && !run.sameBatch(item);
}

function memoOf(): PipelineMemo {
	return {
		serial: 3, generation: 1, program: 7, layout: VertexLayout.Lit, indexed: true,
		format: IndexType.Uint16, state: RenderState.defaults(), targets: SWAPCHAIN_LAYOUT,
		pipeline: 42,
	};
}

test "a draw takes the last pipeline only when every input of its key is the same" {
	const memo: PipelineMemo = memoOf();
	assert memo.holds({ ...memo, pipeline: 0 }, true);
	assert !memo.holds(memo, false);
	assert !memo.holds({ ...memo, serial: 4 }, true);
	assert !memo.holds({ ...memo, generation: 2 }, true);
	assert !memo.holds({ ...memo, program: 8 }, true);
	assert !memo.holds({ ...memo, layout: VertexLayout.LitTextured }, true);
	assert !memo.holds({ ...memo, indexed: false }, true);
	assert !memo.holds({ ...memo, format: IndexType.Uint32 }, true);
	assert !memo.holds({ ...memo, state: RenderState.defaults().withBlendMode(BlendMode.Alpha) }, true);
	assert !memo.holds({ ...memo, targets: { ...SWAPCHAIN_LAYOUT, sampleCount: 4 } }, true);
}

test "a block stays bound only while its range, its floats, its stamp and the pool's writes are the same" {
	const block: UniformBlock = { store: 1, slot: 3, offset: 8, length: 12, generation: 1 };
	const last: SlotApply = { block: block, declared: 12, stamp: 5, writes: 9 };
	assert last.stillBound(block, 12, 5, 9);
	assert !last.stillBound(block, 12, 0, 9);
	assert !last.stillBound(block, 12, 6, 9);
	assert !last.stillBound(block, 4, 5, 9);
	assert !last.stillBound(block, 12, 5, 10);
	assert !last.stillBound({ ...block, offset: 20 }, 12, 5, 9);
	assert !last.stillBound({ ...block, generation: 2 }, 12, 5, 9);
	const none: SlotApply = { block: NO_UNIFORMS, declared: 0, stamp: 0, writes: 0 };
	assert !none.stillBound(NO_UNIFORMS, 0, 0, 0);
}

test "each draw of a staged list takes the rows after the draws before it" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	context.listActive = true;
	context.listBuffer = 9;
	context.listOffset = 256;
	context.listCounts = [1, 3, 2];
	const row: int32 = MESH_INSTANCE_STRIDE * 4;
	assert context.takeListRows(1) == 256;
	assert context.takeListRows(3) == 256 + row;
	assert context.takeListRows(2) == 256 + 4 * row;
	assert context.listCursor == 6 && context.listNext == 3;
}
