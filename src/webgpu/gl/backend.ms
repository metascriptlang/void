import {
	BindingKind,
	bindingKind,
	linearFilter,
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
	GPUIndexFormat,
	GPUMapMode,
	GPULiveCounts,
	GPUPassTimestampWrites,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderAttribute,
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
	checkedBufferUsage,
	checkedDepthSlice,
	checkedDepthTexelCopy,
	checkedDispatch,
	checkedDispatchIndirect,
	checkedMapAsync,
	checkedMappedRange,
	checkedMipLevelCount,
	checkedMultisample,
	checkedNoDepthSlice,
	checkedPassExtent,
	checkedPopDebugGroup,
	checkedQuerySetCount,
	checkedResolveQuerySet,
	checkedResolveTarget,
	checkedSamplerAnisotropy,
	checkedSamplerLod,
	checkedSingleSubresource,
	checkedTexelBufferLayout,
	checkedTexelCopyRegion,
	checkedTexelWritePitch,
	checkedTextureToTextureCopy,
	checkedTimestampWrites,
	checkedUnmap,
	checkedView3d,
	checkedViewLayers,
	checkedViewMips,
	checkedViewport,
	checkedWriteBuffer,
	DUMMY_SAMPLER_BINDING,
	featureBit,
	checkedIntegerTexturePairs,
	firstInstanceRefusal,
	checkedVisibility,
	stopOnUnportedShaderBindings,
	stopOnUnportedShaderBytecode,
} from "../types.ms";
import { Pool, allocate, alive, live, liveIds, newPool, release, reset, slotIndex, store } from "../pool.ms";
import {
	oglActiveTexture,
	oglAttribLocation,
	oglBeginQuery,
	oglBindBuffer,
	oglBindBufferRange,
	oglBindFramebuffer,
	oglBindImageTexture,
	oglBindSampler,
	oglBindTexture,
	oglBindVertexArray,
	oglBlendColor,
	oglBlendEquationSeparate,
	oglBlendFuncSeparate,
	oglBlitColor,
	oglBufferData,
	oglBufferSubData,
	oglCapabilities,
	oglCheckFramebufferStatus,
	oglClearColor,
	oglClearDepth,
	oglClearDepthStencil,
	oglColorMask,
	oglCompileShader,
	oglConstantsDisagreement,
	oglCopyBufferDataUncached,
	oglCopyBytes,
	oglCopyTexels,
	oglCreateBuffer,
	oglCreateFramebuffer,
	oglCreateQuery,
	oglCreateRenderbufferUncached,
	oglCreateSampler,
	oglCreateTexture,
	oglCreateVertexArray,
	oglCullFace,
	oglDebugMarker,
	oglDeleteBuffer,
	oglDeleteFramebuffer,
	oglDeleteProgram,
	oglDeleteQuery,
	oglDeleteRenderbuffer,
	oglDeleteSampler,
	oglDeleteTexture,
	oglDeleteVertexArray,
	oglDepthFunc,
	oglDepthMask,
	oglDepthRange,
	oglDisable,
	oglDisableVertexAttribArray,
	oglDispatchCompute,
	oglDispatchComputeIndirectUncached,
	oglDrawArrays,
	oglDrawArraysInstanced,
	oglDrawBuffers,
	oglDrawElements,
	oglDrawElementsInstanced,
	oglEnable,
	oglEnableVertexAttribArray,
	oglEndQuery,
	oglFramebufferDetach,
	oglFramebufferRenderbuffer,
	oglFramebufferTexture2D,
	oglFramebufferTextureLayer,
	oglFrontFace,
	oglGetBufferDataUncached,
	oglGetError,
	oglGetInteger,
	oglGetInteger64,
	oglGetIntegeri,
	oglLinkComputeProgram,
	oglLinkProgram,
	oglLoad,
	oglLoadMissing,
	oglLog,
	oglMemoryBarrier,
	oglObjectLabel,
	oglPixelStore,
	oglPolygonOffset,
	oglPopDebugGroup,
	oglPushDebugGroup,
	oglQueryCounter,
	oglQueryCounterBits,
	oglQueryResult,
	oglReadBuffer,
	oglReadScreenRectUncached,
	oglReadTexelsToBufferUncached,
	oglSamplerParameterf,
	oglSamplerParameteri,
	oglScissor,
	oglStencilFunc,
	oglStencilFuncSeparate,
	oglStencilMask,
	oglStencilOp,
	oglStencilOpSeparate,
	oglTexParameteri,
	oglTexStorage,
	oglTexSubImage,
	oglTexSubImageFromBufferUncached,
	oglTextureNative,
	oglUniform1i,
	oglUniform4fv,
	oglUniformLocation,
	oglUnload,
	oglUseProgram,
	oglVertexAttribDivisor,
	oglVertexAttribIPointer,
	oglVertexAttribPointer,
	oglViewport,
} from "./gl.h";

when (webgl2) {
	import { oglQueryAvailable } from "./gl.h";
}

when (webgl2 || android) {
	import { oglHasExtension } from "./gl.h";
} else {
	import {
		oglBlendEquationSeparatei,
		oglBlendFuncSeparatei,
		oglColorMaski,
		oglDrawArraysInstancedBaseInstance,
		oglDrawElementsBaseVertex,
		oglDrawElementsInstancedBaseVertex,
		oglDisablei,
		oglDrawElementsInstancedBaseVertexBaseInstance,
		oglEnablei,
		oglSamplerBorderColor,
		oglTexStorage2DMultisample,
	} from "./gl.h";
}

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

const UNIFORM_OFFSET_ALIGNMENT = 256;
const INFLIGHT_SLOTS = 2;
const MAX_TEXTURE_UNITS = 16;
const MAX_TEXTURE_PAIRS = 16;
const MAX_SHADER_RESOURCES = 24;
const MAX_DEBUG_GROUPS = 63;
const STORAGE_OFFSET_ALIGNMENT = 256;
const QUERY_UNWRITTEN: uint8 = 0;
const QUERY_OPEN: uint8 = 1;
const QUERY_WRITTEN: uint8 = 2;
const BARRIER_BETWEEN_DISPATCHES = 0x2068;
const BARRIER_ALL = -1;
const COLOR_WRITE_ALL = 0xF;

const GL_ZERO = 0;
const GL_ONE = 1;
const GL_POINTS = 0x0000;
const GL_LINES = 0x0001;
const GL_LINE_STRIP = 0x0003;
const GL_TRIANGLES = 0x0004;
const GL_TRIANGLE_STRIP = 0x0005;
const GL_CONSTANT_COLOR = 0x8001;
const GL_ONE_MINUS_CONSTANT_COLOR = 0x8002;
const GL_REPLACE = 0x1E01;
const GL_INCR = 0x1E02;
const GL_DECR = 0x1E03;
const GL_INVERT = 0x150A;
const GL_INCR_WRAP = 0x8507;
const GL_DECR_WRAP = 0x8508;
const GL_PRIMITIVE_RESTART_FIXED_INDEX = 0x8D69;
const GL_TEXTURE_BASE_LEVEL = 0x813C;
const GL_TEXTURE_MAX_LEVEL = 0x813D;
const GL_TEXTURE_COMPARE_FUNC = 0x884D;
const GL_COMPARE_REF_TO_TEXTURE = 0x884E;
const GL_TEXTURE_MAX_ANISOTROPY = 0x84FE;
const GL_MAX_TEXTURE_MAX_ANISOTROPY = 0x84FF;
const GL_NEAREST_MIPMAP_LINEAR = 0x2702;
const GL_LINEAR_MIPMAP_LINEAR = 0x2703;
const GL_TEXTURE_3D = 0x806F;
const GL_TEXTURE_2D_ARRAY = 0x8C1A;
const GL_TEXTURE_CUBE_MAP = 0x8513;
const GL_TEXTURE_CUBE_MAP_POSITIVE_X = 0x8515;
const GL_BYTE = 0x1400;
const GL_SHORT = 0x1402;
const GL_INT = 0x1404;
const GL_UNSIGNED_INT_2_10_10_10_REV = 0x8368;
const GL_UNSIGNED_INT_10F_11F_11F_REV = 0x8C3B;
const GL_RG = 0x8227;
const GL_RGB = 0x1907;
const GL_RED_INTEGER = 0x8D94;
const GL_RGBA_INTEGER = 0x8D99;
const GL_RG8 = 0x822B;
const GL_SRGB8_ALPHA8 = 0x8C43;
const GL_RGBA8UI = 0x8D7C;
const GL_RGBA8I = 0x8D8E;
const GL_R16F = 0x822D;
const GL_RG16F = 0x822F;
const GL_RGBA16UI = 0x8D76;
const GL_R32F = 0x822E;
const GL_RG32F = 0x8230;
const GL_RGBA32F = 0x8814;
const GL_RGBA32UI = 0x8D70;
const GL_R32UI = 0x8236;
const GL_RGB10_A2 = 0x8059;
const GL_R11F_G11F_B10F = 0x8C3A;
const GL_DEPTH_COMPONENT16 = 0x81A5;
const STENCIL_MASK_ALL = -1;
const GL_SRC_COLOR = 0x0300;
const GL_ONE_MINUS_SRC_COLOR = 0x0301;
const GL_SRC_ALPHA = 0x0302;
const GL_ONE_MINUS_SRC_ALPHA = 0x0303;
const GL_DST_ALPHA = 0x0304;
const GL_ONE_MINUS_DST_ALPHA = 0x0305;
const GL_DST_COLOR = 0x0306;
const GL_ONE_MINUS_DST_COLOR = 0x0307;
const GL_SRC_ALPHA_SATURATE = 0x0308;
const GL_FUNC_ADD = 0x8006;
const GL_MIN = 0x8007;
const GL_MAX = 0x8008;
const GL_FUNC_SUBTRACT = 0x800A;
const GL_FUNC_REVERSE_SUBTRACT = 0x800B;
const GL_NEVER = 0x0200;
const GL_LESS = 0x0201;
const GL_EQUAL = 0x0202;
const GL_LEQUAL = 0x0203;
const GL_GREATER = 0x0204;
const GL_NOTEQUAL = 0x0205;
const GL_GEQUAL = 0x0206;
const GL_ALWAYS = 0x0207;
const GL_FRONT = 0x0404;
const GL_BACK = 0x0405;
const GL_CW = 0x0900;
const GL_CCW = 0x0901;
const GL_KEEP = 0x1E00;
const GL_CULL_FACE = 0x0B44;
const GL_DEPTH_TEST = 0x0B71;
const GL_STENCIL_TEST = 0x0B90;
const GL_DITHER = 0x0BD0;
const GL_BLEND = 0x0BE2;
const GL_SCISSOR_TEST = 0x0C11;
const GL_POLYGON_OFFSET_FILL = 0x8037;
const GL_MULTISAMPLE = 0x809D;
const GL_SAMPLE_ALPHA_TO_COVERAGE = 0x809E;
const GL_PROGRAM_POINT_SIZE = 0x8642;
const GL_TEXTURE_CUBE_MAP_SEAMLESS = 0x884F;
const GL_FRAMEBUFFER_SRGB = 0x8DB9;
const GL_ARRAY_BUFFER = 0x8892;
const GL_ELEMENT_ARRAY_BUFFER = 0x8893;
const GL_STATIC_DRAW = 0x88E4;
const GL_DYNAMIC_DRAW = 0x88E8;
const GL_STREAM_READ = 0x88E1;
const GL_TEXTURE_2D = 0x0DE1;
const GL_TEXTURE_2D_MULTISAMPLE = 0x9100;
const GL_RENDERBUFFER = 0x8D41;
const GL_R8 = 0x8229;
const GL_RGBA8 = 0x8058;
const GL_RGBA16F = 0x881A;
const GL_DEPTH_COMPONENT32F = 0x8CAC;
const GL_DEPTH32F_STENCIL8 = 0x8CAD;
const GL_RED = 0x1903;
const GL_RGBA = 0x1908;
const GL_DEPTH_COMPONENT = 0x1902;
const GL_DEPTH_STENCIL = 0x84F9;
const GL_UNSIGNED_BYTE = 0x1401;
const GL_UNSIGNED_SHORT = 0x1403;
const GL_UNSIGNED_INT = 0x1405;
const GL_FLOAT = 0x1406;
const GL_HALF_FLOAT = 0x140B;
const GL_FLOAT_32_UNSIGNED_INT_24_8_REV = 0x8DAD;
const GL_UNPACK_ALIGNMENT = 0x0CF5;
const GL_UNPACK_ROW_LENGTH = 0x0CF2;
const GL_UNPACK_IMAGE_HEIGHT = 0x806E;
const OGL_CAPABILITY_COMPUTE = 1;
const OGL_CAPABILITY_DEBUG = 2;
const OGL_CAPABILITY_TIMER = 4;
const OGL_CAPABILITY_EXACT_SAMPLES = 8;
const GL_TEXTURE_MAG_FILTER = 0x2800;
const GL_TEXTURE_MIN_FILTER = 0x2801;
const GL_TEXTURE_WRAP_S = 0x2802;
const GL_TEXTURE_WRAP_T = 0x2803;
const GL_TEXTURE_WRAP_R = 0x8072;
const GL_TEXTURE_MIN_LOD = 0x813A;
const GL_TEXTURE_MAX_LOD = 0x813B;
const GL_TEXTURE_COMPARE_MODE = 0x884C;
const GL_NEAREST = 0x2600;
const GL_LINEAR = 0x2601;
const GL_NEAREST_MIPMAP_NEAREST = 0x2700;
const GL_LINEAR_MIPMAP_NEAREST = 0x2701;
const GL_REPEAT = 0x2901;
const GL_CLAMP_TO_EDGE = 0x812F;
const GL_MIRRORED_REPEAT = 0x8370;
const GL_VERTEX_SHADER = 0x8B31;
const GL_FRAGMENT_SHADER = 0x8B30;
const GL_FRAMEBUFFER = 0x8D40;
const GL_READ_FRAMEBUFFER = 0x8CA8;
const GL_DRAW_FRAMEBUFFER = 0x8CA9;
const GL_COLOR_ATTACHMENT0 = 0x8CE0;
const GL_DEPTH_ATTACHMENT = 0x8D00;
const GL_DEPTH_STENCIL_ATTACHMENT = 0x821A;
const GL_FRAMEBUFFER_COMPLETE = 0x8CD5;
const GL_MAX_VERTEX_ATTRIBS = 0x8869;
const GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS = 0x8B4D;
const GL_MAJOR_VERSION = 0x821B;
const GL_MINOR_VERSION = 0x821C;
const GL_CURRENT_PROGRAM = 0x8B8D;
const GL_SHADER_STORAGE_BUFFER = 0x90D2;
const GL_COMPUTE_SHADER = 0x91B9;
const GL_READ_ONLY = 0x88B8;
const GL_WRITE_ONLY = 0x88B9;
const GL_READ_WRITE = 0x88BA;
const GL_SAMPLES_PASSED = 0x8914;
const GL_ANY_SAMPLES_PASSED = 0x8C2F;
const GL_MAX_TEXTURE_SIZE = 0x0D33;
const GL_MAX_3D_TEXTURE_SIZE = 0x8073;
const GL_MAX_ARRAY_TEXTURE_LAYERS = 0x88FF;
const GL_MAX_TEXTURE_IMAGE_UNITS = 0x8872;
const GL_MAX_VERTEX_UNIFORM_COMPONENTS = 0x8B4A;
const GL_MAX_FRAGMENT_UNIFORM_COMPONENTS = 0x8B49;
const GL_MAX_COLOR_ATTACHMENTS = 0x8CDF;
const GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS = 0x90DD;
const GL_MAX_COMPUTE_SHADER_STORAGE_BLOCKS = 0x90DB;
const GL_MAX_SHADER_STORAGE_BLOCK_SIZE = 0x90DE;
const GL_MAX_IMAGE_UNITS = 0x8F38;
const GL_MAX_COMPUTE_IMAGE_UNIFORMS = 0x91BD;
const GL_MAX_COMPUTE_WORK_GROUP_COUNT = 0x91BE;
const GL_MAX_COMPUTE_WORK_GROUP_SIZE = 0x91BF;
const GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS = 0x90EB;
const GL_BUFFER = 0x82E0;
const GL_PROGRAM = 0x82E2;
const GL_SAMPLER = 0x82E6;
const GL_TEXTURE = 0x1702;

enum ViewDimension {
	TwoD,
	TwoDArray,
	Cube,
	ThreeD,
}

struct FormatInfo {
	internalFormat: int32;
	pixelFormat: int32;
	pixelType: int32;
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
	integer: boolean;
	needsColorBufferFloat: boolean;
}

struct VertexFormatInfo {
	components: int32;
	componentType: int32;
	normalized: int32;
	integer: boolean;
}

struct BlendState {
	enabled: boolean;
	sourceColor: int32;
	destinationColor: int32;
	sourceAlpha: int32;
	destinationAlpha: int32;
	operationColor: int32;
	operationAlpha: int32;
}

struct StencilFace {
	compare: int32;
	failOp: int32;
	depthFailOp: int32;
	passOp: int32;
}

struct BufferSlot {
	id: uint32;
	size: int64;
	usage: int32;
	uniform: boolean;
	storage: boolean;
	mapRead: boolean;
	mapMode: int32;
	mapOffset: int64;
	mapSize: int64;
	target: int32;
	names: uint32[2];
	slotCount: int32;
	activeSlot: int32;
	shadow: Vec<uint8>;
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
	baseLevel: int32;
	maxLevel: int32;
	target: int32;
	names: uint32[2];
	slotCount: int32;
	activeSlot: int32;
	swapchainView: uint32;
}

struct ViewSlot {
	id: uint32;
	texture: uint32;
	sampled: boolean;
	color: boolean;
	depth: boolean;
	resolveFramebuffer: uint32;
	dimension: ViewDimension;
	baseMip: int32;
	mipCount: int32;
	baseLayer: int32;
	layerCount: int32;
	attachable: boolean;
	storage: boolean;
	swapchain: boolean;
}

struct SamplerSlot {
	id: uint32;
	native: uint32;
}

