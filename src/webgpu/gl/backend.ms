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
	GPUIndexFormat,
	GPUMapMode,
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
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	checkedBufferCopy,
	checkedMapRange,
	checkedTexelBufferLayout,
	checkedTexelCopyRegion,
	checkedTexelWritePitch,
	stopOnUnportedRenderPass,
	stopOnUnportedShaderModule,
} from "../types.ms";
import {
	oglActiveTexture,
	oglAttribLocation,
	oglBindBuffer,
	oglBindFramebuffer,
	oglBindSampler,
	oglBindTexture,
	oglBindVertexArray,
	oglBlendColor,
	oglBlendEquationSeparate,
	oglBlendFuncSeparate,
	oglBlitColor,
	oglBufferData,
	oglBufferSubData,
	oglCheckFramebufferStatus,
	oglClearColor,
	oglClearDepth,
	oglClearDepthStencil,
	oglColorMask,
	oglCompileShader,
	oglCopyBufferData,
	oglCopyBytes,
	oglCopyTexels,
	oglCreateBuffer,
	oglCreateFramebuffer,
	oglCreateRenderbuffer,
	oglCreateSampler,
	oglCreateTexture,
	oglCreateVertexArray,
	oglCullFace,
	oglDeleteBuffer,
	oglDeleteFramebuffer,
	oglDeleteProgram,
	oglDeleteRenderbuffer,
	oglDeleteSampler,
	oglDeleteTexture,
	oglDeleteVertexArray,
	oglDepthFunc,
	oglDepthMask,
	oglDepthRange,
	oglDisable,
	oglDisableVertexAttribArray,
	oglDrawArrays,
	oglDrawArraysInstanced,
	oglDrawBuffers,
	oglDrawElements,
	oglDrawElementsInstanced,
	oglEnable,
	oglEnableVertexAttribArray,
	oglFramebufferDetach,
	oglFramebufferRenderbuffer,
	oglFramebufferTexture2D,
	oglFramebufferTextureLayer,
	oglFrontFace,
	oglGetBufferData,
	oglGetError,
	oglGetInteger,
	oglLinkProgram,
	oglLoad,
	oglLoadMissing,
	oglLog,
	oglPixelStore,
	oglPolygonOffset,
	oglReadBuffer,
	oglReadTexelsToBuffer,
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
	oglTexSubImageFromBuffer,
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

when (!webgl2 && !android) {
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

const SLOT_SHIFT = 16;
const SLOT_MASK = 0xFFFF;
const UNIFORM_OFFSET_ALIGNMENT = 256;
const INFLIGHT_SLOTS = 2;
const MAX_TEXTURE_UNITS = 16;
const MAX_TEXTURE_PAIRS = 16;
const MAX_SHADER_RESOURCES = 24;
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
const GL_R32UI = 0x8236;
const GL_RGB10_A2 = 0x8059;
const GL_R11F_G11F_B10F = 0x8C3A;
const GL_DEPTH_COMPONENT16 = 0x81A5;
const DEFAULT_LOD_MAX_CLAMP = 32.0;
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

enum BindingKind {
	Uniform,
	Texture,
	Sampler,
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

struct SlotQueue {
	free: Vec<int32>;
	generations: Vec<uint32>;
}

struct BufferSlot {
	id: uint32;
	size: int64;
	usage: int32;
	uniform: boolean;
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
	dimension: string;
	baseMip: int32;
	mipCount: int32;
	baseLayer: int32;
	layerCount: int32;
	attachable: boolean;
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
}

struct ShaderSlot {
	id: uint32;
	program: uint32;
	uniforms: UniformBinding[8];
	uniformCount: int32;
	pairs: TexturePair[16];
	pairCount: int32;
	resources: ResourceBinding[24];
	resourceCount: int32;
	attributes: GPUShaderAttribute[16];
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
	swapchain: boolean;
	width: int32;
	height: int32;
	colorViews: uint32[4];
	resolveViews: uint32[4];
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
}

let frame: int64 = 0;
let pass: PassState = { active: false };
let bound: BoundState = { pipeline: 0 };
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
let framebuffer: uint32 = 0;
let maxVertexAttributes: int32 = 0;
let maxTextureUnits: int32 = 0;
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 };

let bufferQueue: SlotQueue = { free: [], generations: [] };
let textureQueue: SlotQueue = { free: [], generations: [] };
let viewQueue: SlotQueue = { free: [], generations: [] };
let samplerQueue: SlotQueue = { free: [], generations: [] };
let shaderQueue: SlotQueue = { free: [], generations: [] };
let pipelineQueue: SlotQueue = { free: [], generations: [] };
let layoutQueue: SlotQueue = { free: [], generations: [] };
let bindGroupQueue: SlotQueue = { free: [], generations: [] };

let buffers: Vec<BufferSlot> = [];
let textures: Vec<TextureSlot> = [];
let views: Vec<ViewSlot> = [];
let samplers: Vec<SamplerSlot> = [];
let shaders: Vec<ShaderSlot> = [];
let pipelines: Vec<PipelineSlot> = [];
let layouts: Vec<LayoutSlot> = [];
let bindGroups: Vec<BindGroupSlot> = [];

function stop(message: string): void {
	console.log(`webgpu gl: ${message}`);
	unreachable;
}

function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu gl: ${member} '${value}' is not supported`);
	unreachable;
}

function stopOnVertexFormat(value: string): VertexFormatInfo {
	console.log(`webgpu gl: vertex attribute format '${value}' is not supported`);
	unreachable;
}

function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu gl: ${member} '${value}' is not supported`);
	unreachable;
}

function stopOnHandle(kind: string, id: uint32): int32 {
	console.log(`webgpu gl: ${kind} ${id} is not a live handle`);
	unreachable;
}

function nativeNameOf(name: string | null, what: string): string {
	if (name !== null) { return name; }
	console.log(`webgpu gl: ${what} needs its GLSL name in nativeName`);
	unreachable;
}

function checkError(what: string): void {
	const error = oglGetError();
	if (error != 0) { stop(`${what} raised GL error 0x${error.toString(16)}`); }
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

@inline function roundUp16(bytes: int64): int64 { return (bytes + 15) & ~(15 as int64); }

@inline function smaller(a: int32, b: int32): int32 { return a < b ? a : b; }

function allocateId(ref queue: SlotQueue, what: string): uint32 {
	let index: int32 = 0;
	if (queue.free.length > 0) {
		index = queue.free[queue.free.length - 1];
		queue.free.pop();
	} else {
		if (queue.generations.length == 0) { queue.generations.push(0); }
		index = queue.generations.length as int32;
		if (index > SLOT_MASK) {
			console.error(`webgpu gl: ${what} pool exhausted (65535 live handles)`);
			return 0;
		}
		queue.generations.push(0);
	}
	queue.generations[index] += 1;
	return (queue.generations[index] << SLOT_SHIFT) | (index as uint32);
}

function releaseId(ref queue: SlotQueue, id: uint32): void {
	queue.free.push((id & SLOT_MASK) as int32);
}

@inline function slotOf(id: uint32): int32 { return (id & SLOT_MASK) as int32; }

function bufferIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= buffers.length || buffers[index].id != id) {
		return stopOnHandle("GPUBuffer", id);
	}
	return index;
}

function textureIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= textures.length || textures[index].id != id) {
		return stopOnHandle("GPUTexture", id);
	}
	return index;
}

function viewIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= views.length || views[index].id != id) {
		return stopOnHandle("GPUTextureView", id);
	}
	return index;
}

function samplerIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= samplers.length || samplers[index].id != id) {
		return stopOnHandle("GPUSampler", id);
	}
	return index;
}

function shaderIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= shaders.length || shaders[index].id != id) {
		return stopOnHandle("GPUShaderModule", id);
	}
	return index;
}

function pipelineIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= pipelines.length || pipelines[index].id != id) {
		return stopOnHandle("GPURenderPipeline", id);
	}
	return index;
}

function layoutIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= layouts.length || layouts[index].id != id) {
		return stopOnHandle("GPUBindGroupLayout", id);
	}
	return index;
}

function bindGroupIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= bindGroups.length || bindGroups[index].id != id) {
		return stopOnHandle("GPUBindGroup", id);
	}
	return index;
}

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
	const value: string = factor;
	if (value == "") { return GL_ZERO; }
	return blendFactor(value, member);
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

function linearFilter(filter: string, member: string): boolean {
	const value = match (filter) {
		"" | "nearest" => 0,
		"linear" => 1,
		_ => stopOnMember(member, filter),
	};
	return value == 1;
}

function bindingKind(kind: string): BindingKind {
	return match (kind) {
		"uniform" => BindingKind.Uniform,
		"texture" => BindingKind.Texture,
		"sampler" => BindingKind.Sampler,
		_ => stopOnMember("GPUShaderBinding.kind", kind) as BindingKind,
	};
}

function checkStage(stage: string): void {
	if (stage != "vertex" && stage != "fragment") { stopOnMember("GPUShaderBinding.stage", stage); }
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
			when (!webgl2 && !android) { oglBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0); }
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
	oglColorMask(COLOR_WRITE_ALL);
	oglPolygonOffset(0, 0);
	oglDisable(GL_POLYGON_OFFSET_FILL);
	oglDisable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
	oglDepthRange(0, 1);
	oglDisable(GL_CULL_FACE);
	oglFrontFace(GL_CW);
	oglCullFace(GL_BACK);
	oglEnable(GL_SCISSOR_TEST);
	oglDisable(GL_SAMPLE_ALPHA_TO_COVERAGE);
	oglEnable(GL_DITHER);
	when (!webgl2 && !android) {
		oglEnable(GL_MULTISAMPLE);
		oglEnable(GL_PROGRAM_POINT_SIZE);
	}
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (oglLoad() == 0) {
		const missing: string = oglLoadMissing();
		stop(`requestDevice needs a current GL context; ${missing} did not load`);
	}
	const version = oglGetInteger(GL_MAJOR_VERSION) * 100 + oglGetInteger(GL_MINOR_VERSION) * 10;
	when (webgl2 || android) {
		if (version < 300) { stop(`the current context is GLES ${version}; the GLES3 backend needs 300`); }
	} else {
		if (version < 430) { stop(`the current context is GL ${version}; the GL backend needs 430`); }
	}
	maxVertexAttributes = smaller(oglGetInteger(GL_MAX_VERTEX_ATTRIBS), GPU_MAX_VERTEX_ATTRIBUTES);
	maxTextureUnits = smaller(oglGetInteger(GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS), MAX_TEXTURE_UNITS);
	vertexArray = oglCreateVertexArray();
	oglBindVertexArray(vertexArray);
	framebuffer = oglCreateFramebuffer();
	oglPixelStore(GL_UNPACK_ALIGNMENT, 1);
	when (!webgl2 && !android) { oglEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS); }
	resetStateCache();
	checkError("setup");
	frame = 0;
	pass = { active: false };
	bound = { pipeline: 0 };
	buffers = [{ id: 0 }];
	textures = [{ id: 0 }];
	views = [{ id: 0 }];
	samplers = [{ id: 0 }];
	shaders = [{ id: 0 }];
	pipelines = [{ id: 0 }];
	layouts = [{ id: 0 }];
	bindGroups = [{ id: 0 }];
	bufferQueue = { free: [], generations: [] };
	textureQueue = { free: [], generations: [] };
	viewQueue = { free: [], generations: [] };
	samplerQueue = { free: [], generations: [] };
	shaderQueue = { free: [], generations: [] };
	pipelineQueue = { free: [], generations: [] };
	layoutQueue = { free: [], generations: [] };
	bindGroupQueue = { free: [], generations: [] };
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
	when (webgl2 || android) {
		if (info.needsColorBufferFloat) { return false; }
	}
	return !info.integer;
}

export function frameIndex(): uint32 { return (frame + 1) as uint32; }

export function liveCounts(): GPULiveCounts {
	let counts: GPULiveCounts = { buffers: 0 };
	for (let i = 1; i < buffers.length; i++) { if (buffers[i].id != 0) { counts.buffers += 1; } }
	for (let i = 1; i < textures.length; i++) {
		if (textures[i].id != 0 && textures[i].swapchainView == 0) { counts.textures += 1; }
	}
	for (let i = 1; i < views.length; i++) { if (views[i].id != 0 && !views[i].swapchain) { counts.views += 1; } }
	for (let i = 1; i < samplers.length; i++) { if (samplers[i].id != 0) { counts.samplers += 1; } }
	for (let i = 1; i < shaders.length; i++) { if (shaders[i].id != 0) { counts.shaderModules += 1; } }
	for (let i = 1; i < pipelines.length; i++) { if (pipelines[i].id != 0) { counts.pipelines += 1; } }
	return counts;
}

export function bufferAlive(buffer: GPUBuffer): boolean {
	const index = slotOf(buffer.id);
	return buffer.id != 0 && index < buffers.length && buffers[index].id == buffer.id;
}

export function textureAlive(texture: GPUTexture): boolean {
	const index = slotOf(texture.id);
	return texture.id != 0 && index < textures.length && textures[index].id == texture.id;
}

export function viewAlive(view: GPUTextureView): boolean {
	const index = slotOf(view.id);
	return view.id != 0 && index < views.length && views[index].id == view.id;
}

export function samplerAlive(sampler: GPUSampler): boolean {
	const index = slotOf(sampler.id);
	return sampler.id != 0 && index < samplers.length && samplers[index].id == sampler.id;
}

function reserveSwapchainTexture(format: GPUTextureFormat): uint32 {
	const textureId = allocateId(textureQueue, "texture");
	const viewId = allocateId(viewQueue, "view");
	if (textureId == 0 || viewId == 0) { stop("the swapchain texture and view found their pools exhausted"); }
	const info = formatInfo(format, "canvas format");
	textures.push({
		id: textureId,
		format: format,
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		mipLevels: 1,
		layers: 1,
		swapchainView: viewId,
	});
	views.push({
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
	for (let i = 1; i < bindGroups.length; i++) {
		if (bindGroups[i].id != 0) { destroyBindGroup({ id: bindGroups[i].id }); }
	}
	for (let i = 1; i < pipelines.length; i++) {
		if (pipelines[i].id != 0) { destroyRenderPipeline({ id: pipelines[i].id }); }
	}
	for (let i = 1; i < shaders.length; i++) {
		if (shaders[i].id != 0) { destroyShaderModule({ id: shaders[i].id }); }
	}
	for (let i = 1; i < samplers.length; i++) {
		if (samplers[i].id != 0) { destroySampler({ id: samplers[i].id }); }
	}
	for (let i = 1; i < views.length; i++) {
		if (views[i].id != 0 && !views[i].swapchain) { destroyView({ id: views[i].id }); }
	}
	for (let i = 1; i < textures.length; i++) {
		if (textures[i].id != 0 && textures[i].swapchainView == 0) { destroyTexture({ id: textures[i].id }); }
	}
	for (let i = 1; i < buffers.length; i++) {
		if (buffers[i].id != 0) { destroyBuffer({ id: buffers[i].id }); }
	}
	oglDeleteFramebuffer(framebuffer);
	oglDeleteVertexArray(vertexArray);
	framebuffer = 0;
	vertexArray = 0;
	oglUnload();
	buffers = [];
	textures = [];
	views = [];
	samplers = [];
	shaders = [];
	pipelines = [];
	layouts = [];
	bindGroups = [];
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "glcore", originTopLeft: false, depthZeroToOne: false };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocateId(bufferQueue, "buffer");
	if (id == 0) { return { id: 0 }; }
	const usage = descriptor.usage;
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
	if (has(usage, GPUBufferUsage.STORAGE as int32)) { stop("GPUBufferUsage.STORAGE is not ported to gl yet"); }
	if (has(usage, GPUBufferUsage.INDIRECT as int32)) { stop("GPUBufferUsage.INDIRECT is not ported to gl yet"); }
	const mapRead = has(usage, GPUBufferUsage.MAP_READ as int32);
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
	if (mapRead && usage != ((GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32))) {
		stop("GPUBufferUsage MAP_READ combines only with COPY_DST");
	}
	if (mapWrite && usage != ((GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32))) {
		stop("GPUBufferUsage MAP_WRITE combines only with COPY_SRC");
	}
	const vertexOrIndex = (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.INDEX as int32);
	const uniform = has(usage, GPUBufferUsage.UNIFORM as int32);
	if (uniform && has(usage, vertexOrIndex)) {
		stop("a UNIFORM buffer is a CPU shadow on GL and cannot also be VERTEX or INDEX");
	}
	when (webgl2) {
		if ((usage & vertexOrIndex) == vertexOrIndex) { stop("WebGL2 binds a buffer as VERTEX or as INDEX, not both"); }
	}
	const writable = has(usage, GPUBufferUsage.COPY_DST as int32);
	let slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		usage: usage,
		uniform: uniform,
		mapRead: mapRead,
		target: has(usage, GPUBufferUsage.INDEX as int32) ? GL_ELEMENT_ARRAY_BUFFER : GL_ARRAY_BUFFER,
		slotCount: writable && !mapRead ? INFLIGHT_SLOTS : 1,
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
			oglBufferData(slot.target, descriptor.size, mapRead ? GL_STREAM_READ : (writable ? GL_DYNAMIC_DRAW : GL_STATIC_DRAW));
			cacheRestoreBuffer(slot.target);
		}
		checkError(`createBuffer of ${labelOf(descriptor.label)}`);
	}
	storeBuffer(slot);
	return { id: id };
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

