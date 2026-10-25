import "./lost";
import {
	BindingKind,
	bindingKind,
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_SHADER_BINDINGS,
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
	GPUCommandBuffer,
	GPUColor,
	GPUCommandEncoder,
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
	GPUFeatureName,
	GPUIndexFormat,
	GPULiveCounts,
	GPUPassTimestampWrites,
	GPUPrimitiveState,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderBinding,
	GPUShaderStage,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilFaceState,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	checkedBufferCopy,
	checkedCubeView,
	checkedDepthSlice,
	checkedDepthTexelCopy,
	checkedDispatchIndirect,
	checkedNoDepthSlice,
	checkedPassExtent,
	checkedResolveQuerySet,
	checkedResolveTarget,
	samplerMaxLod,
	checkedSingleSubresource,
	checkedTexelBufferLayout,
	checkedTexelCopyRegion,
	checkedTexelWritePitch,
	checkedTextureToTextureCopy,
	checkedTimestampWrites,
	checkedView3d,
	checkedViewLayers,
	checkedViewMips,
	checkedWriteBuffer,
	featureBit,
	firstInstanceRefusal,
	vertexOffsetRefusal,
	stopOnUnportedShaderBindings,
	stopOnUnportedShaderBytecode,
} from "../types.ms";
import {
	clampedAnisotropy,
	cachedLimits,
	addressesBinding,
	checkedBindGroupIndex,
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
	checkedViewDimension,
	entryBytes,
	occlusionQueryIndex,
	occlusionSetId,
	passSerial,
} from "../validate.ms";
import { Pool, allocate, alive, live, liveIds, newPool, release, reset, slotIndex, store } from "../pool.ms";
import {
	WgBindGroupImpl,
	WgBufferImpl,
	WgLayoutImpl,
	WgModuleImpl,
	WgPipelineImpl,
	WgQuerySetImpl,
	WgSamplerImpl,
	WgTextureImpl,
	WgViewImpl,
	wgBeginComputePass,
	wgBeginEncoder,
	wgBeginOcclusionQuery,
	wgConstantsDisagreement,
	wgCopyBufferToBuffer,
	wgCopyBufferToTexture,
	wgCopyTextureToBuffer,
	wgCopyTextureToTexture,
	wgBeginPass,
	wgCreateBindGroup,
	wgCreateBuffer,
	wgCreateComputePipeline,
	wgCreateLayout,
	wgCreateModule,
	wgCreatePipeline,
	wgCreateQuerySet,
	wgCreateSampler,
	wgCreateTexture,
	wgCreateView,
	wgDispatch,
	wgDispatchIndirect,
	wgDraw,
	wgDrawIndexed,
	wgEndComputePass,
	wgEndOcclusionQuery,
	wgEndPass,
	wgFinish,
	wgInsertDebugMarker,
	wgLimit,
	wgMinUniformBufferOffsetAlignment,
	wgPopDebugGroup,
	wgPushDebugGroup,
	wgReleaseBindGroup,
	wgReleaseBuffer,
	wgReleaseComputePipeline,
	wgReleaseLayout,
	wgReleaseModule,
	wgReleasePipeline,
	wgReleaseQuerySet,
	wgReleaseSampler,
	wgReleaseTexture,
	wgReleaseView,
	wgHasFeature,
	wgResolveQuerySet,
	wgSetBindGroup,
	wgSetBlendConstant,
	wgSetComputeBindGroup,
	wgSetComputePipeline,
	wgSetIndexBuffer,
	wgSetPipeline,
	wgSetScissorRect,
	wgSetStencilReference,
	wgSetViewport,
	wgSetup,
	wgSetVertexBuffer,
	wgShutdown,
	wgSubmit,
	wgTextureNative,
	wgViewFrom,
	wgWriteBuffer,
	wgWriteTexture,
} from "./wgpu.h";

@passC("--use-port=emdawnwebgpu");
@passL("--use-port=emdawnwebgpu");

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

const MAX_UNIFORM_WGSL_BINDING = 16;
const MAX_RESOURCE_WGSL_BINDING = 128;

const FORMAT_R8_UNORM = 0x01;
const FORMAT_R16_FLOAT = 0x09;
const FORMAT_RG8_UNORM = 0x0A;
const FORMAT_R32_FLOAT = 0x0E;
const FORMAT_R32_UINT = 0x0F;
const FORMAT_RG16_FLOAT = 0x15;
const FORMAT_RGBA8_UNORM = 0x16;
const FORMAT_RGBA8_UNORM_SRGB = 0x17;
const FORMAT_RGBA8_UINT = 0x19;
const FORMAT_RGBA8_SINT = 0x1A;
const FORMAT_BGRA8_UNORM = 0x1B;
const FORMAT_BGRA8_UNORM_SRGB = 0x1C;
const FORMAT_RGB10A2_UNORM = 0x1E;
const FORMAT_RG11B10_UFLOAT = 0x1F;
const FORMAT_RG32_FLOAT = 0x21;
const FORMAT_RGBA16_UINT = 0x26;
const FORMAT_RGBA16_FLOAT = 0x28;
const FORMAT_RGBA32_FLOAT = 0x29;
const FORMAT_RGBA32_UINT = 0x2A;
const FORMAT_DEPTH16_UNORM = 0x2D;
const FORMAT_DEPTH24_PLUS_STENCIL8 = 0x2F;
const FORMAT_DEPTH32_FLOAT = 0x30;

const FEATURE_DEPTH_CLIP_CONTROL = 0x02;
const FEATURE_DEPTH32_FLOAT_STENCIL8 = 0x03;
const FEATURE_TEXTURE_COMPRESSION_BC = 0x04;
const FEATURE_TEXTURE_COMPRESSION_ETC2 = 0x06;
const FEATURE_TEXTURE_COMPRESSION_ASTC = 0x07;
const FEATURE_TIMESTAMP_QUERY = 0x09;
const FEATURE_INDIRECT_FIRST_INSTANCE = 0x0A;
const FEATURE_SHADER_F16 = 0x0B;
const FEATURE_RG11B10_UFLOAT_RENDERABLE = 0x0C;
const FEATURE_BGRA8_UNORM_STORAGE = 0x0D;
const FEATURE_FLOAT32_FILTERABLE = 0x0E;
const FEATURE_FLOAT32_BLENDABLE = 0x0F;
const FEATURE_DUAL_SOURCE_BLENDING = 0x11;

const LIMIT_TEXTURE_DIMENSION_1D = 0;
const LIMIT_TEXTURE_DIMENSION_2D = 1;
const LIMIT_TEXTURE_DIMENSION_3D = 2;
const LIMIT_TEXTURE_ARRAY_LAYERS = 3;
const LIMIT_BIND_GROUPS = 4;
const LIMIT_SAMPLED_TEXTURES = 5;
const LIMIT_SAMPLERS = 6;
const LIMIT_STORAGE_BUFFERS = 7;
const LIMIT_STORAGE_TEXTURES = 8;
const LIMIT_UNIFORM_BUFFERS = 9;
const LIMIT_UNIFORM_BINDING_SIZE = 10;
const LIMIT_STORAGE_BINDING_SIZE = 11;
const LIMIT_VERTEX_BUFFERS = 12;
const LIMIT_VERTEX_ATTRIBUTES = 13;
const LIMIT_COLOR_ATTACHMENTS = 14;
const LIMIT_WORKGROUP_SIZE_X = 15;
const LIMIT_WORKGROUP_SIZE_Y = 16;
const LIMIT_WORKGROUP_SIZE_Z = 17;
const LIMIT_WORKGROUP_INVOCATIONS = 18;
const LIMIT_WORKGROUPS_PER_DIMENSION = 19;
const LIMIT_UNIFORM_ALIGNMENT = 20;
const LIMIT_STORAGE_ALIGNMENT = 21;

const QUERY_UNWRITTEN: uint8 = 0;
const QUERY_OPEN: uint8 = 1;
const QUERY_WRITTEN: uint8 = 2;

const TOPOLOGY_POINT_LIST = 1;
const TOPOLOGY_LINE_LIST = 2;
const TOPOLOGY_LINE_STRIP = 3;
const TOPOLOGY_TRIANGLE_LIST = 4;
const TOPOLOGY_TRIANGLE_STRIP = 5;
const DIMENSION_2D = 2;
const DIMENSION_3D = 3;
const VIEW_2D = 2;
const VIEW_2D_ARRAY = 3;
const VIEW_CUBE = 4;
const VIEW_CUBE_ARRAY = 5;
const VIEW_3D = 6;
const MIPMAP_NEAREST = 1;
const MIPMAP_LINEAR = 2;
const STENCIL_MASK_ALL: uint32 = 0xFFFFFFFF;

const LAYOUT_UNIFORM = 0;
const LAYOUT_TEXTURE = 1;
const LAYOUT_SAMPLER = 2;
const LAYOUT_STORAGE_BUFFER = 3;
const LAYOUT_STORAGE_TEXTURE = 4;
const BUFFER_STORAGE = 3;
const BUFFER_READ_ONLY_STORAGE = 4;
const ACCESS_WRITE_ONLY = 2;
const ACCESS_READ_ONLY = 3;
const ACCESS_READ_WRITE = 4;
const SAMPLE_FLOAT = 2;
const SAMPLE_UNFILTERABLE_FLOAT = 3;
const SAMPLE_SINT = 5;
const SAMPLE_UINT = 6;
const SAMPLER_FILTERING = 2;
const SAMPLER_NON_FILTERING = 3;
const ASPECT_ALL = 1;
const ASPECT_DEPTH_ONLY = 3;
const LOAD_LOAD = 1;
const LOAD_CLEAR = 2;
const STORE_STORE = 1;
const STORE_DISCARD = 2;
const STEP_VERTEX = 1;
const STEP_INSTANCE = 2;
const CULL_NONE = 1;
const CULL_FRONT = 2;
const CULL_BACK = 3;
const FRONT_CCW = 1;
const FRONT_CW = 2;
// Values of the WGPU enums in webgpu.h, the emdawnwebgpu port header.
const COMPARE_NEVER = 1;
const COMPARE_LESS = 2;
const COMPARE_EQUAL = 3;
const COMPARE_LESS_EQUAL = 4;
const COMPARE_GREATER = 5;
const COMPARE_NOT_EQUAL = 6;
const COMPARE_GREATER_EQUAL = 7;
const COMPARE_ALWAYS = 8;
const BLEND_ZERO = 1;
const BLEND_ONE = 2;
const BLEND_SRC = 3;
const BLEND_ONE_MINUS_SRC = 4;
const BLEND_SRC_ALPHA = 5;
const BLEND_ONE_MINUS_SRC_ALPHA = 6;
const BLEND_DST = 7;
const BLEND_ONE_MINUS_DST = 8;
const BLEND_DST_ALPHA = 9;
const BLEND_ONE_MINUS_DST_ALPHA = 10;
const BLEND_SRC_ALPHA_SATURATED = 11;
const BLEND_CONSTANT = 12;
const BLEND_ONE_MINUS_CONSTANT = 13;
const BLEND_OP_ADD = 1;
const BLEND_OP_SUBTRACT = 2;
const BLEND_OP_REVERSE_SUBTRACT = 3;
const BLEND_OP_MIN = 4;
const BLEND_OP_MAX = 5;
const STENCIL_OP_KEEP = 1;
const STENCIL_OP_ZERO = 2;
const STENCIL_OP_REPLACE = 3;
const STENCIL_OP_INVERT = 4;
const STENCIL_OP_INCREMENT_CLAMP = 5;
const STENCIL_OP_DECREMENT_CLAMP = 6;
const STENCIL_OP_INCREMENT_WRAP = 7;
const STENCIL_OP_DECREMENT_WRAP = 8;
const VERTEX_FLOAT32 = 0x1C;
const VERTEX_FLOAT32X2 = 0x1D;
const VERTEX_FLOAT32X3 = 0x1E;
const VERTEX_FLOAT32X4 = 0x1F;
const VERTEX_UINT32 = 0x20;
const VERTEX_UINT32X2 = 0x21;
const VERTEX_UINT32X3 = 0x22;
const VERTEX_UINT32X4 = 0x23;
const VERTEX_SINT32 = 0x24;
const VERTEX_SINT32X2 = 0x25;
const VERTEX_SINT32X3 = 0x26;
const VERTEX_SINT32X4 = 0x27;
const VERTEX_UINT8X2 = 0x02;
const VERTEX_UINT8X4 = 0x03;
const VERTEX_SINT8X2 = 0x05;
const VERTEX_SINT8X4 = 0x06;
const VERTEX_UNORM8X2 = 0x08;
const VERTEX_UNORM8X4 = 0x09;
const VERTEX_SNORM8X2 = 0x0B;
const VERTEX_SNORM8X4 = 0x0C;
const VERTEX_UINT16X2 = 0x0E;
const VERTEX_UINT16X4 = 0x0F;
const VERTEX_SINT16X2 = 0x11;
const VERTEX_SINT16X4 = 0x12;
const VERTEX_UNORM16X2 = 0x14;
const VERTEX_UNORM16X4 = 0x15;
const VERTEX_SNORM16X2 = 0x17;
const VERTEX_SNORM16X4 = 0x18;
const VERTEX_FLOAT16X2 = 0x1A;
const VERTEX_FLOAT16X4 = 0x1B;
const ADDRESS_CLAMP = 1;
const ADDRESS_REPEAT = 2;
const ADDRESS_MIRROR = 3;
const FILTER_NEAREST = 1;
const FILTER_LINEAR = 2;
const INDEX_UINT16 = 1;
const INDEX_UINT32 = 2;
const COLOR_WRITE_ALL = 0xF;

