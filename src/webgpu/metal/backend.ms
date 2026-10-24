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
	GPUPassTimestampWrites,
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
	GPUMapMode,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderAttribute,
	GPUShaderBinding,
	GPUShaderStage,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilFaceState,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	checkedBufferCopy,
	checkedBufferUsage,
	checkedDepthTexelCopy,
	checkedDispatch,
	checkedDispatchIndirect,
	checkedMapAsync,
	checkedMappedRange,
	checkedSamplerAnisotropy,
	checkedTexelBufferLayout,
	checkedTexelCopyRegion,
	checkedTextureToTextureCopy,
	checkedUnmap,
	checkedViewport,
	checkedSamplerLod,
	checkedTexelWritePitch,
	checkedCubeView,
	checkedDepthSlice,
	checkedMipLevelCount,
	checkedMultisample,
	checkedNoDepthSlice,
	checkedPopDebugGroup,
	checkedPassExtent,
	checkedQuerySetCount,
	checkedResolveQuerySet,
	checkedResolveTarget,
	checkedSingleSubresource,
	checkedTimestampWrites,
	checkedViewLayers,
	checkedViewMips,
	checkedView3d,
	featureBit,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	checkedVisibility,
	checkedIntegerTexturePairs,
	stopOnUnportedShaderBytecode,
} from "../types.ms";
import {
	MtlBufferImpl,
	MtlCommandBufferImpl,
	MtlComputePipelineImpl,
	MtlDepthStateImpl,
	MtlDeviceImpl,
	MtlEncoderImpl,
	MtlFunctionImpl,
	MtlLibraryImpl,
	MtlPipelineImpl,
	MtlQueueImpl,
	MtlSampleBufferImpl,
	MtlSamplerImpl,
	MtlTextureImpl,
	mtlBeginCommandBuffer,
	mtlBlitBufferToBuffer,
	mtlBlitBufferToTexture,
	mtlBlitTextureToBuffer,
	mtlBlitTextureToTexture,
	mtlComputeMaxThreads,
	mtlComputeSetBuffer,
	mtlComputeSetPipeline,
	mtlComputeSetSampler,
	mtlComputeSetTexture,
	mtlCopyIn,
	mtlCopyOut,
	mtlDispatch,
	mtlDispatchIndirect,
	mtlEncoderInsertSignpost,
	mtlEncoderPopDebugGroup,
	mtlEncoderPushDebugGroup,
	mtlForgetCommitted,
	mtlBeginComputePass,
	mtlMaxBufferLength,
	mtlMaxThreadsPerThreadgroup,
	mtlNewComputePipeline,
	mtlNewMappableBuffer,
	mtlNewSampleBuffer,
	mtlPassSamples,
	mtlPassVisibility,
	mtlPipelineLabel,
	mtlPopDebugGroup,
	mtlPushDebugGroup,
	mtlReleaseComputePipeline,
	mtlReleaseSampleBuffer,
	mtlResolveCounters,
	mtlSetLabel,
	mtlSetVisibility,
	mtlSupportsFloat32Filtering,
	mtlSupportsRg11b10Render,
	mtlSupportsTimestamps,
	mtlNewStagingBuffer,
	mtlWaitCommitted,
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
	mtlNewTextureView,
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
const MAX_STAGE_BUFFERS = 31;
const MAX_DISPATCH_GROUPS = 65535;
const STORAGE_OFFSET_ALIGNMENT = 32;
const QUERY_BYTES = 8;
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
const TYPE_2D = 2;
const TYPE_2D_ARRAY = 3;
const TYPE_2D_MULTISAMPLE = 4;
const TYPE_CUBE = 5;
const TYPE_CUBE_ARRAY = 6;
const TYPE_3D = 7;
const MAX_TEXTURE_DIMENSION_2D = 16384;
const MAX_TEXTURE_DIMENSION_3D = 2048;
const MAX_TEXTURE_ARRAY_LAYERS = 2048;
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
const NO_COMPUTE_PIPELINE = null as unknown as Ptr<MtlComputePipelineImpl>;
const NO_SAMPLE_BUFFER = null as unknown as Ptr<MtlSampleBufferImpl>;

enum BindingKind {
	Uniform,
	Texture,
	Sampler,
	StorageBuffer,
	StorageTexture,
}

enum QueryState {
	Unwritten,
	Open,
	Written,
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
	usage: int32;
	inPlace: boolean;
	gpuUseFrame: int64;
	mapMode: int32;
	mapOffset: int64;
	mapSize: int64;
}

struct TextureSlot {
	id: uint32;
	width: int32;
	height: int32;
	format: GPUTextureFormat;
	usage: int32;
	sampleCount: int32;
	mipLevels: int32;
	layers: int32;
	volume: boolean;
	cube: boolean;
	natives: Ptr<MtlTextureImpl>[2];
	active: int32;
	writtenFrame: int64;
	inPlace: boolean;
	swapchainView: uint32;
}

struct ViewSlot {
	id: uint32;
	texture: uint32;
	baseMip: int32;
	mipCount: int32;
	baseLayer: int32;
	layerCount: int32;
	viewType: int32;
	direct: boolean;
	attachable: boolean;
	volumeTarget: boolean;
	natives: Ptr<MtlTextureImpl>[2];
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
	computeStage: boolean;
	writable: boolean;
	nativeSlot: int32;
	size: int32;
}

struct ShaderSlot {
	id: uint32;
	vertexLibrary: Ptr<MtlLibraryImpl>;
	fragmentLibrary: Ptr<MtlLibraryImpl>;
	vertex: Ptr<MtlFunctionImpl>;
	fragment: Ptr<MtlFunctionImpl>;
	computeLibrary: Ptr<MtlLibraryImpl>;
	compute: Ptr<MtlFunctionImpl>;
	computeEntry: string;
	workgroup: int32[3];
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
	computeState: Ptr<MtlComputePipelineImpl>;
	compute: boolean;
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
	serial: int64;
	groupBase: int32;
	occlusionSet: uint32;
	occlusionOpen: boolean;
	occlusionIndex: int32;
	width: int32;
	height: int32;
	screen: boolean;
}

struct ComputeState {
	active: boolean;
	groupBase: int32;
	pipeline: uint32;
	bindGroup: uint32;
	dirty: boolean;
}

struct QuerySetSlot {
	id: uint32;
	timestamp: boolean;
	count: int32;
	samples: Ptr<MtlSampleBufferImpl>;
	visibility: Ptr<MtlBufferImpl>;
	state: Vec<QueryState>;
	usedPass: Vec<int64>;
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
let computeBound: ComputeState = { active: false };
let computeEncoder: Ptr<MtlEncoderImpl> = NO_ENCODER;
let groupDepth: int32 = 0;
let passSerial: int64 = 0;
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
let pipelines: Pool<PipelineSlot> = newPool<PipelineSlot>("metal", "GPURenderPipeline", "render or compute pipeline", { id: 0 });
let layouts: Pool<LayoutSlot> = newPool<LayoutSlot>("metal", "GPUBindGroupLayout", "bind group layout", { id: 0 });
let bindGroups: Pool<BindGroupSlot> = newPool<BindGroupSlot>("metal", "GPUBindGroup", "bind group", { id: 0 });
let querySets: Pool<QuerySetSlot> = newPool<QuerySetSlot>("metal", "GPUQuerySet", "query set", { id: 0 });

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

function colorInfo(pixel: int32, bytesPerPixel: int32): FormatInfo {
	return { pixel: pixel, bytesPerPixel: bytesPerPixel, depth: false, stencil: false };
}

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => colorInfo(PIXEL_R8_UNORM, 1),
		"rg8unorm" => colorInfo(30, 2),
		"rgba8unorm" => colorInfo(PIXEL_RGBA8_UNORM, 4),
		"rgba8unorm-srgb" => colorInfo(71, 4),
		"bgra8unorm" => colorInfo(PIXEL_BGRA8_UNORM, 4),
		"bgra8unorm-srgb" => colorInfo(81, 4),
		"rgba8uint" => colorInfo(73, 4),
		"rgba8sint" => colorInfo(74, 4),
		"r16float" => colorInfo(25, 2),
		"rg16float" => colorInfo(65, 4),
		"rgba16float" => colorInfo(PIXEL_RGBA16_FLOAT, 8),
		"rgba16uint" => colorInfo(113, 8),
		"r32float" => colorInfo(55, 4),
		"rg32float" => colorInfo(105, 8),
		"rgba32float" => colorInfo(125, 16),
		"rgba32uint" => colorInfo(123, 16),
		"r32uint" => colorInfo(53, 4),
		"rgb10a2unorm" => colorInfo(90, 4),
		"rg11b10ufloat" => colorInfo(92, 4),
		"depth16unorm" => ({ pixel: 250, bytesPerPixel: 2, depth: true, stencil: false }),
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
		"storage-buffer" => BindingKind.StorageBuffer,
		"storage-texture" => BindingKind.StorageTexture,
		_ => stopOnMember("GPUShaderBinding.kind", kind) as BindingKind,
	};
}