struct UniformBinding {
	binding: int32;
	size: int32;
	location: int32;
	count: int32;
}

struct TexturePair {
	samplerBinding: int32;
	textureBinding: int32;
	unit: int32;
}

struct ResourceBinding {
	binding: int32;
	kind: BindingKind;
	writable: boolean;
	nativeSlot: int32;
	access: int32;
	storageFormat: GPUTextureFormat;
}

struct ShaderSlot {
	readsInstanceIndex: boolean;
	id: uint32;
	program: uint32;
	uniforms: UniformBinding[8];
	uniformCount: int32;
	pairs: TexturePair[16];
	pairCount: int32;
	resources: ResourceBinding[24];
	resourceCount: int32;
	attributes: GPUShaderAttribute[16];
	compute: boolean;
	computeEntry: string;
	storageCount: int32;
	writes: boolean;
}

struct VertexAttribute {
	enabled: boolean;
	bufferSlot: int32;
	divisor: int32;
	stride: int32;
	offset: int32;
	size: int32;
	attributeType: int32;
	normalized: int32;
	integer: boolean;
}

struct PipelineSlot {
	label: string | null;
	readsInstanceIndex: boolean;
	id: uint32;
	shader: uint32;
	attributes: VertexAttribute[16];
	strides: int32[2];
	instanced: boolean;
	depthCompare: int32;
	depthWrite: boolean;
	depthBias: int32;
	depthSlope: float64;
	stencil: boolean;
	stencilReadMask: int32;
	stencilWriteMask: int32;
	stencilFront: StencilFace;
	stencilBack: StencilFace;
	colorCount: int32;
	blends: BlendState[4];
	writeMasks: int32[4];
	primitive: int32;
	stripRestart: boolean;
	stripIndexType: int32;
	cullFace: int32;
	frontFace: int32;
	sampleCount: int32;
	layouts: uint32[2];
	compute: boolean;
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

struct QuerySetSlot {
	id: uint32;
	timestamp: boolean;
	count: int32;
	names: Vec<uint32>;
	state: Vec<uint8>;
	usedPass: Vec<int64>;
}

struct ComputeState {
	active: boolean;
	labeled: boolean;
	groupBase: int32;
	timestampSet: uint32;
	timestampEnd: int32;
	pipeline: uint32;
	bindGroup: uint32;
	dirty: boolean;
	pendingBarrier: boolean;
}

struct PassState {
	active: boolean;
	serial: int64;
	labeled: boolean;
	groupBase: int32;
	timestampSet: uint32;
	timestampEnd: int32;
	occlusionSet: uint32;
	occlusionOpen: boolean;
	occlusionIndex: int32;
	swapchain: boolean;
	width: int32;
	height: int32;
	colorViews: uint32[4];
	resolveViews: uint32[4];
	colorSlices: int32[4];
}

struct BoundState {
	pipeline: uint32;
	appliedPipeline: uint32;
	instanced: boolean;
	vertexBuffers: uint32[2];
	vertexOffsets: int64[2];
	indexBuffer: uint32;
	indexType: int32;
	indexSize: int32;
	indexOffset: int64;
	stencilReference: int32;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[8];
	vertexDirty: boolean;
	indexDirty: boolean;
	resourcesDirty: boolean;
	uniformsDirty: boolean;
}

struct CachedAttribute {
	enabled: boolean;
	buffer: uint32;
	size: int32;
	attributeType: int32;
	normalized: int32;
	integer: boolean;
	stride: int32;
	offset: int64;
	divisor: int32;
}

struct CachedUnit {
	target: int32;
	texture: uint32;
	sampler: uint32;
}

struct StateCache {
	program: uint32;
	vertexBuffer: uint32;
	indexBuffer: uint32;
	storedVertexBuffer: uint32;
	storedIndexBuffer: uint32;
	activeTexture: int32;
	storedUnit: CachedUnit;
	depthCompare: int32;
	depthWrite: boolean;
	stencilMask: int32;
	stencilEnabled: boolean;
	blends: BlendState[4];
	blendConstantSet: boolean;
	depthRangeSet: boolean;
	primitiveRestart: boolean;
	polygonOffset: boolean;
	offsetFactor: float64;
	offsetUnits: float64;
	writeMasks: int32[4];
	cullFace: int32;
	frontFace: int32;
	sampleCount: int32;
	unpackRowLength: int32;
	unpackImageHeight: int32;
}

let frame: int64 = 0;
let pass: PassState = { active: false };
let bound: BoundState = { pipeline: 0 };
let computeBound: ComputeState = { active: false };
let passSerial: int64 = 0;
let groupDepth: int32 = 0;
let contextVersion: int32 = 0;
let computeSupported = false;
let debugSupported = false;
let timerSupported = false;
let exactSamples = false;
let maxStorageBindings: int32 = 0;
let maxImageUnits: int32 = 0;
let deviceLimits: GPUSupportedLimits = { maxBindGroups: 0 };
let deviceFeatures: GPUSupportedFeatures = { bits: 0 };
export struct BindStats {
	vertexBuffers: int64;
	indexBuffers: int64;
	shaderResources: int64;
	samplers: int64;
}

let stats: BindStats = { vertexBuffers: 0 };
export function bindStats(): BindStats { return stats; }

let cache: StateCache = { program: 0 };
let cachedAttributes: Vec<CachedAttribute> = [];
let cachedUnits: Vec<CachedUnit> = [];
let vertexArray: uint32 = 0;
let dummySampler: uint32 = 0;
let framebuffer: uint32 = 0;
let readFramebuffer: uint32 = 0;
let maxVertexAttributes: int32 = 0;
let maxTextureUnits: int32 = 0;
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 };

let buffers: Pool<BufferSlot> = newPool<BufferSlot>("gl", "GPUBuffer", "buffer", { id: 0 });
let textures: Pool<TextureSlot> = newPool<TextureSlot>("gl", "GPUTexture", "texture", { id: 0 });
let views: Pool<ViewSlot> = newPool<ViewSlot>("gl", "GPUTextureView", "view", { id: 0 });
let samplers: Pool<SamplerSlot> = newPool<SamplerSlot>("gl", "GPUSampler", "sampler", { id: 0 });
let shaders: Pool<ShaderSlot> = newPool<ShaderSlot>("gl", "GPUShaderModule", "shader module", { id: 0 });
let pipelines: Pool<PipelineSlot> = newPool<PipelineSlot>("gl", "GPURenderPipeline", "render or compute pipeline", { id: 0 });
let layouts: Pool<LayoutSlot> = newPool<LayoutSlot>("gl", "GPUBindGroupLayout", "bind group layout", { id: 0 });
let bindGroups: Pool<BindGroupSlot> = newPool<BindGroupSlot>("gl", "GPUBindGroup", "bind group", { id: 0 });
let querySets: Pool<QuerySetSlot> = newPool<QuerySetSlot>("gl", "GPUQuerySet", "query set", { id: 0 });

@noinline function stop(message: string): never {
	console.log(`webgpu gl: ${message}`);
	unreachable;
}

@noinline function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu gl: ${member} '${value}' is not supported`);
	unreachable;
}

@noinline function stopOnVertexFormat(value: string): VertexFormatInfo {
	console.log(`webgpu gl: vertex attribute format '${value}' is not supported`);
	unreachable;
}

@noinline function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu gl: ${member} '${value}' is not supported`);
	unreachable;
}

function nativeNameOf(name: string | null, what: string): string {
	if (name !== null) { return name; }
	stop(`${what} needs its GLSL name in nativeName`);
}

function checkError(what: string): void {
	const error = oglGetError();
	if (error != 0) { stop(`${what} raised GL error 0x${error.toString(16)}`); }
}

function checkErrorOf(what: string, label: string | null): void {
	const error = oglGetError();
	if (error != 0) { stop(`${what} of ${labelOf(label)} raised GL error 0x${error.toString(16)}`); }
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

@inline function roundUp16(bytes: int64): int64 { return (bytes + 15) & ~(15 as int64); }

@inline function smaller(a: int32, b: int32): int32 { return a < b ? a : b; }

function colorFormat(
	internalFormat: int32,
	pixelFormat: int32,
	pixelType: int32,
	bytesPerPixel: int32,
	integer: boolean,
	needsColorBufferFloat: boolean,
): FormatInfo {
	return {
		internalFormat: internalFormat,
		pixelFormat: pixelFormat,
		pixelType: pixelType,
		bytesPerPixel: bytesPerPixel,
		depth: false,
		stencil: false,
		integer: integer,
		needsColorBufferFloat: needsColorBufferFloat,
	};
}

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => colorFormat(GL_R8, GL_RED, GL_UNSIGNED_BYTE, 1, false, false),
		"rg8unorm" => colorFormat(GL_RG8, GL_RG, GL_UNSIGNED_BYTE, 2, false, false),
		"rgba8unorm" => colorFormat(GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, 4, false, false),
		"rgba8unorm-srgb" => colorFormat(GL_SRGB8_ALPHA8, GL_RGBA, GL_UNSIGNED_BYTE, 4, false, false),
		"rgba8uint" => colorFormat(GL_RGBA8UI, GL_RGBA_INTEGER, GL_UNSIGNED_BYTE, 4, true, false),
		"rgba8sint" => colorFormat(GL_RGBA8I, GL_RGBA_INTEGER, GL_BYTE, 4, true, false),
		"r16float" => colorFormat(GL_R16F, GL_RED, GL_HALF_FLOAT, 2, false, false),
		"rg16float" => colorFormat(GL_RG16F, GL_RG, GL_HALF_FLOAT, 4, false, false),
		"rgba16float" => colorFormat(GL_RGBA16F, GL_RGBA, GL_HALF_FLOAT, 8, false, false),
		"rgba16uint" => colorFormat(GL_RGBA16UI, GL_RGBA_INTEGER, GL_UNSIGNED_SHORT, 8, true, false),
		"r32float" => colorFormat(GL_R32F, GL_RED, GL_FLOAT, 4, false, true),
		"rg32float" => colorFormat(GL_RG32F, GL_RG, GL_FLOAT, 8, false, true),
		"rgba32float" => colorFormat(GL_RGBA32F, GL_RGBA, GL_FLOAT, 16, false, true),
		"rgba32uint" => colorFormat(GL_RGBA32UI, GL_RGBA_INTEGER, GL_UNSIGNED_INT, 16, true, false),
		"r32uint" => colorFormat(GL_R32UI, GL_RED_INTEGER, GL_UNSIGNED_INT, 4, true, false),
		"rgb10a2unorm" => colorFormat(GL_RGB10_A2, GL_RGBA, GL_UNSIGNED_INT_2_10_10_10_REV, 4, false, false),
		"rg11b10ufloat" => colorFormat(GL_R11F_G11F_B10F, GL_RGB, GL_UNSIGNED_INT_10F_11F_11F_REV, 4, false, true),
		"depth16unorm" => ({
			internalFormat: GL_DEPTH_COMPONENT16,
			pixelFormat: GL_DEPTH_COMPONENT,
			pixelType: GL_UNSIGNED_SHORT,
			bytesPerPixel: 2,
			depth: true,
			stencil: false,
		}),
		"depth32float" => ({
			internalFormat: GL_DEPTH_COMPONENT32F,
			pixelFormat: GL_DEPTH_COMPONENT,
			pixelType: GL_FLOAT,
			bytesPerPixel: 4,
			depth: true,
			stencil: false,
		}),
		"depth24plus-stencil8" => ({
			internalFormat: GL_DEPTH32F_STENCIL8,
			pixelFormat: GL_DEPTH_STENCIL,
			pixelType: GL_FLOAT_32_UNSIGNED_INT_24_8_REV,
			bytesPerPixel: 8,
			depth: true,
			stencil: true,
		}),
		_ => stopOnFormat(member, value),
	};
}

function compareFunction(compare: string, member: string): int32 {
	return match (compare) {
		"never" => GL_NEVER,
		"less" => GL_LESS,
		"equal" => GL_EQUAL,
		"less-equal" => GL_LEQUAL,
		"greater" => GL_GREATER,
		"not-equal" => GL_NOTEQUAL,
		"greater-equal" => GL_GEQUAL,
		"" | "always" => GL_ALWAYS,
		_ => stopOnMember(member, compare),
	};
}

function cullFace(cull: string): int32 {
	return match (cull) {
		"" | "none" => 0,
		"front" => GL_FRONT,
		"back" => GL_BACK,
		_ => stopOnMember("primitive.cullMode", cull),
	};
}

function frontFace(face: string): int32 {
	return match (face) {
		"" | "ccw" => GL_CCW,
		"cw" => GL_CW,
		_ => stopOnMember("primitive.frontFace", face),
	};
}

function blendFactor(factor: string, member: string): int32 {
	return match (factor) {
		"zero" => GL_ZERO,
		"" | "one" => GL_ONE,
		"src" => GL_SRC_COLOR,
		"one-minus-src" => GL_ONE_MINUS_SRC_COLOR,
		"src-alpha" => GL_SRC_ALPHA,
		"one-minus-src-alpha" => GL_ONE_MINUS_SRC_ALPHA,
		"dst" => GL_DST_COLOR,
		"one-minus-dst" => GL_ONE_MINUS_DST_COLOR,
		"dst-alpha" => GL_DST_ALPHA,
		"one-minus-dst-alpha" => GL_ONE_MINUS_DST_ALPHA,
		"src-alpha-saturated" => GL_SRC_ALPHA_SATURATE,
		"constant" => GL_CONSTANT_COLOR,
		"one-minus-constant" => GL_ONE_MINUS_CONSTANT_COLOR,
		_ => stopOnMember(member, factor),
	};
}

function destinationFactor(factor: string, member: string): int32 {
	if (factor == "") { return GL_ZERO; }
	return blendFactor(factor, member);
}

function blendOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "add" => GL_FUNC_ADD,
		"subtract" => GL_FUNC_SUBTRACT,
		"reverse-subtract" => GL_FUNC_REVERSE_SUBTRACT,
		"min" => GL_MIN,
		"max" => GL_MAX,
		_ => stopOnMember(member, operation),
	};
}

function vertexFormat(components: int32, componentType: int32, normalized: int32, integer: boolean): VertexFormatInfo {
	return { components: components, componentType: componentType, normalized: normalized, integer: integer };
}

function vertexFormatInfo(format: string): VertexFormatInfo {
	return match (format) {
		"float32" => vertexFormat(1, GL_FLOAT, 0, false),
		"float32x2" => vertexFormat(2, GL_FLOAT, 0, false),
		"float32x3" => vertexFormat(3, GL_FLOAT, 0, false),
		"float32x4" => vertexFormat(4, GL_FLOAT, 0, false),
		"float16x2" => vertexFormat(2, GL_HALF_FLOAT, 0, false),
		"float16x4" => vertexFormat(4, GL_HALF_FLOAT, 0, false),
		"uint32" => vertexFormat(1, GL_UNSIGNED_INT, 0, true),
		"uint32x2" => vertexFormat(2, GL_UNSIGNED_INT, 0, true),
		"uint32x3" => vertexFormat(3, GL_UNSIGNED_INT, 0, true),
		"uint32x4" => vertexFormat(4, GL_UNSIGNED_INT, 0, true),
		"sint32" => vertexFormat(1, GL_INT, 0, true),
		"sint32x2" => vertexFormat(2, GL_INT, 0, true),
		"sint32x3" => vertexFormat(3, GL_INT, 0, true),
		"sint32x4" => vertexFormat(4, GL_INT, 0, true),
		"uint8x2" => vertexFormat(2, GL_UNSIGNED_BYTE, 0, true),
		"uint8x4" => vertexFormat(4, GL_UNSIGNED_BYTE, 0, true),
		"sint8x2" => vertexFormat(2, GL_BYTE, 0, true),
		"sint8x4" => vertexFormat(4, GL_BYTE, 0, true),
		"unorm8x2" => vertexFormat(2, GL_UNSIGNED_BYTE, 1, false),
		"unorm8x4" => vertexFormat(4, GL_UNSIGNED_BYTE, 1, false),
		"snorm8x2" => vertexFormat(2, GL_BYTE, 1, false),
		"snorm8x4" => vertexFormat(4, GL_BYTE, 1, false),
		"uint16x2" => vertexFormat(2, GL_UNSIGNED_SHORT, 0, true),
		"uint16x4" => vertexFormat(4, GL_UNSIGNED_SHORT, 0, true),
		"sint16x2" => vertexFormat(2, GL_SHORT, 0, true),
		"sint16x4" => vertexFormat(4, GL_SHORT, 0, true),
		"unorm16x2" => vertexFormat(2, GL_UNSIGNED_SHORT, 1, false),
		"unorm16x4" => vertexFormat(4, GL_UNSIGNED_SHORT, 1, false),
		"snorm16x2" => vertexFormat(2, GL_SHORT, 1, false),
		"snorm16x4" => vertexFormat(4, GL_SHORT, 1, false),
		_ => stopOnVertexFormat(format),
	};
}

function primitiveMode(topology: string): int32 {
	return match (topology) {
		"point-list" => GL_POINTS,
		"line-list" => GL_LINES,
		"line-strip" => GL_LINE_STRIP,
		"" | "triangle-list" => GL_TRIANGLES,
		"triangle-strip" => GL_TRIANGLE_STRIP,
		_ => stopOnMember("primitive.topology", topology),
	};
}

function stencilOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "keep" => GL_KEEP,
		"zero" => GL_ZERO,
		"replace" => GL_REPLACE,
		"invert" => GL_INVERT,
		"increment-clamp" => GL_INCR,
		"decrement-clamp" => GL_DECR,
		"increment-wrap" => GL_INCR_WRAP,
		"decrement-wrap" => GL_DECR_WRAP,
		_ => stopOnMember(member, operation),
	};
}

function stencilFace(face: GPUStencilFaceState, member: string): StencilFace {
	return {
		compare: compareFunction(face.compare, `${member}.compare`),
		failOp: stencilOperation(face.failOp, `${member}.failOp`),
		depthFailOp: stencilOperation(face.depthFailOp, `${member}.depthFailOp`),
		passOp: stencilOperation(face.passOp, `${member}.passOp`),
	};
}

