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
	checkedTexelBufferLayout,
	checkedDepthTexelCopy,
	checkedTexelCopyRegion,
	checkedTexelWritePitch,
	featureBit,
	stopOnUnportedShaderBindings,
} from "../types.ms";
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
	wgCopyBufferToBuffer,
	wgCopyBufferToTexture,
	wgCopyTextureToBuffer,
	wgCopyTextureToTexture,
	wgBeginPass,
	wgBindEntry,
	wgColorAttachment,
	wgColorTarget,
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
	wgDepthAttachment,
	wgDepthStencil,
	wgDispatch,
	wgDispatchIndirect,
	wgDraw,
	wgDrawIndexed,
	wgDynamicOffset,
	wgEndComputePass,
	wgEndOcclusionQuery,
	wgEndPass,
	wgFinish,
	wgInsertDebugMarker,
	wgLayoutEntry,
	wgLimit,
	wgMaxTextureDimension2D,
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
	wgStencilFace,
	wgSubmit,
	wgTextureNative,
	wgVertexAttribute,
	wgVertexBuffer,
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

const MAX_QUERY_COUNT = 4096;
const RESOLVE_OFFSET_ALIGNMENT = 256;
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
const DEFAULT_LOD_MAX_CLAMP = 32.0;
const STENCIL_MASK_ALL: uint32 = 0xFFFFFFFF;

const STAGE_VERTEX = 0x1;
const STAGE_FRAGMENT = 0x2;
const STAGE_COMPUTE = 0x4;
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
const COMPARE_ALWAYS = 8;
const BLEND_ZERO = 1;
const BLEND_ONE = 2;
const ADDRESS_CLAMP = 1;
const ADDRESS_REPEAT = 2;
const ADDRESS_MIRROR = 3;
const FILTER_NEAREST = 1;
const FILTER_LINEAR = 2;
const INDEX_UINT16 = 1;
const INDEX_UINT32 = 2;
const COLOR_WRITE_ALL = 0xF;

const NO_BUFFER = null as unknown as Ptr<WgBufferImpl>;
const NO_TEXTURE = null as unknown as Ptr<WgTextureImpl>;
const NO_VIEW = null as unknown as Ptr<WgViewImpl>;
const NO_SAMPLER = null as unknown as Ptr<WgSamplerImpl>;
const NO_BIND_GROUP = null as unknown as Ptr<WgBindGroupImpl>;
const NO_QUERY_SET = null as unknown as Ptr<WgQuerySetImpl>;

enum BindingKind {
	Uniform,
	Texture,
	Sampler,
	StorageBuffer,
	StorageTexture,
}

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
	id: uint32;
	shader: uint32;
	native: Ptr<WgPipelineImpl>;
	stripIndexFormat: int32;
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
	active: boolean;
	groupBase: int32;
	timestampSet: uint32;
	timestampEnd: int32;
	occlusionSet: uint32;
	occlusionOpen: boolean;
	occlusionIndex: int32;
	width: int32;
	height: int32;
	pipeline: uint32;
	indexFormat: int32;
}