const LAYOUT_STRIDE = 6;
const PL_BUFFER_COUNT = 0;
const PL_TARGET_COUNT = 1;
const PL_TOPOLOGY = 2;
const PL_STRIP_INDEX_FORMAT = 3;
const PL_CULL_MODE = 4;
const PL_FRONT_FACE = 5;
const PL_SAMPLE_COUNT = 6;
const PL_DEPTH_FORMAT = 7;
const PL_DEPTH_WRITE = 8;
const PL_DEPTH_COMPARE = 9;
const PL_STENCIL_READ_MASK = 10;
const PL_STENCIL_WRITE_MASK = 11;
const PL_DEPTH_BIAS = 12;
const PL_STENCIL_FRONT = 13;
const PL_STENCIL_BACK = 17;
const PL_BUFFERS = 21;
const PL_BUFFER_STRIDE = 3 + GPU_MAX_VERTEX_ATTRIBUTES * 3;
const PL_TARGETS = PL_BUFFERS + GPU_MAX_VERTEX_BUFFERS * PL_BUFFER_STRIDE;
const PL_TARGET_STRIDE = 10;
const PL_SIZE = PL_TARGETS + GPU_MAX_COLOR_ATTACHMENTS * PL_TARGET_STRIDE;
const PASS_COLOR_COUNT = 0;
const PASS_WIDTH = 1;
const PASS_HEIGHT = 2;
const PASS_TIMESTAMP_BEGIN = 3;
const PASS_TIMESTAMP_END = 4;
const PASS_DEPTH_LOAD = 5;
const PASS_DEPTH_STORE = 6;
const PASS_DEPTH_STENCIL = 7;
const PASS_COLOR_OPS = 8;
const PASS_COLOR_OP_STRIDE = 3;
const PASS_SIZE = PASS_COLOR_OPS + GPU_MAX_COLOR_ATTACHMENTS * PASS_COLOR_OP_STRIDE;
const PASS_DEPTH_CLEAR = GPU_MAX_COLOR_ATTACHMENTS * 4;

const NO_BUFFER = null as unknown as Ptr<WgBufferImpl>;
const NO_TEXTURE = null as unknown as Ptr<WgTextureImpl>;
const NO_VIEW = null as unknown as Ptr<WgViewImpl>;
const NO_SAMPLER = null as unknown as Ptr<WgSamplerImpl>;
const NO_BIND_GROUP = null as unknown as Ptr<WgBindGroupImpl>;
const NO_QUERY_SET = null as unknown as Ptr<WgQuerySetImpl>;

struct FormatInfo {
	native: int32;
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
}

struct BufferSlot {
	id: uint32;
	size: int64;
	usage: int32;
	native: Ptr<WgBufferImpl>;
	writtenFrame: int64;
	writtenEnd: int64;
}

struct TextureSlot {
	id: uint32;
	width: int32;
	height: int32;
	format: GPUTextureFormat;
	info: FormatInfo;
	usage: int32;
	sampleCount: int32;
	mipLevels: int32;
	layers: int32;
	volume: boolean;
	cube: boolean;
	native: Ptr<WgTextureImpl>;
	swapchainView: uint32;
}

struct ViewSlot {
	id: uint32;
	texture: uint32;
	native: Ptr<WgViewImpl>;
	binding: Ptr<WgViewImpl>;
	swapchainResolve: Ptr<WgViewImpl>;
	baseMip: int32;
	mipCount: int32;
	dimension: int32;
	attachable: boolean;
	swapchain: boolean;
}

struct SamplerSlot {
	id: uint32;
	native: Ptr<WgSamplerImpl>;
}

struct ShaderBinding {
	binding: int32;
	kind: BindingKind;
	visibility: int32;
	bindingType: int32;
	viewDimension: int32;
	storageFormat: int32;
	size: int32;
}

struct ShaderSlot {
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	id: uint32;
	vertex: Ptr<WgModuleImpl>;
	fragment: Ptr<WgModuleImpl>;
	compute: Ptr<WgModuleImpl>;
	vertexEntry: string;
	fragmentEntry: string;
	computeEntry: string;
	groupLayouts: Ptr<WgLayoutImpl>[2];
	uniforms: ShaderBinding[8];
	uniformCount: int32;
	resources: ShaderBinding[8];
	resourceCount: int32;
}

struct PipelineSlot {
	label: string | null;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	id: uint32;
	shader: uint32;
	native: Ptr<WgPipelineImpl>;
	stripIndexFormat: int32;
	strip: boolean;
	layouts: uint32[2];
	compute: boolean;
}

struct LayoutSlot {
	id: uint32;
	pipeline: uint32;
	group: int32;
}

struct QuerySetSlot {
	id: uint32;
	timestamp: boolean;
	count: int32;
	native: Ptr<WgQuerySetImpl>;
	state: Vec<uint8>;
	usedPass: Vec<int64>;
}

struct PassState {
	timestampSet: uint32;
	timestampEnd: int32;
	width: int32;
	height: int32;
	pipeline: uint32;
	indexFormat: int32;
}

struct ComputeState {
	timestampSet: uint32;
	timestampEnd: int32;
	pipeline: uint32;
	groupMask: int32;
}

struct BindGroupSlot {
	id: uint32;
	group: int32;
	native: Ptr<WgBindGroupImpl>;
	dynamicCount: int32;
}

let frame: int64 = 0;
let pass: PassState = { timestampEnd: -1 };
let computeBound: ComputeState = { timestampEnd: -1 };
let uniformAlignment = 256;
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = {
	format: "bgra8unorm",
	depthFormat: "depth32float",
	sampleCount: 1,
};

let buffers: Pool<BufferSlot> = newPool<BufferSlot>("wgpu", "GPUBuffer", "buffer", { id: 0 });
let textures: Pool<TextureSlot> = newPool<TextureSlot>("wgpu", "GPUTexture", "texture", { id: 0 });
let views: Pool<ViewSlot> = newPool<ViewSlot>("wgpu", "GPUTextureView", "view", { id: 0 });
let samplers: Pool<SamplerSlot> = newPool<SamplerSlot>("wgpu", "GPUSampler", "sampler", { id: 0 });
let shaders: Pool<ShaderSlot> = newPool<ShaderSlot>("wgpu", "GPUShaderModule", "shader module", { id: 0 });
let pipelines: Pool<PipelineSlot> = newPool<PipelineSlot>("wgpu", "GPURenderPipeline", "render or compute pipeline", { id: 0 });
let layouts: Pool<LayoutSlot> = newPool<LayoutSlot>("wgpu", "GPUBindGroupLayout", "bind group layout", { id: 0 });
let querySets: Pool<QuerySetSlot> = newPool<QuerySetSlot>("wgpu", "GPUQuerySet", "query set", { id: 0 });
let bindGroups: Pool<BindGroupSlot> = newPool<BindGroupSlot>("wgpu", "GPUBindGroup", "bind group", { id: 0 });

@noinline function stop(message: string): never {
	console.log(`webgpu wgpu: ${message}`);
	unreachable;
}

@noinline function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu wgpu: ${member} '${value}' is not supported`);
	unreachable;
}

@noinline function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu wgpu: ${member} '${value}' is not supported`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function colorFormat(native: int32, bytesPerPixel: int32): FormatInfo {
	return { native: native, bytesPerPixel: bytesPerPixel, depth: false, stencil: false };
}

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => colorFormat(FORMAT_R8_UNORM, 1),
		"rg8unorm" => colorFormat(FORMAT_RG8_UNORM, 2),
		"rgba8unorm" => colorFormat(FORMAT_RGBA8_UNORM, 4),
		"rgba8unorm-srgb" => colorFormat(FORMAT_RGBA8_UNORM_SRGB, 4),
		"bgra8unorm" => colorFormat(FORMAT_BGRA8_UNORM, 4),
		"bgra8unorm-srgb" => colorFormat(FORMAT_BGRA8_UNORM_SRGB, 4),
		"rgba8uint" => colorFormat(FORMAT_RGBA8_UINT, 4),
		"rgba8sint" => colorFormat(FORMAT_RGBA8_SINT, 4),
		"r16float" => colorFormat(FORMAT_R16_FLOAT, 2),
		"rg16float" => colorFormat(FORMAT_RG16_FLOAT, 4),
		"rgba16float" => colorFormat(FORMAT_RGBA16_FLOAT, 8),
		"rgba16uint" => colorFormat(FORMAT_RGBA16_UINT, 8),
		"r32float" => colorFormat(FORMAT_R32_FLOAT, 4),
		"rg32float" => colorFormat(FORMAT_RG32_FLOAT, 8),
		"rgba32float" => colorFormat(FORMAT_RGBA32_FLOAT, 16),
		"rgba32uint" => colorFormat(FORMAT_RGBA32_UINT, 16),
		"r32uint" => colorFormat(FORMAT_R32_UINT, 4),
		"rgb10a2unorm" => colorFormat(FORMAT_RGB10A2_UNORM, 4),
		"rg11b10ufloat" => colorFormat(FORMAT_RG11B10_UFLOAT, 4),
		"depth16unorm" => ({
			native: FORMAT_DEPTH16_UNORM,
			bytesPerPixel: 2,
			depth: true,
			stencil: false,
		}),
		"depth32float" => ({
			native: FORMAT_DEPTH32_FLOAT,
			bytesPerPixel: 4,
			depth: true,
			stencil: false,
		}),
		"depth24plus-stencil8" => ({
			native: FORMAT_DEPTH24_PLUS_STENCIL8,
			bytesPerPixel: 4,
			depth: true,
			stencil: true,
		}),
		_ => stopOnFormat(member, value),
	};
}

