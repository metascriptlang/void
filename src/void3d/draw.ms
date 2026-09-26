// Draw items and the tables they index. The renderer consumes a flat Span<DrawItem>, not the
// scene tree (docs/VOID3D.md, Porting rules): a scene flattens into items when its structure
// changes, and every frame only rewrites their world matrices.
//
// DrawContext owns everything items point into: GPU meshes, materials, the uniform pool and the
// pipeline cache. Items and materials are plain values holding indices and handles.

import { Mat4, normalMatrix, writeTo } from "../math/math3d";
import {
	VertexLayout,
	Program,
	applyPipeline,
	applyBindings,
	applyUniforms,
	draw,
	makeVertexBuffer,
	makeIndexBuffer,
	makeStreamBuffer,
	updateBuffer,
	destroyBuffer,
	contextGeneration,
} from "./gpu3d";
import {
	GPU3D_BINDING_VERTEX_BUFFER,
	GPU3D_BINDING_INDEX_BUFFER,
	GPU3D_BINDING_VIEW,
	GPU3D_BINDING_SAMPLER,
	GPU3D_BINDING_LENGTH,
} from "./gpu3d.h";
import { Material, UniformBlock } from "./material";
import { MeshData } from "./meshData";
import { PipelineCache, pipelineFor } from "./pipelineCache";
import { TargetLayout } from "./target";

// GPU side of a mesh: buffer handles plus what sg_draw needs. `instanceBuffer` feeds vertex
// buffer slot 1 (billboard instances), 0 when not instanced. `indexBuffer` is 0 for a mesh
// drawn straight from its vertex buffer, and then `indexCount` is unread; when it is set the
// draw is indexed and takes `indexCount` elements. The CPU data a lost context rebuilds this
// from is the MeshData at the same index of `DrawContext.meshData` (addMeshData).
//
// `generation` is the GPU context these handles belong to, 0 for a mesh never uploaded here.
// It is what keeps rebuildMeshes from re-uploading a mesh that is already current — the first
// frame after create() is always a new context to the renderer, and without it every mesh
// would be uploaded twice and the first pair of buffers would leak.
export struct GpuMesh {
	layout: VertexLayout;
	vertexBuffer: uint32;
	instanceBuffer: uint32;
	indexBuffer: uint32;
	vertexCount: int32;
	indexCount: int32;
	instanceCount: int32;
	instanceCapacity: int32;
	generation: int32;
}

export function isIndexed(this mesh: GpuMesh): boolean {
	return mesh.indexBuffer != 0;
}

// What sg_draw counts: index elements when indexed, vertices otherwise.
export function elementCount(this mesh: GpuMesh): int32 {
	return mesh.isIndexed() ? mesh.indexCount : mesh.vertexCount;
}

export struct DrawItem {
	mesh: int32;
	material: int32;
	world: Mat4;
}

// `meshes` and `meshData` are one index space: meshData[i] is the CPU geometry mesh[i] was
// uploaded from, or an empty MeshData for a mesh whose data its owner keeps (the screen
// triangle, billboard corners and instances). Everything with CPU data here comes back on its
// own after a context loss (rebuildMeshes); everything without is its owner's to rebuild.
// Slot 4, matching `layout(binding=4) uniform modelParams` in shader3dBlocks.glsl, a slot no
// other block uses: a program gets the model matrix exactly when it declares that slot.
export const MODEL_SLOT: int32 = 4;
export const MODEL_LENGTH: int32 = 32;

export struct DrawContext {
	meshes: Vec<GpuMesh>;
	meshData: Vec<MeshData>;
	materials: Vec<Material>;
	uniforms: Vec<float32>;
	uniformsUsed: int32;
	pipelines: PipelineCache;
	bindings: Vec<uint32>;
	model: Vec<float32>;
}

export enum UniformError {
	PoolFull,
	WrongLength,
}

export enum MeshUploadError {
	EmptyMesh,
	VertexBufferRefused,
	IndexBufferRefused,
}

// The uniform pool is sized here, once; reserveUniforms only hands out ranges of it.
export function withUniformCapacity(this typeof DrawContext, capacity: int32): DrawContext {
	const bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH);
	for (let i = 0; i < GPU3D_BINDING_LENGTH; i++) {
		bindings[i] = 0;
	}
	const model: Vec<float32> = new Array(MODEL_LENGTH);
	for (let i = 0; i < MODEL_LENGTH; i++) {
		model[i] = 0.0;
	}
	return {
		meshes: [],
		meshData: [],
		materials: [],
		uniforms: new Array(capacity),
		uniformsUsed: 0,
		pipelines: PipelineCache.empty(),
		bindings: bindings,
		model: model,
	};
}