function vertexStage(binding: GPUShaderBinding): boolean {
	const both = (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);
	if (binding.visibility == both) { stop(`shader binding ${binding.binding} is visible to vertex and fragment, which is not ported to metal yet`); }
	return binding.visibility == (GPUShaderStage.VERTEX as int32);
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
	computeBound = { active: false };
	computeEncoder = NO_ENCODER;
	groupDepth = 0;
	bound = { pipeline: 0 };
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(bindGroups);
	reset(querySets);
	canvas = canvasOf(environment);
	swapchainColor = reserveSwapchainTexture(canvas.format);
	const depthFormat: string = canvas.depthFormat;
	swapchainDepth = depthFormat == "" ? 0 : reserveSwapchainTexture(canvas.depthFormat);
	textures.slots[textures.slotIndex(swapchainColor)].usage |= GPUTextureUsage.COPY_SRC as int32;
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
		mipLevels: 1,
		layers: 1,
		natives: [NO_TEXTURE, NO_TEXTURE],
		swapchainView: viewId,
	});
	store(views, { id: viewId, texture: textureId, swapchain: true, attachable: true, swapchainTexture: NO_TEXTURE, swapchainResolve: NO_TEXTURE });
	return textureId;
}

export function shutdown(): void {
	if (pass.active || computeBound.active) { stop("shutdown with a pass still open"); }
	if (commandBuffer != null) {
		mtlCommit(commandBuffer);
		commandBuffer = NO_COMMAND_BUFFER;
	}
	mtlFrameSemaphoreWaitAll();
	mtlForgetCommitted();
	for (const id of querySets.liveIds()) { destroyQuerySet({ id: id }); }
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
	reset(querySets);
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
	checkedBufferUsage(usage);
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
	const mapped = mapWrite || has(usage, GPUBufferUsage.MAP_READ as int32);
	const native = mapped
		? mtlNewMappableBuffer(device, descriptor.size, mapWrite ? 1 : 0)
		: mtlNewBuffer(device, descriptor.size, sharedStorage ? 1 : 0);
	if (native == null) { stop(`newBufferWithLength failed for ${labelOf(descriptor.label)}`); }
	mtlSetLabel(native as Ptr<void>, labelText(descriptor.label));
	const slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		natives: [native, NO_BUFFER],
		active: 0,
		writtenFrame: has(usage, GPUBufferUsage.COPY_DST as int32) ? -1 : -2,
		writtenEnd: 0,
		usage: usage,
		inPlace: mapped || has(usage, GPUBufferUsage.STORAGE as int32) || has(usage, GPUBufferUsage.QUERY_RESOLVE as int32),
		gpuUseFrame: -1,
	};
	store(buffers, slot);
	return { id: id };
}