function compareFunction(compare: string, member: string): int32 {
	return match (compare) {
		"never" => COMPARE_NEVER,
		"less" => COMPARE_LESS,
		"equal" => COMPARE_EQUAL,
		"less-equal" => COMPARE_LESS_EQUAL,
		"greater" => COMPARE_GREATER,
		"not-equal" => COMPARE_NOT_EQUAL,
		"greater-equal" => COMPARE_GREATER_EQUAL,
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

function frontFace(face: string): int32 {
	return match (face) {
		"" | "ccw" => FRONT_CCW,
		"cw" => FRONT_CW,
		_ => stopOnMember("primitive.frontFace", face),
	};
}

function blendFactor(factor: string, member: string): int32 {
	return match (factor) {
		"zero" => BLEND_ZERO,
		"" | "one" => BLEND_ONE,
		"src" => BLEND_SRC,
		"one-minus-src" => BLEND_ONE_MINUS_SRC,
		"src-alpha" => BLEND_SRC_ALPHA,
		"one-minus-src-alpha" => BLEND_ONE_MINUS_SRC_ALPHA,
		"dst" => BLEND_DST,
		"one-minus-dst" => BLEND_ONE_MINUS_DST,
		"dst-alpha" => BLEND_DST_ALPHA,
		"one-minus-dst-alpha" => BLEND_ONE_MINUS_DST_ALPHA,
		"src-alpha-saturated" => BLEND_SRC_ALPHA_SATURATED,
		"constant" => BLEND_CONSTANT,
		"one-minus-constant" => BLEND_ONE_MINUS_CONSTANT,
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
		"" | "add" => BLEND_OP_ADD,
		"subtract" => BLEND_OP_SUBTRACT,
		"reverse-subtract" => BLEND_OP_REVERSE_SUBTRACT,
		"min" => BLEND_OP_MIN,
		"max" => BLEND_OP_MAX,
		_ => stopOnMember(member, operation),
	};
}

function vertexFormat(format: string): int32 {
	return match (format) {
		"float32" => VERTEX_FLOAT32,
		"float32x2" => VERTEX_FLOAT32X2,
		"float32x3" => VERTEX_FLOAT32X3,
		"float32x4" => VERTEX_FLOAT32X4,
		"uint32" => VERTEX_UINT32,
		"uint32x2" => VERTEX_UINT32X2,
		"uint32x3" => VERTEX_UINT32X3,
		"uint32x4" => VERTEX_UINT32X4,
		"sint32" => VERTEX_SINT32,
		"sint32x2" => VERTEX_SINT32X2,
		"sint32x3" => VERTEX_SINT32X3,
		"sint32x4" => VERTEX_SINT32X4,
		"uint8x2" => VERTEX_UINT8X2,
		"uint8x4" => VERTEX_UINT8X4,
		"sint8x2" => VERTEX_SINT8X2,
		"sint8x4" => VERTEX_SINT8X4,
		"unorm8x2" => VERTEX_UNORM8X2,
		"unorm8x4" => VERTEX_UNORM8X4,
		"snorm8x2" => VERTEX_SNORM8X2,
		"snorm8x4" => VERTEX_SNORM8X4,
		"uint16x2" => VERTEX_UINT16X2,
		"uint16x4" => VERTEX_UINT16X4,
		"sint16x2" => VERTEX_SINT16X2,
		"sint16x4" => VERTEX_SINT16X4,
		"unorm16x2" => VERTEX_UNORM16X2,
		"unorm16x4" => VERTEX_UNORM16X4,
		"snorm16x2" => VERTEX_SNORM16X2,
		"snorm16x4" => VERTEX_SNORM16X4,
		"float16x2" => VERTEX_FLOAT16X2,
		"float16x4" => VERTEX_FLOAT16X4,
		_ => stopOnMember("vertex attribute format", format),
	};
}

function primitiveTopology(topology: string): int32 {
	return match (topology) {
		"point-list" => TOPOLOGY_POINT_LIST,
		"line-list" => TOPOLOGY_LINE_LIST,
		"line-strip" => TOPOLOGY_LINE_STRIP,
		"" | "triangle-list" => TOPOLOGY_TRIANGLE_LIST,
		"triangle-strip" => TOPOLOGY_TRIANGLE_STRIP,
		_ => stopOnMember("primitive.topology", topology),
	};
}

function stencilOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "keep" => STENCIL_OP_KEEP,
		"zero" => STENCIL_OP_ZERO,
		"replace" => STENCIL_OP_REPLACE,
		"invert" => STENCIL_OP_INVERT,
		"increment-clamp" => STENCIL_OP_INCREMENT_CLAMP,
		"decrement-clamp" => STENCIL_OP_DECREMENT_CLAMP,
		"increment-wrap" => STENCIL_OP_INCREMENT_WRAP,
		"decrement-wrap" => STENCIL_OP_DECREMENT_WRAP,
		_ => stopOnMember(member, operation),
	};
}

function mipmapFilterMode(filter: string): int32 {
	return match (filter) {
		"" | "nearest" => MIPMAP_NEAREST,
		"linear" => MIPMAP_LINEAR,
		_ => stopOnMember("GPUSamplerDescriptor.mipmapFilter", filter),
	};
}

function stepMode(mode: string): int32 {
	return match (mode) {
		"" | "vertex" => STEP_VERTEX,
		"instance" => STEP_INSTANCE,
		_ => stopOnMember("vertex.buffers stepMode", mode),
	};
}

function addressMode(mode: string, member: string): int32 {
	return match (mode) {
		"" | "clamp-to-edge" => ADDRESS_CLAMP,
		"repeat" => ADDRESS_REPEAT,
		"mirror-repeat" => ADDRESS_MIRROR,
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

function indexFormat(format: GPUIndexFormat): int32 {
	const value: string = format;
	return match (value) {
		"uint16" => INDEX_UINT16,
		"uint32" => INDEX_UINT32,
		_ => stopOnMember("setIndexBuffer indexFormat", value),
	};
}

function attachmentMember(index: int32, field: string): string {
	return index < 0 ? `depthStencilAttachment.${field}` : `colorAttachments[${index}].${field}`;
}

function loadOp(op: string, index: int32, field: string): int32 {
	return match (op) {
		"clear" => LOAD_CLEAR,
		"load" => LOAD_LOAD,
		_ => stopOnMember(attachmentMember(index, field), op),
	};
}

function storeOp(op: string, index: int32, field: string): int32 {
	return match (op) {
		"store" => STORE_STORE,
		"discard" => STORE_DISCARD,
		_ => stopOnMember(attachmentMember(index, field), op),
	};
}

function sampleType(sample: string): int32 {
	return match (sample) {
		"" | "float" => SAMPLE_FLOAT,
		"unfilterable-float" => SAMPLE_UNFILTERABLE_FLOAT,
		"sint" => SAMPLE_SINT,
		"uint" => SAMPLE_UINT,
		_ => stopOnMember("GPUShaderBinding.sampleType", sample),
	};
}

function bindingViewDimension(dimension: string): int32 {
	return match (dimension) {
		"" | "2d" => VIEW_2D,
		"2d-array" => VIEW_2D_ARRAY,
		"cube" => VIEW_CUBE,
		"cube-array" => VIEW_CUBE_ARRAY,
		"3d" => VIEW_3D,
		_ => stopOnMember("GPUShaderBinding.viewDimension", dimension),
	};
}

function samplerType(sampler: string): int32 {
	return match (sampler) {
		"" | "filtering" => SAMPLER_FILTERING,
		"non-filtering" => SAMPLER_NON_FILTERING,
		_ => stopOnMember("GPUShaderBinding.samplerType", sampler),
	};
}

function storageBufferType(type: string): int32 {
	return match (type) {
		"storage" => BUFFER_STORAGE,
		"read-only-storage" => BUFFER_READ_ONLY_STORAGE,
		_ => stopOnMember("GPUShaderBinding.bufferType", type),
	};
}

function storageAccess(access: string): int32 {
	return match (access) {
		"write-only" => ACCESS_WRITE_ONLY,
		"read-only" => ACCESS_READ_ONLY,
		"read-write" => ACCESS_READ_WRITE,
		_ => stopOnMember("GPUShaderBinding.storageAccess", access),
	};
}

function bindingType(binding: GPUShaderBinding, kind: BindingKind): int32 {
	return match (kind) {
		BindingKind.Uniform => 0,
		BindingKind.Texture => sampleType(binding.sampleType),
		BindingKind.Sampler => samplerType(binding.samplerType),
		BindingKind.StorageBuffer => storageBufferType(binding.bufferType),
		BindingKind.StorageTexture => storageAccess(binding.storageAccess),
	};
}

function storageCapable(native: int32): boolean {
	if (native == FORMAT_BGRA8_UNORM) { return wgHasFeature(FEATURE_BGRA8_UNORM_STORAGE) != 0; }
	return native == FORMAT_RGBA8_UNORM || native == FORMAT_RGBA8_UINT || native == FORMAT_RGBA8_SINT
		|| native == FORMAT_RGBA16_UINT || native == FORMAT_RGBA16_FLOAT || native == FORMAT_R32_UINT
		|| native == FORMAT_R32_FLOAT || native == FORMAT_RG32_FLOAT || native == FORMAT_RGBA32_FLOAT;
}

function storageFormatOf(format: GPUTextureFormat, member: string): int32 {
	const name: string = format;
	if (name == "") { stop(`${member} is required for a storage-texture binding`); }
	const info = formatInfo(format, member);
	if (!storageCapable(info.native)) { stop(`${member} '${name}' is not a WebGPU storage texture format (bgra8unorm needs the device feature bgra8unorm-storage)`); }
	return info.native;
}

function labelText(label: string | null): string {
	if (label === null) { return ""; }
	return label;
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

function checkMirroredConstants(): void {
	const values: int32[] = [
		FORMAT_R8_UNORM,
		FORMAT_R16_FLOAT,
		FORMAT_RG8_UNORM,
		FORMAT_R32_FLOAT,
		FORMAT_R32_UINT,
		FORMAT_RG16_FLOAT,
		FORMAT_RGBA8_UNORM,
		FORMAT_RGBA8_UNORM_SRGB,
		FORMAT_RGBA8_UINT,
		FORMAT_RGBA8_SINT,
		FORMAT_BGRA8_UNORM,
		FORMAT_BGRA8_UNORM_SRGB,
		FORMAT_RGB10A2_UNORM,
		FORMAT_RG11B10_UFLOAT,
		FORMAT_RG32_FLOAT,
		FORMAT_RGBA16_UINT,
		FORMAT_RGBA16_FLOAT,
		FORMAT_RGBA32_FLOAT,
		FORMAT_RGBA32_UINT,
		FORMAT_DEPTH16_UNORM,
		FORMAT_DEPTH24_PLUS_STENCIL8,
		FORMAT_DEPTH32_FLOAT,
		FEATURE_DEPTH_CLIP_CONTROL,
		FEATURE_DEPTH32_FLOAT_STENCIL8,
		FEATURE_TEXTURE_COMPRESSION_BC,
		FEATURE_TEXTURE_COMPRESSION_ETC2,
		FEATURE_TEXTURE_COMPRESSION_ASTC,
		FEATURE_TIMESTAMP_QUERY,
		FEATURE_INDIRECT_FIRST_INSTANCE,
		FEATURE_SHADER_F16,
		FEATURE_RG11B10_UFLOAT_RENDERABLE,
		FEATURE_BGRA8_UNORM_STORAGE,
		FEATURE_FLOAT32_FILTERABLE,
		FEATURE_FLOAT32_BLENDABLE,
		FEATURE_DUAL_SOURCE_BLENDING,
		TOPOLOGY_POINT_LIST,
		TOPOLOGY_LINE_LIST,
		TOPOLOGY_LINE_STRIP,
		TOPOLOGY_TRIANGLE_LIST,
		TOPOLOGY_TRIANGLE_STRIP,
		DIMENSION_2D,
		DIMENSION_3D,
		VIEW_2D,
		VIEW_2D_ARRAY,
		VIEW_CUBE,
		VIEW_CUBE_ARRAY,
		VIEW_3D,
		MIPMAP_NEAREST,
		MIPMAP_LINEAR,
		BUFFER_STORAGE,
		BUFFER_READ_ONLY_STORAGE,
		ACCESS_WRITE_ONLY,
		ACCESS_READ_ONLY,
		ACCESS_READ_WRITE,
		SAMPLE_FLOAT,
		SAMPLE_UNFILTERABLE_FLOAT,
		SAMPLE_SINT,
		SAMPLE_UINT,
		SAMPLER_FILTERING,
		SAMPLER_NON_FILTERING,
		ASPECT_ALL,
		ASPECT_DEPTH_ONLY,
		LOAD_LOAD,
		LOAD_CLEAR,
		STORE_STORE,
		STORE_DISCARD,
		STEP_VERTEX,
		STEP_INSTANCE,
		CULL_NONE,
		CULL_FRONT,
		CULL_BACK,
		FRONT_CCW,
		FRONT_CW,
		COMPARE_NEVER,
		COMPARE_LESS,
		COMPARE_EQUAL,
		COMPARE_LESS_EQUAL,
		COMPARE_GREATER,
		COMPARE_NOT_EQUAL,
		COMPARE_GREATER_EQUAL,
		COMPARE_ALWAYS,
		BLEND_ZERO,
		BLEND_ONE,
		BLEND_SRC,
		BLEND_ONE_MINUS_SRC,
		BLEND_SRC_ALPHA,
		BLEND_ONE_MINUS_SRC_ALPHA,
		BLEND_DST,
		BLEND_ONE_MINUS_DST,
		BLEND_DST_ALPHA,
		BLEND_ONE_MINUS_DST_ALPHA,
		BLEND_SRC_ALPHA_SATURATED,
		BLEND_CONSTANT,
		BLEND_ONE_MINUS_CONSTANT,
		BLEND_OP_ADD,
		BLEND_OP_SUBTRACT,
		BLEND_OP_REVERSE_SUBTRACT,
		BLEND_OP_MIN,
		BLEND_OP_MAX,
		STENCIL_OP_KEEP,
		STENCIL_OP_ZERO,
		STENCIL_OP_REPLACE,
		STENCIL_OP_INVERT,
		STENCIL_OP_INCREMENT_CLAMP,
		STENCIL_OP_DECREMENT_CLAMP,
		STENCIL_OP_INCREMENT_WRAP,
		STENCIL_OP_DECREMENT_WRAP,
		VERTEX_FLOAT32,
		VERTEX_FLOAT32X2,
		VERTEX_FLOAT32X3,
		VERTEX_FLOAT32X4,
		VERTEX_UINT32,
		VERTEX_UINT32X2,
		VERTEX_UINT32X3,
		VERTEX_UINT32X4,
		VERTEX_SINT32,
		VERTEX_SINT32X2,
		VERTEX_SINT32X3,
		VERTEX_SINT32X4,
		VERTEX_UINT8X2,
		VERTEX_UINT8X4,
		VERTEX_SINT8X2,
		VERTEX_SINT8X4,
		VERTEX_UNORM8X2,
		VERTEX_UNORM8X4,
		VERTEX_SNORM8X2,
		VERTEX_SNORM8X4,
		VERTEX_UINT16X2,
		VERTEX_UINT16X4,
		VERTEX_SINT16X2,
		VERTEX_SINT16X4,
		VERTEX_UNORM16X2,
		VERTEX_UNORM16X4,
		VERTEX_SNORM16X2,
		VERTEX_SNORM16X4,
		VERTEX_FLOAT16X2,
		VERTEX_FLOAT16X4,
		ADDRESS_CLAMP,
		ADDRESS_REPEAT,
		ADDRESS_MIRROR,
		FILTER_NEAREST,
		FILTER_LINEAR,
		INDEX_UINT16,
		INDEX_UINT32,
		COLOR_WRITE_ALL,
		LIMIT_TEXTURE_DIMENSION_1D,
		LIMIT_TEXTURE_DIMENSION_2D,
		LIMIT_TEXTURE_DIMENSION_3D,
		LIMIT_TEXTURE_ARRAY_LAYERS,
		LIMIT_BIND_GROUPS,
		LIMIT_SAMPLED_TEXTURES,
		LIMIT_SAMPLERS,
		LIMIT_STORAGE_BUFFERS,
		LIMIT_STORAGE_TEXTURES,
		LIMIT_UNIFORM_BUFFERS,
		LIMIT_UNIFORM_BINDING_SIZE,
		LIMIT_STORAGE_BINDING_SIZE,
		LIMIT_VERTEX_BUFFERS,
		LIMIT_VERTEX_ATTRIBUTES,
		LIMIT_COLOR_ATTACHMENTS,
		LIMIT_WORKGROUP_SIZE_X,
		LIMIT_WORKGROUP_SIZE_Y,
		LIMIT_WORKGROUP_SIZE_Z,
		LIMIT_WORKGROUP_INVOCATIONS,
		LIMIT_WORKGROUPS_PER_DIMENSION,
		LIMIT_UNIFORM_ALIGNMENT,
		LIMIT_STORAGE_ALIGNMENT,
		LAYOUT_UNIFORM,
		LAYOUT_TEXTURE,
		LAYOUT_SAMPLER,
		LAYOUT_STORAGE_BUFFER,
		LAYOUT_STORAGE_TEXTURE,
		LAYOUT_STRIDE,
		PL_BUFFER_COUNT,
		PL_TARGET_COUNT,
		PL_TOPOLOGY,
		PL_STRIP_INDEX_FORMAT,
		PL_CULL_MODE,
		PL_FRONT_FACE,
		PL_SAMPLE_COUNT,
		PL_DEPTH_FORMAT,
		PL_DEPTH_WRITE,
		PL_DEPTH_COMPARE,
		PL_STENCIL_READ_MASK,
		PL_STENCIL_WRITE_MASK,
		PL_DEPTH_BIAS,
		PL_STENCIL_FRONT,
		PL_STENCIL_BACK,
		PL_BUFFERS,
		PL_TARGET_STRIDE,
		PASS_COLOR_COUNT,
		PASS_WIDTH,
		PASS_HEIGHT,
		PASS_TIMESTAMP_BEGIN,
		PASS_TIMESTAMP_END,
		PASS_DEPTH_LOAD,
		PASS_DEPTH_STORE,
		PASS_DEPTH_STENCIL,
		PASS_COLOR_OPS,
		PASS_COLOR_OP_STRIDE,
		PL_BUFFER_STRIDE,
		PL_TARGETS,
		PASS_DEPTH_CLEAR,
		GPU_MAX_VERTEX_BUFFERS,
		GPU_MAX_VERTEX_ATTRIBUTES,
		GPU_MAX_COLOR_ATTACHMENTS,
	];
	const disagreement: string = wgConstantsDisagreement(values[0], values.length as int32);
	if (disagreement != "") { stop(`a constant of backend.ms disagrees with webgpu.h or wgpu.c, ${disagreement}`); }
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device === null) {
		stop("requestDevice needs the WGPUDevice the window created");
	}
	checkMirroredConstants();
	if (wgSetup(environment.device) == 0) { stop("the WGPUDevice gave no queue or no limits"); }
	uniformAlignment = wgMinUniformBufferOffsetAlignment();
	frame = 0;
	pass.pipeline = 0;
	computeBound.pipeline = 0;
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(querySets);
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
	if (depthFormat != "") {
		const info = formatInfo(environment.depthFormat, "NativeEnvironment.depthFormat");
		if (!info.depth) { stopOnMember("NativeEnvironment.depthFormat", depthFormat); }
	}
	return {
		format: environment.colorFormat,
		depthFormat: environment.depthFormat,
		sampleCount: environment.sampleCount == 0 ? 1 : environment.sampleCount,
	};
}

export function canvasConfiguration(): GPUCanvasConfiguration { return canvas; }

export function formatRenderable(format: GPUTextureFormat): boolean {
	formatInfo(format, "formatRenderable format");
	return true;
}

export function frameIndex(): uint32 { return (frame + 1) as uint32; }

export function liveCounts(): GPULiveCounts {
	let counts: GPULiveCounts = { buffers: buffers.live() };
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
		info: formatInfo(format, "the swapchain format"),
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		mipLevels: 1,
		layers: 1,
		native: NO_TEXTURE,
		swapchainView: viewId,
	});
	store(views, {
		id: viewId,
		texture: textureId,
		native: NO_VIEW,
		binding: NO_VIEW,
		swapchainResolve: NO_VIEW,
		attachable: true,
		swapchain: true,
	});
	return textureId;
}