struct ComputeState {
	active: boolean;
	groupBase: int32;
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
let encoding = false;
let pass: PassState = { active: false, timestampEnd: -1 };
let computeBound: ComputeState = { active: false, timestampEnd: -1 };
let passSerial: int64 = 0;
let groupDepth: int32 = 0;
let deviceLimits: GPUSupportedLimits = { maxTextureDimension1D: 0 };
let uniformAlignment = 256;
let maxTextureDimension = 0;
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

function stop(message: string): never {
	console.log(`webgpu wgpu: ${message}`);
	unreachable;
}

function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu wgpu: ${member} '${value}' is not supported`);
	unreachable;
}

function stopOnFormat(member: string, value: string): FormatInfo {
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
		"never" => 1,
		"less" => 2,
		"equal" => 3,
		"less-equal" => 4,
		"greater" => 5,
		"not-equal" => 6,
		"greater-equal" => 7,
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
		"src" => 3,
		"one-minus-src" => 4,
		"src-alpha" => 5,
		"one-minus-src-alpha" => 6,
		"dst" => 7,
		"one-minus-dst" => 8,
		"dst-alpha" => 9,
		"one-minus-dst-alpha" => 10,
		"src-alpha-saturated" => 11,
		"constant" => 12,
		"one-minus-constant" => 13,
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
		"" | "add" => 1,
		"subtract" => 2,
		"reverse-subtract" => 3,
		"min" => 4,
		"max" => 5,
		_ => stopOnMember(member, operation),
	};
}

function vertexFormat(format: string): int32 {
	return match (format) {
		"float32" => 0x1C,
		"float32x2" => 0x1D,
		"float32x3" => 0x1E,
		"float32x4" => 0x1F,
		"uint32" => 0x20,
		"uint32x2" => 0x21,
		"uint32x3" => 0x22,
		"uint32x4" => 0x23,
		"sint32" => 0x24,
		"sint32x2" => 0x25,
		"sint32x3" => 0x26,
		"sint32x4" => 0x27,
		"uint8x2" => 0x02,
		"uint8x4" => 0x03,
		"sint8x2" => 0x05,
		"sint8x4" => 0x06,
		"unorm8x2" => 0x08,
		"unorm8x4" => 0x09,
		"snorm8x2" => 0x0B,
		"snorm8x4" => 0x0C,
		"uint16x2" => 0x0E,
		"uint16x4" => 0x0F,
		"sint16x2" => 0x11,
		"sint16x4" => 0x12,
		"unorm16x2" => 0x14,
		"unorm16x4" => 0x15,
		"snorm16x2" => 0x17,
		"snorm16x4" => 0x18,
		"float16x2" => 0x1A,
		"float16x4" => 0x1B,
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
		"" | "keep" => 1,
		"zero" => 2,
		"replace" => 3,
		"invert" => 4,
		"increment-clamp" => 5,
		"decrement-clamp" => 6,
		"increment-wrap" => 7,
		"decrement-wrap" => 8,
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

function mipLevelCountOf(descriptor: GPUTextureDescriptor, volume: boolean, layers: int32): int32 {
	const requested = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	let largest = Math.max(descriptor.size.width, descriptor.size.height);
	if (volume) { largest = Math.max(largest, layers); }
	let possible = 1;
	while ((largest >> possible) > 0) { possible += 1; }
	if (requested < 1 || requested > possible) {
		stop(`GPUTextureDescriptor.mipLevelCount ${requested} is outside 1..${possible} for a ${descriptor.size.width}x${descriptor.size.height} texture`);
	}
	return requested;
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

function visibility(stage: string): int32 {
	return match (stage) {
		"vertex" => STAGE_VERTEX,
		"fragment" => STAGE_FRAGMENT,
		"compute" => STAGE_COMPUTE,
		_ => stopOnMember("GPUShaderBinding.stage", stage),
	};
}

function sampleType(sample: string): int32 {
	return match (sample) {
		"" | "float" => SAMPLE_FLOAT,
		"unfilterable-float" => SAMPLE_UNFILTERABLE_FLOAT,
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

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device === null) {
		stop("requestDevice needs the WGPUDevice the window created");
	}
	if (wgSetup(environment.device) == 0) { stop("the WGPUDevice gave no queue or no limits"); }
	uniformAlignment = wgMinUniformBufferOffsetAlignment();
	maxTextureDimension = wgMaxTextureDimension2D();
	deviceLimits = readLimits();
	frame = 0;
	encoding = false;
	pass.active = false;
	computeBound.active = false;
	passSerial = 0;
	groupDepth = 0;
	pass.occlusionOpen = false;
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
	if (pass.active || computeBound.active) { stop("shutdown with a pass still open"); }
	for (const id of querySets.liveIds()) { destroyQuerySet({ id: id }); }
	for (const id of bindGroups.liveIds()) { destroyBindGroup({ id: id }); }
	for (const id of pipelines.liveIds()) { destroyRenderPipeline({ id: id }); }
	for (const id of shaders.liveIds()) { destroyShaderModule({ id: id }); }
	for (const id of samplers.liveIds()) { destroySampler({ id: id }); }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { destroyView({ id: id }); } }
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { destroyTexture({ id: id }); } }
	for (const id of buffers.liveIds()) { destroyBuffer({ id: id }); }
	wgShutdown();
	encoding = false;
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
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
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
	if (offset < 0 || offset + bytes > buffers.slots[index].size) {
		const id = buffer.id;
		const size = buffers.slots[index].size;
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${id} of ${size}`);
	}
	if ((offset & 3) != 0) { stop(`writeBuffer offset ${offset} is not a multiple of 4`); }
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
	if (width <= 0 || height <= 0) {
		stop("GPUTextureDescriptor.size needs a positive width and height");
	}
	if (width > maxTextureDimension || height > maxTextureDimension) {
		const limit = maxTextureDimension;
		stop(`GPUTextureDescriptor.size ${width}x${height} exceeds maxTextureDimension2D ${limit}`);
	}
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	if (descriptor.size.depthOrArrayLayers < 0) { stop("GPUTextureDescriptor.size.depthOrArrayLayers is negative"); }
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	if (volume && (width > deviceLimits.maxTextureDimension3D || height > deviceLimits.maxTextureDimension3D || layers > deviceLimits.maxTextureDimension3D)) {
		stop(`GPUTextureDescriptor.size ${width}x${height}x${layers} exceeds maxTextureDimension3D ${deviceLimits.maxTextureDimension3D}`);
	}
	if (!volume && layers > deviceLimits.maxTextureArrayLayers) {
		stop(`GPUTextureDescriptor.size.depthOrArrayLayers ${layers} exceeds maxTextureArrayLayers ${deviceLimits.maxTextureArrayLayers}`);
	}
	const mipLevels = mipLevelCountOf(descriptor, volume, layers);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	if (sampleCount > 1 && (volume || layers > 1 || mipLevels > 1)) {
		stop("WebGPU allows a multisampled texture only as a 2d texture with one mip level and one array layer");
	}
	const usage = descriptor.usage;
	if (sampleCount > 1 && has(usage, GPUTextureUsage.STORAGE_BINDING as int32)) { stop("a multisampled texture cannot be STORAGE_BINDING"); }
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (volume && info.depth) { stop("WebGPU allows a depth or stencil format only on a 2d texture"); }
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
	let name: string = descriptor.dimension;
	if (name == "") { name = textures.slots[t].volume ? "3d" : (textures.slots[t].layers > 1 ? "2d-array" : "2d"); }
	if ((name == "3d") != textures.slots[t].volume) {
		stop(`GPUTextureViewDescriptor.dimension '${name}' does not match the ${textures.slots[t].volume ? "3d" : "2d"} GPUTexture ${textures.slots[t].id}`);
	}
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
	if (baseMip < 0 || mipCount < 1 || baseMip + mipCount > textures.slots[t].mipLevels) {
		stop(`view mips ${baseMip}+${mipCount} overrun GPUTexture ${textures.slots[t].id}, which has ${textures.slots[t].mipLevels} mips`);
	}
	const dimension = viewDimensionOf(descriptor, t);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (dimension == VIEW_3D) {
		if (baseLayer != 0 || layerCount > 1) { stop("a 3d view takes no baseArrayLayer or arrayLayerCount"); }
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (dimension == VIEW_2D) { layerCount = 1; }
		if (dimension == VIEW_CUBE) { layerCount = 6; }
		if (layerCount == 0) { layerCount = layers - baseLayer; }
		if (baseLayer < 0 || layerCount < 1 || baseLayer + layerCount > layers) {
			stop(`view layers ${baseLayer}+${layerCount} overrun GPUTexture ${textures.slots[t].id}, which has ${layers} layers`);
		}
	}
	if (dimension == VIEW_CUBE || dimension == VIEW_CUBE_ARRAY) {
		if (!textures.slots[t].cube) {
			stop(`a cube view needs GPUTexture ${textures.slots[t].id} created square, with TEXTURE_BINDING and a depthOrArrayLayers multiple of 6`);
		}
		if (layerCount % 6 != 0 || baseLayer % 6 != 0) { stop("a cube view takes whole cubes: baseArrayLayer and arrayLayerCount multiples of 6"); }
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
	let maxAnisotropy = descriptor.maxAnisotropy;
	if (maxAnisotropy < 1) { maxAnisotropy = 1; }
	if (maxAnisotropy > 1 && !(magFilter == FILTER_LINEAR && minFilter == FILTER_LINEAR && mipmapFilter == MIPMAP_LINEAR)) {
		stop("GPUSamplerDescriptor.maxAnisotropy above 1 needs linear magFilter, minFilter and mipmapFilter");
	}
	if (descriptor.lodMinClamp < 0) { stopOnMember("GPUSamplerDescriptor.lodMinClamp", `${descriptor.lodMinClamp}`); }
	const maxLod = descriptor.lodMaxClamp == 0 ? DEFAULT_LOD_MAX_CLAMP : descriptor.lodMaxClamp;
	if (maxLod < descriptor.lodMinClamp) {
		stop(`GPUSamplerDescriptor.lodMaxClamp ${maxLod} is below lodMinClamp ${descriptor.lodMinClamp}`);
	}
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
		maxAnisotropy,
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
	const compute = descriptor.computeCode != "";
	if (compute && (descriptor.vertexCode != "" || descriptor.fragmentCode != "")) {
		stop("a GPUShaderModule is either a compute module or a vertex and fragment module");
	}
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const stageName: string = descriptor.bindings[i].stage;
		if ((stageName == "compute") != compute) {
			stop(`shader binding ${descriptor.bindings[i].binding} stage '${stageName}' does not match a ${compute ? "compute" : "vertex and fragment"} module`);
		}
		const kind = bindingKind(kindName);
		const native: ShaderBinding = {
			binding: descriptor.bindings[i].binding,
			kind: kind,
			visibility: visibility(stageName),
			bindingType: bindingType(descriptor.bindings[i], kind),
			viewDimension: bindingViewDimension(descriptor.bindings[i].viewDimension),
			storageFormat: kind == BindingKind.StorageTexture ? storageFormatOf(descriptor.bindings[i].storageFormat, "GPUShaderBinding.storageFormat") : 0,
			size: descriptor.bindings[i].size,
		};
		checkBinding(native, descriptor.bindings[i].group);
		if (kind == BindingKind.Uniform) {
			if (slot.uniformCount == GPU_MAX_UNIFORM_BLOCKS) {
				stop("a shader module has over 8 uniform blocks");
			}
			slot.uniforms[slot.uniformCount] = native;
			slot.uniformCount += 1;
		} else {
			if (slot.resourceCount == GPU_MAX_BIND_GROUP_ENTRIES) {
				stop("a shader module has over 8 resources");
			}
			slot.resources[slot.resourceCount] = native;
			slot.resourceCount += 1;
		}
	}
	if (compute) {
		const size: int32[3] = descriptor.workgroupSize;
		if (size[0] > deviceLimits.maxComputeWorkgroupSizeX || size[1] > deviceLimits.maxComputeWorkgroupSizeY || size[2] > deviceLimits.maxComputeWorkgroupSizeZ || size[0] * size[1] * size[2] > deviceLimits.maxComputeInvocationsPerWorkgroup) {
			stop(`workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the device limits ${deviceLimits.maxComputeWorkgroupSizeX}x${deviceLimits.maxComputeWorkgroupSizeY}x${deviceLimits.maxComputeWorkgroupSizeZ} and ${deviceLimits.maxComputeInvocationsPerWorkgroup} invocations`);
		}
		slot.compute = createModule(descriptor.computeCode, descriptor.label);
		slot.computeEntry = entryPoint(descriptor.computeEntryPoint);
	} else {
		slot.vertex = createModule(descriptor.vertexCode, descriptor.label);
		slot.fragment = createModule(descriptor.fragmentCode, descriptor.label);
		slot.vertexEntry = entryPoint(descriptor.vertexEntryPoint);
		slot.fragmentEntry = entryPoint(descriptor.fragmentEntryPoint);
	}
	for (let u = 0; u < slot.uniformCount; u++) {
		const binding = slot.uniforms[u];
		wgLayoutEntry(u, binding.binding, binding.visibility, LAYOUT_UNIFORM, 0, VIEW_2D, 0);
	}
	slot.groupLayouts[GPU_UNIFORM_GROUP] = wgCreateLayout(slot.uniformCount, labelText(descriptor.label));
	for (let r = 0; r < slot.resourceCount; r++) {
		const binding = slot.resources[r];
		const layoutKind = match (binding.kind) {
			BindingKind.Texture => LAYOUT_TEXTURE,
			BindingKind.Sampler => LAYOUT_SAMPLER,
			BindingKind.StorageBuffer => LAYOUT_STORAGE_BUFFER,
			BindingKind.StorageTexture => LAYOUT_STORAGE_TEXTURE,
			BindingKind.Uniform => LAYOUT_UNIFORM,
		};
		wgLayoutEntry(r, binding.binding, binding.visibility, layoutKind, binding.bindingType, binding.viewDimension, binding.storageFormat);
	}
	slot.groupLayouts[GPU_RESOURCE_GROUP] = wgCreateLayout(slot.resourceCount, labelText(descriptor.label));
	const uniformLayout = slot.groupLayouts[GPU_UNIFORM_GROUP];
	if (uniformLayout == null || slot.groupLayouts[GPU_RESOURCE_GROUP] == null) {
		stop(`wgpuDeviceCreateBindGroupLayout failed for ${labelOf(descriptor.label)}`);
	}
	slot.id = id;
	store(shaders, slot);
	return { id: slot.id };
}