function addressMode(mode: string, member: string): int32 {
	return match (mode) {
		"" | "clamp-to-edge" => GL_CLAMP_TO_EDGE,
		"repeat" => GL_REPEAT,
		"mirror-repeat" => GL_MIRRORED_REPEAT,
		_ => stopOnMember(member, mode),
	};
}

function cacheBindBuffer(target: int32, name: uint32): void {
	if (target == GL_ARRAY_BUFFER) {
		if (cache.vertexBuffer != name) {
			cache.vertexBuffer = name;
			oglBindBuffer(target, name);
		}
	} else if (cache.indexBuffer != name) {
		cache.indexBuffer = name;
		oglBindBuffer(target, name);
		stats.indexBuffers += 1;
	}
}

function cacheStoreBuffer(target: int32): void {
	if (target == GL_ARRAY_BUFFER) {
		cache.storedVertexBuffer = cache.vertexBuffer;
	} else {
		cache.storedIndexBuffer = cache.indexBuffer;
	}
}

function cacheRestoreBuffer(target: int32): void {
	if (target == GL_ARRAY_BUFFER) {
		if (cache.storedVertexBuffer != 0) {
			cacheBindBuffer(target, cache.storedVertexBuffer);
			cache.storedVertexBuffer = 0;
		}
	} else if (cache.storedIndexBuffer != 0) {
		cacheBindBuffer(target, cache.storedIndexBuffer);
		cache.storedIndexBuffer = 0;
	}
}

function cacheClearBuffers(force: boolean): void {
	if (force || cache.vertexBuffer != 0) {
		oglBindBuffer(GL_ARRAY_BUFFER, 0);
		cache.vertexBuffer = 0;
	}
	if (force || cache.indexBuffer != 0) {
		oglBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
		cache.indexBuffer = 0;
	}
}

function cacheInvalidateBuffer(name: uint32): void {
	if (name == cache.vertexBuffer) {
		cache.vertexBuffer = 0;
		oglBindBuffer(GL_ARRAY_BUFFER, 0);
	}
	if (name == cache.indexBuffer) {
		cache.indexBuffer = 0;
		oglBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
	}
	if (name == cache.storedVertexBuffer) { cache.storedVertexBuffer = 0; }
	if (name == cache.storedIndexBuffer) { cache.storedIndexBuffer = 0; }
	for (let i = 0; i < cachedAttributes.length; i++) {
		if (cachedAttributes[i].buffer == name) { cachedAttributes[i].buffer = 0; }
	}
}

function cacheUnpack(target: int32, rowLength: int32, imageHeight: int32): void {
	if (cache.unpackRowLength != rowLength) {
		cache.unpackRowLength = rowLength;
		oglPixelStore(GL_UNPACK_ROW_LENGTH, rowLength);
	}
	if ((target == GL_TEXTURE_3D || target == GL_TEXTURE_2D_ARRAY) && cache.unpackImageHeight != imageHeight) {
		cache.unpackImageHeight = imageHeight;
		oglPixelStore(GL_UNPACK_IMAGE_HEIGHT, imageHeight);
	}
}

function cacheActiveTexture(unit: int32): void {
	if (cache.activeTexture != unit) {
		cache.activeTexture = unit;
		oglActiveTexture(unit);
	}
}

function cacheClearUnits(force: boolean): void {
	for (let i = 0; i < maxTextureUnits; i++) {
		if (force || cachedUnits[i].texture != 0) {
			oglActiveTexture(i);
			oglBindTexture(GL_TEXTURE_2D, 0);
			oglBindTexture(GL_TEXTURE_CUBE_MAP, 0);
			oglBindTexture(GL_TEXTURE_2D_ARRAY, 0);
			oglBindTexture(GL_TEXTURE_3D, 0);
			unbindMultisampleTexture();
			oglBindSampler(i, 0);
			cachedUnits[i] = { target: 0, texture: 0, sampler: 0 };
			cache.activeTexture = i;
		}
	}
}

function cacheBindTextureSampler(unit: int32, target: int32, texture: uint32, sampler: uint32): void {
	if (unit >= maxTextureUnits) { return; }
	const slot = cachedUnits[unit];
	if (slot.target != target || slot.texture != texture || slot.sampler != sampler) {
		cacheActiveTexture(unit);
		if (target != slot.target && slot.target != 0) { oglBindTexture(slot.target, 0); }
		if (target != 0) {
			oglBindTexture(target, texture);
			stats.shaderResources += 1;
		}
		oglBindSampler(unit, sampler);
		stats.samplers += 1;
		cachedUnits[unit] = { target: target, texture: texture, sampler: sampler };
	}
}

function cacheStoreUnit0(): void { cache.storedUnit = cachedUnits[0]; }

function cacheRestoreUnit0(): void {
	const stored = cache.storedUnit;
	if (stored.texture != 0) {
		cacheBindTextureSampler(0, stored.target, stored.texture, stored.sampler);
		cache.storedUnit = { target: 0, texture: 0, sampler: 0 };
	}
}

function cacheInvalidateTextureSampler(texture: uint32, sampler: uint32): void {
	for (let i = 0; i < maxTextureUnits; i++) {
		const slot = cachedUnits[i];
		const matches = (texture != 0 && slot.texture == texture) || (sampler != 0 && slot.sampler == sampler);
		if (slot.target != 0 && matches) {
			cacheActiveTexture(i);
			oglBindTexture(slot.target, 0);
			oglBindSampler(i, 0);
			cachedUnits[i] = { target: 0, texture: 0, sampler: 0 };
		}
	}
	const stored = cache.storedUnit;
	if ((texture != 0 && stored.texture == texture) || (sampler != 0 && stored.sampler == sampler)) {
		cache.storedUnit = { target: 0, texture: 0, sampler: 0 };
	}
}

function cacheInvalidateProgram(program: uint32): void {
	if (program == cache.program) {
		cache.program = 0;
		oglUseProgram(0);
	}
}

function defaultBlend(): BlendState {
	return {
		enabled: false,
		sourceColor: GL_ONE,
		destinationColor: GL_ZERO,
		sourceAlpha: GL_ONE,
		destinationAlpha: GL_ZERO,
		operationColor: GL_FUNC_ADD,
		operationAlpha: GL_FUNC_ADD,
	};
}

function resetStateCache(): void {
	oglBindVertexArray(vertexArray);
	cache = { program: 0 };
	cachedAttributes = [];
	cachedUnits = [];
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) { cachedAttributes.push({ enabled: false, divisor: -1 }); }
	for (let i = 0; i < MAX_TEXTURE_UNITS; i++) { cachedUnits.push({ target: 0 }); }
	cacheClearBuffers(true);
	cacheClearUnits(true);
	for (let i = 0; i < maxVertexAttributes; i++) { oglDisableVertexAttribArray(i); }
	cache.program = oglGetInteger(GL_CURRENT_PROGRAM) as uint32;
	cache.depthCompare = GL_ALWAYS;
	cache.depthWrite = false;
	oglEnable(GL_DEPTH_TEST);
	oglDepthFunc(GL_ALWAYS);
	oglDepthMask(0);
	oglDisable(GL_STENCIL_TEST);
	oglStencilFunc(GL_ALWAYS, 0, 0);
	oglStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
	oglStencilMask(0);
	cache.stencilMask = 0;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) { cache.blends[i] = defaultBlend(); }
	oglDisable(GL_BLEND);
	oglBlendFuncSeparate(GL_ONE, GL_ZERO, GL_ONE, GL_ZERO);
	oglBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
	oglBlendColor(0, 0, 0, 0);
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) { cache.writeMasks[i] = COLOR_WRITE_ALL; }
	cache.cullFace = 0;
	cache.frontFace = GL_CW;
	cache.sampleCount = 1;
	oglPixelStore(GL_UNPACK_ROW_LENGTH, 0);
	oglPixelStore(GL_UNPACK_IMAGE_HEIGHT, 0);
	oglColorMask(COLOR_WRITE_ALL);
	oglPolygonOffset(0, 0);
	oglDisable(GL_POLYGON_OFFSET_FILL);
	setPrimitiveRestart(false);
	oglDepthRange(0, 1);
	oglDisable(GL_CULL_FACE);
	oglFrontFace(GL_CW);
	oglCullFace(GL_BACK);
	oglEnable(GL_SCISSOR_TEST);
	oglDisable(GL_SAMPLE_ALPHA_TO_COVERAGE);
	oglEnable(GL_DITHER);
	resetDesktopState();
}

