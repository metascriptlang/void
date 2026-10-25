import {
	TextureRecord,
	ViewRecord,
	bindGroupRecords,
	bufferRecords,
	layoutRecords,
	pipelineRecords,
	put,
	querySetRecords,
	record,
	samplerRecords,
	shaderRecords,
	slotIndex,
	textureRecords,
	vacate,
	viewRecords,
} from "../pool.ms";
import {
	BindingKind,
	bindingKind,
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
	GPUBlendComponent,
	GPUBuffer,
	GPUBufferDescriptor,
	GPUBufferUsage,
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
	checkedDepthTexelCopy,
	checkedDispatchIndirect,
	checkedTexelBufferLayout,
	checkedTextureToTextureCopy,
	samplerMaxLod,
	checkedTexelWritePitch,
	checkedResolveQuerySet,
	checkedTimestampWrites,
	featureBit,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	firstInstanceRefusal,
	labelText,
	labelOf,
} from "../types.ms";
import {
	cachedCanvas,
	currentFrame,
	checkedCopyRegion,
	entryOf,
	clampedAnisotropy,
	addressesBinding,
	checkedBindGroupSet,
	checkedComputeModule,
	checkedComputePipeline,
	checkedRenderPassPipeline,
	checkedOcclusionRange,
	checkedOcclusionReuse,
	checkedOcclusionSetKind,
	checkedRenderModule,
	checkedSampledView,
	checkedStorageEntry,
	checkedStorageView,
	checkedStripDraw,
	checkedUniformEntry,
	computePassOpen,
	occlusionQueryIndex,
	occlusionSetId,
	passSerial,
	renderPassOpen,
} from "../validate.ms";
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
	mtlComputeSetBufferOffset,
	mtlComputeSetPipeline,
	mtlComputeSetSampler,
	mtlComputeSetTexture,
	mtlConstantsDisagreement,
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
	mtlNewLibraryFromBytes,
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
	mtlTakesBytecode,
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
const STAGE_VERTEX = 0;
const STAGE_FRAGMENT = 1;
const STAGE_COMPUTE = 2;
const STAGE_COUNT = 3;

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
const COMPARE_NEVER = 0;
const COMPARE_ALWAYS = 7;

const NO_SAMPLER = null as unknown as Ptr<MtlSamplerImpl>;
const NO_BUFFER = null as unknown as Ptr<MtlBufferImpl>;
const NO_TEXTURE = null as unknown as Ptr<MtlTextureImpl>;
const NO_COMMAND_BUFFER = null as unknown as Ptr<MtlCommandBufferImpl>;
const NO_ENCODER = null as unknown as Ptr<MtlEncoderImpl>;
const NO_COMPUTE_PIPELINE = null as unknown as Ptr<MtlComputePipelineImpl>;
const NO_SAMPLE_BUFFER = null as unknown as Ptr<MtlSampleBufferImpl>;

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
	natives: Ptr<MtlBufferImpl>[2];
	active: int32;
	inPlace: boolean;
	gpuUseFrame: int64;
}

struct TextureSlot {
	natives: Ptr<MtlTextureImpl>[2];
	active: int32;
	writtenFrame: int64;
	inPlace: boolean;
	gpuUsed: boolean;
}

struct ViewSlot {
	viewType: int32;
	direct: boolean;
	natives: Ptr<MtlTextureImpl>[2];
	swapchainTexture: Ptr<MtlTextureImpl>;
	swapchainResolve: Ptr<MtlTextureImpl>;
}

struct SamplerSlot {
	native: Ptr<MtlSamplerImpl>;
}

struct NativeBinding {
	binding: int32;
	kind: BindingKind;
	vertexStage: boolean;
	fragmentStage: boolean;
	computeStage: boolean;
	writable: boolean;
	nativeSlot: int32;
	size: int32;
}

struct ShaderSlot {
	readsInstanceIndex: boolean;
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
	label: string | null;
	readsInstanceIndex: boolean;
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
}

struct BindGroupSlot {
	group: int32;
	entries: GPUBindGroupEntry[8];
	entryCount: int32;
	dynamicIndex: int32[8];
	dynamicCount: int32;
}

struct PassState {
	width: int32;
	height: int32;
	screen: boolean;
}

export struct BindStats {
	buffers: int64;
	offsets: int64;
	textures: int64;
	samplers: int64;
}

struct ComputeState {
	pipeline: uint32;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[8];
	dirty: boolean;
}

