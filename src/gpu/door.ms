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
	doorProgramCount,
	doorMakeTargetImage,
	doorMakeAttachmentView,
	doorMakeTextureView,
	doorMakeSampler,
	doorImageAlive,
	doorViewAlive,
	doorSamplerAlive,
	doorDestroyShader,
	doorDestroyPipeline,
	doorDestroyImage,
	doorDestroyView,
	doorDestroySampler,
	doorBeginScreenPass,
	doorEndPass,
	doorCommit,
	doorPassState,
	doorPassAttachesView,
	doorOriginTopLeft,
	doorDepthZeroToOne,
	doorEnvironmentColorFormat,
	doorEnvironmentDepthFormat,
	doorEnvironmentSampleCount,
	doorContextGeneration,
	doorFrameIndex,
	doorLiveBuffers,
	doorLiveImages,
	doorLiveViews,
	doorLiveSamplers,
	doorLiveShaders,
	doorLivePipelines,
	DOOR_MAX_COLOR_ATTACHMENTS,
	DOOR_UNIFORM_SLOTS,
} from "./door.h";

// The functions that take arrays are declared here instead: an `extern` Span<T> parameter
// lowers to the (pointer, int64 length) pair door.h declares. Importing them from the header
// maps the pointer to Borrow<T>, and on msc 0.2.53 `span[0]` passed there is the address of a
// one-element copy (docs/VOID3D.md, Compiler notes).
extern function doorMakePipeline(descriptor: Readonly<Span<uint32>>): uint32;
extern function doorBeginPass(
	descriptor: Readonly<Span<uint32>>, clear: Readonly<Span<float32>>,
): void;

// Default is the swapchain's own format (sokol's 0), for pipelines drawn to the screen.
export enum PixelFormat {
	None,
	Default,
	Rgba8,
	Depth,
	Bgra8,
	DepthStencil,
}

export enum LoadAction {
	Clear,
	Load,
	DontCare,
}

// sokol's default for a depth attachment is DontCare, which Metal and WebGPU discard at the end
// of the pass (sokol_gfx.h _sg_pass_action_defaults): a depth read later needs Store.
export enum StoreAction {
	Store,
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

export function programCount(): int32 {
	return doorProgramCount();
}

// Floats per element of vertex buffer `buffer` of the registered layout `layout`.
export function layoutFloats(layout: int32, buffer: int32): int32 {
	return doorLayoutFloats(layout, buffer);
}

export function layoutPerInstance(layout: int32): boolean {
	return doorLayoutPerInstance(layout) != 0;
}

export function makePipeline(descriptor: Readonly<Span<uint32>>): uint32 {
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

export function imageAlive(image: uint32): boolean { return doorImageAlive(image) != 0; }
export function viewAlive(view: uint32): boolean { return doorViewAlive(view) != 0; }
export function samplerAlive(sampler: uint32): boolean { return doorSamplerAlive(sampler) != 0; }

export function destroyShader(shader: uint32): void { doorDestroyShader(shader); }
export function destroyPipeline(pipeline: uint32): void { doorDestroyPipeline(pipeline); }
export function destroyImage(image: uint32): void { doorDestroyImage(image); }
export function destroyView(view: uint32): void { doorDestroyView(view); }
export function destroySampler(sampler: uint32): void { doorDestroySampler(sampler); }

export function passState(): PassState {
	return doorPassState() as PassState;
}

export function passAttachesView(view: uint32): boolean {
	return doorPassAttachesView(view) != 0;
}

export function beginPassWith(
	descriptor: Readonly<Span<uint32>>, clear: Readonly<Span<float32>>,
): void {
	doorBeginPass(descriptor, clear);
}

export function beginScreenPassWith(
	red: float32,
	green: float32,
	blue: float32,
	alpha: float32,
): void {
	doorBeginScreenPass(red, green, blue, alpha);
}

export function endPass(): void {
	doorEndPass();
}

export function commit(): void {
	doorCommit();
}

// Framebuffer and texture rows start at the top (D3D11, Metal) rather than the bottom (GL).
export function originTopLeft(): boolean {
	return doorOriginTopLeft() != 0;
}

// The depth buffer holds clip z as is (0..1); GL stores (z + 1) / 2 instead.
export function depthZeroToOne(): boolean {
	return doorDepthZeroToOne() != 0;
}

export function environmentColorFormat(): PixelFormat {
	return doorEnvironmentColorFormat() as PixelFormat;
}

export function environmentDepthFormat(): PixelFormat {
	return doorEnvironmentDepthFormat() as PixelFormat;
}

export function environmentSampleCount(): int32 {
	return doorEnvironmentSampleCount();
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

export function liveImages(): int32 {
	return doorLiveImages();
}

export function liveViews(): int32 {
	return doorLiveViews();
}

export function liveSamplers(): int32 {
	return doorLiveSamplers();
}

export function liveShaders(): int32 {
	return doorLiveShaders();
}

export function livePipelines(): int32 {
	return doorLivePipelines();
}