export function shutdown(): void {
	for (const id of querySets.liveIds()) { destroyQuerySet({ id: id }); }
	for (const id of bindGroups.liveIds()) { destroyBindGroup({ id: id }); }
	for (const id of pipelines.liveIds()) { destroyRenderPipeline({ id: id }); }
	for (const id of shaders.liveIds()) { destroyShaderModule({ id: id }); }
	for (const id of samplers.liveIds()) { destroySampler({ id: id }); }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { destroyView({ id: id }); } }
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { destroyTexture({ id: id }); } }
	for (const id of buffers.liveIds()) { destroyBuffer({ id: id }); }
	wgShutdown();
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(querySets);
	reset(bindGroups);
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "webgpu", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocate(buffers);
	const usage = descriptor.usage;
	if (has(usage, (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.MAP_WRITE as int32))) {
		stop("GPUBufferUsage MAP_READ and MAP_WRITE are not ported to wgpu: mapAsync completes in the browser's event loop and cannot block here without ASYNCIFY or JSPI");
	}
	if (has(usage, GPUBufferUsage.STORAGE as int32) && descriptor.size % 4 != 0) {
		stop(`a STORAGE buffer takes a size that is a multiple of 4, got ${descriptor.size}`);
	}
	const native = wgCreateBuffer(descriptor.size, usage, labelText(descriptor.label));
	if (native == null) { stop(`wgpuDeviceCreateBuffer failed for ${labelOf(descriptor.label)}`); }
	const slot: BufferSlot = { id: id, size: descriptor.size, usage: usage, native: native, writtenFrame: -1, writtenEnd: 0 };
	store(buffers, slot);
	return { id: id };
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	wgReleaseBuffer(buffers.slots[index].native);
	buffers.slots[index] = { id: 0 };
	release(buffers, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 {
	return buffers.slots[buffers.slotIndex(buffer.id)].size;
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, GPUBufferUsage.COPY_DST as int32)) {
		stop(`GPUBuffer ${buffer.id} was created without COPY_DST`);
	}
	checkedWriteBuffer(buffer.id, buffers.slots[index].size, offset, bytes);
	if (buffers.slots[index].writtenFrame != frame) {
		buffers.slots[index].writtenFrame = frame;
	} else if (offset < buffers.slots[index].writtenEnd) {
		stop(`writeBuffer at ${offset} on GPUBuffer ${buffer.id} rewrites bytes this frame already wrote, up to ${buffers.slots[index].writtenEnd}`);
	}
	buffers.slots[index].writtenEnd = offset + bytes;
	wgWriteBuffer(buffers.slots[index].native, offset, data[0], bytes);
}

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocate(textures);
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	if (has(descriptor.usage, GPUTextureUsage.STORAGE_BINDING as int32)) { storageFormatOf(descriptor.format, "GPUTextureDescriptor.format"); }
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const mipLevels = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (sampleCount > 1 && has(usage, GPUTextureUsage.STORAGE_BINDING as int32)) { stop("a multisampled texture cannot be STORAGE_BINDING"); }
	if (attachment && info.native == FORMAT_RG11B10_UFLOAT && wgHasFeature(FEATURE_RG11B10_UFLOAT_RENDERABLE) == 0) {
		stop("rg11b10ufloat as RENDER_ATTACHMENT needs the device feature rg11b10ufloat-renderable, which this device was not created with");
	}
	const cube = !volume && layers % 6 == 0 && width == height && has(usage, GPUTextureUsage.TEXTURE_BINDING as int32) && sampleCount == 1;
	const label = labelText(descriptor.label);
	const native = wgCreateTexture(
		width,
		height,
		layers,
		mipLevels,
		volume ? DIMENSION_3D : DIMENSION_2D,
		info.native,
		usage,
		sampleCount,
		label,
	);
	if (native == null) { stop(`wgpuDeviceCreateTexture failed for ${labelOf(descriptor.label)}`); }
	const slot: TextureSlot = {
		id: id,
		width: width,
		height: height,
		format: descriptor.format,
		info: info,
		usage: usage,
		sampleCount: sampleCount,
		mipLevels: mipLevels,
		layers: layers,
		volume: volume,
		cube: cube,
		native: native,
		swapchainView: 0,
	};
	store(textures, slot);
	return { id: id };
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textures.slotIndex(texture.id);
	if (textures.slots[index].swapchainView != 0) {
		stop("the swapchain texture belongs to the platform");
	}
	wgReleaseTexture(textures.slots[index].native);
	textures.slots[index] = { id: 0 };
	release(textures, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 {
	return textures.slots[textures.slotIndex(texture.id)].width;
}

export function textureHeight(texture: GPUTexture): int32 {
	return textures.slots[textures.slotIndex(texture.id)].height;
}

export function textureUsage(texture: GPUTexture): int32 {
	return textures.slots[textures.slotIndex(texture.id)].usage;
}

export function textureFormat(texture: GPUTexture): GPUTextureFormat {
	return textures.slots[textures.slotIndex(texture.id)].format;
}

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	return wgTextureNative(textures.slots[textures.slotIndex(texture.id)].native);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textures.slotIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (!has(textures.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${destination.texture.id}, created without COPY_DST`);
	}
	const info = textures.slots[index].info;
	const mip = destination.mipLevel;
	const mips = textures.slots[index].mipLevels;
	const depth = textures.slots[index].volume && mip >= 0 && mip < mips ? Math.max(1, textures.slots[index].layers >> mip) : textures.slots[index].layers;
	const bytesPerRow = checkedTexelWritePitch(
		textures.slots[index].width,
		textures.slots[index].height,
		mips,
		depth,
		info.bytesPerPixel,
		bytes,
		destination,
		layout,
		size,
	);
	wgWriteTexture(
		textures.slots[index].native,
		data[0],
		bytes,
		layout.offset,
		bytesPerRow,
		layout.rowsPerImage == 0 ? size.height : layout.rowsPerImage,
		mip,
		destination.origin.x,
		destination.origin.y,
		destination.origin.z,
		size.width,
		size.height,
		size.depthOrArrayLayers,
	);
}

function viewDimensionOf(descriptor: GPUTextureViewDescriptor, t: int32): int32 {
	const name = checkedViewDimension(descriptor.dimension, textures.slots[t].volume, textures.slots[t].layers, textures.slots[t].id);
	if (name == "2d") { return VIEW_2D; }
	if (name == "2d-array") { return VIEW_2D_ARRAY; }
	if (name == "cube") { return VIEW_CUBE; }
	if (name == "cube-array") { return VIEW_CUBE_ARRAY; }
	if (name == "3d") { return VIEW_3D; }
	return stopOnMember("GPUTextureViewDescriptor.dimension", name);
}

export function createView(
	texture: GPUTexture,
	descriptor: GPUTextureViewDescriptor,
): GPUTextureView {
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { return { id: textures.slots[t].swapchainView }; }
	const id = allocate(views);
	const info = textures.slots[t].info;
	const label = labelText(descriptor.label);
	const layers = textures.slots[t].layers;
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? textures.slots[t].mipLevels - baseMip : descriptor.mipLevelCount;
	checkedViewMips(textures.slots[t].id, textures.slots[t].mipLevels, baseMip, mipCount);
	const dimension = viewDimensionOf(descriptor, t);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (dimension == VIEW_3D) {
		checkedView3d(baseLayer, layerCount);
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (dimension == VIEW_2D) { layerCount = 1; }
		if (dimension == VIEW_CUBE) { layerCount = 6; }
		if (layerCount == 0) { layerCount = layers - baseLayer; }
		checkedViewLayers(textures.slots[t].id, layers, baseLayer, layerCount);
	}
	if (dimension == VIEW_CUBE || dimension == VIEW_CUBE_ARRAY) {
		checkedCubeView(textures.slots[t].id, textures.slots[t].cube, baseLayer, layerCount);
	}
	const native = wgCreateView(textures.slots[t].native, ASPECT_ALL, dimension, baseMip, mipCount, baseLayer, layerCount, label);
	if (native == null) { stop(`wgpuTextureCreateView failed for ${labelOf(descriptor.label)}`); }
	let binding = NO_VIEW;
	if (has(textures.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
		binding = native;
		if (info.stencil) {
			binding = wgCreateView(textures.slots[t].native, ASPECT_DEPTH_ONLY, dimension, baseMip, mipCount, baseLayer, layerCount, label);
		}
		if (binding == null) {
			stop(`wgpuTextureCreateView (depth aspect) failed for ${labelOf(descriptor.label)}`);
		}
	}
	const slot: ViewSlot = {
		id: id,
		texture: texture.id,
		native: native,
		binding: binding,
		swapchainResolve: NO_VIEW,
		baseMip: baseMip,
		mipCount: mipCount,
		dimension: dimension,
		attachable: mipCount == 1 && layerCount == 1 && (dimension == VIEW_2D || dimension == VIEW_2D_ARRAY || dimension == VIEW_3D),
		swapchain: false,
	};
	store(views, slot);
	return { id: id };
}

export function destroyView(view: GPUTextureView): void {
	const index = views.slotIndex(view.id);
	if (views.slots[index].swapchain) { return; }
	if (views.slots[index].binding != views.slots[index].native) { wgReleaseView(views.slots[index].binding); }
	wgReleaseView(views.slots[index].native);
	views.slots[index] = { id: 0 };
	release(views, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture {
	return { id: views.slots[views.slotIndex(view.id)].texture };
}

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = views.slotIndex(textures.slots[textures.slotIndex(swapchainColor)].swapchainView);
	views.slots[v].native = wgViewFrom(swapchain.renderView);
	views.slots[v].swapchainResolve = wgViewFrom(swapchain.resolveView);
	if (swapchainDepth != 0) {
		if (swapchain.depthStencilView === null) {
			stop("the canvas has a depth format and the swapchain no depth view");
		}
		updateSwapchainTexture(swapchainDepth, swapchain);
		const d = views.slotIndex(textures.slots[textures.slotIndex(swapchainDepth)].swapchainView);
		views.slots[d].native = wgViewFrom(swapchain.depthStencilView);
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
	const magFilter = filterMode(descriptor.magFilter, "GPUSamplerDescriptor.magFilter");
	const minFilter = filterMode(descriptor.minFilter, "GPUSamplerDescriptor.minFilter");
	const mipmapFilter = mipmapFilterMode(descriptor.mipmapFilter);
	const maxLod = samplerMaxLod(descriptor.lodMaxClamp);
	const compare: string = descriptor.compare;
	const native = wgCreateSampler(
		addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"),
		addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"),
		addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW"),
		magFilter,
		minFilter,
		mipmapFilter,
		descriptor.lodMinClamp,
		maxLod,
		compare == "" ? 0 : compareFunction(compare, "GPUSamplerDescriptor.compare"),
		clampedAnisotropy(descriptor.maxAnisotropy),
		labelText(descriptor.label),
	);
	if (native == null) { stop(`wgpuDeviceCreateSampler failed for ${labelOf(descriptor.label)}`); }
	store(samplers, { id: id, native: native });
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplers.slotIndex(sampler.id);
	wgReleaseSampler(samplers.slots[index].native);
	samplers.slots[index] = { id: 0 };
	release(samplers, sampler.id);
}

function entryPoint(name: string): string { return name == "" ? "main" : name; }

function createModule(code: string, label: string | null): Ptr<WgModuleImpl> {
	const module = wgCreateModule(code, labelText(label));
	if (module == null) { stop(`wgpuDeviceCreateShaderModule failed for ${labelOf(label)}`); }
	return module;
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	stopOnUnportedShaderBindings("wgpu", descriptor);
	stopOnUnportedShaderBytecode("wgpu", descriptor);
	const compute = descriptor.computeCode != "";
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const kind = bindingKind(kindName, "wgpu");
		const native: ShaderBinding = {
			binding: descriptor.bindings[i].binding,
			kind: kind,
			visibility: descriptor.bindings[i].visibility,
			bindingType: bindingType(descriptor.bindings[i], kind),
			viewDimension: bindingViewDimension(descriptor.bindings[i].viewDimension),
			storageFormat: kind == BindingKind.StorageTexture ? storageFormatOf(descriptor.bindings[i].storageFormat, "GPUShaderBinding.storageFormat") : 0,
			size: descriptor.bindings[i].size,
		};
		checkBinding(native, descriptor.bindings[i].group);
		if (kind == BindingKind.Uniform) {
			slot.uniforms[slot.uniformCount] = native;
			slot.uniformCount += 1;
		} else {
			slot.resources[slot.resourceCount] = native;
			slot.resourceCount += 1;
		}
	}
	if (compute) {
		slot.compute = createModule(descriptor.computeCode, descriptor.label);
		slot.computeEntry = entryPoint(descriptor.computeEntryPoint);
	} else {
		slot.vertex = createModule(descriptor.vertexCode, descriptor.label);
		slot.fragment = createModule(descriptor.fragmentCode, descriptor.label);
		slot.vertexEntry = entryPoint(descriptor.vertexEntryPoint);
		slot.fragmentEntry = entryPoint(descriptor.fragmentEntryPoint);
	}
	const uniformEntries = new Array<int32>(GPU_MAX_SHADER_BINDINGS * LAYOUT_STRIDE);
	for (let u = 0; u < slot.uniformCount; u++) {
		const binding = slot.uniforms[u];
		packLayoutEntry(uniformEntries, u, binding.binding, binding.visibility, LAYOUT_UNIFORM, 0, VIEW_2D, 0);
	}
	slot.groupLayouts[GPU_UNIFORM_GROUP] = wgCreateLayout(uniformEntries[0], slot.uniformCount, labelText(descriptor.label));
	const resourceEntries = new Array<int32>(GPU_MAX_SHADER_BINDINGS * LAYOUT_STRIDE);
	for (let r = 0; r < slot.resourceCount; r++) {
		const binding = slot.resources[r];
		const layoutKind = match (binding.kind) {
			BindingKind.Texture => LAYOUT_TEXTURE,
			BindingKind.Sampler => LAYOUT_SAMPLER,
			BindingKind.StorageBuffer => LAYOUT_STORAGE_BUFFER,
			BindingKind.StorageTexture => LAYOUT_STORAGE_TEXTURE,
			BindingKind.Uniform => LAYOUT_UNIFORM,
		};
		packLayoutEntry(resourceEntries, r, binding.binding, binding.visibility, layoutKind, binding.bindingType, binding.viewDimension, binding.storageFormat);
	}
	slot.groupLayouts[GPU_RESOURCE_GROUP] = wgCreateLayout(resourceEntries[0], slot.resourceCount, labelText(descriptor.label));
	const uniformLayout = slot.groupLayouts[GPU_UNIFORM_GROUP];
	if (uniformLayout == null || slot.groupLayouts[GPU_RESOURCE_GROUP] == null) {
		stop(`wgpuDeviceCreateBindGroupLayout failed for ${labelOf(descriptor.label)}`);
	}
	slot.id = id;
	slot.readsInstanceIndex = descriptor.readsInstanceIndex;
	slot.readsVertexIndex = descriptor.readsVertexIndex;
	store(shaders, slot);
	return { id: slot.id };
}

function packLayoutEntry(
	entries: int32[],
	index: int32,
	binding: int32,
	visibility: int32,
	kind: int32,
	bindingType: int32,
	viewDimension: int32,
	storageFormat: int32,
): void {
	const at = index * LAYOUT_STRIDE;
	entries[at] = binding;
	entries[at + 1] = visibility;
	entries[at + 2] = kind;
	entries[at + 3] = bindingType;
	entries[at + 4] = viewDimension;
	entries[at + 5] = storageFormat;
}

@noinline function checkBinding(native: ShaderBinding, group: int32): void {
	const uniform = native.kind == BindingKind.Uniform;
	const kind = native.kind.toString();
	const limit = uniform ? MAX_UNIFORM_WGSL_BINDING : MAX_RESOURCE_WGSL_BINDING;
	if (native.binding < 0 || native.binding >= limit) {
		const last = limit - 1;
		const binding = native.binding;
		stop(`shader binding ${binding} is outside the WGSL group ${group} range 0..${last}`);
	}
	const writable = (native.kind == BindingKind.StorageBuffer && native.bindingType == BUFFER_STORAGE)
		|| (native.kind == BindingKind.StorageTexture && native.bindingType != ACCESS_READ_ONLY);
	if (writable && (native.visibility & (GPUShaderStage.VERTEX as int32)) != 0) {
		stop(`shader binding ${native.binding} is writable storage in the vertex stage, which WebGPU does not allow`);
	}
	if (native.kind == BindingKind.StorageTexture && (native.viewDimension == VIEW_CUBE || native.viewDimension == VIEW_CUBE_ARRAY)) {
		stop(`shader binding ${native.binding} is a storage texture with a cube viewDimension, which WebGPU does not allow`);
	}
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaders.slotIndex(module.id);
	wgReleaseModule(shaders.slots[index].vertex);
	wgReleaseModule(shaders.slots[index].fragment);
	wgReleaseModule(shaders.slots[index].compute);
	wgReleaseLayout(shaders.slots[index].groupLayouts[GPU_UNIFORM_GROUP]);
	wgReleaseLayout(shaders.slots[index].groupLayouts[GPU_RESOURCE_GROUP]);
	shaders.slots[index] = { id: 0 };
	release(shaders, module.id);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocate(pipelines);
	const s = shaders.slotIndex(descriptor.vertex.module.id);
	checkedRenderModule(shaders.slots[s].compute != null);
	const state = new Array<int32>(PL_SIZE);
	let depthBias: float64[2] = [0, 0];
	const topology = primitiveTopology(descriptor.primitive.topology);
	const stripIndexFormat = stripIndexFormatOf(descriptor.primitive);
	state[PL_BUFFER_COUNT] = describeVertexBuffers(descriptor, state);
	const depthFormat: string = descriptor.depthStencil.format;
	if (depthFormat != "") {
		const info = formatInfo(descriptor.depthStencil.format, "depthStencil.format");
		if (!info.depth) { stopOnMember("depthStencil.format", depthFormat); }
		const ds = descriptor.depthStencil;
		state[PL_DEPTH_FORMAT] = info.native;
		state[PL_DEPTH_WRITE] = ds.depthWriteEnabled ? 1 : 0;
		state[PL_DEPTH_COMPARE] = compareFunction(ds.depthCompare, "depthStencil.depthCompare");
		state[PL_STENCIL_READ_MASK] = (ds.stencilReadMask == 0 ? STENCIL_MASK_ALL : ds.stencilReadMask) as int32;
		state[PL_STENCIL_WRITE_MASK] = (ds.stencilWriteMask == 0 ? STENCIL_MASK_ALL : ds.stencilWriteMask) as int32;
		state[PL_DEPTH_BIAS] = ds.depthBias;
		depthBias[0] = ds.depthBiasSlopeScale;
		depthBias[1] = ds.depthBiasClamp;
		packStencilFace(state, PL_STENCIL_FRONT, ds.stencilFront, "depthStencil.stencilFront");
		packStencilFace(state, PL_STENCIL_BACK, ds.stencilBack, "depthStencil.stencilBack");
	}
	state[PL_TARGET_COUNT] = describeColorTargets(descriptor, state);
	state[PL_TOPOLOGY] = topology;
	state[PL_STRIP_INDEX_FORMAT] = stripIndexFormat;
	state[PL_CULL_MODE] = cullMode(descriptor.primitive.cullMode);
	state[PL_FRONT_FACE] = frontFace(descriptor.primitive.frontFace);
	state[PL_SAMPLE_COUNT] = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	const native = wgCreatePipeline(
		shaders.slots[s].vertex,
		shaders.slots[s].vertexEntry,
		shaders.slots[s].fragment,
		shaders.slots[s].fragmentEntry,
		shaders.slots[s].groupLayouts[GPU_UNIFORM_GROUP],
		shaders.slots[s].groupLayouts[GPU_RESOURCE_GROUP],
		state[0],
		depthBias[0],
		labelText(descriptor.label),
	);
	if (native == null) {
		stop(`wgpuDeviceCreateRenderPipeline failed for ${labelOf(descriptor.label)}`);
	}
	const slot: PipelineSlot = {
		id: id,
		shader: descriptor.vertex.module.id,
		label: descriptor.label,
		readsInstanceIndex: shaders.slots[s].readsInstanceIndex,
		readsVertexIndex: shaders.slots[s].readsVertexIndex,
		native: native,
		stripIndexFormat: stripIndexFormat,
		strip: topology == TOPOLOGY_LINE_STRIP || topology == TOPOLOGY_TRIANGLE_STRIP,
	};
	store(pipelines, slot);
	return { id: slot.id };
}

function packStencilFace(state: int32[], at: int32, face: GPUStencilFaceState, member: string): void {
	state[at] = compareFunction(face.compare, `${member}.compare`);
	state[at + 1] = stencilOperation(face.failOp, `${member}.failOp`);
	state[at + 2] = stencilOperation(face.depthFailOp, `${member}.depthFailOp`);
	state[at + 3] = stencilOperation(face.passOp, `${member}.passOp`);
}

function stripIndexFormatOf(state: GPUPrimitiveState): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return 0; }
	return indexFormat(state.stripIndexFormat);
}

function describeVertexBuffers(descriptor: GPURenderPipelineDescriptor, state: int32[]): int32 {
	let count = 0;
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stride = descriptor.vertex.buffers[b].arrayStride;
		let used = stride != 0;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format != "") { used = true; }
		}
		if (!used) { continue; }
		const at = PL_BUFFERS + b * PL_BUFFER_STRIDE;
		state[at] = stride;
		state[at + 1] = stepMode(descriptor.vertex.buffers[b].stepMode);
		let attributes = 0;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			const to = at + 3 + attributes * 3;
			state[to] = vertexFormat(format);
			state[to + 1] = descriptor.vertex.buffers[b].attributes[a].offset;
			state[to + 2] = descriptor.vertex.buffers[b].attributes[a].shaderLocation;
			attributes += 1;
		}
		state[at + 2] = attributes;
		count = b + 1;
	}
	return count;
}

function describeColorTargets(descriptor: GPURenderPipelineDescriptor, state: int32[]): int32 {
	let count = 0;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") { continue; }
		const member = `fragment.targets[${i}].format`;
		const info = formatInfo(descriptor.fragment.targets[i].format, member);
		if (info.depth) { stopOnMember(member, format); }
		const float32 = info.native == FORMAT_R32_FLOAT || info.native == FORMAT_RG32_FLOAT || info.native == FORMAT_RGBA32_FLOAT;
		if (float32 && descriptor.fragment.targets[i].blendEnabled && wgHasFeature(FEATURE_FLOAT32_BLENDABLE) == 0) {
			stop(`fragment.targets[${i}] blends a ${format} target, which needs the device feature float32-blendable`);
		}
		const color: GPUBlendComponent = descriptor.fragment.targets[i].blend.color;
		const alpha: GPUBlendComponent = descriptor.fragment.targets[i].blend.alpha;
		const writeMask = descriptor.fragment.targets[i].writeMask;
		const at = PL_TARGETS + i * PL_TARGET_STRIDE;
		state[at] = info.native;
		state[at + 1] = descriptor.fragment.targets[i].blendEnabled ? 1 : 0;
		state[at + 2] = blendOperation(color.operation, "blend.color.operation");
		state[at + 3] = blendFactor(color.srcFactor, "blend.color.srcFactor");
		state[at + 4] = destinationFactor(color.dstFactor, "blend.color.dstFactor");
		state[at + 5] = blendOperation(alpha.operation, "blend.alpha.operation");
		state[at + 6] = blendFactor(alpha.srcFactor, "blend.alpha.srcFactor");
		state[at + 7] = destinationFactor(alpha.dstFactor, "blend.alpha.dstFactor");
		state[at + 9] = writeMask == 0 ? COLOR_WRITE_ALL : writeMask;
		count = i + 1;
	}
	return count;
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	const index = pipelines.slotIndex(pipeline.id);
	if (pipelines.slots[index].compute) {
		wgReleaseComputePipeline(pipelines.slots[index].native);
	} else {
		wgReleasePipeline(pipelines.slots[index].native);
	}
	if (computeBound.pipeline == pipeline.id) { computeBound.pipeline = 0; }
	for (let g = 0; g < 2; g++) {
		const layout = pipelines.slots[index].layouts[g];
		if (layout != 0) {
			layouts.slots[layouts.slotIndex(layout)] = { id: 0 };
			release(layouts, layout);
		}
	}
	if (pass.pipeline == pipeline.id) { pass.pipeline = 0; }
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
	let count = 0;
	let bindings: int32[GPU_MAX_BIND_GROUP_ENTRIES] = [0];
	let entryBuffers: Ptr<WgBufferImpl>[GPU_MAX_BIND_GROUP_ENTRIES] = [NO_BUFFER];
	let ranges: int64[GPU_MAX_BIND_GROUP_ENTRIES * 2] = [0];
	let entryViews: Ptr<WgViewImpl>[GPU_MAX_BIND_GROUP_ENTRIES] = [NO_VIEW];
	let entrySamplers: Ptr<WgSamplerImpl>[GPU_MAX_BIND_GROUP_ENTRIES] = [NO_SAMPLER];
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) {
			continue;
		}
		if (entry.buffer.id != 0) {
			const buffer = buffers.slots[buffers.slotIndex(entry.buffer.id)].native;
			if (group == GPU_UNIFORM_GROUP) {
				const size = uniformEntrySize(shader, entry);
				entryBuffers[count] = buffer;
				ranges[count * 2] = entry.offset;
				ranges[count * 2 + 1] = size;
				slot.dynamicCount += 1;
			} else {
				const size = storageEntrySize(shader, group, entry);
				entryBuffers[count] = buffer;
				ranges[count * 2] = entry.offset;
				ranges[count * 2 + 1] = size;
			}
		} else if (entry.textureView.id != 0) {
			const v = views.slotIndex(entry.textureView.id);
			const r = resourceIndex(shader, group, entry.binding);
			if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.StorageTexture) {
				entryViews[count] = storageView(shader, r, v, entry.binding);
			} else {
				checkResource(shader, entry.binding, BindingKind.Texture, group);
				const view = views.slots[v].binding;
				checkedSampledView(entry.binding, view != null);
				entryViews[count] = view;
			}
		} else {
			checkResource(shader, entry.binding, BindingKind.Sampler, group);
			const sampler = samplers.slots[samplers.slotIndex(entry.sampler.id)].native;
			entrySamplers[count] = sampler;
		}
		bindings[count] = entry.binding;
		count += 1;
	}
	slot.native = wgCreateBindGroup(
		shaders.slots[shader].groupLayouts[group],
		count,
		bindings[0],
		entryBuffers[0],
		ranges[0],
		entryViews[0],
		entrySamplers[0],
		labelText(descriptor.label),
	);
	if (slot.native == null) {
		stop(`wgpuDeviceCreateBindGroup failed for ${labelOf(descriptor.label)}`);
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: slot.id };
}

function uniformEntrySize(shader: int32, entry: GPUBindGroupEntry): int64 {
	const b = buffers.slotIndex(entry.buffer.id);
	const isUniform = has(buffers.slots[b].usage, GPUBufferUsage.UNIFORM as int32);
	for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
		const binding = shaders.slots[shader].uniforms[u];
		if (addressesBinding(GPU_UNIFORM_GROUP, entry.binding, binding.binding, BindingKind.Uniform)) {
			checkedUniformEntry(entry, isUniform, buffers.slots[b].size, binding.size, uniformAlignment as int64);
			return entry.size == 0 ? binding.size as int64 : entry.size;
		}
	}
	stop(`bind group entry ${entry.binding} (Uniform) is not a binding of the pipeline's shader`);
}

function resourceIndex(shader: int32, group: int32, binding: int32): int32 {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		const resource = shaders.slots[shader].resources[r];
		if (addressesBinding(group, binding, resource.binding, resource.kind)) { return r; }
	}
	return -1;
}

function storageEntrySize(shader: int32, group: int32, entry: GPUBindGroupEntry): int64 {
	const b = buffers.slotIndex(entry.buffer.id);
	const r = resourceIndex(shader, group, entry.binding);
	if (r < 0 || shaders.slots[shader].resources[r].kind != BindingKind.StorageBuffer) {
		stop(`bind group ${GPU_RESOURCE_GROUP} entry ${entry.binding} (buffer) is not a storage buffer binding of the pipeline's shader`);
	}
	checkedStorageEntry(
		entry,
		has(buffers.slots[b].usage, GPUBufferUsage.STORAGE as int32),
		buffers.slots[b].size,
		cachedLimits().minStorageBufferOffsetAlignment as int64,
		cachedLimits().maxStorageBufferBindingSize,
	);
	return entryBytes(entry, buffers.slots[b].size);
}

function storageView(shader: int32, r: int32, v: int32, binding: int32): Ptr<WgViewImpl> {
	const t = textures.slotIndex(views.slots[v].texture);
	checkedStorageView(binding, has(textures.slots[t].usage, GPUTextureUsage.STORAGE_BINDING as int32), views.slots[v].mipCount);
	const expected = shaders.slots[shader].resources[r];
	if (views.slots[v].dimension != expected.viewDimension) {
		stop(`bind group entry ${binding}: the view dimension ${views.slots[v].dimension} differs from the shader's ${expected.viewDimension}`);
	}
	if (textures.slots[t].info.native != expected.storageFormat) {
		stop(`bind group entry ${binding}: the texture format '${textures.slots[t].format}' differs from the shader's storage format`);
	}
	return views.slots[v].native;
}

@noinline function checkResource(shader: int32, binding: int32, kind: BindingKind, group: int32): void {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		const resource = shaders.slots[shader].resources[r];
		if (addressesBinding(group, binding, resource.binding, resource.kind) && resource.kind == kind) { return; }
	}
	const name = kind.toString();
	stop(`bind group ${group} entry ${binding} (${name}) is not a binding of the pipeline shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroups.slotIndex(bindGroup.id);
	wgReleaseBindGroup(bindGroups.slots[index].native);
	bindGroups.slots[index] = { id: 0 };
	release(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder {
	if (wgBeginEncoder() == 0) { stop("wgpuDeviceCreateCommandEncoder failed"); }
	return { id: 1 };
}

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (wgFinish() == 0) { stop("wgpuCommandEncoderFinish failed"); }
	return { id: 1 };
}

export function submit(commandBuffer: GPUCommandBuffer): void {
	wgSubmit();
	frame += 1;
}

export function beginRenderPass(
	encoder: GPUCommandEncoder,
	descriptor: GPURenderPassDescriptor,
): GPURenderPassEncoder {
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	const occlusionId = descriptor.occlusionQuerySet.id;
	if (occlusionId != 0) { checkedOcclusionSetKind(querySets.slots[querySets.slotIndex(occlusionId)].timestamp); }
	pass.width = 0;
	pass.height = 0;
	let count = 0;
	let ints: int32[PASS_SIZE] = [0];
	let reals: float64[PASS_DEPTH_CLEAR + 1] = [0];
	let colorViews: Ptr<WgViewImpl>[GPU_MAX_COLOR_ATTACHMENTS] = [NO_VIEW, NO_VIEW, NO_VIEW, NO_VIEW];
	let resolveViews: Ptr<WgViewImpl>[GPU_MAX_COLOR_ATTACHMENTS] = [NO_VIEW, NO_VIEW, NO_VIEW, NO_VIEW];
	let depthNative = NO_VIEW;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = descriptor.colorAttachments[i];
		const op = PASS_COLOR_OPS + i * PASS_COLOR_OP_STRIDE;
		ints[op + 2] = -1;
		if (attachment.view.id == 0) { continue; }
		const v = views.slotIndex(attachment.view.id);
		checkColorAttachment(i, views.slots[v].texture);
		if (!views.slots[v].attachable) { checkedSingleSubresource(attachmentMember(i, "view"), false); }
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		const slice = attachment.depthSlice;
		if (views.slots[v].dimension == VIEW_3D) {
			const slices = Math.max(1, textures.slots[textures.slotIndex(views.slots[v].texture)].layers >> views.slots[v].baseMip);
			checkedDepthSlice(i, slice, slices, views.slots[v].baseMip, views.slots[v].texture);
		} else {
			checkedNoDepthSlice(i, slice);
		}
		let resolve = views.slots[v].swapchainResolve;
		if (attachment.resolveTarget.id != 0) {
			resolve = checkResolve(i, views.slots[v].texture, attachment.resolveTarget.id);
		}
		const color = attachment.clearValue;
		colorViews[i] = views.slots[v].native;
		resolveViews[i] = resolve;
		ints[op] = loadOp(attachment.loadOp, i, "loadOp");
		ints[op + 1] = storeOp(attachment.storeOp, i, "storeOp");
		ints[op + 2] = views.slots[v].dimension == VIEW_3D ? slice : -1;
		reals[i * 4] = color.r;
		reals[i * 4 + 1] = color.g;
		reals[i * 4 + 2] = color.b;
		reals[i * 4 + 3] = color.a;
		count = i + 1;
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	if (depthView != 0) {
		const v = views.slotIndex(depthView);
		const t = textures.slotIndex(views.slots[v].texture);
		if (!views.slots[v].attachable) { stop("depthStencilAttachment.view spans several mips or layers: a render attachment is one mip of one layer"); }
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		const info = textures.slots[t].info;
		if (!info.depth || !has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT");
		}
		const depth = descriptor.depthStencilAttachment;
		depthNative = views.slots[v].native;
		ints[PASS_DEPTH_LOAD] = loadOp(depth.depthLoadOp, -1, "depthLoadOp");
		ints[PASS_DEPTH_STORE] = storeOp(depth.depthStoreOp, -1, "depthStoreOp");
		ints[PASS_DEPTH_STENCIL] = info.stencil ? 1 : 0;
		reals[PASS_DEPTH_CLEAR] = depth.depthClearValue;
	}
	if (count == 0 && depthView == 0) { stop("beginRenderPass without an attachment"); }
	const writes = descriptor.timestampWrites;
	ints[PASS_COLOR_COUNT] = count;
	ints[PASS_WIDTH] = pass.width;
	ints[PASS_HEIGHT] = pass.height;
	ints[PASS_TIMESTAMP_BEGIN] = writes.beginningOfPassWriteIndex;
	ints[PASS_TIMESTAMP_END] = writes.endOfPassWriteIndex;
	if (wgBeginPass(
		colorViews[0],
		resolveViews[0],
		depthNative,
		ints[0],
		reals[0],
		labelText(descriptor.label),
		occlusionId == 0 ? NO_QUERY_SET : querySets.slots[querySets.slotIndex(occlusionId)].native,
		timestampNative(writes),
	) == 0) {
		stop("wgpuCommandEncoderBeginRenderPass failed");
	}
	pass.timestampSet = writes.querySet.id;
	pass.timestampEnd = writes.endOfPassWriteIndex;
	markTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	pass.pipeline = 0;
	pass.indexFormat = 0;
	return { id: 1 };
}

function passExtent(texture: uint32, baseMip: int32): void {
	const t = textures.slotIndex(texture);
	const width = Math.max(1, textures.slots[t].width >> baseMip);
	const height = Math.max(1, textures.slots[t].height >> baseMip);
	checkedPassExtent(pass.width, pass.height, width, height);
	pass.width = width;
	pass.height = height;
}

@noinline function checkColorAttachment(attachment: int32, texture: uint32): void {
	const t = textures.slotIndex(texture);
	const attachable = has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (textures.slots[t].info.depth || !attachable) {
		stop(`colorAttachments[${attachment}].view is not a color RENDER_ATTACHMENT`);
	}
}

@noinline function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): Ptr<WgViewImpl> {
	const r = views.slotIndex(resolveId);
	const resolveTexture = textures.slotIndex(views.slots[r].texture);
	const color = textures.slotIndex(colorTexture);
	checkedResolveTarget(
		attachment,
		textures.slots[color].sampleCount,
		textures.slots[color].width,
		textures.slots[color].height,
		Math.max(1, textures.slots[resolveTexture].width >> views.slots[r].baseMip),
		Math.max(1, textures.slots[resolveTexture].height >> views.slots[r].baseMip),
	);
	if (textures.slots[resolveTexture].sampleCount != 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample view`);
	}
	checkColorAttachment(attachment, views.slots[r].texture);
	if (!views.slots[r].attachable) { checkedSingleSubresource(attachmentMember(attachment, "resolveTarget"), false); }
	return views.slots[r].native;
}