struct QuerySetSlot {
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
let pass: PassState = { width: 0 };
let computeBound: ComputeState = { pipeline: 0 };
let computeEncoder: Ptr<MtlEncoderImpl> = NO_ENCODER;
let bound: BoundState = { pipeline: 0 };
let boundBuffers: Vec<Ptr<MtlBufferImpl>> = [];
let boundOffsets: Vec<int64> = [];
let boundTextures: Vec<Ptr<MtlTextureImpl>> = [];
let boundSamplers: Vec<Ptr<MtlSamplerImpl>> = [];
let stats: BindStats = { buffers: 0 };
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;


export const BACKEND = "metal";

let buffers: Vec<BufferSlot> = [{}];
let textures: Vec<TextureSlot> = [{}];
let views: Vec<ViewSlot> = [{}];
let samplers: Vec<SamplerSlot> = [{}];
let shaders: Vec<ShaderSlot> = [{}];
let pipelines: Vec<PipelineSlot> = [{}];
let bindGroups: Vec<BindGroupSlot> = [{}];
let querySets: Vec<QuerySetSlot> = [{}];

function stop(message: string): never {
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

function stripIndexTypeOf(state: GPUPrimitiveState): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return NO_STRIP_INDEX; }
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

function checkMirroredConstants(): void {
	const values: int32[] = [
		PIXEL_INVALID,
		formatInfo("r8unorm", "x").pixel,
		formatInfo("rg8unorm", "x").pixel,
		formatInfo("rgba8unorm", "x").pixel,
		formatInfo("rgba8unorm-srgb", "x").pixel,
		formatInfo("bgra8unorm", "x").pixel,
		formatInfo("bgra8unorm-srgb", "x").pixel,
		formatInfo("rgba8uint", "x").pixel,
		formatInfo("rgba8sint", "x").pixel,
		formatInfo("r16float", "x").pixel,
		formatInfo("rg16float", "x").pixel,
		formatInfo("rgba16float", "x").pixel,
		formatInfo("rgba16uint", "x").pixel,
		formatInfo("r32float", "x").pixel,
		formatInfo("rg32float", "x").pixel,
		formatInfo("rgba32float", "x").pixel,
		formatInfo("rgba32uint", "x").pixel,
		formatInfo("r32uint", "x").pixel,
		formatInfo("rgb10a2unorm", "x").pixel,
		formatInfo("rg11b10ufloat", "x").pixel,
		formatInfo("depth16unorm", "x").pixel,
		formatInfo("depth32float", "x").pixel,
		formatInfo("depth24plus-stencil8", "x").pixel,
		vertexFormat("uint8x2"),
		vertexFormat("uint8x4"),
		vertexFormat("sint8x2"),
		vertexFormat("sint8x4"),
		vertexFormat("unorm8x2"),
		vertexFormat("unorm8x4"),
		vertexFormat("snorm8x2"),
		vertexFormat("snorm8x4"),
		vertexFormat("uint16x2"),
		vertexFormat("uint16x4"),
		vertexFormat("sint16x2"),
		vertexFormat("sint16x4"),
		vertexFormat("unorm16x2"),
		vertexFormat("unorm16x4"),
		vertexFormat("snorm16x2"),
		vertexFormat("snorm16x4"),
		vertexFormat("float16x2"),
		vertexFormat("float16x4"),
		vertexFormat("float32"),
		vertexFormat("float32x2"),
		vertexFormat("float32x3"),
		vertexFormat("float32x4"),
		vertexFormat("sint32"),
		vertexFormat("sint32x2"),
		vertexFormat("sint32x3"),
		vertexFormat("sint32x4"),
		vertexFormat("uint32"),
		vertexFormat("uint32x2"),
		vertexFormat("uint32x3"),
		vertexFormat("uint32x4"),
		blendFactor("zero", "x"),
		blendFactor("one", "x"),
		blendFactor("src", "x"),
		blendFactor("one-minus-src", "x"),
		blendFactor("src-alpha", "x"),
		blendFactor("one-minus-src-alpha", "x"),
		blendFactor("dst", "x"),
		blendFactor("one-minus-dst", "x"),
		blendFactor("dst-alpha", "x"),
		blendFactor("one-minus-dst-alpha", "x"),
		blendFactor("src-alpha-saturated", "x"),
		blendFactor("constant", "x"),
		blendFactor("one-minus-constant", "x"),
		blendOperation("add", "x"),
		blendOperation("subtract", "x"),
		blendOperation("reverse-subtract", "x"),
		blendOperation("min", "x"),
		blendOperation("max", "x"),
		stencilOperation("keep", "x"),
		stencilOperation("zero", "x"),
		stencilOperation("replace", "x"),
		stencilOperation("increment-clamp", "x"),
		stencilOperation("decrement-clamp", "x"),
		stencilOperation("invert", "x"),
		stencilOperation("increment-wrap", "x"),
		stencilOperation("decrement-wrap", "x"),
		COMPARE_NEVER,
		compareFunction("never", "x"),
		compareFunction("less", "x"),
		compareFunction("equal", "x"),
		compareFunction("less-equal", "x"),
		compareFunction("greater", "x"),
		compareFunction("not-equal", "x"),
		compareFunction("greater-equal", "x"),
		compareFunction("always", "x"),
		cullMode("none"),
		cullMode("front"),
		cullMode("back"),
		winding("cw"),
		winding("ccw"),
		WRITE_RED,
		WRITE_GREEN,
		WRITE_BLUE,
		WRITE_ALPHA,
		filterMode("nearest", "x"),
		filterMode("linear", "x"),
		mipFilterMode("nearest", "x"),
		mipFilterMode("linear", "x"),
		addressMode("clamp-to-edge", "x"),
		addressMode("repeat", "x"),
		addressMode("mirror-repeat", "x"),
		primitiveType("point-list"),
		primitiveType("line-list"),
		primitiveType("line-strip"),
		primitiveType("triangle-list"),
		primitiveType("triangle-strip"),
		indexType("uint16"),
		indexType("uint32"),
		TYPE_2D,
		TYPE_2D_ARRAY,
		TYPE_2D_MULTISAMPLE,
		TYPE_CUBE,
		TYPE_CUBE_ARRAY,
		TYPE_3D,
		LOAD_LOAD,
		LOAD_CLEAR,
		STORE_DONT_CARE,
		STORE_STORE,
		STORE_RESOLVE,
		STORE_STORE_AND_RESOLVE,
	];
	const disagreement: string = mtlConstantsDisagreement(values[0], values.length as int32);
	if (disagreement != "") { stop(`a constant of backend.ms disagrees with metal.m, ${disagreement}`); }
}

export function bindStats(): BindStats { return stats; }

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device === null) { stop("requestDevice needs the native MTLDevice"); }
	checkMirroredConstants();
	device = mtlDeviceFrom(environment.device);
	queue = mtlNewCommandQueue(device);
	sharedStorage = mtlUsesSharedStorage(device) == 1;
	mtlFrameSemaphoreCreate(FRAMES_IN_FLIGHT);
	commandBuffer = NO_COMMAND_BUFFER;
	encoder = NO_ENCODER;
	pass = { width: 0 };
	computeBound = { pipeline: 0 };
	computeEncoder = NO_ENCODER;
	bound = { pipeline: 0 };
	const sampleCount = cachedCanvas().sampleCount;
	if (mtlSupportsSampleCount(device, sampleCount) == 0) {
		stopOnMember("NativeEnvironment.sampleCount", `${sampleCount}`);
	}
	return { id: 1, queue: { id: 1 } };
}

export function adoptSwapchain(color: uint32, depth: uint32): void {
	swapchainColor = color;
	swapchainDepth = depth;
	adoptSwapchainTexture(color, "NativeEnvironment.colorFormat");
	if (depth != 0) { adoptSwapchainTexture(depth, "NativeEnvironment.depthFormat"); }
}

function adoptSwapchainTexture(id: uint32, member: string): void {
	formatInfo(textureRecords.record(id).format, member);
	put(textures, id, textures[0]);
	put(views, textureRecords.record(id).swapchainView, views[0]);
}

export function formatRenderable(format: GPUTextureFormat): boolean {
	formatInfo(format, "formatRenderable format");
	return true;
}

export function shutdown(): void {
	if (commandBuffer != null) {
		mtlCommit(commandBuffer);
		commandBuffer = NO_COMMAND_BUFFER;
	}
	mtlFrameSemaphoreWaitAll();
	mtlForgetCommitted();
	mtlReleaseQueue(queue);
	mtlReleaseDevice(device);
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "metal", originTopLeft: true, depthZeroToOne: true };
}

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	return mtlTextureNative(liveTexture(textureRecords.slotIndex(texture.id)));
}

export function nativeQueue(): Ptr<void> { return mtlQueueNative(queue); }

// A CPU write waits for the oldest frame in flight as a pass does (sokol _sg_mtl_begin_pass):
// it lands in a copy the frame before last may still read.
function beginFrame(): void {
	if (commandBuffer != null) { return; }
	commandBuffer = mtlBeginCommandBuffer(queue);
}

export function createBuffer(id: uint32, descriptor: GPUBufferDescriptor): void {
	const usage = descriptor.usage;
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
	const mapped = mapWrite || has(usage, GPUBufferUsage.MAP_READ as int32);
	const native = mapped
		? mtlNewMappableBuffer(device, descriptor.size, mapWrite ? 1 : 0)
		: mtlNewBuffer(device, descriptor.size, sharedStorage ? 1 : 0);
	if (native == null) { stop(`newBufferWithLength failed for ${labelOf(descriptor.label)}`); }
	mtlSetLabel(native as Ptr<void>, labelText(descriptor.label));
	const slot: BufferSlot = {
		natives: [native, NO_BUFFER],
		active: 0,
		inPlace: mapped || has(usage, GPUBufferUsage.STORAGE as int32) || has(usage, GPUBufferUsage.QUERY_RESOLVE as int32),
		gpuUseFrame: -1,
	};
	put(buffers, id, slot);
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = bufferRecords.slotIndex(buffer.id);
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (buffers[index].natives[s] != null) { mtlReleaseBuffer(buffers[index].natives[s]); }
	}
	vacate(buffers, buffer.id);
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferRecords.slotIndex(buffer.id);
	if (buffers[index].inPlace) {
		writeBufferInPlace(index, offset, data, bytes);
		return;
	}
	beginFrame();
	const written = bufferRecords.slots[index].writtenFrame;
	if (written >= 0 && written != currentFrame()) { nextBufferCopy(index); }
	const native = buffers[index].natives[buffers[index].active];
	mtlWriteBuffer(native, offset, data[0], bytes, sharedStorage ? 0 : 1);
}

// A buffer a GPU copy writes, or a mappable one, keeps one live copy, so a CPU write joins the
// frame's command buffer behind the earlier copies instead of landing before them.
function writeBufferInPlace<T>(index: int32, offset: int64, data: Readonly<Span<T>>, bytes: int64): void {
	if (renderPassOpen() || computePassOpen()) { stop(`writeBuffer on GPUBuffer ${bufferRecords.slots[index].id} inside a pass: its copies are GPU commands`); }
	beginFrame();
	const staging = mtlNewStagingBuffer(device, data[0], 0, bytes);
	if (staging == null) { stop(`newBufferWithBytes failed for the write to GPUBuffer ${bufferRecords.slots[index].id}`); }
	mtlBlitBufferToBuffer(commandBuffer, staging, 0, buffers[index].natives[buffers[index].active], offset, bytes);
	mtlReleaseBuffer(staging);
	buffers[index].gpuUseFrame = currentFrame();
}