function checkBinding(native: ShaderBinding, group: int32): void {
	const uniform = native.kind == BindingKind.Uniform;
	const expectedGroup = uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
	const kind = native.kind.toString();
	if (group != expectedGroup) {
		const binding = native.binding;
		stop(`shader binding ${binding} (${kind}) belongs in group ${expectedGroup}, not ${group}`);
	}
	const limit = uniform ? MAX_UNIFORM_WGSL_BINDING : MAX_RESOURCE_WGSL_BINDING;
	if (native.binding < 0 || native.binding >= limit) {
		const last = limit - 1;
		const binding = native.binding;
		stop(`shader binding ${binding} is outside the WGSL group ${group} range 0..${last}`);
	}
	if (native.kind == BindingKind.Uniform && native.size <= 0) {
		stop(`uniform binding ${native.binding} needs its block size`);
	}
	if (native.kind == BindingKind.Uniform && (native.size as int64) > deviceLimits.maxUniformBufferBindingSize) {
		stop(`uniform binding ${native.binding} of ${native.size} bytes is over the limit of ${deviceLimits.maxUniformBufferBindingSize}`);
	}
	const writable = (native.kind == BindingKind.StorageBuffer && native.bindingType == BUFFER_STORAGE)
		|| (native.kind == BindingKind.StorageTexture && native.bindingType != ACCESS_READ_ONLY);
	if (writable && native.visibility == STAGE_VERTEX) {
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
	if (shaders.slots[s].compute != null) { stop("a compute GPUShaderModule cannot make a GPURenderPipeline"); }
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule in Void");
	}
	const topology = primitiveTopology(descriptor.primitive.topology);
	const stripIndexFormat = stripIndexFormatOf(descriptor.primitive, topology);
	const bufferCount = describeVertexBuffers(descriptor);
	const depthFormat: string = descriptor.depthStencil.format;
	if (depthFormat != "") {
		const info = formatInfo(descriptor.depthStencil.format, "depthStencil.format");
		if (!info.depth) { stopOnMember("depthStencil.format", depthFormat); }
		const state = descriptor.depthStencil;
		wgDepthStencil(
			info.native,
			state.depthWriteEnabled ? 1 : 0,
			compareFunction(state.depthCompare, "depthStencil.depthCompare"),
			state.stencilReadMask == 0 ? STENCIL_MASK_ALL : state.stencilReadMask,
			state.stencilWriteMask == 0 ? STENCIL_MASK_ALL : state.stencilWriteMask,
			state.depthBias,
			state.depthBiasSlopeScale,
			state.depthBiasClamp,
		);
		const front: GPUStencilFaceState = state.stencilFront;
		const back: GPUStencilFaceState = state.stencilBack;
		wgStencilFace(
			0,
			compareFunction(front.compare, "depthStencil.stencilFront.compare"),
			stencilOperation(front.failOp, "depthStencil.stencilFront.failOp"),
			stencilOperation(front.depthFailOp, "depthStencil.stencilFront.depthFailOp"),
			stencilOperation(front.passOp, "depthStencil.stencilFront.passOp"),
		);
		wgStencilFace(
			1,
			compareFunction(back.compare, "depthStencil.stencilBack.compare"),
			stencilOperation(back.failOp, "depthStencil.stencilBack.failOp"),
			stencilOperation(back.depthFailOp, "depthStencil.stencilBack.depthFailOp"),
			stencilOperation(back.passOp, "depthStencil.stencilBack.passOp"),
		);
	}
	const targetCount = describeColorTargets(descriptor);
	const sampleCount = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	const native = wgCreatePipeline(
		shaders.slots[s].vertex,
		shaders.slots[s].vertexEntry,
		shaders.slots[s].fragment,
		shaders.slots[s].fragmentEntry,
		shaders.slots[s].groupLayouts[GPU_UNIFORM_GROUP],
		shaders.slots[s].groupLayouts[GPU_RESOURCE_GROUP],
		bufferCount,
		targetCount,
		topology,
		stripIndexFormat,
		cullMode(descriptor.primitive.cullMode),
		frontFace(descriptor.primitive.frontFace),
		sampleCount,
		labelText(descriptor.label),
	);
	if (native == null) {
		stop(`wgpuDeviceCreateRenderPipeline failed for ${labelOf(descriptor.label)}`);
	}
	const slot: PipelineSlot = {
		id: id,
		shader: descriptor.vertex.module.id,
		native: native,
		stripIndexFormat: stripIndexFormat,
	};
	store(pipelines, slot);
	return { id: slot.id };
}

