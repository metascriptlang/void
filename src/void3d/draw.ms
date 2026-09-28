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
	drawsQuads,
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
	frameIndex,
} from "./gpu3d";
import {
	GPU3D_BINDING_VERTEX_BUFFER,
	GPU3D_BINDING_INDEX_BUFFER,
	GPU3D_BINDING_VIEW,
	GPU3D_BINDING_SAMPLER,
	GPU3D_BINDING_LENGTH,
} from "./gpu3d.h";
import { Material, UniformBlock, NO_UNIFORMS } from "./material";
import { MeshData } from "./meshData";
import { PipelineCache, pipelineFor } from "./pipelineCache";
import { TargetLayout } from "./target";
import {
	UniformPool,
	UniformError,
	reserveRange,
	releaseRange,
	ownRange,
	disownRange,
	writeRange,
} from "./uniformPool";
import { Slots, claim, vacate } from "./slots";

// GPU side of a mesh: buffer handles plus what sg_draw needs. `instanceBuffer` holds particle
// and billboard instances, 0 when not instanced; a quad layout has no vertex buffer, its
// programs make the corners from the vertex index, and its instances feed vertex buffer slot 0
// (bindItem). `indexBuffer` is 0 for a mesh drawn straight from its vertex buffer, and then
// `indexCount` is unread; when it is set the draw is indexed and takes `indexCount` elements.
// The CPU data a lost context rebuilds this from is the MeshData at the same index of
// `DrawContext.meshData` (addMeshData).
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
	// sokol's frame of the last write into a stream's buffer, 0 before one (frameIndex).
	writtenFrame: uint32;
}

export function isIndexed(this mesh: GpuMesh): boolean {
	return mesh.indexBuffer != 0;
}

// What sg_draw counts: index elements when indexed, vertices otherwise.
export function elementCount(this mesh: GpuMesh): int32 {
	return mesh.isIndexed() ? mesh.indexCount : mesh.vertexCount;
}

// A mesh or a material of a DrawContext, named as M6 names a node (slots.ms). It names nothing
// once its last holder has released it.
export struct MeshId {
	index: int32;
	generation: int32;
}

export struct MaterialId {
	index: int32;
	generation: int32;
}

export struct DrawItem {
	mesh: MeshId;
	material: MaterialId;
	world: Mat4;
}

// Slot 4, matching `layout(binding=4) uniform modelParams` in shader3dBlocks.glsl, a slot no
// other block uses: a program gets the model matrix exactly when it declares that slot.
export const MODEL_SLOT: int32 = 4;
export const MODEL_LENGTH: int32 = 32;

// A buffer of a released mesh, destroyed by the next beginFrame if it is still of the GPU
// context it was made in.
export struct DoomedBuffer {
	buffer: uint32;
	generation: int32;
}

// `meshes` and `meshData` are one index space: meshData[i] is the CPU geometry mesh[i] was
// uploaded from, or an empty MeshData for a mesh whose data its owner keeps (the screen
// triangle, billboard instances). Everything with CPU data here comes back on its
// own after a context loss (rebuildMeshes); everything without is its owner's to rebuild.
// A slot's holders are Heaps' `Primitive.refCount`: the mesh or material goes when they reach 0.
// `…NodeHolds` counts the scene's mesh nodes among them, whose holds only the scene lets go.
export struct DrawContext {
	meshes: Vec<GpuMesh>;
	meshData: Vec<MeshData>;
	meshSlots: Slots;
	meshHolders: Vec<int32>;
	meshNodeHolds: Vec<int32>;
	materials: Vec<Material>;
	materialSlots: Slots;
	materialHolders: Vec<int32>;
	materialNodeHolds: Vec<int32>;
	uniforms: UniformPool;
	doomed: Vec<DoomedBuffer>;
	pipelines: PipelineCache;
	bindings: Vec<uint32>;
	model: Vec<float32>;
}

export enum MeshUploadError {
	EmptyMesh,
	VertexBufferRefused,
	IndexBufferRefused,
}

export enum HandleError {
	StaleMesh,
	StaleMaterial,
	HeldOnlyByNodes,
}

export enum MaterialError {
	ReleasedUniforms,
	SharedUniforms,
}

