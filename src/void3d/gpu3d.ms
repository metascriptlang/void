
import {
	uniformBlockBytes as doorUniformBlockBytes,
	textureSlotMask as doorTextureSlotMask,
	samplerSlotMask as doorSamplerSlotMask,
	layoutFloats as doorLayoutFloats,
	layoutPerInstance as doorLayoutPerInstance,
	programLayout as doorProgramLayout,
} from "../gpu/door";
import {
	PipelineCache,
	pipelineFor as pipelineForIds,
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
extern function gpu3dMakeVertexBuffer(data: Readonly<Span<float32>>): uint32;
extern function gpu3dMakeIndexBuffer(data: Readonly<Span<uint16>>): uint32;
extern function gpu3dMakeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32;
extern function gpu3dUpdateImage(image: uint32, rgba: Readonly<Span<uint32>>): void;
extern function gpu3dUpdateBuffer(buffer: uint32, data: Readonly<Span<float32>>): int32;
extern function gpu3dApplyBindings(bindings: Readonly<Span<uint32>>): void;
extern function gpu3dApplyUniforms(slot: int32, data: Readonly<Span<float32>>): void;

let programBase: int32 = gpu3dProgramBase();
let layoutBase: int32 = gpu3dLayoutBase();

// The door id of one of void3d's programs / layouts, from this layer's own ordinal.
export function doorProgram(program: Program): int32 {
	return programBase + (program as int32);
}

export function doorLayout(layout: VertexLayout): int32 {
	return layoutBase + (layout as int32);
}

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
	LitTextured,
	PixelArtLitTextured,
	UnlitTextured,
	PixelArtUnlitTextured,
	LitTexturedPremultiplied,
	PixelArtLitTexturedPremultiplied,
	UnlitTexturedPremultiplied,
	PixelArtUnlitTexturedPremultiplied,
}

export function samplesPremultiplied(program: Program): boolean {
	return match (program) {
		Program.LitTexturedPremultiplied => true,
		Program.PixelArtLitTexturedPremultiplied => true,
		Program.UnlitTexturedPremultiplied => true,
		Program.PixelArtUnlitTexturedPremultiplied => true,
		Program.Lit => false,
		Program.Particle => false,
		Program.Billboard => false,
		Program.Copy => false,
		Program.PixelArtLit => false,
		Program.PixelArtParticle => false,
		Program.PixelArtBillboard => false,
		Program.PixelArtPost => false,
		Program.PixelArtBlit => false,
		Program.LitTextured => false,
		Program.PixelArtLitTextured => false,
		Program.UnlitTextured => false,
		Program.PixelArtUnlitTextured => false,
	};
}

// Vertex buffer layouts gpu3d.c describes (describeLayout).
export enum VertexLayout {
	Lit,
	Particle,
	Billboard,
	Fullscreen,
	LitTextured,
}

export function vertexLayoutOf(program: Program): VertexLayout {
	return (doorProgramLayout(doorProgram(program)) - layoutBase) as VertexLayout;
}

export function drawsQuads(layout: VertexLayout): boolean {
	return match (layout) {
		VertexLayout.Lit => false,
		VertexLayout.Particle => true,
		VertexLayout.Billboard => true,
		VertexLayout.Fullscreen => false,
		VertexLayout.LitTextured => false,
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
// material's colour before lighting (0 leaves it alone, -1 is grey) and, at 1 in
// MATERIAL_DOUBLE_SIDED, lights a back face through its reversed normal; a preset may give the
// other floats a meaning of its own (pixelArtRenderer.ms RAMP_LEVELS).
export const MATERIAL_UNIFORM_SLOT: int32 = 3;
export const MATERIAL_UNIFORM_LENGTH: int32 = 4;
export const MATERIAL_SATURATION: int32 = 1;
export const MATERIAL_DOUBLE_SIDED: int32 = 2;
export const UNLIT_MATERIAL_UNIFORM_LENGTH: int32 = 8;
export const UNLIT_MATERIAL_COLOR: int32 = 4;
// A billboard material's block (binding=2): its colour, then at BILLBOARD_LIGHT 0 to leave the
// lights out (Heaps' `particles3D` material has `light: true`). A preset may give the other
// floats a meaning of its own (pixelArtRenderer.ms BILLBOARD_RAMP_LEVELS).
export const BILLBOARD_UNIFORM_SLOT: int32 = 2;
export const BILLBOARD_UNIFORM_LENGTH: int32 = 8;
export const BILLBOARD_COLOR: int32 = 0;
export const BILLBOARD_LIGHT: int32 = 5;

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
	cache: PipelineCache,
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


export function makeVertexBuffer(data: Readonly<Span<float32>>): uint32 {
	return gpu3dMakeVertexBuffer(data);
}

// Three uint16 per triangle. sokol copies the data, so the Vec it came from may move after.
export function makeIndexBuffer(data: Readonly<Span<uint16>>): uint32 {
	return gpu3dMakeIndexBuffer(data);
}

export function makeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32 {
	return gpu3dMakeImage(rgba, width, height);
}

// An RGBA8 image the CPU rewrites with updateImage; its pixels start undefined.
export function makeDynamicImage(width: int32, height: int32): uint32 {
	return gpu3dMakeDynamicImage(width, height);
}

// sokol allows one update per image per frame, before any pass samples it.
export function updateImage(image: uint32, rgba: Readonly<Span<uint32>>): void {
	gpu3dUpdateImage(image, rgba);
}

export function makeStreamBuffer(length: int32): uint32 {
	return gpu3dMakeStreamBuffer(length as int64);
}

// sokol takes one update per buffer per frame, before the pass that draws it.
export function updateBuffer(buffer: uint32, data: Readonly<Span<float32>>): boolean {
	return gpu3dUpdateBuffer(buffer, data) != 0;
}


export function destroyBuffer(buffer: uint32): void { gpu3dDestroyBuffer(buffer); }
export function destroyImage(image: uint32): void { gpu3dDestroyImage(image); }

export function applyPipeline(pipeline: uint32): void { gpu3dApplyPipeline(pipeline); }

export function applyBindings(bindings: Readonly<Span<uint32>>): void {
	gpu3dApplyBindings(bindings);
}

export function applyUniforms(slot: int32, data: Readonly<Span<float32>>): void {
	gpu3dApplyUniforms(slot, data);
}

export function draw(base: int32, count: int32, instances: int32): void {
	gpu3dDraw(base, count, instances);
}
