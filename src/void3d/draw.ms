// Draw items and the tables they index. The renderer consumes a flat Span<DrawItem>, not the
// scene tree (docs/VOID3D.md, Porting rules): a scene flattens into items when its structure
// changes, and every frame only rewrites their world matrices.
//
// DrawContext owns everything items point into: GPU meshes, materials, textures, the uniform pool
// and the pipeline cache. Items and materials are plain values holding indices and handles.

import { Mat4, normalMatrix, writeTo } from "../math/math3d";
import {
	VertexLayout,
	Program,
	drawsQuads,
	doorProgram,
	applyPipeline,
	applyBindings,
	applyUniforms,
	draw,
	makeVertexBuffer,
	makeIndexBuffer,
	makeStreamBuffer,
	updateBuffer,
	destroyBuffer,
	destroyImage,
	textureSlotMask,
	samplerSlotMask,
	uniformBlockLength,
	ProgramKey,
	Preset,
	declares,
	MATERIAL_ALPHA_KILL,
	SHADOW_VIEW_SLOT,
	SHADOW_SAMPLER_SLOT,
	NORMAL_VIEW_SLOT,
} from "./gpu3d";
import {
	PassState,
	contextGeneration,
	frameIndex,
	makeSampler,
	destroyView,
	destroySampler,
	passState,
} from "../gpu/door";
import { FilterMode, Wrap, BlendMode, RenderState } from "../gpu/state";
import { Texture, TextureError, DetachedHandles } from "../gpu/texture";
import {
	TextureData,
	TextureId,
	TextureUploadError,
	TextureAlpha,
	NO_TEXTURE,
} from "./texture";

export struct GpuTexture {
	texture: Texture | null;
	sampler: uint32;
	samplerGeneration: int32;
}

export struct DoomedTexture {
	image: uint32;
	view: uint32;
	generation: int32;
}
import {
	GPU3D_BINDING_VERTEX_BUFFER,
	GPU3D_BINDING_INDEX_BUFFER,
	GPU3D_BINDING_VIEW,
	GPU3D_BINDING_SAMPLER,
	GPU3D_BINDING_LENGTH,
} from "./gpu3d.h";
import {
	Material,
	UniformBlock,
	NO_UNIFORMS,
	MATERIAL_TEXTURE_ROLES,
	viewSlotOf,
	samplerSlotOf,
	colorRole,
} from "./material";
import { MeshData } from "./meshData";
import { PipelineCache, closePipelines } from "../gpu/pipeline";
import { pipelineFor } from "./gpu3d";
import { TargetLayout, RenderTarget } from "../gpu/target";
import {
	UniformPool,
	UniformError,
	reserveRange,
	releaseRange,
	ownRange,
	closeUniformPool,
	disownRange,
	writeRange,
} from "./uniformPool";
import { Slots, LAST_GENERATION, claim, vacate } from "./slots";

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
	store: int32;
	index: int32;
	generation: int32;
}

export struct MaterialId {
	store: int32;
	index: int32;
	generation: int32;
}

export const NO_MESH: MeshId = { store: 0, index: -1, generation: 0 };
export const NO_MATERIAL: MaterialId = { store: 0, index: -1, generation: 0 };

export struct DrawItem {
	mesh: MeshId;
	material: MaterialId;
	world: Mat4;
	order: int32;
}

// Slot 4, matching `layout(binding=4) uniform modelParams` in shader3dBlocks.glsl, a slot no
// other block uses: a program gets the model matrix exactly when it declares that slot.
export const MODEL_SLOT: int32 = 4;
export const MODEL_LENGTH: int32 = 32;

export struct DoomedBuffer {
	buffer: uint32;
	generation: int32;
}

// `meshes` and `meshData` are one index space: meshData[i] is the CPU geometry mesh[i] was
// uploaded from, or an empty MeshData for a mesh whose data its owner keeps (the screen
// triangle, billboard instances). Everything with CPU data here comes back on its
// own after a context loss (rebuildMeshes); everything without is its owner's to rebuild.
// A slot's holders are Heaps' `Primitive.refCount`: the mesh or material goes when they reach 0.
// `…Pins` counts the holds among them that only their holder lets go: a mesh node's, a baked
// animation's, a material's hold on its textures. `materialBlocks` and `materialTextures` are the
// range and the textures each material was added with, whatever its fields say later; the
// textures MATERIAL_TEXTURE_ROLES to a material, by role. `textures`
// and `textureData` are one index space, as `meshes` and `meshData` are.
// PENDING3D: store-serial-writable
export interface DrawContext {
	serial: int32;
	meshes: Vec<GpuMesh>;
	meshData: Vec<MeshData>;
	meshSlots: Slots;
	meshHolders: Vec<int32>;
	meshPins: Vec<int32>;
	meshTally: Vec<int32>;
	materials: Vec<Material>;
	materialSlots: Slots;
	materialHolders: Vec<int32>;
	materialPins: Vec<int32>;
	materialTally: Vec<int32>;
	materialBlocks: Vec<UniformBlock>;
	materialTextures: Vec<TextureId>;
	textures: Vec<GpuTexture>;
	textureData: Vec<TextureData>;
	textureSlots: Slots;
	textureHolders: Vec<int32>;
	texturePins: Vec<int32>;
	textureTargets: Vec<RenderTarget | null>;
	textureAlphas: Vec<TextureAlpha>;
	doomedTextures: Vec<DoomedTexture>;
	samplers: Vec<uint32>;
	samplerGeneration: int32;
	uniforms: UniformPool;
	doomed: Vec<DoomedBuffer>;
	pipelines: PipelineCache;
	bindings: Vec<uint32>;
	model: Vec<float32>;
	closed: boolean;
}

export enum MeshUploadError {
	EmptyMesh,
	VertexBufferRefused,
	IndexBufferRefused,
	Unrebuildable,
}

export enum HandleError {
	StaleMesh,
	StaleMaterial,
	OnlyPinned,
	NotPinned,
	StaleTexture,
	ForeignMesh,
	ForeignMaterial,
	ForeignTexture,
}

