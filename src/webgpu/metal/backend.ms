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
	GPUColorWrite,
	GPUCommandBuffer,
	GPUCommandEncoder,
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
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
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
	mtlSetFragmentBuffer,
	mtlSetFragmentSampler,
	mtlSetFragmentTexture,
	mtlSetPipeline,
	mtlSetScissorRect,
	mtlSetVertexBuffer,
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

const SLOT_SHIFT = 16;
const SLOT_MASK = 0xFFFF;
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
const ADDRESS_CLAMP_TO_EDGE = 0;
const ADDRESS_REPEAT = 2;
const ADDRESS_MIRROR_REPEAT = 3;
const INDEX_UINT16 = 0;
const INDEX_UINT32 = 1;
const LOAD_LOAD = 1;
const LOAD_CLEAR = 2;
const STORE_DONT_CARE = 0;
const STORE_STORE = 1;
const STORE_RESOLVE = 2;
const STORE_STORE_AND_RESOLVE = 3;
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

struct SlotQueue {
	free: Vec<int32>;
	generations: Vec<uint32>;
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
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "bgra8unorm", depthFormat: "depth32float", sampleCount: 1 };

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

function stopOnHandle(kind: string, id: uint32): int32 {
	console.log(`webgpu metal: ${kind} ${id} is not a live handle`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function allocateId(ref queue: SlotQueue): uint32 {
	let index: int32 = 0;
	if (queue.free.length > 0) {
		index = queue.free[queue.free.length - 1];
		queue.free.pop();
	} else {
		if (queue.generations.length == 0) { queue.generations.push(0); }
		index = queue.generations.length as int32;
		if (index > SLOT_MASK) { stop("a resource pool is exhausted (65535 live handles)"); }
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
		"float32" => VERTEX_FLOAT,
		"float32x2" => VERTEX_FLOAT2,
		"float32x3" => VERTEX_FLOAT3,
		"float32x4" => VERTEX_FLOAT4,
		"unorm8x4" => VERTEX_UCHAR4_NORMALIZED,
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
	const textureId = allocateId(textureQueue);
	const viewId = allocateId(viewQueue);
	textures.push({
		id: textureId,
		format: format,
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		natives: [NO_TEXTURE, NO_TEXTURE],
		swapchainView: viewId,
	});
	views.push({ id: viewId, texture: textureId, swapchain: true, swapchainTexture: NO_TEXTURE, swapchainResolve: NO_TEXTURE });
	return textureId;
}

export function shutdown(): void {
	if (pass.active) { stop("shutdown with a render pass still open"); }
	if (commandBuffer != null) {
		mtlCommit(commandBuffer);
		commandBuffer = NO_COMMAND_BUFFER;
	}
	mtlFrameSemaphoreWaitAll();
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
	buffers = [];
	textures = [];
	views = [];
	samplers = [];
	shaders = [];
	pipelines = [];
	layouts = [];
	bindGroups = [];
	mtlReleaseQueue(queue);
	mtlReleaseDevice(device);
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "metal", originTopLeft: true, depthZeroToOne: true };
}

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	const t = textureIndex(texture.id);
	return mtlTextureNative(textures[t].natives[textures[t].active]);
}

export function nativeQueue(): Ptr<void> { return mtlQueueNative(queue); }

// A CPU write waits for the oldest frame in flight as a pass does (sokol _sg_mtl_begin_pass):
// it lands in a copy the frame before last may still read.
function beginFrame(): void {
	if (commandBuffer != null) { return; }
	commandBuffer = mtlBeginCommandBuffer(queue);
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const usage = descriptor.usage;
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
	if (has(usage, GPUBufferUsage.MAP_READ as int32) || has(usage, GPUBufferUsage.MAP_WRITE as int32)) {
		stop("GPUBufferUsage MAP_READ and MAP_WRITE have no Metal path");
	}
	const native = mtlNewBuffer(device, descriptor.size, sharedStorage ? 1 : 0);
	if (native == null) { stop(`newBufferWithLength failed for ${labelOf(descriptor.label)}`); }
	const id = allocateId(bufferQueue);
	const slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		natives: [native, NO_BUFFER],
		active: 0,
		writtenFrame: has(usage, GPUBufferUsage.COPY_DST as int32) ? -1 : -2,
		writtenEnd: 0,
	};
	const index = slotOf(id);
	if (index < buffers.length) { buffers[index] = slot; } else { buffers.push(slot); }
	return { id: id };
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = bufferIndex(buffer.id);
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (buffers[index].natives[s] != null) { mtlReleaseBuffer(buffers[index].natives[s]); }
	}
	buffers[index] = { id: 0 };
	releaseId(bufferQueue, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers[bufferIndex(buffer.id)].size; }

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferIndex(buffer.id);
	if (offset < 0 || offset + bytes > buffers[index].size) {
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${buffer.id} of ${buffers[index].size}`);
	}
	if (buffers[index].writtenFrame == -2) { stop(`GPUBuffer ${buffer.id} was created without COPY_DST`); }
	beginFrame();
	if (buffers[index].writtenFrame != frame) {
		if (buffers[index].writtenFrame >= 0) { nextBufferCopy(index); }
		buffers[index].writtenFrame = frame;
		buffers[index].writtenEnd = 0;
	} else if (offset < buffers[index].writtenEnd) {
		stop(`writeBuffer at ${offset} on GPUBuffer ${buffer.id} rewrites bytes this frame already wrote, up to ${buffers[index].writtenEnd}`);
	}
	const native = buffers[index].natives[buffers[index].active];
	mtlWriteBuffer(native, offset, data[0], bytes, sharedStorage ? 0 : 1);
	buffers[index].writtenEnd = offset + bytes;
}

function nextBufferCopy(index: int32): void {
	const next = 1 - buffers[index].active;
	if (buffers[index].natives[next] == null) {
		buffers[index].natives[next] = mtlNewBuffer(device, buffers[index].size, sharedStorage ? 1 : 0);
		if (buffers[index].natives[next] == null) { stop(`newBufferWithLength failed for GPUBuffer ${buffers[index].id}`); }
	}
	buffers[index].active = next;
	bound.vertexDirty = true;
	bound.uniformsDirty = true;
}

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	const layers = descriptor.size.depthOrArrayLayers;
	if (width <= 0 || height <= 0) { stop("GPUTextureDescriptor.size needs a positive width and height"); }
	if (layers > 1) { stop("GPUTextureDescriptor.size.depthOrArrayLayers above 1 has no Void caller yet"); }
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
	const id = allocateId(textureQueue);
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
	const index = slotOf(id);
	if (index < textures.length) { textures[index] = slot; } else { textures.push(slot); }
	return { id: id };
}

function newTexture(width: int32, height: int32, pixel: int32, sampleCount: int32, attachment: boolean): Ptr<MtlTextureImpl> {
	return mtlNewTexture(device, width, height, pixel, sampleCount, attachment ? 1 : 0, sharedStorage ? 1 : 0);
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textureIndex(texture.id);
	if (textures[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	for (let s = 0; s < FRAMES_IN_FLIGHT; s++) {
		if (textures[index].natives[s] != null) { mtlReleaseTexture(textures[index].natives[s]); }
	}
	textures[index] = { id: 0 };
	releaseId(textureQueue, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat { return textures[textureIndex(texture.id)].format; }

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textureIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	const rowPitch = textureCopyPitch(index, bytes, layout, size);
	beginFrame();
	if (textures[index].writtenFrame == frame) {
		stop(`writeTexture twice in one frame on GPUTexture ${destination.texture.id} (sokol allows one update per frame)`);
	}
	if (textures[index].writtenFrame >= 0) { nextTextureCopy(index); }
	textures[index].writtenFrame = frame;
	const native = textures[index].natives[textures[index].active];
	mtlWriteTexture(native, data[0], layout.offset, rowPitch, textures[index].width, textures[index].height);
}

function nextTextureCopy(index: int32): void {
	const next = 1 - textures[index].active;
	if (textures[index].natives[next] == null) {
		const pixel = formatInfo(textures[index].format, "texture format").pixel;
		textures[index].natives[next] = newTexture(textures[index].width, textures[index].height, pixel, 1, false);
		if (textures[index].natives[next] == null) { stop(`newTextureWithDescriptor failed for GPUTexture ${textures[index].id}`); }
	}
	textures[index].active = next;
	bound.resourcesDirty = true;
}

function textureCopyPitch(index: int32, bytes: int64, layout: GPUTexelCopyBufferLayout, size: GPUExtent3D): int32 {
	const width = textures[index].width;
	const height = textures[index].height;
	if (!has(textures[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textures[index].id}, created without COPY_DST`);
	}
	if (size.width != width || size.height != height || size.depthOrArrayLayers > 1) {
		stop("writeTexture covers the whole texture on Metal, which moves it to its next copy (sokol _sg_mtl_update_image)");
	}
	const rowBytes = width * formatInfo(textures[index].format, "texture format").bytesPerPixel;
	const rowPitch = layout.bytesPerRow == 0 ? rowBytes : layout.bytesPerRow;
	if (rowPitch < rowBytes) { stop(`writeTexture bytesPerRow ${rowPitch} is below a row of ${rowBytes}`); }
	const needed = layout.offset + (rowPitch as int64) * ((height - 1) as int64) + (rowBytes as int64);
	if (layout.offset < 0 || needed > bytes) {
		stop(`writeTexture needs ${needed} bytes of data and was given ${bytes}`);
	}
	return rowPitch;
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textureIndex(texture.id);
	if (textures[t].swapchainView != 0) { return { id: textures[t].swapchainView }; }
	const slot: ViewSlot = {
		id: allocateId(viewQueue),
		texture: texture.id,
		swapchain: false,
		swapchainTexture: NO_TEXTURE,
		swapchainResolve: NO_TEXTURE,
	};
	const index = slotOf(slot.id);
	if (index < views.length) { views[index] = slot; } else { views.push(slot); }
	return { id: slot.id };
}