function stripIndexFormatOf(state: GPUPrimitiveState, topology: int32): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return 0; }
	if (topology != TOPOLOGY_LINE_STRIP && topology != TOPOLOGY_TRIANGLE_STRIP) {
		stop(`primitive.stripIndexFormat '${format}' needs a strip topology`);
	}
	return indexFormat(state.stripIndexFormat);
}

function describeVertexBuffers(descriptor: GPURenderPipelineDescriptor): int32 {
	let count = 0;
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stride = descriptor.vertex.buffers[b].arrayStride;
		let used = stride != 0;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format != "") { used = true; }
		}
		if (!used) { continue; }
		wgVertexBuffer(b, stride, stepMode(descriptor.vertex.buffers[b].stepMode));
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			wgVertexAttribute(
				b,
				vertexFormat(format),
				descriptor.vertex.buffers[b].attributes[a].offset,
				descriptor.vertex.buffers[b].attributes[a].shaderLocation,
			);
		}
		count = b + 1;
	}
	return count;
}

function describeColorTargets(descriptor: GPURenderPipelineDescriptor): int32 {
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
		wgColorTarget(
			i,
			info.native,
			descriptor.fragment.targets[i].blendEnabled ? 1 : 0,
			blendOperation(color.operation, "blend.color.operation"),
			blendFactor(color.srcFactor, "blend.color.srcFactor"),
			destinationFactor(color.dstFactor, "blend.color.dstFactor"),
			blendOperation(alpha.operation, "blend.alpha.operation"),
			blendFactor(alpha.srcFactor, "blend.alpha.srcFactor"),
			destinationFactor(alpha.dstFactor, "blend.alpha.dstFactor"),
			writeMask == 0 ? COLOR_WRITE_ALL : writeMask,
		);
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
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) {
			continue;
		}
		if (entry.buffer.id != 0) {
			const buffer = buffers.slots[buffers.slotIndex(entry.buffer.id)].native;
			if (group == GPU_UNIFORM_GROUP) {
				const size = uniformEntrySize(shader, entry);
				wgBindEntry(count, entry.binding, buffer, entry.offset, size, NO_VIEW, NO_SAMPLER);
				slot.dynamicCount += 1;
			} else {
				const size = storageEntrySize(shader, entry);
				wgBindEntry(count, entry.binding, buffer, entry.offset, size, NO_VIEW, NO_SAMPLER);
			}
		} else if (entry.textureView.id != 0) {
			const v = views.slotIndex(entry.textureView.id);
			const r = resourceIndex(shader, entry.binding);
			if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.StorageTexture) {
				wgBindEntry(count, entry.binding, NO_BUFFER, 0, 0, storageView(shader, r, v, entry.binding), NO_SAMPLER);
			} else {
				checkResource(shader, entry.binding, BindingKind.Texture, group);
				const view = views.slots[v].binding;
				if (view == null) {
					stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`);
				}
				wgBindEntry(count, entry.binding, NO_BUFFER, 0, 0, view, NO_SAMPLER);
			}
		} else {
			checkResource(shader, entry.binding, BindingKind.Sampler, group);
			const sampler = samplers.slots[samplers.slotIndex(entry.sampler.id)].native;
			wgBindEntry(count, entry.binding, NO_BUFFER, 0, 0, NO_VIEW, sampler);
		}
		count += 1;
	}
	slot.native = wgCreateBindGroup(shaders.slots[shader].groupLayouts[group], count, labelText(descriptor.label));
	if (slot.native == null) {
		stop(`wgpuDeviceCreateBindGroup failed for ${labelOf(descriptor.label)}`);
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: slot.id };
}

function uniformEntrySize(shader: int32, entry: GPUBindGroupEntry): int64 {
	const b = buffers.slotIndex(entry.buffer.id);
	if (!has(buffers.slots[b].usage, GPUBufferUsage.UNIFORM as int32)) {
		stop(`bind group entry ${entry.binding} needs a UNIFORM buffer`);
	}
	for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
		const binding = shaders.slots[shader].uniforms[u];
		if (binding.binding == entry.binding) {
			if (entry.offset < 0 || entry.offset % (uniformAlignment as int64) != 0) {
				stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${uniformAlignment}`);
			}
			if (entry.offset + (binding.size as int64) > buffers.slots[b].size) {
				stop(`bind group entry ${entry.binding} offset ${entry.offset} overruns its buffer`);
			}
			if (entry.size != 0 && entry.size < (binding.size as int64)) {
				const block = binding.size;
				const at = entry.binding;
				const size = entry.size;
				stop(`bind group entry ${at} size ${size} is below its block of ${block}`);
			}
			return entry.size == 0 ? binding.size as int64 : entry.size;
		}
	}
	stop(`bind group entry ${entry.binding} (Uniform) is not a binding of the pipeline's shader`);
}