function storeBuffer(slot: BufferSlot): void {
	const index = slotOf(slot.id);
	if (index < buffers.length) { buffers[index] = slot; } else { buffers.push(slot); }
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = bufferIndex(buffer.id);
	if (!buffers[index].uniform) {
		for (let s = 0; s < buffers[index].slotCount; s++) {
			cacheInvalidateBuffer(buffers[index].names[s]);
			oglDeleteBuffer(buffers[index].names[s]);
		}
	}
	buffers[index] = { id: 0 };
	releaseId(bufferQueue, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers[bufferIndex(buffer.id)].size; }

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = writableBuffer(buffer.id, offset, bytes);
	claimBufferWrite(index, offset, bytes, "writeBuffer");
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

function claimBufferWrite(index: int32, offset: int64, bytes: int64, member: string): void {
	if (buffers[index].writtenFrame == -2) { stop(`GPUBuffer ${buffers[index].id} was created without COPY_DST`); }
	if (buffers[index].mapRead) { return; }
	const fresh = buffers[index].writtenFrame != frame;
	if (!fresh && offset < buffers[index].writtenEnd) {
		stop(`${member} at ${offset} on GPUBuffer ${buffers[index].id} rewrites bytes this frame already wrote, up to ${buffers[index].writtenEnd}`);
	}
	buffers[index].writtenFrame = frame;
	buffers[index].writtenEnd = offset + bytes;
	if (fresh && !buffers[index].uniform) {
		buffers[index].activeSlot = (buffers[index].activeSlot + 1) % buffers[index].slotCount;
		bound.vertexDirty = true;
		bound.indexDirty = true;
	}
}

function writableBuffer(id: uint32, offset: int64, bytes: int64): int32 {
	const index = bufferIndex(id);
	if (offset < 0 || offset + bytes > buffers[index].size) {
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${id} of ${buffers[index].size}`);
	}
	return index;
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

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocateId(textureQueue, "texture");
	if (id == 0) { return { id: 0 }; }
	if (has(descriptor.usage, GPUTextureUsage.STORAGE_BINDING as int32)) { stop("GPUTextureUsage.STORAGE_BINDING is not ported to gl yet"); }
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	if (width <= 0 || height <= 0) { stop("GPUTextureDescriptor.size needs a positive width and height"); }
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	if (descriptor.size.depthOrArrayLayers < 0) { stop("GPUTextureDescriptor.size.depthOrArrayLayers is negative"); }
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const mipLevels = mipLevelCountOf(descriptor, volume, layers);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	if (sampleCount > 1 && (volume || layers > 1 || mipLevels > 1)) {
		stop("a multisampled texture with mips, array layers or a 3d dimension is not ported to gl: sokol_gfx takes one mip and one layer per multisampled image");
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const copyDestination = has(usage, GPUTextureUsage.COPY_DST as int32);
	if (attachment && copyDestination) {
		stop("COPY_DST with RENDER_ATTACHMENT: a written texture rotates in-flight copies, which an attachment cannot");
	}
	if (sampleCount > 1 && !attachment) { stop("a multisampled texture must be a RENDER_ATTACHMENT"); }
	if (volume && (attachment || info.depth)) { stop("a 3d texture as RENDER_ATTACHMENT or with a depth format is not ported to gl yet"); }
	if (attachment && info.integer) {
		stop(`${descriptor.format} as RENDER_ATTACHMENT is not ported to gl: clearing an integer target needs glClearBufferuiv or glClearBufferiv`);
	}
	when (webgl2 || android) {
		if (attachment && info.needsColorBufferFloat) {
			stop(`${descriptor.format} as RENDER_ATTACHMENT needs EXT_color_buffer_float, which the GLES backend does not query yet`);
		}
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
	const rotates = copyDestination && mipLevels == 1 && layers == 1 && !volume;
	let slot: TextureSlot = {
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
		baseLevel: 0,
		maxLevel: mipLevels - 1,
		target: target,
		slotCount: rotates ? INFLIGHT_SLOTS : 1,
		activeSlot: 0,
		swapchainView: 0,
	};
	if (slot.target == GL_RENDERBUFFER) {
		slot.names[0] = oglCreateRenderbuffer(sampleCount, info.internalFormat, width, height);
	}
	for (let s = 0; s < slot.slotCount && slot.target != GL_RENDERBUFFER; s++) {
		const name = oglCreateTexture();
		slot.names[s] = name;
		cacheStoreUnit0();
		cacheBindTextureSampler(0, slot.target, name, 0);
		if (sampleCount > 1) {
			when (!webgl2 && !android) { oglTexStorage2DMultisample(slot.target, sampleCount, info.internalFormat, width, height); }
		} else {
			oglTexStorage(slot.target, mipLevels, info.internalFormat, width, height, layers);
		}
		cacheRestoreUnit0();
	}
	checkError(`createTexture of ${labelOf(descriptor.label)}`);
	const index = slotOf(id);
	if (index < textures.length) { textures[index] = slot; } else { textures.push(slot); }
	return { id: id };
}

function multisampleTarget(): int32 {
	when (webgl2 || android) { return GL_RENDERBUFFER; } else { return GL_TEXTURE_2D_MULTISAMPLE; }
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textureIndex(texture.id);
	if (textures[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	if (textures[index].target == GL_RENDERBUFFER) {
		oglDeleteRenderbuffer(textures[index].names[0]);
		textures[index] = { id: 0 };
		releaseId(textureQueue, texture.id);
		return;
	}
	for (let s = 0; s < textures[index].slotCount; s++) {
		cacheInvalidateTextureSampler(textures[index].names[s], 0);
		oglDeleteTexture(textures[index].names[s]);
	}
	textures[index] = { id: 0 };
	releaseId(textureQueue, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat { return textures[textureIndex(texture.id)].format; }

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	const t = textureIndex(texture.id);
	if (textures[t].swapchainView != 0) { stop("the swapchain texture is the default framebuffer and has no GL texture"); }
	return oglTextureNative(textures[t].names[textures[t].activeSlot]);
}

function rotateOnWholeWrite(index: int32, size: GPUExtent3D): void {
	const wholeTexture = textures[index].slotCount > 1 && size.width == textures[index].width && size.height == textures[index].height;
	if (wholeTexture) {
		textures[index].activeSlot = (textures[index].activeSlot + 1) % textures[index].slotCount;
		bound.resourcesDirty = true;
	}
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textureIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	if (!has(textures[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textures[index].id}, created without COPY_DST`);
	}
	const info = formatInfo(textures[index].format, "texture format");
	const mip = destination.mipLevel;
	const mips = textures[index].mipLevels;
	const volume = textures[index].volume;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textures[index].layers >> mip) : textures[index].layers;
	const rowPitch = checkedTexelWritePitch(
		textures[index].width,
		textures[index].height,
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
				rowPitch / info.bytesPerPixel,
				0,
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
			rowPitch / info.bytesPerPixel,
			rowsPerImage,
		);
	}
	cacheRestoreUnit0();
}