function checkMirroredConstants(): void {
	const values: int32[] = [
		OGL_CAPABILITY_COMPUTE,
		OGL_CAPABILITY_DEBUG,
		OGL_CAPABILITY_TIMER,
		OGL_CAPABILITY_EXACT_SAMPLES,
		GL_TEXTURE_3D,
		GL_TEXTURE_2D_ARRAY,
		GL_TEXTURE_CUBE_MAP,
		GL_TEXTURE_CUBE_MAP_POSITIVE_X,
		GL_BACK,
		GL_TEXTURE_2D,
		GL_RENDERBUFFER,
		GL_DEPTH_COMPONENT,
		GL_DEPTH_STENCIL,
		GL_UNPACK_ROW_LENGTH,
		GL_UNPACK_IMAGE_HEIGHT,
		GL_NEAREST,
		GL_FRAMEBUFFER,
		GL_READ_FRAMEBUFFER,
		GL_DRAW_FRAMEBUFFER,
		GL_COLOR_ATTACHMENT0,
		GL_DEPTH_ATTACHMENT,
		GL_FRAMEBUFFER_COMPLETE,
	];
	const disagreement: string = oglConstantsDisagreement(values[0], values.length as int32);
	if (disagreement != "") { stop(`a constant of backend.ms disagrees with gl.c, ${disagreement}`); }
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (oglLoad() == 0) {
		const missing: string = oglLoadMissing();
		stop(`requestDevice needs a current GL context; ${missing} did not load`);
	}
	checkMirroredConstants();
	const version = oglGetInteger(GL_MAJOR_VERSION) * 100 + oglGetInteger(GL_MINOR_VERSION) * 10;
	checkContextVersion(version);
	maxVertexAttributes = smaller(oglGetInteger(GL_MAX_VERTEX_ATTRIBS), GPU_MAX_VERTEX_ATTRIBUTES);
	maxTextureUnits = smaller(oglGetInteger(GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS), MAX_TEXTURE_UNITS);
	contextVersion = version;
	const capabilities = oglCapabilities();
	computeSupported = (capabilities & OGL_CAPABILITY_COMPUTE) != 0 && version >= COMPUTE_CONTEXT_VERSION;
	debugSupported = (capabilities & OGL_CAPABILITY_DEBUG) != 0 && version >= DEBUG_CONTEXT_VERSION;
	timerSupported = (capabilities & OGL_CAPABILITY_TIMER) != 0 && oglQueryCounterBits() > 0;
	exactSamples = (capabilities & OGL_CAPABILITY_EXACT_SAMPLES) != 0;
	deviceLimits = queryLimits();
	deviceFeatures = queryFeatures();
	vertexArray = oglCreateVertexArray();
	oglBindVertexArray(vertexArray);
	framebuffer = oglCreateFramebuffer();
	readFramebuffer = oglCreateFramebuffer();
	dummySampler = oglCreateSampler();
	oglSamplerParameteri(dummySampler, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	oglSamplerParameteri(dummySampler, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	oglSamplerParameteri(dummySampler, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	oglSamplerParameteri(dummySampler, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	oglSamplerParameteri(dummySampler, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
	oglPixelStore(GL_UNPACK_ALIGNMENT, 1);
	enableSeamlessCubemaps();
	resetStateCache();
	checkError("setup");
	frame = 0;
	pass = { active: false };
	bound = { pipeline: 0 };
	computeBound = { active: false };
	passSerial = 0;
	groupDepth = 0;
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
	textures.slots[textures.slotIndex(swapchainColor)].usage |= GPUTextureUsage.COPY_SRC as int32;
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
	return {
		format: environment.colorFormat,
		depthFormat: environment.depthFormat,
		sampleCount: environment.sampleCount == 0 ? 1 : environment.sampleCount,
	};
}

export function canvasConfiguration(): GPUCanvasConfiguration { return canvas; }

export function formatRenderable(format: GPUTextureFormat): boolean {
	const value: string = format;
	if (value == "bgra8unorm" || value == "bgra8unorm-srgb") { return false; }
	const info = formatInfo(format, "formatRenderable format");
	return !info.integer && !lacksColorBufferFloat(info);
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
	const info = formatInfo(format, "canvas format");
	store(textures, {
		id: textureId,
		format: format,
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		mipLevels: 1,
		layers: 1,
		swapchainView: viewId,
	});
	store(views, {
		id: viewId,
		texture: textureId,
		color: !info.depth,
		depth: info.depth,
		attachable: true,
		swapchain: true,
	});
	return textureId;
}

export function shutdown(): void {
	if (pass.active) { stop("shutdown with a render pass still open"); }
	if (computeBound.active) { stop("shutdown with a compute pass still open"); }
	for (const id of querySets.liveIds()) { destroyQuerySet({ id: id }); }
	for (const id of bindGroups.liveIds()) { destroyBindGroup({ id: id }); }
	for (const id of pipelines.liveIds()) { destroyRenderPipeline({ id: id }); }
	for (const id of shaders.liveIds()) { destroyShaderModule({ id: id }); }
	for (const id of samplers.liveIds()) { destroySampler({ id: id }); }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { destroyView({ id: id }); } }
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { destroyTexture({ id: id }); } }
	for (const id of buffers.liveIds()) { destroyBuffer({ id: id }); }
	cacheInvalidateTextureSampler(0, dummySampler);
	oglDeleteSampler(dummySampler);
	dummySampler = 0;
	oglDeleteFramebuffer(framebuffer);
	oglDeleteFramebuffer(readFramebuffer);
	oglDeleteVertexArray(vertexArray);
	framebuffer = 0;
	readFramebuffer = 0;
	vertexArray = 0;
	oglUnload();
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(bindGroups);
	reset(querySets);
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "glcore", originTopLeft: false, depthZeroToOne: false };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocate(buffers);
	const usage = descriptor.usage;
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
	const storage = has(usage, GPUBufferUsage.STORAGE as int32);
	const indirect = has(usage, GPUBufferUsage.INDIRECT as int32);
	const resolve = has(usage, GPUBufferUsage.QUERY_RESOLVE as int32);
	if (storage) { stopOnNoCompute("GPUBufferUsage.STORAGE"); }
	if (indirect) { stopOnNoCompute("GPUBufferUsage.INDIRECT"); }
	const mapRead = has(usage, GPUBufferUsage.MAP_READ as int32);
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
	checkedBufferUsage(usage);
	const vertexOrIndex = (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.INDEX as int32);
	const uniform = has(usage, GPUBufferUsage.UNIFORM as int32);
	if (uniform && has(usage, vertexOrIndex)) {
		stop("a UNIFORM buffer is a CPU shadow on GL and cannot also be VERTEX or INDEX");
	}
	if ((storage || indirect) && (uniform || has(usage, vertexOrIndex))) {
		stop("a STORAGE or INDIRECT buffer cannot also be UNIFORM, VERTEX or INDEX on GL");
	}
	if (resolve && (uniform || has(usage, vertexOrIndex))) {
		stop("a QUERY_RESOLVE buffer cannot also be UNIFORM, VERTEX or INDEX on GL");
	}
	if (storage && descriptor.size > deviceLimits.maxStorageBufferBindingSize) {
		stop(`a STORAGE buffer of ${descriptor.size} bytes is over the limit of ${deviceLimits.maxStorageBufferBindingSize}`);
	}
	if (storage && descriptor.size % 4 != 0) { stop("a STORAGE buffer takes a size that is a multiple of 4"); }
	when (webgl2) {
		if ((usage & vertexOrIndex) == vertexOrIndex) { stop("WebGL2 binds a buffer as VERTEX or as INDEX, not both"); }
	}
	const writable = has(usage, GPUBufferUsage.COPY_DST as int32);
	let slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		usage: usage,
		uniform: uniform,
		storage: storage,
		mapRead: mapRead,
		target: has(usage, GPUBufferUsage.INDEX as int32) ? GL_ELEMENT_ARRAY_BUFFER : GL_ARRAY_BUFFER,
		slotCount: writable && !mapRead && !storage && !indirect && !resolve ? INFLIGHT_SLOTS : 1,
		activeSlot: 0,
		writtenFrame: writable ? -1 : -2,
		writtenEnd: 0,
	};
	if (uniform) {
		slot.shadow = new Array(roundUp16(descriptor.size));
	} else {
		if (mapRead) { slot.shadow = new Array(descriptor.size); }
		for (let s = 0; s < slot.slotCount; s++) {
			const name = oglCreateBuffer();
			slot.names[s] = name;
			cacheStoreBuffer(slot.target);
			cacheBindBuffer(slot.target, name);
			oglBufferData(slot.target, descriptor.size, mapRead ? GL_STREAM_READ : (writable || storage || resolve ? GL_DYNAMIC_DRAW : GL_STATIC_DRAW));
			cacheRestoreBuffer(slot.target);
			nameObject(GL_BUFFER, name, descriptor.label);
		}
		checkErrorOf("createBuffer", descriptor.label);
	}
	store(buffers, slot);
	return { id: id };
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	if (!buffers.slots[index].uniform) {
		for (let s = 0; s < buffers.slots[index].slotCount; s++) {
			cacheInvalidateBuffer(buffers.slots[index].names[s]);
			oglDeleteBuffer(buffers.slots[index].names[s]);
		}
	}
	buffers.slots[index] = { id: 0 };
	release(buffers, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers.slots[buffers.slotIndex(buffer.id)].size; }

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = writableBuffer(buffer.id, offset, bytes);
	claimBufferWrite(index, offset, bytes, "writeBuffer");
	if (buffers.slots[index].uniform) {
		oglCopyBytes(buffers.slots[index].shadow[0], offset, data[0], bytes);
		bound.uniformsDirty = true;
		return;
	}
	const target = buffers.slots[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, buffers.slots[index].names[buffers.slots[index].activeSlot]);
	oglBufferSubData(target, offset, data[0], bytes);
	cacheRestoreBuffer(target);
}

function claimBufferWrite(index: int32, offset: int64, bytes: int64, member: string): void {
	if (buffers.slots[index].writtenFrame == -2) { stop(`GPUBuffer ${buffers.slots[index].id} was created without COPY_DST`); }
	if (buffers.slots[index].mapRead) { return; }
	const fresh = buffers.slots[index].writtenFrame != frame;
	if (!fresh && offset < buffers.slots[index].writtenEnd) {
		stop(`${member} at ${offset} on GPUBuffer ${buffers.slots[index].id} rewrites bytes this frame already wrote, up to ${buffers.slots[index].writtenEnd}`);
	}
	buffers.slots[index].writtenFrame = frame;
	buffers.slots[index].writtenEnd = offset + bytes;
	if (fresh && !buffers.slots[index].uniform) {
		buffers.slots[index].activeSlot = (buffers.slots[index].activeSlot + 1) % buffers.slots[index].slotCount;
		bound.vertexDirty = true;
		bound.indexDirty = true;
	}
}

function writableBuffer(id: uint32, offset: int64, bytes: int64): int32 {
	const index = buffers.slotIndex(id);
	checkedWriteBuffer(id, buffers.slots[index].size, offset, bytes);
	return index;
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
	const sideLimit = volume ? deviceLimits.maxTextureDimension3D : deviceLimits.maxTextureDimension2D;
	if (largestSide > sideLimit || (!volume && layers > deviceLimits.maxTextureArrayLayers)) {
		stop(`GPUTextureDescriptor.size ${width}x${height}x${layers} is over the limits ${sideLimit} per side and ${deviceLimits.maxTextureArrayLayers} array layers`);
	}
	const mipLevels = checkedMipLevelCount(descriptor, volume, layers);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	checkedMultisample(sampleCount, volume, layers, mipLevels, attachment);
	const copyDestination = has(usage, GPUTextureUsage.COPY_DST as int32);
	if (attachment && copyDestination) {
		stop("COPY_DST with RENDER_ATTACHMENT: a written texture rotates in-flight copies, which an attachment cannot");
	}
	const storage = has(usage, GPUTextureUsage.STORAGE_BINDING as int32);
	if (storage) {
		stopOnNoCompute("GPUTextureUsage.STORAGE_BINDING");
		if (info.depth || info.internalFormat == GL_SRGB8_ALPHA8 || sampleCount > 1) {
			stop("STORAGE_BINDING needs a single-sample color format that is not sRGB on gl");
		}
	}
	if (volume && info.depth) { stop("WebGPU allows a depth or stencil format only on a 2d texture"); }
	if (attachment && info.integer) {
		stop(`${descriptor.format} as RENDER_ATTACHMENT is not ported to gl: clearing an integer target needs glClearBufferuiv or glClearBufferiv`);
	}
	if (attachment && lacksColorBufferFloat(info)) {
		stop(`${descriptor.format} as RENDER_ATTACHMENT needs EXT_color_buffer_float, which the GLES backend does not query yet`);
	}
	const cube = !volume && layers == 6 && width == height && has(usage, GPUTextureUsage.TEXTURE_BINDING as int32) && sampleCount == 1;
	let target = GL_TEXTURE_2D;
	if (volume) {
		target = GL_TEXTURE_3D;
	} else if (cube) {
		target = GL_TEXTURE_CUBE_MAP;
	} else if (layers > 1) {
		target = GL_TEXTURE_2D_ARRAY;
	} else if (sampleCount > 1) {
		target = multisampleTarget();
	}
	const rotates = copyDestination && mipLevels == 1 && layers == 1 && !volume && !storage;
	let slot: TextureSlot = {
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
		baseLevel: 0,
		maxLevel: mipLevels - 1,
		target: target,
		slotCount: rotates ? INFLIGHT_SLOTS : 1,
		activeSlot: 0,
		swapchainView: 0,
	};
	if (slot.target == GL_RENDERBUFFER) {
		slot.names[0] = oglCreateRenderbufferUncached(sampleCount, info.internalFormat, width, height);
	}
	for (let s = 0; s < slot.slotCount && slot.target != GL_RENDERBUFFER; s++) {
		const name = oglCreateTexture();
		slot.names[s] = name;
		cacheStoreUnit0();
		cacheBindTextureSampler(0, slot.target, name, 0);
		if (sampleCount > 1) {
			storeMultisampleTexture(slot.target, sampleCount, info.internalFormat, width, height);
		} else {
			oglTexStorage(slot.target, mipLevels, info.internalFormat, width, height, layers);
		}
		cacheRestoreUnit0();
	}
	for (let s = 0; s < slot.slotCount; s++) {
		nameObject(slot.target == GL_RENDERBUFFER ? GL_RENDERBUFFER : GL_TEXTURE, slot.names[s], descriptor.label);
	}
	checkErrorOf("createTexture", descriptor.label);
	store(textures, slot);
	return { id: id };
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textures.slotIndex(texture.id);
	if (textures.slots[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	if (textures.slots[index].target == GL_RENDERBUFFER) {
		oglDeleteRenderbuffer(textures.slots[index].names[0]);
		textures.slots[index] = { id: 0 };
		release(textures, texture.id);
		return;
	}
	for (let s = 0; s < textures.slots[index].slotCount; s++) {
		cacheInvalidateTextureSampler(textures.slots[index].names[s], 0);
		oglDeleteTexture(textures.slots[index].names[s]);
	}
	textures.slots[index] = { id: 0 };
	release(textures, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat { return textures.slots[textures.slotIndex(texture.id)].format; }

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { stop("the swapchain texture is the default framebuffer and has no GL texture"); }
	return oglTextureNative(textures.slots[t].names[textures.slots[t].activeSlot]);
}

function rotateOnWholeWrite(index: int32, size: GPUExtent3D): void {
	const wholeTexture = textures.slots[index].slotCount > 1 && size.width == textures.slots[index].width && size.height == textures.slots[index].height;
	if (wholeTexture) {
		textures.slots[index].activeSlot = (textures.slots[index].activeSlot + 1) % textures.slots[index].slotCount;
		bound.resourcesDirty = true;
		computeBound.dirty = true;
	}
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textures.slotIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	if (!has(textures.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textures.slots[index].id}, created without COPY_DST`);
	}
	const info = textures.slots[index].info;
	const mip = destination.mipLevel;
	const mips = textures.slots[index].mipLevels;
	const volume = textures.slots[index].volume;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textures.slots[index].layers >> mip) : textures.slots[index].layers;
	const rowPitch = checkedTexelWritePitch(
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
	rotateOnWholeWrite(index, size);
	const rowsPerImage = layout.rowsPerImage == 0 ? size.height : layout.rowsPerImage;
	const target = textures.slots[index].target;
	const first = destination.origin.z;
	const count = size.depthOrArrayLayers;
	cacheStoreUnit0();
	cacheBindTextureSampler(0, target, textures.slots[index].names[textures.slots[index].activeSlot], 0);
	cacheUnpack(target, rowPitch / info.bytesPerPixel, rowsPerImage);
	if (target == GL_TEXTURE_CUBE_MAP) {
		const imageBytes = (rowPitch as int64) * (rowsPerImage as int64);
		for (let z = 0; z < count; z++) {
			oglTexSubImage(
				GL_TEXTURE_CUBE_MAP_POSITIVE_X + first + z,
				mip,
				destination.origin.x,
				destination.origin.y,
				0,
				size.width,
				size.height,
				1,
				info.pixelFormat,
				info.pixelType,
				data[0],
				layout.offset + imageBytes * (z as int64),
			);
		}
	} else {
		oglTexSubImage(
			target,
			mip,
			destination.origin.x,
			destination.origin.y,
			first,
			size.width,
			size.height,
			count,
			info.pixelFormat,
			info.pixelType,
			data[0],
			layout.offset,
		);
	}
	cacheRestoreUnit0();
}

function viewDimensionName(dimension: ViewDimension): string {
	if (dimension == ViewDimension.TwoD) { return "2d"; }
	if (dimension == ViewDimension.TwoDArray) { return "2d-array"; }
	if (dimension == ViewDimension.Cube) { return "cube"; }
	return "3d";
}

function viewDimensionOf(descriptor: GPUTextureViewDescriptor, t: int32): ViewDimension {
	let name: string = descriptor.dimension;
	if (name == "") { name = textures.slots[t].volume ? "3d" : (textures.slots[t].layers > 1 ? "2d-array" : "2d"); }
	if ((name == "3d") != textures.slots[t].volume) {
		stop(`GPUTextureViewDescriptor.dimension '${name}' does not match the ${textures.slots[t].volume ? "3d" : "2d"} GPUTexture ${textures.slots[t].id}`);
	}
	return match (name) {
		"2d" => ViewDimension.TwoD,
		"2d-array" => ViewDimension.TwoDArray,
		"cube" => ViewDimension.Cube,
		"3d" => ViewDimension.ThreeD,
		_ => stopOnMember("GPUTextureViewDescriptor.dimension", name) as ViewDimension,
	};
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { return { id: textures.slots[t].swapchainView }; }
	const id = allocate(views);
	const info = textures.slots[t].info;
	const usage = textures.slots[t].usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const layers = textures.slots[t].layers;
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? textures.slots[t].mipLevels - baseMip : descriptor.mipLevelCount;
	checkedViewMips(textures.slots[t].id, textures.slots[t].mipLevels, baseMip, mipCount);
	const dimension = viewDimensionOf(descriptor, t);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (dimension == ViewDimension.ThreeD) {
		checkedView3d(baseLayer, layerCount);
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (dimension == ViewDimension.TwoD) { layerCount = 1; }
		if (dimension == ViewDimension.Cube) { layerCount = 6; }
		if (layerCount == 0) { layerCount = layers - baseLayer; }
		checkedViewLayers(textures.slots[t].id, layers, baseLayer, layerCount);
	}
	if (dimension == ViewDimension.Cube) {
		if (!textures.slots[t].cube) {
			stop(`a cube view needs GPUTexture ${textures.slots[t].id} created square with exactly 6 layers and TEXTURE_BINDING: gl makes it a cube map`);
		}
	}
	const slot: ViewSlot = {
		id: id,
		texture: texture.id,
		sampled: has(usage, GPUTextureUsage.TEXTURE_BINDING as int32),
		color: attachment && !info.depth,
		depth: attachment && info.depth,
		resolveFramebuffer: 0,
		dimension: dimension,
		baseMip: baseMip,
		mipCount: mipCount,
		baseLayer: baseLayer,
		layerCount: layerCount,
		attachable: mipCount == 1 && layerCount == 1 && dimension != ViewDimension.Cube,
		storage: has(usage, GPUTextureUsage.STORAGE_BINDING as int32) && mipCount == 1,
		swapchain: false,
	};
	store(views, slot);
	return { id: slot.id };
}

@noinline function checkSampledView(binding: int32, v: int32): void {
	const t = textures.slotIndex(views.slots[v].texture);
	const target = textures.slots[t].target;
	const dimension = views.slots[v].dimension;
	const whole = views.slots[v].baseLayer == 0 && views.slots[v].layerCount == textures.slots[t].layers;
	if (target == GL_TEXTURE_3D && dimension == ViewDimension.ThreeD) { return; }
	if (target == GL_TEXTURE_CUBE_MAP && dimension == ViewDimension.Cube) { return; }
	if (target == GL_TEXTURE_2D_ARRAY && dimension == ViewDimension.TwoDArray && whole) { return; }
	if (target == GL_TEXTURE_2D && dimension == ViewDimension.TwoD) { return; }
	if (target == GL_TEXTURE_2D_MULTISAMPLE && dimension == ViewDimension.TwoD) { return; }
	stop(`bind group entry ${binding}: a ${viewDimensionName(dimension)} view of ${layersName(t)} GPUTexture ${textures.slots[t].id} cannot be sampled on gl without texture views (GL 4.3 glTextureView, absent in GLES3)`);
}

function layersName(t: int32): string {
	if (textures.slots[t].volume) { return "a 3d"; }
	if (textures.slots[t].cube) { return "a cube-map"; }
	return textures.slots[t].layers > 1 ? "a 2d-array" : "a 2d";
}

export function destroyView(view: GPUTextureView): void {
	const index = views.slotIndex(view.id);
	if (views.slots[index].swapchain) { return; }
	oglDeleteFramebuffer(views.slots[index].resolveFramebuffer);
	views.slots[index] = { id: 0 };
	release(views, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views.slots[views.slotIndex(view.id)].texture }; }

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	updateSwapchainTexture(swapchainColor, swapchain);
	if (swapchainDepth != 0) { updateSwapchainTexture(swapchainDepth, swapchain); }
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
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter", "gl");
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter", "gl");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter", "gl");
	let maxAnisotropy = descriptor.maxAnisotropy;
	if (maxAnisotropy < 1) { maxAnisotropy = 1; }
	checkedSamplerAnisotropy(maxAnisotropy, minLinear && magLinear && mipLinear);
	checkSamplerAnisotropy(maxAnisotropy);
	if (descriptor.lodMinClamp < 0) { stopOnMember("GPUSamplerDescriptor.lodMinClamp", `${descriptor.lodMinClamp}`); }
	const maxLod = checkedSamplerLod(descriptor.lodMinClamp, descriptor.lodMaxClamp);
	const native = oglCreateSampler();
	let minFilter = minLinear ? GL_LINEAR_MIPMAP_NEAREST : GL_NEAREST_MIPMAP_NEAREST;
	if (mipLinear) { minFilter = minLinear ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST_MIPMAP_LINEAR; }
	oglSamplerParameteri(native, GL_TEXTURE_MIN_FILTER, minFilter);
	oglSamplerParameteri(native, GL_TEXTURE_MAG_FILTER, magLinear ? GL_LINEAR : GL_NEAREST);
	oglSamplerParameterf(native, GL_TEXTURE_MIN_LOD, descriptor.lodMinClamp);
	oglSamplerParameterf(native, GL_TEXTURE_MAX_LOD, maxLod);
	oglSamplerParameteri(native, GL_TEXTURE_WRAP_S, addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"));
	oglSamplerParameteri(native, GL_TEXTURE_WRAP_T, addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"));
	oglSamplerParameteri(native, GL_TEXTURE_WRAP_R, addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW"));
	setSamplerBorderColor(native);
	const compare: string = descriptor.compare;
	if (compare == "") {
		oglSamplerParameteri(native, GL_TEXTURE_COMPARE_MODE, 0);
	} else {
		oglSamplerParameteri(native, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
		oglSamplerParameteri(native, GL_TEXTURE_COMPARE_FUNC, compareFunction(compare, "GPUSamplerDescriptor.compare"));
	}
	setSamplerAnisotropy(native, maxAnisotropy);
	nameObject(GL_SAMPLER, native, descriptor.label);
	checkErrorOf("createSampler", descriptor.label);
	const slot: SamplerSlot = { id: id, native: native };
	store(samplers, slot);
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplers.slotIndex(sampler.id);
	cacheInvalidateTextureSampler(0, samplers.slots[index].native);
	oglDeleteSampler(samplers.slots[index].native);
	samplers.slots[index] = { id: 0 };
	release(samplers, sampler.id);
}

function compileStage(stage: int32, code: string, entryPoint: string, label: string | null): uint32 {
	if (entryPoint != "" && entryPoint != "main") {
		stop(`GLSL enters at main, not '${entryPoint}', in ${labelOf(label)}`);
	}
	const shader = oglCompileShader(stage, code);
	if (shader == 0) {
		const log: string = oglLog();
		const stageName = stage == GL_VERTEX_SHADER ? "vertex" : (stage == GL_COMPUTE_SHADER ? "compute" : "fragment");
		stop(`compiling the ${stageName} shader of ${labelOf(label)} failed:\n${log}`);
	}
	return shader;
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	stopOnUnportedShaderBindings("gl", descriptor);
	checkedIntegerTexturePairs(descriptor);
	stopOnUnportedShaderBytecode("gl", descriptor);
	const compute = descriptor.computeCode != "";
	if (compute) {
		stopOnNoCompute("a compute GPUShaderModule");
		if (descriptor.vertexCode != "" || descriptor.fragmentCode != "") {
			stop("a GPUShaderModule is either a compute module or a vertex and fragment module");
		}
	}
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const kind = bindingKind(kindName, "gl");
		const binding = descriptor.bindings[i].binding;
		checkedVisibility(descriptor.bindings[i], compute);
		const expectedGroup = kind == BindingKind.Uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
		if (descriptor.bindings[i].group != expectedGroup) {
			stop(`shader binding ${binding} (${kind.toString()}) belongs in group ${expectedGroup}, not ${descriptor.bindings[i].group}`);
		}
		const writable = bindingWritable(descriptor.bindings[i]);
		if (writable && !compute) {
			stop(`shader binding ${binding} is writable storage in a render stage, which gl does not port: bind it read-only or write it from a compute pass`);
		}
		if (kind == BindingKind.Uniform) {
			if (compute) { stop(`uniform binding ${binding} in a compute stage is not ported to gl yet`); }
			const size = descriptor.bindings[i].size;
			if (size <= 0 || size % 16 != 0) { stop(`uniform binding ${binding} needs a block size in whole vec4s, not ${size}`); }
			if ((size as int64) > deviceLimits.maxUniformBufferBindingSize) {
				stop(`uniform binding ${binding} of ${size} bytes is over the limit of ${deviceLimits.maxUniformBufferBindingSize}`);
			}
			if (slot.uniformCount == GPU_MAX_UNIFORM_BLOCKS) { stop("a shader module has over 8 uniform blocks"); }
			slot.uniforms[slot.uniformCount] = { binding: binding, size: size, location: -1, count: size / 16 };
			slot.uniformCount += 1;
			continue;
		}
		let resource: ResourceBinding = { binding: binding, kind: kind, writable: writable };
		if (kind == BindingKind.StorageBuffer || kind == BindingKind.StorageTexture) {
			resource.nativeSlot = descriptor.bindings[i].nativeSlot;
			const limit = kind == BindingKind.StorageBuffer ? maxStorageBindings : maxImageUnits;
			if (resource.nativeSlot < 0 || resource.nativeSlot >= limit) {
				stop(`shader binding ${binding} has binding point ${resource.nativeSlot}, outside 0..${limit - 1} of this context`);
			}
			for (let r = 0; r < slot.resourceCount; r++) {
				if (slot.resources[r].kind == kind && slot.resources[r].nativeSlot == resource.nativeSlot) {
					stop(`shader bindings ${slot.resources[r].binding} and ${binding} share binding point ${resource.nativeSlot}`);
				}
			}
			if (kind == BindingKind.StorageTexture) {
				const accessName: string = descriptor.bindings[i].storageAccess;
				resource.access = match (accessName) {
					"write-only" => GL_WRITE_ONLY,
					"read-write" => GL_READ_WRITE,
					_ => GL_READ_ONLY,
				};
				resource.storageFormat = descriptor.bindings[i].storageFormat;
			}
			slot.storageCount += 1;
			if (writable) { slot.writes = true; }
		}
		const dummy = kind == BindingKind.Sampler && binding == DUMMY_SAMPLER_BINDING;
		if (!dummy) { addResource(slot, resource); }
		if (kind == BindingKind.Sampler) {
			if (descriptor.bindings[i].textureBinding < 0) {
				stop(`sampler binding ${binding} names no texture binding; GL samples through combined pairs`);
			}
			if (slot.pairCount == MAX_TEXTURE_PAIRS) { stop("a shader module has over 16 texture-sampler pairs"); }
			slot.pairs[slot.pairCount] = {
				samplerBinding: binding,
				textureBinding: descriptor.bindings[i].textureBinding,
				unit: -1,
			};
			slot.pairCount += 1;
		}
	}
	for (let p = 0; p < slot.pairCount; p++) { checkPairTexture(slot, slot.pairs[p].textureBinding); }
	slot.attributes = descriptor.attributes;
	if (compute) {
		slot.compute = true;
		slot.computeEntry = descriptor.computeEntryPoint == "" ? "main" : descriptor.computeEntryPoint;
		const size: int32[3] = descriptor.workgroupSize;
		if (
			size[0] > deviceLimits.maxComputeWorkgroupSizeX || size[1] > deviceLimits.maxComputeWorkgroupSizeY
				|| size[2] > deviceLimits.maxComputeWorkgroupSizeZ || size[0] * size[1] * size[2] > deviceLimits.maxComputeInvocationsPerWorkgroup
		) {
			stop(`workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the limits ${deviceLimits.maxComputeWorkgroupSizeX}x${deviceLimits.maxComputeWorkgroupSizeY}x${deviceLimits.maxComputeWorkgroupSizeZ} and ${deviceLimits.maxComputeInvocationsPerWorkgroup} invocations`);
		}
		const shader = compileStage(GL_COMPUTE_SHADER, descriptor.computeCode, descriptor.computeEntryPoint, descriptor.label);
		slot.program = oglLinkComputeProgram(shader);
	} else {
		const vertex = compileStage(GL_VERTEX_SHADER, descriptor.vertexCode, descriptor.vertexEntryPoint, descriptor.label);
		const fragment = compileStage(GL_FRAGMENT_SHADER, descriptor.fragmentCode, descriptor.fragmentEntryPoint, descriptor.label);
		slot.program = oglLinkProgram(vertex, fragment);
	}
	if (slot.program == 0) {
		const log: string = oglLog();
		stop(`linking the program of ${labelOf(descriptor.label)} failed:\n${log}`);
	}
	resolveUniforms(slot, descriptor);
	resolveTextureUnits(slot, descriptor);
	nameObject(GL_PROGRAM, slot.program, descriptor.label);
	checkErrorOf("createShaderModule", descriptor.label);
	slot.id = id;
	slot.readsInstanceIndex = descriptor.readsInstanceIndex;
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

function addResource(ref slot: ShaderSlot, resource: ResourceBinding): void {
	for (let r = 0; r < slot.resourceCount; r++) {
		if (slot.resources[r].binding == resource.binding && slot.resources[r].kind == resource.kind) { return; }
	}
	if (slot.resourceCount == MAX_SHADER_RESOURCES) { stop("a shader module has over 24 resources"); }
	slot.resources[slot.resourceCount] = resource;
	slot.resourceCount += 1;
}

@noinline function checkPairTexture(slot: ShaderSlot, textureBinding: int32): void {
	for (let r = 0; r < slot.resourceCount; r++) {
		if (slot.resources[r].binding == textureBinding && slot.resources[r].kind == BindingKind.Texture) { return; }
	}
	stop(`a sampler pairs with texture binding ${textureBinding}, which the shader module does not declare`);
}

function resolveUniforms(ref slot: ShaderSlot, descriptor: GPUShaderModuleDescriptor): void {
	for (let u = 0; u < slot.uniformCount; u++) {
		const name = nativeNameOf(uniformNameOf(descriptor, slot.uniforms[u].binding), `uniform binding ${slot.uniforms[u].binding}`);
		slot.uniforms[u].location = oglUniformLocation(slot.program, name);
	}
}

function uniformNameOf(descriptor: GPUShaderModuleDescriptor, binding: int32): string | null {
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "uniform" && descriptor.bindings[i].binding == binding) { return descriptor.bindings[i].nativeName; }
	}
	return null;
}

function resolveTextureUnits(ref slot: ShaderSlot, descriptor: GPUShaderModuleDescriptor): void {
	oglUseProgram(slot.program);
	let unit = 0;
	let p = 0;
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName != "sampler") { continue; }
		const name = nativeNameOf(descriptor.bindings[i].nativeName, `sampler binding ${descriptor.bindings[i].binding}`);
		const location = oglUniformLocation(slot.program, name);
		if (location != -1) {
			if (unit == maxTextureUnits) { stop(`a shader module samples over ${maxTextureUnits} textures`); }
			oglUniform1i(location, unit);
			slot.pairs[p].unit = unit;
			unit += 1;
		}
		p += 1;
	}
	oglUseProgram(cache.program);
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaders.slotIndex(module.id);
	cacheInvalidateProgram(shaders.slots[index].program);
	oglDeleteProgram(shaders.slots[index].program);
	shaders.slots[index] = { id: 0 };
	release(shaders, module.id);
}

function attributeNameOf(shader: int32, location: int32): string | null {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		const name = shaders.slots[shader].attributes[i].nativeName;
		if (name !== null && shaders.slots[shader].attributes[i].location == location) { return name; }
	}
	return null;
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocate(pipelines);
	const s = shaders.slotIndex(descriptor.vertex.module.id);
	if (shaders.slots[s].compute) { stop("a compute GPUShaderModule cannot make a GPURenderPipeline"); }
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule on GL");
	}
	let slot: PipelineSlot = { id: 0, shader: descriptor.vertex.module.id, label: descriptor.label, readsInstanceIndex: shaders.slots[s].readsInstanceIndex };
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) { slot.blends[i] = defaultBlend(); }
	describeAttributes(s, descriptor, slot);
	describePrimitive(descriptor, slot);
	describeDepthStencil(descriptor, slot);
	describeBlend(descriptor, slot);
	slot.cullFace = cullFace(descriptor.primitive.cullMode);
	slot.frontFace = frontFace(descriptor.primitive.frontFace);
	slot.sampleCount = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	slot.id = id;
	store(pipelines, slot);
	return { id: slot.id };
}

function describePrimitive(descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	slot.primitive = primitiveMode(descriptor.primitive.topology);
	const strip = slot.primitive == GL_LINE_STRIP || slot.primitive == GL_TRIANGLE_STRIP;
	slot.stripRestart = strip;
	const format: string = descriptor.primitive.stripIndexFormat;
	if (format == "") { return; }
	if (!strip) { stop(`primitive.stripIndexFormat '${format}' needs a strip topology`); }
	slot.stripIndexType = match (format) {
		"uint16" => GL_UNSIGNED_SHORT,
		"uint32" => GL_UNSIGNED_INT,
		_ => stopOnMember("primitive.stripIndexFormat", format),
	};
}

function describeDepthStencil(descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	const state = descriptor.depthStencil;
	const depthFormat: string = state.format;
	slot.depthCompare = GL_ALWAYS;
	if (depthFormat == "") { return; }
	const info = formatInfo(state.format, "depthStencil.format");
	if (!info.depth) { stopOnMember("depthStencil.format", depthFormat); }
	slot.depthWrite = state.depthWriteEnabled;
	slot.depthCompare = compareFunction(state.depthCompare, "depthStencil.depthCompare");
	if (state.depthBiasClamp != 0) {
		stop("depthStencil.depthBiasClamp above 0 is not ported to gl: sokol_gfx documents the clamp as meaningless on GL (glPolygonOffsetClamp is GL 4.6 only)");
	}
	slot.depthBias = state.depthBias;
	slot.depthSlope = state.depthBiasSlopeScale;
	slot.stencil = info.stencil;
	slot.stencilReadMask = state.stencilReadMask == 0 ? STENCIL_MASK_ALL : (state.stencilReadMask as int32);
	slot.stencilWriteMask = state.stencilWriteMask == 0 ? STENCIL_MASK_ALL : (state.stencilWriteMask as int32);
	slot.stencilFront = stencilFace(state.stencilFront, "depthStencil.stencilFront");
	slot.stencilBack = stencilFace(state.stencilBack, "depthStencil.stencilBack");
}

function describeAttributes(shader: int32, descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stepMode: string = descriptor.vertex.buffers[b].stepMode;
		if (stepMode != "" && stepMode != "vertex" && stepMode != "instance") {
			stopOnMember("vertex.buffers stepMode", stepMode);
		}
		const divisor = stepMode == "instance" ? 1 : 0;
		const stride = descriptor.vertex.buffers[b].arrayStride;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			if (stride <= 0) { stop(`vertex buffer ${b} has attributes and no arrayStride`); }
			const shaderLocation = descriptor.vertex.buffers[b].attributes[a].shaderLocation;
			const name = attributeNameOf(shader, shaderLocation);
			const location = name === null ? shaderLocation : oglAttribLocation(shaders.slots[shader].program, name);
			if (location == -1) { continue; }
			if (location < 0 || location >= maxVertexAttributes) {
				stop(`vertex attribute at location ${location} is outside the ${maxVertexAttributes} GL attributes`);
			}
			if (slot.attributes[location].enabled) { stop(`two vertex attributes feed GL location ${location}`); }
			const vertex = vertexFormatInfo(format);
			slot.attributes[location] = {
				enabled: true,
				bufferSlot: b,
				divisor: divisor,
				stride: stride,
				offset: descriptor.vertex.buffers[b].attributes[a].offset,
				size: vertex.components,
				attributeType: vertex.componentType,
				normalized: vertex.normalized,
				integer: vertex.integer,
			};
			slot.strides[b] = stride;
			if (divisor != 0) { slot.instanced = true; }
		}
	}
}

function describeBlend(descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	let first = -1;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") { continue; }
		const info = formatInfo(descriptor.fragment.targets[i].format, `fragment.targets[${i}].format`);
		const writeMask = descriptor.fragment.targets[i].writeMask;
		slot.writeMasks[i] = writeMask == 0 ? COLOR_WRITE_ALL : writeMask;
		slot.colorCount = i + 1;
		const color: GPUBlendComponent = descriptor.fragment.targets[i].blend.color;
		const alpha: GPUBlendComponent = descriptor.fragment.targets[i].blend.alpha;
		const enabled = descriptor.fragment.targets[i].blendEnabled;
		if (enabled && info.integer) { stop(`fragment.targets[${i}] blends ${format}, an integer format`); }
		slot.blends[i] = {
			enabled: enabled,
			sourceColor: blendFactor(color.srcFactor, "blend.color.srcFactor"),
			destinationColor: destinationFactor(color.dstFactor, "blend.color.dstFactor"),
			operationColor: blendOperation(color.operation, "blend.color.operation"),
			sourceAlpha: blendFactor(alpha.srcFactor, "blend.alpha.srcFactor"),
			destinationAlpha: destinationFactor(alpha.dstFactor, "blend.alpha.dstFactor"),
			operationAlpha: blendOperation(alpha.operation, "blend.alpha.operation"),
		};
		checkTargetsAlike(slot, i, first);
		if (first == -1) { first = i; }
	}
}

function sameBlend(a: BlendState, b: BlendState): boolean {
	return a.enabled == b.enabled &&
		a.sourceColor == b.sourceColor &&
		a.destinationColor == b.destinationColor &&
		a.operationColor == b.operationColor &&
		a.sourceAlpha == b.sourceAlpha &&
		a.destinationAlpha == b.destinationAlpha &&
		a.operationAlpha == b.operationAlpha;
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	const index = pipelines.slotIndex(pipeline.id);
	if (bound.appliedPipeline == pipeline.id) { bound.appliedPipeline = 0; }
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
		if (slot.entries[i].buffer.id == 0 || !buffers.slots[buffers.slotIndex(slot.entries[i].buffer.id)].uniform) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			if (
				slot.entries[j].buffer.id != 0 && buffers.slots[buffers.slotIndex(slot.entries[j].buffer.id)].uniform
					&& slot.entries[j].binding < slot.entries[i].binding
			) {
				rank += 1;
			}
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: slot.id };
}

function resourceOf(shader: int32, binding: int32, kind: BindingKind): int32 {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		if (shaders.slots[shader].resources[r].binding == binding && shaders.slots[shader].resources[r].kind == kind) { return r; }
	}
	return -1;
}

function storageRange(entry: GPUBindGroupEntry, b: int32): int64 {
	if (entry.offset < 0 || entry.offset % (STORAGE_OFFSET_ALIGNMENT as int64) != 0) {
		stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${STORAGE_OFFSET_ALIGNMENT}`);
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

@noinline function checkStorageView(entry: GPUBindGroupEntry, v: int32, resource: ResourceBinding): void {
	if (!views.slots[v].storage) {
		stop(`bind group entry ${entry.binding}: the view's texture lacks STORAGE_BINDING or the view spans several mips`);
	}
	const t = textures.slotIndex(views.slots[v].texture);
	const dimension = views.slots[v].dimension;
	const whole = dimension == ViewDimension.ThreeD || (views.slots[v].baseLayer == 0 && views.slots[v].layerCount == textures.slots[t].layers);
	if (dimension != ViewDimension.TwoD && !whole) {
		stop(`bind group entry ${entry.binding}: a ${viewDimensionName(dimension)} storage view must cover the whole GPUTexture on gl, because glBindImageTexture binds one layer or all of them`);
	}
	const expected: string = resource.storageFormat;
	const actual: string = textures.slots[t].format;
	if (expected != "" && expected != actual) {
		stop(`bind group entry ${entry.binding}: the shader declares storage format '${expected}' and the view's texture is '${actual}'`);
	}
}

@noinline function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = buffers.slotIndex(entry.buffer.id);
		for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
			const binding = shaders.slots[shader].uniforms[u];
			if (binding.binding == entry.binding) {
				if (!buffers.slots[b].uniform) { stop(`bind group entry ${entry.binding} needs a UNIFORM buffer`); }
				if (entry.offset < 0 || entry.offset % (UNIFORM_OFFSET_ALIGNMENT as int64) != 0) {
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
		}
		if (resourceOf(shader, entry.binding, BindingKind.StorageBuffer) >= 0) {
			if (!buffers.slots[b].storage) { stop(`bind group entry ${entry.binding} needs a STORAGE buffer`); }
			storageRange(entry, b);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	if (entry.textureView.id != 0) {
		const v = views.slotIndex(entry.textureView.id);
		if (resourceOf(shader, entry.binding, BindingKind.Texture) >= 0) {
			if (!views.slots[v].sampled) { stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`); }
			checkSampledView(entry.binding, v);
			return;
		}
		const r = resourceOf(shader, entry.binding, BindingKind.StorageTexture);
		if (r >= 0) {
			checkStorageView(entry, v, shaders.slots[shader].resources[r]);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplers.slotIndex(entry.sampler.id);
	if (resourceOf(shader, entry.binding, BindingKind.Sampler) >= 0) { return; }
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

export function submit(commandBuffer: GPUCommandBuffer): void {
	cacheClearBuffers(false);
	cacheClearUnits(false);
	bound.vertexDirty = true;
	bound.indexDirty = true;
	bound.resourcesDirty = true;
	frame += 1;
}

export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	if (pass.active || computeBound.active) { stop("beginRenderPass with a pass already open"); }
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	if (descriptor.occlusionQuerySet.id != 0 && querySets.slots[querySets.slotIndex(descriptor.occlusionQuerySet.id)].timestamp) {
		stop("GPURenderPassDescriptor.occlusionQuerySet is a timestamp set: an occlusion set is required");
	}
	passSerial += 1;
	pass = {
		active: true,
		serial: passSerial,
		groupBase: groupDepth,
		timestampSet: descriptor.timestampWrites.querySet.id,
		timestampEnd: descriptor.timestampWrites.endOfPassWriteIndex,
		occlusionSet: descriptor.occlusionQuerySet.id,
	};
	pass.labeled = labelPass(descriptor.label);
	if (pass.timestampSet != 0 && descriptor.timestampWrites.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(pass.timestampSet, descriptor.timestampWrites.beginningOfPassWriteIndex);
	}
	let colorMask = 0;
	let offscreen = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = views.slotIndex(viewId);
		if (!views.slots[v].color) { stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`); }
		if (views.slots[v].swapchain) {
			if (i != 0) { stop(`colorAttachments[${i}] is the canvas, which GL draws only as attachment 0`); }
			if (descriptor.colorAttachments[i].resolveTarget.id != 0) {
				stop("colorAttachments[0] is the canvas, whose multisampled default framebuffer resolves itself on GL");
			}
			pass.swapchain = true;
		} else {
			offscreen = true;
		}
		if (!views.slots[v].attachable) { checkedSingleSubresource(attachmentMember(i, "view"), false); }
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		const slice = descriptor.colorAttachments[i].depthSlice;
		if (views.slots[v].dimension == ViewDimension.ThreeD) {
			const slices = Math.max(1, textures.slots[textures.slotIndex(views.slots[v].texture)].layers >> views.slots[v].baseMip);
			checkedDepthSlice(i, slice, slices, views.slots[v].baseMip, views.slots[v].texture);
		} else {
			checkedNoDepthSlice(i, slice);
		}
		pass.colorSlices[i] = slice;
		pass.colorViews[i] = viewId;
		pass.resolveViews[i] = checkResolve(i, views.slots[v].texture, descriptor.colorAttachments[i].resolveTarget.id);
		colorMask |= 1 << i;
		checkStoreOp(descriptor.colorAttachments[i].storeOp, i, "storeOp");
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	let depthTexture = 0;
	let depthViewSlot = -1;
	let depthStencil = false;
	if (depthView != 0) {
		const v = views.slotIndex(depthView);
		if (!views.slots[v].depth) { stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT"); }
		if (!views.slots[v].attachable) { stop("depthStencilAttachment.view spans several mips or layers: a render attachment is one mip of one layer"); }
		if (views.slots[v].swapchain) { pass.swapchain = true; } else { offscreen = true; }
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		depthViewSlot = v;
		depthTexture = textures.slotIndex(views.slots[v].texture);
		depthStencil = textures.slots[depthTexture].info.stencil;
		checkStoreOp(descriptor.depthStencilAttachment.depthStoreOp, -1, "depthStoreOp");
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	if (pass.swapchain && offscreen) {
		stop("a render pass mixes the canvas with offscreen attachments; GL draws the canvas through framebuffer 0");
	}
	if (pass.swapchain) {
		setFramebufferSrgb(false);
		oglBindFramebuffer(GL_FRAMEBUFFER, 0);
	} else {
		bindOffscreenFramebuffer(colorMask, depthViewSlot, depthStencil);
	}
	oglViewport(0, 0, pass.width, pass.height);
	oglScissor(0, 0, pass.width, pass.height);
	if (cache.depthRangeSet) {
		cache.depthRangeSet = false;
		oglDepthRange(0, 1);
	}
	if (cache.blendConstantSet) {
		cache.blendConstantSet = false;
		oglBlendColor(0, 0, 0, 0);
	}
	bound.stencilReference = 0;
	clearAttachments(descriptor, depthView != 0, depthStencil);
	bound.appliedPipeline = 0;
	bound.vertexDirty = true;
	bound.indexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
	return { id: 1 };
}

function bindOffscreenFramebuffer(colorMask: int32, depthView: int32, depthStencil: boolean): void {
	setFramebufferSrgb(true);
	oglBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = GL_COLOR_ATTACHMENT0 + i;
		if (pass.colorViews[i] == 0) {
			oglFramebufferDetach(attachment);
			continue;
		}
		const v = views.slotIndex(pass.colorViews[i]);
		attachView(attachment, v, views.slots[v].dimension == ViewDimension.ThreeD ? pass.colorSlices[i] : views.slots[v].baseLayer);
	}
	if (depthView >= 0) {
		oglFramebufferDetach(GL_DEPTH_ATTACHMENT);
		oglFramebufferDetach(GL_DEPTH_STENCIL_ATTACHMENT);
		attachView(depthStencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT, depthView, views.slots[depthView].baseLayer);
	} else {
		oglFramebufferDetach(GL_DEPTH_STENCIL_ATTACHMENT);
	}
	const status = oglCheckFramebufferStatus();
	if (status != GL_FRAMEBUFFER_COMPLETE) { stop(`the render pass framebuffer is incomplete (status 0x${status.toString(16)})`); }
	oglDrawBuffers(GPU_MAX_COLOR_ATTACHMENTS, colorMask);
}

function attachView(attachment: int32, v: int32, layer: int32): void {
	const t = textures.slotIndex(views.slots[v].texture);
	const target = textures.slots[t].target;
	const name = textures.slots[t].names[0];
	if (target == GL_RENDERBUFFER) {
		oglFramebufferRenderbuffer(attachment, name);
	} else if (target == GL_TEXTURE_2D_ARRAY || target == GL_TEXTURE_3D) {
		oglFramebufferTextureLayer(attachment, name, views.slots[v].baseMip, layer);
	} else if (target == GL_TEXTURE_CUBE_MAP) {
		oglFramebufferTexture2D(attachment, GL_TEXTURE_CUBE_MAP_POSITIVE_X + views.slots[v].baseLayer, name, views.slots[v].baseMip);
	} else {
		oglFramebufferTexture2D(attachment, target, name, views.slots[v].baseMip);
	}
}

function clearAttachments(descriptor: GPURenderPassDescriptor, hasDepth: boolean, depthStencil: boolean): void {
	let clearAnyColor = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] != 0 && isClear(descriptor.colorAttachments[i].loadOp, i, "loadOp")) {
			clearAnyColor = true;
		}
	}
	const clearDepth = hasDepth && isClear(descriptor.depthStencilAttachment.depthLoadOp, -1, "depthLoadOp");
	if (clearAnyColor) {
		let flushMask = false;
		for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
			if (cache.writeMasks[i] != COLOR_WRITE_ALL) {
				flushMask = true;
				cache.writeMasks[i] = COLOR_WRITE_ALL;
			}
		}
		if (flushMask) { oglColorMask(COLOR_WRITE_ALL); }
	}
	if (clearDepth) {
		if (!cache.depthWrite) {
			cache.depthWrite = true;
			oglDepthMask(1);
		}
		if (cache.depthCompare != GL_ALWAYS) {
			cache.depthCompare = GL_ALWAYS;
			oglDepthFunc(GL_ALWAYS);
		}
		if (depthStencil && cache.stencilMask != 0xFF) {
			cache.stencilMask = 0xFF;
			oglStencilMask(0xFF);
		}
	}
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] == 0) { continue; }
		if (isClear(descriptor.colorAttachments[i].loadOp, i, "loadOp")) {
			const color = descriptor.colorAttachments[i].clearValue;
			oglClearColor(i, color.r, color.g, color.b, color.a);
		}
	}
	if (clearDepth) {
		const depth = descriptor.depthStencilAttachment.depthClearValue;
		if (depthStencil) { oglClearDepthStencil(depth, 0); } else { oglClearDepth(depth); }
	}
}

function passExtent(texture: uint32, baseMip: int32): void {
	const t = textures.slotIndex(texture);
	const width = Math.max(1, textures.slots[t].width >> baseMip);
	const height = Math.max(1, textures.slots[t].height >> baseMip);
	checkedPassExtent(pass.width, pass.height, width, height);
	pass.width = width;
	pass.height = height;
}

@noinline function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): uint32 {
	if (resolveId == 0) { return 0; }
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
	if (textures.slots[resolveTexture].sampleCount != 1 || !views.slots[r].color || views.slots[r].swapchain) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample offscreen color RENDER_ATTACHMENT`);
	}
	if (!views.slots[r].attachable) { checkedSingleSubresource(attachmentMember(attachment, "resolveTarget"), false); }
	passExtent(views.slots[r].texture, views.slots[r].baseMip);
	if (views.slots[r].resolveFramebuffer == 0) {
		const resolveFramebuffer = oglCreateFramebuffer();
		oglBindFramebuffer(GL_FRAMEBUFFER, resolveFramebuffer);
		attachView(GL_COLOR_ATTACHMENT0, r, views.slots[r].baseLayer);
		const status = oglCheckFramebufferStatus();
		if (status != GL_FRAMEBUFFER_COMPLETE) { stop(`the resolve framebuffer is incomplete (status 0x${status.toString(16)})`); }
		oglDrawBuffers(1, 1);
		views.slots[r].resolveFramebuffer = resolveFramebuffer;
	}
	return resolveId;
}

function attachmentMember(index: int32, field: string): string {
	return index < 0 ? `depthStencilAttachment.${field}` : `colorAttachments[${index}].${field}`;
}

function isClear(loadOp: string, index: int32, field: string): boolean {
	const value = match (loadOp) {
		"clear" => 1,
		"load" => 0,
		_ => stopOnMember(attachmentMember(index, field), loadOp),
	};
	return value == 1;
}

@noinline function checkStoreOp(storeOp: string, index: int32, field: string): void {
	if (storeOp != "store" && storeOp != "discard") { stopOnMember(attachmentMember(index, field), storeOp); }
}

export function endPass(): void {
	if (!pass.active) { stop("end without an open render pass"); }
	if (pass.occlusionOpen) { stop("end with an occlusion query still open"); }
	checkGroupsClosed(pass.groupBase, "end");
	let readBound = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.resolveViews[i] == 0) { continue; }
		if (!readBound) {
			oglBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
			readBound = true;
		}
		const r = views.slotIndex(pass.resolveViews[i]);
		oglBindFramebuffer(GL_DRAW_FRAMEBUFFER, views.slots[r].resolveFramebuffer);
		oglReadBuffer(GL_COLOR_ATTACHMENT0 + i);
		oglBlitColor(pass.width, pass.height);
	}
	if (pass.timestampSet != 0 && pass.timestampEnd >= 0) { writeTimestamp(pass.timestampSet, pass.timestampEnd); }
	if (pass.labeled) { endLabel(); }
	pass.active = false;
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	if (pipelines.slots[pipelines.slotIndex(pipeline.id)].compute) {
		stop(`GPUPipeline ${pipeline.id} is a compute pipeline: a render pass takes a render pipeline`);
	}
	bound.pipeline = pipeline.id;
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) { stopOnMember("setVertexBuffer slot", `${slot}`); }
	bound.vertexBuffers[slot] = buffer.id;
	bound.vertexOffsets[slot] = offset;
	bound.vertexDirty = true;
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	const value: string = format;
	bound.indexType = match (value) {
		"uint16" => GL_UNSIGNED_SHORT,
		"uint32" => GL_UNSIGNED_INT,
		_ => stopOnMember("setIndexBuffer indexFormat", value),
	};
	bound.indexSize = bound.indexType == GL_UNSIGNED_SHORT ? 2 : 4;
	bound.indexBuffer = buffer.id;
	bound.indexOffset = offset;
	bound.indexDirty = true;
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

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	if (!pass.active) { stop("setScissorRect outside a render pass"); }
	oglScissor(x, pass.height - (y + height), width, height);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	if (!pass.active) { stop("setViewport outside a render pass"); }
	checkedViewport(width, height, minDepth, maxDepth);
	const left = x as int32;
	const top = y as int32;
	const viewWidth = width as int32;
	const viewHeight = height as int32;
	if ((left as float32) != x || (top as float32) != y || (viewWidth as float32) != width || (viewHeight as float32) != height) {
		stop(`setViewport ${x},${y} ${width}x${height} is fractional: glViewport takes whole pixels`);
	}
	oglViewport(left, pass.height - (top + viewHeight), viewWidth, viewHeight);
	oglDepthRange(minDepth, maxDepth);
	cache.depthRangeSet = true;
}

export function setBlendConstant(color: GPUColor): void {
	if (!pass.active) { stop("setBlendConstant outside a render pass"); }
	oglBlendColor(color.r, color.g, color.b, color.a);
	cache.blendConstantSet = true;
}

export function setStencilReference(reference: uint32): void {
	if (!pass.active) { stop("setStencilReference outside a render pass"); }
	bound.stencilReference = reference as int32;
	if (bound.appliedPipeline != 0 && pipelines.slots[pipelines.slotIndex(bound.appliedPipeline)].stencil) {
		applyStencilFaces(pipelines.slotIndex(bound.appliedPipeline));
	}
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush(false);
	checkFirstInstance("draw", firstInstance);
	const mode = pipelines.slots[pipelines.slotIndex(bound.pipeline)].primitive;
	if (instanceCount > 1 || bound.instanced) {
		if (firstInstance == 0) {
			oglDrawArraysInstanced(mode, firstVertex, vertexCount, instanceCount);
		} else {
			drawArraysBaseInstance(mode, firstVertex, vertexCount, instanceCount, firstInstance);
		}
	} else {
		oglDrawArrays(mode, firstVertex, vertexCount);
	}
}

export function drawIndexed(
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	if (instanceCount == 0) { return; }
	flush(true);
	checkFirstInstance("drawIndexed", firstInstance);
	const pipeline = pipelines.slotIndex(bound.pipeline);
	const mode = pipelines.slots[pipeline].primitive;
	if (pipelines.slots[pipeline].stripIndexType != 0 && pipelines.slots[pipeline].stripIndexType != bound.indexType) {
		stop("an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format");
	}
	const offset = (firstIndex as int64) * (bound.indexSize as int64) + bound.indexOffset;
	const indexType = bound.indexType;
	if (baseVertex == 0 && firstInstance == 0) {
		if (instanceCount > 1 || bound.instanced) {
			oglDrawElementsInstanced(mode, indexCount, indexType, offset, instanceCount);
		} else {
			oglDrawElements(mode, indexCount, indexType, offset);
		}
		return;
	}
	drawElementsBaseVertex(mode, indexCount, indexType, offset, instanceCount, baseVertex, firstInstance);
}

function checkFirstInstance(call: string, firstInstance: int32): void {
	if (firstInstance == 0) { return; }
	const p = pipelines.slotIndex(bound.pipeline);
	if (pipelines.slots[p].readsInstanceIndex) { stop(firstInstanceRefusal(call, labelOf(pipelines.slots[p].label), firstInstance)); }
}

function flush(indexed: boolean): void {
	if (!pass.active) { stop("draw outside a render pass"); }
	if (bound.pipeline == 0) { stop("draw without setPipeline"); }
	if (bound.appliedPipeline != bound.pipeline) { applyPipeline(); }
	if (bound.vertexDirty) { applyVertexBuffers(); }
	if (indexed && bound.indexDirty) { applyIndexBuffer(); }
	if (bound.resourcesDirty) { applyResources(); }
	if (bound.uniformsDirty) { applyUniforms(); }
}

function applyPipeline(): void {
	const p = pipelines.slotIndex(bound.pipeline);
	if (!shaders.alive(pipelines.slots[p].shader)) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	const s = shaders.slotIndex(pipelines.slots[p].shader);
	if (shaders.slots[s].program != cache.program) {
		cache.program = shaders.slots[s].program;
		oglUseProgram(cache.program);
	}
	applyDepthState(p);
	applyStencilState(p);
	if (pipelines.slots[p].colorCount > 0) { applyBlendState(p); }
	if (pipelines.slots[p].stripRestart != cache.primitiveRestart) {
		cache.primitiveRestart = pipelines.slots[p].stripRestart;
		setPrimitiveRestart(cache.primitiveRestart);
	}
	if (pipelines.slots[p].cullFace != cache.cullFace) {
		cache.cullFace = pipelines.slots[p].cullFace;
		if (cache.cullFace == 0) {
			oglDisable(GL_CULL_FACE);
		} else {
			oglEnable(GL_CULL_FACE);
			oglCullFace(cache.cullFace);
		}
	}
	if (pipelines.slots[p].frontFace != cache.frontFace) {
		cache.frontFace = pipelines.slots[p].frontFace;
		oglFrontFace(cache.frontFace);
	}
	if (pipelines.slots[p].sampleCount != cache.sampleCount) {
		cache.sampleCount = pipelines.slots[p].sampleCount;
		setMultisample(cache.sampleCount);
	}
	bound.instanced = pipelines.slots[p].instanced;
	bound.appliedPipeline = bound.pipeline;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
}

// WebGL2 always restarts a strip at the all-ones index and refuses the capability's enum.
function setPrimitiveRestart(on: boolean): void {
	when (!webgl2) {
		if (on) { oglEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX); } else { oglDisable(GL_PRIMITIVE_RESTART_FIXED_INDEX); }
	}
}

function applyDepthState(p: int32): void {
	if (pipelines.slots[p].depthCompare != cache.depthCompare) {
		cache.depthCompare = pipelines.slots[p].depthCompare;
		oglDepthFunc(cache.depthCompare);
	}
	if (pipelines.slots[p].depthWrite != cache.depthWrite) {
		cache.depthWrite = pipelines.slots[p].depthWrite;
		oglDepthMask(cache.depthWrite ? 1 : 0);
	}
	const slope = pipelines.slots[p].depthSlope;
	const units = pipelines.slots[p].depthBias as float64;
	if (slope != cache.offsetFactor || units != cache.offsetUnits) {
		cache.offsetFactor = slope;
		cache.offsetUnits = units;
		oglPolygonOffset(slope, units);
	}
	const offset = slope != 0 || units != 0;
	if (offset != cache.polygonOffset) {
		cache.polygonOffset = offset;
		if (offset) { oglEnable(GL_POLYGON_OFFSET_FILL); } else { oglDisable(GL_POLYGON_OFFSET_FILL); }
	}
}

function applyStencilState(p: int32): void {
	if (!pipelines.slots[p].stencil) {
		if (cache.stencilEnabled) {
			cache.stencilEnabled = false;
			oglDisable(GL_STENCIL_TEST);
		}
		return;
	}
	if (!cache.stencilEnabled) {
		cache.stencilEnabled = true;
		oglEnable(GL_STENCIL_TEST);
	}
	if (pipelines.slots[p].stencilWriteMask != cache.stencilMask) {
		cache.stencilMask = pipelines.slots[p].stencilWriteMask;
		oglStencilMask(cache.stencilMask);
	}
	applyStencilFaces(p);
	oglStencilOpSeparate(GL_FRONT, pipelines.slots[p].stencilFront.failOp, pipelines.slots[p].stencilFront.depthFailOp, pipelines.slots[p].stencilFront.passOp);
	oglStencilOpSeparate(GL_BACK, pipelines.slots[p].stencilBack.failOp, pipelines.slots[p].stencilBack.depthFailOp, pipelines.slots[p].stencilBack.passOp);
}

function applyStencilFaces(p: int32): void {
	oglStencilFuncSeparate(GL_FRONT, pipelines.slots[p].stencilFront.compare, bound.stencilReference, pipelines.slots[p].stencilReadMask);
	oglStencilFuncSeparate(GL_BACK, pipelines.slots[p].stencilBack.compare, bound.stencilReference, pipelines.slots[p].stencilReadMask);
}

function applyBlendState(p: int32): void {
	for (let i = 0; i < pipelines.slots[p].colorCount; i++) {
		const next: BlendState = pipelines.slots[p].blends[i];
		const current: BlendState = cache.blends[i];
		applyBlend(i, next, current);
		if (pipelines.slots[p].writeMasks[i] != cache.writeMasks[i]) {
			cache.writeMasks[i] = pipelines.slots[p].writeMasks[i];
			applyWriteMask(i, cache.writeMasks[i]);
		}
		cache.blends[i] = next;
	}
}

function applyBlendAll(next: BlendState, current: BlendState): void {
	if (next.enabled != current.enabled) {
		if (next.enabled) { oglEnable(GL_BLEND); } else { oglDisable(GL_BLEND); }
	}
	if (
		next.sourceColor != current.sourceColor ||
		next.destinationColor != current.destinationColor ||
		next.sourceAlpha != current.sourceAlpha ||
		next.destinationAlpha != current.destinationAlpha
	) {
		oglBlendFuncSeparate(next.sourceColor, next.destinationColor, next.sourceAlpha, next.destinationAlpha);
	}
	if (next.operationColor != current.operationColor || next.operationAlpha != current.operationAlpha) {
		oglBlendEquationSeparate(next.operationColor, next.operationAlpha);
	}
}

when (webgl2 || android) {
	const COMPUTE_CONTEXT_VERSION = 310;
	const DEBUG_CONTEXT_VERSION = 320;

	function checkContextVersion(version: int32): void {
		if (version < 300) { stop(`the current context is GLES ${version}; the GLES3 backend needs 300`); }
	}

	function multisampleTarget(): int32 { return GL_RENDERBUFFER; }

	function floatFeatureBits(): uint32 {
		if (oglHasExtension("OES_texture_float_linear") != 0) { return featureBit("float32-filterable"); }
		return 0;
	}

	@inline function lacksColorBufferFloat(info: FormatInfo): boolean { return info.needsColorBufferFloat; }

	@inline function resetDesktopState(): void {}

	@inline function enableSeamlessCubemaps(): void {}

	@inline function unbindMultisampleTexture(): void {}

	@inline function storeMultisampleTexture(target: int32, sampleCount: int32, internalFormat: int32, width: int32, height: int32): void {}

	@inline function setMultisample(sampleCount: int32): void {}

	@inline function setFramebufferSrgb(on: boolean): void {}

	@inline function setSamplerBorderColor(native: uint32): void {}

	@inline function setSamplerAnisotropy(native: uint32, maxAnisotropy: int32): void {}

	function checkSamplerAnisotropy(maxAnisotropy: int32): void {
		if (maxAnisotropy > 1) {
			stop("GPUSamplerDescriptor.maxAnisotropy above 1 needs EXT_texture_filter_anisotropic, which the GLES backend does not query yet");
		}
	}

	function checkTargetsAlike(ref slot: PipelineSlot, i: int32, first: int32): void {
		if (first != -1 && slot.writeMasks[i] != slot.writeMasks[first]) {
			stop(`fragment.targets[${i}].writeMask differs from target ${first}; GLES3 masks every target alike`);
		}
		if (first != -1 && !sameBlend(slot.blends[i], slot.blends[first])) {
			stop(`fragment.targets[${i}].blend differs from target ${first}; GLES3 blends every target alike`);
		}
	}

	function checkDepthReadback(info: FormatInfo): void {
		if (info.depth) { stop("copyTextureToBuffer of a depth GPUTexture: GLES has no glReadPixels of GL_DEPTH_COMPONENT"); }
	}

	function drawArraysBaseInstance(mode: int32, firstVertex: int32, vertexCount: int32, instanceCount: int32, firstInstance: int32): void {
		stop(`draw with firstInstance ${firstInstance}: GLES3 has no base instance`);
	}

	function drawElementsBaseVertex(
		mode: int32,
		indexCount: int32,
		indexType: int32,
		offset: int64,
		instanceCount: int32,
		baseVertex: int32,
		firstInstance: int32,
	): void {
		stop(`drawIndexed with baseVertex ${baseVertex} and firstInstance ${firstInstance}: GLES3 has neither`);
	}

	function applyBlend(i: int32, next: BlendState, current: BlendState): void {
		if (i == 0) { applyBlendAll(next, current); }
	}

	function applyWriteMask(i: int32, mask: int32): void {
		if (i == 0) { oglColorMask(mask); }
	}
} else {
	const COMPUTE_CONTEXT_VERSION = 430;
	const DEBUG_CONTEXT_VERSION = 430;

	function checkContextVersion(version: int32): void {
		if (version < 430) { stop(`the current context is GL ${version}; the GL backend needs 430`); }
	}

	function multisampleTarget(): int32 { return GL_TEXTURE_2D_MULTISAMPLE; }

	function floatFeatureBits(): uint32 {
		return featureBit("float32-filterable") | featureBit("float32-blendable") | featureBit("rg11b10ufloat-renderable");
	}

	@inline function lacksColorBufferFloat(info: FormatInfo): boolean { return false; }

	function resetDesktopState(): void {
		oglEnable(GL_MULTISAMPLE);
		oglEnable(GL_PROGRAM_POINT_SIZE);
	}

	function enableSeamlessCubemaps(): void { oglEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS); }

	function unbindMultisampleTexture(): void { oglBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0); }

	function storeMultisampleTexture(target: int32, sampleCount: int32, internalFormat: int32, width: int32, height: int32): void {
		oglTexStorage2DMultisample(target, sampleCount, internalFormat, width, height);
	}

	function setMultisample(sampleCount: int32): void {
		if (sampleCount > 1) { oglEnable(GL_MULTISAMPLE); } else { oglDisable(GL_MULTISAMPLE); }
	}

	function setFramebufferSrgb(on: boolean): void {
		if (on) { oglEnable(GL_FRAMEBUFFER_SRGB); } else { oglDisable(GL_FRAMEBUFFER_SRGB); }
	}

	function setSamplerBorderColor(native: uint32): void { oglSamplerBorderColor(native, 0, 0, 0, 1); }

	function setSamplerAnisotropy(native: uint32, maxAnisotropy: int32): void {
		if (maxAnisotropy > 1) {
			oglSamplerParameteri(native, GL_TEXTURE_MAX_ANISOTROPY, smaller(maxAnisotropy, oglGetInteger(GL_MAX_TEXTURE_MAX_ANISOTROPY)));
		}
	}

	@inline function checkSamplerAnisotropy(maxAnisotropy: int32): void {}

	@inline function checkTargetsAlike(ref slot: PipelineSlot, i: int32, first: int32): void {}

	@inline function checkDepthReadback(info: FormatInfo): void {}

	function drawArraysBaseInstance(mode: int32, firstVertex: int32, vertexCount: int32, instanceCount: int32, firstInstance: int32): void {
		oglDrawArraysInstancedBaseInstance(mode, firstVertex, vertexCount, instanceCount, firstInstance);
	}

	function drawElementsBaseVertex(
		mode: int32,
		indexCount: int32,
		indexType: int32,
		offset: int64,
		instanceCount: int32,
		baseVertex: int32,
		firstInstance: int32,
	): void {
		if (instanceCount > 1 || bound.instanced) {
			if (firstInstance == 0) {
				oglDrawElementsInstancedBaseVertex(mode, indexCount, indexType, offset, instanceCount, baseVertex);
			} else {
				oglDrawElementsInstancedBaseVertexBaseInstance(mode, indexCount, indexType, offset, instanceCount, baseVertex, firstInstance);
			}
		} else {
			oglDrawElementsBaseVertex(mode, indexCount, indexType, offset, baseVertex);
		}
	}

	function applyBlend(i: int32, next: BlendState, current: BlendState): void {
		if (next.enabled != current.enabled) {
			if (next.enabled) { oglEnablei(GL_BLEND, i); } else { oglDisablei(GL_BLEND, i); }
		}
		if (
			next.sourceColor != current.sourceColor ||
			next.destinationColor != current.destinationColor ||
			next.sourceAlpha != current.sourceAlpha ||
			next.destinationAlpha != current.destinationAlpha
		) {
			oglBlendFuncSeparatei(i, next.sourceColor, next.destinationColor, next.sourceAlpha, next.destinationAlpha);
		}
		if (next.operationColor != current.operationColor || next.operationAlpha != current.operationAlpha) {
			oglBlendEquationSeparatei(i, next.operationColor, next.operationAlpha);
		}
	}

	function applyWriteMask(i: int32, mask: int32): void { oglColorMaski(i, mask); }
}

function applyVertexBuffers(): void {
	const p = pipelines.slotIndex(bound.pipeline);
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines.slots[p].strides[slot] != 0 && bound.vertexBuffers[slot] == 0) {
			stop(`the pipeline reads vertex buffer ${slot}, which is not set`);
		}
	}
	for (let i = 0; i < maxVertexAttributes; i++) {
		const attribute: VertexAttribute = pipelines.slots[p].attributes[i];
		const cached = cachedAttributes[i];
		if (!attribute.enabled) {
			if (cached.enabled) {
				oglDisableVertexAttribArray(i);
				cachedAttributes[i].enabled = false;
			}
			continue;
		}
		const b = buffers.slotIndex(bound.vertexBuffers[attribute.bufferSlot]);
		const name = buffers.slots[b].names[buffers.slots[b].activeSlot];
		const offset = bound.vertexOffsets[attribute.bufferSlot] + (attribute.offset as int64);
		if (
			name != cached.buffer ||
			attribute.size != cached.size ||
			attribute.attributeType != cached.attributeType ||
			attribute.normalized != cached.normalized ||
			attribute.integer != cached.integer ||
			attribute.stride != cached.stride ||
			offset != cached.offset ||
			attribute.divisor != cached.divisor
		) {
			cacheBindBuffer(GL_ARRAY_BUFFER, name);
			if (attribute.integer) {
				oglVertexAttribIPointer(i, attribute.size, attribute.attributeType, attribute.stride, offset);
			} else {
				oglVertexAttribPointer(i, attribute.size, attribute.attributeType, attribute.normalized, attribute.stride, offset);
			}
			stats.vertexBuffers += 1;
			oglVertexAttribDivisor(i, attribute.divisor);
			cachedAttributes[i] = {
				enabled: cached.enabled,
				buffer: name,
				size: attribute.size,
				attributeType: attribute.attributeType,
				normalized: attribute.normalized,
				integer: attribute.integer,
				stride: attribute.stride,
				offset: offset,
				divisor: attribute.divisor,
			};
		}
		if (!cached.enabled) {
			oglEnableVertexAttribArray(i);
			cachedAttributes[i].enabled = true;
		}
	}
	bound.vertexDirty = false;
}

function applyIndexBuffer(): void {
	if (bound.indexBuffer == 0) { stop("drawIndexed without setIndexBuffer"); }
	const b = buffers.slotIndex(bound.indexBuffer);
	cacheBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffers.slots[b].names[buffers.slots[b].activeSlot]);
	bound.indexDirty = false;
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
	if (shaders.slots[s].pairCount == 0 && shaders.slots[s].storageCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	bindResources(s, bindGroups.slotIndex(bound.bindGroups[GPU_RESOURCE_GROUP]));
}

function bindResources(s: int32, g: int32): void {
	for (let i = 0; i < shaders.slots[s].pairCount; i++) {
		const pair: TexturePair = shaders.slots[s].pairs[i];
		if (pair.unit < 0) { continue; }
		const view = views.slotIndex(bindGroups.slots[g].entries[entryOf(g, pair.textureBinding)].textureView.id);
		const t = textures.slotIndex(views.slots[view].texture);
		const sampler = pair.samplerBinding == DUMMY_SAMPLER_BINDING
			? dummySampler
			: samplers.slots[samplers.slotIndex(bindGroups.slots[g].entries[entryOf(g, pair.samplerBinding)].sampler.id)].native;
		cacheBindTextureSampler(pair.unit, textures.slots[t].target, textures.slots[t].names[textures.slots[t].activeSlot], sampler);
		const lastMip = views.slots[view].baseMip + views.slots[view].mipCount - 1;
		if (textures.slots[t].baseLevel != views.slots[view].baseMip || textures.slots[t].maxLevel != lastMip) {
			cacheActiveTexture(pair.unit);
			oglTexParameteri(textures.slots[t].target, GL_TEXTURE_BASE_LEVEL, views.slots[view].baseMip);
			oglTexParameteri(textures.slots[t].target, GL_TEXTURE_MAX_LEVEL, lastMip);
			textures.slots[t].baseLevel = views.slots[view].baseMip;
			textures.slots[t].maxLevel = lastMip;
		}
	}
	for (let r = 0; r < shaders.slots[s].resourceCount; r++) {
		const resource: ResourceBinding = shaders.slots[s].resources[r];
		if (resource.kind == BindingKind.StorageBuffer) {
			bindStorageBuffer(resource, g);
		} else if (resource.kind == BindingKind.StorageTexture) {
			bindStorageTexture(resource, g);
		}
	}
}

function bindStorageBuffer(resource: ResourceBinding, g: int32): void {
	const entry: GPUBindGroupEntry = bindGroups.slots[g].entries[entryOf(g, resource.binding)];
	const b = buffers.slotIndex(entry.buffer.id);
	const bytes = entry.size == 0 ? buffers.slots[b].size - entry.offset : entry.size;
	oglBindBufferRange(GL_SHADER_STORAGE_BUFFER, resource.nativeSlot as uint32, bufferName(b), entry.offset, bytes);
}

function bindStorageTexture(resource: ResourceBinding, g: int32): void {
	const entry: GPUBindGroupEntry = bindGroups.slots[g].entries[entryOf(g, resource.binding)];
	const v = views.slotIndex(entry.textureView.id);
	const t = textures.slotIndex(views.slots[v].texture);
	const layered = views.slots[v].dimension != ViewDimension.TwoD;
	oglBindImageTexture(
		resource.nativeSlot,
		textureName(t),
		views.slots[v].baseMip,
		layered ? 1 : 0,
		layered ? 0 : views.slots[v].baseLayer,
		resource.access,
		textures.slots[t].info.internalFormat,
	);
}

function applyUniforms(): void {
	const s = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(bound.pipeline)].shader);
	bound.uniformsDirty = false;
	if (shaders.slots[s].uniformCount == 0) { return; }
	if (bound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the pipeline reads bind group 0, which is not set"); }
	const g = bindGroups.slotIndex(bound.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders.slots[s].uniformCount; u++) {
		const uniform: UniformBinding = shaders.slots[s].uniforms[u];
		const e = entryOf(g, uniform.binding);
		const offset = (bound.dynamicOffsets[bindGroups.slots[g].dynamicIndex[e]] as int64) + bindGroups.slots[g].entries[e].offset;
		const b = buffers.slotIndex(bindGroups.slots[g].entries[e].buffer.id);
		if (offset + (uniform.size as int64) > buffers.slots[b].size) {
			stop(`uniform binding ${uniform.binding} at offset ${offset} overruns its buffer`);
		}
		if (uniform.location == -1) { continue; }
		oglUniform4fv(uniform.location, uniform.count, buffers.slots[b].shadow[0], offset);
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers.slots[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	if (buffers.slots[index].uniform) { stop(`${member}: GPUBuffer ${buffer.id} is a CPU shadow uniform block on gl and cannot be copied`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	const index = textures.slotIndex(info.texture.id);
	if (!has(textures.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures.slots[index].swapchainView != 0) {
		if (flag != (GPUTextureUsage.COPY_SRC as int32)) { stop(`${member}: the swapchain texture is the default framebuffer on gl and is only read`); }
		return index;
	}
	if (textures.slots[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
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

@inline function bufferName(index: int32): uint32 { return buffers.slots[index].names[buffers.slots[index].activeSlot]; }

@inline function textureName(index: int32): uint32 { return textures.slots[index].names[textures.slots[index].activeSlot]; }

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedBufferCopy(source.id, buffers.slots[from].size, sourceOffset, destination.id, buffers.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	if (from == to) { stop(`copyBufferToBuffer inside GPUBuffer ${source.id} is not ported to gl yet: a written buffer rotates its in-flight copies`); }
	claimBufferWrite(to, destinationOffset, size, "copyBufferToBuffer");
	oglCopyBufferDataUncached(bufferName(from), sourceOffset, bufferName(to), destinationOffset, size);
	checkError("copyBufferToBuffer");
}

function flipBufferRows(index: int32, offset: int64, span: int64, rowStride: int32, rowBytes: int32, rows: int32): void {
	if (rows < 2) { return; }
	const bytes: Vec<uint8> = new Array(span);
	if (oglGetBufferDataUncached(bufferName(index), offset, bytes[0], span) == 0) {
		stop("copyTextureToBuffer: this GL target cannot read the default framebuffer rows back to flip them");
	}
	const swap: Vec<uint8> = new Array(rowBytes);
	for (let top = 0; top < rows - 1 - top; top++) {
		const upper = (top as int64) * (rowStride as int64);
		const lower = ((rows - 1 - top) as int64) * (rowStride as int64);
		oglCopyBytes(swap[0], 0, bytes[upper], rowBytes as int64);
		oglCopyBytes(bytes[0], upper, bytes[lower], rowBytes as int64);
		oglCopyBytes(bytes[0], lower, swap[0], rowBytes as int64);
	}
	const target = buffers.slots[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, bufferName(index));
	oglBufferSubData(target, offset, bytes[0], span);
	cacheRestoreBuffer(target);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination.buffer, "copyTextureToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const info = texelFormatOf(from, "copyTextureToBuffer source", false, source, size);
	checkDepthReadback(info);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", info.bytesPerPixel, buffers.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (bytesPerRow as int64) * ((size.height - 1) as int64)
		+ ((size.width * info.bytesPerPixel) as int64);
	claimBufferWrite(to, destination.offset, span, "copyTextureToBuffer");
	checkError("copyTextureToBuffer");
	if (textures.slots[from].swapchainView != 0) {
		const format: string = textures.slots[from].format;
		if (format != "rgba8unorm") { stop(`copyTextureToBuffer: the default framebuffer reads as RGBA bytes, which the canvas format ${format} would mislabel`); }
		const read = oglReadScreenRectUncached(
			source.origin.x,
			textures.slots[from].height - (source.origin.y + size.height),
			size.width,
			size.height,
			info.pixelFormat,
			info.pixelType,
			bytesPerRow / info.bytesPerPixel,
			bufferName(to),
			destination.offset,
		);
		if (read == 0) { stop("copyTextureToBuffer: glReadPixels of the default framebuffer failed"); }
		flipBufferRows(to, destination.offset, span, bytesPerRow, size.width * info.bytesPerPixel, size.height);
		return;
	}
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		const read = oglReadTexelsToBufferUncached(
			readFramebuffer,
			textureName(from),
			textures.slots[from].target,
			source.mipLevel,
			source.origin.z + i,
			source.origin.x,
			source.origin.y,
			size.width,
			size.height,
			info.pixelFormat,
			info.pixelType,
			bytesPerRow / info.bytesPerPixel,
			bufferName(to),
			destination.offset + imageBytes * (i as int64),
		);
		if (read == 0) {
			stop(`copyTextureToBuffer: ${textures.slots[from].format} GPUTexture ${source.texture.id} is not color-renderable on this GL target, so it cannot be read back`);
		}
		if (read < 0) {
			stop(`copyTextureToBuffer: this GL target has no read format for ${textures.slots[from].format} GPUTexture ${source.texture.id}`);
		}
	}
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const info = texelFormatOf(to, "copyBufferToTexture destination", true, destination, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", info.bytesPerPixel, buffers.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	rotateOnWholeWrite(to, size);
	const target = textures.slots[to].target;
	const first = destination.origin.z;
	cacheStoreUnit0();
	cacheBindTextureSampler(0, target, textureName(to), 0);
	cacheUnpack(target, bytesPerRow / info.bytesPerPixel, rowsPerImage);
	if (target == GL_TEXTURE_CUBE_MAP) {
		for (let z = 0; z < size.depthOrArrayLayers; z++) {
			oglTexSubImageFromBufferUncached(
				GL_TEXTURE_CUBE_MAP_POSITIVE_X + first + z,
				destination.mipLevel,
				destination.origin.x,
				destination.origin.y,
				0,
				size.width,
				size.height,
				1,
				info.pixelFormat,
				info.pixelType,
				bufferName(from),
				source.offset + imageBytes * (z as int64),
			);
		}
	} else {
		oglTexSubImageFromBufferUncached(
			target,
			destination.mipLevel,
			destination.origin.x,
			destination.origin.y,
			first,
			size.width,
			size.height,
			size.depthOrArrayLayers,
			info.pixelFormat,
			info.pixelType,
			bufferName(from),
			source.offset,
		);
	}
	cacheRestoreUnit0();
	checkError("copyBufferToTexture");
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyTextureToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	if (textures.slots[from].info.depth) { stop("copyTextureToTexture of a depth GPUTexture is not ported to gl yet"); }
	if (textures.slots[from].swapchainView != 0) { stop("copyTextureToTexture from the swapchain texture: the default framebuffer reads only into a buffer on gl"); }
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
	if (from != to) { rotateOnWholeWrite(to, size); }
	const fromFormat: string = textures.slots[from].format;
	checkError("copyTextureToTexture");
	cacheStoreUnit0();
	cacheBindTextureSampler(0, textures.slots[to].target, textureName(to), 0);
	const copied = oglCopyTexels(
		readFramebuffer,
		textureName(from),
		textures.slots[from].target,
		source.mipLevel,
		source.origin.z,
		source.origin.x,
		source.origin.y,
		textures.slots[to].target,
		destination.mipLevel,
		destination.origin.x,
		destination.origin.y,
		destination.origin.z,
		size.width,
		size.height,
		size.depthOrArrayLayers,
	);
	cacheRestoreUnit0();
	if (copied == 0) { stop(`copyTextureToTexture: ${fromFormat} GPUTexture ${source.texture.id} is not color-renderable on this GL target, so it cannot be copied`); }
	if (copied < 0) { stop(`copyTextureToTexture: this GL target refused the copy between ${fromFormat} GPUTexture ${source.texture.id} and ${destination.texture.id}`); }
}

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	const index = buffers.slotIndex(buffer.id);
	const read = mode == (GPUMapMode.READ as int32);
	const length = checkedMapAsync(buffer.id, buffers.slots[index].usage, buffers.slots[index].mapMode, buffers.slots[index].size, mode, offset, size);
	if (read) {
		if (oglGetBufferDataUncached(bufferName(index), offset, buffers.slots[index].shadow[offset], length) == 0) {
			stop(`mapAsync READ of GPUBuffer ${buffer.id}: this GL target cannot read a buffer back`);
		}
		checkError("mapAsync");
	}
	buffers.slots[index].mapMode = mode;
	buffers.slots[index].mapOffset = offset;
	buffers.slots[index].mapSize = length;
}

function mappedRange(member: string, buffer: GPUBuffer, mode: int32, offset: int64, size: int64): int64 {
	const index = buffers.slotIndex(buffer.id);
	const slot = buffers.slots[index];
	return checkedMappedRange(member, buffer.id, slot.size, slot.mapMode, slot.mapOffset, slot.mapSize, mode, offset, size);
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const length = mappedRange("getMappedRange", buffer, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	oglCopyBytes(bytes[0], 0, buffers.slots[buffers.slotIndex(buffer.id)].shadow[offset], length);
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	mappedRange("writeMappedRange", buffer, GPUMapMode.WRITE as int32, offset, bytes);
	const index = buffers.slotIndex(buffer.id);
	const target = buffers.slots[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, bufferName(index));
	oglBufferSubData(target, offset, data[0], bytes);
	cacheRestoreBuffer(target);
}

export function unmap(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	checkedUnmap(buffer.id, buffers.slots[index].mapMode);
	buffers.slots[index].mapMode = 0;
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const s = shaders.slotIndex(descriptor.compute.module.id);
	if (!shaders.slots[s].compute) { stop("createComputePipeline needs a GPUShaderModule made with computeCode"); }
	const entry = descriptor.compute.entryPoint == "" ? "main" : descriptor.compute.entryPoint;
	if (entry != shaders.slots[s].computeEntry) {
		stop(`compute.entryPoint '${entry}' differs from the module's computeEntryPoint '${shaders.slots[s].computeEntry}'`);
	}
	const id = allocate(pipelines);
	const slot: PipelineSlot = { id: id, shader: descriptor.compute.module.id, compute: true };
	store(pipelines, slot);
	return { id: id };
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	if (pass.active || computeBound.active) { stop("beginComputePass with a pass already open"); }
	checkTimestampWrites("GPUComputePassDescriptor.timestampWrites", descriptor.timestampWrites);
	computeBound = {
		active: true,
		groupBase: groupDepth,
		timestampSet: descriptor.timestampWrites.querySet.id,
		timestampEnd: descriptor.timestampWrites.endOfPassWriteIndex,
	};
	computeBound.labeled = labelPass(descriptor.label);
	if (computeBound.timestampSet != 0 && descriptor.timestampWrites.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(computeBound.timestampSet, descriptor.timestampWrites.beginningOfPassWriteIndex);
	}
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
	const s = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(computeBound.pipeline)].shader);
	if (computeBound.pendingBarrier) {
		oglMemoryBarrier(BARRIER_BETWEEN_DISPATCHES);
		computeBound.pendingBarrier = false;
	}
	if (!computeBound.dirty) { return s; }
	computeBound.dirty = false;
	if (shaders.slots[s].program != cache.program) {
		cache.program = shaders.slots[s].program;
		oglUseProgram(cache.program);
	}
	if (shaders.slots[s].pairCount == 0 && shaders.slots[s].storageCount == 0) { return s; }
	if (computeBound.bindGroup == 0) { stop("the compute pipeline reads bind group 1, which is not set"); }
	bindResources(s, bindGroups.slotIndex(computeBound.bindGroup));
	return s;
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	const limit = deviceLimits.maxComputeWorkgroupsPerDimension;
	checkedDispatch(x, y, z, limit);
	const s = applyCompute();
	oglDispatchCompute(x, y, z);
	if (shaders.slots[s].writes) { computeBound.pendingBarrier = true; }
	checkError("dispatchWorkgroups");
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = buffers.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, buffers.slots[b].usage, buffers.slots[b].size, offset);
	const s = applyCompute();
	oglDispatchComputeIndirectUncached(bufferName(b), offset);
	if (shaders.slots[s].writes) { computeBound.pendingBarrier = true; }
	checkError("dispatchWorkgroupsIndirect");
}