function resourceIndex(shader: int32, binding: int32): int32 {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		if (shaders.slots[shader].resources[r].binding == binding) { return r; }
	}
	return -1;
}

function storageEntrySize(shader: int32, entry: GPUBindGroupEntry): int64 {
	const b = buffers.slotIndex(entry.buffer.id);
	const r = resourceIndex(shader, entry.binding);
	if (r < 0 || shaders.slots[shader].resources[r].kind != BindingKind.StorageBuffer) {
		stop(`bind group ${GPU_RESOURCE_GROUP} entry ${entry.binding} (buffer) is not a storage buffer binding of the pipeline's shader`);
	}
	if (!has(buffers.slots[b].usage, GPUBufferUsage.STORAGE as int32)) { stop(`bind group entry ${entry.binding} needs a STORAGE buffer`); }
	const alignment = deviceLimits.minStorageBufferOffsetAlignment as int64;
	if (entry.offset < 0 || entry.offset % alignment != 0) {
		stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${alignment}`);
	}
	const bytes = entry.size == 0 ? buffers.slots[b].size - entry.offset : entry.size;
	if (bytes <= 0 || bytes % 4 != 0 || entry.offset + bytes > buffers.slots[b].size) {
		stop(`bind group entry ${entry.binding} range ${entry.offset}+${bytes} is not a positive multiple of 4 inside its buffer of ${buffers.slots[b].size}`);
	}
	if (bytes > deviceLimits.maxStorageBufferBindingSize) {
		stop(`bind group entry ${entry.binding} range of ${bytes} bytes is over the limit of ${deviceLimits.maxStorageBufferBindingSize}`);
	}
	return bytes;
}

function storageView(shader: int32, r: int32, v: int32, binding: int32): Ptr<WgViewImpl> {
	const t = textures.slotIndex(views.slots[v].texture);
	if (!has(textures.slots[t].usage, GPUTextureUsage.STORAGE_BINDING as int32)) {
		stop(`bind group entry ${binding}: the view's texture lacks STORAGE_BINDING`);
	}
	if (views.slots[v].mipCount != 1) { stop(`bind group entry ${binding}: a storage texture view takes exactly one mip`); }
	const expected = shaders.slots[shader].resources[r];
	if (views.slots[v].dimension != expected.viewDimension) {
		stop(`bind group entry ${binding}: the view dimension ${views.slots[v].dimension} differs from the shader's ${expected.viewDimension}`);
	}
	if (textures.slots[t].info.native != expected.storageFormat) {
		stop(`bind group entry ${binding}: the texture format '${textures.slots[t].format}' differs from the shader's storage format`);
	}
	return views.slots[v].native;
}