export enum MaterialError {
	ReleasedUniforms,
	SharedUniforms,
	StaleTexture,
	TextureNamedTwice,
	TextureNotSampled,
	ForeignTexture,
	ForeignUniforms,
	PremultipliedTexture,
	StraightTexture,
	StraightBlend,
	NoAlphaKill,
	UndeclaredProgram,
}

let contextSerials: int32 = 0;

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
	let samplers: Vec<uint32> = new Array(SAMPLER_SETTINGS);
	for (let i = 0; i < SAMPLER_SETTINGS; i++) {
		samplers[i] = 0;
	}
	if (contextSerials == LAST_GENERATION) {
		console.log("void3d: DrawContext.withUniformCapacity has no serial left for a new context");
		unreachable;
	}
	contextSerials = contextSerials + 1;
	return {
		serial: contextSerials,
		meshes: [],
		meshData: [],
		meshSlots: Slots.empty(),
		meshHolders: [],
		meshPins: [],
		meshTally: [],
		materials: [],
		materialSlots: Slots.empty(),
		materialHolders: [],
		materialPins: [],
		materialTally: [],
		materialBlocks: [],
		materialTextures: [],
		textures: [],
		textureData: [],
		textureSlots: Slots.empty(),
		textureHolders: [],
		texturePins: [],
		textureTargets: [],
		textureAlphas: [],
		doomedTextures: [],
		samplers: samplers,
		samplerGeneration: 0,
		uniforms: UniformPool.withCapacity(capacity),
		doomed: [],
		pipelines: PipelineCache.empty(),
		bindings: bindings,
		model: model,
		closed: false,
	};
}

export function issuedMesh(this context: DrawContext, id: MeshId): boolean {
	return id.store == context.serial;
}

export function issuedMaterial(this context: DrawContext, id: MaterialId): boolean {
	return id.store == context.serial;
}

export function issuedTexture(this context: DrawContext, id: TextureId): boolean {
	return id.store == context.serial;
}

export function hasMesh(this context: DrawContext, id: MeshId): boolean {
	if (context.closed || !context.issuedMesh(id)) { return false; }
	return context.meshSlots.isCurrent(id.index, id.generation);
}

export function hasMaterial(this context: DrawContext, id: MaterialId): boolean {
	if (context.closed || !context.issuedMaterial(id)) { return false; }
	return context.materialSlots.isCurrent(id.index, id.generation);
}

function meshRefusal(this context: DrawContext, id: MeshId): HandleError {
	return context.issuedMesh(id) ? HandleError.StaleMesh : HandleError.ForeignMesh;
}

function materialRefusal(this context: DrawContext, id: MaterialId): HandleError {
	return context.issuedMaterial(id) ? HandleError.StaleMaterial : HandleError.ForeignMaterial;
}

function textureRefusal(this context: DrawContext, id: TextureId): HandleError {
	return context.issuedTexture(id) ? HandleError.StaleTexture : HandleError.ForeignTexture;
}

export function liveMeshes(this context: DrawContext): int32 {
	return context.meshSlots.liveCount();
}

export function liveMaterials(this context: DrawContext): int32 {
	return context.materialSlots.liveCount();
}

// The caller holds the new mesh once.
function newMesh(context: DrawContext, mesh: GpuMesh, data: MeshData): MeshId {
	const index: int32 = claim(context.meshSlots);
	if (index == (context.meshes.length as int32)) {
		context.meshes.push(mesh);
		context.meshData.push(data);
		context.meshHolders.push(1);
		context.meshPins.push(0);
		context.meshTally.push(0);
	} else {
		context.meshes[index] = mesh;
		context.meshData[index] = data;
		context.meshHolders[index] = 1;
		context.meshPins[index] = 0;
		context.meshTally[index] = 0;
	}
	return {
		store: context.serial,
		index: index,
		generation: context.meshSlots.generations[index],
	};
}

// A mesh with no CPU data here. Whose buffers they are is the mesh's generation:
// EXTERNAL_GENERATION (fullscreen, billboards) keeps them the caller's, never rebuilt and never
// destroyed here; any other makes them the context's, which dooms them when the mesh is freed and
// remakes them after a context loss. Only a stream can be remade from nothing, so any other mesh
// that is not the caller's is refused, and so is one that names buffers made in no context.
export function addMesh(context: DrawContext, mesh: GpuMesh): Result<MeshId, MeshUploadError> {
	if (context.closed) { stopOnClosedContext("addMesh"); }
	if (mesh.generation != EXTERNAL_GENERATION && !mesh.isStream()) {
		return Result.err(MeshUploadError.Unrebuildable);
	}
	const buffers: boolean =
		mesh.vertexBuffer != 0 || mesh.indexBuffer != 0 || mesh.instanceBuffer != 0;
	if (mesh.generation == 0 && buffers) { return Result.err(MeshUploadError.Unrebuildable); }
	return Result.ok(newMesh(context, mesh, MeshData.empty()));
}

