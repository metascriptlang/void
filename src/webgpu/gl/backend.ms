import {
	BindingKind,
	bindingKind,
	linearFilter,
	compareNative,
	blendFactorNative,
	blendOperationNative,
	stencilOperationNative,
	vertexFormatNative,
	addressModeNative,
	topologyNative,
	FORMAT_COUNT,
	nativeAt,
	textureFormatFacts,
	stopOnFormat,
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
	checkedDepthTexelCopy,
	samplerMaxLod,
	checkedTexelBufferLayout,
	checkedTexelWritePitch,
	DUMMY_SAMPLER_BINDING,
	featureBit,
	stopOnUnportedShaderBindings,
	stopOnUnportedShaderBytecode,
	labelOf,
} from "../types.ms";
import {
	currentFrame,
	entryOf,
	clampedAnisotropy,
	cachedCanvas,
	cachedLimits,
	addressesBinding,
	checkedBufferRewrite,
	checkedComputeModule,
	checkedRenderModule,
	markBufferWritten,
	occlusionSetId,
	openDebugGroups,
	stencil8Mask,
	boundFacts,
	colorWriteBits,
	isIntegerFormat,
} from "../validate.ms";
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
	slotOf,
	textureRecords,
	vacate,
	viewRecords,
} from "../pool.ms";
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
	oglClearStencil,
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

when (webgl2 || android || (linux && voidGles3)) {
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
		oglMultiDrawElementsIndirectUncached,
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
const GL_MAX_SAMPLES = 0x8D57;
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
	uniform: boolean;
	storage: boolean;
	mapRead: boolean;
	target: int32;
	names: uint32[2];
	slotCount: int32;
	activeSlot: int32;
	shadow: Vec<uint8>;
}

struct TextureSlot {
	info: FormatInfo;
	cubeMap: boolean;
	baseLevel: int32;
	maxLevel: int32;
	target: int32;
	names: uint32[2];
	slotCount: int32;
	activeSlot: int32;
}

struct ViewSlot {
	sampled: boolean;
	resolveFramebuffer: uint32;
	dimension: ViewDimension;
}

struct SamplerSlot {
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
	cullFace: int32;
	frontFace: int32;
	sampleCount: int32;
	compute: boolean;
}

struct BindGroupSlot {
	group: int32;
	entries: GPUBindGroupEntry[8];
	entryCount: int32;
}

struct QuerySetSlot {
	names: Vec<uint32>;
}

struct ComputeState {
	labeled: boolean;
	timestampSet: uint32;
	timestampEnd: int32;
	dirty: boolean;
	pendingBarrier: boolean;
}

struct PassState {
	labeled: boolean;
	timestampSet: uint32;
	timestampEnd: int32;
	swapchain: boolean;
	width: int32;
	height: int32;
	colorViews: uint32[4];
	resolveViews: uint32[4];
	colorSlices: int32[4];
}