function checkResource(shader: int32, binding: int32, kind: BindingKind, group: int32): void {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		const resource = shaders.slots[shader].resources[r];
		if (resource.binding == binding && resource.kind == kind) { return; }
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
	if (encoding) { stop("createCommandEncoder with the frame's encoder not yet finished"); }
	if (wgBeginEncoder() == 0) { stop("wgpuDeviceCreateCommandEncoder failed"); }
	encoding = true;
	groupDepth = 0;
	return { id: 1 };
}

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (pass.active) { stop("finish with a render pass still open"); }
	if (computeBound.active) { stop("finish with a compute pass still open"); }
	checkGroupsClosed(0, "finish");
	if (!encoding) { stop("finish without createCommandEncoder"); }
	encoding = false;
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
	if (pass.active || computeBound.active) { stop("beginRenderPass with a pass already open"); }
	if (!encoding) { stop("beginRenderPass without createCommandEncoder"); }
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	const occlusionId = descriptor.occlusionQuerySet.id;
	if (occlusionId != 0 && querySets.slots[querySets.slotIndex(occlusionId)].timestamp) {
		stop("GPURenderPassDescriptor.occlusionQuerySet is a timestamp set: an occlusion set is required");
	}
	pass.width = 0;
	pass.height = 0;
	let count = 0;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = descriptor.colorAttachments[i];
		if (attachment.view.id == 0) {
			wgColorAttachment(i, NO_VIEW, NO_VIEW, 0, 0, -1, 0, 0, 0, 0);
			continue;
		}
		const v = views.slotIndex(attachment.view.id);
		checkColorAttachment(i, views.slots[v].texture);
		if (!views.slots[v].attachable) { stop(`colorAttachments[${i}].view spans several mips or layers: a render attachment is one mip of one layer`); }
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		const slice = attachment.depthSlice;
		if (views.slots[v].dimension == VIEW_3D) {
			const slices = Math.max(1, textures.slots[textures.slotIndex(views.slots[v].texture)].layers >> views.slots[v].baseMip);
			if (slice < 0 || slice >= slices) {
				stop(`colorAttachments[${i}].depthSlice ${slice} is outside the ${slices} slices of mip ${views.slots[v].baseMip} of GPUTexture ${views.slots[v].texture}`);
			}
		} else if (slice != 0) {
			stop(`colorAttachments[${i}].depthSlice ${slice} needs a 3d view`);
		}
		let resolve = views.slots[v].swapchainResolve;
		if (attachment.resolveTarget.id != 0) {
			resolve = checkResolve(i, views.slots[v].texture, attachment.resolveTarget.id);
		}
		const color = attachment.clearValue;
		wgColorAttachment(
			i,
			views.slots[v].native,
			resolve,
			loadOp(attachment.loadOp, i, "loadOp"),
			storeOp(attachment.storeOp, i, "storeOp"),
			views.slots[v].dimension == VIEW_3D ? slice : -1,
			color.r,
			color.g,
			color.b,
			color.a,
		);
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
		wgDepthAttachment(
			views.slots[v].native,
			loadOp(depth.depthLoadOp, -1, "depthLoadOp"),
			storeOp(depth.depthStoreOp, -1, "depthStoreOp"),
			depth.depthClearValue,
			info.stencil ? 1 : 0,
		);
	}
	if (count == 0 && depthView == 0) { stop("beginRenderPass without an attachment"); }
	const writes = descriptor.timestampWrites;
	if (wgBeginPass(
		count,
		depthView != 0 ? 1 : 0,
		pass.width,
		pass.height,
		labelText(descriptor.label),
		occlusionId == 0 ? NO_QUERY_SET : querySets.slots[querySets.slotIndex(occlusionId)].native,
		timestampNative(writes),
		writes.beginningOfPassWriteIndex,
		writes.endOfPassWriteIndex,
	) == 0) {
		stop("wgpuCommandEncoderBeginRenderPass failed");
	}
	pass.active = true;
	passSerial += 1;
	pass.groupBase = groupDepth;
	pass.timestampSet = writes.querySet.id;
	pass.timestampEnd = writes.endOfPassWriteIndex;
	pass.occlusionSet = occlusionId;
	pass.occlusionOpen = false;
	markTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	pass.pipeline = 0;
	pass.indexFormat = 0;
	return { id: 1 };
}

function passExtent(texture: uint32, baseMip: int32): void {
	const t = textures.slotIndex(texture);
	const width = Math.max(1, textures.slots[t].width >> baseMip);
	const height = Math.max(1, textures.slots[t].height >> baseMip);
	if (pass.width == 0) {
		pass.width = width;
		pass.height = height;
	} else if (pass.width != width || pass.height != height) {
		stop("render pass attachments differ in size");
	}
}

function checkColorAttachment(attachment: int32, texture: uint32): void {
	const t = textures.slotIndex(texture);
	const attachable = has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (textures.slots[t].info.depth || !attachable) {
		stop(`colorAttachments[${attachment}].view is not a color RENDER_ATTACHMENT`);
	}
}

function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): Ptr<WgViewImpl> {
	const r = views.slotIndex(resolveId);
	const resolveTexture = textures.slotIndex(views.slots[r].texture);
	if (textures.slots[textures.slotIndex(colorTexture)].sampleCount == 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`);
	}
	if (textures.slots[resolveTexture].sampleCount != 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample view`);
	}
	checkColorAttachment(attachment, views.slots[r].texture);
	if (!views.slots[r].attachable) { stop(`colorAttachments[${attachment}].resolveTarget spans several mips or layers: a render attachment is one mip of one layer`); }
	return views.slots[r].native;
}

export function endPass(): void {
	if (!pass.active) { stop("end without an open render pass"); }
	if (pass.occlusionOpen) { stop("end with an occlusion query still open"); }
	checkGroupsClosed(pass.groupBase, "end");
	wgEndPass();
	markTimestamp(pass.timestampSet, pass.timestampEnd);
	pass.active = false;
}

@inline function checkPass(call: string): void {
	if (!pass.active) { stop(`${call} outside a render pass`); }
}

@inline export function setPipeline(pipeline: GPURenderPipeline): void {
	checkPass("setPipeline");
	const p = pipelines.slotIndex(pipeline.id);
	if (pipelines.slots[p].compute) { stop(`GPUPipeline ${pipeline.id} is a compute pipeline`); }
	wgSetPipeline(pipelines.slots[p].native);
	pass.pipeline = pipeline.id;
}

@inline export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	checkPass("setVertexBuffer");
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
	checkPass("setIndexBuffer");
	pass.indexFormat = indexFormat(format);
	wgSetIndexBuffer(buffers.slots[buffers.slotIndex(buffer.id)].native, pass.indexFormat, offset);
}

export function setBindGroup(
	index: int32,
	bindGroup: GPUBindGroup,
	dynamicOffsets: Readonly<Span<uint32>>,
): void {
	checkPass("setBindGroup");
	stageBindGroup(index, bindGroup, dynamicOffsets, false);
}

