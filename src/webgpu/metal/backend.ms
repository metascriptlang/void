import { Pool, allocate, alive, live, liveIds, newPool, release, reset, slotIndex, store } from "../pool.ms";
import {
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	GPUAdapterInfo,
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBindGroupLayout,
	GPUBlendComponent,
	GPUBuffer,
	GPUBufferDescriptor,
	GPUBufferUsage,
	GPUCanvasConfiguration,
	GPUColor,
	GPUColorWrite,
	GPUCommandBuffer,
	GPUCommandEncoder,
	GPUPrimitiveState,
	GPUQuerySet,
	GPUQuerySetDescriptor,
	GPUSupportedFeatures,
	GPUSupportedLimits,
	GPUComputePassDescriptor,
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUComputePipelineDescriptor,
	GPUDevice,
	GPUExtent3D,
	GPUIndexFormat,
	GPULiveCounts,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderAttribute,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilFaceState,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	checkedSamplerAnisotropy,
	checkedViewport,
	checkedSamplerLod,
	checkedTexelWritePitch,
	stopOnUnportedBindEntry,
	stopOnUnportedTexelWrite,
	stopOnUnportedRenderPass,
	stopOnUnportedShaderModule,
	stopOnUnportedTexture,
	stopOnUnportedView,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
} from "../types.ms";
import {
	MtlBufferImpl,
	MtlCommandBufferImpl,
	MtlDepthStateImpl,
	MtlDeviceImpl,
	MtlEncoderImpl,
	MtlFunctionImpl,
	MtlLibraryImpl,
	MtlPipelineImpl,
	MtlQueueImpl,
	MtlSamplerImpl,
	MtlTextureImpl,
	mtlBeginCommandBuffer,
	mtlBeginPass,
	mtlCommit,
	mtlDeviceFrom,
	mtlDraw,
	mtlDrawIndexed,
	mtlEndPass,
	mtlErrorLog,
	mtlFrameSemaphoreCreate,
	mtlFrameSemaphoreWaitAll,
	mtlNewBuffer,
	mtlNewCommandQueue,
	mtlNewDepthState,
	mtlNewFunction,
	mtlNewLibrary,
	mtlNewPipeline,
	mtlNewSampler,
	mtlNewTexture,
	mtlPassColor,
	mtlPassDepth,
	mtlPassReset,
	mtlPipelineAttribute,
	mtlPipelineColor,
	mtlPipelineLayout,
	mtlPipelineReset,
	mtlPresentDrawable,
	mtlQueueNative,
	mtlReleaseBuffer,
	mtlReleaseDepthState,
	mtlReleaseDevice,
	mtlReleaseFunction,
	mtlReleaseLibrary,
	mtlReleasePipeline,
	mtlReleaseQueue,
	mtlReleaseSampler,
	mtlReleaseTexture,
	mtlSetBlendColor,
	mtlSetFragmentBuffer,
	mtlSetFragmentBufferOffset,
	mtlSetFragmentSampler,
	mtlSetFragmentTexture,
	mtlSetPipeline,
	mtlSetStencilReference,
	mtlSetScissorRect,
	mtlSetVertexBuffer,
	mtlSetVertexBufferOffset,
	mtlSetVertexSampler,
	mtlSetVertexTexture,
	mtlSetViewport,
	mtlSupportsSampleCount,
	mtlTextureFrom,
	mtlTextureNative,
	mtlUsesSharedStorage,
	mtlWriteBuffer,
	mtlWriteTexture,
} from "./metal.h";

@compile("./metal.m");
@passL("-framework Metal");
@passL("-framework QuartzCore");
@passL("-framework Foundation");

export struct NativeEnvironment {
	device: Ptr<void> | null;
	context: Ptr<void> | null;
	colorFormat: GPUTextureFormat;
	depthFormat: GPUTextureFormat;
	sampleCount: int32;
}
export struct NativeSwapchain {
	width: int32;
	height: int32;
	sampleCount: int32;
	renderView: Ptr<void> | null;
	resolveView: Ptr<void> | null;
	depthStencilView: Ptr<void> | null;
}

const FRAMES_IN_FLIGHT = 2;
const UNIFORM_OFFSET_ALIGNMENT = 256;
const MAX_STAGE_UNIFORM_BUFFERS = 8;
const MAX_STAGE_TEXTURES = 32;
const MAX_STAGE_SAMPLERS = 12;
const VERTEX_BUFFER_BASE = 23;

const PIXEL_INVALID = 0;
const PIXEL_R8_UNORM = 10;
const PIXEL_RGBA8_UNORM = 70;
const PIXEL_BGRA8_UNORM = 80;
const PIXEL_RGBA16_FLOAT = 115;
const PIXEL_DEPTH32_FLOAT = 252;
const PIXEL_DEPTH32_FLOAT_STENCIL8 = 260;

const VERTEX_UCHAR4_NORMALIZED = 9;
const VERTEX_FLOAT = 28;
const VERTEX_FLOAT2 = 29;
const VERTEX_FLOAT3 = 30;
const VERTEX_FLOAT4 = 31;

const BLEND_ZERO = 0;
const BLEND_ONE = 1;
const BLEND_SRC_COLOR = 2;
const BLEND_ONE_MINUS_SRC_COLOR = 3;
const BLEND_SRC_ALPHA = 4;
const BLEND_ONE_MINUS_SRC_ALPHA = 5;
const BLEND_DST_COLOR = 6;
const BLEND_ONE_MINUS_DST_COLOR = 7;
const BLEND_DST_ALPHA = 8;
const BLEND_ONE_MINUS_DST_ALPHA = 9;
const BLEND_SRC_ALPHA_SATURATED = 10;
const BLEND_COLOR = 11;
const BLEND_ONE_MINUS_COLOR = 12;

const WRITE_RED = 0x8;
const WRITE_GREEN = 0x4;
const WRITE_BLUE = 0x2;
const WRITE_ALPHA = 0x1;

const CULL_NONE = 0;
const CULL_FRONT = 1;
const CULL_BACK = 2;
const WINDING_CLOCKWISE = 0;
const WINDING_COUNTER_CLOCKWISE = 1;
const FILTER_NEAREST = 0;
const FILTER_LINEAR = 1;
const MIP_FILTER_NEAREST = 1;
const MIP_FILTER_LINEAR = 2;
const MAX_ANISOTROPY = 16;
const ADDRESS_CLAMP_TO_EDGE = 0;
const ADDRESS_REPEAT = 2;
const ADDRESS_MIRROR_REPEAT = 3;
const INDEX_UINT16 = 0;
const INDEX_UINT32 = 1;
const NO_STRIP_INDEX = -1;
const PRIMITIVE_LINE_STRIP = 2;
const PRIMITIVE_TRIANGLE = 3;
const PRIMITIVE_TRIANGLE_STRIP = 4;
const LOAD_LOAD = 1;
const LOAD_CLEAR = 2;
const STORE_DONT_CARE = 0;
const STORE_STORE = 1;
const STORE_RESOLVE = 2;
const STORE_STORE_AND_RESOLVE = 3;
const STENCIL_MASK_ALL: uint32 = 0xFFFFFFFF;
const COMPARE_NEVER = 0;
const COMPARE_ALWAYS = 7;

const NO_BUFFER = null as unknown as Ptr<MtlBufferImpl>;
const NO_TEXTURE = null as unknown as Ptr<MtlTextureImpl>;
const NO_COMMAND_BUFFER = null as unknown as Ptr<MtlCommandBufferImpl>;
const NO_ENCODER = null as unknown as Ptr<MtlEncoderImpl>;

enum BindingKind {
	Uniform,
	Texture,
	Sampler,
}

struct FormatInfo {
	pixel: int32;
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
}

struct BufferSlot {
	id: uint32;
	size: int64;
	natives: Ptr<MtlBufferImpl>[2];
	active: int32;
	writtenFrame: int64;
	writtenEnd: int64;
}