export function destroyView(view: GPUTextureView): void {
	const index = viewIndex(view.id);
	if (views[index].swapchain) { return; }
	views[index] = { id: 0 };
	releaseId(viewQueue, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views[viewIndex(view.id)].texture }; }

function viewNative(v: int32): Ptr<MtlTextureImpl> {
	if (views[v].swapchain) { return views[v].swapchainTexture; }
	const t = textureIndex(views[v].texture);
	return textures[t].natives[textures[t].active];
}

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = viewIndex(textures[textureIndex(swapchainColor)].swapchainView);
	views[v].swapchainTexture = mtlTextureFrom(swapchain.renderView);
	views[v].swapchainResolve = swapchain.resolveView === null ? NO_TEXTURE : mtlTextureFrom(swapchain.resolveView);
	if (swapchainDepth != 0) {
		if (swapchain.depthStencilView === null) { stop("the canvas has a depth format and the native swapchain no depth view"); }
		updateSwapchainTexture(swapchainDepth, swapchain);
		const d = viewIndex(textures[textureIndex(swapchainDepth)].swapchainView);
		views[d].swapchainTexture = mtlTextureFrom(swapchain.depthStencilView);
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
	const native = mtlNewSampler(
		device,
		filterMode(descriptor.minFilter, "GPUSamplerDescriptor.minFilter"),
		filterMode(descriptor.magFilter, "GPUSamplerDescriptor.magFilter"),
		addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"),
		addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"),
	);
	if (native == null) { stop(`newSamplerStateWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	const id = allocateId(samplerQueue);
	const index = slotOf(id);
	const slot: SamplerSlot = { id: id, native: native };
	if (index < samplers.length) { samplers[index] = slot; } else { samplers.push(slot); }
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplerIndex(sampler.id);
	mtlReleaseSampler(samplers[index].native);
	samplers[index] = { id: 0 };
	releaseId(samplerQueue, sampler.id);
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
	slot.id = allocateId(shaderQueue);
	const index = slotOf(slot.id);
	if (index < shaders.length) { shaders[index] = slot; } else { shaders.push(slot); }
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
	const index = shaderIndex(module.id);
	mtlReleaseFunction(shaders[index].vertex);
	mtlReleaseFunction(shaders[index].fragment);
	mtlReleaseLibrary(shaders[index].vertexLibrary);
	mtlReleaseLibrary(shaders[index].fragmentLibrary);
	shaders[index] = { id: 0 };
	releaseId(shaderQueue, module.id);
}

function checkAttribute(shader: int32, location: int32): void {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		if (shaders[shader].attributes[i].location == location) { return; }
	}
	stopOnMember("vertex attribute shaderLocation (absent from the shader reflection)", `${location}`);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const s = shaderIndex(descriptor.vertex.module.id);
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule on Metal");
	}
	const topology: string = descriptor.primitive.topology;
	if (topology != "" && topology != "triangle-list") { stopOnMember("primitive.topology", topology); }
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
	slot.state = mtlNewPipeline(device, shaders[s].vertex, shaders[s].fragment, depthPixel, stencilPixel, sampleCount);
	if (slot.state == null) {
		const log: string = mtlErrorLog();
		stop(`newRenderPipelineStateWithDescriptor failed for ${labelOf(descriptor.label)}:\n${log}`);
	}
	slot.depth = mtlNewDepthState(
		device,
		depthFormat == "" ? COMPARE_ALWAYS : compareFunction(descriptor.depthStencil.depthCompare, "depthStencil.depthCompare"),
		depthFormat != "" && descriptor.depthStencil.depthWriteEnabled ? 1 : 0,
	);
	if (slot.depth == null) { stop(`newDepthStencilStateWithDescriptor failed for ${labelOf(descriptor.label)}`); }
	slot.cullMode = cullMode(descriptor.primitive.cullMode);
	slot.winding = winding(descriptor.primitive.frontFace);
	slot.id = allocateId(pipelineQueue);
	const index = slotOf(slot.id);
	if (index < pipelines.length) { pipelines[index] = slot; } else { pipelines.push(slot); }
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
	const index = pipelineIndex(pipeline.id);
	mtlReleasePipeline(pipelines[index].state);
	mtlReleaseDepthState(pipelines[index].depth);
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
		const id = allocateId(layoutQueue);
		const slot: LayoutSlot = { id: id, pipeline: pipeline.id, group: index };
		const l = slotOf(id);
		if (l < layouts.length) { layouts[l] = slot; } else { layouts.push(slot); }
		pipelines[p].layouts[index] = id;
	}
	return { id: pipelines[p].layouts[index] };
}

export function createBindGroup(descriptor: GPUBindGroupDescriptor): GPUBindGroup {
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
	slot.id = allocateId(bindGroupQueue);
	const index = slotOf(slot.id);
	if (index < bindGroups.length) { bindGroups[index] = slot; } else { bindGroups.push(slot); }
	return { id: slot.id };
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	const kind = entry.buffer.id != 0 ? BindingKind.Uniform :
		(entry.textureView.id != 0 ? BindingKind.Texture : BindingKind.Sampler);
	if (kind == BindingKind.Uniform) {
		bufferIndex(entry.buffer.id);
		for (let u = 0; u < shaders[shader].uniformCount; u++) {
			const binding = shaders[shader].uniforms[u];
			if (binding.binding == entry.binding) {
				if (entry.size != 0 && entry.size < (binding.size as int64)) {
					stop(`bind group entry ${entry.binding} size ${entry.size} is below its block of ${binding.size}`);
				}
				return;
			}
		}
	} else {
		if (kind == BindingKind.Texture) {
			const t = textureIndex(views[viewIndex(entry.textureView.id)].texture);
			if (!has(textures[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
				stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`);
			}
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
	if (pass.active) { stop("beginRenderPass with a render pass already open"); }
	pass = { active: true };
	beginFrame();
	mtlPassReset();
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = viewIndex(viewId);
		const t = textureIndex(views[v].texture);
		if (formatInfo(textures[t].format, "texture format").depth || !has(textures[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`);
		}
		passExtent(t);
		const resolve = resolveTexture(i, v, descriptor.colorAttachments[i].resolveTarget.id);
		if (views[v].swapchain) { pass.screen = true; }
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
		const v = viewIndex(depthView);
		const t = textureIndex(views[v].texture);
		const info = formatInfo(textures[t].format, "depth format");
		if (!info.depth || !has(textures[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
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
	mtlSetViewport(encoder, pass.width, pass.height);
	bound.appliedPipeline = 0;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
	return { id: 1 };
}

function passExtent(t: int32): void {
	if (pass.width == 0) {
		pass.width = textures[t].width;
		pass.height = textures[t].height;
	} else if (pass.width != textures[t].width || pass.height != textures[t].height) {
		stop("render pass attachments differ in size");
	}
}

function resolveTexture(attachment: int32, colorView: int32, resolveId: uint32): Ptr<MtlTextureImpl> {
	const colorTexture = textureIndex(views[colorView].texture);
	if (views[colorView].swapchain && resolveId == 0) { return views[colorView].swapchainResolve; }
	if (resolveId == 0) { return NO_TEXTURE; }
	const r = viewIndex(resolveId);
	const resolve = textureIndex(views[r].texture);
	if (textures[colorTexture].sampleCount == 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`);
	}
	if (textures[resolve].sampleCount != 1 || !has(textures[resolve].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
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
	bound.indexBuffer = buffer.id;
	bound.indexType = indexType(format);
	bound.indexBytes = bound.indexType == INDEX_UINT16 ? 2 : 4;
	bound.indexOffset = offset;
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

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush();
	mtlDraw(encoder, vertexCount, instanceCount, firstVertex, firstInstance);
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
	const b = bufferIndex(bound.indexBuffer);
	mtlDrawIndexed(
		encoder,
		buffers[b].natives[buffers[b].active],
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
	const p = pipelineIndex(bound.pipeline);
	if (shaders.length <= slotOf(pipelines[p].shader) || shaders[slotOf(pipelines[p].shader)].id != pipelines[p].shader) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	mtlSetPipeline(encoder, pipelines[p].state, pipelines[p].depth, pipelines[p].cullMode, pipelines[p].winding);
	bound.appliedPipeline = bound.pipeline;
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
}

function applyVertexBuffers(): void {
	const p = pipelineIndex(bound.pipeline);
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines[p].strides[slot] == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		const b = bufferIndex(bound.vertexBuffers[slot]);
		mtlSetVertexBuffer(encoder, buffers[b].natives[buffers[b].active], bound.vertexOffsets[slot], VERTEX_BUFFER_BASE + slot);
	}
	bound.vertexDirty = false;
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
	if (shaders[s].resourceCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	const g = bindGroupIndex(bound.bindGroups[GPU_RESOURCE_GROUP]);
	for (let r = 0; r < shaders[s].resourceCount; r++) {
		const binding: NativeBinding = shaders[s].resources[r];
		const e = entryOf(g, binding.binding);
		if (binding.kind == BindingKind.Texture) {
			const texture = viewNative(viewIndex(bindGroups[g].entries[e].textureView.id));
			if (binding.vertexStage) {
				mtlSetVertexTexture(encoder, texture, binding.nativeSlot);
			} else {
				mtlSetFragmentTexture(encoder, texture, binding.nativeSlot);
			}
		} else {
			const sampler = samplers[samplerIndex(bindGroups[g].entries[e].sampler.id)].native;
			if (binding.vertexStage) {
				mtlSetVertexSampler(encoder, sampler, binding.nativeSlot);
			} else {
				mtlSetFragmentSampler(encoder, sampler, binding.nativeSlot);
			}
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
		const e = entryOf(g, shaders[s].uniforms[u].binding);
		const offset = bound.dynamicOffsets[bindGroups[g].dynamicIndex[e]] as int64;
		const b = bufferIndex(bindGroups[g].entries[e].buffer.id);
		if (offset + (shaders[s].uniforms[u].size as int64) > buffers[b].size) {
			stop(`uniform binding ${shaders[s].uniforms[u].binding} at offset ${offset} overruns its buffer`);
		}
		const native = buffers[b].natives[buffers[b].active];
		if (shaders[s].uniforms[u].vertexStage) {
			mtlSetVertexBuffer(encoder, native, offset, shaders[s].uniforms[u].nativeSlot);
		} else {
			mtlSetFragmentBuffer(encoder, native, offset, shaders[s].uniforms[u].nativeSlot);
		}
	}
}
