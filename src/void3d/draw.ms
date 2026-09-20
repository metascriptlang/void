// Draw items and the tables they index. The renderer consumes a flat Span<DrawItem>, not the
// scene tree (docs/VOID3D.md, Porting rules): a scene flattens into items when its structure
// changes, and every frame only rewrites their world matrices.
//
// DrawContext owns everything items point into: GPU meshes, materials, the uniform pool and the
// pipeline cache. Items and materials are plain values holding indices and handles.

import { Mat4 } from "../math/math3d";
import {
	VertexLayout,
	applyPipeline,
	applyBindings,
	applyUniforms,
	draw,
	makeVertexBuffer,
	makeIndexBuffer,
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
	generation: int32;
}

export function isIndexed(this mesh: GpuMesh): boolean {
	return mesh.indexBuffer != 0;
}

// What sg_draw counts: index elements when indexed, vertices otherwise.
export function elementCount(this mesh: GpuMesh): int32 {
	return mesh.isIndexed() ? mesh.indexCount : mesh.vertexCount;
}

// `mesh` and `material` index the DrawContext tables. `world` is carried for M6: the programs
// in shader3d.glsl still take world-space vertices and have no model matrix to upload it to.
export struct DrawItem {
	mesh: int32;
	material: int32;
	world: Mat4;
}

// `meshes` and `meshData` are one index space: meshData[i] is the CPU geometry mesh[i] was
// uploaded from, or an empty MeshData for a mesh whose data its owner keeps (the screen
// triangle, billboard corners and instances). Everything with CPU data here comes back on its
// own after a context loss (rebuildMeshes); everything without is its owner's to rebuild.
export struct DrawContext {
	meshes: Vec<GpuMesh>;
	meshData: Vec<MeshData>;
	materials: Vec<Material>;
	uniforms: Vec<float32>;
	uniformsUsed: int32;
	pipelines: PipelineCache;
	bindings: Vec<uint32>;
}

export enum UniformError {
	PoolFull,
}

export enum MeshUploadError {
	VertexBufferRefused,
	IndexBufferRefused,
}

// The uniform pool is sized here, once; reserveUniforms only hands out ranges of it.
export function withUniformCapacity(this typeof DrawContext, capacity: int32): DrawContext {
	const bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH);
	for (let i = 0; i < GPU3D_BINDING_LENGTH; i++) {
		bindings[i] = 0;
	}
	return {
		meshes: [],
		meshData: [],
		materials: [],
		uniforms: new Array(capacity),
		uniformsUsed: 0,
		pipelines: PipelineCache.empty(),
		bindings: bindings,
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
	data: MeshData,
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
		generation: generation,
	};
}

// A mesh is stale when it has CPU data and its handles belong to an older GPU context.
export function isStale(this mesh: GpuMesh, data: MeshData, generation: int32): boolean {
	return data.vertexCount() > 0 && mesh.generation != generation;
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
export function uploadMesh(ref context: DrawContext, index: int32): Result<int32, MeshUploadError> {
	const vertexBuffer: uint32 = makeVertexBuffer(context.meshData[index].vertices);
	let indexBuffer: uint32 = 0;
	if (context.meshData[index].isIndexed()) {
		indexBuffer = makeIndexBuffer(context.meshData[index].indices);
	}
	if (vertexBuffer == 0) {
		context.meshes[index] = context.meshes[index].drawsNothing();
		return Result.err(MeshUploadError.VertexBufferRefused);
	}
	if (context.meshData[index].isIndexed() && indexBuffer == 0) {
		context.meshes[index] = context.meshes[index].drawsNothing();
		return Result.err(MeshUploadError.IndexBufferRefused);
	}
	context.meshes[index] = meshFor(
		context.meshData[index],
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
	context.meshes.push(meshFor(data, 0, 0, 0));
	const uploaded: int32 = try uploadMesh(context, index);
	return Result.ok(uploaded);
}

// How many meshes would come back on their own after a context loss.
export function rebuildableMeshes(this context: DrawContext): int32 {
	let count: int32 = 0;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshData[i].vertexCount() > 0) { count = count + 1; }
	}
	return count;
}

// How many meshes hold handles from an older GPU context.
export function staleMeshes(this context: DrawContext, generation: int32): int32 {
	let count: int32 = 0;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshes[i].isStale(context.meshData[i], generation)) { count = count + 1; }
	}
	return count;
}

// Re-uploads every mesh whose handles are from an older GPU context, and answers how many came
// back. Called from the core's beginFrame on the frame that sees a new contextGeneration; a
// mesh uploaded on this generation already (addMeshData, the common case) is left alone. A
// mesh the driver refuses is left empty and stale, so it is retried on the next rebuild and is
// not counted here. Nothing on this path allocates: a MeshData parameter is passed by pointer,
// not copied, because the struct is over 24 bytes (CODE-STYLE §5, measured on 0.2.53).
export function rebuildMeshes(ref context: DrawContext): int32 {
	const generation: int32 = contextGeneration();
	let rebuilt: int32 = 0;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (!context.meshes[i].isStale(context.meshData[i], generation)) { continue; }
		if (uploadMesh(context, i).ok) { rebuilt = rebuilt + 1; }
	}
	return rebuilt;
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

// Copies `values` into the block; extra values are dropped, missing ones keep their old value.
export function writeUniforms(
	ref context: DrawContext,
	block: UniformBlock,
	values: Span<float32>,
): void {
	const count: int32 = Math.min(block.length, values.length as int32) as int32;
	for (let i = 0; i < count; i++) {
		context.uniforms[block.offset + i] = values[i];
	}
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

// One item into the current pass, whose attachments match `targets`. `globals` are the
// pass-wide blocks (camera, lights) applied before the material's own.
export function drawItem(
	ref context: DrawContext,
	item: DrawItem,
	targets: TargetLayout,
	globals: Span<UniformBlock>,
): void {
	const mesh: GpuMesh = context.meshes[item.mesh];
	const material: Material = context.materials[item.material];
	const pipeline: uint32 = pipelineFor(
		context.pipelines,
		material.program,
		mesh.layout,
		mesh.isIndexed(),
		material.pass,
		targets,
	);
	applyPipeline(pipeline);
	bindItem(context, mesh, material);
	for (const block of globals) {
		context.applyBlock(block);
	}
	if (material.uniforms.length > 0) {
		context.applyBlock(material.uniforms);
	}
	draw(0, mesh.elementCount(), mesh.instanceCount);
}

// Draws `items` in order.
export function drawItems(
	ref context: DrawContext,
	items: Span<DrawItem>,
	targets: TargetLayout,
	globals: Span<UniformBlock>,
): void {
	for (const item of items) {
		drawItem(context, item, targets, globals);
	}
}