struct TextureSlot {
	id: uint32;
	width: int32;
	height: int32;
	format: GPUTextureFormat;
	usage: int32;
	sampleCount: int32;
	natives: Ptr<MtlTextureImpl>[2];
	active: int32;
	writtenFrame: int64;
	swapchainView: uint32;
}

struct ViewSlot {
	id: uint32;
	texture: uint32;
	swapchain: boolean;
	swapchainTexture: Ptr<MtlTextureImpl>;
	swapchainResolve: Ptr<MtlTextureImpl>;
}

struct SamplerSlot {
	id: uint32;
	native: Ptr<MtlSamplerImpl>;
}

struct NativeBinding {
	binding: int32;
	kind: BindingKind;
	vertexStage: boolean;
	nativeSlot: int32;
	size: int32;
}

struct ShaderSlot {
	id: uint32;
	vertexLibrary: Ptr<MtlLibraryImpl>;
	fragmentLibrary: Ptr<MtlLibraryImpl>;
	vertex: Ptr<MtlFunctionImpl>;
	fragment: Ptr<MtlFunctionImpl>;
	uniforms: NativeBinding[8];
	uniformCount: int32;
	resources: NativeBinding[8];
	resourceCount: int32;
	attributes: GPUShaderAttribute[16];
}

struct PipelineSlot {
	id: uint32;
	shader: uint32;
	state: Ptr<MtlPipelineImpl>;
	depth: Ptr<MtlDepthStateImpl>;
	cullMode: int32;
	winding: int32;
	depthBias: float32;
	depthBiasSlope: float32;
	depthBiasClamp: float32;
	primitive: int32;
	stripIndexType: int32;
	strides: int32[2];
	layouts: uint32[2];
}

struct LayoutSlot {
	id: uint32;
	pipeline: uint32;
	group: int32;
}

struct BindGroupSlot {
	id: uint32;
	group: int32;
	entries: GPUBindGroupEntry[8];
	entryCount: int32;
	dynamicIndex: int32[8];
	dynamicCount: int32;
}

struct PassState {
	active: boolean;
	width: int32;
	height: int32;
	screen: boolean;
}

struct BoundState {
	pipeline: uint32;
	appliedPipeline: uint32;
	vertexBuffers: uint32[2];
	vertexOffsets: int64[2];
	indexBuffer: uint32;
	indexType: int32;
	indexBytes: int64;
	indexOffset: int64;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[8];
	vertexDirty: boolean;
	resourcesDirty: boolean;
	uniformsDirty: boolean;
}

let device: Ptr<MtlDeviceImpl> = null as unknown as Ptr<MtlDeviceImpl>;
let queue: Ptr<MtlQueueImpl> = null as unknown as Ptr<MtlQueueImpl>;
let sharedStorage = true;
let commandBuffer: Ptr<MtlCommandBufferImpl> = NO_COMMAND_BUFFER;
let encoder: Ptr<MtlEncoderImpl> = NO_ENCODER;
let frame: int64 = 0;
let pass: PassState = { active: false };
let bound: BoundState = { pipeline: 0 };
let passVertexUniforms: Vec<Ptr<MtlBufferImpl>> = [];
let passFragmentUniforms: Vec<Ptr<MtlBufferImpl>> = [];
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "bgra8unorm", depthFormat: "depth32float", sampleCount: 1 };


let buffers: Pool<BufferSlot> = newPool<BufferSlot>("metal", "GPUBuffer", "buffer", { id: 0 });
let textures: Pool<TextureSlot> = newPool<TextureSlot>("metal", "GPUTexture", "texture", { id: 0 });
let views: Pool<ViewSlot> = newPool<ViewSlot>("metal", "GPUTextureView", "view", { id: 0 });
let samplers: Pool<SamplerSlot> = newPool<SamplerSlot>("metal", "GPUSampler", "sampler", { id: 0 });
let shaders: Pool<ShaderSlot> = newPool<ShaderSlot>("metal", "GPUShaderModule", "shader module", { id: 0 });
let pipelines: Pool<PipelineSlot> = newPool<PipelineSlot>("metal", "GPURenderPipeline", "render pipeline", { id: 0 });
let layouts: Pool<LayoutSlot> = newPool<LayoutSlot>("metal", "GPUBindGroupLayout", "bind group layout", { id: 0 });
let bindGroups: Pool<BindGroupSlot> = newPool<BindGroupSlot>("metal", "GPUBindGroup", "bind group", { id: 0 });

function stop(message: string): void {
	console.log(`webgpu metal: ${message}`);
	unreachable;
}

function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu metal: ${member} '${value}' is not supported`);
	unreachable;
}

function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu metal: ${member} '${value}' is not supported`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => ({ pixel: PIXEL_R8_UNORM, bytesPerPixel: 1, depth: false, stencil: false }),
		"rgba8unorm" => ({ pixel: PIXEL_RGBA8_UNORM, bytesPerPixel: 4, depth: false, stencil: false }),
		"bgra8unorm" => ({ pixel: PIXEL_BGRA8_UNORM, bytesPerPixel: 4, depth: false, stencil: false }),
		"rgba16float" => ({ pixel: PIXEL_RGBA16_FLOAT, bytesPerPixel: 8, depth: false, stencil: false }),
		"depth32float" => ({ pixel: PIXEL_DEPTH32_FLOAT, bytesPerPixel: 4, depth: true, stencil: false }),
		"depth24plus-stencil8" => ({ pixel: PIXEL_DEPTH32_FLOAT_STENCIL8, bytesPerPixel: 8, depth: true, stencil: true }),
		_ => stopOnFormat(member, value),
	};
}

function compareFunction(compare: string, member: string): int32 {
	return match (compare) {
		"never" => 0,
		"less" => 1,
		"equal" => 2,
		"less-equal" => 3,
		"greater" => 4,
		"not-equal" => 5,
		"greater-equal" => 6,
		"" | "always" => COMPARE_ALWAYS,
		_ => stopOnMember(member, compare),
	};
}

function cullMode(cull: string): int32 {
	return match (cull) {
		"" | "none" => CULL_NONE,
		"front" => CULL_FRONT,
		"back" => CULL_BACK,
		_ => stopOnMember("primitive.cullMode", cull),
	};
}

function winding(face: string): int32 {
	return match (face) {
		"" | "ccw" => WINDING_COUNTER_CLOCKWISE,
		"cw" => WINDING_CLOCKWISE,
		_ => stopOnMember("primitive.frontFace", face),
	};
}

function blendFactor(factor: string, member: string): int32 {
	return match (factor) {
		"zero" => BLEND_ZERO,
		"" | "one" => BLEND_ONE,
		"src" => BLEND_SRC_COLOR,
		"one-minus-src" => BLEND_ONE_MINUS_SRC_COLOR,
		"src-alpha" => BLEND_SRC_ALPHA,
		"one-minus-src-alpha" => BLEND_ONE_MINUS_SRC_ALPHA,
		"dst" => BLEND_DST_COLOR,
		"one-minus-dst" => BLEND_ONE_MINUS_DST_COLOR,
		"dst-alpha" => BLEND_DST_ALPHA,
		"one-minus-dst-alpha" => BLEND_ONE_MINUS_DST_ALPHA,
		"src-alpha-saturated" => BLEND_SRC_ALPHA_SATURATED,
		"constant" => BLEND_COLOR,
		"one-minus-constant" => BLEND_ONE_MINUS_COLOR,
		_ => stopOnMember(member, factor),
	};
}

function destinationFactor(factor: string, member: string): int32 {
	const value: string = factor;
	if (value == "") { return BLEND_ZERO; }
	return blendFactor(value, member);
}

function blendOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "add" => 0,
		"subtract" => 1,
		"reverse-subtract" => 2,
		"min" => 3,
		"max" => 4,
		_ => stopOnMember(member, operation),
	};
}

function stencilOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "keep" => 0,
		"zero" => 1,
		"replace" => 2,
		"increment-clamp" => 3,
		"decrement-clamp" => 4,
		"invert" => 5,
		"increment-wrap" => 6,
		"decrement-wrap" => 7,
		_ => stopOnMember(member, operation),
	};
}

function colorWriteMask(mask: int32): int32 {
	const bits = mask == 0 ? GPUColorWrite.ALL as int32 : mask;
	let native = 0;
	if (has(bits, GPUColorWrite.RED as int32)) { native |= WRITE_RED; }
	if (has(bits, GPUColorWrite.GREEN as int32)) { native |= WRITE_GREEN; }
	if (has(bits, GPUColorWrite.BLUE as int32)) { native |= WRITE_BLUE; }
	if (has(bits, GPUColorWrite.ALPHA as int32)) { native |= WRITE_ALPHA; }
	return native;
}

function vertexFormat(format: string): int32 {
	return match (format) {
		"uint8x2" => 1,
		"uint8x4" => 3,
		"sint8x2" => 4,
		"sint8x4" => 6,
		"unorm8x2" => 7,
		"unorm8x4" => VERTEX_UCHAR4_NORMALIZED,
		"snorm8x2" => 10,
		"snorm8x4" => 12,
		"uint16x2" => 13,
		"uint16x4" => 15,
		"sint16x2" => 16,
		"sint16x4" => 18,
		"unorm16x2" => 19,
		"unorm16x4" => 21,
		"snorm16x2" => 22,
		"snorm16x4" => 24,
		"float16x2" => 25,
		"float16x4" => 27,
		"float32" => VERTEX_FLOAT,
		"float32x2" => VERTEX_FLOAT2,
		"float32x3" => VERTEX_FLOAT3,
		"float32x4" => VERTEX_FLOAT4,
		"sint32" => 32,
		"sint32x2" => 33,
		"sint32x3" => 34,
		"sint32x4" => 35,
		"uint32" => 36,
		"uint32x2" => 37,
		"uint32x3" => 38,
		"uint32x4" => 39,
		_ => stopOnMember("vertex attribute format", format),
	};
}

function addressMode(mode: string, member: string): int32 {
	return match (mode) {
		"" | "clamp-to-edge" => ADDRESS_CLAMP_TO_EDGE,
		"repeat" => ADDRESS_REPEAT,
		"mirror-repeat" => ADDRESS_MIRROR_REPEAT,
		_ => stopOnMember(member, mode),
	};
}

function filterMode(filter: string, member: string): int32 {
	return match (filter) {
		"" | "nearest" => FILTER_NEAREST,
		"linear" => FILTER_LINEAR,
		_ => stopOnMember(member, filter),
	};
}

function mipFilterMode(filter: string, member: string): int32 {
	return match (filter) {
		"" | "nearest" => MIP_FILTER_NEAREST,
		"linear" => MIP_FILTER_LINEAR,
		_ => stopOnMember(member, filter),
	};
}

function primitiveType(topology: string): int32 {
	return match (topology) {
		"point-list" => 0,
		"line-list" => 1,
		"line-strip" => PRIMITIVE_LINE_STRIP,
		"" | "triangle-list" => PRIMITIVE_TRIANGLE,
		"triangle-strip" => PRIMITIVE_TRIANGLE_STRIP,
		_ => stopOnMember("primitive.topology", topology),
	};
}

function stripIndexTypeOf(state: GPUPrimitiveState, primitive: int32): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return NO_STRIP_INDEX; }
	if (primitive != PRIMITIVE_LINE_STRIP && primitive != PRIMITIVE_TRIANGLE_STRIP) {
		stop(`primitive.stripIndexFormat '${format}' needs a strip topology`);
	}
	return indexType(state.stripIndexFormat);
}

function indexType(format: GPUIndexFormat): int32 {
	const value: string = format;
	return match (value) {
		"uint16" => INDEX_UINT16,
		"uint32" => INDEX_UINT32,
		_ => stopOnMember("setIndexBuffer indexFormat", value),
	};
}

function bindingKind(kind: string): BindingKind {
	return match (kind) {
		"uniform" => BindingKind.Uniform,
		"texture" => BindingKind.Texture,
		"sampler" => BindingKind.Sampler,
		_ => stopOnMember("GPUShaderBinding.kind", kind) as BindingKind,
	};
}

function vertexStage(stage: string): boolean {
	const value = match (stage) {
		"vertex" => 1,
		"fragment" => 0,
		_ => stopOnMember("GPUShaderBinding.stage", stage),
	};
	return value == 1;
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device === null) { stop("requestDevice needs the native MTLDevice"); }
	device = mtlDeviceFrom(environment.device);
	queue = mtlNewCommandQueue(device);
	sharedStorage = mtlUsesSharedStorage(device) == 1;
	mtlFrameSemaphoreCreate(FRAMES_IN_FLIGHT);
	commandBuffer = NO_COMMAND_BUFFER;
	encoder = NO_ENCODER;
	frame = 0;
	pass = { active: false };
	bound = { pipeline: 0 };
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(bindGroups);
	canvas = canvasOf(environment);
	swapchainColor = reserveSwapchainTexture(canvas.format);
	const depthFormat: string = canvas.depthFormat;
	swapchainDepth = depthFormat == "" ? 0 : reserveSwapchainTexture(canvas.depthFormat);
	return { id: 1, queue: { id: 1 } };
}

function canvasOf(environment: NativeEnvironment): GPUCanvasConfiguration {
	const colorFormat: string = environment.colorFormat;
	if (colorFormat == "") { stop("NativeEnvironment.colorFormat is required"); }
	if (formatInfo(environment.colorFormat, "NativeEnvironment.colorFormat").depth) {
		stopOnMember("NativeEnvironment.colorFormat", colorFormat);
	}
	const depthFormat: string = environment.depthFormat;
	if (depthFormat != "" && !formatInfo(environment.depthFormat, "NativeEnvironment.depthFormat").depth) {
		stopOnMember("NativeEnvironment.depthFormat", depthFormat);
	}
	const sampleCount = environment.sampleCount == 0 ? 1 : environment.sampleCount;
	if (mtlSupportsSampleCount(device, sampleCount) == 0) {
		stopOnMember("NativeEnvironment.sampleCount", `${sampleCount}`);
	}
	return { format: environment.colorFormat, depthFormat: environment.depthFormat, sampleCount: sampleCount };
}

export function canvasConfiguration(): GPUCanvasConfiguration { return canvas; }

export function formatRenderable(format: GPUTextureFormat): boolean {
	formatInfo(format, "formatRenderable format");
	return true;
}

export function frameIndex(): uint32 { return (frame + 1) as uint32; }

export function liveCounts(): GPULiveCounts {
	let counts: GPULiveCounts = { buffers: 0 };
	counts.buffers = buffers.live();
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { counts.textures += 1; } }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { counts.views += 1; } }
	counts.samplers = samplers.live();
	counts.shaderModules = shaders.live();
	counts.pipelines = pipelines.live();
	return counts;
}

export function bufferAlive(buffer: GPUBuffer): boolean {
	return buffers.alive(buffer.id);
}

export function textureAlive(texture: GPUTexture): boolean {
	return textures.alive(texture.id);
}

export function viewAlive(view: GPUTextureView): boolean {
	return views.alive(view.id);
}

export function samplerAlive(sampler: GPUSampler): boolean {
	return samplers.alive(sampler.id);
}

function reserveSwapchainTexture(format: GPUTextureFormat): uint32 {
	const textureId = allocate(textures);
	const viewId = allocate(views);
	store(textures, {
		id: textureId,
		format: format,
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		natives: [NO_TEXTURE, NO_TEXTURE],
		swapchainView: viewId,
	});
	store(views, { id: viewId, texture: textureId, swapchain: true, swapchainTexture: NO_TEXTURE, swapchainResolve: NO_TEXTURE });
	return textureId;
}