struct BoundState {
	appliedPipeline: uint32;
	instanced: boolean;
	indexType: int32;
	indexSize: int32;
	stencilReference: int32;
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

let pass: PassState = { width: 0 };
let bound: BoundState = { appliedPipeline: 0 };
let computeBound: ComputeState = { dirty: false };
let contextVersion: int32 = 0;
let computeSupported = false;
let debugSupported = false;
let timerSupported = false;
let exactSamples = false;
let maxStorageBindings: int32 = 0;
let maxImageUnits: int32 = 0;
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

export const BACKEND = "gl";

let buffers: Vec<BufferSlot> = [{}];
let textures: Vec<TextureSlot> = [{}];
let views: Vec<ViewSlot> = [{}];
let samplers: Vec<SamplerSlot> = [{}];
let shaders: Vec<ShaderSlot> = [{}];
let pipelines: Vec<PipelineSlot> = [{}];
let bindGroups: Vec<BindGroupSlot> = [{}];
let querySets: Vec<QuerySetSlot> = [{}];

@noinline function stop(message: string): never {
	console.log(`webgpu gl: ${message}`);
	unreachable;
}

@noinline function stopOnMember(member: string, value: string): int32 {
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

struct GlFormat {
	internalFormat: int32;
	pixelFormat: int32;
	pixelType: int32;
	needsColorBufferFloat: boolean;
}

const NO_GL_FORMAT: GlFormat = { internalFormat: 0, pixelFormat: 0, pixelType: 0, needsColorBufferFloat: false };

const GL_FORMATS: GlFormat[] = [
	{ internalFormat: GL_R8, pixelFormat: GL_RED, pixelType: GL_UNSIGNED_BYTE, needsColorBufferFloat: false },
	{ internalFormat: GL_RG8, pixelFormat: GL_RG, pixelType: GL_UNSIGNED_BYTE, needsColorBufferFloat: false },
	{ internalFormat: GL_RGBA8, pixelFormat: GL_RGBA, pixelType: GL_UNSIGNED_BYTE, needsColorBufferFloat: false },
	{ internalFormat: GL_SRGB8_ALPHA8, pixelFormat: GL_RGBA, pixelType: GL_UNSIGNED_BYTE, needsColorBufferFloat: false },
	NO_GL_FORMAT,
	NO_GL_FORMAT,
	{ internalFormat: GL_RGBA8UI, pixelFormat: GL_RGBA_INTEGER, pixelType: GL_UNSIGNED_BYTE, needsColorBufferFloat: false },
	{ internalFormat: GL_RGBA8I, pixelFormat: GL_RGBA_INTEGER, pixelType: GL_BYTE, needsColorBufferFloat: false },
	{ internalFormat: GL_R16F, pixelFormat: GL_RED, pixelType: GL_HALF_FLOAT, needsColorBufferFloat: false },
	{ internalFormat: GL_RG16F, pixelFormat: GL_RG, pixelType: GL_HALF_FLOAT, needsColorBufferFloat: false },
	{ internalFormat: GL_RGBA16F, pixelFormat: GL_RGBA, pixelType: GL_HALF_FLOAT, needsColorBufferFloat: false },
	{ internalFormat: GL_RGBA16UI, pixelFormat: GL_RGBA_INTEGER, pixelType: GL_UNSIGNED_SHORT, needsColorBufferFloat: false },
	{ internalFormat: GL_R32F, pixelFormat: GL_RED, pixelType: GL_FLOAT, needsColorBufferFloat: true },
	{ internalFormat: GL_RG32F, pixelFormat: GL_RG, pixelType: GL_FLOAT, needsColorBufferFloat: true },
	{ internalFormat: GL_RGBA32F, pixelFormat: GL_RGBA, pixelType: GL_FLOAT, needsColorBufferFloat: true },
	{ internalFormat: GL_RGBA32UI, pixelFormat: GL_RGBA_INTEGER, pixelType: GL_UNSIGNED_INT, needsColorBufferFloat: false },
	{ internalFormat: GL_R32UI, pixelFormat: GL_RED_INTEGER, pixelType: GL_UNSIGNED_INT, needsColorBufferFloat: false },
	{ internalFormat: GL_RGB10_A2, pixelFormat: GL_RGBA, pixelType: GL_UNSIGNED_INT_2_10_10_10_REV, needsColorBufferFloat: false },
	{ internalFormat: GL_R11F_G11F_B10F, pixelFormat: GL_RGB, pixelType: GL_UNSIGNED_INT_10F_11F_11F_REV, needsColorBufferFloat: true },
	{ internalFormat: GL_DEPTH_COMPONENT16, pixelFormat: GL_DEPTH_COMPONENT, pixelType: GL_UNSIGNED_SHORT, needsColorBufferFloat: false },
	{ internalFormat: GL_DEPTH_COMPONENT32F, pixelFormat: GL_DEPTH_COMPONENT, pixelType: GL_FLOAT, needsColorBufferFloat: false },
	{ internalFormat: GL_DEPTH32F_STENCIL8, pixelFormat: GL_DEPTH_STENCIL, pixelType: GL_FLOAT_32_UNSIGNED_INT_24_8_REV, needsColorBufferFloat: false },
];

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	const facts = textureFormatFacts(value, member, "gl");
	const native = nativeAt(GL_FORMATS, FORMAT_COUNT, facts.index, "gl", "GL format");
	if (native.internalFormat == 0) { stopOnFormat("gl", member, value); }
	return {
		internalFormat: native.internalFormat,
		pixelFormat: native.pixelFormat,
		pixelType: native.pixelType,
		bytesPerPixel: facts.bytesPerPixel,
		depth: facts.depth,
		stencil: facts.stencil,
		integer: isIntegerFormat(value),
		needsColorBufferFloat: native.needsColorBufferFloat,
	};
}

const COMPARE_FUNCTIONS: int32[] = [GL_NEVER, GL_LESS, GL_EQUAL, GL_LEQUAL, GL_GREATER, GL_NOTEQUAL, GL_GEQUAL, GL_ALWAYS];

function compareFunction(compare: string, member: string): int32 { return compareNative(COMPARE_FUNCTIONS, compare, member, "gl"); }

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

const BLEND_FACTORS: int32[] = [
	GL_ZERO, GL_ONE, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR,
	GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_SRC_ALPHA_SATURATE, GL_CONSTANT_COLOR, GL_ONE_MINUS_CONSTANT_COLOR,
];

function blendFactor(factor: string, member: string): int32 { return blendFactorNative(BLEND_FACTORS, factor, member, "gl"); }

function destinationFactor(factor: string, member: string): int32 {
	if (factor == "") { return GL_ZERO; }
	return blendFactor(factor, member);
}

const BLEND_OPERATIONS: int32[] = [GL_FUNC_ADD, GL_FUNC_SUBTRACT, GL_FUNC_REVERSE_SUBTRACT, GL_MIN, GL_MAX];

function blendOperation(operation: string, member: string): int32 { return blendOperationNative(BLEND_OPERATIONS, operation, member, "gl"); }

function vertexFormat(components: int32, componentType: int32, normalized: int32, integer: boolean): VertexFormatInfo {
	return { components: components, componentType: componentType, normalized: normalized, integer: integer };
}

const VERTEX_FORMATS: VertexFormatInfo[] = [
	vertexFormat(2, GL_UNSIGNED_BYTE, 0, true),
	vertexFormat(4, GL_UNSIGNED_BYTE, 0, true),
	vertexFormat(2, GL_BYTE, 0, true),
	vertexFormat(4, GL_BYTE, 0, true),
	vertexFormat(2, GL_UNSIGNED_BYTE, 1, false),
	vertexFormat(4, GL_UNSIGNED_BYTE, 1, false),
	vertexFormat(2, GL_BYTE, 1, false),
	vertexFormat(4, GL_BYTE, 1, false),
	vertexFormat(2, GL_UNSIGNED_SHORT, 0, true),
	vertexFormat(4, GL_UNSIGNED_SHORT, 0, true),
	vertexFormat(2, GL_SHORT, 0, true),
	vertexFormat(4, GL_SHORT, 0, true),
	vertexFormat(2, GL_UNSIGNED_SHORT, 1, false),
	vertexFormat(4, GL_UNSIGNED_SHORT, 1, false),
	vertexFormat(2, GL_SHORT, 1, false),
	vertexFormat(4, GL_SHORT, 1, false),
	vertexFormat(2, GL_HALF_FLOAT, 0, false),
	vertexFormat(4, GL_HALF_FLOAT, 0, false),
	vertexFormat(1, GL_FLOAT, 0, false),
	vertexFormat(2, GL_FLOAT, 0, false),
	vertexFormat(3, GL_FLOAT, 0, false),
	vertexFormat(4, GL_FLOAT, 0, false),
	vertexFormat(1, GL_UNSIGNED_INT, 0, true),
	vertexFormat(2, GL_UNSIGNED_INT, 0, true),
	vertexFormat(3, GL_UNSIGNED_INT, 0, true),
	vertexFormat(4, GL_UNSIGNED_INT, 0, true),
	vertexFormat(1, GL_INT, 0, true),
	vertexFormat(2, GL_INT, 0, true),
	vertexFormat(3, GL_INT, 0, true),
	vertexFormat(4, GL_INT, 0, true),
];

function vertexFormatInfo(format: string): VertexFormatInfo { return vertexFormatNative(VERTEX_FORMATS, format, "vertex attribute format", "gl"); }

const PRIMITIVE_MODES: int32[] = [GL_POINTS, GL_LINES, GL_LINE_STRIP, GL_TRIANGLES, GL_TRIANGLE_STRIP];

function primitiveMode(topology: string): int32 { return topologyNative(PRIMITIVE_MODES, topology, "primitive.topology", "gl"); }

const STENCIL_OPERATIONS: int32[] = [GL_KEEP, GL_ZERO, GL_REPLACE, GL_INVERT, GL_INCR, GL_DECR, GL_INCR_WRAP, GL_DECR_WRAP];

function stencilOperation(operation: string, member: string): int32 { return stencilOperationNative(STENCIL_OPERATIONS, operation, member, "gl"); }

function stencilFace(face: GPUStencilFaceState, member: string): StencilFace {
	return {
		compare: compareFunction(face.compare, `${member}.compare`),
		failOp: stencilOperation(face.failOp, `${member}.failOp`),
		depthFailOp: stencilOperation(face.depthFailOp, `${member}.depthFailOp`),
		passOp: stencilOperation(face.passOp, `${member}.passOp`),
	};
}

const ADDRESS_MODES: int32[] = [GL_CLAMP_TO_EDGE, GL_REPEAT, GL_MIRRORED_REPEAT];

function addressMode(mode: string, member: string): int32 { return addressModeNative(ADDRESS_MODES, mode, member, "gl"); }

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
	if (cachedCanvas().sampleCount > oglGetInteger(GL_MAX_SAMPLES)) { stopOnMember("NativeEnvironment.sampleCount", `${cachedCanvas().sampleCount}`); }
	contextVersion = version;
	const capabilities = oglCapabilities();
	computeSupported = (capabilities & OGL_CAPABILITY_COMPUTE) != 0 && version >= COMPUTE_CONTEXT_VERSION;
	debugSupported = (capabilities & OGL_CAPABILITY_DEBUG) != 0 && version >= DEBUG_CONTEXT_VERSION;
	timerSupported = (capabilities & OGL_CAPABILITY_TIMER) != 0 && oglQueryCounterBits() > 0;
	exactSamples = (capabilities & OGL_CAPABILITY_EXACT_SAMPLES) != 0;
	if (computeSupported) {
		maxStorageBindings = oglGetInteger(GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS);
		maxImageUnits = oglGetInteger(GL_MAX_IMAGE_UNITS);
	}
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
	pass = { width: 0 };
	bound = { appliedPipeline: 0 };
	computeBound = { dirty: false };
	return { id: 1, queue: { id: 1 } };
}