function labelText(label: string | null): string {
	if (label === null) { return ""; }
	return label;
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
	if (buffers.slots[index].mapMode != 0) { stop(`writeBuffer on GPUBuffer ${buffer.id}, which is mapped`); }
	if (buffers.slots[index].inPlace) {
		writeBufferInPlace(index, offset, data, bytes);
		return;
	}
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

// A buffer a GPU copy writes, or a mappable one, keeps one live copy, so a CPU write joins the
// frame's command buffer behind the earlier copies instead of landing before them.
function writeBufferInPlace<T>(index: int32, offset: int64, data: Readonly<Span<T>>, bytes: int64): void {
	if (pass.active || computeBound.active) { stop(`writeBuffer on GPUBuffer ${buffers.slots[index].id} inside a pass: its copies are GPU commands`); }
	beginFrame();
	const staging = mtlNewStagingBuffer(device, data[0], 0, bytes);
	if (staging == null) { stop(`newBufferWithBytes failed for the write to GPUBuffer ${buffers.slots[index].id}`); }
	mtlBlitBufferToBuffer(commandBuffer, staging, 0, buffers.slots[index].natives[buffers.slots[index].active], offset, bytes);
	mtlReleaseBuffer(staging);
	buffers.slots[index].gpuUseFrame = frame;
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
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	if (descriptor.size.depthOrArrayLayers < 0) { stop("GPUTextureDescriptor.size.depthOrArrayLayers is negative"); }
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const largestSide = volume ? Math.max(Math.max(width, height), layers) : Math.max(width, height);
	const sideLimit = volume ? MAX_TEXTURE_DIMENSION_3D : MAX_TEXTURE_DIMENSION_2D;
	if (largestSide > sideLimit || (!volume && layers > MAX_TEXTURE_ARRAY_LAYERS)) {
		stop(`GPUTextureDescriptor.size ${width}x${height}x${layers} is over the limits ${sideLimit} per side and ${MAX_TEXTURE_ARRAY_LAYERS} array layers`);
	}
	const mipLevels = checkedMipLevelCount(descriptor, volume, layers);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && mtlSupportsSampleCount(device, sampleCount) == 0) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	checkedMultisample(sampleCount, volume, layers, mipLevels, attachment);
	const storage = has(usage, GPUTextureUsage.STORAGE_BINDING as int32);
	if (storage && (sampleCount != 1 || info.depth)) { stop("GPUTextureUsage.STORAGE_BINDING takes a single-sample colour texture"); }
	if (volume && info.depth) { stop("WebGPU allows a depth or stencil format only on a 2d texture"); }
	const cube = !volume && layers % 6 == 0 && width == height && has(usage, GPUTextureUsage.TEXTURE_BINDING as int32) && sampleCount == 1;
	const native = newTexture(width, height, layers, mipLevels, volume, info.pixel, sampleCount, attachment, storage);
	if (native == null) { stop(`newTextureWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	mtlSetLabel(native as Ptr<void>, labelText(descriptor.label));
	const slot: TextureSlot = {
		id: id,
		width: width,
		height: height,
		format: descriptor.format,
		usage: usage,
		sampleCount: sampleCount,
		mipLevels: mipLevels,
		layers: layers,
		volume: volume,
		cube: cube,
		natives: [native, NO_TEXTURE],
		active: 0,
		writtenFrame: -1,
		inPlace: false,
		swapchainView: 0,
	};
	store(textures, slot);
	return { id: id };
}

function naturalType(volume: boolean, layers: int32, sampleCount: int32): int32 {
	if (volume) { return TYPE_3D; }
	if (sampleCount > 1) { return TYPE_2D_MULTISAMPLE; }
	return layers > 1 ? TYPE_2D_ARRAY : TYPE_2D;
}

function newTexture(
	width: int32,
	height: int32,
	layers: int32,
	mipLevels: int32,
	volume: boolean,
	pixel: int32,
	sampleCount: int32,
	attachment: boolean,
	storage: boolean,
): Ptr<MtlTextureImpl> {
	return mtlNewTexture(
		device,
		width,
		height,
		layers,
		mipLevels,
		naturalType(volume, layers, sampleCount),
		pixel,
		sampleCount,
		attachment ? 1 : 0,
		storage ? 1 : 0,
		sharedStorage ? 1 : 0,
	);
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
	const slot = textures.slots[index];
	const wholeOnly = slot.mipLevels == 1 && slot.layers == 1 && !slot.volume;
	const whole = wholeOnly && destination.origin.x == 0 && destination.origin.y == 0 && size.width == slot.width && size.height == slot.height;
	if (!whole || slot.inPlace || has(slot.usage, (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.STORAGE_BINDING as int32)) || slot.writtenFrame == frame) {
		writeTextureByBlit(index, data, destination, layout, rowPitch, size);
		return;
	}
	beginFrame();
	if (textures.slots[index].writtenFrame >= 0) { nextTextureCopy(index); }
	textures.slots[index].writtenFrame = frame;
	const native = textures.slots[index].natives[textures.slots[index].active];
	mtlWriteTexture(native, data[0], layout.offset, rowPitch, slot.width, slot.height);
}

// A write that is not a whole single-subresource texture lands through a staging buffer and a blit
// in the frame's command buffer, so it follows the frame's earlier reads of the texture in queue
// order; a CPU `replaceRegion` would not.
function writeTextureByBlit<T>(
	index: int32,
	data: Readonly<Span<T>>,
	destination: GPUTexelCopyTextureInfo,
	layout: GPUTexelCopyBufferLayout,
	rowPitch: int32,
	size: GPUExtent3D,
): void {
	if (pass.active || computeBound.active) { stop(`writeTexture of ${size.width}x${size.height} on GPUTexture ${textures.slots[index].id} inside a pass: a partial or repeated write is a GPU copy`); }
	const bytesPerPixel = formatInfo(textures.slots[index].format, "texture format").bytesPerPixel;
	const imageBytes = (rowPitch as int64) * (layout.rowsPerImage as int64);
	const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (rowPitch as int64) * ((size.height - 1) as int64) + ((size.width * bytesPerPixel) as int64);
	beginFrame();
	const staging = mtlNewStagingBuffer(device, data[0], layout.offset, span);
	if (staging == null) { stop(`newBufferWithBytes failed for the write to GPUTexture ${textures.slots[index].id}`); }
	const native = textures.slots[index].natives[textures.slots[index].active];
	if (textures.slots[index].volume) {
		mtlBlitBufferToTexture(commandBuffer, staging, 0, rowPitch, imageBytes as int32, size.width, size.height, size.depthOrArrayLayers, native, 0, destination.mipLevel, destination.origin.x, destination.origin.y, destination.origin.z);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlBlitBufferToTexture(commandBuffer, staging, imageBytes * (i as int64), rowPitch, 0, size.width, size.height, 1, native, destination.origin.z + i, destination.mipLevel, destination.origin.x, destination.origin.y, 0);
		}
	}
	mtlReleaseBuffer(staging);
	textures.slots[index].inPlace = true;
}

function nextTextureCopy(index: int32): void {
	const next = 1 - textures.slots[index].active;
	if (textures.slots[index].natives[next] == null) {
		const pixel = formatInfo(textures.slots[index].format, "texture format").pixel;
		textures.slots[index].natives[next] = newTexture(textures.slots[index].width, textures.slots[index].height, 1, 1, false, pixel, 1, false, false);
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
	if (textures.slots[index].sampleCount != 1) { stop(`writeTexture on GPUTexture ${textures.slots[index].id}, which is multisampled`); }
	const volume = textures.slots[index].volume;
	const mip = destination.mipLevel;
	const mips = textures.slots[index].mipLevels;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textures.slots[index].layers >> mip) : textures.slots[index].layers;
	return checkedTexelWritePitch(
		width,
		height,
		mips,
		depth,
		formatInfo(textures.slots[index].format, "texture format").bytesPerPixel,
		bytes,
		destination,
		layout,
		size,
	);
}

function viewTypeOf(descriptor: GPUTextureViewDescriptor, t: int32): int32 {
	let name: string = descriptor.dimension;
	if (name == "") { name = textures.slots[t].volume ? "3d" : (textures.slots[t].layers > 1 ? "2d-array" : "2d"); }
	if ((name == "3d") != textures.slots[t].volume) {
		stop(`GPUTextureViewDescriptor.dimension '${name}' does not match the ${textures.slots[t].volume ? "3d" : "2d"} GPUTexture ${textures.slots[t].id}`);
	}
	if (name == "2d") { return textures.slots[t].sampleCount > 1 ? TYPE_2D_MULTISAMPLE : TYPE_2D; }
	if (name == "2d-array") { return TYPE_2D_ARRAY; }
	if (name == "cube") { return TYPE_CUBE; }
	if (name == "cube-array") { return TYPE_CUBE_ARRAY; }
	if (name == "3d") { return TYPE_3D; }
	return stopOnMember("GPUTextureViewDescriptor.dimension", name);
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { return { id: textures.slots[t].swapchainView }; }
	const id = allocate(views);
	const layers = textures.slots[t].layers;
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? textures.slots[t].mipLevels - baseMip : descriptor.mipLevelCount;
	checkedViewMips(textures.slots[t].id, textures.slots[t].mipLevels, baseMip, mipCount);
	const viewType = viewTypeOf(descriptor, t);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (viewType == TYPE_3D) {
		checkedView3d(baseLayer, layerCount);
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (viewType == TYPE_2D || viewType == TYPE_2D_MULTISAMPLE) { layerCount = 1; }
		if (viewType == TYPE_CUBE) { layerCount = 6; }
		if (layerCount == 0) { layerCount = layers - baseLayer; }
		checkedViewLayers(textures.slots[t].id, layers, baseLayer, layerCount);
	}
	if (viewType == TYPE_CUBE || viewType == TYPE_CUBE_ARRAY) {
		checkedCubeView(textures.slots[t].id, textures.slots[t].cube, baseLayer, layerCount);
	}
	const volume = textures.slots[t].volume;
	const direct = viewType == naturalType(volume, layers, textures.slots[t].sampleCount)
		&& baseMip == 0 && mipCount == textures.slots[t].mipLevels && baseLayer == 0 && (volume || layerCount == layers);
	const slot: ViewSlot = {
		id: id,
		texture: texture.id,
		baseMip: baseMip,
		mipCount: mipCount,
		baseLayer: baseLayer,
		layerCount: layerCount,
		viewType: viewType,
		direct: direct,
		attachable: mipCount == 1 && layerCount == 1 && viewType != TYPE_CUBE && viewType != TYPE_CUBE_ARRAY,
		volumeTarget: volume && viewType == TYPE_3D,
		natives: [NO_TEXTURE, NO_TEXTURE],
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
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (views.slots[index].natives[s] != null) { mtlReleaseTexture(views.slots[index].natives[s]); }
	}
	views.slots[index] = { id: 0 };
	release(views, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views.slots[views.slotIndex(view.id)].texture }; }

function attachmentNative(v: int32): Ptr<MtlTextureImpl> {
	if (views.slots[v].swapchain) { return views.slots[v].swapchainTexture; }
	const t = textures.slotIndex(views.slots[v].texture);
	return textures.slots[t].natives[textures.slots[t].active];
}

function viewNative(v: int32): Ptr<MtlTextureImpl> {
	const base = attachmentNative(v);
	if (views.slots[v].swapchain || views.slots[v].direct) { return base; }
	const t = textures.slotIndex(views.slots[v].texture);
	const active = textures.slots[t].active;
	if (views.slots[v].natives[active] == null) {
		const layerCount = views.slots[v].viewType == TYPE_3D ? 1 : views.slots[v].layerCount;
		views.slots[v].natives[active] = mtlNewTextureView(
			base,
			formatInfo(textures.slots[t].format, "texture format").pixel,
			views.slots[v].viewType,
			views.slots[v].baseMip,
			views.slots[v].mipCount,
			views.slots[v].baseLayer,
			layerCount,
		);
		if (views.slots[v].natives[active] == null) { stop(`newTextureViewWithPixelFormat failed for GPUTexture ${textures.slots[t].id}`); }
	}
	return views.slots[v].natives[active];
}

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = views.slotIndex(textures.slots[textures.slotIndex(swapchainColor)].swapchainView);
	views.slots[v].swapchainTexture = mtlTextureFrom(swapchain.renderView);
	views.slots[v].swapchainResolve = swapchain.resolveView === null ? NO_TEXTURE : mtlTextureFrom(swapchain.resolveView);
	textures.slots[textures.slotIndex(swapchainColor)].natives[0] = swapchain.sampleCount > 1 ? views.slots[v].swapchainResolve : views.slots[v].swapchainTexture;
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
		labelText(descriptor.label),
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
	stopOnUnportedShaderBytecode("metal", descriptor);
	checkedIntegerTexturePairs(descriptor);
	const compute = descriptor.computeCode != "";
	if (compute && (descriptor.vertexCode != "" || descriptor.fragmentCode != "")) {
		stop("a GPUShaderModule is either a compute module or a vertex and fragment module");
	}
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		checkedVisibility(descriptor.bindings[i], compute);
		const native: NativeBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName),
			vertexStage: vertexStage(descriptor.bindings[i]),
			computeStage: compute,
			writable: bindingWritable(descriptor.bindings[i]),
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
	if (compute) {
		const size: int32[3] = descriptor.workgroupSize;
		if (size[0] <= 0 || size[1] <= 0 || size[2] <= 0) {
			stop("a compute GPUShaderModule needs workgroupSize: Metal takes the threadgroup size at dispatch");
		}
		const limitX = mtlMaxThreadsPerThreadgroup(device, 0);
		const limitY = mtlMaxThreadsPerThreadgroup(device, 1);
		const limitZ = mtlMaxThreadsPerThreadgroup(device, 2);
		if (size[0] > limitX || size[1] > limitY || size[2] > limitZ || size[0] * size[1] * size[2] > limitX) {
			stop(`workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the limits ${limitX}x${limitY}x${limitZ} and ${limitX} invocations`);
		}
		slot.workgroup = size;
		slot.computeEntry = descriptor.computeEntryPoint == "" ? "_main" : descriptor.computeEntryPoint;
		slot.computeLibrary = compileLibrary(descriptor.computeCode, "compute", descriptor.label);
		slot.compute = entryFunction(slot.computeLibrary, slot.computeEntry, "compute", descriptor.label);
	} else {
		slot.vertexLibrary = compileLibrary(descriptor.vertexCode, "vertex", descriptor.label);
		slot.fragmentLibrary = compileLibrary(descriptor.fragmentCode, "fragment", descriptor.label);
		slot.vertex = entryFunction(slot.vertexLibrary, descriptor.vertexEntryPoint, "vertex", descriptor.label);
		slot.fragment = entryFunction(slot.fragmentLibrary, descriptor.fragmentEntryPoint, "fragment", descriptor.label);
	}
	slot.id = id;
	store(shaders, slot);
	return { id: slot.id };
}

function bindingWritable(binding: GPUShaderBinding): boolean {
	const kind: string = binding.kind;
	if (kind == "storage-buffer") {
		const bufferType: string = binding.bufferType;
		if (bufferType == "storage") { return true; }
		if (bufferType == "read-only-storage") { return false; }
		return stopOnMember("GPUShaderBinding.bufferType", bufferType) == 0;
	}
	if (kind == "storage-texture") {
		const access: string = binding.storageAccess;
		if (access == "write-only" || access == "read-write") { return true; }
		if (access == "read-only") { return false; }
		return stopOnMember("GPUShaderBinding.storageAccess", access) == 0;
	}
	return false;
}

function checkBinding(native: NativeBinding, group: int32): void {
	const expectedGroup = native.kind == BindingKind.Uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
	if (group != expectedGroup) {
		stop(`shader binding ${native.binding} (${native.kind.toString()}) belongs in group ${expectedGroup}, not ${group}`);
	}
	if (native.kind == BindingKind.Uniform && native.computeStage) {
		stop(`uniform binding ${native.binding} in a compute stage is not ported to metal yet`);
	}
	if (native.kind == BindingKind.StorageTexture && !native.computeStage) {
		stop(`storage texture binding ${native.binding} in a render stage is not ported to metal`);
	}
	if (native.kind == BindingKind.StorageBuffer && native.writable && !native.computeStage) {
		stop(`shader binding ${native.binding} is writable storage in a render stage: not ported to metal`);
	}
	const limit = match (native.kind) {
		BindingKind.Uniform => MAX_STAGE_UNIFORM_BUFFERS,
		BindingKind.Texture => MAX_STAGE_TEXTURES,
		BindingKind.Sampler => MAX_STAGE_SAMPLERS,
		BindingKind.StorageBuffer => native.vertexStage ? VERTEX_BUFFER_BASE : MAX_STAGE_BUFFERS,
		BindingKind.StorageTexture => MAX_STAGE_TEXTURES,
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
	if (shaders.slots[index].compute != null) {
		mtlReleaseFunction(shaders.slots[index].compute);
		mtlReleaseLibrary(shaders.slots[index].computeLibrary);
	} else {
		mtlReleaseFunction(shaders.slots[index].vertex);
		mtlReleaseFunction(shaders.slots[index].fragment);
		mtlReleaseLibrary(shaders.slots[index].vertexLibrary);
		mtlReleaseLibrary(shaders.slots[index].fragmentLibrary);
	}
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
	if (shaders.slots[s].compute != null) { stop("a compute GPUShaderModule cannot make a GPURenderPipeline"); }
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule on Metal");
	}
	let slot: PipelineSlot = { id: 0, shader: descriptor.vertex.module.id };
	mtlPipelineReset();
	mtlPipelineLabel(labelText(descriptor.label));
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
	if (pipelines.slots[index].compute) {
		mtlReleaseComputePipeline(pipelines.slots[index].computeState);
	} else {
		mtlReleasePipeline(pipelines.slots[index].state);
		mtlReleaseDepthState(pipelines.slots[index].depth);
	}
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
		if (slot.entries[i].buffer.id == 0 || uniformOf(shader, slot.entries[i].binding) < 0) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			if (slot.entries[j].buffer.id != 0 && uniformOf(shader, slot.entries[j].binding) >= 0 && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: slot.id };
}

function uniformOf(shader: int32, binding: int32): int32 {
	for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
		if (shaders.slots[shader].uniforms[u].binding == binding) { return u; }
	}
	return -1;
}

function resourceOf(shader: int32, binding: int32): int32 {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		if (shaders.slots[shader].resources[r].binding == binding) { return r; }
	}
	return -1;
}

function checkStorageRange(entry: GPUBindGroupEntry, b: int32): void {
	if (!has(buffers.slots[b].usage, GPUBufferUsage.STORAGE as int32)) { stop(`bind group entry ${entry.binding} needs a STORAGE buffer`); }
	if (entry.offset < 0 || entry.offset % STORAGE_OFFSET_ALIGNMENT != 0) {
		stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${STORAGE_OFFSET_ALIGNMENT}`);
	}
	const bytes = entry.size == 0 ? buffers.slots[b].size - entry.offset : entry.size;
	if (bytes <= 0 || entry.offset + bytes > buffers.slots[b].size) {
		stop(`bind group entry ${entry.binding} range ${entry.offset}+${bytes} is not a positive size inside its buffer of ${buffers.slots[b].size}`);
	}
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = buffers.slotIndex(entry.buffer.id);
		const u = uniformOf(shader, entry.binding);
		if (u >= 0) {
			const binding = shaders.slots[shader].uniforms[u];
			if (!has(buffers.slots[b].usage, GPUBufferUsage.UNIFORM as int32)) { stop(`bind group entry ${entry.binding} needs a UNIFORM buffer`); }
			if (entry.offset < 0 || entry.offset % UNIFORM_OFFSET_ALIGNMENT != 0) {
				stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${UNIFORM_OFFSET_ALIGNMENT}`);
			}
			if (entry.offset + (binding.size as int64) > buffers.slots[b].size) {
				stop(`bind group entry ${entry.binding} offset ${entry.offset} overruns its buffer`);
			}
			if (entry.size != 0 && entry.size < (binding.size as int64)) {
				stop(`bind group entry ${entry.binding} size ${entry.size} is below its block of ${binding.size}`);
			}
			return;
		}
		const r = resourceOf(shader, entry.binding);
		if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.StorageBuffer) {
			checkStorageRange(entry, b);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	const r = resourceOf(shader, entry.binding);
	if (entry.textureView.id != 0) {
		const v = views.slotIndex(entry.textureView.id);
		const t = textures.slotIndex(views.slots[v].texture);
		if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.Texture) {
			if (!has(textures.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
				stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`);
			}
			return;
		}
		if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.StorageTexture) {
			if (!has(textures.slots[t].usage, GPUTextureUsage.STORAGE_BINDING as int32) || views.slots[v].mipCount != 1) {
				stop(`bind group entry ${entry.binding}: the view's texture lacks STORAGE_BINDING or the view spans several mips`);
			}
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplers.slotIndex(entry.sampler.id);
	if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.Sampler) { return; }
	stop(`bind group ${group} entry ${entry.binding} (sampler) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroups.slotIndex(bindGroup.id);
	bindGroups.slots[index] = { id: 0 };
	release(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (pass.active) { stop("finish with a render pass still open"); }
	if (computeBound.active) { stop("finish with a compute pass still open"); }
	checkGroupsClosed(0, "finish");
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
	if (pass.active || computeBound.active) { stop("beginRenderPass with a pass already open"); }
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	if (descriptor.occlusionQuerySet.id != 0 && querySets.slots[querySets.slotIndex(descriptor.occlusionQuerySet.id)].timestamp) {
		stop("GPURenderPassDescriptor.occlusionQuerySet is a timestamp set: an occlusion set is required");
	}
	passSerial += 1;
	pass = { active: true, serial: passSerial, groupBase: groupDepth, occlusionSet: descriptor.occlusionQuerySet.id };
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
		checkedSingleSubresource(`colorAttachments[${i}].view`, views.slots[v].attachable);
		const slice = descriptor.colorAttachments[i].depthSlice;
		if (views.slots[v].volumeTarget) {
			checkedDepthSlice(i, slice, Math.max(1, textures.slots[t].layers >> views.slots[v].baseMip), views.slots[v].baseMip, textures.slots[t].id);
		} else {
			checkedNoDepthSlice(i, slice);
		}
		passExtent(v);
		const resolveId = descriptor.colorAttachments[i].resolveTarget.id;
		const resolve = resolveTexture(i, v, resolveId);
		const r = resolveId == 0 ? v : views.slotIndex(resolveId);
		if (views.slots[v].swapchain) { pass.screen = true; }
		const color = descriptor.colorAttachments[i].clearValue;
		mtlPassColor(
			i,
			attachmentNative(v),
			views.slots[v].baseMip,
			views.slots[v].baseLayer,
			slice,
			resolve,
			views.slots[r].baseMip,
			views.slots[r].baseLayer,
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
		checkedSingleSubresource("depthStencilAttachment.view", views.slots[v].attachable);
		passExtent(v);
		mtlPassDepth(
			attachmentNative(v),
			views.slots[v].baseMip,
			views.slots[v].baseLayer,
			loadAction(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp"),
			storeAction(descriptor.depthStencilAttachment.depthStoreOp, false, "depthStencilAttachment.depthStoreOp"),
			descriptor.depthStencilAttachment.depthClearValue,
			info.stencil ? 1 : 0,
		);
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	if (descriptor.timestampWrites.querySet.id != 0) {
		const q = querySets.slotIndex(descriptor.timestampWrites.querySet.id);
		mtlPassSamples(querySets.slots[q].samples, descriptor.timestampWrites.beginningOfPassWriteIndex, descriptor.timestampWrites.endOfPassWriteIndex);
		markTimestampsWritten(q, descriptor.timestampWrites);
	}
	if (pass.occlusionSet != 0) { mtlPassVisibility(querySets.slots[querySets.slotIndex(pass.occlusionSet)].visibility); }
	encoder = mtlBeginPass(commandBuffer);
	if (encoder == null) { stop("renderCommandEncoderWithDescriptor returned nil"); }
	mtlSetLabel(encoder as Ptr<void>, labelText(descriptor.label));
	mtlSetViewport(encoder, 0.0, 0.0, pass.width, pass.height, 0.0, 1.0);
	bound.appliedPipeline = 0;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
	return { id: 1 };
}

function passExtent(v: int32): void {
	const t = textures.slotIndex(views.slots[v].texture);
	const width = Math.max(1, textures.slots[t].width >> views.slots[v].baseMip);
	const height = Math.max(1, textures.slots[t].height >> views.slots[v].baseMip);
	checkedPassExtent(pass.width, pass.height, width, height);
	pass.width = width;
	pass.height = height;
}

function resolveTexture(attachment: int32, colorView: int32, resolveId: uint32): Ptr<MtlTextureImpl> {
	const colorTexture = textures.slotIndex(views.slots[colorView].texture);
	if (views.slots[colorView].swapchain && resolveId == 0) { return views.slots[colorView].swapchainResolve; }
	if (resolveId == 0) { return NO_TEXTURE; }
	const r = views.slotIndex(resolveId);
	const resolve = textures.slotIndex(views.slots[r].texture);
	checkedSingleSubresource(`colorAttachments[${attachment}].resolveTarget`, views.slots[r].attachable);
	checkedResolveTarget(
		attachment,
		textures.slots[colorTexture].sampleCount,
		textures.slots[colorTexture].width,
		textures.slots[colorTexture].height,
		Math.max(1, textures.slots[resolve].width >> views.slots[r].baseMip),
		Math.max(1, textures.slots[resolve].height >> views.slots[r].baseMip),
	);
	if (textures.slots[resolve].sampleCount != 1 || !has(textures.slots[resolve].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample color RENDER_ATTACHMENT`);
	}
	return attachmentNative(r);
}