export function shutdown(): void {
	if (pass.active) { stop("shutdown with a render pass still open"); }
	if (commandBuffer != null) {
		mtlCommit(commandBuffer);
		commandBuffer = NO_COMMAND_BUFFER;
	}
	mtlFrameSemaphoreWaitAll();
	for (const id of bindGroups.liveIds()) { destroyBindGroup({ id: id }); }
	for (const id of pipelines.liveIds()) { destroyRenderPipeline({ id: id }); }
	for (const id of shaders.liveIds()) { destroyShaderModule({ id: id }); }
	for (const id of samplers.liveIds()) { destroySampler({ id: id }); }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { destroyView({ id: id }); } }
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { destroyTexture({ id: id }); } }
	for (const id of buffers.liveIds()) { destroyBuffer({ id: id }); }
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(bindGroups);
	mtlReleaseQueue(queue);
	mtlReleaseDevice(device);
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "metal", originTopLeft: true, depthZeroToOne: true };
}

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	const t = textures.slotIndex(texture.id);
	return mtlTextureNative(textures.slots[t].natives[textures.slots[t].active]);
}

export function nativeQueue(): Ptr<void> { return mtlQueueNative(queue); }

// A CPU write waits for the oldest frame in flight as a pass does (sokol _sg_mtl_begin_pass):
// it lands in a copy the frame before last may still read.
function beginFrame(): void {
	if (commandBuffer != null) { return; }
	commandBuffer = mtlBeginCommandBuffer(queue);
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocate(buffers);
	const usage = descriptor.usage;
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
	if (has(usage, GPUBufferUsage.MAP_READ as int32) || has(usage, GPUBufferUsage.MAP_WRITE as int32)) {
		stop("GPUBufferUsage MAP_READ and MAP_WRITE have no Metal path");
	}
	const native = mtlNewBuffer(device, descriptor.size, sharedStorage ? 1 : 0);
	if (native == null) { stop(`newBufferWithLength failed for ${labelOf(descriptor.label)}`); }
	const slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		natives: [native, NO_BUFFER],
		active: 0,
		writtenFrame: has(usage, GPUBufferUsage.COPY_DST as int32) ? -1 : -2,
		writtenEnd: 0,
	};
	store(buffers, slot);
	return { id: id };
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (buffers.slots[index].natives[s] != null) { mtlReleaseBuffer(buffers.slots[index].natives[s]); }
	}
	buffers.slots[index] = { id: 0 };
	release(buffers, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers.slots[buffers.slotIndex(buffer.id)].size; }

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = buffers.slotIndex(buffer.id);
	if (offset < 0 || offset + bytes > buffers.slots[index].size) {
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${buffer.id} of ${buffers.slots[index].size}`);
	}
	if (buffers.slots[index].writtenFrame == -2) { stop(`GPUBuffer ${buffer.id} was created without COPY_DST`); }
	beginFrame();
	if (buffers.slots[index].writtenFrame != frame) {
		if (buffers.slots[index].writtenFrame >= 0) { nextBufferCopy(index); }
		buffers.slots[index].writtenFrame = frame;
		buffers.slots[index].writtenEnd = 0;
	} else if (offset < buffers.slots[index].writtenEnd) {
		stop(`writeBuffer at ${offset} on GPUBuffer ${buffer.id} rewrites bytes this frame already wrote, up to ${buffers.slots[index].writtenEnd}`);
	}
	const native = buffers.slots[index].natives[buffers.slots[index].active];
	mtlWriteBuffer(native, offset, data[0], bytes, sharedStorage ? 0 : 1);
	buffers.slots[index].writtenEnd = offset + bytes;
}

function nextBufferCopy(index: int32): void {
	const next = 1 - buffers.slots[index].active;
	if (buffers.slots[index].natives[next] == null) {
		buffers.slots[index].natives[next] = mtlNewBuffer(device, buffers.slots[index].size, sharedStorage ? 1 : 0);
		if (buffers.slots[index].natives[next] == null) { stop(`newBufferWithLength failed for GPUBuffer ${buffers.slots[index].id}`); }
	}
	buffers.slots[index].active = next;
	bound.vertexDirty = true;
	bound.uniformsDirty = true;
}

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocate(textures);
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	if (width <= 0 || height <= 0) { stop("GPUTextureDescriptor.size needs a positive width and height"); }
	stopOnUnportedTexture("metal", descriptor);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && mtlSupportsSampleCount(device, sampleCount) == 0) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (attachment && has(usage, GPUTextureUsage.COPY_DST as int32)) {
		stop("COPY_DST with RENDER_ATTACHMENT: a Metal attachment is private storage the CPU cannot write");
	}
	if (sampleCount > 1 && !attachment) { stop("a multisampled texture must be a RENDER_ATTACHMENT"); }
	const native = newTexture(width, height, info.pixel, sampleCount, attachment);
	if (native == null) { stop(`newTextureWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	const slot: TextureSlot = {
		id: id,
		width: width,
		height: height,
		format: descriptor.format,
		usage: usage,
		sampleCount: sampleCount,
		natives: [native, NO_TEXTURE],
		active: 0,
		writtenFrame: -1,
		swapchainView: 0,
	};
	store(textures, slot);
	return { id: id };
}