export function adoptSwapchain(color: uint32, depth: uint32): void {
	swapchainColor = color;
	swapchainDepth = depth;
	adoptSwapchainTexture(color, "NativeEnvironment.colorFormat");
	if (depth != 0) { adoptSwapchainTexture(depth, "NativeEnvironment.depthFormat"); }
}

function adoptSwapchainTexture(id: uint32, member: string): void {
	put(textures, id, { info: formatInfo(textureRecords.record(id).format, member) });
	put(views, textureRecords.record(id).swapchainView, views[0]);
}

export function formatRenderable(format: GPUTextureFormat): boolean {
	const value: string = format;
	if (value == "bgra8unorm" || value == "bgra8unorm-srgb") { return false; }
	const info = formatInfo(format, "formatRenderable format");
	return !info.integer && !lacksColorBufferFloat(info);
}

export function shutdown(): void {
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
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "glcore", originTopLeft: false, depthZeroToOne: false };
}

export function createBuffer(id: uint32, descriptor: GPUBufferDescriptor): void {
	const usage = descriptor.usage;
	const storage = has(usage, GPUBufferUsage.STORAGE as int32);
	const indirect = has(usage, GPUBufferUsage.INDIRECT as int32);
	const resolve = has(usage, GPUBufferUsage.QUERY_RESOLVE as int32);
	if (storage) { stopOnNoCompute("GPUBufferUsage.STORAGE"); }
	if (indirect) { stopOnNoCompute("GPUBufferUsage.INDIRECT"); }
	const mapRead = has(usage, GPUBufferUsage.MAP_READ as int32);
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
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
	if (storage && descriptor.size > cachedLimits().maxStorageBufferBindingSize) {
		stop(`a STORAGE buffer of ${descriptor.size} bytes is over the limit of ${cachedLimits().maxStorageBufferBindingSize}`);
	}
	when (webgl2) {
		if ((usage & vertexOrIndex) == vertexOrIndex) { stop("WebGL2 binds a buffer as VERTEX or as INDEX, not both"); }
	}
	const writable = has(usage, GPUBufferUsage.COPY_DST as int32);
	let slot: BufferSlot = {
		uniform: uniform,
		storage: storage,
		mapRead: mapRead,
		target: has(usage, GPUBufferUsage.INDEX as int32) ? GL_ELEMENT_ARRAY_BUFFER : GL_ARRAY_BUFFER,
		slotCount: writable && !mapRead && !storage && !indirect && !resolve ? INFLIGHT_SLOTS : 1,
		activeSlot: 0,
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
	put(buffers, id, slot);
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = bufferRecords.slotIndex(buffer.id);
	if (!buffers[index].uniform) {
		for (let s = 0; s < buffers[index].slotCount; s++) {
			cacheInvalidateBuffer(buffers[index].names[s]);
			oglDeleteBuffer(buffers[index].names[s]);
		}
	}
	vacate(buffers, buffer.id);
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferRecords.slotIndex(buffer.id);
	rotateOnFirstWrite(index);
	if (buffers[index].uniform) {
		oglCopyBytes(buffers[index].shadow[0], offset, data[0], bytes);
		bound.uniformsDirty = true;
		return;
	}
	const target = buffers[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, buffers[index].names[buffers[index].activeSlot]);
	oglBufferSubData(target, offset, data[0], bytes);
	cacheRestoreBuffer(target);
}

function rotateOnFirstWrite(index: int32): void {
	if (buffers[index].uniform || bufferRecords.slots[index].writtenFrame == currentFrame()) { return; }
	buffers[index].activeSlot = (buffers[index].activeSlot + 1) % buffers[index].slotCount;
	bound.vertexDirty = true;
	bound.indexDirty = true;
}

function claimBufferCopy(index: int32, offset: int64, bytes: int64, member: string): void {
	if (buffers[index].mapRead) { return; }
	checkedBufferRewrite(index, member, offset);
	rotateOnFirstWrite(index);
	markBufferWritten(index, offset, bytes);
}

export function createTexture(texture: TextureRecord, descriptor: GPUTextureDescriptor): void {
	const id = texture.id;
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = texture.width;
	const height = texture.height;
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = texture.volume;
	const layers = texture.layers;
	const mipLevels = texture.mipLevels;
	const sampleCount = texture.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const usage = texture.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
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
	if (attachment && info.integer) {
		stop(`${descriptor.format} as RENDER_ATTACHMENT is not ported to gl: clearing an integer target needs glClearBufferuiv or glClearBufferiv`);
	}
	if (attachment && lacksColorBufferFloat(info)) {
		stop(`${descriptor.format} as RENDER_ATTACHMENT needs EXT_color_buffer_float, which the GLES backend does not query yet`);
	}
	const cubeMap = texture.cube && layers == 6;
	let target = GL_TEXTURE_2D;
	if (volume) {
		target = GL_TEXTURE_3D;
	} else if (cubeMap) {
		target = GL_TEXTURE_CUBE_MAP;
	} else if (layers > 1) {
		target = GL_TEXTURE_2D_ARRAY;
	} else if (sampleCount > 1) {
		target = multisampleTarget();
	}
	const rotates = copyDestination && mipLevels == 1 && layers == 1 && !volume && !storage;
	let slot: TextureSlot = {
		info: info,
		cubeMap: cubeMap,
		baseLevel: 0,
		maxLevel: mipLevels - 1,
		target: target,
		slotCount: rotates ? INFLIGHT_SLOTS : 1,
		activeSlot: 0,
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
	put(textures, id, slot);
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textureRecords.slotIndex(texture.id);
	if (textures[index].target == GL_RENDERBUFFER) {
		oglDeleteRenderbuffer(textures[index].names[0]);
		vacate(textures, texture.id);
		return;
	}
	for (let s = 0; s < textures[index].slotCount; s++) {
		cacheInvalidateTextureSampler(textures[index].names[s], 0);
		oglDeleteTexture(textures[index].names[s]);
	}
	vacate(textures, texture.id);
}

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	const t = textureRecords.slotIndex(texture.id);
	if (textureRecords.slots[t].swapchainView != 0) { stop("the swapchain texture is the default framebuffer and has no GL texture"); }
	return oglTextureNative(textures[t].names[textures[t].activeSlot]);
}

function rotateOnWholeWrite(index: int32, size: GPUExtent3D): void {
	const wholeTexture = textures[index].slotCount > 1 && size.width == textureRecords.slots[index].width && size.height == textureRecords.slots[index].height;
	if (wholeTexture) {
		textures[index].activeSlot = (textures[index].activeSlot + 1) % textures[index].slotCount;
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
	const index = textureRecords.slotIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	if (!has(textureRecords.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textureRecords.slots[index].id}, created without COPY_DST`);
	}
	const info = textures[index].info;
	const mip = destination.mipLevel;
	const mips = textureRecords.slots[index].mipLevels;
	const volume = textureRecords.slots[index].volume;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textureRecords.slots[index].layers >> mip) : textureRecords.slots[index].layers;
	const rowPitch = checkedTexelWritePitch(
		textureRecords.slots[index].width,
		textureRecords.slots[index].height,
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
	const target = textures[index].target;
	const first = destination.origin.z;
	const count = size.depthOrArrayLayers;
	cacheStoreUnit0();
	cacheBindTextureSampler(0, target, textures[index].names[textures[index].activeSlot], 0);
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

function viewDimensionOf(name: string): ViewDimension {
	return match (name) {
		"2d" => ViewDimension.TwoD,
		"2d-array" => ViewDimension.TwoDArray,
		"cube" => ViewDimension.Cube,
		"3d" => ViewDimension.ThreeD,
		_ => stopOnMember("GPUTextureViewDescriptor.dimension", name) as ViewDimension,
	};
}

export function createView(view: ViewRecord, descriptor: GPUTextureViewDescriptor): void {
	const t = textureRecords.slotIndex(view.texture);
	const dimension = viewDimensionOf(view.dimension);
	if (dimension == ViewDimension.Cube && !textures[t].cubeMap) {
		stop(`a cube view needs GPUTexture ${textureRecords.slots[t].id} created square with exactly 6 layers and TEXTURE_BINDING: gl makes it a cube map`);
	}
	put(views, view.id, {
		sampled: has(textureRecords.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32),
		resolveFramebuffer: 0,
		dimension: dimension,
	});
}

@noinline function checkSampledView(binding: int32, v: int32): void {
	const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
	const target = textures[t].target;
	const dimension = views[v].dimension;
	const whole = viewRecords.slots[v].baseLayer == 0 && viewRecords.slots[v].layerCount == textureRecords.slots[t].layers;
	if (target == GL_TEXTURE_3D && dimension == ViewDimension.ThreeD) { return; }
	if (target == GL_TEXTURE_CUBE_MAP && dimension == ViewDimension.Cube) { return; }
	if (target == GL_TEXTURE_2D_ARRAY && dimension == ViewDimension.TwoDArray && whole) { return; }
	if (target == GL_TEXTURE_2D && dimension == ViewDimension.TwoD) { return; }
	if (target == GL_TEXTURE_2D_MULTISAMPLE && dimension == ViewDimension.TwoD) { return; }
	stop(`bind group entry ${binding}: a ${viewDimensionName(dimension)} view of ${layersName(t)} GPUTexture ${textureRecords.slots[t].id} cannot be sampled on gl without texture views (GL 4.3 glTextureView, absent in GLES3)`);
}

function layersName(t: int32): string {
	if (textureRecords.slots[t].volume) { return "a 3d"; }
	if (textures[t].cubeMap) { return "a cube-map"; }
	return textureRecords.slots[t].layers > 1 ? "a 2d-array" : "a 2d";
}

export function destroyView(view: GPUTextureView): void {
	const index = viewRecords.slotIndex(view.id);
	oglDeleteFramebuffer(views[index].resolveFramebuffer);
	vacate(views, view.id);
}

export function acquireSwapchain(swapchain: NativeSwapchain): void {
}

export function createSampler(id: uint32, descriptor: GPUSamplerDescriptor): void {
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter", "gl");
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter", "gl");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter", "gl");
	const maxLod = samplerMaxLod(descriptor.lodMaxClamp);
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
	setSamplerAnisotropy(native, clampedAnisotropy(descriptor.maxAnisotropy));
	nameObject(GL_SAMPLER, native, descriptor.label);
	checkErrorOf("createSampler", descriptor.label);
	const slot: SamplerSlot = { native: native };
	put(samplers, id, slot);
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplerRecords.slotIndex(sampler.id);
	cacheInvalidateTextureSampler(0, samplers[index].native);
	oglDeleteSampler(samplers[index].native);
	vacate(samplers, sampler.id);
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

export function createShaderModule(id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	stopOnUnportedShaderBindings("gl", descriptor);
	stopOnUnportedShaderBytecode("gl", descriptor);
	const compute = descriptor.computeCode != "";
	if (compute) {
		stopOnNoCompute("a compute GPUShaderModule");
	}
	let slot: ShaderSlot = {};
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const kind = bindingKind(kindName, "gl");
		const binding = descriptor.bindings[i].binding;
		const writable = bindingWritable(descriptor.bindings[i]);
		if (writable && !compute) {
			stop(`shader binding ${binding} is writable storage in a render stage, which gl does not port: bind it read-only or write it from a compute pass`);
		}
		if (kind == BindingKind.Uniform) {
			if (compute) { stop(`uniform binding ${binding} in a compute stage is not ported to gl yet`); }
			const size = descriptor.bindings[i].size;
			if (size % 16 != 0) { stop(`uniform binding ${binding} needs a block size in whole vec4s, not ${size}`); }
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
	const index = shaderRecords.slotIndex(module.id);
	cacheInvalidateProgram(shaders[index].program);
	oglDeleteProgram(shaders[index].program);
	vacate(shaders, module.id);
}

function attributeNameOf(shader: int32, location: int32): string | null {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		const name = shaders[shader].attributes[i].nativeName;
		if (name !== null && shaders[shader].attributes[i].location == location) { return name; }
	}
	return null;
}

export function createRenderPipeline(id: uint32, descriptor: GPURenderPipelineDescriptor): void {
	const s = shaderRecords.slotIndex(descriptor.vertex.module.id);
	checkedRenderModule(shaders[s].compute);
	let slot: PipelineSlot = { shader: descriptor.vertex.module.id };
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) { slot.blends[i] = defaultBlend(); }
	describeAttributes(s, descriptor, slot);
	describePrimitive(descriptor, slot);
	describeDepthStencil(descriptor, slot);
	describeBlend(descriptor, slot);
	slot.cullFace = cullFace(descriptor.primitive.cullMode);
	slot.frontFace = frontFace(descriptor.primitive.frontFace);
	slot.sampleCount = descriptor.multisample.count;
	put(pipelines, id, slot);
}

function describePrimitive(descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	slot.primitive = primitiveMode(descriptor.primitive.topology);
	const strip = slot.primitive == GL_LINE_STRIP || slot.primitive == GL_TRIANGLE_STRIP;
	slot.stripRestart = strip;
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
	slot.stencilReadMask = stencil8Mask(state.stencilReadMask);
	slot.stencilWriteMask = stencil8Mask(state.stencilWriteMask);
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
			const location = name === null ? shaderLocation : oglAttribLocation(shaders[shader].program, name);
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
		slot.writeMasks[i] = colorWriteBits(writeMask);
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
	const index = pipelineRecords.slotIndex(pipeline.id);
	if (bound.appliedPipeline == pipeline.id) { bound.appliedPipeline = 0; }
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
		checkEntryView(shader, group, entry);
		slot.entries[slot.entryCount] = entry;
		slot.entryCount += 1;
	}
	put(bindGroups, id, slot);
}

function resourceOf(shader: int32, group: int32, binding: int32, kind: BindingKind): int32 {
	for (let r = 0; r < shaders[shader].resourceCount; r++) {
		const resource = shaders[shader].resources[r];
		if (addressesBinding(group, binding, resource.binding, resource.kind) && resource.kind == kind) { return r; }
	}
	return -1;
}

@noinline function checkStorageView(entry: GPUBindGroupEntry, v: int32): void {
	const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
	const dimension = views[v].dimension;
	const whole = dimension == ViewDimension.ThreeD || (viewRecords.slots[v].baseLayer == 0 && viewRecords.slots[v].layerCount == textureRecords.slots[t].layers);
	if (dimension != ViewDimension.TwoD && !whole) {
		stop(`bind group entry ${entry.binding}: a ${viewDimensionName(dimension)} storage view must cover the whole GPUTexture on gl, because glBindImageTexture binds one layer or all of them`);
	}
}

@noinline function checkEntryView(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.textureView.id == 0) { return; }
	const v = viewRecords.slotIndex(entry.textureView.id);
	if (resourceOf(shader, group, entry.binding, BindingKind.Texture) >= 0) {
		checkSampledView(entry.binding, v);
	} else {
		checkStorageView(entry, v);
	}
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroupRecords.slotIndex(bindGroup.id);
	vacate(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(commandBuffer: GPUCommandBuffer): void {
	cacheClearBuffers(false);
	cacheClearUnits(false);
	bound.vertexDirty = true;
	bound.indexDirty = true;
	bound.resourcesDirty = true;
}

export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor, extent: GPUExtent3D): GPURenderPassEncoder {
	pass = {
		timestampSet: descriptor.timestampWrites.querySet.id,
		timestampEnd: descriptor.timestampWrites.endOfPassWriteIndex,
		width: extent.width,
		height: extent.height,
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
		const v = viewRecords.slotIndex(viewId);
		if (viewRecords.slots[v].swapchain) {
			if (i != 0) { stop(`colorAttachments[${i}] is the canvas, which GL draws only as attachment 0`); }
			if (descriptor.colorAttachments[i].resolveTarget.id != 0) {
				stop("colorAttachments[0] is the canvas, whose multisampled default framebuffer resolves itself on GL");
			}
			pass.swapchain = true;
		} else {
			offscreen = true;
		}
		pass.colorSlices[i] = descriptor.colorAttachments[i].depthSlice;
		pass.colorViews[i] = viewId;
		pass.resolveViews[i] = resolveView(i, descriptor.colorAttachments[i].resolveTarget.id);
		colorMask |= 1 << i;
		checkStoreOp(descriptor.colorAttachments[i].storeOp, i, "storeOp");
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	let depthTexture = 0;
	let depthViewSlot = -1;
	let depthStencil = false;
	if (depthView != 0) {
		const v = viewRecords.slotIndex(depthView);
		if (viewRecords.slots[v].swapchain) { pass.swapchain = true; } else { offscreen = true; }
		depthViewSlot = v;
		depthTexture = textureRecords.slotIndex(viewRecords.slots[v].texture);
		depthStencil = textures[depthTexture].info.stencil;
		checkStoreOp(descriptor.depthStencilAttachment.depthStoreOp, -1, "depthStoreOp");
		if (depthStencil) { checkStoreOp(descriptor.depthStencilAttachment.stencilStoreOp, -1, "stencilStoreOp"); }
	}
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
		const v = viewRecords.slotIndex(pass.colorViews[i]);
		attachView(attachment, v, views[v].dimension == ViewDimension.ThreeD ? pass.colorSlices[i] : viewRecords.slots[v].baseLayer);
	}
	if (depthView >= 0) {
		oglFramebufferDetach(GL_DEPTH_ATTACHMENT);
		oglFramebufferDetach(GL_DEPTH_STENCIL_ATTACHMENT);
		attachView(depthStencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT, depthView, viewRecords.slots[depthView].baseLayer);
	} else {
		oglFramebufferDetach(GL_DEPTH_STENCIL_ATTACHMENT);
	}
	const status = oglCheckFramebufferStatus();
	if (status != GL_FRAMEBUFFER_COMPLETE) { stop(`the render pass framebuffer is incomplete (status 0x${status.toString(16)})`); }
	oglDrawBuffers(GPU_MAX_COLOR_ATTACHMENTS, colorMask);
}

function attachView(attachment: int32, v: int32, layer: int32): void {
	const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
	const target = textures[t].target;
	const name = textures[t].names[0];
	if (target == GL_RENDERBUFFER) {
		oglFramebufferRenderbuffer(attachment, name);
	} else if (target == GL_TEXTURE_2D_ARRAY || target == GL_TEXTURE_3D) {
		oglFramebufferTextureLayer(attachment, name, viewRecords.slots[v].baseMip, layer);
	} else if (target == GL_TEXTURE_CUBE_MAP) {
		oglFramebufferTexture2D(attachment, GL_TEXTURE_CUBE_MAP_POSITIVE_X + viewRecords.slots[v].baseLayer, name, viewRecords.slots[v].baseMip);
	} else {
		oglFramebufferTexture2D(attachment, target, name, viewRecords.slots[v].baseMip);
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
	const clearStencil = depthStencil && isClear(descriptor.depthStencilAttachment.stencilLoadOp, -1, "stencilLoadOp");
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
	}
	if (clearStencil && cache.stencilMask != 0xFF) {
		cache.stencilMask = 0xFF;
		oglStencilMask(0xFF);
	}
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] == 0) { continue; }
		if (isClear(descriptor.colorAttachments[i].loadOp, i, "loadOp")) {
			const color = descriptor.colorAttachments[i].clearValue;
			oglClearColor(i, color.r, color.g, color.b, color.a);
		}
	}
	const depth = descriptor.depthStencilAttachment.depthClearValue;
	const stencil = (descriptor.depthStencilAttachment.stencilClearValue & 0xFF) as int32;
	if (clearDepth && clearStencil) {
		oglClearDepthStencil(depth, stencil);
	} else if (clearDepth) {
		oglClearDepth(depth);
	} else if (clearStencil) {
		oglClearStencil(stencil);
	}
}

@noinline function resolveView(attachment: int32, resolveId: uint32): uint32 {
	if (resolveId == 0) { return 0; }
	const r = viewRecords.slotIndex(resolveId);
	if (viewRecords.slots[r].swapchain) {
		stop(`colorAttachments[${attachment}].resolveTarget is the canvas, which GL draws only through framebuffer 0`);
	}
	if (views[r].resolveFramebuffer == 0) {
		const resolveFramebuffer = oglCreateFramebuffer();
		oglBindFramebuffer(GL_FRAMEBUFFER, resolveFramebuffer);
		attachView(GL_COLOR_ATTACHMENT0, r, viewRecords.slots[r].baseLayer);
		const status = oglCheckFramebufferStatus();
		if (status != GL_FRAMEBUFFER_COMPLETE) { stop(`the resolve framebuffer is incomplete (status 0x${status.toString(16)})`); }
		oglDrawBuffers(1, 1);
		views[r].resolveFramebuffer = resolveFramebuffer;
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
	let readBound = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.resolveViews[i] == 0) { continue; }
		if (!readBound) {
			oglBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
			readBound = true;
		}
		const r = viewRecords.slotIndex(pass.resolveViews[i]);
		oglBindFramebuffer(GL_DRAW_FRAMEBUFFER, views[r].resolveFramebuffer);
		oglReadBuffer(GL_COLOR_ATTACHMENT0 + i);
		oglBlitColor(pass.width, pass.height);
	}
	if (pass.timestampSet != 0 && pass.timestampEnd >= 0) { writeTimestamp(pass.timestampSet, pass.timestampEnd); }
	if (pass.labeled) { endLabel(); }
}

export function setPipeline(pipeline: GPURenderPipeline): void {}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
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
	bound.indexDirty = true;
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (bindGroup.id == 0) { return; }
	if (index == GPU_UNIFORM_GROUP) {
		bound.uniformsDirty = true;
	} else {
		bound.resourcesDirty = true;
	}
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	oglScissor(x, pass.height - (y + height), width, height);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
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
	oglBlendColor(color.r, color.g, color.b, color.a);
	cache.blendConstantSet = true;
}

export function setStencilReference(reference: uint32): void {
	bound.stencilReference = reference as int32;
	if (bound.appliedPipeline != 0 && pipelines[pipelineRecords.slotIndex(bound.appliedPipeline)].stencil) {
		applyStencilFaces(pipelineRecords.slotIndex(bound.appliedPipeline));
	}
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush(false);
	const mode = pipelines[slotOf(boundFacts.pipeline)].primitive;
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
	const mode = pipelines[slotOf(boundFacts.pipeline)].primitive;
	const offset = (firstIndex as int64) * (bound.indexSize as int64) + boundFacts.indexOffset;
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

export function multiDrawIndexedIndirect(buffer: GPUBuffer, offset: int64, drawCount: int32): void {
	if (boundFacts.indexOffset != 0) {
		stop(`multiDrawIndexedIndirect with the index buffer set at offset ${boundFacts.indexOffset}: a GL indirect draw reads indices from offset 0, so set it there`);
	}
	flush(true);
	multiDrawElementsIndirect(pipelines[slotOf(boundFacts.pipeline)].primitive, bound.indexType, bufferName(slotOf(buffer.id)), offset, drawCount);
}


function flush(indexed: boolean): void {
	if (bound.appliedPipeline != boundFacts.pipeline) { applyPipeline(); }
	if (bound.vertexDirty) { applyVertexBuffers(); }
	if (indexed && bound.indexDirty) { applyIndexBuffer(); }
	if (bound.resourcesDirty) { applyResources(); }
	if (bound.uniformsDirty) { applyUniforms(); }
}

function applyPipeline(): void {
	const p = slotOf(boundFacts.pipeline);
	const s = shaderRecords.slotIndex(pipelines[p].shader);
	if (shaders[s].program != cache.program) {
		cache.program = shaders[s].program;
		oglUseProgram(cache.program);
	}
	applyDepthState(p);
	applyStencilState(p);
	if (pipelines[p].colorCount > 0) { applyBlendState(p); }
	if (pipelines[p].stripRestart != cache.primitiveRestart) {
		cache.primitiveRestart = pipelines[p].stripRestart;
		setPrimitiveRestart(cache.primitiveRestart);
	}
	if (pipelines[p].cullFace != cache.cullFace) {
		cache.cullFace = pipelines[p].cullFace;
		if (cache.cullFace == 0) {
			oglDisable(GL_CULL_FACE);
		} else {
			oglEnable(GL_CULL_FACE);
			oglCullFace(cache.cullFace);
		}
	}
	if (pipelines[p].frontFace != cache.frontFace) {
		cache.frontFace = pipelines[p].frontFace;
		oglFrontFace(cache.frontFace);
	}
	if (pipelines[p].sampleCount != cache.sampleCount) {
		cache.sampleCount = pipelines[p].sampleCount;
		setMultisample(cache.sampleCount);
	}
	bound.instanced = pipelines[p].instanced;
	bound.appliedPipeline = boundFacts.pipeline;
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
	if (pipelines[p].depthCompare != cache.depthCompare) {
		cache.depthCompare = pipelines[p].depthCompare;
		oglDepthFunc(cache.depthCompare);
	}
	if (pipelines[p].depthWrite != cache.depthWrite) {
		cache.depthWrite = pipelines[p].depthWrite;
		oglDepthMask(cache.depthWrite ? 1 : 0);
	}
	const slope = pipelines[p].depthSlope;
	const units = pipelines[p].depthBias as float64;
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
	if (!pipelines[p].stencil) {
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
	if (pipelines[p].stencilWriteMask != cache.stencilMask) {
		cache.stencilMask = pipelines[p].stencilWriteMask;
		oglStencilMask(cache.stencilMask);
	}
	applyStencilFaces(p);
	oglStencilOpSeparate(GL_FRONT, pipelines[p].stencilFront.failOp, pipelines[p].stencilFront.depthFailOp, pipelines[p].stencilFront.passOp);
	oglStencilOpSeparate(GL_BACK, pipelines[p].stencilBack.failOp, pipelines[p].stencilBack.depthFailOp, pipelines[p].stencilBack.passOp);
}

function applyStencilFaces(p: int32): void {
	oglStencilFuncSeparate(GL_FRONT, pipelines[p].stencilFront.compare, bound.stencilReference, pipelines[p].stencilReadMask);
	oglStencilFuncSeparate(GL_BACK, pipelines[p].stencilBack.compare, bound.stencilReference, pipelines[p].stencilReadMask);
}

function applyBlendState(p: int32): void {
	for (let i = 0; i < pipelines[p].colorCount; i++) {
		const next: BlendState = pipelines[p].blends[i];
		const current: BlendState = cache.blends[i];
		applyBlend(i, next, current);
		if (pipelines[p].writeMasks[i] != cache.writeMasks[i]) {
			cache.writeMasks[i] = pipelines[p].writeMasks[i];
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

when (webgl2 || android || (linux && voidGles3)) {
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

	function indirectFeatureBits(): uint32 { return 0; }

	function multiDrawElementsIndirect(mode: int32, indexType: int32, buffer: uint32, offset: int64, drawCount: int32): void {
		stop("multiDrawIndexedIndirect: a GLES indirect draw has no base instance");
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

	function indirectFeatureBits(): uint32 { return featureBit("indirect-first-instance"); }

	function multiDrawElementsIndirect(mode: int32, indexType: int32, buffer: uint32, offset: int64, drawCount: int32): void {
		oglMultiDrawElementsIndirectUncached(mode, indexType, buffer, offset, drawCount);
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
	const p = slotOf(boundFacts.pipeline);
	for (let i = 0; i < maxVertexAttributes; i++) {
		const attribute: VertexAttribute = pipelines[p].attributes[i];
		const cached = cachedAttributes[i];
		if (!attribute.enabled) {
			if (cached.enabled) {
				oglDisableVertexAttribArray(i);
				cachedAttributes[i].enabled = false;
			}
			continue;
		}
		const b = bufferRecords.slotIndex(boundFacts.vertexBuffers[attribute.bufferSlot]);
		const name = buffers[b].names[buffers[b].activeSlot];
		const offset = boundFacts.vertexOffsets[attribute.bufferSlot] + (attribute.offset as int64);
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
	const b = bufferRecords.slotIndex(boundFacts.indexBuffer);
	cacheBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffers[b].names[buffers[b].activeSlot]);
	bound.indexDirty = false;
}


function applyResources(): void {
	const s = shaderRecords.slotIndex(pipelines[slotOf(boundFacts.pipeline)].shader);
	bound.resourcesDirty = false;
	if (shaders[s].pairCount == 0 && shaders[s].storageCount == 0) { return; }
	bindResources(s, bindGroupRecords.slotIndex(boundFacts.bindGroups[GPU_RESOURCE_GROUP]));
}

function bindResources(s: int32, g: int32): void {
	for (let i = 0; i < shaders[s].pairCount; i++) {
		const pair: TexturePair = shaders[s].pairs[i];
		if (pair.unit < 0) { continue; }
		const view = viewRecords.slotIndex(bindGroups[g].entries[entryOf(bindGroups[g], pair.textureBinding)].textureView.id);
		const t = textureRecords.slotIndex(viewRecords.slots[view].texture);
		const sampler = pair.samplerBinding == DUMMY_SAMPLER_BINDING
			? dummySampler
			: samplers[samplerRecords.slotIndex(bindGroups[g].entries[entryOf(bindGroups[g], pair.samplerBinding)].sampler.id)].native;
		cacheBindTextureSampler(pair.unit, textures[t].target, textures[t].names[textures[t].activeSlot], sampler);
		const lastMip = viewRecords.slots[view].baseMip + viewRecords.slots[view].mipCount - 1;
		if (textures[t].baseLevel != viewRecords.slots[view].baseMip || textures[t].maxLevel != lastMip) {
			cacheActiveTexture(pair.unit);
			oglTexParameteri(textures[t].target, GL_TEXTURE_BASE_LEVEL, viewRecords.slots[view].baseMip);
			oglTexParameteri(textures[t].target, GL_TEXTURE_MAX_LEVEL, lastMip);
			textures[t].baseLevel = viewRecords.slots[view].baseMip;
			textures[t].maxLevel = lastMip;
		}
	}
	for (let r = 0; r < shaders[s].resourceCount; r++) {
		const resource: ResourceBinding = shaders[s].resources[r];
		if (resource.kind == BindingKind.StorageBuffer) {
			bindStorageBuffer(resource, g);
		} else if (resource.kind == BindingKind.StorageTexture) {
			bindStorageTexture(resource, g);
		}
	}
}

function bindStorageBuffer(resource: ResourceBinding, g: int32): void {
	const entry: GPUBindGroupEntry = bindGroups[g].entries[entryOf(bindGroups[g], resource.binding)];
	const b = bufferRecords.slotIndex(entry.buffer.id);
	const bytes = entry.size == 0 ? bufferRecords.slots[b].size - entry.offset : entry.size;
	oglBindBufferRange(GL_SHADER_STORAGE_BUFFER, resource.nativeSlot as uint32, bufferName(b), entry.offset, bytes);
}

function bindStorageTexture(resource: ResourceBinding, g: int32): void {
	const entry: GPUBindGroupEntry = bindGroups[g].entries[entryOf(bindGroups[g], resource.binding)];
	const v = viewRecords.slotIndex(entry.textureView.id);
	const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
	const layered = views[v].dimension != ViewDimension.TwoD;
	oglBindImageTexture(
		resource.nativeSlot,
		textureName(t),
		viewRecords.slots[v].baseMip,
		layered ? 1 : 0,
		layered ? 0 : viewRecords.slots[v].baseLayer,
		resource.access,
		textures[t].info.internalFormat,
	);
}

function applyUniforms(): void {
	const s = shaderRecords.slotIndex(pipelines[slotOf(boundFacts.pipeline)].shader);
	bound.uniformsDirty = false;
	if (shaders[s].uniformCount == 0) { return; }
	const g = bindGroupRecords.slotIndex(boundFacts.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders[s].uniformCount; u++) {
		const uniform: UniformBinding = shaders[s].uniforms[u];
		const e = entryOf(bindGroups[g], uniform.binding);
		const offset = (boundFacts.dynamicOffsets[bindGroupRecords.slots[g].dynamicIndex[e]] as int64) + bindGroups[g].entries[e].offset;
		const b = bufferRecords.slotIndex(bindGroups[g].entries[e].buffer.id);
		if (uniform.location == -1) { continue; }
		oglUniform4fv(uniform.location, uniform.count, buffers[b].shadow[0], offset);
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string): int32 {
	const index = bufferRecords.slotIndex(buffer.id);
	if (buffers[index].uniform) { stop(`${member}: GPUBuffer ${buffer.id} is a CPU shadow uniform block on gl and cannot be copied`); }
	return index;
}


function texelFormatOf(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): FormatInfo {
	const info = textures[index].info;
	if (info.depth) {
		checkedDepthTexelCopy(member, textureRecords.slots[index].id, textureRecords.slots[index].format, info.stencil, writes, textureRecords.slots[index].width, textureRecords.slots[index].height, copy.mipLevel, size);
	}
	return info;
}

@inline function bufferName(index: int32): uint32 { return buffers[index].names[buffers[index].activeSlot]; }

@inline function textureName(index: int32): uint32 { return textures[index].names[textures[index].activeSlot]; }

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination");
	if (from == to) { stop(`copyBufferToBuffer inside GPUBuffer ${source.id} is not ported to gl yet: a written buffer rotates its in-flight copies`); }
	claimBufferCopy(to, destinationOffset, size, "copyBufferToBuffer");
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
	const target = buffers[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, bufferName(index));
	oglBufferSubData(target, offset, bytes[0], span);
	cacheRestoreBuffer(target);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = textureRecords.slotIndex(source.texture.id);
	const to = copyableBuffer(destination.buffer, "copyTextureToBuffer destination");
	const info = texelFormatOf(from, "copyTextureToBuffer source", false, source, size);
	checkDepthReadback(info);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", info.bytesPerPixel, bufferRecords.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (bytesPerRow as int64) * ((size.height - 1) as int64)
		+ ((size.width * info.bytesPerPixel) as int64);
	claimBufferCopy(to, destination.offset, span, "copyTextureToBuffer");
	checkError("copyTextureToBuffer");
	if (textureRecords.slots[from].swapchainView != 0) {
		const format: string = textureRecords.slots[from].format;
		if (format != "rgba8unorm") { stop(`copyTextureToBuffer: the default framebuffer reads as RGBA bytes, which the canvas format ${format} would mislabel`); }
		const read = oglReadScreenRectUncached(
			source.origin.x,
			textureRecords.slots[from].height - (source.origin.y + size.height),
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
			textures[from].target,
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
			stop(`copyTextureToBuffer: ${textureRecords.slots[from].format} GPUTexture ${source.texture.id} is not color-renderable on this GL target, so it cannot be read back`);
		}
		if (read < 0) {
			stop(`copyTextureToBuffer: this GL target has no read format for ${textureRecords.slots[from].format} GPUTexture ${source.texture.id}`);
		}
	}
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source");
	const to = textureRecords.slotIndex(destination.texture.id);
	const info = texelFormatOf(to, "copyBufferToTexture destination", true, destination, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", info.bytesPerPixel, bufferRecords.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	rotateOnWholeWrite(to, size);
	const target = textures[to].target;
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
	const from = textureRecords.slotIndex(source.texture.id);
	const to = textureRecords.slotIndex(destination.texture.id);
	if (textures[from].info.depth) { stop("copyTextureToTexture of a depth GPUTexture is not ported to gl yet"); }
	if (textureRecords.slots[from].swapchainView != 0) { stop("copyTextureToTexture from the swapchain texture: the default framebuffer reads only into a buffer on gl"); }
	if (from != to) { rotateOnWholeWrite(to, size); }
	const fromFormat: string = textureRecords.slots[from].format;
	checkError("copyTextureToTexture");
	cacheStoreUnit0();
	cacheBindTextureSampler(0, textures[to].target, textureName(to), 0);
	const copied = oglCopyTexels(
		readFramebuffer,
		textureName(from),
		textures[from].target,
		source.mipLevel,
		source.origin.z,
		source.origin.x,
		source.origin.y,
		textures[to].target,
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

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, length: int64): void {
	const index = bufferRecords.slotIndex(buffer.id);
	if (mode == (GPUMapMode.READ as int32)) {
		if (oglGetBufferDataUncached(bufferName(index), offset, buffers[index].shadow[offset], length) == 0) {
			stop(`mapAsync READ of GPUBuffer ${buffer.id}: this GL target cannot read a buffer back`);
		}
		checkError("mapAsync");
	}
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, length: int64): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(length);
	oglCopyBytes(bytes[0], 0, buffers[bufferRecords.slotIndex(buffer.id)].shadow[offset], length);
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferRecords.slotIndex(buffer.id);
	const target = buffers[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, bufferName(index));
	oglBufferSubData(target, offset, data[0], bytes);
	cacheRestoreBuffer(target);
}

export function createComputePipeline(id: uint32, descriptor: GPUComputePipelineDescriptor): void {
	const s = shaderRecords.slotIndex(descriptor.compute.module.id);
	const entry = descriptor.compute.entryPoint == "" ? "main" : descriptor.compute.entryPoint;
	checkedComputeModule(shaders[s].compute, entry, shaders[s].computeEntry);
	const slot: PipelineSlot = { shader: descriptor.compute.module.id, compute: true };
	put(pipelines, id, slot);
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	computeBound = {
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
	computeBound.dirty = true;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (index != GPU_RESOURCE_GROUP) { return; }
	computeBound.dirty = true;
}

function applyCompute(): int32 {
	const s = shaderRecords.slotIndex(pipelines[slotOf(boundFacts.pipeline)].shader);
	if (computeBound.pendingBarrier) {
		oglMemoryBarrier(BARRIER_BETWEEN_DISPATCHES);
		computeBound.pendingBarrier = false;
	}
	if (!computeBound.dirty) { return s; }
	computeBound.dirty = false;
	if (shaders[s].program != cache.program) {
		cache.program = shaders[s].program;
		oglUseProgram(cache.program);
	}
	if (shaders[s].pairCount == 0 && shaders[s].storageCount == 0) { return s; }
	bindResources(s, bindGroupRecords.slotIndex(boundFacts.bindGroups[GPU_RESOURCE_GROUP]));
	return s;
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	const s = applyCompute();
	oglDispatchCompute(x, y, z);
	if (shaders[s].writes) { computeBound.pendingBarrier = true; }
	checkError("dispatchWorkgroups");
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = slotOf(buffer.id);
	const s = applyCompute();
	oglDispatchComputeIndirectUncached(bufferName(b), offset);
	if (shaders[s].writes) { computeBound.pendingBarrier = true; }
	checkError("dispatchWorkgroupsIndirect");
}

export function endComputePass(): void {
	if (computeBound.pendingBarrier) { oglMemoryBarrier(BARRIER_ALL); }
	if (computeBound.timestampSet != 0 && computeBound.timestampEnd >= 0) {
		writeTimestamp(computeBound.timestampSet, computeBound.timestampEnd);
	}
	if (computeBound.labeled) { endLabel(); }
	computeBound = { dirty: false };
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

export function limits(): GPUSupportedLimits {
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
	if (computeSupported) { bits |= indirectFeatureBits(); }
	return { bits: bits };
}

export function features(): GPUSupportedFeatures { return deviceFeatures; }

export function pushDebugGroup(label: string): void {
	if (openDebugGroups() > MAX_DEBUG_GROUPS) { stop(`pushDebugGroup nested over ${MAX_DEBUG_GROUPS} deep, the minimum GL_MAX_DEBUG_GROUP_STACK_DEPTH leaves`); }
	if (debugSupported) { oglPushDebugGroup(label); }
}

export function popDebugGroup(): void {
	if (debugSupported) { oglPopDebugGroup(); }
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

export function createQuerySet(id: uint32, descriptor: GPUQuerySetDescriptor): void {
	let slot: QuerySetSlot = { names: [] };
	for (let i = 0; i < descriptor.count; i++) { slot.names.push(oglCreateQuery()); }
	checkErrorOf("createQuerySet", descriptor.label);
	put(querySets, id, slot);
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySetRecords.slotIndex(querySet.id);
	for (let i = 0; i < querySets[index].names.length; i++) { oglDeleteQuery(querySets[index].names[i]); }
	vacate(querySets, querySet.id);
}

function writeTimestamp(querySet: uint32, queryIndex: int32): void {
	const q = querySetRecords.slotIndex(querySet);
	oglQueryCounter(querySets[q].names[queryIndex]);
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	const q = querySetRecords.slotIndex(querySet.id);
	const b = bufferRecords.slotIndex(destination.id);
	const bytes = (queryCount as int64) * 8;
	let values: Vec<uint64> = new Array(queryCount);
	for (let i = 0; i < queryCount; i++) {
		const name = querySets[q].names[firstQuery + i];
		when (webgl2) {
			if (oglQueryAvailable(name) == 0) {
				stop(`resolveQuerySet: query ${firstQuery + i} is not ready, because WebGL2 delivers query results only after the page returns to the event loop: resolve it in a later task than the pass that wrote it`);
			}
		}
		values[i] = oglQueryResult(name);
	}
	const target = buffers[b].target;
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
	const q = querySetRecords.slotIndex(occlusionSetId());
	oglBeginQuery(occlusionTarget(), querySets[q].names[queryIndex]);
}

export function endOcclusionQuery(): void {
	const q = querySetRecords.slotIndex(occlusionSetId());
	oglEndQuery(occlusionTarget());
}