function nextBufferCopy(index: int32): void {
	const next = 1 - buffers[index].active;
	if (buffers[index].natives[next] == null) {
		buffers[index].natives[next] = mtlNewBuffer(device, bufferRecords.slots[index].size, sharedStorage ? 1 : 0);
		if (buffers[index].natives[next] == null) { stop(`newBufferWithLength failed for GPUBuffer ${bufferRecords.slots[index].id}`); }
	}
	buffers[index].active = next;
	bound.vertexDirty = true;
	bound.uniformsDirty = true;
}

export function createTexture(texture: TextureRecord, descriptor: GPUTextureDescriptor): void {
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const sampleCount = texture.sampleCount;
	if (sampleCount != 1 && mtlSupportsSampleCount(device, sampleCount) == 0) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const attachment = has(texture.usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const storage = has(texture.usage, GPUTextureUsage.STORAGE_BINDING as int32);
	if (storage && (sampleCount != 1 || info.depth)) { stop("GPUTextureUsage.STORAGE_BINDING takes a single-sample colour texture"); }
	const native = newTexture(texture.width, texture.height, texture.layers, texture.mipLevels, texture.volume, info.pixel, sampleCount, attachment, storage);
	if (native == null) { stop(`newTextureWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	mtlSetLabel(native as Ptr<void>, labelText(descriptor.label));
	put(textures, texture.id, { natives: [native, NO_TEXTURE], active: 0, writtenFrame: -1, inPlace: false, gpuUsed: false });
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
	const index = textureRecords.slotIndex(texture.id);
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (textures[index].natives[s] != null) { mtlReleaseTexture(textures[index].natives[s]); }
	}
	vacate(textures, texture.id);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textureRecords.slotIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	const rowPitch = textureCopyPitch(index, bytes, destination, layout, size);
	const slot = textureRecords.slots[index];
	const wholeOnly = slot.mipLevels == 1 && slot.layers == 1 && !slot.volume;
	const whole = wholeOnly && destination.origin.x == 0 && destination.origin.y == 0 && size.width == slot.width && size.height == slot.height;
	if (!whole || textures[index].inPlace || has(slot.usage, (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.STORAGE_BINDING as int32)) || textures[index].writtenFrame == currentFrame()) {
		writeTextureByBlit(index, data, destination, layout, rowPitch, size);
		return;
	}
	beginFrame();
	if (textures[index].writtenFrame >= 0) { nextTextureCopy(index); }
	textures[index].writtenFrame = currentFrame();
	const native = textures[index].natives[textures[index].active];
	mtlWriteTexture(native, data[0], layout.offset, rowPitch, 0, slot.width, slot.height, 1, 0, 0, 0, 0, 0);
}

// A write that is not a whole single-subresource texture lands through a staging buffer and a blit
// in the frame's command buffer, so it follows the frame's earlier reads of the texture in queue
// order; a CPU `replaceRegion` would not. Inside a pass no blit can be encoded, so only a texture
// no command has used yet is written there, by the CPU.
function writeTextureByBlit<T>(
	index: int32,
	data: Readonly<Span<T>>,
	destination: GPUTexelCopyTextureInfo,
	layout: GPUTexelCopyBufferLayout,
	rowPitch: int32,
	size: GPUExtent3D,
): void {
	const imageBytes = (rowPitch as int64) * (layout.rowsPerImage as int64);
	if (renderPassOpen() || computePassOpen()) {
		const private = has(textureRecords.slots[index].usage, (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.STORAGE_BINDING as int32));
		if (textures[index].gpuUsed || private) {
			stop(`writeTexture of ${size.width}x${size.height} on GPUTexture ${textureRecords.slots[index].id} inside a pass: a texture GPU work already uses, or one only the GPU holds, is written by a GPU copy`);
		}
		writeUnusedTexture(index, data, destination, layout, rowPitch, imageBytes, size);
		return;
	}
	const bytesPerPixel = formatInfo(textureRecords.slots[index].format, "texture format").bytesPerPixel;
	const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (rowPitch as int64) * ((size.height - 1) as int64) + ((size.width * bytesPerPixel) as int64);
	beginFrame();
	const staging = mtlNewStagingBuffer(device, data[0], layout.offset, span);
	if (staging == null) { stop(`newBufferWithBytes failed for the write to GPUTexture ${textureRecords.slots[index].id}`); }
	const native = textures[index].natives[textures[index].active];
	if (textureRecords.slots[index].volume) {
		mtlBlitBufferToTexture(commandBuffer, staging, 0, rowPitch, imageBytes as int32, size.width, size.height, size.depthOrArrayLayers, native, 0, destination.mipLevel, destination.origin.x, destination.origin.y, destination.origin.z);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlBlitBufferToTexture(commandBuffer, staging, imageBytes * (i as int64), rowPitch, 0, size.width, size.height, 1, native, destination.origin.z + i, destination.mipLevel, destination.origin.x, destination.origin.y, 0);
		}
	}
	mtlReleaseBuffer(staging);
	textures[index].inPlace = true;
	textures[index].gpuUsed = true;
}

function writeUnusedTexture<T>(
	index: int32,
	data: Readonly<Span<T>>,
	destination: GPUTexelCopyTextureInfo,
	layout: GPUTexelCopyBufferLayout,
	rowPitch: int32,
	imageBytes: int64,
	size: GPUExtent3D,
): void {
	const native = textures[index].natives[textures[index].active];
	if (textureRecords.slots[index].volume) {
		mtlWriteTexture(native, data[0], layout.offset, rowPitch, imageBytes as int32, size.width, size.height, size.depthOrArrayLayers, 0, destination.mipLevel, destination.origin.x, destination.origin.y, destination.origin.z);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlWriteTexture(native, data[0], layout.offset + imageBytes * (i as int64), rowPitch, 0, size.width, size.height, 1, destination.origin.z + i, destination.mipLevel, destination.origin.x, destination.origin.y, 0);
		}
	}
	textures[index].inPlace = true;
}

function nextTextureCopy(index: int32): void {
	const next = 1 - textures[index].active;
	if (textures[index].natives[next] == null) {
		const pixel = formatInfo(textureRecords.slots[index].format, "texture format").pixel;
		textures[index].natives[next] = newTexture(textureRecords.slots[index].width, textureRecords.slots[index].height, 1, 1, false, pixel, 1, false, false);
		if (textures[index].natives[next] == null) { stop(`newTextureWithDescriptor failed for GPUTexture ${textureRecords.slots[index].id}`); }
	}
	textures[index].active = next;
	bound.resourcesDirty = true;
}

function textureCopyPitch(
	index: int32,
	bytes: int64,
	destination: GPUTexelCopyTextureInfo,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): int32 {
	const width = textureRecords.slots[index].width;
	const height = textureRecords.slots[index].height;
	if (!has(textureRecords.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textureRecords.slots[index].id}, created without COPY_DST`);
	}
	if (textureRecords.slots[index].sampleCount != 1) { stop(`writeTexture on GPUTexture ${textureRecords.slots[index].id}, which is multisampled`); }
	const volume = textureRecords.slots[index].volume;
	const mip = destination.mipLevel;
	const mips = textureRecords.slots[index].mipLevels;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textureRecords.slots[index].layers >> mip) : textureRecords.slots[index].layers;
	return checkedTexelWritePitch(
		width,
		height,
		mips,
		depth,
		formatInfo(textureRecords.slots[index].format, "texture format").bytesPerPixel,
		bytes,
		destination,
		layout,
		size,
	);
}

function viewTypeOf(name: string, t: int32): int32 {
	if (name == "2d") { return textureRecords.slots[t].sampleCount > 1 ? TYPE_2D_MULTISAMPLE : TYPE_2D; }
	if (name == "2d-array") { return TYPE_2D_ARRAY; }
	if (name == "cube") { return TYPE_CUBE; }
	if (name == "cube-array") { return TYPE_CUBE_ARRAY; }
	if (name == "3d") { return TYPE_3D; }
	return stopOnMember("GPUTextureViewDescriptor.dimension", name);
}

