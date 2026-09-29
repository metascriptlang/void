// void3d's programs and draw path, MetaScript side. void3d's programs and vertex layouts are
// registered with the GPU door (src/gpu/door.c) once at module load, and the ids handed back
// are what every door call takes: doorProgram / doorLayout add this layer's base to a Program
// or VertexLayout ordinal, because registration order is import order and no layer's enum may
// assume another's base. Buffers, plain and dynamic images, bindings, uniforms and the draw
// call stay here (gpu3d.c); what both render layers share — programs, pipelines, targets,
// formats, passes, samplers — is the door's (src/gpu).
//
// Enum members are sent to C as ordinals and mapped by tables in door.c, so a member added
// here must be added there in the same position. Handles are sokol ids as uint32, 0 = none.
// The bindings layout (GPU3D_BINDING_*) comes from gpu3d.h.

import {
	makeShader as doorMakeShader,
	uniformSlotMask as doorUniformSlotMask,
	uniformBlockBytes as doorUniformBlockBytes,
	textureSlotMask as doorTextureSlotMask,
	samplerSlotMask as doorSamplerSlotMask,
	layoutFloats as doorLayoutFloats,
	layoutPerInstance as doorLayoutPerInstance,
	programLayout as doorProgramLayout,
	originTopLeft as doorOriginTopLeft,
	depthZeroToOne as doorDepthZeroToOne,
	contextGeneration as doorContextGeneration,
	frameIndex as doorFrameIndex,
	liveBuffers as doorLiveBuffers,
	UNIFORM_SLOTS as DOOR_UNIFORM_SLOTS,
} from "../gpu/door";
import {
	PipelineCache,
	PipelineKey,
	pipelineFor as pipelineForIds,
	pipelineKey as pipelineKeyIds,
} from "../gpu/pipeline";
import { RenderState } from "../gpu/state";
import { TargetLayout } from "../gpu/target";
import {
	gpu3dProgramBase,
	gpu3dLayoutBase,
	gpu3dMakeDynamicImage,
	gpu3dMakeStreamBuffer,
	gpu3dDestroyBuffer,
	gpu3dDestroyImage,
	gpu3dApplyPipeline,
	gpu3dDraw,
} from "./gpu3d.h";

// The functions that take arrays are declared here instead: an `extern` Span<T> parameter
// lowers to the (pointer, int64 length) pair gpu3d.h declares. Importing them from the header
// maps the pointer to Borrow<T>, and on msc 0.2.53 `span[0]` passed there is the address of a
// one-element copy (docs/VOID3D.md, Compiler notes).
extern function gpu3dMakeVertexBuffer(data: Span<float32>): uint32;
extern function gpu3dMakeIndexBuffer(data: Span<uint16>): uint32;
extern function gpu3dMakeImage(rgba: Span<uint32>, width: int32, height: int32): uint32;
extern function gpu3dUpdateImage(image: uint32, rgba: Span<uint32>): void;
extern function gpu3dUpdateBuffer(buffer: uint32, data: Span<float32>): int32;
extern function gpu3dApplyBindings(bindings: Span<uint32>): void;
extern function gpu3dApplyUniforms(slot: int32, data: Span<float32>): void;

let programBase: int32 = gpu3dProgramBase();
let layoutBase: int32 = gpu3dLayoutBase();

// The door id of one of void3d's programs / layouts, from this layer's own ordinal.
export function doorProgram(program: Program): int32 {
	return programBase + (program as int32);
}

export function doorLayout(layout: VertexLayout): int32 {
	return layoutBase + (layout as int32);
}

// One per @program in shader3d.glsl (the core's) and pixelArt3d.glsl (the preset's), in the
// order gpu3d.c registers them. Materials name the first three.
export enum Program {
	Lit,
	Particle,
	Billboard,
	Copy,
	PixelArtLit,
	PixelArtParticle,
	PixelArtBillboard,
	PixelArtPost,
	PixelArtBlit,
}

// Vertex buffer layouts gpu3d.c describes (describeLayout).
export enum VertexLayout {
	Lit,
	Particle,
	Billboard,
	Fullscreen,
}

// The layout each program reads: gpu3d.c asserts that every program of a layout declares the
// core program's attribute slots, and tests hold this map against the registration's own
// answer (door programLayout).
export function vertexLayoutOf(program: Program): VertexLayout {
	return match (program) {
		Program.Lit => VertexLayout.Lit,
		Program.Particle => VertexLayout.Particle,
		Program.Billboard => VertexLayout.Billboard,
		Program.Copy => VertexLayout.Fullscreen,
		Program.PixelArtLit => VertexLayout.Lit,
		Program.PixelArtParticle => VertexLayout.Particle,
		Program.PixelArtBillboard => VertexLayout.Billboard,
		Program.PixelArtPost => VertexLayout.Fullscreen,
		Program.PixelArtBlit => VertexLayout.Fullscreen,
	};
}

export function drawsQuads(layout: VertexLayout): boolean {
	return match (layout) {
		VertexLayout.Lit => false,
		VertexLayout.Particle => true,
		VertexLayout.Billboard => true,
		VertexLayout.Fullscreen => false,
	};
}