// A mesh whose buffers the caller made and keeps: no CPU data here, so a lost context is the
// caller's to repair.
export function addMesh(ref context: DrawContext, mesh: GpuMesh): int32 {
	context.meshes.push(mesh);
	context.meshData.push(MeshData.empty());
	return (context.meshes.length as int32) - 1;
}

// The GpuMesh that `data` describes once its buffers exist. Pure: what the counts and the
// indexed flag are is decided here, so the rebuild path can be checked without a GPU.
export function meshFor(
	this data: MeshData,
	vertexBuffer: uint32,
	indexBuffer: uint32,
	generation: int32,
): GpuMesh {
	return {
		layout: VertexLayout.Lit,
		vertexBuffer: vertexBuffer,
		instanceBuffer: 0,
		indexBuffer: data.isIndexed() ? indexBuffer : (0 as uint32),
		vertexCount: data.vertexCount(),
		indexCount: data.indexCount(),
		instanceCount: 1,
		instanceCapacity: 0,
		generation: generation,
	};
}

// A mesh whose buffers the caller made and keeps: `EXTERNAL_GENERATION` says so on the mesh
// itself, which is what keeps `uploadMesh` away from it — an empty MeshData would zero its
// handles. Defaulting the rest here is what keeps the next field added to GpuMesh from being
// silently zero at a hand-written literal (docs/VOID3D.md, Compiler notes).
export const EXTERNAL_GENERATION: int32 = -1;

export function external(
	this typeof GpuMesh,
	layout: VertexLayout,
	vertexBuffer: uint32,
	instanceBuffer: uint32,
	vertexCount: int32,
	instanceCount: int32,
): GpuMesh {
	return {
		layout: layout,
		vertexBuffer: vertexBuffer,
		instanceBuffer: instanceBuffer,
		indexBuffer: 0,
		vertexCount: vertexCount,
		indexCount: 0,
		instanceCount: instanceCount,
		instanceCapacity: 0,
		generation: EXTERNAL_GENERATION,
	};
}

export function isStale(this mesh: GpuMesh, generation: int32): boolean {
	return mesh.generation != EXTERNAL_GENERATION && mesh.generation != generation;
}

// The same mesh with nothing to draw and no generation, so a refused upload draws nothing and
// stays stale for the next rebuild rather than drawing wrong triangles.
function drawsNothing(this mesh: GpuMesh): GpuMesh {
	return {
		...mesh,
		vertexBuffer: 0,
		indexBuffer: 0,
		vertexCount: 0,
		indexCount: 0,
		generation: 0,
	};
}

// Makes the buffers for mesh `index` from its CPU data and points the GpuMesh at them. The
// old handles are dropped rather than destroyed: after a context loss they may already name an
// object of the new context (docs/VOID3D.md, Android lifecycle).
//
// A buffer the driver refuses comes back as handle 0. That must not reach `meshFor`: whether a
// GpuMesh is indexed is read off `indexBuffer`, so an indexed mesh whose index buffer was
// refused would silently become a non-indexed draw over an indexed vertex array — 194 wrong
// triangles instead of 292 right ones, with no diagnostic. The mesh is emptied instead.
// PENDING3D: upload-mesh-leaks-on-replace
export function uploadMesh(ref context: DrawContext, index: int32): Result<int32, MeshUploadError> {
	// sokol validates a buffer's size > 0 and panics rather than returning an invalid id, so an
	// empty mesh must never reach the driver.
	if (context.meshData[index].vertexCount() == 0) {
		context.meshes[index] = context.meshes[index].drawsNothing();
		return Result.err(MeshUploadError.EmptyMesh);
	}
	const vertexBuffer: uint32 = makeVertexBuffer(context.meshData[index].vertices);
	let indexBuffer: uint32 = 0;
	if (context.meshData[index].isIndexed()) {
		indexBuffer = makeIndexBuffer(context.meshData[index].indices);
	}
	if (vertexBuffer == 0) {
		if (indexBuffer != 0) { destroyBuffer(indexBuffer); }
		context.meshes[index] = context.meshes[index].drawsNothing();
		return Result.err(MeshUploadError.VertexBufferRefused);
	}
	if (context.meshData[index].isIndexed() && indexBuffer == 0) {
		destroyBuffer(vertexBuffer);
		context.meshes[index] = context.meshes[index].drawsNothing();
		return Result.err(MeshUploadError.IndexBufferRefused);
	}
	context.meshes[index] = context.meshData[index].meshFor(
		vertexBuffer,
		indexBuffer,
		contextGeneration(),
	);
	return Result.ok(index);
}