export function createView(view: ViewRecord, descriptor: GPUTextureViewDescriptor): void {
	const t = textureRecords.slotIndex(view.texture);
	const texture = textureRecords.slots[t];
	const viewType = viewTypeOf(view.dimension, t);
	const direct = viewType == naturalType(texture.volume, texture.layers, texture.sampleCount)
		&& view.baseMip == 0 && view.mipCount == texture.mipLevels && view.baseLayer == 0 && (texture.volume || view.layerCount == texture.layers);
	put(views, view.id, { viewType: viewType, direct: direct, natives: [NO_TEXTURE, NO_TEXTURE], swapchainTexture: NO_TEXTURE, swapchainResolve: NO_TEXTURE });
}

export function destroyView(view: GPUTextureView): void {
	const index = viewRecords.slotIndex(view.id);
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (views[index].natives[s] != null) { mtlReleaseTexture(views[index].natives[s]); }
	}
	vacate(views, view.id);
}

function attachmentNative(v: int32): Ptr<MtlTextureImpl> {
	if (viewRecords.slots[v].swapchain) { return views[v].swapchainTexture; }
	return liveTexture(textureRecords.slotIndex(viewRecords.slots[v].texture));
}

function viewNative(v: int32): Ptr<MtlTextureImpl> {
	const base = attachmentNative(v);
	if (viewRecords.slots[v].swapchain || views[v].direct) { return base; }
	const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
	const active = textures[t].active;
	if (views[v].natives[active] == null) {
		const layerCount = views[v].viewType == TYPE_3D ? 1 : viewRecords.slots[v].layerCount;
		views[v].natives[active] = mtlNewTextureView(
			base,
			formatInfo(textureRecords.slots[t].format, "texture format").pixel,
			views[v].viewType,
			viewRecords.slots[v].baseMip,
			viewRecords.slots[v].mipCount,
			viewRecords.slots[v].baseLayer,
			layerCount,
		);
		if (views[v].natives[active] == null) { stop(`newTextureViewWithPixelFormat failed for GPUTexture ${textureRecords.slots[t].id}`); }
	}
	return views[v].natives[active];
}

export function acquireSwapchain(swapchain: NativeSwapchain): void {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	const v = viewRecords.slotIndex(textureRecords.slots[textureRecords.slotIndex(swapchainColor)].swapchainView);
	views[v].swapchainTexture = mtlTextureFrom(swapchain.renderView);
	views[v].swapchainResolve = swapchain.resolveView === null ? NO_TEXTURE : mtlTextureFrom(swapchain.resolveView);
	textures[textureRecords.slotIndex(swapchainColor)].natives[0] = swapchain.sampleCount > 1 ? views[v].swapchainResolve : views[v].swapchainTexture;
	if (swapchainDepth != 0) {
		if (swapchain.depthStencilView === null) { stop("the canvas has a depth format and the native swapchain no depth view"); }
		const d = viewRecords.slotIndex(textureRecords.slots[textureRecords.slotIndex(swapchainDepth)].swapchainView);
		views[d].swapchainTexture = mtlTextureFrom(swapchain.depthStencilView);
	}
}

export function createSampler(id: uint32, descriptor: GPUSamplerDescriptor): void {
	const minFilter = filterMode(descriptor.minFilter, "GPUSamplerDescriptor.minFilter");
	const magFilter = filterMode(descriptor.magFilter, "GPUSamplerDescriptor.magFilter");
	const mipFilter = mipFilterMode(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter");
	const maxAnisotropy = clampedAnisotropy(descriptor.maxAnisotropy);
	const maxLod = samplerMaxLod(descriptor.lodMaxClamp);
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
	put(samplers, id, { native: native });
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplerRecords.slotIndex(sampler.id);
	mtlReleaseSampler(samplers[index].native);
	vacate(samplers, sampler.id);
}

function compileLibrary(code: string, bytecode: Readonly<Vec<uint8>>, stage: string, label: string | null): Ptr<MtlLibraryImpl> {
	if (bytecode.length > 0 && mtlTakesBytecode() != 0) {
		const loaded = mtlNewLibraryFromBytes(device, bytecode[0], bytecode.length as int64);
		if (loaded == null) {
			const log: string = mtlErrorLog();
			stop(`the device rejected GPUShaderModuleDescriptor.${stage}Bytecode of ${labelOf(label)}:\n${log}`);
		}
		return loaded;
	}
	if (code == "") {
		stop(`the ${stage} of ${labelOf(label)} has no MSL and no bytecode this device takes`);
	}
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

export function createShaderModule(id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	let slot: ShaderSlot = {};
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const visibility = descriptor.bindings[i].visibility;
		const native: NativeBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName, "metal"),
			vertexStage: (visibility & (GPUShaderStage.VERTEX as int32)) != 0,
			fragmentStage: (visibility & (GPUShaderStage.FRAGMENT as int32)) != 0,
			computeStage: compute,
			writable: bindingWritable(descriptor.bindings[i]),
			nativeSlot: descriptor.bindings[i].nativeSlot,
			size: descriptor.bindings[i].size,
		};
		checkBinding(native);
		if (native.kind == BindingKind.Uniform) {
			slot.uniforms[slot.uniformCount] = native;
			slot.uniformCount += 1;
		} else {
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
		slot.workgroup = size;
		slot.computeEntry = descriptor.computeEntryPoint == "" ? "_main" : descriptor.computeEntryPoint;
		slot.computeLibrary = compileLibrary(descriptor.computeCode, descriptor.computeBytecode, "compute", descriptor.label);
		slot.compute = entryFunction(slot.computeLibrary, slot.computeEntry, "compute", descriptor.label);
	} else {
		slot.vertexLibrary = compileLibrary(descriptor.vertexCode, descriptor.vertexBytecode, "vertex", descriptor.label);
		slot.fragmentLibrary = compileLibrary(descriptor.fragmentCode, descriptor.fragmentBytecode, "fragment", descriptor.label);
		slot.vertex = entryFunction(slot.vertexLibrary, descriptor.vertexEntryPoint, "vertex", descriptor.label);
		slot.fragment = entryFunction(slot.fragmentLibrary, descriptor.fragmentEntryPoint, "fragment", descriptor.label);
	}
	slot.readsInstanceIndex = descriptor.readsInstanceIndex;
	put(shaders, id, slot);
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

function checkBinding(native: NativeBinding): void {
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
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaderRecords.slotIndex(module.id);
	if (shaders[index].compute != null) {
		mtlReleaseFunction(shaders[index].compute);
		mtlReleaseLibrary(shaders[index].computeLibrary);
	} else {
		mtlReleaseFunction(shaders[index].vertex);
		mtlReleaseFunction(shaders[index].fragment);
		mtlReleaseLibrary(shaders[index].vertexLibrary);
		mtlReleaseLibrary(shaders[index].fragmentLibrary);
	}
	vacate(shaders, module.id);
}

function checkAttribute(shader: int32, location: int32): void {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		if (shaders[shader].attributes[i].location == location) { return; }
	}
	stopOnMember("vertex attribute shaderLocation (absent from the shader reflection)", `${location}`);
}

export function createRenderPipeline(id: uint32, descriptor: GPURenderPipelineDescriptor): void {
	const s = shaderRecords.slotIndex(descriptor.vertex.module.id);
	checkedRenderModule(shaders[s].compute != null);
	let slot: PipelineSlot = { shader: descriptor.vertex.module.id, label: descriptor.label, readsInstanceIndex: shaders[s].readsInstanceIndex };
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
	const sampleCount = descriptor.multisample.count;
	slot.state = mtlNewPipeline(device, shaders[s].vertex, shaders[s].fragment, depthPixel, stencilPixel, sampleCount);
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
		readMask,
		writeMask,
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
	slot.stripIndexType = stripIndexTypeOf(descriptor.primitive);
	slot.cullMode = cullMode(descriptor.primitive.cullMode);
	slot.winding = winding(descriptor.primitive.frontFace);
	put(pipelines, id, slot);
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
	const index = pipelineRecords.slotIndex(pipeline.id);
	if (pipelines[index].compute) {
		mtlReleaseComputePipeline(pipelines[index].computeState);
	} else {
		mtlReleasePipeline(pipelines[index].state);
		mtlReleaseDepthState(pipelines[index].depth);
	}
	vacate(pipelines, pipeline.id);
}