export function endComputePass(): void {
	if (!computeBound.active) { stop("end without an open compute pass"); }
	checkGroupsClosed(computeBound.groupBase, "end");
	if (computeBound.pendingBarrier) { oglMemoryBarrier(BARRIER_ALL); }
	if (computeBound.timestampSet != 0 && computeBound.timestampEnd >= 0) {
		writeTimestamp(computeBound.timestampSet, computeBound.timestampEnd);
	}
	if (computeBound.labeled) { endLabel(); }
	computeBound = { active: false };
}

@noinline function stopOnNoCompute(what: string): void {
	if (computeSupported) { return; }
	when (webgl2) {
		stop(`${what} is not available on WebGL2: it has no compute shaders or shader storage buffers (GL 4.3 or GLES 3.1 required)`);
	} else {
		stop(`${what} needs compute shaders and shader storage buffers, absent from context version ${contextVersion} (GL 4.3 or GLES 3.1 required)`);
	}
}

function nameObject(identifier: int32, name: uint32, label: string | null): void {
	if (label === null || !debugSupported) { return; }
	oglObjectLabel(identifier, name, label);
}

function queryLimits(): GPUSupportedLimits {
	const textureSize = oglGetInteger(GL_MAX_TEXTURE_SIZE);
	const units = smaller(smaller(oglGetInteger(GL_MAX_TEXTURE_IMAGE_UNITS), maxTextureUnits), GPU_MAX_BIND_GROUP_ENTRIES);
	const uniformComponents = smaller(oglGetInteger(GL_MAX_VERTEX_UNIFORM_COMPONENTS), oglGetInteger(GL_MAX_FRAGMENT_UNIFORM_COMPONENTS));
	let value: GPUSupportedLimits = {
		maxTextureDimension1D: textureSize,
		maxTextureDimension2D: textureSize,
		maxTextureDimension3D: oglGetInteger(GL_MAX_3D_TEXTURE_SIZE),
		maxTextureArrayLayers: oglGetInteger(GL_MAX_ARRAY_TEXTURE_LAYERS),
		maxBindGroups: GPU_RESOURCE_GROUP + 1,
		maxSampledTexturesPerShaderStage: units,
		maxSamplersPerShaderStage: units,
		maxStorageBuffersPerShaderStage: 0,
		maxStorageTexturesPerShaderStage: 0,
		maxUniformBuffersPerShaderStage: GPU_MAX_UNIFORM_BLOCKS,
		maxUniformBufferBindingSize: (uniformComponents as int64) * 4,
		maxStorageBufferBindingSize: 0,
		maxVertexBuffers: GPU_MAX_VERTEX_BUFFERS,
		maxVertexAttributes: maxVertexAttributes,
		maxColorAttachments: smaller(oglGetInteger(GL_MAX_COLOR_ATTACHMENTS), GPU_MAX_COLOR_ATTACHMENTS),
		maxComputeWorkgroupSizeX: 0,
		maxComputeWorkgroupSizeY: 0,
		maxComputeWorkgroupSizeZ: 0,
		maxComputeInvocationsPerWorkgroup: 0,
		maxComputeWorkgroupsPerDimension: 0,
		minUniformBufferOffsetAlignment: UNIFORM_OFFSET_ALIGNMENT,
		minStorageBufferOffsetAlignment: STORAGE_OFFSET_ALIGNMENT,
	};
	if (!computeSupported) { return value; }
	maxStorageBindings = oglGetInteger(GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS);
	maxImageUnits = oglGetInteger(GL_MAX_IMAGE_UNITS);
	value.maxStorageBuffersPerShaderStage = smaller(smaller(oglGetInteger(GL_MAX_COMPUTE_SHADER_STORAGE_BLOCKS), maxStorageBindings), GPU_MAX_BIND_GROUP_ENTRIES);
	value.maxStorageTexturesPerShaderStage = smaller(smaller(oglGetInteger(GL_MAX_COMPUTE_IMAGE_UNIFORMS), maxImageUnits), GPU_MAX_BIND_GROUP_ENTRIES);
	value.maxStorageBufferBindingSize = oglGetInteger64(GL_MAX_SHADER_STORAGE_BLOCK_SIZE);
	value.maxComputeWorkgroupSizeX = oglGetIntegeri(GL_MAX_COMPUTE_WORK_GROUP_SIZE, 0);
	value.maxComputeWorkgroupSizeY = oglGetIntegeri(GL_MAX_COMPUTE_WORK_GROUP_SIZE, 1);
	value.maxComputeWorkgroupSizeZ = oglGetIntegeri(GL_MAX_COMPUTE_WORK_GROUP_SIZE, 2);
	value.maxComputeInvocationsPerWorkgroup = oglGetInteger(GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS);
	value.maxComputeWorkgroupsPerDimension = smaller(
		smaller(oglGetIntegeri(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 0), oglGetIntegeri(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 1)),
		oglGetIntegeri(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 2),
	);
	return value;
}