function layoutOf(this data: MeshData): VertexLayout {
	if (data.hasTangents) { return VertexLayout.LitTexturedTangent; }
	return data.hasUvs ? VertexLayout.LitTextured : VertexLayout.Lit;
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
		layout: data.layoutOf(),
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
// buffers it replaces are doomed (doomBuffersOf), so a live mesh uploaded again leaks nothing and
// one whose context was lost drops them at the next beginFrame.
//
// A buffer the driver refuses comes back as handle 0. That must not reach `meshFor`: whether a
// GpuMesh is indexed is read off `indexBuffer`, so an indexed mesh whose index buffer was
// refused would silently become a non-indexed draw over an indexed vertex array — 194 wrong
// triangles instead of 292 right ones, with no diagnostic. The mesh is emptied instead.
function uploadMesh(context: DrawContext, index: int32): Result<int32, MeshUploadError> {
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
	context: DrawContext,
	data: MeshData,
): Result<MeshId, MeshUploadError> {
	if (context.closed) { stopOnClosedContext("addMeshData"); }
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
	ForeignMesh,
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

function remakeStream(context: DrawContext, index: int32): Result<int32, StreamError> {
	doomBuffersOf(context, context.meshes[index]);
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
	context: DrawContext,
	capacity: int32,
): Result<MeshId, StreamError> {
	if (context.closed) { stopOnClosedContext("addStreamMesh"); }
	if (capacity <= 0) { return Result.err(StreamError.OverCapacity); }
	const id: MeshId = newMesh(context, GpuMesh.streamMesh(capacity, 0, 0), MeshData.empty());
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
	context: DrawContext,
	id: MeshId,
	instances: Readonly<Span<float32>>,
	count: int32,
): Result<int32, StreamError> {
	if (context.closed) { stopOnClosedContext("writeStream"); }
	if (!context.hasMesh(id)) {
		return Result.err(context.issuedMesh(id) ? StreamError.StaleMesh : StreamError.ForeignMesh);
	}
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
function sweepStaleMeshes(context: DrawContext, generation: int32, upload: boolean): int32 {
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

export function staleMeshes(context: DrawContext, generation: int32): int32 {
	return sweepStaleMeshes(context, generation, false);
}

// Re-uploads every mesh whose handles are from an older GPU context, and answers how many came
// back. Called from the core's beginFrame on the frame that sees a new contextGeneration; a
// mesh uploaded on this generation already (addMeshData, the common case) is left alone. A
// mesh the driver refuses is left empty and stale, so it is retried on the next rebuild and is
// not counted here. Nothing on this path allocates: a MeshData parameter is passed by pointer,
// not copied, because the struct is over 24 bytes (CODE-STYLE §5, measured on 0.2.53).
export function rebuildMeshes(context: DrawContext): int32 {
	if (context.closed) { stopOnClosedContext("rebuildMeshes"); }
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

function doom(context: DrawContext, buffer: uint32, generation: int32): void {
	if (buffer != 0) { context.doomed.push({ buffer: buffer, generation: generation }); }
}

// A caller's buffers (EXTERNAL_GENERATION) are not ours to destroy.
function doomBuffersOf(context: DrawContext, mesh: GpuMesh): void {
	if (mesh.generation == EXTERNAL_GENERATION || mesh.generation == 0) { return; }
	doom(context, mesh.vertexBuffer, mesh.generation);
	doom(context, mesh.indexBuffer, mesh.generation);
	doom(context, mesh.instanceBuffer, mesh.generation);
}

function freeMesh(context: DrawContext, index: int32): void {
	doomBuffersOf(context, context.meshes[index]);
	context.meshes[index] = VACANT_MESH;
	context.meshData[index] = MeshData.empty();
	context.meshHolders[index] = 0;
	vacate(context.meshSlots, index);
}

// Another holder of `id`, as Heaps' `Primitive.incref`; answers how many hold it now.
export function retainMesh(context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("retainMesh"); }
	if (!context.hasMesh(id)) { return Result.err(context.meshRefusal(id)); }
	context.meshHolders[id.index] = context.meshHolders[id.index] + 1;
	return Result.ok(context.meshHolders[id.index]);
}

function letGoOfMesh(context: DrawContext, index: int32): int32 {
	const left: int32 = context.meshHolders[index] - 1;
	if (left > 0) {
		context.meshHolders[index] = left;
		return left;
	}
	freeMesh(context, index);
	return 0;
}

// One holder lets go, as `Primitive.decref`; at none the mesh is freed and `id` goes stale.
// Answers how many still hold it. A release that would take a pin is a caller releasing once
// too often, and is refused.
export function releaseMesh(context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("releaseMesh"); }
	if (!context.hasMesh(id)) { return Result.err(context.meshRefusal(id)); }
	if (context.meshHolders[id.index] == context.meshPins[id.index]) {
		return Result.err(HandleError.OnlyPinned);
	}
	return Result.ok(letGoOfMesh(context, id.index));
}

// A hold only its holder lets go (a mesh node's, a baked animation's), with unpinMesh.
export function pinMesh(context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("pinMesh"); }
	if (!context.hasMesh(id)) { return Result.err(context.meshRefusal(id)); }
	context.meshPins[id.index] = context.meshPins[id.index] + 1;
	context.meshHolders[id.index] = context.meshHolders[id.index] + 1;
	return Result.ok(context.meshHolders[id.index]);
}

export function unpinMesh(context: DrawContext, id: MeshId): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("unpinMesh"); }
	if (!context.hasMesh(id)) { return Result.err(context.meshRefusal(id)); }
	if (context.meshPins[id.index] == 0) { return Result.err(HandleError.NotPinned); }
	context.meshPins[id.index] = context.meshPins[id.index] - 1;
	return Result.ok(letGoOfMesh(context, id.index));
}

export function meshPinned(this context: DrawContext, id: MeshId): int32 {
	return context.hasMesh(id) ? context.meshPins[id.index] : 0;
}

// Counts one more holder about to unpin `id`, and answers whether its pins still cover every one
// counted since the last clearMeshTally. A freed id counts nothing: whoever pinned it let go.
// Linear where a pairwise count would be quadratic in the holders checked.
export function tallyMeshPin(context: DrawContext, id: MeshId): boolean {
	if (context.closed) { stopOnClosedContext("tallyMeshPin"); }
	if (!context.issuedMesh(id)) {
		console.log("void3d: tallyMeshPin through a context that did not issue the mesh");
		unreachable;
	}
	if (!context.hasMesh(id)) { return true; }
	context.meshTally[id.index] = context.meshTally[id.index] + 1;
	return context.meshTally[id.index] <= context.meshPins[id.index];
}

export function clearMeshTally(context: DrawContext, id: MeshId): void {
	if (context.closed) { stopOnClosedContext("clearMeshTally"); }
	if (context.hasMesh(id)) { context.meshTally[id.index] = 0; }
}

function stopOnOwnError(error: UniformError): MaterialError {
	console.log(`void3d: addMaterial got ${error.toString()} from the uniform pool`);
	unreachable;
}

function uniformsError(error: UniformError): MaterialError {
	return match (error) {
		UniformError.Owned => MaterialError.SharedUniforms,
		UniformError.Foreign => MaterialError.ForeignUniforms,
		UniformError.Released => MaterialError.ReleasedUniforms,
		UniformError.PoolFull | UniformError.WrongLength => stopOnOwnError(error),
	};
}

