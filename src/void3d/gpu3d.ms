// void3d GPU bridge, MetaScript side. gpu3d.c only turns flat arrays into sokol descriptor
// structs; everything that decides what to build and when lives above this file.
//
// Enum members are sent to C as ordinals and mapped by tables in gpu3d.c, so a member added
// here must be added there in the same position. Handles are sokol ids as uint32, 0 = none.
// The descriptor layouts (GPU3D_PIPELINE_*, GPU3D_PASS_*, GPU3D_BINDING_*) come from gpu3d.h.

import {
	gpu3dMakeShader,
	gpu3dMakeTargetImage,
	gpu3dMakeAttachmentView,
	gpu3dMakeTextureView,
	gpu3dMakeSampler,
	gpu3dMakeDynamicImage,
	gpu3dDestroyShader,
	gpu3dDestroyPipeline,
	gpu3dDestroyBuffer,
	gpu3dDestroyImage,
	gpu3dDestroyView,
	gpu3dDestroySampler,
	gpu3dBeginSwapchainPass,
	gpu3dApplyPipeline,
	gpu3dDraw,
	gpu3dEndPass,
	gpu3dCommit,
	gpu3dOriginTopLeft,
	gpu3dDepthZeroToOne,
	gpu3dContextGeneration,
} from "./gpu3d.h";

// The functions that take arrays are declared here instead: an `extern` Span<T> parameter
// lowers to the (pointer, int64 length) pair gpu3d.h declares. Importing them from the header
// maps the pointer to Borrow<T>, and on msc 0.2.53 `span[0]` passed there is the address of a
// one-element copy (docs/VOID3D.md, Compiler notes).
extern function gpu3dMakePipeline(descriptor: Span<uint32>): uint32;
extern function gpu3dMakeVertexBuffer(data: Span<float32>): uint32;
extern function gpu3dMakeImage(rgba: Span<uint32>, width: int32, height: int32): uint32;
extern function gpu3dBeginPass(descriptor: Span<uint32>, clear: Span<float32>): void;
extern function gpu3dApplyBindings(bindings: Span<uint32>): void;
extern function gpu3dApplyUniforms(slot: int32, data: Span<float32>): void;
extern function gpu3dUpdateImage(image: uint32, rgba: Span<uint32>): void;

// One per @program in shader3d.glsl; gpu3d.c maps each to its *_shader_desc.
export enum Program {
	Lit,
	Billboard,
	Post,
	Blit,
}

// Vertex buffer layouts gpu3d.c knows how to describe (describeLayout).
export enum VertexLayout {
	Lit,
	Billboard,
	Fullscreen,
}

// Default is the swapchain's own format (sokol's 0), for pipelines drawn to the screen.
export enum PixelFormat {
	None,
	Default,
	Rgba8,
	Depth,
}

export enum LoadAction {
	Clear,
	Load,
	DontCare,
}

// h3d.mat.Data.Filter / Wrap, the members sokol has.
export enum Filter {
	Nearest,
	Linear,
}

export enum Wrap {
	Clamp,
	Repeat,
	Mirror,
}

// Uniform block slots and sizes in floats, from the `binding=` blocks in shader3d.glsl.
export const VERTEX_UNIFORM_SLOT: int32 = 0;
export const VERTEX_UNIFORM_LENGTH: int32 = 24;
export const LIGHT_UNIFORM_SLOT: int32 = 1;
export const LIGHT_UNIFORM_LENGTH: int32 = 20;
export const POST_UNIFORM_SLOT: int32 = 0;
export const POST_UNIFORM_LENGTH: int32 = 20;
export const BLIT_UNIFORM_SLOT: int32 = 0;
export const BLIT_UNIFORM_LENGTH: int32 = 4;

export function makeShader(program: Program): uint32 {
	return gpu3dMakeShader(program as int32);
}

export function makePipeline(descriptor: Span<uint32>): uint32 {
	return gpu3dMakePipeline(descriptor);
}

export function makeVertexBuffer(data: Span<float32>): uint32 {
	return gpu3dMakeVertexBuffer(data);
}

export function makeImage(rgba: Span<uint32>, width: int32, height: int32): uint32 {
	return gpu3dMakeImage(rgba, width, height);
}

export function makeTargetImage(width: int32, height: int32, format: PixelFormat): uint32 {
	return gpu3dMakeTargetImage(width, height, format as int32);
}

export function makeAttachmentView(image: uint32, format: PixelFormat): uint32 {
	return gpu3dMakeAttachmentView(image, format as int32);
}

export function makeTextureView(image: uint32): uint32 {
	return gpu3dMakeTextureView(image);
}

export function makeSampler(filter: Filter, wrap: Wrap): uint32 {
	return gpu3dMakeSampler(filter as int32, wrap as int32);
}

// An RGBA8 image the CPU rewrites with updateImage; its pixels start undefined.
export function makeDynamicImage(width: int32, height: int32): uint32 {
	return gpu3dMakeDynamicImage(width, height);
}

// sokol allows one update per image per frame, before any pass samples it.
export function updateImage(image: uint32, rgba: Span<uint32>): void {
	gpu3dUpdateImage(image, rgba);
}

// Framebuffer and texture rows start at the top (D3D11, Metal) rather than the bottom (GL).
export function originTopLeft(): boolean {
	return gpu3dOriginTopLeft() != 0;
}

// The depth buffer holds clip z as is (0..1); GL stores (z + 1) / 2 instead.
export function depthZeroToOne(): boolean {
	return gpu3dDepthZeroToOne() != 0;
}

// Counts GPU contexts: it changes when the host lost the context and made a new one, and every
// handle from before is then stale (docs/VOID3D.md, Android lifecycle). Only the Android
// bridge ever loses its context.
export function contextGeneration(): int32 {
	return gpu3dContextGeneration();
}

export function destroyShader(shader: uint32): void { gpu3dDestroyShader(shader); }
export function destroyPipeline(pipeline: uint32): void { gpu3dDestroyPipeline(pipeline); }
export function destroyBuffer(buffer: uint32): void { gpu3dDestroyBuffer(buffer); }
export function destroyImage(image: uint32): void { gpu3dDestroyImage(image); }
export function destroyView(view: uint32): void { gpu3dDestroyView(view); }
export function destroySampler(sampler: uint32): void { gpu3dDestroySampler(sampler); }

export function beginPassWith(descriptor: Span<uint32>, clear: Span<float32>): void {
	gpu3dBeginPass(descriptor, clear);
}

export function beginSwapchainPass(
	red: float32,
	green: float32,
	blue: float32,
	alpha: float32,
): void {
	gpu3dBeginSwapchainPass(red, green, blue, alpha);
}

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

export function endPass(): void { gpu3dEndPass(); }
export function commit(): void { gpu3dCommit(); }