function viewDimensionOf(descriptor: GPUTextureViewDescriptor, t: int32): string {
	let name: string = descriptor.dimension;
	if (name == "") { name = textures[t].volume ? "3d" : (textures[t].layers > 1 ? "2d-array" : "2d"); }
	if ((name == "3d") != textures[t].volume) {
		stop(`GPUTextureViewDescriptor.dimension '${name}' does not match the ${textures[t].volume ? "3d" : "2d"} GPUTexture ${textures[t].id}`);
	}
	if (name != "2d" && name != "2d-array" && name != "cube" && name != "3d") {
		stopOnMember("GPUTextureViewDescriptor.dimension", name);
	}
	return name;
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textureIndex(texture.id);
	if (textures[t].swapchainView != 0) { return { id: textures[t].swapchainView }; }
	const id = allocateId(viewQueue, "view");
	if (id == 0) { return { id: 0 }; }
	const info = formatInfo(textures[t].format, "texture format");
	const usage = textures[t].usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const layers = textures[t].layers;
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? textures[t].mipLevels - baseMip : descriptor.mipLevelCount;
	if (baseMip < 0 || mipCount < 1 || baseMip + mipCount > textures[t].mipLevels) {
		stop(`view mips ${baseMip}+${mipCount} overrun GPUTexture ${textures[t].id}, which has ${textures[t].mipLevels} mips`);
	}
	const dimension = viewDimensionOf(descriptor, t);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (dimension == "3d") {
		if (baseLayer != 0 || layerCount > 1) { stop("a 3d view takes no baseArrayLayer or arrayLayerCount"); }
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (dimension == "2d") { layerCount = 1; }
		if (dimension == "cube") { layerCount = 6; }
		if (layerCount == 0) { layerCount = layers - baseLayer; }
		if (baseLayer < 0 || layerCount < 1 || baseLayer + layerCount > layers) {
			stop(`view layers ${baseLayer}+${layerCount} overrun GPUTexture ${textures[t].id}, which has ${layers} layers`);
		}
	}
	if (dimension == "cube") {
		if (!textures[t].cube) {
			stop(`a cube view needs GPUTexture ${textures[t].id} created square with exactly 6 layers and TEXTURE_BINDING: gl makes it a cube map`);
		}
		if (baseLayer != 0) { stop("a cube view at baseArrayLayer above 0 is not ported to gl"); }
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
		attachable: mipCount == 1 && layerCount == 1 && (dimension == "2d" || dimension == "2d-array"),
		swapchain: false,
	};
	const index = slotOf(slot.id);
	if (index < views.length) { views[index] = slot; } else { views.push(slot); }
	return { id: slot.id };
}

function checkSampledView(binding: int32, v: int32): void {
	const t = textureIndex(views[v].texture);
	const target = textures[t].target;
	const dimension = views[v].dimension;
	const whole = views[v].baseLayer == 0 && views[v].layerCount == textures[t].layers;
	if (target == GL_TEXTURE_3D && dimension == "3d") { return; }
	if (target == GL_TEXTURE_CUBE_MAP && dimension == "cube") { return; }
	if (target == GL_TEXTURE_2D_ARRAY && dimension == "2d-array" && whole) { return; }
	if (target == GL_TEXTURE_2D && dimension == "2d") { return; }
	if (target == GL_TEXTURE_2D_MULTISAMPLE && dimension == "2d") { return; }
	stop(`bind group entry ${binding}: a ${dimension} view of ${layersName(t)} GPUTexture ${textures[t].id} cannot be sampled on gl without texture views (GL 4.3 glTextureView, absent in GLES3)`);
}

function layersName(t: int32): string {
	if (textures[t].volume) { return "a 3d"; }
	if (textures[t].cube) { return "a cube-map"; }
	return textures[t].layers > 1 ? "a 2d-array" : "a 2d";
}

export function destroyView(view: GPUTextureView): void {
	const index = viewIndex(view.id);
	if (views[index].swapchain) { return; }
	oglDeleteFramebuffer(views[index].resolveFramebuffer);
	views[index] = { id: 0 };
	releaseId(viewQueue, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views[viewIndex(view.id)].texture }; }

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	updateSwapchainTexture(swapchainColor, swapchain);
	if (swapchainDepth != 0) { updateSwapchainTexture(swapchainDepth, swapchain); }
	return { id: swapchainColor };
}

export function swapchainDepthTexture(): GPUTexture { return { id: swapchainDepth }; }

function updateSwapchainTexture(id: uint32, swapchain: NativeSwapchain): void {
	const t = textureIndex(id);
	textures[t].width = swapchain.width;
	textures[t].height = swapchain.height;
	textures[t].sampleCount = swapchain.sampleCount == 0 ? 1 : swapchain.sampleCount;
}