function stageBindGroup(
	index: int32,
	bindGroup: GPUBindGroup,
	dynamicOffsets: Readonly<Span<uint32>>,
	compute: boolean,
): void {
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) {
		stopOnMember("setBindGroup index", `${index}`);
	}
	if (bindGroup.id == 0) {
		if (compute) {
			wgSetComputeBindGroup(index, NO_BIND_GROUP, 0);
			computeBound.groupMask &= ~(1 << index);
		} else {
			wgSetBindGroup(index, NO_BIND_GROUP, 0);
		}
		return;
	}
	const g = bindGroups.slotIndex(bindGroup.id);
	if (bindGroups.slots[g].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups.slots[g].group}`);
	}
	if ((dynamicOffsets.length as int32) != bindGroups.slots[g].dynamicCount) {
		const expected = bindGroups.slots[g].dynamicCount;
		const got = dynamicOffsets.length;
		stop(`setBindGroup(${index}) takes ${expected} dynamic offsets, got ${got}`);
	}
	for (let i = 0; i < bindGroups.slots[g].dynamicCount; i++) {
		if (dynamicOffsets[i] % (uniformAlignment as uint32) != 0) {
			stop(`dynamic offset ${dynamicOffsets[i]} is not a multiple of ${uniformAlignment}`);
		}
		wgDynamicOffset(i, dynamicOffsets[i]);
	}
	if (compute) {
		wgSetComputeBindGroup(index, bindGroups.slots[g].native, bindGroups.slots[g].dynamicCount);
		computeBound.groupMask |= 1 << index;
	} else {
		wgSetBindGroup(index, bindGroups.slots[g].native, bindGroups.slots[g].dynamicCount);
	}
}

@inline export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	checkPass("setScissorRect");
	wgSetScissorRect(x, y, width, height);
}

export function setViewport(x: number, y: number, width: number, height: number, minDepth: number, maxDepth: number): void {
	checkPass("setViewport");
	if (width < 0 || height < 0 || minDepth < 0 || maxDepth > 1 || minDepth > maxDepth) {
		stop(`setViewport ${width}x${height} depth ${minDepth}..${maxDepth} is outside WebGPU's valid range`);
	}
	wgSetViewport(x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	checkPass("setBlendConstant");
	wgSetBlendConstant(color.r, color.g, color.b, color.a);
}

export function setStencilReference(reference: uint32): void {
	checkPass("setStencilReference");
	wgSetStencilReference(reference);
}

@inline export function draw(
	vertexCount: int32,
	instanceCount: int32,
	firstVertex: int32,
	firstInstance: int32,
): void {
	checkPass("draw");
	if (pass.pipeline == 0) { stop("draw without setPipeline"); }
	wgDraw(vertexCount, instanceCount, firstVertex, firstInstance);
}

@inline export function drawIndexed(
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	checkPass("drawIndexed");
	if (pass.pipeline == 0) { stop("drawIndexed without setPipeline"); }
	const strip = pipelines.slots[pipelines.slotIndex(pass.pipeline)].stripIndexFormat;
	if (strip != 0 && strip != pass.indexFormat) {
		stop("an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format");
	}
	wgDrawIndexed(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
}

function encodedCopy(member: string): void {
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	if (!encoding) { stop(`${member} without createCommandEncoder`); }
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	encodedCopy(member);
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	encodedCopy(member);
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

function checkedBufferLayout(member: string, bytesPerPixel: int32, slot: int32, info: GPUTexelCopyBufferInfo, size: GPUExtent3D): int32 {
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
	const fromFormat: string = textures.slots[from].format;
	const toFormat: string = textures.slots[to].format;
	if (fromFormat != toFormat) { stop(`copyTextureToTexture between formats '${fromFormat}' and '${toFormat}'`); }
	if (textures.slots[from].volume != textures.slots[to].volume) { stop("copyTextureToTexture between a 3d and a 2d GPUTexture"); }
	copyRegion("copyTextureToTexture source", source, from, size);
	copyRegion("copyTextureToTexture destination", destination, to, size);
	const mipWidth = Math.max(1, textures.slots[from].width >> source.mipLevel);
	const mipHeight = Math.max(1, textures.slots[from].height >> source.mipLevel);
	if (textures.slots[from].info.depth && (size.width != mipWidth || size.height != mipHeight)) {
		stop(`copyTextureToTexture of depth GPUTexture ${source.texture.id} copies whole mips only`);
	}
	if (
		from == to && source.mipLevel == destination.mipLevel
			&& source.origin.z < destination.origin.z + size.depthOrArrayLayers && destination.origin.z < source.origin.z + size.depthOrArrayLayers
			&& source.origin.x < destination.origin.x + size.width && destination.origin.x < source.origin.x + size.width
			&& source.origin.y < destination.origin.y + size.height && destination.origin.y < source.origin.y + size.height
	) {
		stop(`copyTextureToTexture regions overlap inside mip ${source.mipLevel} of GPUTexture ${source.texture.id}`);
	}
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
	if (shaders.slots[s].compute == null) { stop("createComputePipeline needs a GPUShaderModule made with computeCode"); }
	const entry = entryPoint(descriptor.compute.entryPoint);
	if (entry != shaders.slots[s].computeEntry) {
		stop(`compute.entryPoint '${entry}' differs from the module's computeEntryPoint '${shaders.slots[s].computeEntry}'`);
	}
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
	if (pass.active || computeBound.active) { stop("beginComputePass with a pass already open"); }
	if (!encoding) { stop("beginComputePass without createCommandEncoder"); }
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
	computeBound.active = true;
	computeBound.groupBase = groupDepth;
	computeBound.timestampSet = writes.querySet.id;
	computeBound.timestampEnd = writes.endOfPassWriteIndex;
	markTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	computeBound.pipeline = 0;
	computeBound.groupMask = 0;
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	if (!computeBound.active) { stop("setPipeline outside a compute pass"); }
	const p = pipelines.slotIndex(pipeline.id);
	if (!pipelines.slots[p].compute) { stop(`GPUPipeline ${pipeline.id} is not a compute pipeline`); }
	wgSetComputePipeline(pipelines.slots[p].native);
	computeBound.pipeline = pipeline.id;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (!computeBound.active) { stop("setBindGroup outside a compute pass"); }
	stageBindGroup(index, bindGroup, dynamicOffsets, true);
}

function checkDispatch(call: string): void {
	if (!computeBound.active) { stop(`${call} outside a compute pass`); }
	if (computeBound.pipeline == 0) { stop(`${call} without setPipeline`); }
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
	const limit = deviceLimits.maxComputeWorkgroupsPerDimension;
	if (x < 0 || y < 0 || z < 0 || x > limit || y > limit || z > limit) {
		stop(`dispatchWorkgroups ${x},${y},${z} is outside 0..${limit}`);
	}
	wgDispatch(x, y, z);
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	checkDispatch("dispatchWorkgroupsIndirect");
	const b = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[b].usage, GPUBufferUsage.INDIRECT as int32)) {
		stop(`dispatchWorkgroupsIndirect: GPUBuffer ${buffer.id} was created without INDIRECT`);
	}
	if (offset < 0 || offset % 4 != 0 || offset + 12 > buffers.slots[b].size) {
		stop(`dispatchWorkgroupsIndirect offset ${offset} is not a multiple of 4 with 12 bytes inside GPUBuffer ${buffer.id} of ${buffers.slots[b].size}`);
	}
	wgDispatchIndirect(buffers.slots[b].native, offset);
}