export function createBindGroup(id: uint32, descriptor: GPUBindGroupDescriptor): void {
	const l = layoutRecords.slotIndex(descriptor.layout.id);
	const group = layoutRecords.slots[l].group;
	const shader = shaderRecords.slotIndex(pipelines[pipelineRecords.slotIndex(layoutRecords.slots[l].pipeline)].shader);
	let slot: BindGroupSlot = { group: group };
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) { continue; }
		checkEntry(shader, group, entry);
		slot.entries[slot.entryCount] = entry;
		slot.entryCount += 1;
	}
	for (let i = 0; i < slot.entryCount; i++) {
		if (slot.entries[i].buffer.id == 0 || uniformOf(shader, group, slot.entries[i].binding) < 0) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			if (slot.entries[j].buffer.id != 0 && uniformOf(shader, group, slot.entries[j].binding) >= 0 && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	put(bindGroups, id, slot);
}

function uniformOf(shader: int32, group: int32, binding: int32): int32 {
	for (let u = 0; u < shaders[shader].uniformCount; u++) {
		if (addressesBinding(group, binding, shaders[shader].uniforms[u].binding, BindingKind.Uniform)) { return u; }
	}
	return -1;
}

function resourceOf(shader: int32, group: int32, binding: int32): int32 {
	for (let r = 0; r < shaders[shader].resourceCount; r++) {
		const resource = shaders[shader].resources[r];
		if (addressesBinding(group, binding, resource.binding, resource.kind)) { return r; }
	}
	return -1;
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = bufferRecords.slotIndex(entry.buffer.id);
		const u = uniformOf(shader, group, entry.binding);
		if (u >= 0) {
			const binding = shaders[shader].uniforms[u];
			checkedUniformEntry(
				entry,
				has(bufferRecords.slots[b].usage, GPUBufferUsage.UNIFORM as int32),
				bufferRecords.slots[b].size,
				binding.size,
				UNIFORM_OFFSET_ALIGNMENT as int64,
			);
			return;
		}
		const r = resourceOf(shader, group, entry.binding);
		if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.StorageBuffer) {
			checkedStorageEntry(
				entry,
				has(bufferRecords.slots[b].usage, GPUBufferUsage.STORAGE as int32),
				bufferRecords.slots[b].size,
				STORAGE_OFFSET_ALIGNMENT as int64,
				mtlMaxBufferLength(device),
			);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	const r = resourceOf(shader, group, entry.binding);
	if (entry.textureView.id != 0) {
		const v = viewRecords.slotIndex(entry.textureView.id);
		const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
		if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.Texture) {
			checkedSampledView(entry.binding, has(textureRecords.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32));
			return;
		}
		if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.StorageTexture) {
			checkedStorageView(entry.binding, has(textureRecords.slots[t].usage, GPUTextureUsage.STORAGE_BINDING as int32), viewRecords.slots[v].mipCount);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplerRecords.slotIndex(entry.sampler.id);
	if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.Sampler) { return; }
	stop(`bind group ${group} entry ${entry.binding} (sampler) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroupRecords.slotIndex(bindGroup.id);
	vacate(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(submitted: GPUCommandBuffer): void {
	if (commandBuffer != null) {
		mtlCommit(commandBuffer);
		commandBuffer = NO_COMMAND_BUFFER;
	}
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

export function beginRenderPass(passEncoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor, extent: GPUExtent3D): GPURenderPassEncoder {
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	if (descriptor.occlusionQuerySet.id != 0) {
		checkedOcclusionSetKind(querySets[querySetRecords.slotIndex(descriptor.occlusionQuerySet.id)].timestamp);
	}
	pass = { width: extent.width, height: extent.height };
	beginFrame();
	mtlPassReset();
	clearBinds();
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = viewRecords.slotIndex(viewId);
		const slice = descriptor.colorAttachments[i].depthSlice;
		const resolveId = descriptor.colorAttachments[i].resolveTarget.id;
		const resolve = resolveTexture(v, resolveId);
		const r = resolveId == 0 ? v : viewRecords.slotIndex(resolveId);
		if (viewRecords.slots[v].swapchain) { pass.screen = true; }
		const color = descriptor.colorAttachments[i].clearValue;
		mtlPassColor(
			i,
			attachmentNative(v),
			viewRecords.slots[v].baseMip,
			viewRecords.slots[v].baseLayer,
			slice,
			resolve,
			viewRecords.slots[r].baseMip,
			viewRecords.slots[r].baseLayer,
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
		const v = viewRecords.slotIndex(depthView);
		const info = formatInfo(textureRecords.slots[textureRecords.slotIndex(viewRecords.slots[v].texture)].format, "depth format");
		mtlPassDepth(
			attachmentNative(v),
			viewRecords.slots[v].baseMip,
			viewRecords.slots[v].baseLayer,
			loadAction(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp"),
			storeAction(descriptor.depthStencilAttachment.depthStoreOp, false, "depthStencilAttachment.depthStoreOp"),
			descriptor.depthStencilAttachment.depthClearValue,
			info.stencil ? 1 : 0,
		);
	}
	if (descriptor.timestampWrites.querySet.id != 0) {
		const q = querySetRecords.slotIndex(descriptor.timestampWrites.querySet.id);
		mtlPassSamples(querySets[q].samples, descriptor.timestampWrites.beginningOfPassWriteIndex, descriptor.timestampWrites.endOfPassWriteIndex);
		markTimestampsWritten(q, descriptor.timestampWrites);
	}
	if (descriptor.occlusionQuerySet.id != 0) { mtlPassVisibility(querySets[querySetRecords.slotIndex(descriptor.occlusionQuerySet.id)].visibility); }
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

function resolveTexture(colorView: int32, resolveId: uint32): Ptr<MtlTextureImpl> {
	if (viewRecords.slots[colorView].swapchain && resolveId == 0) { return views[colorView].swapchainResolve; }
	if (resolveId == 0) { return NO_TEXTURE; }
	return attachmentNative(viewRecords.slotIndex(resolveId));
}

export function endPass(): void {
	mtlEndPass(encoder);
	encoder = NO_ENCODER;
	if (pass.screen) { mtlPresentDrawable(commandBuffer); }
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	checkedRenderPassPipeline(pipeline.id, pipelines[pipelineRecords.slotIndex(pipeline.id)].compute);
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
	bound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroupRecords.slotIndex(bindGroup.id);
	checkedBindGroupSet(index, bindGroups[g].group, bindGroups[g].dynamicCount, dynamicOffsets, UNIFORM_OFFSET_ALIGNMENT);
	if (index == GPU_UNIFORM_GROUP) {
		for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
			bound.dynamicOffsets[i] = dynamicOffsets[i];
		}
		bound.uniformsDirty = true;
	} else {
		bound.resourcesDirty = true;
	}
}

// Metal refuses a scissor rect outside the attachment; sokol clips it the same way (_sg_clipi).
export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	const left = x < 0 ? 0 : (x > pass.width ? pass.width : x);
	const top = y < 0 ? 0 : (y > pass.height ? pass.height : y);
	let right = x + width;
	let bottom = y + height;
	right = right > pass.width ? pass.width : (right < left ? left : right);
	bottom = bottom > pass.height ? pass.height : (bottom < top ? top : bottom);
	mtlSetScissorRect(encoder, left, top, right - left, bottom - top);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	mtlSetViewport(encoder, x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	mtlSetBlendColor(encoder, color.r, color.g, color.b, color.a);
}

export function setStencilReference(reference: uint32): void {
	mtlSetStencilReference(encoder, reference);
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush();
	checkFirstInstance("draw", firstInstance);
	mtlDraw(encoder, pipelines[pipelineRecords.slotIndex(bound.pipeline)].primitive, vertexCount, instanceCount, firstVertex, firstInstance);
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
	checkFirstInstance("drawIndexed", firstInstance);
	const p = pipelineRecords.slotIndex(bound.pipeline);
	const primitive = pipelines[p].primitive;
	checkedStripDraw(primitive == PRIMITIVE_LINE_STRIP || primitive == PRIMITIVE_TRIANGLE_STRIP, pipelines[p].stripIndexType == bound.indexType);
	const b = bufferRecords.slotIndex(bound.indexBuffer);
	mtlDrawIndexed(
		encoder,
		primitive,
		buffers[b].natives[buffers[b].active],
		bound.indexType,
		bound.indexOffset + (firstIndex as int64) * bound.indexBytes,
		indexCount,
		instanceCount,
		baseVertex,
		firstInstance,
	);
}

function checkFirstInstance(call: string, firstInstance: int32): void {
	if (firstInstance == 0) { return; }
	const p = pipelineRecords.slotIndex(bound.pipeline);
	if (pipelines[p].readsInstanceIndex) { stop(firstInstanceRefusal(call, labelOf(pipelines[p].label), firstInstance)); }
}

function flush(): void {
	if (bound.appliedPipeline != bound.pipeline) { applyPipeline(); }
	if (bound.vertexDirty) { applyVertexBuffers(); }
	if (bound.resourcesDirty) { applyResources(); }
	if (bound.uniformsDirty) { applyUniforms(); }
}

function applyPipeline(): void {
	const p = pipelineRecords.slotIndex(bound.pipeline);
	if (!shaderRecords.alive(pipelines[p].shader)) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	mtlSetPipeline(encoder, pipelines[p].state, pipelines[p].depth, pipelines[p].cullMode, pipelines[p].winding, pipelines[p].depthBias, pipelines[p].depthBiasSlope, pipelines[p].depthBiasClamp);
	bound.appliedPipeline = bound.pipeline;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
}

function clearBinds(): void {
	boundBuffers = [];
	boundOffsets = [];
	boundTextures = [];
	boundSamplers = [];
	for (let i = 0; i < STAGE_COUNT * MAX_STAGE_BUFFERS; i++) {
		boundBuffers.push(NO_BUFFER);
		boundOffsets.push(0);
	}
	for (let i = 0; i < STAGE_COUNT * MAX_STAGE_TEXTURES; i++) { boundTextures.push(NO_TEXTURE); }
	for (let i = 0; i < STAGE_COUNT * MAX_STAGE_SAMPLERS; i++) { boundSamplers.push(NO_SAMPLER); }
}

function bindBuffer(stage: int32, native: Ptr<MtlBufferImpl>, offset: int64, slot: int32): void {
	const i = stage * MAX_STAGE_BUFFERS + slot;
	if (boundBuffers[i] == native) {
		if (boundOffsets[i] == offset) { return; }
		if (stage == STAGE_VERTEX) {
			mtlSetVertexBufferOffset(encoder, offset, slot);
		} else if (stage == STAGE_FRAGMENT) {
			mtlSetFragmentBufferOffset(encoder, offset, slot);
		} else {
			mtlComputeSetBufferOffset(computeEncoder, offset, slot);
		}
		boundOffsets[i] = offset;
		stats.offsets += 1;
		return;
	}
	if (stage == STAGE_VERTEX) {
		mtlSetVertexBuffer(encoder, native, offset, slot);
	} else if (stage == STAGE_FRAGMENT) {
		mtlSetFragmentBuffer(encoder, native, offset, slot);
	} else {
		mtlComputeSetBuffer(computeEncoder, native, offset, slot);
	}
	boundBuffers[i] = native;
	boundOffsets[i] = offset;
	stats.buffers += 1;
}

function bindTexture(stage: int32, texture: Ptr<MtlTextureImpl>, slot: int32): void {
	const i = stage * MAX_STAGE_TEXTURES + slot;
	if (boundTextures[i] == texture) { return; }
	if (stage == STAGE_VERTEX) {
		mtlSetVertexTexture(encoder, texture, slot);
	} else if (stage == STAGE_FRAGMENT) {
		mtlSetFragmentTexture(encoder, texture, slot);
	} else {
		mtlComputeSetTexture(computeEncoder, texture, slot);
	}
	boundTextures[i] = texture;
	stats.textures += 1;
}

function bindSampler(stage: int32, sampler: Ptr<MtlSamplerImpl>, slot: int32): void {
	const i = stage * MAX_STAGE_SAMPLERS + slot;
	if (boundSamplers[i] == sampler) { return; }
	if (stage == STAGE_VERTEX) {
		mtlSetVertexSampler(encoder, sampler, slot);
	} else if (stage == STAGE_FRAGMENT) {
		mtlSetFragmentSampler(encoder, sampler, slot);
	} else {
		mtlComputeSetSampler(computeEncoder, sampler, slot);
	}
	boundSamplers[i] = sampler;
	stats.samplers += 1;
}

function applyVertexBuffers(): void {
	const p = pipelineRecords.slotIndex(bound.pipeline);
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines[p].strides[slot] == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		const b = bufferRecords.slotIndex(bound.vertexBuffers[slot]);
		bindBuffer(STAGE_VERTEX, buffers[b].natives[buffers[b].active], bound.vertexOffsets[slot], VERTEX_BUFFER_BASE + slot);
	}
	bound.vertexDirty = false;
}


function applyResources(): void {
	const s = shaderRecords.slotIndex(pipelines[pipelineRecords.slotIndex(bound.pipeline)].shader);
	bound.resourcesDirty = false;
	if (shaders[s].resourceCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	const g = bindGroupRecords.slotIndex(bound.bindGroups[GPU_RESOURCE_GROUP]);
	for (let r = 0; r < shaders[s].resourceCount; r++) {
		const binding: NativeBinding = shaders[s].resources[r];
		const e = entryOf(bindGroups[g], binding.binding);
		if (binding.kind == BindingKind.Texture) {
			const texture = viewNative(viewRecords.slotIndex(bindGroups[g].entries[e].textureView.id));
			if (binding.vertexStage) { bindTexture(STAGE_VERTEX, texture, binding.nativeSlot); }
			if (binding.fragmentStage) { bindTexture(STAGE_FRAGMENT, texture, binding.nativeSlot); }
		} else if (binding.kind == BindingKind.StorageBuffer) {
			const native = liveBuffer(bufferRecords.slotIndex(bindGroups[g].entries[e].buffer.id));
			const offset = bindGroups[g].entries[e].offset;
			if (binding.vertexStage) { bindBuffer(STAGE_VERTEX, native, offset, binding.nativeSlot); }
			if (binding.fragmentStage) { bindBuffer(STAGE_FRAGMENT, native, offset, binding.nativeSlot); }
		} else {
			const sampler = samplers[samplerRecords.slotIndex(bindGroups[g].entries[e].sampler.id)].native;
			if (binding.vertexStage) { bindSampler(STAGE_VERTEX, sampler, binding.nativeSlot); }
			if (binding.fragmentStage) { bindSampler(STAGE_FRAGMENT, sampler, binding.nativeSlot); }
		}
	}
}

function applyUniforms(): void {
	const s = shaderRecords.slotIndex(pipelines[pipelineRecords.slotIndex(bound.pipeline)].shader);
	bound.uniformsDirty = false;
	if (shaders[s].uniformCount == 0) { return; }
	if (bound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the pipeline reads bind group 0, which is not set"); }
	const g = bindGroupRecords.slotIndex(bound.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders[s].uniformCount; u++) {
		const e = entryOf(bindGroups[g], shaders[s].uniforms[u].binding);
		const offset = (bound.dynamicOffsets[bindGroups[g].dynamicIndex[e]] as int64) + bindGroups[g].entries[e].offset;
		const b = bufferRecords.slotIndex(bindGroups[g].entries[e].buffer.id);
		if (offset + (shaders[s].uniforms[u].size as int64) > bufferRecords.slots[b].size) {
			stop(`uniform binding ${shaders[s].uniforms[u].binding} at offset ${offset} overruns its buffer`);
		}
		const native = buffers[b].natives[buffers[b].active];
		const slot = shaders[s].uniforms[u].nativeSlot;
		if (shaders[s].uniforms[u].vertexStage) { bindBuffer(STAGE_VERTEX, native, offset, slot); }
		if (shaders[s].uniforms[u].fragmentStage) { bindBuffer(STAGE_FRAGMENT, native, offset, slot); }
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	const index = bufferRecords.slotIndex(buffer.id);
	if (!has(bufferRecords.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (bufferRecords.slots[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	return index;
}

function copyDestinationBuffer(buffer: GPUBuffer, member: string): int32 {
	const index = copyableBuffer(buffer, member, GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	buffers[index].inPlace = true;
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	const index = textureRecords.slotIndex(info.texture.id);
	if (!has(textureRecords.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textureRecords.slots[index].swapchainView != 0) {
		if (textures[index].natives[0] == null) { stop(`${member}: the swapchain texture has no back buffer to copy`); }
		return index;
	}
	if (textureRecords.slots[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	return index;
}

function copyDestinationTexture(info: GPUTexelCopyTextureInfo, member: string): int32 {
	const index = copyableTexture(info, member, GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	textures[index].inPlace = true;
	return index;
}


function texelCopyBytes(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): int32 {
	const format = formatInfo(textureRecords.slots[index].format, "texture format");
	if (format.depth) {
		checkedDepthTexelCopy(member, textureRecords.slots[index].id, textureRecords.slots[index].format, format.stencil, writes, textureRecords.slots[index].width, textureRecords.slots[index].height, copy.mipLevel, size);
	}
	return format.bytesPerPixel;
}

function liveTexture(index: int32): Ptr<MtlTextureImpl> {
	textures[index].gpuUsed = true;
	return textures[index].natives[textures[index].active];
}
function liveBuffer(index: int32): Ptr<MtlBufferImpl> { return buffers[index].natives[buffers[index].active]; }

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination, "copyBufferToBuffer destination");
	checkedBufferCopy(source.id, bufferRecords.slots[from].size, sourceOffset, destination.id, bufferRecords.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	beginFrame();
	mtlBlitBufferToBuffer(commandBuffer, liveBuffer(from), sourceOffset, liveBuffer(to), destinationOffset, size);
	buffers[from].gpuUseFrame = currentFrame();
	buffers[to].gpuUseFrame = currentFrame();
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination.buffer, "copyTextureToBuffer destination");
	checkedCopyRegion("copyTextureToBuffer source", textureRecords.slots[from], source, size);
	const bytesPerPixel = texelCopyBytes(from, "copyTextureToBuffer source", false, source, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", bytesPerPixel, bufferRecords.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	beginFrame();
	if (textureRecords.slots[from].volume) {
		mtlBlitTextureToBuffer(commandBuffer, liveTexture(from), 0, source.mipLevel, source.origin.x, source.origin.y, source.origin.z, size.width, size.height, size.depthOrArrayLayers, liveBuffer(to), destination.offset, bytesPerRow, imageBytes as int32);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlBlitTextureToBuffer(commandBuffer, liveTexture(from), source.origin.z + i, source.mipLevel, source.origin.x, source.origin.y, 0, size.width, size.height, 1, liveBuffer(to), destination.offset + imageBytes * (i as int64), bytesPerRow, (bytesPerRow * size.height));
		}
	}
	buffers[to].gpuUseFrame = currentFrame();
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationTexture(destination, "copyBufferToTexture destination");
	checkedCopyRegion("copyBufferToTexture destination", textureRecords.slots[to], destination, size);
	const bytesPerPixel = texelCopyBytes(to, "copyBufferToTexture destination", true, destination, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", bytesPerPixel, bufferRecords.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	beginFrame();
	if (textureRecords.slots[to].volume) {
		mtlBlitBufferToTexture(commandBuffer, liveBuffer(from), source.offset, bytesPerRow, imageBytes as int32, size.width, size.height, size.depthOrArrayLayers, liveTexture(to), 0, destination.mipLevel, destination.origin.x, destination.origin.y, destination.origin.z);
	} else {
		for (let i = 0; i < size.depthOrArrayLayers; i++) {
			mtlBlitBufferToTexture(commandBuffer, liveBuffer(from), source.offset + imageBytes * (i as int64), bytesPerRow, 0, size.width, size.height, 1, liveTexture(to), destination.origin.z + i, destination.mipLevel, destination.origin.x, destination.origin.y, 0);
		}
	}
	buffers[from].gpuUseFrame = currentFrame();
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationTexture(destination, "copyTextureToTexture destination");
	checkedCopyRegion("copyTextureToTexture source", textureRecords.slots[from], source, size);
	checkedCopyRegion("copyTextureToTexture destination", textureRecords.slots[to], destination, size);
	checkedTextureToTextureCopy(
		source,
		destination,
		size,
		textureRecords.slots[from].format,
		textureRecords.slots[to].format,
		textureRecords.slots[from].volume,
		textureRecords.slots[to].volume,
		formatInfo(textureRecords.slots[from].format, "texture format").depth,
		textureRecords.slots[from].width,
		textureRecords.slots[from].height,
	);
	beginFrame();
	if (textureRecords.slots[from].volume) {
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
export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, length: int64): void {
	const index = bufferRecords.slotIndex(buffer.id);
	if (buffers[index].gpuUseFrame >= 0) {
		if (commandBuffer != null && buffers[index].gpuUseFrame == currentFrame()) {
			stop(`mapAsync on GPUBuffer ${buffer.id} would wait for the frame's command buffer, which is not committed: submit the copy first`);
		}
		if (mtlWaitCommitted() == 0) { stop(`mapAsync on GPUBuffer ${buffer.id}: the command buffer that wrote it failed`); }
	}
}