// The uniform pool is sized here, once; reserveUniforms only hands out ranges of it.
export function withUniformCapacity(this typeof DrawContext, capacity: int32): DrawContext {
	let bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH);
	for (let i = 0; i < GPU3D_BINDING_LENGTH; i++) {
		bindings[i] = 0;
	}
	let model: Vec<float32> = new Array(MODEL_LENGTH);
	for (let i = 0; i < MODEL_LENGTH; i++) {
		model[i] = 0.0;
	}
	return {
		meshes: [],
		meshData: [],
		meshSlots: Slots.empty(),
		meshHolders: [],
		meshNodeHolds: [],
		materials: [],
		materialSlots: Slots.empty(),
		materialHolders: [],
		materialNodeHolds: [],
		uniforms: UniformPool.withCapacity(capacity),
		doomed: [],
		pipelines: PipelineCache.empty(),
		bindings: bindings,
		model: model,
	};
}

export function hasMesh(this context: DrawContext, id: MeshId): boolean {
	return context.meshSlots.isCurrent(id.index, id.generation);
}

export function hasMaterial(this context: DrawContext, id: MaterialId): boolean {
	return context.materialSlots.isCurrent(id.index, id.generation);
}

export function liveMeshes(this context: DrawContext): int32 {
	return context.meshSlots.liveCount();
}

export function liveMaterials(this context: DrawContext): int32 {
	return context.materialSlots.liveCount();
}

// The caller holds the new mesh once.
function newMesh(ref context: DrawContext, mesh: GpuMesh, data: MeshData): MeshId {
	const index: int32 = claim(context.meshSlots);
	if (index == (context.meshes.length as int32)) {
		context.meshes.push(mesh);
		context.meshData.push(data);
		context.meshHolders.push(1);
		context.meshNodeHolds.push(0);
	} else {
		context.meshes[index] = mesh;
		context.meshData[index] = data;
		context.meshHolders[index] = 1;
		context.meshNodeHolds[index] = 0;
	}
	return { index: index, generation: context.meshSlots.generations[index] };
}

// A mesh with no CPU data here, so a lost context is its maker's to repair. Whose buffers they
// are is the mesh's generation: EXTERNAL_GENERATION (fullscreen, billboards) keeps them the
// caller's, never rebuilt and never destroyed here; any other makes them the context's, which
// dooms them when the mesh is freed.
export function addMesh(ref context: DrawContext, mesh: GpuMesh): MeshId {
	return newMesh(context, mesh, MeshData.empty());
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
		writtenFrame: 0,
	};
}

// A mesh whose buffers the caller made and keeps: `EXTERNAL_GENERATION` says so on the mesh
// itself, which is what keeps `uploadMesh` away from it — an empty MeshData would zero its
// handles. Defaulting the rest here is what keeps the next field added to GpuMesh from being
// silently zero at a hand-written literal (docs/VOID3D.md, Compiler notes).
export const EXTERNAL_GENERATION: int32 = -1;

// The vertices a quad layout draws per instance: QUAD_CORNERS in shader3dBlocks.glsl.
export const QUAD_VERTEX_COUNT: int32 = 6;

export function fullscreen(
	this typeof GpuMesh,
	vertexBuffer: uint32,
	vertexCount: int32,
): GpuMesh {
	return {
		layout: VertexLayout.Fullscreen,
		vertexBuffer: vertexBuffer,
		instanceBuffer: 0,
		indexBuffer: 0,
		vertexCount: vertexCount,
		indexCount: 0,
		instanceCount: 1,
		instanceCapacity: 0,
		generation: EXTERNAL_GENERATION,
		writtenFrame: 0,
	};
}

function quadMesh(
	layout: VertexLayout,
	instanceBuffer: uint32,
	instanceCount: int32,
	instanceCapacity: int32,
	generation: int32,
): GpuMesh {
	return {
		layout: layout,
		vertexBuffer: 0,
		instanceBuffer: instanceBuffer,
		indexBuffer: 0,
		vertexCount: QUAD_VERTEX_COUNT,
		indexCount: 0,
		instanceCount: instanceCount,
		instanceCapacity: instanceCapacity,
		generation: generation,
		writtenFrame: 0,
	};
}

export function billboards(
	this typeof GpuMesh,
	instanceBuffer: uint32,
	instanceCount: int32,
): GpuMesh {
	return quadMesh(VertexLayout.Billboard, instanceBuffer, instanceCount, 0, EXTERNAL_GENERATION);
}

export function isQuadShaped(this mesh: GpuMesh): boolean {
	return mesh.vertexBuffer == 0 && mesh.vertexCount == QUAD_VERTEX_COUNT &&
		(mesh.instanceBuffer != 0 || mesh.instanceCount == 0);
}