export function endPass(): void {
	wgEndPass();
	markTimestamp(pass.timestampSet, pass.timestampEnd);
}

@inline export function setPipeline(pipeline: GPURenderPipeline): void {
	const p = pipelines.slotIndex(pipeline.id);
	checkedRenderPassPipeline(pipeline.id, pipelines.slots[p].compute);
	wgSetPipeline(pipelines.slots[p].native);
	pass.pipeline = pipeline.id;
}

@inline export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) {
		stopOnMember("setVertexBuffer slot", `${slot}`);
	}
	wgSetVertexBuffer(slot, buffers.slots[buffers.slotIndex(buffer.id)].native, offset);
}

@inline export function setIndexBuffer(
	buffer: GPUBuffer,
	format: GPUIndexFormat,
	offset: int64,
): void {
	pass.indexFormat = indexFormat(format);
	wgSetIndexBuffer(buffers.slots[buffers.slotIndex(buffer.id)].native, pass.indexFormat, offset);
}

export function setBindGroup(
	index: int32,
	bindGroup: GPUBindGroup,
	dynamicOffsets: Readonly<Span<uint32>>,
): void {
	stageBindGroup(index, bindGroup, dynamicOffsets, false);
}

function stageBindGroup(
	index: int32,
	bindGroup: GPUBindGroup,
	dynamicOffsets: Readonly<Span<uint32>>,
	compute: boolean,
): void {
	let offsets: uint32[GPU_MAX_BIND_GROUP_ENTRIES] = [0];
	if (bindGroup.id == 0) {
		if (compute) {
			wgSetComputeBindGroup(index, NO_BIND_GROUP, 0, offsets[0]);
			computeBound.groupMask &= ~(1 << index);
		} else {
			wgSetBindGroup(index, NO_BIND_GROUP, 0, offsets[0]);
		}
		return;
	}
	const g = bindGroups.slotIndex(bindGroup.id);
	checkedBindGroupSet(index, bindGroups.slots[g].group, bindGroups.slots[g].dynamicCount, dynamicOffsets, uniformAlignment as uint32);
	for (let i = 0; i < bindGroups.slots[g].dynamicCount; i++) { offsets[i] = dynamicOffsets[i]; }
	if (compute) {
		wgSetComputeBindGroup(index, bindGroups.slots[g].native, bindGroups.slots[g].dynamicCount, offsets[0]);
		computeBound.groupMask |= 1 << index;
	} else {
		wgSetBindGroup(index, bindGroups.slots[g].native, bindGroups.slots[g].dynamicCount, offsets[0]);
	}
}