// Takes a copy of `data` — pushing a MeshData into the table copies its two Vec (CODE-STYLE
// §5) — uploads it, and returns the index both tables now share. The entry is kept even when
// the upload is refused: the CPU data is what a later rebuild works from.
export function addMeshData(
	ref context: DrawContext,
	data: MeshData,
): Result<int32, MeshUploadError> {
	const index: int32 = context.meshes.length as int32;
	context.meshData.push(data);
	context.meshes.push(data.meshFor(0, 0, 0));
	const uploaded: int32 = try uploadMesh(context, index);
	return Result.ok(uploaded);
}

// h3d.parts.Particles' quad: corners at ±0.5 around the instance root, two triangles.
const STREAM_CORNERS: Vec<float32> = [
	-0.5, -0.5, 0.5, -0.5, 0.5, 0.5,
	-0.5, -0.5, 0.5, 0.5, -0.5, 0.5,
];
const STREAM_CORNER_COUNT: int32 = 6;

export const STREAM_INSTANCE_STRIDE: int32 = 8;

export enum StreamError {
	MeshOutOfRange,
	NotAStream,
	OverCapacity,
	ShortInstances,
	BufferRefused,
}

export function isStream(this mesh: GpuMesh): boolean {
	return mesh.instanceCapacity > 0;
}

export function streamMesh(
	this typeof GpuMesh,
	capacity: int32,
	cornerBuffer: uint32,
	instanceBuffer: uint32,
	generation: int32,
): GpuMesh {
	return {
		layout: VertexLayout.Billboard,
		vertexBuffer: cornerBuffer,
		instanceBuffer: instanceBuffer,
		indexBuffer: 0,
		vertexCount: STREAM_CORNER_COUNT,
		indexCount: 0,
		instanceCount: 0,
		instanceCapacity: capacity,
		generation: generation,
	};
}

function remakeStream(ref context: DrawContext, index: int32): Result<int32, StreamError> {
	const capacity: int32 = context.meshes[index].instanceCapacity;
	const corners: uint32 = makeVertexBuffer(STREAM_CORNERS);
	const instances: uint32 = makeStreamBuffer(capacity * STREAM_INSTANCE_STRIDE);
	if (corners == 0 || instances == 0) {
		if (corners != 0) { destroyBuffer(corners); }
		if (instances != 0) { destroyBuffer(instances); }
		context.meshes[index] = GpuMesh.streamMesh(capacity, 0, 0, 0);
		return Result.err(StreamError.BufferRefused);
	}
	context.meshes[index] = GpuMesh.streamMesh(capacity, corners, instances, contextGeneration());
	return Result.ok(index);
}

export function addStreamMesh(
	ref context: DrawContext,
	capacity: int32,
): Result<int32, StreamError> {
	if (capacity <= 0) { return Result.err(StreamError.OverCapacity); }
	const index: int32 = addMesh(context, GpuMesh.streamMesh(capacity, 0, 0, 0));
	return remakeStream(context, index);
}

// A stream whose handles are from an older context is made again first: the write that follows
// a context loss is also its rebuild.
export function writeStream(
	ref context: DrawContext,
	index: int32,
	instances: Span<float32>,
	count: int32,
): Result<int32, StreamError> {
	if (index < 0 || index >= (context.meshes.length as int32)) {
		return Result.err(StreamError.MeshOutOfRange);
	}
	if (!context.meshes[index].isStream()) { return Result.err(StreamError.NotAStream); }
	if (count < 0 || count > context.meshes[index].instanceCapacity) {
		return Result.err(StreamError.OverCapacity);
	}
	const length: int32 = count * STREAM_INSTANCE_STRIDE;
	if ((instances.length as int32) < length) { return Result.err(StreamError.ShortInstances); }
	if (context.meshes[index].isStale(contextGeneration())) {
		const _remade: int32 = try remakeStream(context, index);
	}
	if (count > 0 && !updateBuffer(context.meshes[index].instanceBuffer, instances[0..length])) {
		context.meshes[index].instanceCount = 0;
		return Result.err(StreamError.BufferRefused);
	}
	context.meshes[index].instanceCount = count;
	return Result.ok(count);
}

// How many meshes would come back on their own after a context loss.
export function rebuildableMeshes(this context: DrawContext): int32 {
	let count: int32 = 0;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshData[i].vertexCount() > 0) { count = count + 1; }
	}
	return count;
}

// How many meshes hold handles from an older GPU context, and re-uploading them: one walk,
// because a counting loop and a working loop that must agree is a defect that only bites when
// they drift.
function sweepStaleMeshes(ref context: DrawContext, generation: int32, upload: boolean): int32 {
	let count: int32 = 0;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (!context.meshes[i].isStale(generation)) { continue; }
		if (!upload) {
			count = count + 1;
			continue;
		}
		if (context.meshes[i].isStream()) {
			if (remakeStream(context, i).ok) { count = count + 1; }
			continue;
		}
		if (uploadMesh(context, i).ok) { count = count + 1; }
	}
	return count;
}