// A copy of the mapped bytes: WebGPU's ArrayBuffer view has no MetaScript counterpart on a native pointer.
export function getMappedRange(buffer: GPUBuffer, offset: int64, length: int64): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(length);
	mtlCopyOut(liveBuffer(bufferRecords.slotIndex(buffer.id)), offset, bytes[0], length);
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	mtlCopyIn(liveBuffer(bufferRecords.slotIndex(buffer.id)), offset, data[0], (data.length as int64) * (sizeof T as int64));
}
export function createComputePipeline(id: uint32, descriptor: GPUComputePipelineDescriptor): void {
	const s = shaderRecords.slotIndex(descriptor.compute.module.id);
	const entry = descriptor.compute.entryPoint == "" ? "_main" : descriptor.compute.entryPoint;
	checkedComputeModule(shaders[s].compute != null, entry, shaders[s].computeEntry);
	const state = mtlNewComputePipeline(device, shaders[s].compute, labelText(descriptor.label));
	if (state == null) {
		const log: string = mtlErrorLog();
		stop(`newComputePipelineStateWithDescriptor failed for ${labelOf(descriptor.label)}:\n${log}`);
	}
	const size: int32[3] = shaders[s].workgroup;
	const invocations = mtlComputeMaxThreads(state);
	if (size[0] * size[1] * size[2] > invocations) {
		stop(`workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the ${invocations} invocations this compute pipeline can run`);
	}
	const slot: PipelineSlot = { shader: descriptor.compute.module.id, compute: true, computeState: state };
	put(pipelines, id, slot);
}