export function endPass(): void {
	if (!pass.active) { stop("end without an open render pass"); }
	if (pass.occlusionOpen) { stop("end with an occlusion query still open"); }
	checkGroupsClosed(pass.groupBase, "end");
	mtlEndPass(encoder);
	encoder = NO_ENCODER;
	if (pass.screen) { mtlPresentDrawable(commandBuffer); }
	pass.active = false;
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	if (pipelines.slots[pipelines.slotIndex(pipeline.id)].compute) { stop(`GPUPipeline ${pipeline.id} is a compute pipeline: setPipeline on a render pass takes a render pipeline`); }
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
		} else if (binding.kind == BindingKind.StorageBuffer) {
			const native = liveBuffer(buffers.slotIndex(bindGroups.slots[g].entries[e].buffer.id));
			if (binding.vertexStage) {
				mtlSetVertexBuffer(encoder, native, bindGroups.slots[g].entries[e].offset, binding.nativeSlot);
			} else {
				mtlSetFragmentBuffer(encoder, native, bindGroups.slots[g].entries[e].offset, binding.nativeSlot);
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
		const offset = (bound.dynamicOffsets[bindGroups.slots[g].dynamicIndex[e]] as int64) + bindGroups.slots[g].entries[e].offset;
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

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers.slots[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	return index;
}

function copyDestinationBuffer(buffer: GPUBuffer, member: string): int32 {
	const index = copyableBuffer(buffer, member, GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	buffers.slots[index].inPlace = true;
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	const index = textures.slotIndex(info.texture.id);
	if (!has(textures.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures.slots[index].swapchainView != 0) {
		if (textures.slots[index].natives[0] == null) { stop(`${member}: the swapchain texture has no back buffer to copy`); }
		return index;
	}
	if (textures.slots[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	return index;
}

function copyDestinationTexture(info: GPUTexelCopyTextureInfo, member: string): int32 {
	const index = copyableTexture(info, member, GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	textures.slots[index].inPlace = true;
	return index;
}

function copyRegion(member: string, info: GPUTexelCopyTextureInfo, index: int32, size: GPUExtent3D): void {
	checkedTexelCopyRegion(
		member,
		textures.slots[index].id,
		textures.slots[index].width,
		textures.slots[index].height,
		textures.slots[index].mipLevels,
		textures.slots[index].layers,
		textures.slots[index].volume,
		info,
		size,
	);
}

function texelCopyBytes(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): int32 {
	const format = formatInfo(textures.slots[index].format, "texture format");
	if (format.depth) {
		checkedDepthTexelCopy(member, textures.slots[index].id, textures.slots[index].format, format.stencil, writes, textures.slots[index].width, textures.slots[index].height, copy.mipLevel, size);
	}
	return format.bytesPerPixel;
}

function liveTexture(index: int32): Ptr<MtlTextureImpl> { return textures.slots[index].natives[textures.slots[index].active]; }
function liveBuffer(index: int32): Ptr<MtlBufferImpl> { return buffers.slots[index].natives[buffers.slots[index].active]; }

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination, "copyBufferToBuffer destination");
	checkedBufferCopy(source.id, buffers.slots[from].size, sourceOffset, destination.id, buffers.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	beginFrame();
	mtlBlitBufferToBuffer(commandBuffer, liveBuffer(from), sourceOffset, liveBuffer(to), destinationOffset, size);
	buffers.slots[from].gpuUseFrame = frame;
	buffers.slots[to].gpuUseFrame = frame;
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination.buffer, "copyTextureToBuffer destination");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const bytesPerPixel = texelCopyBytes(from, "copyTextureToBuffer source", false, source, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", bytesPerPixel, buffers.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	beginFrame();
	if (textures.slots[from].volume) {
		mtlBlitTextureToBuffer(commandBuffer, liveTexture(from), 0, source.mipLevel, source.origin.x, source.origin.y, source.origin.z, size.width, size.height, size.depthOrArrayLayers, liveBuffer(to), destination.offset, bytesPerRow, imageBytes as int32);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlBlitTextureToBuffer(commandBuffer, liveTexture(from), source.origin.z + i, source.mipLevel, source.origin.x, source.origin.y, 0, size.width, size.height, 1, liveBuffer(to), destination.offset + imageBytes * (i as int64), bytesPerRow, (bytesPerRow * size.height));
		}
	}
	buffers.slots[to].gpuUseFrame = frame;
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationTexture(destination, "copyBufferToTexture destination");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const bytesPerPixel = texelCopyBytes(to, "copyBufferToTexture destination", true, destination, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", bytesPerPixel, buffers.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	beginFrame();
	if (textures.slots[to].volume) {
		mtlBlitBufferToTexture(commandBuffer, liveBuffer(from), source.offset, bytesPerRow, imageBytes as int32, size.width, size.height, size.depthOrArrayLayers, liveTexture(to), 0, destination.mipLevel, destination.origin.x, destination.origin.y, destination.origin.z);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlBlitBufferToTexture(commandBuffer, liveBuffer(from), source.offset + imageBytes * (i as int64), bytesPerRow, 0, size.width, size.height, 1, liveTexture(to), destination.origin.z + i, destination.mipLevel, destination.origin.x, destination.origin.y, 0);
		}
	}
	buffers.slots[from].gpuUseFrame = frame;
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationTexture(destination, "copyTextureToTexture destination");
	copyRegion("copyTextureToTexture source", source, from, size);
	copyRegion("copyTextureToTexture destination", destination, to, size);
	checkedTextureToTextureCopy(
		source,
		destination,
		size,
		textures.slots[from].format,
		textures.slots[to].format,
		textures.slots[from].volume,
		textures.slots[to].volume,
		formatInfo(textures.slots[from].format, "texture format").depth,
		textures.slots[from].width,
		textures.slots[from].height,
	);
	beginFrame();
	if (textures.slots[from].volume) {
		mtlBlitTextureToTexture(commandBuffer, liveTexture(from), 0, source.mipLevel, source.origin.x, source.origin.y, source.origin.z, size.width, size.height, size.depthOrArrayLayers, liveTexture(to), 0, destination.mipLevel, destination.origin.x, destination.origin.y, destination.origin.z);
		return;
	}
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		mtlBlitTextureToTexture(commandBuffer, liveTexture(from), source.origin.z + i, source.mipLevel, source.origin.x, source.origin.y, 0, size.width, size.height, 1, liveTexture(to), destination.origin.z + i, destination.mipLevel, destination.origin.x, destination.origin.y, 0);
	}
}

// A mappable buffer is shared storage, so a mapped range is the buffer's own bytes once the GPU
// work that wrote them is done. The wait is on the last committed command buffer, never on the
// frame's open one: Metal runs a queue's buffers in order and the open one commits only after
// this call returns.
export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	const index = buffers.slotIndex(buffer.id);
	const length = checkedMapAsync(buffer.id, buffers.slots[index].usage, buffers.slots[index].mapMode, buffers.slots[index].size, mode, offset, size);
	if (buffers.slots[index].gpuUseFrame >= 0) {
		if (commandBuffer != null && buffers.slots[index].gpuUseFrame == frame) {
			stop(`mapAsync on GPUBuffer ${buffer.id} would wait for the frame's command buffer, which is not committed: submit the copy first`);
		}
		if (mtlWaitCommitted() == 0) { stop(`mapAsync on GPUBuffer ${buffer.id}: the command buffer that wrote it failed`); }
	}
	buffers.slots[index].mapMode = mode;
	buffers.slots[index].mapOffset = offset;
	buffers.slots[index].mapSize = length;
}

function mappedRange(member: string, buffer: GPUBuffer, mode: int32, offset: int64, size: int64): int64 {
	const slot = buffers.slots[buffers.slotIndex(buffer.id)];
	return checkedMappedRange(member, buffer.id, slot.size, slot.mapMode, slot.mapOffset, slot.mapSize, mode, offset, size);
}

// A copy of the mapped bytes: WebGPU's ArrayBuffer view has no MetaScript counterpart on a native pointer.
export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const length = mappedRange("getMappedRange", buffer, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	mtlCopyOut(liveBuffer(buffers.slotIndex(buffer.id)), offset, bytes[0], length);
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	mappedRange("writeMappedRange", buffer, GPUMapMode.WRITE as int32, offset, bytes);
	mtlCopyIn(liveBuffer(buffers.slotIndex(buffer.id)), offset, data[0], bytes);
}

export function unmap(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	checkedUnmap(buffer.id, buffers.slots[index].mapMode);
	buffers.slots[index].mapMode = 0;
}
export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const s = shaders.slotIndex(descriptor.compute.module.id);
	if (shaders.slots[s].compute == null) { stop("createComputePipeline needs a GPUShaderModule made with computeCode"); }
	const entry = descriptor.compute.entryPoint == "" ? "_main" : descriptor.compute.entryPoint;
	if (entry != shaders.slots[s].computeEntry) {
		stop(`compute.entryPoint '${entry}' differs from the module's computeEntryPoint '${shaders.slots[s].computeEntry}'`);
	}
	const id = allocate(pipelines);
	const state = mtlNewComputePipeline(device, shaders.slots[s].compute, labelText(descriptor.label));
	if (state == null) {
		const log: string = mtlErrorLog();
		stop(`newComputePipelineStateWithDescriptor failed for ${labelOf(descriptor.label)}:\n${log}`);
	}
	const size: int32[3] = shaders.slots[s].workgroup;
	const invocations = mtlComputeMaxThreads(state);
	if (size[0] * size[1] * size[2] > invocations) {
		stop(`workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the ${invocations} invocations this compute pipeline can run`);
	}
	const slot: PipelineSlot = { id: id, shader: descriptor.compute.module.id, compute: true, computeState: state };
	store(pipelines, slot);
	return { id: id };
}

export function beginComputePass(passEncoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	if (pass.active || computeBound.active) { stop("beginComputePass with a pass already open"); }
	if (descriptor.timestampWrites.querySet.id != 0) {
		stop("GPUComputePassDescriptor.timestampWrites is not ported to metal: a compute pass's counter sample is not written before a resolve that follows it in the same command buffer");
	}
	beginFrame();
	computeEncoder = mtlBeginComputePass(commandBuffer, labelText(descriptor.label));
	if (computeEncoder == null) { stop("computeCommandEncoder returned nil"); }
	computeBound = { active: true, groupBase: groupDepth };
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	if (!computeBound.active) { stop("setPipeline outside a compute pass"); }
	if (!pipelines.slots[pipelines.slotIndex(pipeline.id)].compute) { stop(`GPUPipeline ${pipeline.id} is not a compute pipeline`); }
	computeBound.pipeline = pipeline.id;
	computeBound.dirty = true;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (!computeBound.active) { stop("setBindGroup outside a compute pass"); }
	if (index != GPU_RESOURCE_GROUP) { stop(`a compute pipeline has no uniform group: setBindGroup(${index}) takes group ${GPU_RESOURCE_GROUP}`); }
	if (dynamicOffsets.length != 0) { stop("a compute bind group takes no dynamic offsets"); }
	if (bindGroup.id != 0 && bindGroups.slots[bindGroups.slotIndex(bindGroup.id)].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups.slots[bindGroups.slotIndex(bindGroup.id)].group}`);
	}
	computeBound.bindGroup = bindGroup.id;
	computeBound.dirty = true;
}

function applyCompute(): int32 {
	if (!computeBound.active) { stop("dispatch outside a compute pass"); }
	if (computeBound.pipeline == 0) { stop("dispatch without setPipeline"); }
	const p = pipelines.slotIndex(computeBound.pipeline);
	const s = shaders.slotIndex(pipelines.slots[p].shader);
	if (computeBound.dirty) {
		computeBound.dirty = false;
		mtlComputeSetPipeline(computeEncoder, pipelines.slots[p].computeState);
		if (shaders.slots[s].resourceCount > 0) {
			if (computeBound.bindGroup == 0) { stop("the compute pipeline reads bind group 1, which is not set"); }
			applyComputeResources(s, bindGroups.slotIndex(computeBound.bindGroup));
		}
	}
	return s;
}

function applyComputeResources(s: int32, g: int32): void {
	for (let r = 0; r < shaders.slots[s].resourceCount; r++) {
		const binding: NativeBinding = shaders.slots[s].resources[r];
		const entry: GPUBindGroupEntry = bindGroups.slots[g].entries[entryOf(g, binding.binding)];
		if (binding.kind == BindingKind.Sampler) {
			mtlComputeSetSampler(computeEncoder, samplers.slots[samplers.slotIndex(entry.sampler.id)].native, binding.nativeSlot);
		} else if (binding.kind == BindingKind.StorageBuffer) {
			mtlComputeSetBuffer(computeEncoder, liveBuffer(buffers.slotIndex(entry.buffer.id)), entry.offset, binding.nativeSlot);
		} else {
			mtlComputeSetTexture(computeEncoder, viewNative(views.slotIndex(entry.textureView.id)), binding.nativeSlot);
		}
	}
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	checkedDispatch(x, y, z, MAX_DISPATCH_GROUPS);
	const s = applyCompute();
	if (x == 0 || y == 0 || z == 0) { return; }
	const size: int32[3] = shaders.slots[s].workgroup;
	mtlDispatch(computeEncoder, x, y, z, size[0], size[1], size[2]);
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = buffers.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, buffers.slots[b].usage, buffers.slots[b].size, offset);
	const s = applyCompute();
	const size: int32[3] = shaders.slots[s].workgroup;
	mtlDispatchIndirect(computeEncoder, liveBuffer(b), offset, size[0], size[1], size[2]);
}

export function endComputePass(): void {
	if (!computeBound.active) { stop("end without an open compute pass"); }
	checkGroupsClosed(computeBound.groupBase, "end");
	mtlEndPass(computeEncoder);
	computeEncoder = NO_ENCODER;
	computeBound = { active: false };
}

export function limits(): GPUSupportedLimits {
	const maxBuffer = mtlMaxBufferLength(device);
	const threadsX = mtlMaxThreadsPerThreadgroup(device, 0);
	return {
		maxTextureDimension1D: MAX_TEXTURE_DIMENSION_2D,
		maxTextureDimension2D: MAX_TEXTURE_DIMENSION_2D,
		maxTextureDimension3D: MAX_TEXTURE_DIMENSION_3D,
		maxTextureArrayLayers: MAX_TEXTURE_ARRAY_LAYERS,
		maxBindGroups: GPU_RESOURCE_GROUP + 1,
		maxSampledTexturesPerShaderStage: Math.min(MAX_STAGE_TEXTURES, GPU_MAX_BIND_GROUP_ENTRIES),
		maxSamplersPerShaderStage: Math.min(MAX_STAGE_SAMPLERS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageBuffersPerShaderStage: GPU_MAX_BIND_GROUP_ENTRIES,
		maxStorageTexturesPerShaderStage: GPU_MAX_BIND_GROUP_ENTRIES,
		maxUniformBuffersPerShaderStage: Math.min(MAX_STAGE_UNIFORM_BUFFERS, GPU_MAX_UNIFORM_BLOCKS),
		maxUniformBufferBindingSize: maxBuffer,
		maxStorageBufferBindingSize: maxBuffer,
		maxVertexBuffers: GPU_MAX_VERTEX_BUFFERS,
		maxVertexAttributes: GPU_MAX_VERTEX_ATTRIBUTES,
		maxColorAttachments: GPU_MAX_COLOR_ATTACHMENTS,
		maxComputeWorkgroupSizeX: threadsX,
		maxComputeWorkgroupSizeY: mtlMaxThreadsPerThreadgroup(device, 1),
		maxComputeWorkgroupSizeZ: mtlMaxThreadsPerThreadgroup(device, 2),
		maxComputeInvocationsPerWorkgroup: threadsX,
		maxComputeWorkgroupsPerDimension: MAX_DISPATCH_GROUPS,
		minUniformBufferOffsetAlignment: UNIFORM_OFFSET_ALIGNMENT,
		minStorageBufferOffsetAlignment: STORAGE_OFFSET_ALIGNMENT,
	};
}

export function features(): GPUSupportedFeatures {
	let bits: uint32 = featureBit("float32-blendable");
	if (mtlSupportsTimestamps(device) == 1) { bits |= featureBit("timestamp-query"); }
	if (mtlSupportsFloat32Filtering(device) == 1) { bits |= featureBit("float32-filterable"); }
	if (mtlSupportsRg11b10Render(device) == 1) { bits |= featureBit("rg11b10ufloat-renderable"); }
	return { bits: bits };
}

function checkGroupsClosed(base: int32, what: string): void {
	if (groupDepth != base) { stop(`${what} with ${groupDepth - base} debug groups still open`); }
}

// Outside a pass a group lives on the frame's command buffer, inside one on the pass's encoder,
// so a pass cannot pop a group it did not push.
export function pushDebugGroup(label: string): void {
	if (pass.active) {
		mtlEncoderPushDebugGroup(encoder, label);
	} else if (computeBound.active) {
		mtlEncoderPushDebugGroup(computeEncoder, label);
	} else {
		beginFrame();
		mtlPushDebugGroup(commandBuffer, label);
	}
	groupDepth += 1;
}

export function popDebugGroup(): void {
	const base = pass.active ? pass.groupBase : (computeBound.active ? computeBound.groupBase : 0);
	checkedPopDebugGroup(groupDepth, base);
	if (pass.active) {
		mtlEncoderPopDebugGroup(encoder);
	} else if (computeBound.active) {
		mtlEncoderPopDebugGroup(computeEncoder);
	} else {
		mtlPopDebugGroup(commandBuffer);
	}
	groupDepth -= 1;
}

// A command buffer has no signpost, so a marker outside a pass is an empty group.
export function insertDebugMarker(label: string): void {
	if (pass.active) {
		mtlEncoderInsertSignpost(encoder, label);
	} else if (computeBound.active) {
		mtlEncoderInsertSignpost(computeEncoder, label);
	} else {
		beginFrame();
		mtlPushDebugGroup(commandBuffer, label);
		mtlPopDebugGroup(commandBuffer);
	}
}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	if (kind != "timestamp" && kind != "occlusion") { stopOnMember("GPUQuerySetDescriptor.type", kind); }
	const timestamp = kind == "timestamp";
	checkedQuerySetCount(descriptor.count);
	if (timestamp && mtlSupportsTimestamps(device) == 0) {
		stop("this device has no timestamp queries: features().has('timestamp-query') is false (MTLCounterSamplingPointAtStageBoundary and a nanosecond timestamp counter are required)");
	}
	const id = allocate(querySets);
	let slot: QuerySetSlot = {
		id: id,
		timestamp: timestamp,
		count: descriptor.count,
		samples: NO_SAMPLE_BUFFER,
		visibility: NO_BUFFER,
		state: new Array(descriptor.count),
		usedPass: new Array(descriptor.count),
	};
	if (timestamp) {
		slot.samples = mtlNewSampleBuffer(device, descriptor.count, labelText(descriptor.label));
		if (slot.samples == null) {
			const log: string = mtlErrorLog();
			stop(`newCounterSampleBufferWithDescriptor failed for ${labelOf(descriptor.label)}:\n${log}`);
		}
	} else {
		slot.visibility = mtlNewMappableBuffer(device, (descriptor.count as int64) * QUERY_BYTES, 0);
		if (slot.visibility == null) { stop(`newBufferWithLength failed for ${labelOf(descriptor.label)}`); }
		mtlSetLabel(slot.visibility as Ptr<void>, labelText(descriptor.label));
	}
	store(querySets, slot);
	return { id: id };
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySets.slotIndex(querySet.id);
	if (querySets.slots[index].timestamp) {
		mtlReleaseSampleBuffer(querySets.slots[index].samples);
	} else {
		mtlReleaseBuffer(querySets.slots[index].visibility);
	}
	querySets.slots[index] = { id: 0 };
	release(querySets, querySet.id);
}

function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySets.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets.slots[q].timestamp, querySets.slots[q].count);
}

function markTimestampsWritten(q: int32, writes: GPUPassTimestampWrites): void {
	if (writes.beginningOfPassWriteIndex >= 0) { querySets.slots[q].state[writes.beginningOfPassWriteIndex] = QueryState.Written; }
	if (writes.endOfPassWriteIndex >= 0) { querySets.slots[q].state[writes.endOfPassWriteIndex] = QueryState.Written; }
}

// A timestamp resolves in the counters' own ticks, which are nanoseconds on the devices
// features() reports timestamp-query for (an Intel GPU's tick is 83.333 ns and is refused).
export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	if (pass.active || computeBound.active) { stop("resolveQuerySet inside a pass"); }
	const q = querySets.slotIndex(querySet.id);
	const b = buffers.slotIndex(destination.id);
	const bytes = checkedResolveQuerySet(
		querySets.slots[q].count,
		firstQuery,
		queryCount,
		destination.id,
		buffers.slots[b].usage,
		buffers.slots[b].size,
		destinationOffset,
	);
	if (queryCount == 0) { return; }
	for (let i = 0; i < queryCount; i++) {
		const state = querySets.slots[q].state[firstQuery + i];
		if (state == QueryState.Unwritten) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QueryState.Open) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	beginFrame();
	if (querySets.slots[q].timestamp) {
		mtlResolveCounters(commandBuffer, querySets.slots[q].samples, firstQuery, queryCount, liveBuffer(b), destinationOffset);
	} else {
		mtlBlitBufferToBuffer(commandBuffer, querySets.slots[q].visibility, (firstQuery as int64) * QUERY_BYTES, liveBuffer(b), destinationOffset, bytes);
	}
	buffers.slots[b].gpuUseFrame = frame;
}

export function beginOcclusionQuery(queryIndex: int32): void {
	if (!pass.active) { stop("beginOcclusionQuery outside a render pass"); }
	if (pass.occlusionSet == 0) { stop("beginOcclusionQuery needs GPURenderPassDescriptor.occlusionQuerySet"); }
	if (pass.occlusionOpen) { stop("beginOcclusionQuery with an occlusion query already open"); }
	const q = querySets.slotIndex(pass.occlusionSet);
	if (queryIndex < 0 || queryIndex >= querySets.slots[q].count) {
		stop(`beginOcclusionQuery index ${queryIndex} is outside the query set of ${querySets.slots[q].count}`);
	}
	if (querySets.slots[q].usedPass[queryIndex] == pass.serial) {
		stop(`beginOcclusionQuery index ${queryIndex} was already used in this pass`);
	}
	querySets.slots[q].usedPass[queryIndex] = pass.serial;
	querySets.slots[q].state[queryIndex] = QueryState.Open;
	mtlSetVisibility(encoder, 1, (queryIndex as int64) * QUERY_BYTES);
	pass.occlusionOpen = true;
	pass.occlusionIndex = queryIndex;
}

export function endOcclusionQuery(): void {
	if (!pass.active || !pass.occlusionOpen) { stop("endOcclusionQuery without an open occlusion query"); }
	const q = querySets.slotIndex(pass.occlusionSet);
	mtlSetVisibility(encoder, 0, (pass.occlusionIndex as int64) * QUERY_BYTES);
	querySets.slots[q].state[pass.occlusionIndex] = QueryState.Written;
	pass.occlusionOpen = false;
}
