// Draw items and the tables they index. The renderer consumes a flat Span<DrawItem>, not the
// scene tree (docs/VOID3D.md, Porting rules): a scene flattens into items when its structure
// changes, and every frame only rewrites their world matrices.
//
// DrawContext owns everything items point into: GPU meshes, materials, the uniform pool and the
// pipeline cache. Items and materials are plain values holding indices and handles.

import { Mat4 } from "../math/math3d";
import { VertexLayout, applyPipeline, applyBindings, applyUniforms, draw } from "./gpu3d";
import {
	GPU3D_BINDING_VERTEX_BUFFER,
	GPU3D_BINDING_INDEX_BUFFER,
	GPU3D_BINDING_VIEW,
	GPU3D_BINDING_SAMPLER,
	GPU3D_BINDING_LENGTH,
} from "./gpu3d.h";
import { Material, UniformBlock } from "./material";
import { PipelineCache, pipelineFor } from "./pipelineCache";
import { TargetLayout } from "./target";

// GPU side of a mesh until M5 brings MeshData: buffer handles plus what sg_draw needs.
// `instanceBuffer` feeds vertex buffer slot 1 (billboard instances), 0 when not instanced.
export struct GpuMesh {
	layout: VertexLayout;
	vertexBuffer: uint32;
	instanceBuffer: uint32;
	vertexCount: int32;
	instanceCount: int32;
}

// `mesh` and `material` index the DrawContext tables. `world` is carried for M6: the programs
// in shader3d.glsl still take world-space vertices and have no model matrix to upload it to.
export struct DrawItem {
	mesh: int32;
	material: int32;
	world: Mat4;
}

export struct DrawContext {
	meshes: Vec<GpuMesh>;
	materials: Vec<Material>;
	uniforms: Vec<float32>;
	uniformsUsed: int32;
	pipelines: PipelineCache;
	bindings: Vec<uint32>;
}

export enum UniformError {
	PoolFull,
}

// The uniform pool is sized here, once; reserveUniforms only hands out ranges of it.
export function withUniformCapacity(this typeof DrawContext, capacity: int32): DrawContext {
	const bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH);
	for (let i = 0; i < GPU3D_BINDING_LENGTH; i++) {
		bindings[i] = 0;
	}
	return {
		meshes: [],
		materials: [],
		uniforms: new Array(capacity),
		uniformsUsed: 0,
		pipelines: PipelineCache.empty(),
		bindings: bindings,
	};
}

export function addMesh(ref context: DrawContext, mesh: GpuMesh): int32 {
	context.meshes.push(mesh);
	return (context.meshes.length as int32) - 1;
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
	context.bindings[GPU3D_BINDING_INDEX_BUFFER] = 0;
	context.bindings[GPU3D_BINDING_VIEW] = material.texture0;
	context.bindings[GPU3D_BINDING_VIEW + 1] = material.texture1;
	context.bindings[GPU3D_BINDING_SAMPLER] = material.sampler;
	applyBindings(context.bindings);
}

// Draws `items` in order into the current pass, whose attachments match `targets`.
// `globals` are the pass-wide blocks (camera, lights) applied before each material's own.
export function drawItems(
	ref context: DrawContext,
	items: Span<DrawItem>,
	targets: TargetLayout,
	globals: Span<UniformBlock>,
): void {
	for (let i = 0; i < (items.length as int32); i++) {
		const mesh: GpuMesh = context.meshes[items[i].mesh];
		const material: Material = context.materials[items[i].material];
		const pipeline: uint32 = pipelineFor(
			context.pipelines,
			material.program,
			mesh.layout,
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
		draw(0, mesh.vertexCount, mesh.instanceCount);
	}
}