function queryFeatures(): GPUSupportedFeatures {
	let bits: uint32 = 0;
	if (timerSupported) { bits |= featureBit("timestamp-query"); }
	bits |= floatFeatureBits();
	return { bits: bits };
}

export function limits(): GPUSupportedLimits { return deviceLimits; }

export function features(): GPUSupportedFeatures { return deviceFeatures; }

export function pushDebugGroup(label: string): void {
	if (groupDepth >= MAX_DEBUG_GROUPS) { stop(`pushDebugGroup nested over ${MAX_DEBUG_GROUPS} deep, the minimum GL_MAX_DEBUG_GROUP_STACK_DEPTH leaves`); }
	if (debugSupported) { oglPushDebugGroup(label); }
	groupDepth += 1;
}

export function popDebugGroup(): void {
	const base = pass.active ? pass.groupBase : (computeBound.active ? computeBound.groupBase : 0);
	checkedPopDebugGroup(groupDepth, base);
	if (debugSupported) { oglPopDebugGroup(); }
	groupDepth -= 1;
}

export function insertDebugMarker(label: string): void {
	if (debugSupported) { oglDebugMarker(label); }
}

function labelPass(label: string | null): boolean {
	if (label === null) { return false; }
	if (debugSupported) { oglPushDebugGroup(label); }
	return true;
}