export function createSampler(descriptor: GPUSamplerDescriptor): GPUSampler {
	const id = allocateId(samplerQueue, "sampler");
	if (id == 0) { return { id: 0 }; }
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter");
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter");
	let maxAnisotropy = descriptor.maxAnisotropy;
	if (maxAnisotropy < 1) { maxAnisotropy = 1; }
	if (maxAnisotropy > 1 && !(minLinear && magLinear && mipLinear)) {
		stop("GPUSamplerDescriptor.maxAnisotropy above 1 needs linear magFilter, minFilter and mipmapFilter");
	}
	when (webgl2 || android) {
		if (maxAnisotropy > 1) {
			stop("GPUSamplerDescriptor.maxAnisotropy above 1 needs EXT_texture_filter_anisotropic, which the GLES backend does not query yet");
		}
	}
	if (descriptor.lodMinClamp < 0) { stopOnMember("GPUSamplerDescriptor.lodMinClamp", `${descriptor.lodMinClamp}`); }
	const maxLod = descriptor.lodMaxClamp == 0 ? DEFAULT_LOD_MAX_CLAMP : descriptor.lodMaxClamp;
	if (maxLod < descriptor.lodMinClamp) {
		stop(`GPUSamplerDescriptor.lodMaxClamp ${maxLod} is below lodMinClamp ${descriptor.lodMinClamp}`);
	}
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
	when (!webgl2 && !android) { oglSamplerBorderColor(native, 0, 0, 0, 1); }
	const compare: string = descriptor.compare;
	if (compare == "") {
		oglSamplerParameteri(native, GL_TEXTURE_COMPARE_MODE, 0);
	} else {
		oglSamplerParameteri(native, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
		oglSamplerParameteri(native, GL_TEXTURE_COMPARE_FUNC, compareFunction(compare, "GPUSamplerDescriptor.compare"));
	}
	when (!webgl2 && !android) {
		if (maxAnisotropy > 1) {
			oglSamplerParameteri(native, GL_TEXTURE_MAX_ANISOTROPY, smaller(maxAnisotropy, oglGetInteger(GL_MAX_TEXTURE_MAX_ANISOTROPY)));
		}
	}
	checkError(`createSampler of ${labelOf(descriptor.label)}`);
	const index = slotOf(id);
	const slot: SamplerSlot = { id: id, native: native };
	if (index < samplers.length) { samplers[index] = slot; } else { samplers.push(slot); }
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplerIndex(sampler.id);
	cacheInvalidateTextureSampler(0, samplers[index].native);
	oglDeleteSampler(samplers[index].native);
	samplers[index] = { id: 0 };
	releaseId(samplerQueue, sampler.id);
}

function compileStage(stage: int32, code: string, entryPoint: string, label: string | null): uint32 {
	if (entryPoint != "" && entryPoint != "main") {
		stop(`GLSL enters at main, not '${entryPoint}', in ${labelOf(label)}`);
	}
	const shader = oglCompileShader(stage, code);
	if (shader == 0) {
		const log: string = oglLog();
		const stageName = stage == GL_VERTEX_SHADER ? "vertex" : "fragment";
		stop(`compiling the ${stageName} shader of ${labelOf(label)} failed:\n${log}`);
	}
	return shader;
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	stopOnUnportedShaderModule("gl", descriptor);
	const id = allocateId(shaderQueue, "shader module");
	if (id == 0) { return { id: 0 }; }
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const kind = bindingKind(kindName);
		const binding = descriptor.bindings[i].binding;
		checkStage(descriptor.bindings[i].stage);
		const expectedGroup = kind == BindingKind.Uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
		if (descriptor.bindings[i].group != expectedGroup) {
			stop(`shader binding ${binding} (${kind.toString()}) belongs in group ${expectedGroup}, not ${descriptor.bindings[i].group}`);
		}
		if (kind == BindingKind.Uniform) {
			const size = descriptor.bindings[i].size;
			if (size <= 0 || size % 16 != 0) { stop(`uniform binding ${binding} needs a block size in whole vec4s, not ${size}`); }
			if (slot.uniformCount == GPU_MAX_UNIFORM_BLOCKS) { stop("a shader module has over 8 uniform blocks"); }
			slot.uniforms[slot.uniformCount] = { binding: binding, size: size, location: -1, count: size / 16 };
			slot.uniformCount += 1;
			continue;
		}
		addResource(slot, binding, kind);
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
	const vertex = compileStage(GL_VERTEX_SHADER, descriptor.vertexCode, descriptor.vertexEntryPoint, descriptor.label);
	const fragment = compileStage(GL_FRAGMENT_SHADER, descriptor.fragmentCode, descriptor.fragmentEntryPoint, descriptor.label);
	slot.program = oglLinkProgram(vertex, fragment);
	if (slot.program == 0) {
		const log: string = oglLog();
		stop(`linking the program of ${labelOf(descriptor.label)} failed:\n${log}`);
	}
	resolveUniforms(slot, descriptor);
	resolveTextureUnits(slot, descriptor);
	checkError(`createShaderModule of ${labelOf(descriptor.label)}`);
	slot.id = id;
	const index = slotOf(slot.id);
	if (index < shaders.length) { shaders[index] = slot; } else { shaders.push(slot); }
	return { id: slot.id };
}

function addResource(ref slot: ShaderSlot, binding: int32, kind: BindingKind): void {
	for (let r = 0; r < slot.resourceCount; r++) {
		if (slot.resources[r].binding == binding && slot.resources[r].kind == kind) { return; }
	}
	if (slot.resourceCount == MAX_SHADER_RESOURCES) { stop("a shader module has over 24 resources"); }
	slot.resources[slot.resourceCount] = { binding: binding, kind: kind };
	slot.resourceCount += 1;
}

function checkPairTexture(slot: ShaderSlot, textureBinding: int32): void {
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
	const index = shaderIndex(module.id);
	cacheInvalidateProgram(shaders[index].program);
	oglDeleteProgram(shaders[index].program);
	shaders[index] = { id: 0 };
	releaseId(shaderQueue, module.id);
}

function attributeNameOf(shader: int32, location: int32): string | null {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		const name = shaders[shader].attributes[i].nativeName;
		if (name !== null && shaders[shader].attributes[i].location == location) { return name; }
	}
	return null;
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocateId(pipelineQueue, "render pipeline");
	if (id == 0) { return { id: 0 }; }
	const s = shaderIndex(descriptor.vertex.module.id);
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule on GL");
	}
	let slot: PipelineSlot = { id: 0, shader: descriptor.vertex.module.id };
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) { slot.blends[i] = defaultBlend(); }
	describeAttributes(s, descriptor, slot);
	describePrimitive(descriptor, slot);
	describeDepthStencil(descriptor, slot);
	describeBlend(descriptor, slot);
	slot.cullFace = cullFace(descriptor.primitive.cullMode);
	slot.frontFace = frontFace(descriptor.primitive.frontFace);
	slot.sampleCount = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	slot.id = id;
	const index = slotOf(slot.id);
	if (index < pipelines.length) { pipelines[index] = slot; } else { pipelines.push(slot); }
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
		when (webgl2 || android) {
			if (first != -1 && slot.writeMasks[i] != slot.writeMasks[first]) {
				stop(`fragment.targets[${i}].writeMask differs from target ${first}; GLES3 masks every target alike`);
			}
			if (first != -1 && !sameBlend(slot.blends[i], slot.blends[first])) {
				stop(`fragment.targets[${i}].blend differs from target ${first}; GLES3 blends every target alike`);
			}
		}
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
	const index = pipelineIndex(pipeline.id);
	if (bound.appliedPipeline == pipeline.id) { bound.appliedPipeline = 0; }
	for (let g = 0; g < 2; g++) {
		const layout = pipelines[index].layouts[g];
		if (layout != 0) {
			layouts[layoutIndex(layout)] = { id: 0 };
			releaseId(layoutQueue, layout);
		}
	}
	pipelines[index] = { id: 0 };
	releaseId(pipelineQueue, pipeline.id);
}

export function getBindGroupLayout(pipeline: GPURenderPipeline, index: int32): GPUBindGroupLayout {
	const p = pipelineIndex(pipeline.id);
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) {
		stopOnMember("getBindGroupLayout index", `${index}`);
	}
	if (pipelines[p].layouts[index] == 0) {
		const id = allocateId(layoutQueue, "bind group layout");
		if (id == 0) { return { id: 0 }; }
		const slot: LayoutSlot = { id: id, pipeline: pipeline.id, group: index };
		const l = slotOf(id);
		if (l < layouts.length) { layouts[l] = slot; } else { layouts.push(slot); }
		pipelines[p].layouts[index] = id;
	}
	return { id: pipelines[p].layouts[index] };
}

