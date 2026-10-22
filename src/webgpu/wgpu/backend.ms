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
	GPULiveCounts,
	GPUPrimitiveState,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
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
	checkedTexelCopyRegion,
	checkedTexelWritePitch,
	stopOnUnportedRenderPass,
	stopOnUnportedShaderModule,
} from "../types.ms";
import {
	WgBindGroupImpl,
	WgBufferImpl,
	WgLayoutImpl,
	WgModuleImpl,
	WgPipelineImpl,
	WgSamplerImpl,
	WgTextureImpl,
	WgViewImpl,
	wgBeginEncoder,
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
	wgCreateLayout,
	wgCreateModule,
	wgCreatePipeline,
	wgCreateSampler,
	wgCreateTexture,
	wgCreateView,
	wgDepthAttachment,
	wgDepthStencil,
	wgDraw,
	wgDrawIndexed,
	wgDynamicOffset,
	wgEndPass,
	wgFinish,
	wgLayoutEntry,
	wgMaxTextureDimension2D,
	wgMinUniformBufferOffsetAlignment,
	wgReleaseBindGroup,
	wgReleaseBuffer,
	wgReleaseLayout,
	wgReleaseModule,
	wgReleasePipeline,
	wgReleaseSampler,
	wgReleaseTexture,
	wgReleaseView,
	wgHasFeature,
	wgSetBindGroup,
	wgSetBlendConstant,
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

const SLOT_SHIFT = 16;
const SLOT_MASK = 0xFFFF;
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

const FEATURE_RG11B10_UFLOAT_RENDERABLE = 0x0C;
const FEATURE_FLOAT32_BLENDABLE = 0x0F;

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
const LAYOUT_UNIFORM = 0;
const LAYOUT_TEXTURE = 1;
const LAYOUT_SAMPLER = 2;
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

enum BindingKind {
	Uniform,
	Texture,
	Sampler,
}

struct FormatInfo {
	native: int32;
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
}

struct SlotQueue {
	free: Vec<int32>;
	generations: Vec<uint32>;
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
	size: int32;
}

struct ShaderSlot {
	id: uint32;
	vertex: Ptr<WgModuleImpl>;
	fragment: Ptr<WgModuleImpl>;
	vertexEntry: string;
	fragmentEntry: string;
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
}

struct LayoutSlot {
	id: uint32;
	pipeline: uint32;
	group: int32;
}

struct BindGroupSlot {
	id: uint32;
	group: int32;
	native: Ptr<WgBindGroupImpl>;
	dynamicCount: int32;
}

let frame: int64 = 0;
let encoding = false;
let passActive = false;
let boundPipeline: uint32 = 0;
let boundIndexFormat = 0;
let passWidth = 0;
let passHeight = 0;
let uniformAlignment = 256;
let maxTextureDimension = 0;
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = {
	format: "bgra8unorm",
	depthFormat: "depth32float",
	sampleCount: 1,
};

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

function stopOnHandle(kind: string, id: uint32): int32 {
	console.log(`webgpu wgpu: ${kind} ${id} is not a live handle`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function allocateId(ref queue: SlotQueue, what: string): uint32 {
	let index: int32 = 0;
	if (queue.free.length > 0) {
		index = queue.free[queue.free.length - 1];
		queue.free.pop();
	} else {
		if (queue.generations.length == 0) { queue.generations.push(0); }
		index = queue.generations.length as int32;
		if (index > SLOT_MASK) {
			console.error(`webgpu wgpu: ${what} pool exhausted (65535 live handles)`);
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

function loadOp(op: string, member: string): int32 {
	return match (op) {
		"clear" => LOAD_CLEAR,
		"load" => LOAD_LOAD,
		_ => stopOnMember(member, op),
	};
}

function storeOp(op: string, member: string): int32 {
	return match (op) {
		"store" => STORE_STORE,
		"discard" => STORE_DISCARD,
		_ => stopOnMember(member, op),
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

function visibility(stage: string): int32 {
	return match (stage) {
		"vertex" => STAGE_VERTEX,
		"fragment" => STAGE_FRAGMENT,
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

function bindingType(kind: BindingKind, sample: string, sampler: string): int32 {
	return match (kind) {
		BindingKind.Uniform => 0,
		BindingKind.Texture => sampleType(sample),
		BindingKind.Sampler => samplerType(sampler),
	};
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
	frame = 0;
	encoding = false;
	passActive = false;
	boundPipeline = 0;
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
	let counts: GPULiveCounts = { buffers: 0 };
	for (let i = 1; i < buffers.length; i++) { if (buffers[i].id != 0) { counts.buffers += 1; } }
	for (let i = 1; i < textures.length; i++) {
		if (textures[i].id != 0 && textures[i].swapchainView == 0) { counts.textures += 1; }
	}
	for (let i = 1; i < views.length; i++) {
		if (views[i].id != 0 && !views[i].swapchain) { counts.views += 1; }
	}
	for (let i = 1; i < samplers.length; i++) { if (samplers[i].id != 0) { counts.samplers += 1; } }
	for (let i = 1; i < shaders.length; i++) {
		if (shaders[i].id != 0) { counts.shaderModules += 1; }
	}
	for (let i = 1; i < pipelines.length; i++) {
		if (pipelines[i].id != 0) { counts.pipelines += 1; }
	}
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
	textures.push({
		id: textureId,
		format: format,
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		mipLevels: 1,
		layers: 1,
		native: NO_TEXTURE,
		swapchainView: viewId,
	});
	views.push({
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
	if (passActive) { stop("shutdown with a render pass still open"); }
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
		if (textures[i].id != 0 && textures[i].swapchainView == 0) {
			destroyTexture({ id: textures[i].id });
		}
	}
	for (let i = 1; i < buffers.length; i++) {
		if (buffers[i].id != 0) { destroyBuffer({ id: buffers[i].id }); }
	}
	wgShutdown();
	encoding = false;
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
	return { backend: "webgpu", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocateId(bufferQueue, "buffer");
	if (id == 0) { return { id: 0 }; }
	const usage = descriptor.usage;
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
	if (has(usage, (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.MAP_WRITE as int32))) {
		stop("GPUBufferUsage MAP_READ and MAP_WRITE are not ported to wgpu: mapAsync completes in the browser's event loop and cannot block here without ASYNCIFY or JSPI");
	}
	if (has(usage, GPUBufferUsage.STORAGE as int32)) { stop("GPUBufferUsage.STORAGE is not ported to wgpu yet"); }
	if (has(usage, GPUBufferUsage.INDIRECT as int32)) { stop("GPUBufferUsage.INDIRECT is not ported to wgpu yet"); }
	const native = wgCreateBuffer(descriptor.size, usage, labelText(descriptor.label));
	if (native == null) { stop(`wgpuDeviceCreateBuffer failed for ${labelOf(descriptor.label)}`); }
	const slot: BufferSlot = { id: id, size: descriptor.size, usage: usage, native: native, writtenFrame: -1, writtenEnd: 0 };
	const index = slotOf(id);
	if (index < buffers.length) { buffers[index] = slot; } else { buffers.push(slot); }
	return { id: id };
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = bufferIndex(buffer.id);
	wgReleaseBuffer(buffers[index].native);
	buffers[index] = { id: 0 };
	releaseId(bufferQueue, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 {
	return buffers[bufferIndex(buffer.id)].size;
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	const index = bufferIndex(buffer.id);
	if (!has(buffers[index].usage, GPUBufferUsage.COPY_DST as int32)) {
		stop(`GPUBuffer ${buffer.id} was created without COPY_DST`);
	}
	if (offset < 0 || offset + bytes > buffers[index].size) {
		const id = buffer.id;
		const size = buffers[index].size;
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${id} of ${size}`);
	}
	if ((offset & 3) != 0) { stop(`writeBuffer offset ${offset} is not a multiple of 4`); }
	if (buffers[index].writtenFrame != frame) {
		buffers[index].writtenFrame = frame;
	} else if (offset < buffers[index].writtenEnd) {
		stop(`writeBuffer at ${offset} on GPUBuffer ${buffer.id} rewrites bytes this frame already wrote, up to ${buffers[index].writtenEnd}`);
	}
	buffers[index].writtenEnd = offset + bytes;
	wgWriteBuffer(buffers[index].native, offset, data[0], bytes);
}

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocateId(textureQueue, "texture");
	if (id == 0) { return { id: 0 }; }
	if (has(descriptor.usage, GPUTextureUsage.STORAGE_BINDING as int32)) { stop("GPUTextureUsage.STORAGE_BINDING is not ported to wgpu yet"); }
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
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
	const mipLevels = mipLevelCountOf(descriptor, volume, layers);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	if (sampleCount > 1 && (volume || layers > 1 || mipLevels > 1)) {
		stop("a multisampled texture with mips, array layers or a 3d dimension is not ported to wgpu: WebGPU takes one mip and one layer");
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (volume && (attachment || info.depth)) { stop("a 3d texture as RENDER_ATTACHMENT or with a depth format is not ported to wgpu yet"); }
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
		usage: usage,
		sampleCount: sampleCount,
		mipLevels: mipLevels,
		layers: layers,
		volume: volume,
		cube: cube,
		native: native,
		swapchainView: 0,
	};
	const index = slotOf(id);
	if (index < textures.length) { textures[index] = slot; } else { textures.push(slot); }
	return { id: id };
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textureIndex(texture.id);
	if (textures[index].swapchainView != 0) {
		stop("the swapchain texture belongs to the platform");
	}
	wgReleaseTexture(textures[index].native);
	textures[index] = { id: 0 };
	releaseId(textureQueue, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 {
	return textures[textureIndex(texture.id)].width;
}

export function textureHeight(texture: GPUTexture): int32 {
	return textures[textureIndex(texture.id)].height;
}

export function textureUsage(texture: GPUTexture): int32 {
	return textures[textureIndex(texture.id)].usage;
}

export function textureFormat(texture: GPUTexture): GPUTextureFormat {
	return textures[textureIndex(texture.id)].format;
}

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	return wgTextureNative(textures[textureIndex(texture.id)].native);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textureIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (!has(textures[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${destination.texture.id}, created without COPY_DST`);
	}
	const info = formatInfo(textures[index].format, "texture format");
	const mip = destination.mipLevel;
	const mips = textures[index].mipLevels;
	const depth = textures[index].volume && mip >= 0 && mip < mips ? Math.max(1, textures[index].layers >> mip) : textures[index].layers;
	const bytesPerRow = checkedTexelWritePitch(
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
	wgWriteTexture(
		textures[index].native,
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
	if (name == "") { name = textures[t].volume ? "3d" : (textures[t].layers > 1 ? "2d-array" : "2d"); }
	if ((name == "3d") != textures[t].volume) {
		stop(`GPUTextureViewDescriptor.dimension '${name}' does not match the ${textures[t].volume ? "3d" : "2d"} GPUTexture ${textures[t].id}`);
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
	const t = textureIndex(texture.id);
	if (textures[t].swapchainView != 0) { return { id: textures[t].swapchainView }; }
	const id = allocateId(viewQueue, "view");
	if (id == 0) { return { id: 0 }; }
	const info = formatInfo(textures[t].format, "texture format");
	const label = labelText(descriptor.label);
	const layers = textures[t].layers;
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? textures[t].mipLevels - baseMip : descriptor.mipLevelCount;
	if (baseMip < 0 || mipCount < 1 || baseMip + mipCount > textures[t].mipLevels) {
		stop(`view mips ${baseMip}+${mipCount} overrun GPUTexture ${textures[t].id}, which has ${textures[t].mipLevels} mips`);
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
			stop(`view layers ${baseLayer}+${layerCount} overrun GPUTexture ${textures[t].id}, which has ${layers} layers`);
		}
	}
	if (dimension == VIEW_CUBE || dimension == VIEW_CUBE_ARRAY) {
		if (!textures[t].cube) {
			stop(`a cube view needs GPUTexture ${textures[t].id} created square, with TEXTURE_BINDING and a depthOrArrayLayers multiple of 6`);
		}
		if (layerCount % 6 != 0 || baseLayer % 6 != 0) { stop("a cube view takes whole cubes: baseArrayLayer and arrayLayerCount multiples of 6"); }
	}
	const native = wgCreateView(textures[t].native, ASPECT_ALL, dimension, baseMip, mipCount, baseLayer, layerCount, label);
	if (native == null) { stop(`wgpuTextureCreateView failed for ${labelOf(descriptor.label)}`); }
	let binding = NO_VIEW;
	if (has(textures[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
		binding = native;
		if (info.stencil) {
			binding = wgCreateView(textures[t].native, ASPECT_DEPTH_ONLY, dimension, baseMip, mipCount, baseLayer, layerCount, label);
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
		attachable: mipCount == 1 && layerCount == 1 && (dimension == VIEW_2D || dimension == VIEW_2D_ARRAY),
		swapchain: false,
	};
	const index = slotOf(id);
	if (index < views.length) { views[index] = slot; } else { views.push(slot); }
	return { id: id };
}

export function destroyView(view: GPUTextureView): void {
	const index = viewIndex(view.id);
	if (views[index].swapchain) { return; }
	if (views[index].binding != views[index].native) { wgReleaseView(views[index].binding); }
	wgReleaseView(views[index].native);
	views[index] = { id: 0 };
	releaseId(viewQueue, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture {
	return { id: views[viewIndex(view.id)].texture };
}

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = viewIndex(textures[textureIndex(swapchainColor)].swapchainView);
	views[v].native = wgViewFrom(swapchain.renderView);
	views[v].swapchainResolve = wgViewFrom(swapchain.resolveView);
	if (swapchainDepth != 0) {
		if (swapchain.depthStencilView === null) {
			stop("the canvas has a depth format and the swapchain no depth view");
		}
		updateSwapchainTexture(swapchainDepth, swapchain);
		const d = viewIndex(textures[textureIndex(swapchainDepth)].swapchainView);
		views[d].native = wgViewFrom(swapchain.depthStencilView);
	}
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
	const index = slotOf(id);
	const slot: SamplerSlot = { id: id, native: native };
	if (index < samplers.length) { samplers[index] = slot; } else { samplers.push(slot); }
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplerIndex(sampler.id);
	wgReleaseSampler(samplers[index].native);
	samplers[index] = { id: 0 };
	releaseId(samplerQueue, sampler.id);
}

function entryPoint(name: string): string { return name == "" ? "main" : name; }

function createModule(code: string, label: string | null): Ptr<WgModuleImpl> {
	const module = wgCreateModule(code, labelText(label));
	if (module == null) { stop(`wgpuDeviceCreateShaderModule failed for ${labelOf(label)}`); }
	return module;
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	stopOnUnportedShaderModule("wgpu", descriptor);
	const id = allocateId(shaderQueue, "shader module");
	if (id == 0) { return { id: 0 }; }
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const kind = bindingKind(kindName);
		const native: ShaderBinding = {
			binding: descriptor.bindings[i].binding,
			kind: kind,
			visibility: visibility(descriptor.bindings[i].stage),
			bindingType: bindingType(
				kind,
				descriptor.bindings[i].sampleType,
				descriptor.bindings[i].samplerType,
			),
			viewDimension: bindingViewDimension(descriptor.bindings[i].viewDimension),
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
	slot.vertex = createModule(descriptor.vertexCode, descriptor.label);
	slot.fragment = createModule(descriptor.fragmentCode, descriptor.label);
	slot.vertexEntry = entryPoint(descriptor.vertexEntryPoint);
	slot.fragmentEntry = entryPoint(descriptor.fragmentEntryPoint);
	for (let u = 0; u < slot.uniformCount; u++) {
		const binding = slot.uniforms[u];
		wgLayoutEntry(u, binding.binding, binding.visibility, LAYOUT_UNIFORM, 0, VIEW_2D);
	}
	slot.groupLayouts[GPU_UNIFORM_GROUP] = wgCreateLayout(slot.uniformCount);
	for (let r = 0; r < slot.resourceCount; r++) {
		const binding = slot.resources[r];
		const kind = binding.kind == BindingKind.Texture ? LAYOUT_TEXTURE : LAYOUT_SAMPLER;
		wgLayoutEntry(r, binding.binding, binding.visibility, kind, binding.bindingType, binding.viewDimension);
	}
	slot.groupLayouts[GPU_RESOURCE_GROUP] = wgCreateLayout(slot.resourceCount);
	const uniformLayout = slot.groupLayouts[GPU_UNIFORM_GROUP];
	if (uniformLayout == null || slot.groupLayouts[GPU_RESOURCE_GROUP] == null) {
		stop(`wgpuDeviceCreateBindGroupLayout failed for ${labelOf(descriptor.label)}`);
	}
	slot.id = id;
	const index = slotOf(slot.id);
	if (index < shaders.length) { shaders[index] = slot; } else { shaders.push(slot); }
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
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaderIndex(module.id);
	wgReleaseModule(shaders[index].vertex);
	wgReleaseModule(shaders[index].fragment);
	wgReleaseLayout(shaders[index].groupLayouts[GPU_UNIFORM_GROUP]);
	wgReleaseLayout(shaders[index].groupLayouts[GPU_RESOURCE_GROUP]);
	shaders[index] = { id: 0 };
	releaseId(shaderQueue, module.id);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocateId(pipelineQueue, "render pipeline");
	if (id == 0) { return { id: 0 }; }
	const s = shaderIndex(descriptor.vertex.module.id);
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
		shaders[s].vertex,
		shaders[s].vertexEntry,
		shaders[s].fragment,
		shaders[s].fragmentEntry,
		shaders[s].groupLayouts[GPU_UNIFORM_GROUP],
		shaders[s].groupLayouts[GPU_RESOURCE_GROUP],
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
	const index = slotOf(slot.id);
	if (index < pipelines.length) { pipelines[index] = slot; } else { pipelines.push(slot); }
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
	const index = pipelineIndex(pipeline.id);
	wgReleasePipeline(pipelines[index].native);
	for (let g = 0; g < 2; g++) {
		const layout = pipelines[index].layouts[g];
		if (layout != 0) {
			layouts[layoutIndex(layout)] = { id: 0 };
			releaseId(layoutQueue, layout);
		}
	}
	if (boundPipeline == pipeline.id) { boundPipeline = 0; }
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
	let count = 0;
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) {
			continue;
		}
		if (entry.buffer.id != 0) {
			const size = uniformEntrySize(shader, entry);
			const buffer = buffers[bufferIndex(entry.buffer.id)].native;
			wgBindEntry(count, entry.binding, buffer, entry.offset, size, NO_VIEW, NO_SAMPLER);
			slot.dynamicCount += 1;
		} else if (entry.textureView.id != 0) {
			checkResource(shader, entry.binding, BindingKind.Texture, group);
			const view = views[viewIndex(entry.textureView.id)].binding;
			if (view == null) {
				stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`);
			}
			wgBindEntry(count, entry.binding, NO_BUFFER, 0, 0, view, NO_SAMPLER);
		} else {
			checkResource(shader, entry.binding, BindingKind.Sampler, group);
			const sampler = samplers[samplerIndex(entry.sampler.id)].native;
			wgBindEntry(count, entry.binding, NO_BUFFER, 0, 0, NO_VIEW, sampler);
		}
		count += 1;
	}
	slot.native = wgCreateBindGroup(shaders[shader].groupLayouts[group], count);
	if (slot.native == null) {
		stop(`wgpuDeviceCreateBindGroup failed for ${labelOf(descriptor.label)}`);
	}
	slot.id = id;
	const index = slotOf(slot.id);
	if (index < bindGroups.length) { bindGroups[index] = slot; } else { bindGroups.push(slot); }
	return { id: slot.id };
}

function uniformEntrySize(shader: int32, entry: GPUBindGroupEntry): int64 {
	const b = bufferIndex(entry.buffer.id);
	if (!has(buffers[b].usage, GPUBufferUsage.UNIFORM as int32)) {
		stop(`bind group entry ${entry.binding} needs a UNIFORM buffer`);
	}
	for (let u = 0; u < shaders[shader].uniformCount; u++) {
		const binding = shaders[shader].uniforms[u];
		if (binding.binding == entry.binding) {
			if (entry.offset < 0 || entry.offset % (uniformAlignment as int64) != 0) {
				stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${uniformAlignment}`);
			}
			if (entry.offset + (binding.size as int64) > buffers[b].size) {
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
	return 0;
}

function checkResource(shader: int32, binding: int32, kind: BindingKind, group: int32): void {
	for (let r = 0; r < shaders[shader].resourceCount; r++) {
		const resource = shaders[shader].resources[r];
		if (resource.binding == binding && resource.kind == kind) { return; }
	}
	const name = kind.toString();
	stop(`bind group ${group} entry ${binding} (${name}) is not a binding of the pipeline shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroupIndex(bindGroup.id);
	wgReleaseBindGroup(bindGroups[index].native);
	bindGroups[index] = { id: 0 };
	releaseId(bindGroupQueue, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder {
	if (encoding) { stop("createCommandEncoder with the frame's encoder not yet finished"); }
	if (wgBeginEncoder() == 0) { stop("wgpuDeviceCreateCommandEncoder failed"); }
	encoding = true;
	return { id: 1 };
}

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (passActive) { stop("finish with a render pass still open"); }
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
	stopOnUnportedRenderPass("wgpu", descriptor);
	if (passActive) { stop("beginRenderPass with a render pass already open"); }
	if (!encoding) { stop("beginRenderPass without createCommandEncoder"); }
	passWidth = 0;
	passHeight = 0;
	let count = 0;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = descriptor.colorAttachments[i];
		if (attachment.view.id == 0) {
			wgColorAttachment(i, NO_VIEW, NO_VIEW, 0, 0, 0, 0, 0, 0);
			continue;
		}
		const v = viewIndex(attachment.view.id);
		checkColorAttachment(i, views[v].texture);
		if (!views[v].attachable) { stop(`colorAttachments[${i}].view spans several mips or layers: a render attachment is one mip of one layer`); }
		passExtent(views[v].texture, views[v].baseMip);
		let resolve = views[v].swapchainResolve;
		if (attachment.resolveTarget.id != 0) {
			resolve = checkResolve(i, views[v].texture, attachment.resolveTarget.id);
		}
		const color = attachment.clearValue;
		wgColorAttachment(
			i,
			views[v].native,
			resolve,
			loadOp(attachment.loadOp, `colorAttachments[${i}].loadOp`),
			storeOp(attachment.storeOp, `colorAttachments[${i}].storeOp`),
			color.r,
			color.g,
			color.b,
			color.a,
		);
		count = i + 1;
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	if (depthView != 0) {
		const v = viewIndex(depthView);
		const t = textureIndex(views[v].texture);
		if (!views[v].attachable) { stop("depthStencilAttachment.view spans several mips or layers: a render attachment is one mip of one layer"); }
		passExtent(views[v].texture, views[v].baseMip);
		const info = formatInfo(textures[t].format, "depth format");
		if (!info.depth || !has(textures[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT");
		}
		const depth = descriptor.depthStencilAttachment;
		wgDepthAttachment(
			views[v].native,
			loadOp(depth.depthLoadOp, "depthStencilAttachment.depthLoadOp"),
			storeOp(depth.depthStoreOp, "depthStencilAttachment.depthStoreOp"),
			depth.depthClearValue,
			info.stencil ? 1 : 0,
		);
	}
	if (count == 0 && depthView == 0) { stop("beginRenderPass without an attachment"); }
	if (wgBeginPass(count, depthView != 0 ? 1 : 0, passWidth, passHeight) == 0) {
		stop("wgpuCommandEncoderBeginRenderPass failed");
	}
	passActive = true;
	boundPipeline = 0;
	boundIndexFormat = 0;
	return { id: 1 };
}

function passExtent(texture: uint32, baseMip: int32): void {
	const t = textureIndex(texture);
	const width = Math.max(1, textures[t].width >> baseMip);
	const height = Math.max(1, textures[t].height >> baseMip);
	if (passWidth == 0) {
		passWidth = width;
		passHeight = height;
	} else if (passWidth != width || passHeight != height) {
		stop("render pass attachments differ in size");
	}
}

function checkColorAttachment(attachment: int32, texture: uint32): void {
	const t = textureIndex(texture);
	const attachable = has(textures[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	if (formatInfo(textures[t].format, "color format").depth || !attachable) {
		stop(`colorAttachments[${attachment}].view is not a color RENDER_ATTACHMENT`);
	}
}

function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): Ptr<WgViewImpl> {
	const r = viewIndex(resolveId);
	const resolveTexture = textureIndex(views[r].texture);
	if (textures[textureIndex(colorTexture)].sampleCount == 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`);
	}
	if (textures[resolveTexture].sampleCount != 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample view`);
	}
	checkColorAttachment(attachment, views[r].texture);
	if (!views[r].attachable) { stop(`colorAttachments[${attachment}].resolveTarget spans several mips or layers: a render attachment is one mip of one layer`); }
	return views[r].native;
}

export function endPass(): void {
	if (!passActive) { stop("end without an open render pass"); }
	wgEndPass();
	passActive = false;
}

@inline function checkPass(call: string): void {
	if (!passActive) { stop(`${call} outside a render pass`); }
}

@inline export function setPipeline(pipeline: GPURenderPipeline): void {
	checkPass("setPipeline");
	wgSetPipeline(pipelines[pipelineIndex(pipeline.id)].native);
	boundPipeline = pipeline.id;
}

@inline export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	checkPass("setVertexBuffer");
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) {
		stopOnMember("setVertexBuffer slot", `${slot}`);
	}
	wgSetVertexBuffer(slot, buffers[bufferIndex(buffer.id)].native, offset);
}

@inline export function setIndexBuffer(
	buffer: GPUBuffer,
	format: GPUIndexFormat,
	offset: int64,
): void {
	checkPass("setIndexBuffer");
	boundIndexFormat = indexFormat(format);
	wgSetIndexBuffer(buffers[bufferIndex(buffer.id)].native, boundIndexFormat, offset);
}

export function setBindGroup(
	index: int32,
	bindGroup: GPUBindGroup,
	dynamicOffsets: Readonly<Span<uint32>>,
): void {
	checkPass("setBindGroup");
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) {
		stopOnMember("setBindGroup index", `${index}`);
	}
	if (bindGroup.id == 0) {
		wgSetBindGroup(index, NO_BIND_GROUP, 0);
		return;
	}
	const g = bindGroupIndex(bindGroup.id);
	if (bindGroups[g].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups[g].group}`);
	}
	if ((dynamicOffsets.length as int32) != bindGroups[g].dynamicCount) {
		const expected = bindGroups[g].dynamicCount;
		const got = dynamicOffsets.length;
		stop(`setBindGroup(${index}) takes ${expected} dynamic offsets, got ${got}`);
	}
	for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
		if (dynamicOffsets[i] % (uniformAlignment as uint32) != 0) {
			stop(`dynamic offset ${dynamicOffsets[i]} is not a multiple of ${uniformAlignment}`);
		}
		wgDynamicOffset(i, dynamicOffsets[i]);
	}
	wgSetBindGroup(index, bindGroups[g].native, bindGroups[g].dynamicCount);
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
	if (boundPipeline == 0) { stop("draw without setPipeline"); }
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
	if (boundPipeline == 0) { stop("drawIndexed without setPipeline"); }
	const strip = pipelines[pipelineIndex(boundPipeline)].stripIndexFormat;
	if (strip != 0 && strip != boundIndexFormat) {
		stop("an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format");
	}
	wgDrawIndexed(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
}

function encodedCopy(member: string): void {
	if (passActive) { stop(`${member} inside a render pass`); }
	if (!encoding) { stop(`${member} without createCommandEncoder`); }
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	encodedCopy(member);
	const index = bufferIndex(buffer.id);
	if (!has(buffers[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	encodedCopy(member);
	const index = textureIndex(info.texture.id);
	if (!has(textures[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	if (textures[index].swapchainView != 0) { stop(`${member}: the swapchain texture belongs to the platform`); }
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
	if (info.depth) { stop(`${member}: depth or stencil GPUTexture ${textures[index].id} is not ported to wgpu yet`); }
	return info;
}

function checkedBufferLayout(member: string, bytesPerPixel: int32, slot: int32, info: GPUTexelCopyBufferInfo, size: GPUExtent3D): int32 {
	if (info.offset % 4 != 0) { stop(`${member}.offset ${info.offset} is not a multiple of 4`); }
	return checkedTexelBufferLayout(member, bytesPerPixel, buffers[slot].size, info, size);
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedBufferCopy(source.id, buffers[from].size, sourceOffset, destination.id, buffers[to].size, destinationOffset, size);
	if (size == 0) { return; }
	wgCopyBufferToBuffer(buffers[from].native, sourceOffset, buffers[to].native, destinationOffset, size);
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	const info = colorFormatOf(to, "copyBufferToTexture destination");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const bytesPerRow = checkedBufferLayout("copyBufferToTexture source", info.bytesPerPixel, from, source, size);
	wgCopyBufferToTexture(
		buffers[from].native,
		source.offset,
		bytesPerRow,
		source.rowsPerImage == 0 ? size.height : source.rowsPerImage,
		textures[to].native,
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
	const info = colorFormatOf(from, "copyTextureToBuffer source");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const bytesPerRow = checkedBufferLayout("copyTextureToBuffer destination", info.bytesPerPixel, to, destination, size);
	wgCopyTextureToBuffer(
		textures[from].native,
		source.mipLevel,
		source.origin.x,
		source.origin.y,
		source.origin.z,
		buffers[to].native,
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
	const fromFormat: string = textures[from].format;
	const toFormat: string = textures[to].format;
	if (fromFormat != toFormat) { stop(`copyTextureToTexture between formats '${fromFormat}' and '${toFormat}'`); }
	if (textures[from].volume != textures[to].volume) { stop("copyTextureToTexture between a 3d and a 2d GPUTexture"); }
	copyRegion("copyTextureToTexture source", source, from, size);
	copyRegion("copyTextureToTexture destination", destination, to, size);
	const mipWidth = Math.max(1, textures[from].width >> source.mipLevel);
	const mipHeight = Math.max(1, textures[from].height >> source.mipLevel);
	if (formatInfo(textures[from].format, "texture format").depth && (size.width != mipWidth || size.height != mipHeight)) {
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
		textures[from].native,
		source.mipLevel,
		source.origin.x,
		source.origin.y,
		source.origin.z,
		textures[to].native,
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
	return new Array(0);
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	stop("writeMappedRange is not ported to wgpu: it needs mapAsync");
}

export function unmap(buffer: GPUBuffer): void {
	stop("unmap is not ported to wgpu: it needs mapAsync");
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	stop("createComputePipeline is not ported to wgpu yet");
	return { id: 0 };
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	stop("beginComputePass is not ported to wgpu yet");
	return { id: 0 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void { stop("setPipeline on a compute pass is not ported to wgpu yet"); }

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	stop("setBindGroup on a compute pass is not ported to wgpu yet");
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void { stop("dispatchWorkgroups is not ported to wgpu yet"); }

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	stop("dispatchWorkgroupsIndirect is not ported to wgpu yet");
}

export function endComputePass(): void { stop("end on a compute pass is not ported to wgpu yet"); }

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	stop("createQuerySet is not ported to wgpu yet");
	return { id: 0 };
}

export function destroyQuerySet(querySet: GPUQuerySet): void { stop("destroy on a GPUQuerySet is not ported to wgpu yet"); }

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	stop("resolveQuerySet is not ported to wgpu yet");
}

export function beginOcclusionQuery(queryIndex: int32): void { stop("beginOcclusionQuery is not ported to wgpu yet"); }
export function endOcclusionQuery(): void { stop("endOcclusionQuery is not ported to wgpu yet"); }

export function limits(): GPUSupportedLimits {
	stop("limits is not ported to wgpu yet");
	return {};
}

export function features(): GPUSupportedFeatures {
	stop("features is not ported to wgpu yet");
	return { bits: 0 };
}

export function pushDebugGroup(label: string): void { stop("pushDebugGroup is not ported to wgpu yet"); }
export function popDebugGroup(): void { stop("popDebugGroup is not ported to wgpu yet"); }
export function insertDebugMarker(label: string): void { stop("insertDebugMarker is not ported to wgpu yet"); }