function endLabel(): void {
	if (debugSupported) { oglPopDebugGroup(); }
}

@noinline function checkGroupsClosed(base: int32, what: string): void {
	if (groupDepth != base) { stop(`${what} with ${groupDepth - base} debug groups still open`); }
}

function timestampReason(): string {
	when (webgl2) {
		return "WebGL2 hands back query results only after the page returns to the event loop, so the blocking resolveQuerySet could never read a timestamp";
	} else {
		when (android) {
			return "the GLES backend does not load EXT_disjoint_timer_query, and GLES 3.2 has no GL_TIMESTAMP counter";
		} else {
			return "GL_TIMESTAMP reports 0 counter bits on this context";
		}
	}
}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	if (kind != "timestamp" && kind != "occlusion") { stopOnMember("GPUQuerySetDescriptor.type", kind); }
	const timestamp = kind == "timestamp";
	checkedQuerySetCount(descriptor.count);
	if (timestamp && !timerSupported) {
		stop(`this device has no timestamp queries: features().has('timestamp-query') is false, because ${timestampReason()}`);
	}
	const id = allocate(querySets);
	let slot: QuerySetSlot = {
		id: id,
		timestamp: timestamp,
		count: descriptor.count,
		names: [],
		state: new Array(descriptor.count),
		usedPass: new Array(descriptor.count),
	};
	for (let i = 0; i < descriptor.count; i++) { slot.names.push(oglCreateQuery()); }
	checkErrorOf("createQuerySet", descriptor.label);
	store(querySets, slot);
	return { id: id };
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySets.slotIndex(querySet.id);
	for (let i = 0; i < querySets.slots[index].names.length; i++) { oglDeleteQuery(querySets.slots[index].names[i]); }
	querySets.slots[index] = { id: 0 };
	release(querySets, querySet.id);
}