export function createBindGroup(descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	const id = allocateId(bindGroupQueue, "bind group");
	if (id == 0) { return { id: 0 }; }
	const l = layoutIndex(descriptor.layout.id);
	const group = layouts[l].group;
	const shader = shaderIndex(pipelines[pipelineIndex(layouts[l].pipeline)].shader);
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
	const index = slotOf(slot.id);
	if (index < bindGroups.length) { bindGroups[index] = slot; } else { bindGroups.push(slot); }
	return { id: slot.id };
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	const kind = entry.buffer.id != 0 ? BindingKind.Uniform :
		(entry.textureView.id != 0 ? BindingKind.Texture : BindingKind.Sampler);
	if (kind == BindingKind.Uniform) {
		const b = bufferIndex(entry.buffer.id);
		if (!buffers[b].uniform) { stop(`bind group entry ${entry.binding} needs a UNIFORM buffer`); }
		for (let u = 0; u < shaders[shader].uniformCount; u++) {
			const binding = shaders[shader].uniforms[u];
			if (binding.binding == entry.binding) {
				if (entry.offset < 0 || entry.offset % (UNIFORM_OFFSET_ALIGNMENT as int64) != 0) {
					stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${UNIFORM_OFFSET_ALIGNMENT}`);
				}
				if (entry.offset + (binding.size as int64) > buffers[b].size) {
					stop(`bind group entry ${entry.binding} offset ${entry.offset} overruns its buffer`);
				}
				if (entry.size != 0 && entry.size < (binding.size as int64)) {
					stop(`bind group entry ${entry.binding} size ${entry.size} is below its block of ${binding.size}`);
				}
				return;
			}
		}
	} else {
		if (kind == BindingKind.Texture) {
			if (!views[viewIndex(entry.textureView.id)].sampled) {
				stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`);
			}
			checkSampledView(entry.binding, viewIndex(entry.textureView.id));
		} else {
			samplerIndex(entry.sampler.id);
		}
		for (let r = 0; r < shaders[shader].resourceCount; r++) {
			if (shaders[shader].resources[r].binding == entry.binding && shaders[shader].resources[r].kind == kind) {
				return;
			}
		}
	}
	stop(`bind group ${group} entry ${entry.binding} (${kind.toString()}) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroupIndex(bindGroup.id);
	bindGroups[index] = { id: 0 };
	releaseId(bindGroupQueue, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (pass.active) { stop("finish with a render pass still open"); }
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
	stopOnUnportedRenderPass("gl", descriptor);
	if (pass.active) { stop("beginRenderPass with a render pass already open"); }
	pass = { active: true };
	let colorMask = 0;
	let offscreen = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = viewIndex(viewId);
		if (!views[v].color) { stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`); }
		if (views[v].swapchain) {
			if (i != 0) { stop(`colorAttachments[${i}] is the canvas, which GL draws only as attachment 0`); }
			if (descriptor.colorAttachments[i].resolveTarget.id != 0) {
				stop("colorAttachments[0] is the canvas, whose multisampled default framebuffer resolves itself on GL");
			}
			pass.swapchain = true;
		} else {
			offscreen = true;
		}
		if (!views[v].attachable) { stop(`colorAttachments[${i}].view spans several mips or layers: a render attachment is one mip of one layer`); }
		passExtent(views[v].texture, views[v].baseMip);
		pass.colorViews[i] = viewId;
		pass.resolveViews[i] = checkResolve(i, views[v].texture, descriptor.colorAttachments[i].resolveTarget.id);
		colorMask |= 1 << i;
		checkStoreOp(descriptor.colorAttachments[i].storeOp, `colorAttachments[${i}].storeOp`);
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	let depthTexture = 0;
	let depthViewSlot = -1;
	let depthStencil = false;
	if (depthView != 0) {
		const v = viewIndex(depthView);
		if (!views[v].depth) { stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT"); }
		if (!views[v].attachable) { stop("depthStencilAttachment.view spans several mips or layers: a render attachment is one mip of one layer"); }
		if (views[v].swapchain) { pass.swapchain = true; } else { offscreen = true; }
		passExtent(views[v].texture, views[v].baseMip);
		depthViewSlot = v;
		depthTexture = textureIndex(views[v].texture);
		depthStencil = formatInfo(textures[depthTexture].format, "depth format").stencil;
		checkStoreOp(descriptor.depthStencilAttachment.depthStoreOp, "depthStencilAttachment.depthStoreOp");
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	if (pass.swapchain && offscreen) {
		stop("a render pass mixes the canvas with offscreen attachments; GL draws the canvas through framebuffer 0");
	}
	if (pass.swapchain) {
		when (!webgl2 && !android) { oglDisable(GL_FRAMEBUFFER_SRGB); }
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
	when (!webgl2 && !android) { oglEnable(GL_FRAMEBUFFER_SRGB); }
	oglBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = GL_COLOR_ATTACHMENT0 + i;
		if (pass.colorViews[i] == 0) {
			oglFramebufferDetach(attachment);
			continue;
		}
		attachView(attachment, viewIndex(pass.colorViews[i]));
	}
	if (depthView >= 0) {
		oglFramebufferDetach(GL_DEPTH_ATTACHMENT);
		oglFramebufferDetach(GL_DEPTH_STENCIL_ATTACHMENT);
		attachView(depthStencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT, depthView);
	} else {
		oglFramebufferDetach(GL_DEPTH_STENCIL_ATTACHMENT);
	}
	const status = oglCheckFramebufferStatus();
	if (status != GL_FRAMEBUFFER_COMPLETE) { stop(`the render pass framebuffer is incomplete (status 0x${status.toString(16)})`); }
	oglDrawBuffers(GPU_MAX_COLOR_ATTACHMENTS, colorMask);
}

function attachView(attachment: int32, v: int32): void {
	const t = textureIndex(views[v].texture);
	const target = textures[t].target;
	const name = textures[t].names[0];
	if (target == GL_RENDERBUFFER) {
		oglFramebufferRenderbuffer(attachment, name);
	} else if (target == GL_TEXTURE_2D_ARRAY) {
		oglFramebufferTextureLayer(attachment, name, views[v].baseMip, views[v].baseLayer);
	} else if (target == GL_TEXTURE_CUBE_MAP) {
		oglFramebufferTexture2D(attachment, GL_TEXTURE_CUBE_MAP_POSITIVE_X + views[v].baseLayer, name, views[v].baseMip);
	} else {
		oglFramebufferTexture2D(attachment, target, name, views[v].baseMip);
	}
}

function clearAttachments(descriptor: GPURenderPassDescriptor, hasDepth: boolean, depthStencil: boolean): void {
	let clearAnyColor = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] != 0 && isClear(descriptor.colorAttachments[i].loadOp, `colorAttachments[${i}].loadOp`)) {
			clearAnyColor = true;
		}
	}
	const clearDepth = hasDepth && isClear(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp");
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
		if (isClear(descriptor.colorAttachments[i].loadOp, `colorAttachments[${i}].loadOp`)) {
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
	const t = textureIndex(texture);
	const width = Math.max(1, textures[t].width >> baseMip);
	const height = Math.max(1, textures[t].height >> baseMip);
	if (pass.width == 0) {
		pass.width = width;
		pass.height = height;
	} else if (pass.width != width || pass.height != height) {
		stop("render pass attachments differ in size");
	}
}

function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): uint32 {
	if (resolveId == 0) { return 0; }
	const r = viewIndex(resolveId);
	const resolveTexture = textureIndex(views[r].texture);
	if (textures[textureIndex(colorTexture)].sampleCount == 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`);
	}
	if (textures[resolveTexture].sampleCount != 1 || !views[r].color || views[r].swapchain) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample offscreen color RENDER_ATTACHMENT`);
	}
	if (!views[r].attachable) { stop(`colorAttachments[${attachment}].resolveTarget spans several mips or layers: a render attachment is one mip of one layer`); }
	passExtent(views[r].texture, views[r].baseMip);
	if (views[r].resolveFramebuffer == 0) {
		const resolveFramebuffer = oglCreateFramebuffer();
		oglBindFramebuffer(GL_FRAMEBUFFER, resolveFramebuffer);
		attachView(GL_COLOR_ATTACHMENT0, r);
		const status = oglCheckFramebufferStatus();
		if (status != GL_FRAMEBUFFER_COMPLETE) { stop(`the resolve framebuffer is incomplete (status 0x${status.toString(16)})`); }
		oglDrawBuffers(1, 1);
		views[r].resolveFramebuffer = resolveFramebuffer;
	}
	return resolveId;
}

function isClear(loadOp: string, member: string): boolean {
	const value = match (loadOp) {
		"clear" => 1,
		"load" => 0,
		_ => stopOnMember(member, loadOp),
	};
	return value == 1;
}

function checkStoreOp(storeOp: string, member: string): void {
	if (storeOp != "store" && storeOp != "discard") { stopOnMember(member, storeOp); }
}