// A block ownRange refuses is ownRange's to name.
function cutsAbove(this context: DrawContext, block: UniformBlock): boolean {
	if (block.length <= MATERIAL_ALPHA_KILL) { return false; }
	if (!context.uniforms.holds(block)) { return true; }
	return context.uniforms.values[block.offset + MATERIAL_ALPHA_KILL] > 0.0;
}

const PREMULTIPLIED_OVER: RenderState = RenderState.defaults().withBlendMode(BlendMode.AlphaAdd);

function blendsPremultiplied(pass: RenderState): boolean {
	return pass.blendSource == PREMULTIPLIED_OVER.blendSource
		&& pass.blendDestination == PREMULTIPLIED_OVER.blendDestination
		&& pass.blendAlphaSource == PREMULTIPLIED_OVER.blendAlphaSource
		&& pass.blendAlphaDestination == PREMULTIPLIED_OVER.blendAlphaDestination
		&& pass.blendOperation == PREMULTIPLIED_OVER.blendOperation
		&& pass.blendAlphaOperation == PREMULTIPLIED_OVER.blendAlphaOperation;
}

export function slotBit(slot: int32): uint32 {
	return (1 as uint32) << (slot as uint32);
}

// A context texture the material names in `role`: not also a raw view or sampler at its slots,
// sampled there by the program, live in this context, and, for a colour role, of the program's
// alpha.
function textureFits(
	context: DrawContext,
	material: Material,
	role: int32,
): Result<int32, MaterialError> {
	const texture: TextureId = material.textureOf(role);
	const view: int32 = viewSlotOf(role);
	const sampler: int32 = samplerSlotOf(role);
	if (material.rawView(view) != 0 || (sampler >= 0 && material.rawSampler(sampler) != 0)) {
		return Result.err(MaterialError.TextureNamedTwice);
	}
	const read: int32 = sampler >= 0 ? sampler : 0;
	if ((textureSlotMask(material.program) & slotBit(view)) == 0 ||
		(samplerSlotMask(material.program) & slotBit(read)) == 0) {
		return Result.err(MaterialError.TextureNotSampled);
	}
	if (!context.hasTexture(texture)) {
		const issued: boolean = context.issuedTexture(texture);
		return Result.err(issued ? MaterialError.StaleTexture : MaterialError.ForeignTexture);
	}
	const premultiplied: boolean =
		context.textureAlphas[texture.index] == TextureAlpha.Premultiplied;
	if (colorRole(role) && premultiplied != material.program.premultiplied) {
		return Result.err(
			premultiplied ? MaterialError.PremultipliedTexture : MaterialError.StraightTexture,
		);
	}
	return Result.ok(role);
}

// The material takes its uniform range with it: the range returns to the pool when the material
// is freed, so one range under two materials is refused. It pins its textures until it is
// freed, as a Bevy material holds its images' strong handles.
export function addMaterial(
	context: DrawContext,
	material: Material,
): Result<MaterialId, MaterialError> {
	if (context.closed) { stopOnClosedContext("addMaterial"); }
	if (!declares(material.program)) { return Result.err(MaterialError.UndeclaredProgram); }
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		if (!material.textureOf(role).isTexture()) { continue; }
		const fits: Result<int32, MaterialError> = textureFits(context, material, role);
		if (!fits.ok) { return Result.err(fits.error); }
	}
	if (material.program.premultiplied && !blendsPremultiplied(material.pass)) {
		return Result.err(MaterialError.StraightBlend);
	}
	const fixedCut: boolean = material.program.program == Program.Billboard;
	if (material.program.cutout && !fixedCut && !context.cutsAbove(material.uniforms)) {
		return Result.err(MaterialError.NoAlphaKill);
	}
	const owned: Result<int32, UniformError> = ownRange(context.uniforms, material.uniforms);
	if (!owned.ok) {
		return Result.err(uniformsError(owned.error));
	}
	const index: int32 = claim(context.materialSlots);
	if (index == (context.materials.length as int32)) {
		context.materials.push(material);
		context.materialHolders.push(1);
		context.materialPins.push(0);
		context.materialTally.push(0);
		context.materialBlocks.push(material.uniforms);
		for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
			context.materialTextures.push(material.textureOf(role));
		}
	} else {
		context.materials[index] = material;
		context.materialHolders[index] = 1;
		context.materialPins[index] = 0;
		context.materialTally[index] = 0;
		context.materialBlocks[index] = material.uniforms;
		for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
			context.materialTextures[index * MATERIAL_TEXTURE_ROLES + role] =
				material.textureOf(role);
		}
	}
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		if (!material.textureOf(role).isTexture()) { continue; }
		let texture: int32 = material.textureOf(role).index;
		context.texturePins[texture] = context.texturePins[texture] + 1;
		context.textureHolders[texture] = context.textureHolders[texture] + 1;
	}
	return Result.ok({
		store: context.serial,
		index: index,
		generation: context.materialSlots.generations[index],
	});
}

// Whether `id`'s `uniforms` still names the range it was added with; beginFrame refuses a
// material that does not.
export function keepsItsUniforms(this context: DrawContext, id: MaterialId): boolean {
	return context.materials[id.index].uniforms == context.materialBlocks[id.index];
}

export function keepsItsTexture(this context: DrawContext, id: MaterialId): boolean {
	const material: Material = context.materials[id.index];
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		const held: TextureId = context.materialTextures[id.index * MATERIAL_TEXTURE_ROLES + role];
		if (material.textureOf(role) != held) { return false; }
	}
	return true;
}

export function retainMaterial(
	context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("retainMaterial"); }
	if (!context.hasMaterial(id)) { return Result.err(context.materialRefusal(id)); }
	context.materialHolders[id.index] = context.materialHolders[id.index] + 1;
	return Result.ok(context.materialHolders[id.index]);
}