export function staleMeshes(ref context: DrawContext, generation: int32): int32 {
	return sweepStaleMeshes(context, generation, false);
}

// Re-uploads every mesh whose handles are from an older GPU context, and answers how many came
// back. Called from the core's beginFrame on the frame that sees a new contextGeneration; a
// mesh uploaded on this generation already (addMeshData, the common case) is left alone. A
// mesh the driver refuses is left empty and stale, so it is retried on the next rebuild and is
// not counted here. Nothing on this path allocates: a MeshData parameter is passed by pointer,
// not copied, because the struct is over 24 bytes (CODE-STYLE §5, measured on 0.2.53).
export function rebuildMeshes(ref context: DrawContext): int32 {
	return sweepStaleMeshes(context, contextGeneration(), true);
}

export function addMaterial(ref context: DrawContext, material: Material): int32 {
	context.materials.push(material);
	return (context.materials.length as int32) - 1;
}

export function reserveUniforms(
	ref context: DrawContext,
	slot: int32,
	length: int32,
): Result<UniformBlock, UniformError> {
	const offset: int32 = context.uniformsUsed;
	if (offset + length > (context.uniforms.length as int32)) {
		return Result.err(UniformError.PoolFull);
	}
	context.uniformsUsed = offset + length;
	return Result.ok({ slot: slot, offset: offset, length: length });
}

export function writeUniforms(
	ref context: DrawContext,
	block: UniformBlock,
	values: Span<float32>,
): Result<int32, UniformError> {
	if ((values.length as int32) != block.length) { return Result.err(UniformError.WrongLength); }
	for (let i = 0; i < block.length; i++) {
		context.uniforms[block.offset + i] = values[i];
	}
	return Result.ok(block.length);
}

function applyBlock(this context: DrawContext, block: UniformBlock): void {
	applyUniforms(block.slot, context.uniforms[block.offset..block.offset + block.length]);
}

function bindItem(ref context: DrawContext, mesh: GpuMesh, material: Material): void {
	context.bindings[GPU3D_BINDING_VERTEX_BUFFER] = mesh.vertexBuffer;
	context.bindings[GPU3D_BINDING_VERTEX_BUFFER + 1] = mesh.instanceBuffer;
	context.bindings[GPU3D_BINDING_INDEX_BUFFER] = mesh.indexBuffer;
	context.bindings[GPU3D_BINDING_VIEW] = material.texture0;
	context.bindings[GPU3D_BINDING_VIEW + 1] = material.texture1;
	context.bindings[GPU3D_BINDING_VIEW + 2] = material.texture2;
	context.bindings[GPU3D_BINDING_VIEW + 3] = material.texture3;
	context.bindings[GPU3D_BINDING_SAMPLER] = material.sampler0;
	context.bindings[GPU3D_BINDING_SAMPLER + 1] = material.sampler1;
	applyBindings(context.bindings);
}

// One item into the current pass, whose attachments match `targets`, drawn with `program`:
// the material's own, or the one a renderer draws in its place (programMap.ms). `globals` are
// the pass-wide blocks (camera, lights) applied before the material's own.
export function drawItem(
	ref context: DrawContext,
	item: DrawItem,
	program: Program,
	targets: TargetLayout,
	globals: Span<UniformBlock>,
): void {
	const mesh: GpuMesh = context.meshes[item.mesh];
	const material: Material = context.materials[item.material];
	const pipeline: uint32 = pipelineFor(
		context.pipelines,
		program,
		mesh.layout,
		mesh.isIndexed(),
		material.pass,
		targets,
	);
	applyPipeline(pipeline);
	bindItem(context, mesh, material);
	if (context.pipelines.declaresBlock(program, MODEL_SLOT)) {
		item.world.writeTo(context.model[0..MODEL_LENGTH], 0);
		item.world.normalMatrix().writeTo(context.model[0..MODEL_LENGTH], 16);
		applyUniforms(MODEL_SLOT, context.model[0..MODEL_LENGTH]);
	}
	for (const block of globals) {
		if (context.pipelines.declaresBlock(program, block.slot)) {
			context.applyBlock(block);
		}
	}
	if (material.uniforms.length > 0) {
		context.applyBlock(material.uniforms);
	}
	draw(0, mesh.elementCount(), mesh.instanceCount);
}

// Draws `items` in order, each with its material's own program.
export function drawItems(
	ref context: DrawContext,
	items: Span<DrawItem>,
	targets: TargetLayout,
	globals: Span<UniformBlock>,
): void {
	for (const item of items) {
		drawItem(context, item, context.materials[item.material].program, targets, globals);
	}
}