// Uniform block slots and sizes in floats, from the `binding=` blocks in shader3dBlocks.glsl.
export const VERTEX_UNIFORM_SLOT: int32 = 0;
export const VERTEX_UNIFORM_LENGTH: int32 = 24;
export const LIGHT_UNIFORM_SLOT: int32 = 1;
// ambient (rgb + point count), dirLight (direction + power), dirColor, then pointLight[4]
// (position + power) and pointColor[4] (rgb + radius): two vec4 arrays of one vec4 per light,
// packoffset(c3) and packoffset(c7) in the HLSL, so four floats per light in each.
export const MAX_POINT_LIGHTS: int32 = 4;
export const LIGHT_UNIFORM_LENGTH: int32 = 12 + 2 * MAX_POINT_LIGHTS * 4;
// A lit material's own block (binding=3). The core reads the saturation it applies to the
// material's colour before lighting (0 leaves it alone, -1 is grey); a preset may give the
// other floats a meaning of its own (pixelArtRenderer.ms RAMP_LEVELS).
export const MATERIAL_UNIFORM_SLOT: int32 = 3;
export const MATERIAL_UNIFORM_LENGTH: int32 = 4;
export const MATERIAL_SATURATION: int32 = 1;
// A billboard material's block (binding=2): its colour, then at BILLBOARD_LIGHT 0 to leave the
// lights out (Heaps' `particles3D` material has `light: true`). A preset may give the other
// floats a meaning of its own (pixelArtRenderer.ms BILLBOARD_RAMP_LEVELS).
export const BILLBOARD_UNIFORM_SLOT: int32 = 2;
export const BILLBOARD_UNIFORM_LENGTH: int32 = 8;
export const BILLBOARD_COLOR: int32 = 0;
export const BILLBOARD_LIGHT: int32 = 5;

export const UNIFORM_SLOTS: int32 = DOOR_UNIFORM_SLOTS;

// The layout the door's registration gives one of void3d's programs, as an id.
export function registeredLayout(program: Program): int32 {
	return doorProgramLayout(doorProgram(program));
}

export function uniformSlotMask(program: Program): uint32 {
	return doorUniformSlotMask(doorProgram(program));
}

// Floats of the block `program` declares at `slot`, 0 for none, read off its shader desc.
export function uniformBlockLength(program: Program, slot: int32): int32 {
	return doorUniformBlockBytes(doorProgram(program), slot) / 4;
}

// Bit n set when `program` samples a texture at view slot n (textureSlotMask) or declares
// sampler slot n (samplerSlotMask), read off its shader desc.
export function textureSlotMask(program: Program): uint32 {
	return doorTextureSlotMask(doorProgram(program));
}

export function samplerSlotMask(program: Program): uint32 {
	return doorSamplerSlotMask(doorProgram(program));
}

// Floats per element of vertex buffer `buffer` of `layout`, as gpu3d.c registered it.
export function layoutFloats(layout: VertexLayout, buffer: int32): int32 {
	return doorLayoutFloats(doorLayout(layout), buffer);
}

export function layoutPerInstance(layout: VertexLayout): boolean {
	return doorLayoutPerInstance(doorLayout(layout));
}

// PipelineBuilder.lookup, on void3d's own enums: the key and the cache are the door's.
export function pipelineFor(
	ref cache: PipelineCache,
	program: Program,
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): uint32 {
	return pipelineForIds(
		cache,
		doorProgram(program),
		doorLayout(layout),
		indexed,
		state,
		targets,
	);
}

export function pipelineKey(
	program: Program,
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): PipelineKey {
	return pipelineKeyIds(doorProgram(program), doorLayout(layout), indexed, state, targets);
}

export function makeVertexBuffer(data: Span<float32>): uint32 {
	return gpu3dMakeVertexBuffer(data);
}

// Three uint16 per triangle. sokol copies the data, so the Vec it came from may move after.
export function makeIndexBuffer(data: Span<uint16>): uint32 {
	return gpu3dMakeIndexBuffer(data);
}

export function makeImage(rgba: Span<uint32>, width: int32, height: int32): uint32 {
	return gpu3dMakeImage(rgba, width, height);
}

// An RGBA8 image the CPU rewrites with updateImage; its pixels start undefined.
export function makeDynamicImage(width: int32, height: int32): uint32 {
	return gpu3dMakeDynamicImage(width, height);
}

// sokol allows one update per image per frame, before any pass samples it.
export function updateImage(image: uint32, rgba: Span<uint32>): void {
	gpu3dUpdateImage(image, rgba);
}

export function makeStreamBuffer(length: int32): uint32 {
	return gpu3dMakeStreamBuffer(length as int64);
}

// sokol takes one update per buffer per frame, before the pass that draws it.
export function updateBuffer(buffer: uint32, data: Span<float32>): boolean {
	return gpu3dUpdateBuffer(buffer, data) != 0;
}

// Framebuffer and texture rows start at the top (D3D11, Metal) rather than the bottom (GL).
export function originTopLeft(): boolean {
	return doorOriginTopLeft();
}

// The depth buffer holds clip z as is (0..1); GL stores (z + 1) / 2 instead.
export function depthZeroToOne(): boolean {
	return doorDepthZeroToOne();
}

// Counts GPU contexts: it changes when the host lost the context and made a new one, and every
// handle from before is then stale (docs/VOID3D.md, Android lifecycle). Only the Android
// bridge ever loses its context.
export function contextGeneration(): int32 {
	return doorContextGeneration();
}

export function frameIndex(): uint32 {
	return doorFrameIndex();
}

export function liveBuffers(): int32 {
	return doorLiveBuffers();
}

export function destroyBuffer(buffer: uint32): void { gpu3dDestroyBuffer(buffer); }
export function destroyImage(image: uint32): void { gpu3dDestroyImage(image); }

export function applyPipeline(pipeline: uint32): void { gpu3dApplyPipeline(pipeline); }

export function applyBindings(bindings: Span<uint32>): void {
	gpu3dApplyBindings(bindings);
}

export function applyUniforms(slot: int32, data: Span<float32>): void {
	gpu3dApplyUniforms(slot, data);
}

export function draw(base: int32, count: int32, instances: int32): void {
	gpu3dDraw(base, count, instances);
}