function writeTimestamp(querySet: uint32, queryIndex: int32): void {
	const q = querySets.slotIndex(querySet);
	oglQueryCounter(querySets.slots[q].names[queryIndex]);
	querySets.slots[q].state[queryIndex] = QUERY_WRITTEN;
}

@noinline function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySets.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets.slots[q].timestamp, querySets.slots[q].count);
}

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
	let values: Vec<uint64> = new Array(queryCount);
	for (let i = 0; i < queryCount; i++) {
		const state = querySets.slots[q].state[firstQuery + i];
		if (state == QUERY_UNWRITTEN) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QUERY_OPEN) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
		const name = querySets.slots[q].names[firstQuery + i];
		when (webgl2) {
			if (oglQueryAvailable(name) == 0) {
				stop(`resolveQuerySet: query ${firstQuery + i} is not ready, because WebGL2 delivers query results only after the page returns to the event loop: resolve it in a later task than the pass that wrote it`);
			}
		}
		values[i] = oglQueryResult(name);
	}
	const target = buffers.slots[b].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, bufferName(b));
	oglBufferSubData(target, destinationOffset, values[0], bytes);
	cacheRestoreBuffer(target);
	checkError("resolveQuerySet");
}

function occlusionTarget(): int32 {
	return exactSamples ? GL_SAMPLES_PASSED : GL_ANY_SAMPLES_PASSED;
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
	querySets.slots[q].state[queryIndex] = QUERY_OPEN;
	oglBeginQuery(occlusionTarget(), querySets.slots[q].names[queryIndex]);
	pass.occlusionOpen = true;
	pass.occlusionIndex = queryIndex;
}

export function endOcclusionQuery(): void {
	if (!pass.active || !pass.occlusionOpen) { stop("endOcclusionQuery without an open occlusion query"); }
	const q = querySets.slotIndex(pass.occlusionSet);
	oglEndQuery(occlusionTarget());
	querySets.slots[q].state[pass.occlusionIndex] = QUERY_WRITTEN;
	pass.occlusionOpen = false;
}
