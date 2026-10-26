import "../host/gpu";
import { FilterMode, Wrap } from "./state";
import {
	ColorAttachment,
	DepthAttachment,
	PassState,
	PipelineDescriptor,
	PixelFormat,
} from "./doorGpu.ms";

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
	doorMakePipeline,
	doorMakeImage,
	doorMakeImageMips,
	doorMakeCubeImage,
	doorMakeTargetImage,
	doorMakeCubeTargetImage,
	doorMakeCubeAttachmentView,
	doorMakeTextureView,
	doorMakeSampler,
	doorMakeSamplerEx,
	doorAnisotropyPortable,
	doorImageAlive,
	doorViewAlive,
	doorSamplerAlive,
	doorDestroyShader,
	doorDestroyPipeline,
	doorDestroyImage,
	doorDestroyView,
	doorDestroySampler,
	doorBeginPass,
	doorBeginScreenPass,
	doorEndPass,
	doorPassState,
	doorPassAttachesView,
	doorOriginTopLeft,
	doorDepthZeroToOne,
	doorEnvironmentColorFormat,
	doorEnvironmentDepthFormat,
	doorEnvironmentSampleCount,
	doorFormatRenderable,
	doorContextGeneration,
	doorCommit,
	doorFrameIndex,
	doorLiveBuffers,
	doorLiveImages,
	doorLiveViews,
	doorLiveSamplers,
	doorLiveShaders,
	doorLivePipelines,
	DOOR_MAX_COLOR_ATTACHMENTS,
	DOOR_UNIFORM_SLOTS,
} from "./doorGpu.ms";

@include("../host/bridge.h");
extern function voidLoseContext(): void;

export { PixelFormat, LoadAction, StoreAction, PassState } from "./doorGpu.ms";

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

export function layoutPerInstance(layout: int32, buffer: int32): boolean {
	return doorLayoutPerInstance(layout, buffer) != 0;
}

export function makePipeline(descriptor: PipelineDescriptor): uint32 {
	return doorMakePipeline(descriptor);
}

export function makeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32 {
	return doorMakeImage(rgba, width, height);
}

export function makeImageMips(
	rgba: Readonly<Span<uint32>>, width: int32, height: int32, levels: int32,
): uint32 {
	return doorMakeImageMips(rgba, width, height, levels);
}

export function makeTargetImage(width: int32, height: int32, format: PixelFormat): uint32 {
	return doorMakeTargetImage(width, height, format as int32);
}

export function makeCubeImage(rgba: Readonly<Span<uint32>>, size: int32): uint32 {
	return doorMakeCubeImage(rgba, size);
}

export function makeCubeTargetImage(size: int32, levels: int32, format: PixelFormat): uint32 {
	return doorMakeCubeTargetImage(size, levels, format as int32);
}

export function makeCubeAttachmentView(image: uint32, face: int32, level: int32): uint32 {
	return doorMakeCubeAttachmentView(image, face, level);
}

export function makeTextureView(image: uint32): uint32 {
	return doorMakeTextureView(image);
}

export function makeSampler(filter: FilterMode, wrap: Wrap): uint32 {
	return doorMakeSampler(filter as int32, wrap as int32);
}

export function anisotropyPortable(): boolean { return doorAnisotropyPortable() != 0; }

// Ordinals of FilterMode, TextureMipFilter and Wrap (void3d/textureMip.ms `doorCall`).
export function makeSamplerEx(
	minFilter: int32, magFilter: int32, mipFilter: int32, wrapU: int32, wrapV: int32,
	minLod: float32, maxLod: float32, maxAnisotropy: int32,
): uint32 {
	return doorMakeSamplerEx(
		minFilter, magFilter, mipFilter, wrapU, wrapV, minLod, maxLod, maxAnisotropy,
	);
}

export function imageAlive(image: uint32): boolean { return doorImageAlive(image) != 0; }
export function viewAlive(view: uint32): boolean { return doorViewAlive(view) != 0; }
export function samplerAlive(sampler: uint32): boolean { return doorSamplerAlive(sampler); }

export function destroyShader(shader: uint32): void { doorDestroyShader(shader); }
export function destroyPipeline(pipeline: uint32): void { doorDestroyPipeline(pipeline); }
export function destroyImage(image: uint32): void { doorDestroyImage(image); }
export function destroyView(view: uint32): void { doorDestroyView(view); }
export function destroySampler(sampler: uint32): void { doorDestroySampler(sampler); }

export function passState(): PassState {
	return doorPassState() as PassState;
}

export function passAttachesView(view: uint32): boolean {
	return doorPassAttachesView(view);
}

export function beginPassWith(
	colors: Readonly<Span<ColorAttachment>>, depth: DepthAttachment,
): void {
	doorBeginPass(colors, depth);
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
	return doorDepthZeroToOne();
}

export function environmentColorFormat(): PixelFormat {
	return doorEnvironmentColorFormat();
}

export function environmentDepthFormat(): PixelFormat {
	return doorEnvironmentDepthFormat();
}

export function environmentSampleCount(): int32 {
	return doorEnvironmentSampleCount();
}

// Whether this device can draw into a target of this format; Rgba16f needs a color-buffer-float
// extension on GLES3 and WebGL2 (sokol_gfx.h _sg_gl_init_pixelformats_half_float).
export function formatRenderable(format: PixelFormat): boolean {
	return doorFormatRenderable(format as int32);
}

export function contextGeneration(): int32 {
	return doorContextGeneration();
}

export function loseContext(): void {
	voidLoseContext();
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