function newTexture(width: int32, height: int32, pixel: int32, sampleCount: int32, attachment: boolean): Ptr<MtlTextureImpl> {
	return mtlNewTexture(device, width, height, pixel, sampleCount, attachment ? 1 : 0, sharedStorage ? 1 : 0);
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textures.slotIndex(texture.id);
	if (textures.slots[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (textures.slots[index].natives[s] != null) { mtlReleaseTexture(textures.slots[index].natives[s]); }
	}
	textures.slots[index] = { id: 0 };
	release(textures, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat { return textures.slots[textures.slotIndex(texture.id)].format; }

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textures.slotIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	const rowPitch = textureCopyPitch(index, bytes, destination, layout, size);
	beginFrame();
	if (textures.slots[index].writtenFrame == frame) {
		stop(`writeTexture twice in one frame on GPUTexture ${destination.texture.id} (sokol allows one update per frame)`);
	}
	if (textures.slots[index].writtenFrame >= 0) { nextTextureCopy(index); }
	textures.slots[index].writtenFrame = frame;
	const native = textures.slots[index].natives[textures.slots[index].active];
	mtlWriteTexture(native, data[0], layout.offset, rowPitch, textures.slots[index].width, textures.slots[index].height);
}

function nextTextureCopy(index: int32): void {
	const next = 1 - textures.slots[index].active;
	if (textures.slots[index].natives[next] == null) {
		const pixel = formatInfo(textures.slots[index].format, "texture format").pixel;
		textures.slots[index].natives[next] = newTexture(textures.slots[index].width, textures.slots[index].height, pixel, 1, false);
		if (textures.slots[index].natives[next] == null) { stop(`newTextureWithDescriptor failed for GPUTexture ${textures.slots[index].id}`); }
	}
	textures.slots[index].active = next;
	bound.resourcesDirty = true;
}

function textureCopyPitch(
	index: int32,
	bytes: int64,
	destination: GPUTexelCopyTextureInfo,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): int32 {
	const width = textures.slots[index].width;
	const height = textures.slots[index].height;
	if (!has(textures.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textures.slots[index].id}, created without COPY_DST`);
	}
	const bytesPerPixel = formatInfo(textures.slots[index].format, "texture format").bytesPerPixel;
	stopOnUnportedTexelWrite("metal", destination, size);
	const rowPitch = checkedTexelWritePitch(width, height, 1, 1, bytesPerPixel, bytes, destination, layout, size);
	if (destination.origin.x != 0 || destination.origin.y != 0 || size.width != width || size.height != height) {
		stop(`writeTexture of ${size.width}x${size.height} at origin ${destination.origin.x},${destination.origin.y} on GPUTexture ${textures.slots[index].id}: Metal writes the whole texture only`);
	}
	return rowPitch;
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	stopOnUnportedView("metal", descriptor);
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { return { id: textures.slots[t].swapchainView }; }
	const id = allocate(views);
	const slot: ViewSlot = {
		id: id,
		texture: texture.id,
		swapchain: false,
		swapchainTexture: NO_TEXTURE,
		swapchainResolve: NO_TEXTURE,
	};
	store(views, slot);
	return { id: slot.id };
}

export function destroyView(view: GPUTextureView): void {
	const index = views.slotIndex(view.id);
	if (views.slots[index].swapchain) { return; }
	views.slots[index] = { id: 0 };
	release(views, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views.slots[views.slotIndex(view.id)].texture }; }

function viewNative(v: int32): Ptr<MtlTextureImpl> {
	if (views.slots[v].swapchain) { return views.slots[v].swapchainTexture; }
	const t = textures.slotIndex(views.slots[v].texture);
	return textures.slots[t].natives[textures.slots[t].active];
}

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = views.slotIndex(textures.slots[textures.slotIndex(swapchainColor)].swapchainView);
	views.slots[v].swapchainTexture = mtlTextureFrom(swapchain.renderView);
	views.slots[v].swapchainResolve = swapchain.resolveView === null ? NO_TEXTURE : mtlTextureFrom(swapchain.resolveView);
	if (swapchainDepth != 0) {
		if (swapchain.depthStencilView === null) { stop("the canvas has a depth format and the native swapchain no depth view"); }
		updateSwapchainTexture(swapchainDepth, swapchain);
		const d = views.slotIndex(textures.slots[textures.slotIndex(swapchainDepth)].swapchainView);
		views.slots[d].swapchainTexture = mtlTextureFrom(swapchain.depthStencilView);
	}
	return { id: swapchainColor };
}

export function swapchainDepthTexture(): GPUTexture { return { id: swapchainDepth }; }

function updateSwapchainTexture(id: uint32, swapchain: NativeSwapchain): void {
	const t = textures.slotIndex(id);
	textures.slots[t].width = swapchain.width;
	textures.slots[t].height = swapchain.height;
	textures.slots[t].sampleCount = swapchain.sampleCount == 0 ? 1 : swapchain.sampleCount;
}

export function createSampler(descriptor: GPUSamplerDescriptor): GPUSampler {
	const id = allocate(samplers);
	const minFilter = filterMode(descriptor.minFilter, "GPUSamplerDescriptor.minFilter");
	const magFilter = filterMode(descriptor.magFilter, "GPUSamplerDescriptor.magFilter");
	const mipFilter = mipFilterMode(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter");
	let maxAnisotropy = descriptor.maxAnisotropy;
	if (maxAnisotropy < 1) { maxAnisotropy = 1; }
	if (maxAnisotropy > MAX_ANISOTROPY) { stopOnMember("GPUSamplerDescriptor.maxAnisotropy", `${maxAnisotropy}`); }
	checkedSamplerAnisotropy(maxAnisotropy, minFilter == FILTER_LINEAR && magFilter == FILTER_LINEAR && mipFilter == MIP_FILTER_LINEAR);
	if (descriptor.lodMinClamp < 0) { stopOnMember("GPUSamplerDescriptor.lodMinClamp", `${descriptor.lodMinClamp}`); }
	const maxLod = checkedSamplerLod(descriptor.lodMinClamp, descriptor.lodMaxClamp);
	const compare: string = descriptor.compare;
	const native = mtlNewSampler(
		device,
		minFilter,
		magFilter,
		mipFilter,
		addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"),
		addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"),
		addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW"),
		descriptor.lodMinClamp,
		maxLod,
		maxAnisotropy,
		compare == "" ? COMPARE_NEVER : compareFunction(compare, "GPUSamplerDescriptor.compare"),
	);
	if (native == null) { stop(`newSamplerStateWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	store(samplers, { id: id, native: native });
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplers.slotIndex(sampler.id);
	mtlReleaseSampler(samplers.slots[index].native);
	samplers.slots[index] = { id: 0 };
	release(samplers, sampler.id);
}

function compileLibrary(code: string, stage: string, label: string | null): Ptr<MtlLibraryImpl> {
	const library = mtlNewLibrary(device, code);
	if (library == null) {
		const log: string = mtlErrorLog();
		stop(`the ${stage} MSL of ${labelOf(label)} does not compile:\n${log}`);
	}
	return library;
}

function entryFunction(library: Ptr<MtlLibraryImpl>, entryPoint: string, stage: string, label: string | null): Ptr<MtlFunctionImpl> {
	const entry = entryPoint == "" ? "_main" : entryPoint;
	const found = mtlNewFunction(library, entry);
	if (found == null) { stop(`the ${stage} MSL of ${labelOf(label)} has no function '${entry}'`); }
	return found;
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	stopOnUnportedShaderModule("metal", descriptor);
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const native: NativeBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName),
			vertexStage: vertexStage(descriptor.bindings[i].stage),
			nativeSlot: descriptor.bindings[i].nativeSlot,
			size: descriptor.bindings[i].size,
		};
		checkBinding(native, descriptor.bindings[i].group);
		if (native.kind == BindingKind.Uniform) {
			if (slot.uniformCount == GPU_MAX_UNIFORM_BLOCKS) { stop("a shader module has over 8 uniform blocks"); }
			slot.uniforms[slot.uniformCount] = native;
			slot.uniformCount += 1;
		} else {
			if (slot.resourceCount == GPU_MAX_BIND_GROUP_ENTRIES) { stop("a shader module has over 8 resources"); }
			slot.resources[slot.resourceCount] = native;
			slot.resourceCount += 1;
		}
	}
	slot.attributes = descriptor.attributes;
	slot.vertexLibrary = compileLibrary(descriptor.vertexCode, "vertex", descriptor.label);
	slot.fragmentLibrary = compileLibrary(descriptor.fragmentCode, "fragment", descriptor.label);
	slot.vertex = entryFunction(slot.vertexLibrary, descriptor.vertexEntryPoint, "vertex", descriptor.label);
	slot.fragment = entryFunction(slot.fragmentLibrary, descriptor.fragmentEntryPoint, "fragment", descriptor.label);
	slot.id = id;
	store(shaders, slot);
	return { id: slot.id };
}

function checkBinding(native: NativeBinding, group: int32): void {
	const expectedGroup = native.kind == BindingKind.Uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
	if (group != expectedGroup) {
		stop(`shader binding ${native.binding} (${native.kind.toString()}) belongs in group ${expectedGroup}, not ${group}`);
	}
	const limit = match (native.kind) {
		BindingKind.Uniform => MAX_STAGE_UNIFORM_BUFFERS,
		BindingKind.Texture => MAX_STAGE_TEXTURES,
		BindingKind.Sampler => MAX_STAGE_SAMPLERS,
	};
	if (native.nativeSlot < 0 || native.nativeSlot >= limit) {
		stop(`shader binding ${native.binding} has MSL slot ${native.nativeSlot}, outside 0..${limit - 1}`);
	}
	if (native.kind == BindingKind.Uniform && native.size <= 0) {
		stop(`uniform binding ${native.binding} needs its block size`);
	}
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaders.slotIndex(module.id);
	mtlReleaseFunction(shaders.slots[index].vertex);
	mtlReleaseFunction(shaders.slots[index].fragment);
	mtlReleaseLibrary(shaders.slots[index].vertexLibrary);
	mtlReleaseLibrary(shaders.slots[index].fragmentLibrary);
	shaders.slots[index] = { id: 0 };
	release(shaders, module.id);
}