function letGoOfMaterial(context: DrawContext, index: int32): int32 {
	const left: int32 = context.materialHolders[index] - 1;
	if (left > 0) {
		context.materialHolders[index] = left;
		return left;
	}
	const disowned: Result<int32, UniformError> =
		disownRange(context.uniforms, context.materialBlocks[index]);
	if (!disowned.ok) { unreachable; }
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		const at: int32 = index * MATERIAL_TEXTURE_ROLES + role;
		let held: TextureId = context.materialTextures[at];
		if (held.isTexture()) {
			if (!context.hasTexture(held)) { unreachable; }
			context.texturePins[held.index] = context.texturePins[held.index] - 1;
			let _left: int32 = letGoOfTexture(context, held.index);
		}
		context.materialTextures[at] = NO_TEXTURE;
	}
	context.materials[index].uniforms = NO_UNIFORMS;
	context.materials[index].texture = NO_TEXTURE;
	context.materials[index].backTexture = NO_TEXTURE;
	context.materials[index].dissolveTexture = NO_TEXTURE;
	context.materials[index].emissiveTexture = NO_TEXTURE;
	context.materials[index].normalTexture = NO_TEXTURE;
	context.materialBlocks[index] = NO_UNIFORMS;
	context.materialHolders[index] = 0;
	vacate(context.materialSlots, index);
	return 0;
}

export function releaseMaterial(
	context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("releaseMaterial"); }
	if (!context.hasMaterial(id)) { return Result.err(context.materialRefusal(id)); }
	if (context.materialHolders[id.index] == context.materialPins[id.index]) {
		return Result.err(HandleError.OnlyPinned);
	}
	return Result.ok(letGoOfMaterial(context, id.index));
}

export function pinMaterial(
	context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("pinMaterial"); }
	if (!context.hasMaterial(id)) { return Result.err(context.materialRefusal(id)); }
	context.materialPins[id.index] = context.materialPins[id.index] + 1;
	context.materialHolders[id.index] = context.materialHolders[id.index] + 1;
	return Result.ok(context.materialHolders[id.index]);
}

export function unpinMaterial(
	context: DrawContext,
	id: MaterialId,
): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("unpinMaterial"); }
	if (!context.hasMaterial(id)) { return Result.err(context.materialRefusal(id)); }
	if (context.materialPins[id.index] == 0) { return Result.err(HandleError.NotPinned); }
	context.materialPins[id.index] = context.materialPins[id.index] - 1;
	return Result.ok(letGoOfMaterial(context, id.index));
}

export function tallyMaterialPin(context: DrawContext, id: MaterialId): boolean {
	if (context.closed) { stopOnClosedContext("tallyMaterialPin"); }
	if (!context.issuedMaterial(id)) {
		console.log("void3d: tallyMaterialPin through a context that did not issue the material");
		unreachable;
	}
	if (!context.hasMaterial(id)) { return true; }
	context.materialTally[id.index] = context.materialTally[id.index] + 1;
	return context.materialTally[id.index] <= context.materialPins[id.index];
}

export function clearMaterialTally(context: DrawContext, id: MaterialId): void {
	if (context.closed) { stopOnClosedContext("clearMaterialTally"); }
	if (context.hasMaterial(id)) { context.materialTally[id.index] = 0; }
}

const SAMPLER_SETTINGS: int32 = 6;

export function samplerSlot(filter: FilterMode, wrap: Wrap): int32 {
	let row: int32 = match (filter) {
		FilterMode.Nearest => 0,
		FilterMode.Linear => 3,
	};
	let column: int32 = match (wrap) {
		Wrap.Clamp => 0,
		Wrap.Repeat => 1,
		Wrap.Mirror => 2,
	};
	return row + column;
}

// Heaps' DirectXDriver shares one sampler state per setting (`samplerStates`), as PipelineCache
// shares a pipeline per key, and like it the cache belongs to one GPU context.
function samplerFor(context: DrawContext, filter: FilterMode, wrap: Wrap): uint32 {
	let generation: int32 = contextGeneration();
	if (context.samplerGeneration != generation) {
		for (let i = 0; i < SAMPLER_SETTINGS; i++) { context.samplers[i] = 0; }
		context.samplerGeneration = generation;
	}
	let at: int32 = samplerSlot(filter, wrap);
	if (context.samplers[at] == 0) { context.samplers[at] = makeSampler(filter, wrap); }
	return context.samplers[at];
}

const VACANT_TEXTURE: GpuTexture = { texture: null, sampler: 0, samplerGeneration: 0 };

function doomOwner(context: DrawContext, owner: Texture): void {
	const handles: DetachedHandles = owner.detach();
	if (handles.image != 0 || handles.view != 0) {
		context.doomedTextures.push({
			image: handles.image,
			view: handles.view,
			generation: handles.generation,
		});
	}
}

function uploadError(error: TextureError): TextureUploadError {
	return match (error) {
		TextureError.BadSize => TextureUploadError.BadSize,
		TextureError.ImageRefused => TextureUploadError.ImageRefused,
		TextureError.ViewRefused => TextureUploadError.ViewRefused,
	};
}

function uploadTexture(context: DrawContext, index: int32): Result<int32, TextureUploadError> {
	const sampler: uint32 = samplerFor(
		context,
		context.textureData[index].filter,
		context.textureData[index].wrap,
	);
	if (sampler == 0) { return Result.err(TextureUploadError.SamplerRefused); }
	const owner: Texture = Texture.create(
		context.textureData[index].width,
		context.textureData[index].height,
		null,
	);
	const uploaded: Result<int32, TextureError> = owner.upload(context.textureData[index].pixels);
	if (!uploaded.ok) {
		owner.close();
		return Result.err(uploadError(uploaded.error));
	}
	context.textures[index] = {
		texture: owner,
		sampler: sampler,
		samplerGeneration: contextGeneration(),
	};
	return Result.ok(index);
}

function freeTexture(context: DrawContext, index: int32): void {
	const owner: Texture | null = context.textures[index].texture;
	if (owner !== null) { doomOwner(context, owner); }
	context.textures[index] = VACANT_TEXTURE;
	context.textureData[index] = TextureData.empty();
	context.textureHolders[index] = 0;
	context.texturePins[index] = 0;
	context.textureTargets[index] = null;
	context.textureAlphas[index] = TextureAlpha.Straight;
	vacate(context.textureSlots, index);
}