@inline export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	wgSetScissorRect(x, y, width, height);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	wgSetViewport(x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	wgSetBlendConstant(color.r, color.g, color.b, color.a);
}

export function setStencilReference(reference: uint32): void {
	wgSetStencilReference(reference);
}

function checkDrawOffsets(call: string, vertexMember: string, vertexOffset: int32, firstInstance: int32): void {
	if (vertexOffset == 0 && firstInstance == 0) { return; }
	const p = pipelines.slotIndex(pass.pipeline);
	if (firstInstance != 0 && pipelines.slots[p].readsInstanceIndex) { stop(firstInstanceRefusal(call, labelOf(pipelines.slots[p].label), firstInstance)); }
	if (vertexOffset != 0 && pipelines.slots[p].readsVertexIndex) {
		stop(vertexOffsetRefusal(call, labelOf(pipelines.slots[p].label), vertexMember, vertexOffset));
	}
}

@inline export function draw(
	vertexCount: int32,
	instanceCount: int32,
	firstVertex: int32,
	firstInstance: int32,
): void {
	checkDrawOffsets("draw", "firstVertex", firstVertex, firstInstance);
	wgDraw(vertexCount, instanceCount, firstVertex, firstInstance);
}

@inline export function drawIndexed(
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	checkDrawOffsets("drawIndexed", "baseVertex", baseVertex, firstInstance);
	const strip = pipelines.slots[pipelines.slotIndex(pass.pipeline)].stripIndexFormat;
	checkedStripDraw(pipelines.slots[pipelines.slotIndex(pass.pipeline)].strip, strip == pass.indexFormat);
	wgDrawIndexed(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	const index = textures.slotIndex(info.texture.id);
	if (!has(textures.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures.slots[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	if (textures.slots[index].swapchainView != 0) { stop(`${member}: the swapchain texture belongs to the platform`); }
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

function texelFormatOf(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): FormatInfo {
	const info = textures.slots[index].info;
	if (info.depth) {
		checkedDepthTexelCopy(member, textures.slots[index].id, textures.slots[index].format, info.stencil, writes, textures.slots[index].width, textures.slots[index].height, copy.mipLevel, size);
	}
	return info;
}

@noinline function checkedBufferLayout(member: string, bytesPerPixel: int32, slot: int32, info: GPUTexelCopyBufferInfo, size: GPUExtent3D): int32 {
	if (info.offset % 4 != 0) { stop(`${member}.offset ${info.offset} is not a multiple of 4`); }
	return checkedTexelBufferLayout(member, bytesPerPixel, buffers.slots[slot].size, info, size);
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedBufferCopy(source.id, buffers.slots[from].size, sourceOffset, destination.id, buffers.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	wgCopyBufferToBuffer(buffers.slots[from].native, sourceOffset, buffers.slots[to].native, destinationOffset, size);
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const info = texelFormatOf(to, "copyBufferToTexture destination", true, destination, size);
	const bytesPerRow = checkedBufferLayout("copyBufferToTexture source", info.bytesPerPixel, from, source, size);
	wgCopyBufferToTexture(
		buffers.slots[from].native,
		source.offset,
		bytesPerRow,
		source.rowsPerImage == 0 ? size.height : source.rowsPerImage,
		textures.slots[to].native,
		destination.mipLevel,
		destination.origin.x,
		destination.origin.y,
		destination.origin.z,
		size.width,
		size.height,
		size.depthOrArrayLayers,
	);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination.buffer, "copyTextureToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const info = texelFormatOf(from, "copyTextureToBuffer source", false, source, size);
	const bytesPerRow = checkedBufferLayout("copyTextureToBuffer destination", info.bytesPerPixel, to, destination, size);
	wgCopyTextureToBuffer(
		textures.slots[from].native,
		source.mipLevel,
		source.origin.x,
		source.origin.y,
		source.origin.z,
		buffers.slots[to].native,
		destination.offset,
		bytesPerRow,
		destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage,
		size.width,
		size.height,
		size.depthOrArrayLayers,
	);
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyTextureToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
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
		textures.slots[from].info.depth,
		textures.slots[from].width,
		textures.slots[from].height,
	);
	wgCopyTextureToTexture(
		textures.slots[from].native,
		source.mipLevel,
		source.origin.x,
		source.origin.y,
		source.origin.z,
		textures.slots[to].native,
		destination.mipLevel,
		destination.origin.x,
		destination.origin.y,
		destination.origin.z,
		size.width,
		size.height,
		size.depthOrArrayLayers,
	);
}

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	stop("mapAsync is not ported to wgpu: wgpuBufferMapAsync completes in the browser's event loop, and the build has neither ASYNCIFY nor JSPI to block on it");
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	stop("getMappedRange is not ported to wgpu: it needs mapAsync");
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	stop("writeMappedRange is not ported to wgpu: it needs mapAsync");
}

export function unmap(buffer: GPUBuffer): void {
	stop("unmap is not ported to wgpu: it needs mapAsync");
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const s = shaders.slotIndex(descriptor.compute.module.id);
	const entry = entryPoint(descriptor.compute.entryPoint);
	checkedComputeModule(shaders.slots[s].compute != null, entry, shaders.slots[s].computeEntry);
	const id = allocate(pipelines);
	const native = wgCreateComputePipeline(
		shaders.slots[s].compute,
		shaders.slots[s].computeEntry,
		shaders.slots[s].groupLayouts[GPU_UNIFORM_GROUP],
		shaders.slots[s].groupLayouts[GPU_RESOURCE_GROUP],
		labelText(descriptor.label),
	);
	if (native == null) { stop(`wgpuDeviceCreateComputePipeline failed for ${labelOf(descriptor.label)}`); }
	const slot: PipelineSlot = { id: id, shader: descriptor.compute.module.id, native: native, compute: true };
	store(pipelines, slot);
	return { id: id };
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	checkTimestampWrites("GPUComputePassDescriptor.timestampWrites", descriptor.timestampWrites);
	const writes = descriptor.timestampWrites;
	if (wgBeginComputePass(
		labelText(descriptor.label),
		timestampNative(writes),
		writes.beginningOfPassWriteIndex,
		writes.endOfPassWriteIndex,
	) == 0) {
		stop("wgpuCommandEncoderBeginComputePass failed");
	}
	computeBound.timestampSet = writes.querySet.id;
	computeBound.timestampEnd = writes.endOfPassWriteIndex;
	markTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	computeBound.pipeline = 0;
	computeBound.groupMask = 0;
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	const p = pipelines.slotIndex(pipeline.id);
	checkedComputePipeline(pipeline.id, pipelines.slots[p].compute);
	wgSetComputePipeline(pipelines.slots[p].native);
	computeBound.pipeline = pipeline.id;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	stageBindGroup(index, bindGroup, dynamicOffsets, true);
}

@noinline function checkDispatch(call: string): void {
	const s = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(computeBound.pipeline)].shader);
	if (shaders.slots[s].uniformCount > 0 && (computeBound.groupMask & 1) == 0) {
		stop(`${call}: the compute pipeline reads bind group ${GPU_UNIFORM_GROUP}, which is not set`);
	}
	if (shaders.slots[s].resourceCount > 0 && (computeBound.groupMask & 2) == 0) {
		stop(`${call}: the compute pipeline reads bind group ${GPU_RESOURCE_GROUP}, which is not set`);
	}
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	checkDispatch("dispatchWorkgroups");
	wgDispatch(x, y, z);
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	checkDispatch("dispatchWorkgroupsIndirect");
	const b = buffers.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, buffers.slots[b].usage, buffers.slots[b].size, offset);
	wgDispatchIndirect(buffers.slots[b].native, offset);
}

export function endComputePass(): void {
	wgEndComputePass();
	markTimestamp(computeBound.timestampSet, computeBound.timestampEnd);
	computeBound.pipeline = 0;
}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	const timestamp = kind == "timestamp";
	if (timestamp && wgHasFeature(FEATURE_TIMESTAMP_QUERY) == 0) {
		stop("this device has no timestamp queries: features().has('timestamp-query') is false (the window must request the feature when it creates the WGPUDevice)");
	}
	const id = allocate(querySets);
	const native = wgCreateQuerySet(timestamp ? 1 : 0, descriptor.count, labelText(descriptor.label));
	if (native == null) { stop(`wgpuDeviceCreateQuerySet failed for ${labelOf(descriptor.label)}`); }
	const slot: QuerySetSlot = {
		id: id,
		timestamp: timestamp,
		count: descriptor.count,
		native: native,
		state: new Array(descriptor.count),
		usedPass: new Array(descriptor.count),
	};
	store(querySets, slot);
	return { id: id };
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySets.slotIndex(querySet.id);
	wgReleaseQuerySet(querySets.slots[index].native);
	querySets.slots[index] = { id: 0 };
	release(querySets, querySet.id);
}