export function beginComputePass(passEncoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	if (descriptor.timestampWrites.querySet.id != 0) {
		stop("GPUComputePassDescriptor.timestampWrites is not ported to metal: a compute pass's counter sample is not written before a resolve that follows it in the same command buffer");
	}
	beginFrame();
	computeEncoder = mtlBeginComputePass(commandBuffer, labelText(descriptor.label));
	if (computeEncoder == null) { stop("computeCommandEncoder returned nil"); }
	computeBound = { pipeline: 0 };
	clearBinds();
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	checkedComputePipeline(pipeline.id, pipelines[pipelineRecords.slotIndex(pipeline.id)].compute);
	computeBound.pipeline = pipeline.id;
	computeBound.dirty = true;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	computeBound.bindGroups[index] = bindGroup.id;
	computeBound.dirty = true;
	if (bindGroup.id == 0) { return; }
	const g = bindGroupRecords.slotIndex(bindGroup.id);
	checkedBindGroupSet(index, bindGroups[g].group, bindGroups[g].dynamicCount, dynamicOffsets, UNIFORM_OFFSET_ALIGNMENT);
	if (index == GPU_UNIFORM_GROUP) {
		for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
			computeBound.dynamicOffsets[i] = dynamicOffsets[i];
		}
	}
}

function applyCompute(): int32 {
	const p = pipelineRecords.slotIndex(computeBound.pipeline);
	const s = shaderRecords.slotIndex(pipelines[p].shader);
	if (computeBound.dirty) {
		computeBound.dirty = false;
		mtlComputeSetPipeline(computeEncoder, pipelines[p].computeState);
		if (shaders[s].uniformCount > 0) {
			if (computeBound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the compute pipeline reads bind group 0, which is not set"); }
			applyComputeUniforms(s, bindGroupRecords.slotIndex(computeBound.bindGroups[GPU_UNIFORM_GROUP]));
		}
		if (shaders[s].resourceCount > 0) {
			if (computeBound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the compute pipeline reads bind group 1, which is not set"); }
			applyComputeResources(s, bindGroupRecords.slotIndex(computeBound.bindGroups[GPU_RESOURCE_GROUP]));
		}
	}
	return s;
}

function applyComputeUniforms(s: int32, g: int32): void {
	for (let u = 0; u < shaders[s].uniformCount; u++) {
		const e = entryOf(bindGroups[g], shaders[s].uniforms[u].binding);
		const offset = (computeBound.dynamicOffsets[bindGroups[g].dynamicIndex[e]] as int64) + bindGroups[g].entries[e].offset;
		const b = bufferRecords.slotIndex(bindGroups[g].entries[e].buffer.id);
		if (offset + (shaders[s].uniforms[u].size as int64) > bufferRecords.slots[b].size) {
			stop(`uniform binding ${shaders[s].uniforms[u].binding} at offset ${offset} overruns its buffer`);
		}
		bindBuffer(STAGE_COMPUTE, buffers[b].natives[buffers[b].active], offset, shaders[s].uniforms[u].nativeSlot);
	}
}

function applyComputeResources(s: int32, g: int32): void {
	for (let r = 0; r < shaders[s].resourceCount; r++) {
		const binding: NativeBinding = shaders[s].resources[r];
		const entry: GPUBindGroupEntry = bindGroups[g].entries[entryOf(bindGroups[g], binding.binding)];
		if (binding.kind == BindingKind.Sampler) {
			bindSampler(STAGE_COMPUTE, samplers[samplerRecords.slotIndex(entry.sampler.id)].native, binding.nativeSlot);
		} else if (binding.kind == BindingKind.StorageBuffer) {
			bindBuffer(STAGE_COMPUTE, liveBuffer(bufferRecords.slotIndex(entry.buffer.id)), entry.offset, binding.nativeSlot);
		} else {
			bindTexture(STAGE_COMPUTE, viewNative(viewRecords.slotIndex(entry.textureView.id)), binding.nativeSlot);
		}
	}
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	const s = applyCompute();
	if (x == 0 || y == 0 || z == 0) { return; }
	const size: int32[3] = shaders[s].workgroup;
	mtlDispatch(computeEncoder, x, y, z, size[0], size[1], size[2]);
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = bufferRecords.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, bufferRecords.slots[b].usage, bufferRecords.slots[b].size, offset);
	const s = applyCompute();
	const size: int32[3] = shaders[s].workgroup;
	mtlDispatchIndirect(computeEncoder, liveBuffer(b), offset, size[0], size[1], size[2]);
}

export function endComputePass(): void {
	mtlEndPass(computeEncoder);
	computeEncoder = NO_ENCODER;
	computeBound = { pipeline: 0 };
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

// Outside a pass a group lives on the frame's command buffer, inside one on the pass's encoder,
// so a pass cannot pop a group it did not push.
export function pushDebugGroup(label: string): void {
	if (renderPassOpen()) {
		mtlEncoderPushDebugGroup(encoder, label);
	} else if (computePassOpen()) {
		mtlEncoderPushDebugGroup(computeEncoder, label);
	} else {
		beginFrame();
		mtlPushDebugGroup(commandBuffer, label);
	}
}

export function popDebugGroup(): void {
	if (renderPassOpen()) {
		mtlEncoderPopDebugGroup(encoder);
	} else if (computePassOpen()) {
		mtlEncoderPopDebugGroup(computeEncoder);
	} else {
		mtlPopDebugGroup(commandBuffer);
	}
}

// A command buffer has no signpost, so a marker outside a pass is an empty group.
export function insertDebugMarker(label: string): void {
	if (renderPassOpen()) {
		mtlEncoderInsertSignpost(encoder, label);
	} else if (computePassOpen()) {
		mtlEncoderInsertSignpost(computeEncoder, label);
	} else {
		beginFrame();
		mtlPushDebugGroup(commandBuffer, label);
		mtlPopDebugGroup(commandBuffer);
	}
}

export function createQuerySet(id: uint32, descriptor: GPUQuerySetDescriptor): void {
	const kind: string = descriptor.type;
	const timestamp = kind == "timestamp";
	if (timestamp && mtlSupportsTimestamps(device) == 0) {
		stop("this device has no timestamp queries: features().has('timestamp-query') is false (MTLCounterSamplingPointAtStageBoundary and a nanosecond timestamp counter are required)");
	}
	let slot: QuerySetSlot = {
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
	put(querySets, id, slot);
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySetRecords.slotIndex(querySet.id);
	if (querySets[index].timestamp) {
		mtlReleaseSampleBuffer(querySets[index].samples);
	} else {
		mtlReleaseBuffer(querySets[index].visibility);
	}
	vacate(querySets, querySet.id);
}

function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySetRecords.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets[q].timestamp, querySets[q].count);
}

function markTimestampsWritten(q: int32, writes: GPUPassTimestampWrites): void {
	if (writes.beginningOfPassWriteIndex >= 0) { querySets[q].state[writes.beginningOfPassWriteIndex] = QueryState.Written; }
	if (writes.endOfPassWriteIndex >= 0) { querySets[q].state[writes.endOfPassWriteIndex] = QueryState.Written; }
}

// A timestamp resolves in the counters' own ticks, which are nanoseconds on the devices
// features() reports timestamp-query for (an Intel GPU's tick is 83.333 ns and is refused).
export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	const q = querySetRecords.slotIndex(querySet.id);
	const b = bufferRecords.slotIndex(destination.id);
	const bytes = checkedResolveQuerySet(
		querySets[q].count,
		firstQuery,
		queryCount,
		destination.id,
		bufferRecords.slots[b].usage,
		bufferRecords.slots[b].size,
		destinationOffset,
	);
	if (queryCount == 0) { return; }
	for (let i = 0; i < queryCount; i++) {
		const state = querySets[q].state[firstQuery + i];
		if (state == QueryState.Unwritten) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QueryState.Open) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	beginFrame();
	if (querySets[q].timestamp) {
		mtlResolveCounters(commandBuffer, querySets[q].samples, firstQuery, queryCount, liveBuffer(b), destinationOffset);
	} else {
		mtlBlitBufferToBuffer(commandBuffer, querySets[q].visibility, (firstQuery as int64) * QUERY_BYTES, liveBuffer(b), destinationOffset, bytes);
	}
	buffers[b].gpuUseFrame = currentFrame();
}

export function beginOcclusionQuery(queryIndex: int32): void {
	const q = querySetRecords.slotIndex(occlusionSetId());
	checkedOcclusionRange(queryIndex, querySets[q].count);
	checkedOcclusionReuse(queryIndex, querySets[q].usedPass[queryIndex]);
	querySets[q].usedPass[queryIndex] = passSerial();
	querySets[q].state[queryIndex] = QueryState.Open;
	mtlSetVisibility(encoder, 1, (queryIndex as int64) * QUERY_BYTES);
}

export function endOcclusionQuery(): void {
	const q = querySetRecords.slotIndex(occlusionSetId());
	mtlSetVisibility(encoder, 0, (occlusionQueryIndex() as int64) * QUERY_BYTES);
	querySets[q].state[occlusionQueryIndex()] = QueryState.Written;
}