// Takes a copy of `data` (CODE-STYLE §5); the caller holds the texture once. A refused upload
// frees the slot, as addMeshData does.
export function addTexture(
	context: DrawContext,
	data: TextureData,
): Result<TextureId, TextureUploadError> {
	if (context.closed) { stopOnClosedContext("addTexture"); }
	if (!data.isWellFormed()) { return Result.err(TextureUploadError.BadSize); }
	let index: int32 = claimTexture(context, data, null, TextureAlpha.Straight);
	let uploaded: Result<int32, TextureUploadError> = uploadTexture(context, index);
	if (!uploaded.ok) {
		freeTexture(context, index);
		return Result.err(uploaded.error);
	}
	return Result.ok(context.issuedTextureAt(index));
}

function claimTexture(
	context: DrawContext,
	data: TextureData,
	target: RenderTarget | null,
	alpha: TextureAlpha,
): int32 {
	let index: int32 = claim(context.textureSlots);
	if (index == (context.textures.length as int32)) {
		context.textures.push(VACANT_TEXTURE);
		context.textureData.push(data);
		context.textureHolders.push(1);
		context.texturePins.push(0);
		context.textureTargets.push(target);
		context.textureAlphas.push(alpha);
	} else {
		context.textures[index] = VACANT_TEXTURE;
		context.textureData[index] = data;
		context.textureHolders[index] = 1;
		context.texturePins[index] = 0;
		context.textureTargets[index] = target;
		context.textureAlphas[index] = alpha;
	}
	return index;
}

function issuedTextureAt(this context: DrawContext, index: int32): TextureId {
	return {
		store: context.serial,
		index: index,
		generation: context.textureSlots.generations[index],
	};
}

// Heaps' Target-flagged texture (h3d/mat/Texture.hx:257), sampled like any other.
export function addTargetTexture(
	context: DrawContext,
	target: RenderTarget,
	filter: FilterMode,
	wrap: Wrap,
	alpha: TextureAlpha,
): Result<TextureId, TextureUploadError> {
	if (context.closed) { stopOnClosedContext("addTargetTexture"); }
	if (target.isClosed()) {
		console.log("void3d: addTargetTexture on a render target that was closed");
		unreachable;
	}
	if (!target.sampled) { return Result.err(TextureUploadError.TargetNotSampled); }
	if (target.image == 0 || target.generation != contextGeneration()) {
		return Result.err(TextureUploadError.TargetNotAllocated);
	}
	const sampler: uint32 = samplerFor(context, filter, wrap);
	if (sampler == 0) { return Result.err(TextureUploadError.SamplerRefused); }
	const settings: TextureData = { ...TextureData.empty(), filter: filter, wrap: wrap };
	const index: int32 = claimTexture(context, settings, target, alpha);
	context.textures[index] = {
		texture: null,
		sampler: sampler,
		samplerGeneration: contextGeneration(),
	};
	return Result.ok(context.issuedTextureAt(index));
}

export function hasTexture(this context: DrawContext, id: TextureId): boolean {
	if (context.closed || !context.issuedTexture(id)) { return false; }
	return context.textureSlots.isCurrent(id.index, id.generation);
}

export function liveTextures(this context: DrawContext): int32 {
	return context.textureSlots.liveCount();
}

export function texturePinned(this context: DrawContext, id: TextureId): int32 {
	return context.hasTexture(id) ? context.texturePins[id.index] : 0;
}

export function retainTexture(
	context: DrawContext,
	id: TextureId,
): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("retainTexture"); }
	if (!context.hasTexture(id)) { return Result.err(context.textureRefusal(id)); }
	context.textureHolders[id.index] = context.textureHolders[id.index] + 1;
	return Result.ok(context.textureHolders[id.index]);
}

function letGoOfTexture(context: DrawContext, index: int32): int32 {
	let left: int32 = context.textureHolders[index] - 1;
	if (left > 0) {
		context.textureHolders[index] = left;
		return left;
	}
	freeTexture(context, index);
	return 0;
}

export function releaseTexture(
	context: DrawContext,
	id: TextureId,
): Result<int32, HandleError> {
	if (context.closed) { stopOnClosedContext("releaseTexture"); }
	if (!context.hasTexture(id)) { return Result.err(context.textureRefusal(id)); }
	if (context.textureHolders[id.index] == context.texturePins[id.index]) {
		return Result.err(HandleError.OnlyPinned);
	}
	return Result.ok(letGoOfTexture(context, id.index));
}

// Remakes every texture whose image or sampler is from an older GPU context, and answers how
// many came back. The image goes back through the owner's own upload, which Heaps' `realloc`
// does (h3d/mat/Texture.hx:166-168), but here where a refusal is tolerated: asView would stop on
// it. A refused one is left without a view, so it is retried on the next rebuild and its
// materials draw nothing meanwhile (drawItem).
export function rebuildTextures(context: DrawContext): int32 {
	if (context.closed) { stopOnClosedContext("rebuildTextures"); }
	let generation: int32 = contextGeneration();
	let count: int32 = 0;
	for (let i = 0; i < (context.textures.length as int32); i++) {
		if (context.textureHolders[i] == 0) { continue; }
		const owner: Texture | null = context.textures[i].texture;
		const imageStale: boolean = owner !== null && owner.generation != generation;
		if (context.textures[i].samplerGeneration == generation && !imageStale) { continue; }
		if (context.textures[i].samplerGeneration != generation) {
			const sampler: uint32 =
				samplerFor(context, context.textureData[i].filter, context.textureData[i].wrap);
			if (sampler == 0) {
				if (owner !== null) { context.textures[i].sampler = 0; }
				continue;
			}
			context.textures[i].sampler = sampler;
			context.textures[i].samplerGeneration = generation;
		}
		if (owner !== null && imageStale) {
			if (!owner.upload(context.textureData[i].pixels).ok) { continue; }
		}
		count = count + 1;
	}
	return count;
}