function checkAttribute(shader: int32, location: int32): void {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		if (shaders.slots[shader].attributes[i].location == location) { return; }
	}
	stopOnMember("vertex attribute shaderLocation (absent from the shader reflection)", `${location}`);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocate(pipelines);
	const s = shaders.slotIndex(descriptor.vertex.module.id);
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule on Metal");
	}
	let slot: PipelineSlot = { id: 0, shader: descriptor.vertex.module.id };
	mtlPipelineReset();
	describeVertexLayout(s, descriptor, slot);
	describeColorTargets(descriptor);
	const depthFormat: string = descriptor.depthStencil.format;
	let depthPixel = PIXEL_INVALID;
	let stencilPixel = PIXEL_INVALID;
	if (depthFormat != "") {
		const info = formatInfo(descriptor.depthStencil.format, "depthStencil.format");
		if (!info.depth) { stopOnMember("depthStencil.format", depthFormat); }
		depthPixel = info.pixel;
		if (info.stencil) { stencilPixel = info.pixel; }
	}
	const sampleCount = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	slot.state = mtlNewPipeline(device, shaders.slots[s].vertex, shaders.slots[s].fragment, depthPixel, stencilPixel, sampleCount);
	if (slot.state == null) {
		const log: string = mtlErrorLog();
		stop(`newRenderPipelineStateWithDescriptor failed for ${labelOf(descriptor.label)}:\n${log}`);
	}
	const stencil = stencilPixel != PIXEL_INVALID;
	const front: GPUStencilFaceState = descriptor.depthStencil.stencilFront;
	const back: GPUStencilFaceState = descriptor.depthStencil.stencilBack;
	const readMask = descriptor.depthStencil.stencilReadMask;
	const writeMask = descriptor.depthStencil.stencilWriteMask;
	slot.depth = mtlNewDepthState(
		device,
		depthFormat == "" ? COMPARE_ALWAYS : compareFunction(descriptor.depthStencil.depthCompare, "depthStencil.depthCompare"),
		depthFormat != "" && descriptor.depthStencil.depthWriteEnabled ? 1 : 0,
		stencil ? 1 : 0,
		readMask == 0 ? STENCIL_MASK_ALL : readMask,
		writeMask == 0 ? STENCIL_MASK_ALL : writeMask,
		stencilOperation(front.failOp, "depthStencil.stencilFront.failOp"),
		stencilOperation(front.depthFailOp, "depthStencil.stencilFront.depthFailOp"),
		stencilOperation(front.passOp, "depthStencil.stencilFront.passOp"),
		compareFunction(front.compare, "depthStencil.stencilFront.compare"),
		stencilOperation(back.failOp, "depthStencil.stencilBack.failOp"),
		stencilOperation(back.depthFailOp, "depthStencil.stencilBack.depthFailOp"),
		stencilOperation(back.passOp, "depthStencil.stencilBack.passOp"),
		compareFunction(back.compare, "depthStencil.stencilBack.compare"),
	);
	if (slot.depth == null) { stop(`newDepthStencilStateWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	slot.depthBias = descriptor.depthStencil.depthBias as float32;
	slot.depthBiasSlope = descriptor.depthStencil.depthBiasSlopeScale;
	slot.depthBiasClamp = descriptor.depthStencil.depthBiasClamp;
	slot.primitive = primitiveType(descriptor.primitive.topology);
	slot.stripIndexType = stripIndexTypeOf(descriptor.primitive, slot.primitive);
	slot.cullMode = cullMode(descriptor.primitive.cullMode);
	slot.winding = winding(descriptor.primitive.frontFace);
	slot.id = id;
	store(pipelines, slot);
	return { id: slot.id };
}

function describeVertexLayout(shader: int32, descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stepMode: string = descriptor.vertex.buffers[b].stepMode;
		if (stepMode != "" && stepMode != "vertex" && stepMode != "instance") {
			stopOnMember("vertex.buffers stepMode", stepMode);
		}
		let used = false;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			const location = descriptor.vertex.buffers[b].attributes[a].shaderLocation;
			checkAttribute(shader, location);
			mtlPipelineAttribute(location, vertexFormat(format), descriptor.vertex.buffers[b].attributes[a].offset, VERTEX_BUFFER_BASE + b);
			used = true;
		}
		const stride = descriptor.vertex.buffers[b].arrayStride;
		if (used || stride != 0) {
			if (stride <= 0) { stop(`vertex.buffers[${b}] has attributes and no arrayStride`); }
			mtlPipelineLayout(VERTEX_BUFFER_BASE + b, stride, stepMode == "instance" ? 1 : 0);
			slot.strides[b] = stride;
		}
	}
}

function describeColorTargets(descriptor: GPURenderPipelineDescriptor): void {
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") { continue; }
		const info = formatInfo(descriptor.fragment.targets[i].format, `fragment.targets[${i}].format`);
		const color: GPUBlendComponent = descriptor.fragment.targets[i].blend.color;
		const alpha: GPUBlendComponent = descriptor.fragment.targets[i].blend.alpha;
		mtlPipelineColor(
			i,
			info.pixel,
			descriptor.fragment.targets[i].blendEnabled ? 1 : 0,
			blendFactor(color.srcFactor, "blend.color.srcFactor"),
			destinationFactor(color.dstFactor, "blend.color.dstFactor"),
			blendOperation(color.operation, "blend.color.operation"),
			blendFactor(alpha.srcFactor, "blend.alpha.srcFactor"),
			destinationFactor(alpha.dstFactor, "blend.alpha.dstFactor"),
			blendOperation(alpha.operation, "blend.alpha.operation"),
			colorWriteMask(descriptor.fragment.targets[i].writeMask),
		);
	}
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	const index = pipelines.slotIndex(pipeline.id);
	mtlReleasePipeline(pipelines.slots[index].state);
	mtlReleaseDepthState(pipelines.slots[index].depth);
	for (let g = 0; g < 2; g++) {
		const layout = pipelines.slots[index].layouts[g];
		if (layout != 0) {
			layouts.slots[layouts.slotIndex(layout)] = { id: 0 };
			release(layouts, layout);
		}
	}
	pipelines.slots[index] = { id: 0 };
	release(pipelines, pipeline.id);
}

export function getBindGroupLayout(pipeline: GPURenderPipeline, index: int32): GPUBindGroupLayout {
	const p = pipelines.slotIndex(pipeline.id);
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) {
		stopOnMember("getBindGroupLayout index", `${index}`);
	}
	if (pipelines.slots[p].layouts[index] == 0) {
		const id = allocate(layouts);
		const slot: LayoutSlot = { id: id, pipeline: pipeline.id, group: index };
		store(layouts, slot);
		pipelines.slots[p].layouts[index] = id;
	}
	return { id: pipelines.slots[p].layouts[index] };
}

export function createBindGroup(descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	const id = allocate(bindGroups);
	const l = layouts.slotIndex(descriptor.layout.id);
	const group = layouts.slots[l].group;
	const shader = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(layouts.slots[l].pipeline)].shader);
	let slot: BindGroupSlot = { id: 0, group: group };
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) { continue; }
		checkEntry(shader, group, entry);
		slot.entries[slot.entryCount] = entry;
		slot.entryCount += 1;
	}
	for (let i = 0; i < slot.entryCount; i++) {
		if (slot.entries[i].buffer.id == 0) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			if (slot.entries[j].buffer.id != 0 && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: slot.id };
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	const kind = entry.buffer.id != 0 ? BindingKind.Uniform :
		(entry.textureView.id != 0 ? BindingKind.Texture : BindingKind.Sampler);
	if (kind == BindingKind.Uniform) {
		buffers.slotIndex(entry.buffer.id);
		for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
			const binding = shaders.slots[shader].uniforms[u];
			if (binding.binding == entry.binding) {
				stopOnUnportedBindEntry("metal", entry);
				if (entry.size != 0 && entry.size < (binding.size as int64)) {
					stop(`bind group entry ${entry.binding} size ${entry.size} is below its block of ${binding.size}`);
				}
				return;
			}
		}
	} else {
		if (kind == BindingKind.Texture) {
			const t = textures.slotIndex(views.slots[views.slotIndex(entry.textureView.id)].texture);
			if (!has(textures.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
				stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`);
			}
		} else {
			samplers.slotIndex(entry.sampler.id);
		}
		for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
			if (shaders.slots[shader].resources[r].binding == entry.binding && shaders.slots[shader].resources[r].kind == kind) {
				return;
			}
		}
	}
	stop(`bind group ${group} entry ${entry.binding} (${kind.toString()}) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroups.slotIndex(bindGroup.id);
	bindGroups.slots[index] = { id: 0 };
	release(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (pass.active) { stop("finish with a render pass still open"); }
	return { id: 1 };
}

export function submit(submitted: GPUCommandBuffer): void {
	if (commandBuffer != null) {
		mtlCommit(commandBuffer);
		commandBuffer = NO_COMMAND_BUFFER;
	}
	frame += 1;
}

function loadAction(loadOp: string, member: string): int32 {
	return match (loadOp) {
		"clear" => LOAD_CLEAR,
		"load" => LOAD_LOAD,
		_ => stopOnMember(member, loadOp),
	};
}

function storeAction(storeOp: string, resolve: boolean, member: string): int32 {
	return match (storeOp) {
		"store" => resolve ? STORE_STORE_AND_RESOLVE : STORE_STORE,
		"discard" => resolve ? STORE_RESOLVE : STORE_DONT_CARE,
		_ => stopOnMember(member, storeOp),
	};
}

export function beginRenderPass(passEncoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	stopOnUnportedRenderPass("metal", descriptor);
	if (pass.active) { stop("beginRenderPass with a render pass already open"); }
	pass = { active: true };
	beginFrame();
	mtlPassReset();
	passVertexUniforms = [];
	passFragmentUniforms = [];
	for (let i = 0; i < MAX_STAGE_UNIFORM_BUFFERS; i++) {
		passVertexUniforms.push(NO_BUFFER);
		passFragmentUniforms.push(NO_BUFFER);
	}
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = views.slotIndex(viewId);
		const t = textures.slotIndex(views.slots[v].texture);
		if (formatInfo(textures.slots[t].format, "texture format").depth || !has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`);
		}
		passExtent(t);
		const resolve = resolveTexture(i, v, descriptor.colorAttachments[i].resolveTarget.id);
		if (views.slots[v].swapchain) { pass.screen = true; }
		const color = descriptor.colorAttachments[i].clearValue;
		mtlPassColor(
			i,
			viewNative(v),
			resolve,
			loadAction(descriptor.colorAttachments[i].loadOp, `colorAttachments[${i}].loadOp`),
			storeAction(descriptor.colorAttachments[i].storeOp, resolve != null, `colorAttachments[${i}].storeOp`),
			color.r,
			color.g,
			color.b,
			color.a,
		);
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	if (depthView != 0) {
		const v = views.slotIndex(depthView);
		const t = textures.slotIndex(views.slots[v].texture);
		const info = formatInfo(textures.slots[t].format, "depth format");
		if (!info.depth || !has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT");
		}
		passExtent(t);
		mtlPassDepth(
			viewNative(v),
			loadAction(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp"),
			storeAction(descriptor.depthStencilAttachment.depthStoreOp, false, "depthStencilAttachment.depthStoreOp"),
			descriptor.depthStencilAttachment.depthClearValue,
			info.stencil ? 1 : 0,
		);
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	encoder = mtlBeginPass(commandBuffer);
	if (encoder == null) { stop("renderCommandEncoderWithDescriptor returned nil"); }
	mtlSetViewport(encoder, 0.0, 0.0, pass.width, pass.height, 0.0, 1.0);
	bound.appliedPipeline = 0;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
	return { id: 1 };
}

function passExtent(t: int32): void {
	if (pass.width == 0) {
		pass.width = textures.slots[t].width;
		pass.height = textures.slots[t].height;
	} else if (pass.width != textures.slots[t].width || pass.height != textures.slots[t].height) {
		stop("render pass attachments differ in size");
	}
}

function resolveTexture(attachment: int32, colorView: int32, resolveId: uint32): Ptr<MtlTextureImpl> {
	const colorTexture = textures.slotIndex(views.slots[colorView].texture);
	if (views.slots[colorView].swapchain && resolveId == 0) { return views.slots[colorView].swapchainResolve; }
	if (resolveId == 0) { return NO_TEXTURE; }
	const r = views.slotIndex(resolveId);
	const resolve = textures.slotIndex(views.slots[r].texture);
	if (textures.slots[colorTexture].sampleCount == 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`);
	}
	if (textures.slots[resolve].sampleCount != 1 || !has(textures.slots[resolve].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample color RENDER_ATTACHMENT`);
	}
	return viewNative(r);
}