export function endPass(): void {
	if (!pass.active) { stop("end without an open render pass"); }
	let readBound = false;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.resolveViews[i] == 0) { continue; }
		if (!readBound) {
			oglBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
			readBound = true;
		}
		const r = viewIndex(pass.resolveViews[i]);
		oglBindFramebuffer(GL_DRAW_FRAMEBUFFER, views[r].resolveFramebuffer);
		oglReadBuffer(GL_COLOR_ATTACHMENT0 + i);
		oglBlitColor(pass.width, pass.height);
	}
	pass.active = false;
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	pipelineIndex(pipeline.id);
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
	const g = bindGroupIndex(bindGroup.id);
	if (bindGroups[g].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups[g].group}`);
	}
	if ((dynamicOffsets.length as int32) != bindGroups[g].dynamicCount) {
		stop(`setBindGroup(${index}) takes ${bindGroups[g].dynamicCount} dynamic offsets, got ${dynamicOffsets.length}`);
	}
	if (index == GPU_UNIFORM_GROUP) {
		for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
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

export function setViewport(x: number, y: number, width: number, height: number, minDepth: number, maxDepth: number): void {
	if (!pass.active) { stop("setViewport outside a render pass"); }
	if (width < 0 || height < 0 || minDepth < 0 || maxDepth > 1 || minDepth > maxDepth) {
		stop(`setViewport ${width}x${height} depth ${minDepth}..${maxDepth} is outside WebGPU's valid range`);
	}
	const left = x as int32;
	const top = y as int32;
	const viewWidth = width as int32;
	const viewHeight = height as int32;
	if ((left as number) != x || (top as number) != y || (viewWidth as number) != width || (viewHeight as number) != height) {
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
	if (bound.appliedPipeline != 0 && pipelines[pipelineIndex(bound.appliedPipeline)].stencil) {
		applyStencilFaces(pipelineIndex(bound.appliedPipeline));
	}
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush(false);
	const mode = pipelines[pipelineIndex(bound.pipeline)].primitive;
	if (instanceCount > 1 || bound.instanced) {
		if (firstInstance == 0) {
			oglDrawArraysInstanced(mode, firstVertex, vertexCount, instanceCount);
		} else {
			when (webgl2 || android) {
				stop(`draw with firstInstance ${firstInstance}: GLES3 has no base instance`);
			} else {
				oglDrawArraysInstancedBaseInstance(mode, firstVertex, vertexCount, instanceCount, firstInstance);
			}
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
	const pipeline = pipelineIndex(bound.pipeline);
	const mode = pipelines[pipeline].primitive;
	if (pipelines[pipeline].stripIndexType != 0 && pipelines[pipeline].stripIndexType != bound.indexType) {
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
	when (webgl2 || android) {
		stop(`drawIndexed with baseVertex ${baseVertex} and firstInstance ${firstInstance}: GLES3 has neither`);
	} else {
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
	const p = pipelineIndex(bound.pipeline);
	if (shaders.length <= slotOf(pipelines[p].shader) || shaders[slotOf(pipelines[p].shader)].id != pipelines[p].shader) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	const s = shaderIndex(pipelines[p].shader);
	if (shaders[s].program != cache.program) {
		cache.program = shaders[s].program;
		oglUseProgram(cache.program);
	}
	applyDepthState(p);
	applyStencilState(p);
	if (pipelines[p].colorCount > 0) { applyBlendState(p); }
	if (pipelines[p].stripRestart != cache.primitiveRestart) {
		cache.primitiveRestart = pipelines[p].stripRestart;
		if (cache.primitiveRestart) { oglEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX); } else { oglDisable(GL_PRIMITIVE_RESTART_FIXED_INDEX); }
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
		when (!webgl2 && !android) {
			if (cache.sampleCount > 1) { oglEnable(GL_MULTISAMPLE); } else { oglDisable(GL_MULTISAMPLE); }
		}
	}
	bound.instanced = pipelines[p].instanced;
	bound.appliedPipeline = bound.pipeline;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
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
		when (webgl2 || android) {
			if (i == 0) { applyBlendAll(next, current); }
		} else {
			applyBlendTarget(i, next, current);
		}
		if (pipelines[p].writeMasks[i] != cache.writeMasks[i]) {
			cache.writeMasks[i] = pipelines[p].writeMasks[i];
			when (webgl2 || android) {
				if (i == 0) { oglColorMask(cache.writeMasks[0]); }
			} else {
				oglColorMaski(i, cache.writeMasks[i]);
			}
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

when (!webgl2 && !android) {
	function applyBlendTarget(i: int32, next: BlendState, current: BlendState): void {
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
}

function applyVertexBuffers(): void {
	const p = pipelineIndex(bound.pipeline);
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines[p].strides[slot] != 0 && bound.vertexBuffers[slot] == 0) {
			stop(`the pipeline reads vertex buffer ${slot}, which is not set`);
		}
	}
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
		const b = bufferIndex(bound.vertexBuffers[attribute.bufferSlot]);
		const name = buffers[b].names[buffers[b].activeSlot];
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
	const b = bufferIndex(bound.indexBuffer);
	cacheBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffers[b].names[buffers[b].activeSlot]);
	bound.indexDirty = false;
}

function entryOf(group: int32, binding: int32): int32 {
	for (let e = 0; e < bindGroups[group].entryCount; e++) {
		if (bindGroups[group].entries[e].binding == binding) { return e; }
	}
	return stopOnMember("bound bind group: missing entry for binding", `${binding}`);
}

function applyResources(): void {
	const s = shaderIndex(pipelines[pipelineIndex(bound.pipeline)].shader);
	bound.resourcesDirty = false;
	if (shaders[s].pairCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	const g = bindGroupIndex(bound.bindGroups[GPU_RESOURCE_GROUP]);
	for (let i = 0; i < shaders[s].pairCount; i++) {
		const pair: TexturePair = shaders[s].pairs[i];
		if (pair.unit < 0) { continue; }
		const view = viewIndex(bindGroups[g].entries[entryOf(g, pair.textureBinding)].textureView.id);
		const t = textureIndex(views[view].texture);
		const sampler = samplers[samplerIndex(bindGroups[g].entries[entryOf(g, pair.samplerBinding)].sampler.id)].native;
		cacheBindTextureSampler(pair.unit, textures[t].target, textures[t].names[textures[t].activeSlot], sampler);
		const lastMip = views[view].baseMip + views[view].mipCount - 1;
		if (textures[t].baseLevel != views[view].baseMip || textures[t].maxLevel != lastMip) {
			cacheActiveTexture(pair.unit);
			oglTexParameteri(textures[t].target, GL_TEXTURE_BASE_LEVEL, views[view].baseMip);
			oglTexParameteri(textures[t].target, GL_TEXTURE_MAX_LEVEL, lastMip);
			textures[t].baseLevel = views[view].baseMip;
			textures[t].maxLevel = lastMip;
		}
	}
}

function applyUniforms(): void {
	const s = shaderIndex(pipelines[pipelineIndex(bound.pipeline)].shader);
	bound.uniformsDirty = false;
	if (shaders[s].uniformCount == 0) { return; }
	if (bound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the pipeline reads bind group 0, which is not set"); }
	const g = bindGroupIndex(bound.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders[s].uniformCount; u++) {
		const uniform: UniformBinding = shaders[s].uniforms[u];
		const e = entryOf(g, uniform.binding);
		const offset = (bound.dynamicOffsets[bindGroups[g].dynamicIndex[e]] as int64) + bindGroups[g].entries[e].offset;
		const b = bufferIndex(bindGroups[g].entries[e].buffer.id);
		if (offset + (uniform.size as int64) > buffers[b].size) {
			stop(`uniform binding ${uniform.binding} at offset ${offset} overruns its buffer`);
		}
		if (uniform.location == -1) { continue; }
		oglUniform4fv(uniform.location, uniform.count, buffers[b].shadow[0], offset);
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	if (pass.active) { stop(`${member} inside a render pass`); }
	const index = bufferIndex(buffer.id);
	if (!has(buffers[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	if (buffers[index].uniform) { stop(`${member}: GPUBuffer ${buffer.id} is a CPU shadow uniform block on gl and cannot be copied`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	if (pass.active) { stop(`${member} inside a render pass`); }
	const index = textureIndex(info.texture.id);
	if (!has(textures[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	if (textures[index].swapchainView != 0) { stop(`${member}: the swapchain texture is the default framebuffer on gl`); }
	return index;
}

function copyRegion(member: string, info: GPUTexelCopyTextureInfo, index: int32, size: GPUExtent3D): void {
	checkedTexelCopyRegion(
		member,
		textures[index].id,
		textures[index].width,
		textures[index].height,
		textures[index].mipLevels,
		textures[index].layers,
		textures[index].volume,
		info,
		size,
	);
}

function colorFormatOf(index: int32, member: string): FormatInfo {
	const info = formatInfo(textures[index].format, "texture format");
	if (info.depth) { stop(`${member}: depth or stencil GPUTexture ${textures[index].id} is not ported to gl yet`); }
	return info;
}

@inline function bufferName(index: int32): uint32 { return buffers[index].names[buffers[index].activeSlot]; }

@inline function textureName(index: int32): uint32 { return textures[index].names[textures[index].activeSlot]; }

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedBufferCopy(source.id, buffers[from].size, sourceOffset, destination.id, buffers[to].size, destinationOffset, size);
	if (size == 0) { return; }
	if (from == to) { stop(`copyBufferToBuffer inside GPUBuffer ${source.id} is not ported to gl yet: a written buffer rotates its in-flight copies`); }
	claimBufferWrite(to, destinationOffset, size, "copyBufferToBuffer");
	oglCopyBufferData(bufferName(from), sourceOffset, bufferName(to), destinationOffset, size);
	checkError("copyBufferToBuffer");
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination.buffer, "copyTextureToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	const info = colorFormatOf(from, "copyTextureToBuffer source");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", info.bytesPerPixel, buffers[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (bytesPerRow as int64) * ((size.height - 1) as int64)
		+ ((size.width * info.bytesPerPixel) as int64);
	claimBufferWrite(to, destination.offset, span, "copyTextureToBuffer");
	checkError("copyTextureToBuffer");
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		const read = oglReadTexelsToBuffer(
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
			stop(`copyTextureToBuffer: ${textures[from].format} GPUTexture ${source.texture.id} is not color-renderable on this GL target, so it cannot be read back`);
		}
		if (read < 0) {
			stop(`copyTextureToBuffer: this GL target has no read format for ${textures[from].format} GPUTexture ${source.texture.id}`);
		}
	}
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	const info = colorFormatOf(to, "copyBufferToTexture destination");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", info.bytesPerPixel, buffers[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	rotateOnWholeWrite(to, size);
	const target = textures[to].target;
	const first = destination.origin.z;
	cacheStoreUnit0();
	cacheBindTextureSampler(0, target, textureName(to), 0);
	if (target == GL_TEXTURE_CUBE_MAP) {
		for (let z = 0; z < size.depthOrArrayLayers; z++) {
			oglTexSubImageFromBuffer(
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
				bytesPerRow / info.bytesPerPixel,
				0,
			);
		}
	} else {
		oglTexSubImageFromBuffer(
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
			bytesPerRow / info.bytesPerPixel,
			rowsPerImage,
		);
	}
	cacheRestoreUnit0();
	checkError("copyBufferToTexture");
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyTextureToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	colorFormatOf(from, "copyTextureToTexture source");
	const fromFormat: string = textures[from].format;
	const toFormat: string = textures[to].format;
	if (fromFormat != toFormat) { stop(`copyTextureToTexture between formats '${fromFormat}' and '${toFormat}'`); }
	if (textures[from].volume != textures[to].volume) { stop("copyTextureToTexture between a 3d and a 2d GPUTexture"); }
	copyRegion("copyTextureToTexture source", source, from, size);
	copyRegion("copyTextureToTexture destination", destination, to, size);
	if (
		from == to && source.mipLevel == destination.mipLevel
			&& source.origin.z < destination.origin.z + size.depthOrArrayLayers && destination.origin.z < source.origin.z + size.depthOrArrayLayers
			&& source.origin.x < destination.origin.x + size.width && destination.origin.x < source.origin.x + size.width
			&& source.origin.y < destination.origin.y + size.height && destination.origin.y < source.origin.y + size.height
	) {
		stop(`copyTextureToTexture regions overlap inside mip ${source.mipLevel} of GPUTexture ${source.texture.id}`);
	}
	if (from != to) { rotateOnWholeWrite(to, size); }
	checkError("copyTextureToTexture");
	cacheStoreUnit0();
	cacheBindTextureSampler(0, textures[to].target, textureName(to), 0);
	const copied = oglCopyTexels(
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

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	const index = bufferIndex(buffer.id);
	const read = mode == (GPUMapMode.READ as int32);
	if (!read && mode != (GPUMapMode.WRITE as int32)) { stop(`mapAsync mode ${mode} is not GPUMapMode READ or WRITE`); }
	const need = read ? GPUBufferUsage.MAP_READ as int32 : GPUBufferUsage.MAP_WRITE as int32;
	if (!has(buffers[index].usage, need)) { stop(`mapAsync ${read ? "READ" : "WRITE"} on GPUBuffer ${buffer.id}, created without ${read ? "MAP_READ" : "MAP_WRITE"}`); }
	if (buffers[index].mapMode != 0) { stop(`mapAsync on GPUBuffer ${buffer.id}, which is already mapped`); }
	const length = checkedMapRange("mapAsync", buffer.id, buffers[index].size, offset, size);
	if (read) {
		if (oglGetBufferData(bufferName(index), offset, buffers[index].shadow[offset], length) == 0) {
			stop(`mapAsync READ of GPUBuffer ${buffer.id}: this GL target cannot read a buffer back`);
		}
		checkError("mapAsync");
	}
	buffers[index].mapMode = mode;
	buffers[index].mapOffset = offset;
	buffers[index].mapSize = length;
}

function mappedRange(member: string, buffer: GPUBuffer, mode: int32, offset: int64, size: int64): int64 {
	const index = bufferIndex(buffer.id);
	if (buffers[index].mapMode != mode) { stop(`${member} on GPUBuffer ${buffer.id}, which is not mapped for ${mode == 1 ? "READ" : "WRITE"}`); }
	const length = checkedMapRange(member, buffer.id, buffers[index].size, offset, size == 0 ? buffers[index].mapOffset + buffers[index].mapSize - offset : size);
	if (offset < buffers[index].mapOffset || offset + length > buffers[index].mapOffset + buffers[index].mapSize) {
		stop(`${member} of ${length} bytes at ${offset} leaves the mapped range ${buffers[index].mapOffset}..${buffers[index].mapOffset + buffers[index].mapSize} of GPUBuffer ${buffer.id}`);
	}
	return length;
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const length = mappedRange("getMappedRange", buffer, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	oglCopyBytes(bytes[0], 0, buffers[bufferIndex(buffer.id)].shadow[offset], length);
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	mappedRange("writeMappedRange", buffer, GPUMapMode.WRITE as int32, offset, bytes);
	const index = bufferIndex(buffer.id);
	const target = buffers[index].target;
	cacheStoreBuffer(target);
	cacheBindBuffer(target, bufferName(index));
	oglBufferSubData(target, offset, data[0], bytes);
	cacheRestoreBuffer(target);
}

export function unmap(buffer: GPUBuffer): void {
	const index = bufferIndex(buffer.id);
	if (buffers[index].mapMode == 0) { stop(`unmap on GPUBuffer ${buffer.id}, which is not mapped`); }
	buffers[index].mapMode = 0;
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	stop("createComputePipeline is not ported to gl yet");
	return { id: 0 };
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	stop("beginComputePass is not ported to gl yet");
	return { id: 0 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void { stop("setPipeline on a compute pass is not ported to gl yet"); }

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	stop("setBindGroup on a compute pass is not ported to gl yet");
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void { stop("dispatchWorkgroups is not ported to gl yet"); }

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	stop("dispatchWorkgroupsIndirect is not ported to gl yet");
}

export function endComputePass(): void { stop("end on a compute pass is not ported to gl yet"); }

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	stop("createQuerySet is not ported to gl yet");
	return { id: 0 };
}

export function destroyQuerySet(querySet: GPUQuerySet): void { stop("destroy on a GPUQuerySet is not ported to gl yet"); }

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	stop("resolveQuerySet is not ported to gl yet");
}

export function beginOcclusionQuery(queryIndex: int32): void { stop("beginOcclusionQuery is not ported to gl yet"); }
export function endOcclusionQuery(): void { stop("endOcclusionQuery is not ported to gl yet"); }

export function limits(): GPUSupportedLimits {
	stop("limits is not ported to gl yet");
	return {};
}

export function features(): GPUSupportedFeatures {
	stop("features is not ported to gl yet");
	return { bits: 0 };
}

export function pushDebugGroup(label: string): void { stop("pushDebugGroup is not ported to gl yet"); }
export function popDebugGroup(): void { stop("popDebugGroup is not ported to gl yet"); }
export function insertDebugMarker(label: string): void { stop("insertDebugMarker is not ported to gl yet"); }