export function hasNothingToDraw(this mesh: GpuMesh): boolean {
	return mesh.elementCount() == 0 || mesh.instanceCount == 0;
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
// buffers it replaces are doomed (freeMesh), so a live mesh uploaded again leaks nothing and one
// whose context was lost drops them at the next beginFrame.
//
// A buffer the driver refuses comes back as handle 0. That must not reach `meshFor`: whether a
// GpuMesh is indexed is read off `indexBuffer`, so an indexed mesh whose index buffer was
// refused would silently become a non-indexed draw over an indexed vertex array — 194 wrong
// triangles instead of 292 right ones, with no diagnostic. The mesh is emptied instead.
function uploadMesh(ref context: DrawContext, index: int32): Result<int32, MeshUploadError> {
	doomBuffersOf(context, context.meshes[index]);
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

// Takes a copy of `data`, since storing a MeshData in the table copies its two Vec (CODE-STYLE
// §5), and uploads it. A refused upload frees the slot: the caller gets no id to release it with.
export function addMeshData(
	ref context: DrawContext,
	data: MeshData,
): Result<MeshId, MeshUploadError> {
	const id: MeshId = newMesh(context, data.meshFor(0, 0, 0), data);
	const uploaded: Result<int32, MeshUploadError> = uploadMesh(context, id.index);
	if (!uploaded.ok) {
		freeMesh(context, id.index);
		return Result.err(uploaded.error);
	}
	return Result.ok(id);
}

export const STREAM_INSTANCE_STRIDE: int32 = 8;

export enum StreamError {
	StaleMesh,
	NotAStream,
	OverCapacity,
	ShortInstances,
	BufferRefused,
	WrittenThisFrame,
}

export function isStream(this mesh: GpuMesh): boolean {
	return mesh.instanceCapacity > 0;
}

export function streamMesh(
	this typeof GpuMesh,
	capacity: int32,
	instanceBuffer: uint32,
	generation: int32,
): GpuMesh {
	return quadMesh(VertexLayout.Particle, instanceBuffer, 0, capacity, generation);
}

function remakeStream(ref context: DrawContext, index: int32): Result<int32, StreamError> {
	const capacity: int32 = context.meshes[index].instanceCapacity;
	const instances: uint32 = makeStreamBuffer(capacity * STREAM_INSTANCE_STRIDE);
	if (instances == 0) {
		context.meshes[index] = GpuMesh.streamMesh(capacity, 0, 0);
		return Result.err(StreamError.BufferRefused);
	}
	context.meshes[index] = GpuMesh.streamMesh(capacity, instances, contextGeneration());
	return Result.ok(index);
}

// A refused buffer frees the slot, as a refused addMeshData does.
export function addStreamMesh(
	ref context: DrawContext,
	capacity: int32,
): Result<MeshId, StreamError> {
	if (capacity <= 0) { return Result.err(StreamError.OverCapacity); }
	const id: MeshId = addMesh(context, GpuMesh.streamMesh(capacity, 0, 0));
	const made: Result<int32, StreamError> = remakeStream(context, id.index);
	if (!made.ok) {
		freeMesh(context, id.index);
		return Result.err(made.error);
	}
	return Result.ok(id);
}

// A stream whose handles are from an older context is made again first: the write that follows
// a context loss is also its rebuild. sokol takes one update per buffer per frame and panics on a
// second in a debug build, so a second write in one frame is refused here instead.
export function writeStream(
	ref context: DrawContext,
	id: MeshId,
	instances: Span<float32>,
	count: int32,
): Result<int32, StreamError> {
	if (!context.hasMesh(id)) { return Result.err(StreamError.StaleMesh); }
	const index: int32 = id.index;
	if (!context.meshes[index].isStream()) { return Result.err(StreamError.NotAStream); }
	if (count < 0 || count > context.meshes[index].instanceCapacity) {
		return Result.err(StreamError.OverCapacity);
	}
	const length: int32 = count * STREAM_INSTANCE_STRIDE;
	if ((instances.length as int32) < length) { return Result.err(StreamError.ShortInstances); }
	if (context.meshes[index].isStale(contextGeneration())) {
		const _remade: int32 = try remakeStream(context, index);
	}
	if (count == 0) {
		context.meshes[index].instanceCount = 0;
		return Result.ok(0);
	}
	const frame: uint32 = frameIndex();
	if (context.meshes[index].writtenFrame == frame) {
		return Result.err(StreamError.WrittenThisFrame);
	}
	if (!updateBuffer(context.meshes[index].instanceBuffer, instances[0..length])) {
		context.meshes[index].instanceCount = 0;
		return Result.err(StreamError.BufferRefused);
	}
	context.meshes[index].instanceCount = count;
	context.meshes[index].writtenFrame = frame;
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
		if (context.meshHolders[i] == 0 || !context.meshes[i].isStale(generation)) { continue; }
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

const VACANT_MESH: GpuMesh = {
	layout: VertexLayout.Lit,
	vertexBuffer: 0,
	instanceBuffer: 0,
	indexBuffer: 0,
	vertexCount: 0,
	indexCount: 0,
	instanceCount: 0,
	instanceCapacity: 0,
	generation: 0,
	writtenFrame: 0,
};

function doom(ref context: DrawContext, buffer: uint32, generation: int32): void {
	if (buffer != 0) { context.doomed.push({ buffer: buffer, generation: generation }); }
}

// The buffers go to the next beginFrame, so a pass list of this frame that still names the
// mesh never reaches a destroyed buffer; a caller's buffers (EXTERNAL_GENERATION) are not ours.
function doomBuffersOf(ref context: DrawContext, mesh: GpuMesh): void {
	if (mesh.generation == EXTERNAL_GENERATION || mesh.generation == 0) { return; }
	doom(context, mesh.vertexBuffer, mesh.generation);
	doom(context, mesh.indexBuffer, mesh.generation);
	doom(context, mesh.instanceBuffer, mesh.generation);
}

function freeMesh(ref context: DrawContext, index: int32): void {
	doomBuffersOf(context, context.meshes[index]);
	context.meshes[index] = VACANT_MESH;
	context.meshData[index] = MeshData.empty();
	context.meshHolders[index] = 0;
	vacate(context.meshSlots, index);
}

// Another holder of `id`, as Heaps' `Primitive.incref`; answers how many hold it now.
export function retainMesh(ref context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (!context.hasMesh(id)) { return Result.err(HandleError.StaleMesh); }
	context.meshHolders[id.index] = context.meshHolders[id.index] + 1;
	return Result.ok(context.meshHolders[id.index]);
}

function letGoOfMesh(ref context: DrawContext, index: int32): int32 {
	const left: int32 = context.meshHolders[index] - 1;
	if (left > 0) {
		context.meshHolders[index] = left;
		return left;
	}
	freeMesh(context, index);
	return 0;
}

// One holder lets go, as `Primitive.decref`; at none the mesh is freed and `id` goes stale.
// Answers how many still hold it. A caller whose release would take a mesh node's hold has
// released it once too often, and is refused.
export function releaseMesh(ref context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (!context.hasMesh(id)) { return Result.err(HandleError.StaleMesh); }
	if (context.meshHolders[id.index] == context.meshNodeHolds[id.index]) {
		return Result.err(HandleError.HeldOnlyByNodes);
	}
	return Result.ok(letGoOfMesh(context, id.index));
}

// A mesh node holds `id` (scene.ms addMeshNode, setMeshOf).
export function nodeHoldsMesh(ref context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (!context.hasMesh(id)) { return Result.err(HandleError.StaleMesh); }
	context.meshNodeHolds[id.index] = context.meshNodeHolds[id.index] + 1;
	context.meshHolders[id.index] = context.meshHolders[id.index] + 1;
	return Result.ok(context.meshHolders[id.index]);
}

export function nodeLetsGoOfMesh(
	ref context: DrawContext,
	id: MeshId,
): Result<int32, HandleError> {
	if (!context.hasMesh(id)) { return Result.err(HandleError.StaleMesh); }
	if (context.meshNodeHolds[id.index] == 0) { return Result.err(HandleError.StaleMesh); }
	context.meshNodeHolds[id.index] = context.meshNodeHolds[id.index] - 1;
	return Result.ok(letGoOfMesh(context, id.index));
}

// The material takes its uniform range with it: the range returns to the pool when the material
// is freed, so one range under two materials is refused.
export function addMaterial(
	ref context: DrawContext,
	material: Material,
): Result<MaterialId, MaterialError> {
	const owned: Result<int32, UniformError> = ownRange(context.uniforms, material.uniforms);
	if (!owned.ok) {
		const shared: boolean = owned.error == UniformError.Owned;
		return Result.err(shared ? MaterialError.SharedUniforms : MaterialError.ReleasedUniforms);
	}
	const index: int32 = claim(context.materialSlots);
	if (index == (context.materials.length as int32)) {
		context.materials.push(material);
		context.materialHolders.push(1);
		context.materialNodeHolds.push(0);
	} else {
		context.materials[index] = material;
		context.materialHolders[index] = 1;
		context.materialNodeHolds[index] = 0;
	}
	return Result.ok({ index: index, generation: context.materialSlots.generations[index] });
}

export function retainMaterial(
	ref context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (!context.hasMaterial(id)) { return Result.err(HandleError.StaleMaterial); }
	context.materialHolders[id.index] = context.materialHolders[id.index] + 1;
	return Result.ok(context.materialHolders[id.index]);
}

function letGoOfMaterial(ref context: DrawContext, index: int32): int32 {
	const left: int32 = context.materialHolders[index] - 1;
	if (left > 0) {
		context.materialHolders[index] = left;
		return left;
	}
	const owned: UniformBlock = context.materials[index].uniforms;
	const disowned: Result<int32, UniformError> = disownRange(context.uniforms, owned);
	if (!disowned.ok) { unreachable; }
	context.materials[index].uniforms = NO_UNIFORMS;
	context.materialHolders[index] = 0;
	vacate(context.materialSlots, index);
	return 0;
}

export function releaseMaterial(
	ref context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (!context.hasMaterial(id)) { return Result.err(HandleError.StaleMaterial); }
	if (context.materialHolders[id.index] == context.materialNodeHolds[id.index]) {
		return Result.err(HandleError.HeldOnlyByNodes);
	}
	return Result.ok(letGoOfMaterial(context, id.index));
}

export function nodeHoldsMaterial(
	ref context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (!context.hasMaterial(id)) { return Result.err(HandleError.StaleMaterial); }
	context.materialNodeHolds[id.index] = context.materialNodeHolds[id.index] + 1;
	context.materialHolders[id.index] = context.materialHolders[id.index] + 1;
	return Result.ok(context.materialHolders[id.index]);
}

export function nodeLetsGoOfMaterial(
	ref context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (!context.hasMaterial(id)) { return Result.err(HandleError.StaleMaterial); }
	if (context.materialNodeHolds[id.index] == 0) { return Result.err(HandleError.StaleMaterial); }
	context.materialNodeHolds[id.index] = context.materialNodeHolds[id.index] - 1;
	return Result.ok(letGoOfMaterial(context, id.index));
}

// How many doomed buffers the next beginFrame on `generation` destroys; the rest are dropped.
export function doomedFor(this context: DrawContext, generation: int32): int32 {
	let count: int32 = 0;
	for (const doomed of context.doomed) {
		if (doomed.generation == generation) { count = count + 1; }
	}
	return count;
}

// A buffer of an older GPU context died with it, and its handle may name an object of the new
// one (docs/VOID3D.md, Android lifecycle): it is dropped, never destroyed.
export function buryDoomed(ref context: DrawContext, generation: int32): int32 {
	let destroyed: int32 = 0;
	for (const doomed of context.doomed) {
		if (doomed.generation != generation) { continue; }
		destroyBuffer(doomed.buffer);
		destroyed = destroyed + 1;
	}
	while ((context.doomed.length as int32) > 0) { context.doomed.pop(); }
	return destroyed;
}

export function reserveUniforms(
	ref context: DrawContext,
	slot: int32,
	length: int32,
): Result<UniformBlock, UniformError> {
	return reserveRange(context.uniforms, slot, length);
}

// Once released, `block` is refused wherever it is written, and its range goes to the next
// reserve of the same length. A material's range goes with the material, never before it
// (UniformError.Owned).
export function releaseUniforms(
	ref context: DrawContext,
	block: UniformBlock,
): Result<int32, UniformError> {
	return releaseRange(context.uniforms, block);
}

export function writeUniforms(
	ref context: DrawContext,
	block: UniformBlock,
	values: Span<float32>,
): Result<int32, UniformError> {
	return writeRange(context.uniforms, block, values);
}

function applyBlock(this context: DrawContext, block: UniformBlock): void {
	applyUniforms(block.slot, context.uniforms.values[block.offset..block.offset + block.length]);
}

function bindItem(ref context: DrawContext, mesh: GpuMesh, material: Material): void {
	context.bindings[GPU3D_BINDING_VERTEX_BUFFER] =
		drawsQuads(mesh.layout) ? mesh.instanceBuffer : mesh.vertexBuffer;
	context.bindings[GPU3D_BINDING_VERTEX_BUFFER + 1] = 0;
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
	// beginFrame refused every stale item and the presets their own screen meshes and materials,
	// so only a release in the middle of a frame reaches here, which nothing may do.
	if (!context.hasMesh(item.mesh) || !context.hasMaterial(item.material)) { unreachable; }
	const mesh: GpuMesh = context.meshes[item.mesh.index];
	if (mesh.hasNothingToDraw()) { return; }
	const material: Material = context.materials[item.material.index];
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
		drawItem(context, item, context.materials[item.material.index].program, targets, globals);
	}
}