function timestampNative(writes: GPUPassTimestampWrites): Ptr<WgQuerySetImpl> {
	if (writes.querySet.id == 0) { return NO_QUERY_SET; }
	return querySets.slots[querySets.slotIndex(writes.querySet.id)].native;
}

function markTimestamp(querySet: uint32, queryIndex: int32): void {
	if (querySet == 0 || queryIndex < 0) { return; }
	querySets.slots[querySets.slotIndex(querySet)].state[queryIndex] = QUERY_WRITTEN;
}

@noinline function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySets.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets.slots[q].timestamp, querySets.slots[q].count);
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
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
		if (state == QUERY_UNWRITTEN) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QUERY_OPEN) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	wgResolveQuerySet(querySets.slots[q].native, firstQuery, queryCount, buffers.slots[b].native, destinationOffset);
}

export function beginOcclusionQuery(queryIndex: int32): void {
	const q = querySets.slotIndex(occlusionSetId());
	checkedOcclusionRange(queryIndex, querySets.slots[q].count);
	checkedOcclusionReuse(queryIndex, querySets.slots[q].usedPass[queryIndex]);
	querySets.slots[q].usedPass[queryIndex] = passSerial();
	querySets.slots[q].state[queryIndex] = QUERY_OPEN;
	wgBeginOcclusionQuery(queryIndex);
}

