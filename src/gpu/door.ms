import "../sokol/gpu";
import { FilterMode, Wrap } from "./state";

import {
	doorMakeShader,
	doorUniformSlotMask,
	doorUniformBlockBytes,
	doorTextureSlotMask,
	doorSamplerSlotMask,
	doorLayoutFloats,
	doorLayoutPerInstance,
	doorProgramLayout,
	doorMakeTargetImage,
	doorMakeAttachmentView,
	doorMakeTextureView,
	doorMakeSampler,
	doorDestroyShader,
	doorDestroyPipeline,
	doorDestroyImage,
	doorDestroyView,
	doorDestroySampler,
	doorBeginScreenPass,
	doorEndPass,
	doorPassState,
	doorOriginTopLeft,
	doorDepthZeroToOne,
	doorContextGeneration,
	doorFrameIndex,
	doorLiveBuffers,
	DOOR_MAX_COLOR_ATTACHMENTS,
	DOOR_MAX_PROGRAMS,
	DOOR_MAX_LAYOUTS,
	DOOR_UNIFORM_SLOTS,
} from "./door.h";

// The functions that take arrays are declared here instead: an `extern` Span<T> parameter
// lowers to the (pointer, int64 length) pair door.h declares. Importing them from the header
// maps the pointer to Borrow<T>, and on msc 0.2.53 `span[0]` passed there is the address of a
// one-element copy (docs/VOID3D.md, Compiler notes).
extern function doorMakePipeline(descriptor: Span<uint32>): uint32;
extern function doorBeginPass(descriptor: Span<uint32>, clear: Span<float32>): void;

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

// Which pass the door has open; read by the render layers to stop misuse naming the call.
export enum PassState {
	None,
	Target,
	Screen,
}

export const UNIFORM_SLOTS: int32 = DOOR_UNIFORM_SLOTS;
export const MAX_COLOR_ATTACHMENTS: int32 = DOOR_MAX_COLOR_ATTACHMENTS;
export const MAX_PROGRAMS: int32 = DOOR_MAX_PROGRAMS;
export const MAX_LAYOUTS: int32 = DOOR_MAX_LAYOUTS;

// A registered program, by id: what a PipelineKey holds and materials name through their
// layer's own enum.
export function makeShader(program: int32): uint32 {
	return doorMakeShader(program);
}

export function uniformSlotMask(program: int32): uint32 {
	return doorUniformSlotMask(program);
}

// Bytes of the block `program` declares at `slot`, 0 for none, read off its shader desc.
export function uniformBlockBytes(program: int32, slot: int32): int32 {
	return doorUniformBlockBytes(program, slot);
}

// Bit n set when `program` samples a texture at view slot n (textureSlotMask) or declares
// sampler slot n (samplerSlotMask), read off its shader desc.
export function textureSlotMask(program: int32): uint32 {
	return doorTextureSlotMask(program);
}

export function samplerSlotMask(program: int32): uint32 {
	return doorSamplerSlotMask(program);
}

// The layout a registered program reads; the registration's own answer.
export function programLayout(program: int32): int32 {
	return doorProgramLayout(program);
}

// Floats per element of vertex buffer `buffer` of the registered layout `layout`.
export function layoutFloats(layout: int32, buffer: int32): int32 {
	return doorLayoutFloats(layout, buffer);
}

export function layoutPerInstance(layout: int32): boolean {
	return doorLayoutPerInstance(layout) != 0;
}

export function makePipeline(descriptor: Span<uint32>): uint32 {
	return doorMakePipeline(descriptor);
}

export function makeTargetImage(width: int32, height: int32, format: PixelFormat): uint32 {
	return doorMakeTargetImage(width, height, format as int32);
}

export function makeAttachmentView(image: uint32, format: PixelFormat): uint32 {
	return doorMakeAttachmentView(image, format as int32);
}

export function makeTextureView(image: uint32): uint32 {
	return doorMakeTextureView(image);
}

export function makeSampler(filter: FilterMode, wrap: Wrap): uint32 {
	return doorMakeSampler(filter as int32, wrap as int32);
}

export function destroyShader(shader: uint32): void { doorDestroyShader(shader); }
export function destroyPipeline(pipeline: uint32): void { doorDestroyPipeline(pipeline); }
export function destroyImage(image: uint32): void { doorDestroyImage(image); }
export function destroyView(view: uint32): void { doorDestroyView(view); }
export function destroySampler(sampler: uint32): void { doorDestroySampler(sampler); }

export function passState(): PassState {
	return doorPassState() as PassState;
}

// sokol cannot nest passes, so every begin stops while one is open, and endPass stops when
// none is; the message names the call, as void3d's and void2d's stops do.
export function beginPassWith(descriptor: Span<uint32>, clear: Span<float32>): void {
	if (doorPassState() != 0) {
		console.log("gpu door: beginPass with a pass already open; endPass ends it");
		unreachable;
	}
	doorBeginPass(descriptor, clear);
}

export function beginScreenPassWith(
	red: float32,
	green: float32,
	blue: float32,
	alpha: float32,
): void {
	if (doorPassState() != 0) {
		console.log("gpu door: beginScreenPass with a pass already open; endPass ends it");
		unreachable;
	}
	doorBeginScreenPass(red, green, blue, alpha);
}

export function endPass(): void {
	if (doorPassState() == 0) {
		console.log("gpu door: endPass with no pass open");
		unreachable;
	}
	doorEndPass();
}

// Framebuffer and texture rows start at the top (D3D11, Metal) rather than the bottom (GL).
export function originTopLeft(): boolean {
	return doorOriginTopLeft() != 0;
}

// The depth buffer holds clip z as is (0..1); GL stores (z + 1) / 2 instead.
export function depthZeroToOne(): boolean {
	return doorDepthZeroToOne() != 0;
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