// Destroys the doomed buffers, images and views of GPU context `generation` and drops the rest:
// one of an older context died with it, and its handle may name an object of the new one
// (docs/VOID3D.md, Android lifecycle).
export function buryDoomed(context: DrawContext, generation: int32): int32 {
	if (context.closed) { stopOnClosedContext("buryDoomed"); }
	let destroyed: int32 = 0;
	for (const doomed of context.doomed) {
		if (doomed.generation != generation) { continue; }
		destroyBuffer(doomed.buffer);
		destroyed = destroyed + 1;
	}
	while ((context.doomed.length as int32) > 0) { context.doomed.pop(); }
	for (const doomed of context.doomedTextures) {
		if (doomed.generation != generation) { continue; }
		destroyView(doomed.view);
		destroyImage(doomed.image);
		destroyed = destroyed + 1;
	}
	while ((context.doomedTextures.length as int32) > 0) { context.doomedTextures.pop(); }
	return destroyed;
}

export function reserveUniforms(
	context: DrawContext,
	slot: int32,
	length: int32,
): Result<UniformBlock, UniformError> {
	if (context.closed) { stopOnClosedContext("reserveUniforms"); }
	return reserveRange(context.uniforms, slot, length);
}

// Once released, `block` is refused wherever it is written, and its range goes to the next
// reserve of the same length. A material's range goes with the material, never before it
// (UniformError.Owned).
export function releaseUniforms(
	context: DrawContext,
	block: UniformBlock,
): Result<int32, UniformError> {
	if (context.closed) { stopOnClosedContext("releaseUniforms"); }
	return releaseRange(context.uniforms, block);
}

export function writeUniforms(
	context: DrawContext,
	block: UniformBlock,
	values: Readonly<Span<float32>>,
): Result<int32, UniformError> {
	if (context.closed) { stopOnClosedContext("writeUniforms"); }
	return writeRange(context.uniforms, block, values);
}

function applyBlock(this context: DrawContext, block: UniformBlock): void {
	applyUniforms(block.slot, context.uniforms.values[block.offset..block.offset + block.length]);
}

// The first `declared` floats of a block: a program that reads less than its material's block
// takes the head, since gpu3d.ms puts the features a caster drops last (emissiveBase).
// Only a shadow program may read less than its material's block; a colour pass reads all of it.
export function applyBlockHead(
	this context: DrawContext,
	block: UniformBlock,
	program: ProgramKey,
	declared: int32,
): void {
	if (block.length < declared) { stopOnShortBlock(program, block, declared); }
	if (program.preset != Preset.Shadow && block.length != declared) {
		stopOnLongBlock(program, block, declared);
	}
	applyUniforms(block.slot, context.uniforms.values[block.offset..block.offset + declared]);
}

function stopOnShortBlock(program: ProgramKey, block: UniformBlock, declared: int32): void {
	console.log(`void3d: ${program.describe()} reads ${declared} floats of slot ${block.slot} ` +
		`and its material's block holds ${block.length}`);
	unreachable;
}

function stopOnLongBlock(program: ProgramKey, block: UniformBlock, declared: int32): void {
	console.log(`void3d: ${program.describe()} reads ${declared} floats of slot ${block.slot}, ` +
		`so a block of ${block.length} is not its own; only a shadow caster takes a head`);
	unreachable;
}

// An hxsl global texture (Heaps' `shadow.map`), bound past a material's slots.
export struct SceneTexture {
	view: uint32;
	sampler: uint32;
}

export const NO_SCENE_TEXTURE: SceneTexture = { view: 0, sampler: 0 };

function bindItem(
	context: DrawContext,
	mesh: GpuMesh,
	material: Material,
	scene: SceneTexture,
): void {
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
	context.bindings[GPU3D_BINDING_VIEW + NORMAL_VIEW_SLOT] = 0;
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		const texture: TextureId = material.textureOf(role);
		if (!texture.isTexture()) { continue; }
		context.bindings[GPU3D_BINDING_VIEW + viewSlotOf(role)] = context.viewAt(texture.index);
		const sampler: int32 = samplerSlotOf(role);
		if (sampler >= 0) {
			context.bindings[GPU3D_BINDING_SAMPLER + sampler] =
				context.textures[texture.index].sampler;
		}
	}
	context.bindings[GPU3D_BINDING_VIEW + SHADOW_VIEW_SLOT] = scene.view;
	context.bindings[GPU3D_BINDING_SAMPLER + SHADOW_SAMPLER_SLOT] = scene.sampler;
	applyBindings(context.bindings);
}

// viewAt and textureReady read `owner.view` because `asView` stops on a stale texture.
function viewAt(this context: DrawContext, index: int32): uint32 {
	const target: RenderTarget | null = context.textureTargets[index];
	if (target !== null) { return target.asTexture(); }
	const owner: Texture | null = context.textures[index].texture;
	if (owner !== null) { return owner.view; }
	return 0;
}

function stopOnFeedbackTarget(index: int32): void {
	console.log(`void3d: drawItem samples texture ${index} from the render target this pass ` +
		"draws into; end the pass that writes it first");
	unreachable;
}

function stopOnClosedTargetTexture(index: int32): void {
	console.log(`void3d: drawItem samples texture ${index}, a render target that was ` +
		"closed; release the materials that sample it first");
	unreachable;
}

export function textureReady(this context: DrawContext, index: int32): boolean {
	const target: RenderTarget | null = context.textureTargets[index];
	if (target === null) {
		const owner: Texture | null = context.textures[index].texture;
		return owner !== null && owner.view != 0 && owner.generation == contextGeneration() &&
			context.textures[index].sampler != 0;
	}
	if (target.isClosed()) { stopOnClosedTargetTexture(index); }
	const generation: int32 = contextGeneration();
	if (target.image == 0 || target.generation != generation ||
		context.textures[index].samplerGeneration != generation) {
		return false;
	}
	if (target.isAttachedToOpenPass()) { stopOnFeedbackTarget(index); }
	return true;
}

function stopOnAlphaMismatch(program: ProgramKey, alpha: TextureAlpha): void {
	console.log(`void3d: drawItem draws ${program.describe()} for a ${alpha.toString()} ` +
		"material or texture; premultiplied input needs a premultiplied program, straight a " +
		"straight one");
	unreachable;
}

function stopOnUnheldItem(): void {
	console.log("void3d: drawItem on an item its context does not hold; beginFrame refuses one");
	unreachable;
}

function stopOnUnheldBlock(slot: int32): void {
	console.log(`void3d: drawItem with a block at slot ${slot} its context does not hold`);
	unreachable;
}