export function endOcclusionQuery(): void {
	wgEndOcclusionQuery();
	querySets.slots[querySets.slotIndex(occlusionSetId())].state[occlusionQueryIndex()] = QUERY_WRITTEN;
}

function limitOf(which: int32): int32 { return wgLimit(which) as int32; }

export function limits(): GPUSupportedLimits {
	return {
		maxTextureDimension1D: limitOf(LIMIT_TEXTURE_DIMENSION_1D),
		maxTextureDimension2D: limitOf(LIMIT_TEXTURE_DIMENSION_2D),
		maxTextureDimension3D: limitOf(LIMIT_TEXTURE_DIMENSION_3D),
		maxTextureArrayLayers: limitOf(LIMIT_TEXTURE_ARRAY_LAYERS),
		maxBindGroups: Math.min(limitOf(LIMIT_BIND_GROUPS), GPU_RESOURCE_GROUP + 1),
		maxSampledTexturesPerShaderStage: Math.min(limitOf(LIMIT_SAMPLED_TEXTURES), GPU_MAX_BIND_GROUP_ENTRIES),
		maxSamplersPerShaderStage: Math.min(limitOf(LIMIT_SAMPLERS), GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageBuffersPerShaderStage: Math.min(limitOf(LIMIT_STORAGE_BUFFERS), GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageTexturesPerShaderStage: Math.min(limitOf(LIMIT_STORAGE_TEXTURES), GPU_MAX_BIND_GROUP_ENTRIES),
		maxUniformBuffersPerShaderStage: Math.min(limitOf(LIMIT_UNIFORM_BUFFERS), GPU_MAX_UNIFORM_BLOCKS),
		maxUniformBufferBindingSize: wgLimit(LIMIT_UNIFORM_BINDING_SIZE),
		maxStorageBufferBindingSize: wgLimit(LIMIT_STORAGE_BINDING_SIZE),
		maxVertexBuffers: Math.min(limitOf(LIMIT_VERTEX_BUFFERS), GPU_MAX_VERTEX_BUFFERS),
		maxVertexAttributes: Math.min(limitOf(LIMIT_VERTEX_ATTRIBUTES), GPU_MAX_VERTEX_ATTRIBUTES),
		maxColorAttachments: Math.min(limitOf(LIMIT_COLOR_ATTACHMENTS), GPU_MAX_COLOR_ATTACHMENTS),
		maxComputeWorkgroupSizeX: limitOf(LIMIT_WORKGROUP_SIZE_X),
		maxComputeWorkgroupSizeY: limitOf(LIMIT_WORKGROUP_SIZE_Y),
		maxComputeWorkgroupSizeZ: limitOf(LIMIT_WORKGROUP_SIZE_Z),
		maxComputeInvocationsPerWorkgroup: limitOf(LIMIT_WORKGROUP_INVOCATIONS),
		maxComputeWorkgroupsPerDimension: limitOf(LIMIT_WORKGROUPS_PER_DIMENSION),
		minUniformBufferOffsetAlignment: limitOf(LIMIT_UNIFORM_ALIGNMENT),
		minStorageBufferOffsetAlignment: limitOf(LIMIT_STORAGE_ALIGNMENT),
	};
}


function featureBits(bits: uint32, native: int32, name: GPUFeatureName): uint32 {
	return wgHasFeature(native) != 0 ? bits | featureBit(name) : bits;
}

struct FeatureEntry {
	native: int32;
	name: GPUFeatureName;
}

const FEATURE_TABLE: FeatureEntry[] = [
	{ native: FEATURE_TIMESTAMP_QUERY, name: "timestamp-query" },
	{ native: FEATURE_TEXTURE_COMPRESSION_BC, name: "texture-compression-bc" },
	{ native: FEATURE_TEXTURE_COMPRESSION_ETC2, name: "texture-compression-etc2" },
	{ native: FEATURE_TEXTURE_COMPRESSION_ASTC, name: "texture-compression-astc" },
	{ native: FEATURE_DEPTH32_FLOAT_STENCIL8, name: "depth32float-stencil8" },
	{ native: FEATURE_DEPTH_CLIP_CONTROL, name: "depth-clip-control" },
	{ native: FEATURE_FLOAT32_FILTERABLE, name: "float32-filterable" },
	{ native: FEATURE_FLOAT32_BLENDABLE, name: "float32-blendable" },
	{ native: FEATURE_RG11B10_UFLOAT_RENDERABLE, name: "rg11b10ufloat-renderable" },
	{ native: FEATURE_BGRA8_UNORM_STORAGE, name: "bgra8unorm-storage" },
	{ native: FEATURE_INDIRECT_FIRST_INSTANCE, name: "indirect-first-instance" },
	{ native: FEATURE_SHADER_F16, name: "shader-f16" },
	{ native: FEATURE_DUAL_SOURCE_BLENDING, name: "dual-source-blending" },
];

export function features(): GPUSupportedFeatures {
	let bits: uint32 = 0;
	for (const entry of FEATURE_TABLE) { bits = featureBits(bits, entry.native, entry.name); }
	return { bits: bits };
}

export function pushDebugGroup(label: string): void {
	wgPushDebugGroup(label);
}

export function popDebugGroup(): void {
	wgPopDebugGroup();
}

export function insertDebugMarker(label: string): void {
	wgInsertDebugMarker(label);
}