export function endComputePass(): void {
	if (!computeBound.active) { stop("end without an open compute pass"); }
	checkGroupsClosed(computeBound.groupBase, "end");
	wgEndComputePass();
	markTimestamp(computeBound.timestampSet, computeBound.timestampEnd);
	computeBound.active = false;
	computeBound.pipeline = 0;
}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	if (kind != "timestamp" && kind != "occlusion") { stopOnMember("GPUQuerySetDescriptor.type", kind); }
	const timestamp = kind == "timestamp";
	if (descriptor.count < 1 || descriptor.count > MAX_QUERY_COUNT) {
		stop(`GPUQuerySetDescriptor.count ${descriptor.count} is outside 1..${MAX_QUERY_COUNT}`);
	}
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

function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySets.slotIndex(writes.querySet.id);
	if (!querySets.slots[q].timestamp) { stop(`${member}.querySet is an occlusion set: a timestamp set is required`); }
	const begin = writes.beginningOfPassWriteIndex;
	const end = writes.endOfPassWriteIndex;
	if (begin == end) {
		stop(`${member} writes index ${begin} at both ends: give each end its own index, or -1 (GPU_NO_QUERY_INDEX) to skip one`);
	}
	if (begin < -1 || begin >= querySets.slots[q].count || end < -1 || end >= querySets.slots[q].count) {
		stop(`${member} indices ${begin} and ${end} are outside the query set of ${querySets.slots[q].count}`);
	}
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	if (pass.active || computeBound.active) { stop("resolveQuerySet inside a pass"); }
	if (!encoding) { stop("resolveQuerySet without createCommandEncoder"); }
	const q = querySets.slotIndex(querySet.id);
	if (firstQuery < 0 || queryCount < 0 || firstQuery + queryCount > querySets.slots[q].count) {
		stop(`resolveQuerySet ${firstQuery}+${queryCount} overruns the query set of ${querySets.slots[q].count}`);
	}
	const b = buffers.slotIndex(destination.id);
	if (!has(buffers.slots[b].usage, GPUBufferUsage.QUERY_RESOLVE as int32)) {
		stop(`resolveQuerySet: GPUBuffer ${destination.id} was created without QUERY_RESOLVE`);
	}
	if (destinationOffset < 0 || destinationOffset % RESOLVE_OFFSET_ALIGNMENT != 0) {
		stop(`resolveQuerySet destinationOffset ${destinationOffset} is not a multiple of ${RESOLVE_OFFSET_ALIGNMENT}`);
	}
	const bytes = (queryCount as int64) * 8;
	if (destinationOffset + bytes > buffers.slots[b].size) {
		stop(`resolveQuerySet of ${bytes} bytes at ${destinationOffset} overruns GPUBuffer ${destination.id} of ${buffers.slots[b].size}`);
	}
	if (queryCount == 0) { return; }
	for (let i = 0; i < queryCount; i++) {
		const state = querySets.slots[q].state[firstQuery + i];
		if (state == QUERY_UNWRITTEN) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QUERY_OPEN) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	wgResolveQuerySet(querySets.slots[q].native, firstQuery, queryCount, buffers.slots[b].native, destinationOffset);
}

export function beginOcclusionQuery(queryIndex: int32): void {
	if (!pass.active) { stop("beginOcclusionQuery outside a render pass"); }
	if (pass.occlusionSet == 0) { stop("beginOcclusionQuery needs GPURenderPassDescriptor.occlusionQuerySet"); }
	if (pass.occlusionOpen) { stop("beginOcclusionQuery with an occlusion query already open"); }
	const q = querySets.slotIndex(pass.occlusionSet);
	if (queryIndex < 0 || queryIndex >= querySets.slots[q].count) {
		stop(`beginOcclusionQuery index ${queryIndex} is outside the query set of ${querySets.slots[q].count}`);
	}
	if (querySets.slots[q].usedPass[queryIndex] == passSerial) {
		stop(`beginOcclusionQuery index ${queryIndex} was already used in this pass`);
	}
	querySets.slots[q].usedPass[queryIndex] = passSerial;
	querySets.slots[q].state[queryIndex] = QUERY_OPEN;
	wgBeginOcclusionQuery(queryIndex);
	pass.occlusionOpen = true;
	pass.occlusionIndex = queryIndex;
}

export function endOcclusionQuery(): void {
	if (!pass.active || !pass.occlusionOpen) { stop("endOcclusionQuery without an open occlusion query"); }
	wgEndOcclusionQuery();
	querySets.slots[querySets.slotIndex(pass.occlusionSet)].state[pass.occlusionIndex] = QUERY_WRITTEN;
	pass.occlusionOpen = false;
}

function limitOf(which: int32): int32 { return wgLimit(which) as int32; }

function readLimits(): GPUSupportedLimits {
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

export function limits(): GPUSupportedLimits { return deviceLimits; }

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

function checkGroupsClosed(base: int32, what: string): void {
	if (groupDepth != base) { stop(`${what} with ${groupDepth - base} debug groups still open`); }
}

export function pushDebugGroup(label: string): void {
	if (!encoding) { stop("pushDebugGroup without createCommandEncoder"); }
	wgPushDebugGroup(label);
	groupDepth += 1;
}

export function popDebugGroup(): void {
	if (!encoding) { stop("popDebugGroup without createCommandEncoder"); }
	const base = pass.active ? pass.groupBase : (computeBound.active ? computeBound.groupBase : 0);
	if (groupDepth <= base) { stop("popDebugGroup without a matching pushDebugGroup"); }
	wgPopDebugGroup();
	groupDepth -= 1;
}

export function insertDebugMarker(label: string): void {
	if (!encoding) { stop("insertDebugMarker without createCommandEncoder"); }
	wgInsertDebugMarker(label);
}