function stopOnReplacedBlock(): void {
	console.log("void3d: drawItem with a material whose block is not the one it was added with");
	unreachable;
}

function stopOnReplacedTexture(): void {
	console.log("void3d: drawItem with a material whose texture is not the one it was added with");
	unreachable;
}

// One item into the current pass, whose attachments match `targets`, drawn with `program`:
// the material's own, or its key in the renderer's preset (gpu3d.ms drawnIn). `globals` are
// the pass-wide blocks (camera, lights) applied before the material's own.
export function drawItem(
	context: DrawContext,
	item: DrawItem,
	program: ProgramKey,
	targets: TargetLayout,
	globals: Readonly<Span<UniformBlock>>,
): void {
	if (context.closed) { stopOnClosedContext("drawItem"); }
	if (!context.hasMaterial(item.material)) { stopOnUnheldItem(); }
	const state: RenderState = context.materials[item.material.index].pass;
	drawItemWith(context, item, program, state, targets, globals, NO_SCENE_TEXTURE);
}

// A caster draws with h3d.mat.Material's "shadow" Pass state, not the material's main pass.
export function drawItemWith(
	context: DrawContext,
	item: DrawItem,
	program: ProgramKey,
	state: RenderState,
	targets: TargetLayout,
	globals: Readonly<Span<UniformBlock>>,
	scene: SceneTexture,
): void {
	if (context.closed) { stopOnClosedContext("drawItem"); }
	if (!context.hasMesh(item.mesh) || !context.hasMaterial(item.material)) { stopOnUnheldItem(); }
	for (const block of globals) {
		if (!context.uniforms.holds(block)) { stopOnUnheldBlock(block.slot); }
	}
	if (!context.keepsItsUniforms(item.material)) { stopOnReplacedBlock(); }
	if (!context.keepsItsTexture(item.material)) { stopOnReplacedTexture(); }
	const material: Material = context.materials[item.material.index];
	const mesh: GpuMesh = context.meshes[item.mesh.index];
	if (mesh.hasNothingToDraw()) { return; }
	const declared: TextureAlpha = material.program.premultiplied ?
		TextureAlpha.Premultiplied : TextureAlpha.Straight;
	// Depth has no colour to premultiply, and the alpha a caster cuts by is the same either way.
	const colored: boolean = program.preset != Preset.Shadow;
	if (colored && program.premultiplied != material.program.premultiplied) {
		stopOnAlphaMismatch(program, declared);
	}
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		const texture: TextureId = material.textureOf(role);
		if (!texture.isTexture()) { continue; }
		const alpha: TextureAlpha = context.textureAlphas[texture.index];
		if (colored && colorRole(role) && alpha != declared) {
			stopOnAlphaMismatch(program, alpha);
		}
		if (!context.textureReady(texture.index)) { return; }
	}
	const pipeline: uint32 = pipelineFor(
		context.pipelines,
		program,
		mesh.layout,
		mesh.isIndexed(),
		state,
		targets,
	);
	applyPipeline(pipeline);
	bindItem(context, mesh, material, scene);
	let globalProgram: int32 = doorProgram(program);
	if (context.pipelines.declaresBlock(globalProgram, MODEL_SLOT)) {
		const modelLength: int32 = uniformBlockLength(program, MODEL_SLOT);
		item.world.writeTo(context.model[0..MODEL_LENGTH], 0);
		if (modelLength == MODEL_LENGTH) {
			item.world.normalMatrix().writeTo(context.model[0..MODEL_LENGTH], 16);
		}
		applyUniforms(MODEL_SLOT, context.model[0..modelLength]);
	}
	for (const block of globals) {
		if (context.pipelines.declaresBlock(globalProgram, block.slot)) {
			context.applyBlock(block);
		}
	}
	// A caster that does not cut reads none of its material's block.
	if (material.uniforms.length > 0 &&
		context.pipelines.declaresBlock(globalProgram, material.uniforms.slot)) {
		const declared: int32 = uniformBlockLength(program, material.uniforms.slot);
		context.applyBlockHead(material.uniforms, program, declared);
	}
	draw(0, mesh.elementCount(), mesh.instanceCount);
}

export function closeContext(context: DrawContext): void {
	if (context.closed) { stopOnClosedContext("closeContext"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeContext with a pass open; endPass ends it");
		unreachable;
	}
	const meshes: int32 = context.liveMeshes();
	const materials: int32 = context.liveMaterials();
	const textures: int32 = context.liveTextures();
	const ranges: int32 = context.uniforms.liveRanges();
	if (meshes + materials + textures + ranges > 0) {
		stopOnLiveHolds(context, meshes, materials, textures, ranges);
	}
	const generation: int32 = contextGeneration();
	const _buried: int32 = buryDoomed(context, generation);
	if (context.samplerGeneration == generation) {
		for (const sampler of context.samplers) {
			if (sampler != 0) { destroySampler(sampler); }
		}
	}
	for (let i = 0; i < SAMPLER_SETTINGS; i++) { context.samplers[i] = 0; }
	if (!context.pipelines.closed) { closePipelines(context.pipelines); }
	if (!context.uniforms.closed) { closeUniformPool(context.uniforms); }
	context.closed = true;
}

export function isClosed(this context: DrawContext): boolean {
	return context.closed;
}

export function requireOpen(this context: DrawContext, call: string): void {
	if (context.closed) { stopOnClosedContext(call); }
}

function stopOnLiveHolds(
	context: DrawContext,
	meshes: int32,
	materials: int32,
	textures: int32,
	ranges: int32,
): void {
	let pins: int32 = 0;
	for (const pinned of context.meshPins) { pins = pins + pinned; }
	for (const pinned of context.materialPins) { pins = pins + pinned; }
	for (const pinned of context.texturePins) { pins = pins + pinned; }
	console.log(
		`void3d: closeContext with holds still live: meshes ${meshes}, materials ${materials}, ` +
		`textures ${textures}, uniform ranges ${ranges}, pins ${pins}`,
	);
	unreachable;
}

function stopOnClosedContext(call: string): void {
	console.log(`void3d: ${call} on a draw context that was closed`);
	unreachable;
}