export function endPass(): void {
	if (!pass.active) { stop("end without an open render pass"); }
	mtlEndPass(encoder);
	encoder = NO_ENCODER;
	if (pass.screen) { mtlPresentDrawable(commandBuffer); }
	pass.active = false;
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	pipelines.slotIndex(pipeline.id);
	bound.pipeline = pipeline.id;
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) { stopOnMember("setVertexBuffer slot", `${slot}`); }
	bound.vertexBuffers[slot] = buffer.id;
	bound.vertexOffsets[slot] = offset;
	bound.vertexDirty = true;
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	bound.indexBuffer = buffer.id;
	bound.indexType = indexType(format);
	bound.indexBytes = bound.indexType == INDEX_UINT16 ? 2 : 4;
	bound.indexOffset = offset;
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) { stopOnMember("setBindGroup index", `${index}`); }
	bound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroups.slotIndex(bindGroup.id);
	if (bindGroups.slots[g].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups.slots[g].group}`);
	}
	if ((dynamicOffsets.length as int32) != bindGroups.slots[g].dynamicCount) {
		stop(`setBindGroup(${index}) takes ${bindGroups.slots[g].dynamicCount} dynamic offsets, got ${dynamicOffsets.length}`);
	}
	if (index == GPU_UNIFORM_GROUP) {
		for (let i = 0; i < bindGroups.slots[g].dynamicCount; i++) {
			if (dynamicOffsets[i] % UNIFORM_OFFSET_ALIGNMENT != 0) {
				stop(`dynamic offset ${dynamicOffsets[i]} is not a multiple of ${UNIFORM_OFFSET_ALIGNMENT}`);
			}
			bound.dynamicOffsets[i] = dynamicOffsets[i];
		}
		bound.uniformsDirty = true;
	} else {
		bound.resourcesDirty = true;
	}
}

// Metal refuses a scissor rect outside the attachment; sokol clips it the same way (_sg_clipi).
export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	if (!pass.active) { stop("setScissorRect outside a render pass"); }
	const left = x < 0 ? 0 : (x > pass.width ? pass.width : x);
	const top = y < 0 ? 0 : (y > pass.height ? pass.height : y);
	let right = x + width;
	let bottom = y + height;
	right = right > pass.width ? pass.width : (right < left ? left : right);
	bottom = bottom > pass.height ? pass.height : (bottom < top ? top : bottom);
	mtlSetScissorRect(encoder, left, top, right - left, bottom - top);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	if (!pass.active) { stop("setViewport outside a render pass"); }
	checkedViewport(width, height, minDepth, maxDepth);
	mtlSetViewport(encoder, x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	if (!pass.active) { stop("setBlendConstant outside a render pass"); }
	mtlSetBlendColor(encoder, color.r, color.g, color.b, color.a);
}

export function setStencilReference(reference: uint32): void {
	if (!pass.active) { stop("setStencilReference outside a render pass"); }
	mtlSetStencilReference(encoder, reference);
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush();
	mtlDraw(encoder, pipelines.slots[pipelines.slotIndex(bound.pipeline)].primitive, vertexCount, instanceCount, firstVertex, firstInstance);
}

export function drawIndexed(
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	if (instanceCount == 0) { return; }
	flush();
	if (bound.indexBuffer == 0) { stop("drawIndexed without setIndexBuffer"); }
	const p = pipelines.slotIndex(bound.pipeline);
	const primitive = pipelines.slots[p].primitive;
	if ((primitive == PRIMITIVE_LINE_STRIP || primitive == PRIMITIVE_TRIANGLE_STRIP) && pipelines.slots[p].stripIndexType != bound.indexType) {
		stop("an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format");
	}
	const b = buffers.slotIndex(bound.indexBuffer);
	mtlDrawIndexed(
		encoder,
		primitive,
		buffers.slots[b].natives[buffers.slots[b].active],
		bound.indexType,
		bound.indexOffset + (firstIndex as int64) * bound.indexBytes,
		indexCount,
		instanceCount,
		baseVertex,
		firstInstance,
	);
}

function flush(): void {
	if (!pass.active) { stop("draw outside a render pass"); }
	if (bound.pipeline == 0) { stop("draw without setPipeline"); }
	if (bound.appliedPipeline != bound.pipeline) { applyPipeline(); }
	if (bound.vertexDirty) { applyVertexBuffers(); }
	if (bound.resourcesDirty) { applyResources(); }
	if (bound.uniformsDirty) { applyUniforms(); }
}

function applyPipeline(): void {
	const p = pipelines.slotIndex(bound.pipeline);
	if (!shaders.alive(pipelines.slots[p].shader)) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	mtlSetPipeline(encoder, pipelines.slots[p].state, pipelines.slots[p].depth, pipelines.slots[p].cullMode, pipelines.slots[p].winding, pipelines.slots[p].depthBias, pipelines.slots[p].depthBiasSlope, pipelines.slots[p].depthBiasClamp);
	bound.appliedPipeline = bound.pipeline;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
}

function applyVertexBuffers(): void {
	const p = pipelines.slotIndex(bound.pipeline);
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines.slots[p].strides[slot] == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		const b = buffers.slotIndex(bound.vertexBuffers[slot]);
		mtlSetVertexBuffer(encoder, buffers.slots[b].natives[buffers.slots[b].active], bound.vertexOffsets[slot], VERTEX_BUFFER_BASE + slot);
	}
	bound.vertexDirty = false;
}

function entryOf(group: int32, binding: int32): int32 {
	for (let e = 0; e < bindGroups.slots[group].entryCount; e++) {
		if (bindGroups.slots[group].entries[e].binding == binding) { return e; }
	}
	return stopOnMember("bound bind group: missing entry for binding", `${binding}`);
}

function applyResources(): void {
	const s = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(bound.pipeline)].shader);
	bound.resourcesDirty = false;
	if (shaders.slots[s].resourceCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	const g = bindGroups.slotIndex(bound.bindGroups[GPU_RESOURCE_GROUP]);
	for (let r = 0; r < shaders.slots[s].resourceCount; r++) {
		const binding: NativeBinding = shaders.slots[s].resources[r];
		const e = entryOf(g, binding.binding);
		if (binding.kind == BindingKind.Texture) {
			const texture = viewNative(views.slotIndex(bindGroups.slots[g].entries[e].textureView.id));
			if (binding.vertexStage) {
				mtlSetVertexTexture(encoder, texture, binding.nativeSlot);
			} else {
				mtlSetFragmentTexture(encoder, texture, binding.nativeSlot);
			}
		} else {
			const sampler = samplers.slots[samplers.slotIndex(bindGroups.slots[g].entries[e].sampler.id)].native;
			if (binding.vertexStage) {
				mtlSetVertexSampler(encoder, sampler, binding.nativeSlot);
			} else {
				mtlSetFragmentSampler(encoder, sampler, binding.nativeSlot);
			}
		}
	}
}

function applyUniforms(): void {
	const s = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(bound.pipeline)].shader);
	bound.uniformsDirty = false;
	if (shaders.slots[s].uniformCount == 0) { return; }
	if (bound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the pipeline reads bind group 0, which is not set"); }
	const g = bindGroups.slotIndex(bound.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders.slots[s].uniformCount; u++) {
		const e = entryOf(g, shaders.slots[s].uniforms[u].binding);
		const offset = bound.dynamicOffsets[bindGroups.slots[g].dynamicIndex[e]] as int64;
		const b = buffers.slotIndex(bindGroups.slots[g].entries[e].buffer.id);
		if (offset + (shaders.slots[s].uniforms[u].size as int64) > buffers.slots[b].size) {
			stop(`uniform binding ${shaders.slots[s].uniforms[u].binding} at offset ${offset} overruns its buffer`);
		}
		const native = buffers.slots[b].natives[buffers.slots[b].active];
		const slot = shaders.slots[s].uniforms[u].nativeSlot;
		if (shaders.slots[s].uniforms[u].vertexStage) {
			if (passVertexUniforms[slot] == native) {
				mtlSetVertexBufferOffset(encoder, offset, slot);
			} else {
				mtlSetVertexBuffer(encoder, native, offset, slot);
				passVertexUniforms[slot] = native;
			}
		} else if (passFragmentUniforms[slot] == native) {
			mtlSetFragmentBufferOffset(encoder, offset, slot);
		} else {
			mtlSetFragmentBuffer(encoder, native, offset, slot);
			passFragmentUniforms[slot] = native;
		}
	}
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void { stop("copyBufferToBuffer is not ported to metal yet"); }
export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void { stop("copyBufferToTexture is not ported to metal yet"); }
export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void { stop("copyTextureToBuffer is not ported to metal yet"); }
export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void { stop("copyTextureToTexture is not ported to metal yet"); }
export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void { stop("mapAsync is not ported to metal yet"); }
export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> { stop("getMappedRange is not ported to metal yet"); return []; }
export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void { stop("writeMappedRange is not ported to metal yet"); }
export function unmap(buffer: GPUBuffer): void { stop("unmap is not ported to metal yet"); }
export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline { stop("createComputePipeline is not ported to metal yet"); return { id: 0 }; }
export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder { stop("beginComputePass is not ported to metal yet"); return { id: 0 }; }
export function setComputePipeline(pipeline: GPUComputePipeline): void { stop("setPipeline on a compute pass is not ported to metal yet"); }
export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void { stop("setBindGroup on a compute pass is not ported to metal yet"); }
export function dispatchWorkgroups(x: int32, y: int32, z: int32): void { stop("dispatchWorkgroups is not ported to metal yet"); }
export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void { stop("dispatchWorkgroupsIndirect is not ported to metal yet"); }
export function endComputePass(): void { stop("end on a compute pass is not ported to metal yet"); }
export function limits(): GPUSupportedLimits { stop("limits is not ported to metal yet"); return {}; }
export function features(): GPUSupportedFeatures { stop("features is not ported to metal yet"); return { bits: 0 }; }
export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet { stop("GPUQuerySet is not ported to metal yet"); return { id: 0 }; }
export function destroyQuerySet(querySet: GPUQuerySet): void { stop("GPUQuerySet is not ported to metal yet"); }
export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void { stop("resolveQuerySet is not ported to metal yet"); }
export function pushDebugGroup(label: string): void { stop("pushDebugGroup is not ported to metal yet"); }
export function popDebugGroup(): void { stop("popDebugGroup is not ported to metal yet"); }
export function insertDebugMarker(label: string): void { stop("insertDebugMarker is not ported to metal yet"); }
export function beginOcclusionQuery(queryIndex: int32): void { stop("beginOcclusionQuery is not ported to metal yet"); }
export function endOcclusionQuery(): void { stop("endOcclusionQuery is not ported to metal yet"); }
