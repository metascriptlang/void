import { Pool, allocate, alive, live, liveIds, newPool, release, reset, slotIndex, store } from "../pool.ms";
import {
	BindingKind,
	DUMMY_SAMPLER_BINDING,
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
	GPUCommandBuffer,
	GPUCommandEncoder,
	GPUComputePassDescriptor,
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUComputePipelineDescriptor,
	GPUDevice,
	GPUExtent3D,
	GPUIndexFormat,
	GPULiveCounts,
	GPUMapMode,
	GPUPassTimestampWrites,
	GPUPrimitiveState,
	GPUQuerySet,
	GPUQuerySetDescriptor,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderBinding,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUStencilFaceState,
	GPUSupportedFeatures,
	GPUSupportedLimits,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	bindingKind,
	checkedBufferCopy,
	checkedCubeView,
	checkedDepthSlice,
	checkedDepthTexelCopy,
	checkedDispatch,
	checkedDispatchIndirect,
	checkedIntegerTexturePairs,
	checkedMapAsync,
	checkedMappedRange,
	checkedNoDepthSlice,
	checkedPassExtent,
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
	checkedVisibility,
	checkedWriteBuffer,
	featureBit,
	firstInstanceRefusal,
	linearFilter,
	vertexOffsetRefusal,
} from "../types.ms";
import {
	addressesBinding,
	checkedBindGroupSet,
	checkedBindingGroup,
	checkedComputeModule,
	checkedComputePipeline,
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
	occlusionQueryIndex,
	occlusionSetId,
	passSerial,
} from "../validate.ms";
import { dummyCopyBytes, dummyZeroBytes } from "./dummy.h";

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
const STORAGE_OFFSET_ALIGNMENT = 256;
const MAX_ANISOTROPY = 16;
const MAX_TEXTURE_DIMENSION_2D = 16384;
const MAX_TEXTURE_DIMENSION_3D = 1024;
const MAX_TEXTURE_ARRAY_LAYERS = 1024;
const MAX_STAGE_TEXTURES = 16;
const MAX_STAGE_SAMPLERS = 12;
const MAX_STAGE_STORAGE_BUFFERS = 8;
const MAX_STAGE_STORAGE_TEXTURES = 4;
const MAX_UNIFORM_BUFFER_BINDING_SIZE: int64 = 65536;
const MAX_STORAGE_BUFFER_BINDING_SIZE: int64 = 134217728;
const MAX_WORKGROUP_SIZE_XY = 256;
const MAX_WORKGROUP_SIZE_Z = 64;
const MAX_WORKGROUP_INVOCATIONS = 256;
const MAX_DISPATCH_GROUPS = 65535;
const TIMESTAMP_STEP: uint64 = 1000;
const PRIMITIVE_LINE_STRIP = 2;
const PRIMITIVE_TRIANGLE_STRIP = 4;

enum ViewDimension {
	TwoD,
	TwoDArray,
	Cube,
	CubeArray,
	ThreeD,
}

enum QueryState {
	Unwritten,
	Open,
	Written,
}

struct FormatInfo {
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
	integer: boolean;
}

struct BufferSlot {
	id: uint32;
	size: int64;
	usage: int32;
	bytes: Vec<uint8>;
	writtenFrame: int64;
	writtenEnd: int64;
	inPlace: boolean;
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
	swapchainView: uint32;
}

struct ViewSlot {
	id: uint32;
	texture: uint32;
	dimension: ViewDimension;
	baseMip: int32;
	mipCount: int32;
	baseLayer: int32;
	layerCount: int32;
	attachable: boolean;
	volumeTarget: boolean;
	swapchain: boolean;
}

struct SamplerSlot {
	id: uint32;
}

struct ShaderBinding {
	binding: int32;
	kind: BindingKind;
	visibility: int32;
	size: int32;
	storageFormat: GPUTextureFormat;
}

struct ShaderSlot {
	id: uint32;
	compute: boolean;
	computeEntry: string;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	uniforms: ShaderBinding[8];
	uniformCount: int32;
	resources: ShaderBinding[24];
	resourceCount: int32;
}

struct PipelineSlot {
	id: uint32;
	label: string | null;
	shader: uint32;
	compute: boolean;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	primitive: int32;
	stripIndexSize: int32;
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
	entries: GPUBindGroupEntry[16];
	entryCount: int32;
	dynamicIndex: int32[16];
	dynamicCount: int32;
}

struct QuerySetSlot {
	id: uint32;
	timestamp: boolean;
	count: int32;
	state: Vec<QueryState>;
	usedPass: Vec<int64>;
	values: Vec<uint64>;
}

struct PassState {
	timestampSet: uint32;
	timestampEnd: int32;
	width: int32;
	height: int32;
}

struct ComputeState {
	timestampSet: uint32;
	timestampEnd: int32;
	pipeline: uint32;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[8];
}

struct BoundState {
	pipeline: uint32;
	vertexBuffers: uint32[2];
	indexSize: int32;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[8];
}

let frame: int64 = 0;
let ticks: uint64 = 0;
let pass: PassState = { width: 0 };
let computeBound: ComputeState = { pipeline: 0 };
let bound: BoundState = { pipeline: 0 };
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 };

let buffers: Pool<BufferSlot> = newPool<BufferSlot>("dummy", "GPUBuffer", "buffer", { id: 0 });
let textures: Pool<TextureSlot> = newPool<TextureSlot>("dummy", "GPUTexture", "texture", { id: 0 });
let views: Pool<ViewSlot> = newPool<ViewSlot>("dummy", "GPUTextureView", "view", { id: 0 });
let samplers: Pool<SamplerSlot> = newPool<SamplerSlot>("dummy", "GPUSampler", "sampler", { id: 0 });
let shaders: Pool<ShaderSlot> = newPool<ShaderSlot>("dummy", "GPUShaderModule", "shader module", { id: 0 });
let pipelines: Pool<PipelineSlot> = newPool<PipelineSlot>("dummy", "GPURenderPipeline", "render or compute pipeline", { id: 0 });
let layouts: Pool<LayoutSlot> = newPool<LayoutSlot>("dummy", "GPUBindGroupLayout", "bind group layout", { id: 0 });
let bindGroups: Pool<BindGroupSlot> = newPool<BindGroupSlot>("dummy", "GPUBindGroup", "bind group", { id: 0 });
let querySets: Pool<QuerySetSlot> = newPool<QuerySetSlot>("dummy", "GPUQuerySet", "query set", { id: 0 });

@noinline function stop(message: string): never {
	console.log(`webgpu dummy: ${message}`);
	unreachable;
}

@noinline function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu dummy: ${member} '${value}' is not supported`);
	unreachable;
}

@noinline function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu dummy: ${member} '${value}' is not supported`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function colorInfo(bytesPerPixel: int32, integer: boolean): FormatInfo {
	return { bytesPerPixel: bytesPerPixel, depth: false, stencil: false, integer: integer };
}

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => colorInfo(1, false),
		"rg8unorm" => colorInfo(2, false),
		"rgba8unorm" | "rgba8unorm-srgb" | "bgra8unorm" | "bgra8unorm-srgb" => colorInfo(4, false),
		"rgba8uint" | "rgba8sint" => colorInfo(4, true),
		"r16float" => colorInfo(2, false),
		"rg16float" => colorInfo(4, false),
		"rgba16float" => colorInfo(8, false),
		"rgba16uint" => colorInfo(8, true),
		"r32float" => colorInfo(4, false),
		"rg32float" => colorInfo(8, false),
		"rgba32float" => colorInfo(16, false),
		"rgba32uint" => colorInfo(16, true),
		"r32uint" => colorInfo(4, true),
		"rgb10a2unorm" | "rg11b10ufloat" => colorInfo(4, false),
		"depth16unorm" => ({ bytesPerPixel: 2, depth: true, stencil: false, integer: false }),
		"depth32float" => ({ bytesPerPixel: 4, depth: true, stencil: false, integer: false }),
		"depth24plus-stencil8" => ({ bytesPerPixel: 8, depth: true, stencil: true, integer: false }),
		_ => stopOnFormat(member, value),
	};
}

function compareFunction(compare: string, member: string): int32 {
	return match (compare) {
		"" | "never" | "less" | "equal" | "less-equal" | "greater" | "not-equal" | "greater-equal" | "always" => 0,
		_ => stopOnMember(member, compare),
	};
}

function blendFactor(factor: string, member: string): int32 {
	return match (factor) {
		"" | "zero" | "one" | "src" | "one-minus-src" | "src-alpha" | "one-minus-src-alpha" => 0,
		"dst" | "one-minus-dst" | "dst-alpha" | "one-minus-dst-alpha" | "src-alpha-saturated" => 0,
		"constant" | "one-minus-constant" => 0,
		_ => stopOnMember(member, factor),
	};
}

function blendOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "add" | "subtract" | "reverse-subtract" | "min" | "max" => 0,
		_ => stopOnMember(member, operation),
	};
}

function stencilOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "keep" | "zero" | "replace" | "invert" => 0,
		"increment-clamp" | "decrement-clamp" | "increment-wrap" | "decrement-wrap" => 0,
		_ => stopOnMember(member, operation),
	};
}

function vertexFormat(format: string): int32 {
	return match (format) {
		"uint8x2" | "uint8x4" | "sint8x2" | "sint8x4" | "unorm8x2" | "unorm8x4" | "snorm8x2" | "snorm8x4" => 0,
		"uint16x2" | "uint16x4" | "sint16x2" | "sint16x4" | "unorm16x2" | "unorm16x4" => 0,
		"snorm16x2" | "snorm16x4" | "float16x2" | "float16x4" => 0,
		"float32" | "float32x2" | "float32x3" | "float32x4" => 0,
		"sint32" | "sint32x2" | "sint32x3" | "sint32x4" | "uint32" | "uint32x2" | "uint32x3" | "uint32x4" => 0,
		_ => stopOnMember("vertex attribute format", format),
	};
}

function addressMode(mode: string, member: string): int32 {
	return match (mode) {
		"" | "clamp-to-edge" | "repeat" | "mirror-repeat" => 0,
		_ => stopOnMember(member, mode),
	};
}

function primitiveType(topology: string): int32 {
	return match (topology) {
		"point-list" => 0,
		"line-list" => 1,
		"line-strip" => PRIMITIVE_LINE_STRIP,
		"" | "triangle-list" => 3,
		"triangle-strip" => PRIMITIVE_TRIANGLE_STRIP,
		_ => stopOnMember("primitive.topology", topology),
	};
}

function indexSize(format: GPUIndexFormat): int32 {
	const value: string = format;
	return match (value) {
		"uint16" => 2,
		"uint32" => 4,
		_ => stopOnMember("setIndexBuffer indexFormat", value),
	};
}

function stripIndexSizeOf(state: GPUPrimitiveState): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return 0; }
	return indexSize(state.stripIndexFormat);
}

function loadOp(value: string, member: string): int32 {
	return match (value) {
		"clear" | "load" => 0,
		_ => stopOnMember(member, value),
	};
}

function storeOp(value: string, member: string): int32 {
	return match (value) {
		"store" | "discard" => 0,
		_ => stopOnMember(member, value),
	};
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

export function setup(environment: NativeEnvironment): GPUDevice {
	frame = 0;
	ticks = 0;
	pass = { width: 0 };
	computeBound = { pipeline: 0 };
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
	if (sampleCount != 1 && sampleCount != 4) { stopOnMember("NativeEnvironment.sampleCount", `${sampleCount}`); }
	return { format: environment.colorFormat, depthFormat: environment.depthFormat, sampleCount: sampleCount };
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
		swapchainView: viewId,
	});
	store(views, {
		id: viewId,
		texture: textureId,
		dimension: ViewDimension.TwoD,
		mipCount: 1,
		layerCount: 1,
		attachable: true,
		swapchain: true,
	});
	return textureId;
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
	for (const id of textures.liveIds()) {
		if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { counts.textures += 1; }
	}
	for (const id of views.liveIds()) {
		if (!views.slots[views.slotIndex(id)].swapchain) { counts.views += 1; }
	}
	counts.samplers = samplers.live();
	counts.shaderModules = shaders.live();
	counts.pipelines = pipelines.live();
	return counts;
}

export function bufferAlive(buffer: GPUBuffer): boolean { return buffers.alive(buffer.id); }
export function textureAlive(texture: GPUTexture): boolean { return textures.alive(texture.id); }
export function viewAlive(view: GPUTextureView): boolean { return views.alive(view.id); }
export function samplerAlive(sampler: GPUSampler): boolean { return samplers.alive(sampler.id); }

export function shutdown(): void {
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
	return { backend: "dummy", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocate(buffers);
	const usage = descriptor.usage;
	const inPlace = has(usage, GPUBufferUsage.MAP_READ as int32)
		|| has(usage, GPUBufferUsage.MAP_WRITE as int32)
		|| has(usage, GPUBufferUsage.STORAGE as int32)
		|| has(usage, GPUBufferUsage.QUERY_RESOLVE as int32);
	const slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		usage: usage,
		bytes: new Array(descriptor.size),
		writtenFrame: has(usage, GPUBufferUsage.COPY_DST as int32) ? -1 : -2,
		writtenEnd: 0,
		inPlace: inPlace,
	};
	store(buffers, slot);
	return { id: id };
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	buffers.slots[index] = { id: 0 };
	release(buffers, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers.slots[buffers.slotIndex(buffer.id)].size; }

function claimBufferWrite(index: int32, offset: int64, bytes: int64, member: string): void {
	const id = buffers.slots[index].id;
	if (buffers.slots[index].writtenFrame == -2) { stop(`GPUBuffer ${id} was created without COPY_DST`); }
	if (buffers.slots[index].mapMode != 0) { stop(`${member} on GPUBuffer ${id}, which is mapped`); }
	if (buffers.slots[index].inPlace) { return; }
	const fresh = buffers.slots[index].writtenFrame != frame;
	if (!fresh && offset < buffers.slots[index].writtenEnd) {
		stop(`${member} at ${offset} on GPUBuffer ${id} rewrites bytes this frame already wrote, up to ${buffers.slots[index].writtenEnd}`);
	}
	buffers.slots[index].writtenFrame = frame;
	buffers.slots[index].writtenEnd = offset + bytes;
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = buffers.slotIndex(buffer.id);
	checkedWriteBuffer(buffer.id, buffers.slots[index].size, offset, bytes);
	claimBufferWrite(index, offset, bytes, "writeBuffer");
	dummyCopyBytes(buffers.slots[index].bytes[0], offset, data[0], bytes);
}

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocate(textures);
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const mipLevels = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) { stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`); }
	const usage = descriptor.usage;
	if (has(usage, GPUTextureUsage.STORAGE_BINDING as int32) && (sampleCount != 1 || info.depth)) {
		stop("GPUTextureUsage.STORAGE_BINDING takes a single-sample colour texture");
	}
	const cube = !volume
		&& layers % 6 == 0
		&& width == height
		&& has(usage, GPUTextureUsage.TEXTURE_BINDING as int32)
		&& sampleCount == 1;
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
		swapchainView: 0,
	};
	store(textures, slot);
	return { id: id };
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textures.slotIndex(texture.id);
	if (textures.slots[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	textures.slots[index] = { id: 0 };
	release(textures, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat {
	return textures.slots[textures.slotIndex(texture.id)].format;
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textures.slotIndex(destination.texture.id);
	const id = textures.slots[index].id;
	if (!has(textures.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${id}, created without COPY_DST`);
	}
	if (textures.slots[index].sampleCount != 1) { stop(`writeTexture on GPUTexture ${id}, which is multisampled`); }
	const volume = textures.slots[index].volume;
	const mip = destination.mipLevel;
	const mips = textures.slots[index].mipLevels;
	const layers = textures.slots[index].layers;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, layers >> mip) : layers;
	checkedTexelWritePitch(
		textures.slots[index].width,
		textures.slots[index].height,
		mips,
		depth,
		formatInfo(textures.slots[index].format, "texture format").bytesPerPixel,
		(data.length as int64) * (sizeof T as int64),
		destination,
		layout,
		size,
	);
}

function viewDimensionOf(descriptor: GPUTextureViewDescriptor, t: int32): ViewDimension {
	const name = checkedViewDimension(
		descriptor.dimension,
		textures.slots[t].volume,
		textures.slots[t].layers,
		textures.slots[t].id,
	);
	return match (name) {
		"2d" => ViewDimension.TwoD,
		"2d-array" => ViewDimension.TwoDArray,
		"cube" => ViewDimension.Cube,
		"cube-array" => ViewDimension.CubeArray,
		"3d" => ViewDimension.ThreeD,
		_ => stopOnMember("GPUTextureViewDescriptor.dimension", name) as ViewDimension,
	};
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { return { id: textures.slots[t].swapchainView }; }
	const id = allocate(views);
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
	const cubic = dimension == ViewDimension.Cube || dimension == ViewDimension.CubeArray;
	if (cubic) { checkedCubeView(textures.slots[t].id, textures.slots[t].cube, baseLayer, layerCount); }
	const slot: ViewSlot = {
		id: id,
		texture: texture.id,
		dimension: dimension,
		baseMip: baseMip,
		mipCount: mipCount,
		baseLayer: baseLayer,
		layerCount: layerCount,
		attachable: mipCount == 1 && layerCount == 1 && !cubic,
		volumeTarget: textures.slots[t].volume && dimension == ViewDimension.ThreeD,
		swapchain: false,
	};
	store(views, slot);
	return { id: id };
}

export function destroyView(view: GPUTextureView): void {
	const index = views.slotIndex(view.id);
	if (views.slots[index].swapchain) { return; }
	views.slots[index] = { id: 0 };
	release(views, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views.slots[views.slotIndex(view.id)].texture }; }

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.width <= 0 || swapchain.height <= 0) {
		stop(`the swapchain size ${swapchain.width}x${swapchain.height} is not positive`);
	}
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
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter", "dummy");
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter", "dummy");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter", "dummy");
	let maxAnisotropy = descriptor.maxAnisotropy;
	if (maxAnisotropy < 1) { maxAnisotropy = 1; }
	if (maxAnisotropy > MAX_ANISOTROPY) { stopOnMember("GPUSamplerDescriptor.maxAnisotropy", `${maxAnisotropy}`); }
	checkedSamplerAnisotropy(maxAnisotropy, minLinear && magLinear && mipLinear);
	if (descriptor.lodMinClamp < 0) { stopOnMember("GPUSamplerDescriptor.lodMinClamp", `${descriptor.lodMinClamp}`); }
	checkedSamplerLod(descriptor.lodMinClamp, descriptor.lodMaxClamp);
	addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU");
	addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV");
	addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW");
	compareFunction(descriptor.compare, "GPUSamplerDescriptor.compare");
	store(samplers, { id: id });
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplers.slotIndex(sampler.id);
	samplers.slots[index] = { id: 0 };
	release(samplers, sampler.id);
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	checkedIntegerTexturePairs(descriptor);
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		checkedVisibility(descriptor.bindings[i], compute);
		const binding: ShaderBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName, "dummy"),
			visibility: descriptor.bindings[i].visibility,
			size: descriptor.bindings[i].size,
			storageFormat: descriptor.bindings[i].storageFormat,
		};
		bindingWritable(descriptor.bindings[i]);
		const group = descriptor.bindings[i].group;
		checkedBindingGroup(binding.binding, binding.kind, group);
		if (binding.kind == BindingKind.Uniform) {
			slot.uniforms[slot.uniformCount] = binding;
			slot.uniformCount += 1;
		} else if (!(binding.kind == BindingKind.Sampler && binding.binding == DUMMY_SAMPLER_BINDING)) {
			addResource(slot, binding);
		}
	}
	checkStageLimits(slot);
	if (compute) {
		slot.computeEntry = descriptor.computeEntryPoint == "" ? "main" : descriptor.computeEntryPoint;
	}
	slot.id = id;
	slot.compute = compute;
	slot.readsInstanceIndex = descriptor.readsInstanceIndex;
	slot.readsVertexIndex = descriptor.readsVertexIndex;
	store(shaders, slot);
	return { id: id };
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

function addResource(ref slot: ShaderSlot, resource: ShaderBinding): void {
	for (let r = 0; r < slot.resourceCount; r++) {
		if (slot.resources[r].binding == resource.binding && slot.resources[r].kind == resource.kind) { return; }
	}
	slot.resources[slot.resourceCount] = resource;
	slot.resourceCount += 1;
}

function checkStageLimits(slot: ShaderSlot): void {
	const stages: int32[] = [
		GPUShaderStage.VERTEX as int32,
		GPUShaderStage.FRAGMENT as int32,
		GPUShaderStage.COMPUTE as int32,
	];
	for (const stage of stages) {
		let sampled = 0;
		let samplerCount = 0;
		let storageBuffers = 0;
		let storageTextures = 0;
		for (let r = 0; r < slot.resourceCount; r++) {
			if (!has(slot.resources[r].visibility, stage)) { continue; }
			const kind = slot.resources[r].kind;
			if (kind == BindingKind.Texture) { sampled += 1; }
			if (kind == BindingKind.Sampler) { samplerCount += 1; }
			if (kind == BindingKind.StorageBuffer) { storageBuffers += 1; }
			if (kind == BindingKind.StorageTexture) { storageTextures += 1; }
		}
		checkStageLimit(stage, "textures", sampled, MAX_STAGE_TEXTURES);
		checkStageLimit(stage, "samplers", samplerCount, MAX_STAGE_SAMPLERS);
		checkStageLimit(stage, "storage buffers", storageBuffers, MAX_STAGE_STORAGE_BUFFERS);
		checkStageLimit(stage, "storage textures", storageTextures, MAX_STAGE_STORAGE_TEXTURES);
	}
}

function checkStageLimit(stage: int32, what: string, count: int32, limit: int32): void {
	if (count > limit) { stop(`shader stage ${stage} binds ${count} ${what}, over the limit of ${limit}`); }
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaders.slotIndex(module.id);
	shaders.slots[index] = { id: 0 };
	release(shaders, module.id);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocate(pipelines);
	const s = shaders.slotIndex(descriptor.vertex.module.id);
	checkedRenderModule(shaders.slots[s].compute);
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule in Void");
	}
	let slot: PipelineSlot = {
		id: 0,
		label: descriptor.label,
		shader: descriptor.vertex.module.id,
		readsInstanceIndex: shaders.slots[s].readsInstanceIndex,
		readsVertexIndex: shaders.slots[s].readsVertexIndex,
	};
	describeVertexLayout(descriptor, slot);
	describeColorTargets(descriptor);
	describeDepthStencil(descriptor);
	slot.primitive = primitiveType(descriptor.primitive.topology);
	slot.stripIndexSize = stripIndexSizeOf(descriptor.primitive);
	const cull: string = descriptor.primitive.cullMode;
	if (cull != "" && cull != "none" && cull != "front" && cull != "back") { stopOnMember("primitive.cullMode", cull); }
	const face: string = descriptor.primitive.frontFace;
	if (face != "" && face != "ccw" && face != "cw") { stopOnMember("primitive.frontFace", face); }
	const sampleCount = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	if (sampleCount != 1 && sampleCount != 4) { stopOnMember("multisample.count", `${sampleCount}`); }
	slot.id = id;
	store(pipelines, slot);
	return { id: id };
}

function describeVertexLayout(descriptor: GPURenderPipelineDescriptor, ref slot: PipelineSlot): void {
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stepMode: string = descriptor.vertex.buffers[b].stepMode;
		if (stepMode != "" && stepMode != "vertex" && stepMode != "instance") {
			stopOnMember("vertex.buffers stepMode", stepMode);
		}
		let used = false;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			vertexFormat(format);
			const location = descriptor.vertex.buffers[b].attributes[a].shaderLocation;
			if (location < 0 || location >= GPU_MAX_VERTEX_ATTRIBUTES) {
				stopOnMember("vertex attribute shaderLocation", `${location}`);
			}
			used = true;
		}
		const stride = descriptor.vertex.buffers[b].arrayStride;
		if (used || stride != 0) {
			if (stride <= 0) { stop(`vertex.buffers[${b}] has attributes and no arrayStride`); }
			slot.strides[b] = stride;
		}
	}
}

function describeColorTargets(descriptor: GPURenderPipelineDescriptor): void {
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") { continue; }
		const info = formatInfo(descriptor.fragment.targets[i].format, `fragment.targets[${i}].format`);
		if (info.depth) { stopOnMember(`fragment.targets[${i}].format`, format); }
		const enabled = descriptor.fragment.targets[i].blendEnabled;
		if (enabled && info.integer) { stop(`fragment.targets[${i}] blends ${format}, an integer format`); }
		const color: GPUBlendComponent = descriptor.fragment.targets[i].blend.color;
		const alpha: GPUBlendComponent = descriptor.fragment.targets[i].blend.alpha;
		blendFactor(color.srcFactor, "blend.color.srcFactor");
		blendFactor(color.dstFactor, "blend.color.dstFactor");
		blendOperation(color.operation, "blend.color.operation");
		blendFactor(alpha.srcFactor, "blend.alpha.srcFactor");
		blendFactor(alpha.dstFactor, "blend.alpha.dstFactor");
		blendOperation(alpha.operation, "blend.alpha.operation");
	}
}

function describeDepthStencil(descriptor: GPURenderPipelineDescriptor): void {
	const depthFormat: string = descriptor.depthStencil.format;
	if (depthFormat == "") { return; }
	const info = formatInfo(descriptor.depthStencil.format, "depthStencil.format");
	if (!info.depth) { stopOnMember("depthStencil.format", depthFormat); }
	compareFunction(descriptor.depthStencil.depthCompare, "depthStencil.depthCompare");
	const front: GPUStencilFaceState = descriptor.depthStencil.stencilFront;
	const back: GPUStencilFaceState = descriptor.depthStencil.stencilBack;
	stencilOperation(front.failOp, "depthStencil.stencilFront.failOp");
	stencilOperation(front.depthFailOp, "depthStencil.stencilFront.depthFailOp");
	stencilOperation(front.passOp, "depthStencil.stencilFront.passOp");
	compareFunction(front.compare, "depthStencil.stencilFront.compare");
	stencilOperation(back.failOp, "depthStencil.stencilBack.failOp");
	stencilOperation(back.depthFailOp, "depthStencil.stencilBack.depthFailOp");
	stencilOperation(back.passOp, "depthStencil.stencilBack.passOp");
	compareFunction(back.compare, "depthStencil.stencilBack.compare");
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	const index = pipelines.slotIndex(pipeline.id);
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
		if (slot.entries[i].buffer.id == 0 || uniformOf(shader, group, slot.entries[i].binding) < 0) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			const uniform = slot.entries[j].buffer.id != 0 && uniformOf(shader, group, slot.entries[j].binding) >= 0;
			if (uniform && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: id };
}

function uniformOf(shader: int32, group: int32, binding: int32): int32 {
	for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
		if (addressesBinding(group, binding, shaders.slots[shader].uniforms[u].binding, BindingKind.Uniform)) { return u; }
	}
	return -1;
}

function resourceOf(shader: int32, group: int32, binding: int32, kind: BindingKind): int32 {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		const resource = shaders.slots[shader].resources[r];
		if (resource.kind == kind && addressesBinding(group, binding, resource.binding, resource.kind)) { return r; }
	}
	return -1;
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = buffers.slotIndex(entry.buffer.id);
		const u = uniformOf(shader, group, entry.binding);
		if (u >= 0) {
			checkedUniformEntry(
				entry,
				has(buffers.slots[b].usage, GPUBufferUsage.UNIFORM as int32),
				buffers.slots[b].size,
				shaders.slots[shader].uniforms[u].size,
				UNIFORM_OFFSET_ALIGNMENT as int64,
			);
			return;
		}
		if (resourceOf(shader, group, entry.binding, BindingKind.StorageBuffer) >= 0) {
			checkedStorageEntry(
				entry,
				has(buffers.slots[b].usage, GPUBufferUsage.STORAGE as int32),
				buffers.slots[b].size,
				STORAGE_OFFSET_ALIGNMENT as int64,
				MAX_STORAGE_BUFFER_BINDING_SIZE,
			);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	if (entry.textureView.id != 0) {
		const v = views.slotIndex(entry.textureView.id);
		const t = textures.slotIndex(views.slots[v].texture);
		if (resourceOf(shader, group, entry.binding, BindingKind.Texture) >= 0) {
			const sampled = has(textures.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32);
			checkedSampledView(entry.binding, sampled);
			return;
		}
		const r = resourceOf(shader, group, entry.binding, BindingKind.StorageTexture);
		if (r >= 0) {
			const storage = has(textures.slots[t].usage, GPUTextureUsage.STORAGE_BINDING as int32);
			checkedStorageView(entry.binding, storage, views.slots[v].mipCount);
			const expected: string = shaders.slots[shader].resources[r].storageFormat;
			const actual: string = textures.slots[t].format;
			if (expected != "" && expected != actual) {
				stop(`bind group entry ${entry.binding}: the shader declares storage format '${expected}' and the view's texture is '${actual}'`);
			}
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplers.slotIndex(entry.sampler.id);
	if (resourceOf(shader, group, entry.binding, BindingKind.Sampler) >= 0) { return; }
	stop(`bind group ${group} entry ${entry.binding} (sampler) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroups.slotIndex(bindGroup.id);
	bindGroups.slots[index] = { id: 0 };
	release(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(submitted: GPUCommandBuffer): void {
	frame += 1;
}

export function beginRenderPass(passEncoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	const occlusionSet = descriptor.occlusionQuerySet.id;
	if (occlusionSet != 0) {
		checkedOcclusionSetKind(querySets.slots[querySets.slotIndex(occlusionSet)].timestamp);
	}
	pass = { width: 0 };
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = views.slotIndex(viewId);
		const t = textures.slotIndex(views.slots[v].texture);
		const color = !formatInfo(textures.slots[t].format, "texture format").depth;
		if (!color || !has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`);
		}
		checkedSingleSubresource(`colorAttachments[${i}].view`, views.slots[v].attachable);
		const slice = descriptor.colorAttachments[i].depthSlice;
		if (views.slots[v].volumeTarget) {
			const slices = Math.max(1, textures.slots[t].layers >> views.slots[v].baseMip);
			checkedDepthSlice(i, slice, slices, views.slots[v].baseMip, textures.slots[t].id);
		} else {
			checkedNoDepthSlice(i, slice);
		}
		passExtent(v);
		checkResolve(i, v, descriptor.colorAttachments[i].resolveTarget.id);
		loadOp(descriptor.colorAttachments[i].loadOp, `colorAttachments[${i}].loadOp`);
		storeOp(descriptor.colorAttachments[i].storeOp, `colorAttachments[${i}].storeOp`);
	}
	const depthView = descriptor.depthStencilAttachment.view.id;
	if (depthView != 0) {
		const v = views.slotIndex(depthView);
		const t = textures.slotIndex(views.slots[v].texture);
		const depth = formatInfo(textures.slots[t].format, "depth format").depth;
		if (!depth || !has(textures.slots[t].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
			stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT");
		}
		checkedSingleSubresource("depthStencilAttachment.view", views.slots[v].attachable);
		passExtent(v);
		loadOp(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp");
		storeOp(descriptor.depthStencilAttachment.depthStoreOp, "depthStencilAttachment.depthStoreOp");
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	const writes = descriptor.timestampWrites;
	pass.timestampSet = writes.querySet.id;
	pass.timestampEnd = writes.endOfPassWriteIndex;
	if (writes.querySet.id != 0 && writes.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	}
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

function checkResolve(attachment: int32, colorView: int32, resolveId: uint32): void {
	if (resolveId == 0) { return; }
	const colorTexture = textures.slotIndex(views.slots[colorView].texture);
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
	const single = textures.slots[resolve].sampleCount == 1;
	if (!single || !has(textures.slots[resolve].usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample color RENDER_ATTACHMENT`);
	}
}

export function endPass(): void {
	if (pass.timestampSet != 0 && pass.timestampEnd >= 0) { writeTimestamp(pass.timestampSet, pass.timestampEnd); }
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	if (pipelines.slots[pipelines.slotIndex(pipeline.id)].compute) {
		stop(`GPUPipeline ${pipeline.id} is a compute pipeline: setPipeline on a render pass takes a render pipeline`);
	}
	bound.pipeline = pipeline.id;
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) { stopOnMember("setVertexBuffer slot", `${slot}`); }
	buffers.slotIndex(buffer.id);
	bound.vertexBuffers[slot] = buffer.id;
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	buffers.slotIndex(buffer.id);
	bound.indexSize = indexSize(format);
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	bound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroups.slotIndex(bindGroup.id);
	checkedBindGroupSet(
		index,
		bindGroups.slots[g].group,
		bindGroups.slots[g].dynamicCount,
		dynamicOffsets,
		UNIFORM_OFFSET_ALIGNMENT,
	);
	for (let i = 0; i < bindGroups.slots[g].dynamicCount; i++) {
		bound.dynamicOffsets[i] = dynamicOffsets[i];
	}
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	checkedViewport(width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {}

export function setStencilReference(reference: uint32): void {}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush();
	checkDrawOffsets("draw", "firstVertex", firstVertex, firstInstance);
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
	checkDrawOffsets("drawIndexed", "baseVertex", baseVertex, firstInstance);
	const p = pipelines.slotIndex(bound.pipeline);
	const primitive = pipelines.slots[p].primitive;
	const strip = primitive == PRIMITIVE_LINE_STRIP || primitive == PRIMITIVE_TRIANGLE_STRIP;
	checkedStripDraw(strip, pipelines.slots[p].stripIndexSize == bound.indexSize);
}

function checkDrawOffsets(call: string, vertexMember: string, vertexOffset: int32, firstInstance: int32): void {
	if (vertexOffset == 0 && firstInstance == 0) { return; }
	const p = pipelines.slotIndex(bound.pipeline);
	const label = labelOf(pipelines.slots[p].label);
	if (firstInstance != 0 && pipelines.slots[p].readsInstanceIndex) { stop(firstInstanceRefusal(call, label, firstInstance)); }
	if (vertexOffset != 0 && pipelines.slots[p].readsVertexIndex) {
		stop(vertexOffsetRefusal(call, label, vertexMember, vertexOffset));
	}
}

function flush(): void {
	const p = pipelines.slotIndex(bound.pipeline);
	if (!shaders.alive(pipelines.slots[p].shader)) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines.slots[p].strides[slot] == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		buffers.slotIndex(bound.vertexBuffers[slot]);
	}
	const s = shaders.slotIndex(pipelines.slots[p].shader);
	checkBoundGroups(s, bound.bindGroups, bound.dynamicOffsets, "pipeline");
}

function entryOf(group: int32, binding: int32): int32 {
	for (let e = 0; e < bindGroups.slots[group].entryCount; e++) {
		if (bindGroups.slots[group].entries[e].binding == binding) { return e; }
	}
	return stopOnMember("bound bind group: missing entry for binding", `${binding}`);
}

function checkBoundGroups(s: int32, groups: uint32[2], dynamicOffsets: uint32[8], what: string): void {
	if (shaders.slots[s].uniformCount > 0) {
		if (groups[GPU_UNIFORM_GROUP] == 0) { stop(`the ${what} reads bind group 0, which is not set`); }
		const g = bindGroups.slotIndex(groups[GPU_UNIFORM_GROUP]);
		for (let u = 0; u < shaders.slots[s].uniformCount; u++) {
			const binding = shaders.slots[s].uniforms[u].binding;
			const e = entryOf(g, binding);
			const dynamic = dynamicOffsets[bindGroups.slots[g].dynamicIndex[e]] as int64;
			const offset = dynamic + bindGroups.slots[g].entries[e].offset;
			const b = buffers.slotIndex(bindGroups.slots[g].entries[e].buffer.id);
			if (offset + (shaders.slots[s].uniforms[u].size as int64) > buffers.slots[b].size) {
				stop(`uniform binding ${binding} at offset ${offset} overruns its buffer`);
			}
		}
	}
	if (shaders.slots[s].resourceCount > 0) {
		if (groups[GPU_RESOURCE_GROUP] == 0) { stop(`the ${what} reads bind group 1, which is not set`); }
		const g = bindGroups.slotIndex(groups[GPU_RESOURCE_GROUP]);
		for (let r = 0; r < shaders.slots[s].resourceCount; r++) {
			const e = entryOf(g, shaders.slots[s].resources[r].binding);
			const entry: GPUBindGroupEntry = bindGroups.slots[g].entries[e];
			if (entry.buffer.id != 0) { buffers.slotIndex(entry.buffer.id); }
			if (entry.textureView.id != 0) { textures.slotIndex(views.slots[views.slotIndex(entry.textureView.id)].texture); }
			if (entry.sampler.id != 0) { samplers.slotIndex(entry.sampler.id); }
		}
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers.slots[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	const index = textures.slotIndex(info.texture.id);
	if (!has(textures.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures.slots[index].swapchainView != 0) { return index; }
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

function texelCopyBytes(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): int32 {
	const format = formatInfo(textures.slots[index].format, "texture format");
	if (format.depth) {
		checkedDepthTexelCopy(
			member,
			textures.slots[index].id,
			textures.slots[index].format,
			format.stencil,
			writes,
			textures.slots[index].width,
			textures.slots[index].height,
			copy.mipLevel,
			size,
		);
	}
	return format.bytesPerPixel;
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedBufferCopy(source.id, buffers.slots[from].size, sourceOffset, destination.id, buffers.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	dummyCopyBytes(buffers.slots[to].bytes[0], destinationOffset, buffers.slots[from].bytes[sourceOffset], size);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination.buffer, "copyTextureToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const bytesPerPixel = texelCopyBytes(from, "copyTextureToBuffer source", false, source, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", bytesPerPixel, buffers.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const rowBytes = (size.width as int64) * (bytesPerPixel as int64);
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		for (let y = 0; y < size.height; y++) {
			const offset = destination.offset + imageBytes * (i as int64) + (bytesPerRow as int64) * (y as int64);
			dummyZeroBytes(buffers.slots[to].bytes[0], offset, rowBytes);
		}
	}
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const bytesPerPixel = texelCopyBytes(to, "copyBufferToTexture destination", true, destination, size);
	checkedTexelBufferLayout("copyBufferToTexture source", bytesPerPixel, buffers.slots[from].size, source, size);
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
		formatInfo(textures.slots[from].format, "texture format").depth,
		textures.slots[from].width,
		textures.slots[from].height,
	);
}

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	const index = buffers.slotIndex(buffer.id);
	const length = checkedMapAsync(
		buffer.id,
		buffers.slots[index].usage,
		buffers.slots[index].mapMode,
		buffers.slots[index].size,
		mode,
		offset,
		size,
	);
	buffers.slots[index].mapMode = mode;
	buffers.slots[index].mapOffset = offset;
	buffers.slots[index].mapSize = length;
}

function mappedRange(member: string, index: int32, mode: int32, offset: int64, size: int64): int64 {
	return checkedMappedRange(
		member,
		buffers.slots[index].id,
		buffers.slots[index].size,
		buffers.slots[index].mapMode,
		buffers.slots[index].mapOffset,
		buffers.slots[index].mapSize,
		mode,
		offset,
		size,
	);
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const index = buffers.slotIndex(buffer.id);
	const length = mappedRange("getMappedRange", index, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	if (length > 0) { dummyCopyBytes(bytes[0], 0, buffers.slots[index].bytes[offset], length); }
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = buffers.slotIndex(buffer.id);
	mappedRange("writeMappedRange", index, GPUMapMode.WRITE as int32, offset, bytes);
	dummyCopyBytes(buffers.slots[index].bytes[0], offset, data[0], bytes);
}

export function unmap(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	checkedUnmap(buffer.id, buffers.slots[index].mapMode);
	buffers.slots[index].mapMode = 0;
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const s = shaders.slotIndex(descriptor.compute.module.id);
	const entry = descriptor.compute.entryPoint == "" ? "main" : descriptor.compute.entryPoint;
	checkedComputeModule(shaders.slots[s].compute, entry, shaders.slots[s].computeEntry);
	const id = allocate(pipelines);
	const slot: PipelineSlot = { id: id, label: descriptor.label, shader: descriptor.compute.module.id, compute: true };
	store(pipelines, slot);
	return { id: id };
}

export function beginComputePass(passEncoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	checkTimestampWrites("GPUComputePassDescriptor.timestampWrites", descriptor.timestampWrites);
	const writes = descriptor.timestampWrites;
	computeBound = {
		timestampSet: writes.querySet.id,
		timestampEnd: writes.endOfPassWriteIndex,
	};
	if (writes.querySet.id != 0 && writes.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	}
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	checkedComputePipeline(pipeline.id, pipelines.slots[pipelines.slotIndex(pipeline.id)].compute);
	computeBound.pipeline = pipeline.id;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	computeBound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroups.slotIndex(bindGroup.id);
	checkedBindGroupSet(
		index,
		bindGroups.slots[g].group,
		bindGroups.slots[g].dynamicCount,
		dynamicOffsets,
		UNIFORM_OFFSET_ALIGNMENT,
	);
	for (let i = 0; i < bindGroups.slots[g].dynamicCount; i++) {
		computeBound.dynamicOffsets[i] = dynamicOffsets[i];
	}
}

function checkCompute(): void {
	const p = pipelines.slotIndex(computeBound.pipeline);
	const s = shaders.slotIndex(pipelines.slots[p].shader);
	checkBoundGroups(s, computeBound.bindGroups, computeBound.dynamicOffsets, "compute pipeline");
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	checkedDispatch(x, y, z, MAX_DISPATCH_GROUPS);
	checkCompute();
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = buffers.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, buffers.slots[b].usage, buffers.slots[b].size, offset);
	checkCompute();
}

export function endComputePass(): void {
	if (computeBound.timestampSet != 0 && computeBound.timestampEnd >= 0) {
		writeTimestamp(computeBound.timestampSet, computeBound.timestampEnd);
	}
	computeBound = { pipeline: 0 };
}

export function limits(): GPUSupportedLimits {
	return {
		maxTextureDimension1D: MAX_TEXTURE_DIMENSION_2D,
		maxTextureDimension2D: MAX_TEXTURE_DIMENSION_2D,
		maxTextureDimension3D: MAX_TEXTURE_DIMENSION_3D,
		maxTextureArrayLayers: MAX_TEXTURE_ARRAY_LAYERS,
		maxBindGroups: GPU_RESOURCE_GROUP + 1,
		maxSampledTexturesPerShaderStage: MAX_STAGE_TEXTURES,
		maxSamplersPerShaderStage: MAX_STAGE_SAMPLERS,
		maxStorageBuffersPerShaderStage: MAX_STAGE_STORAGE_BUFFERS,
		maxStorageTexturesPerShaderStage: MAX_STAGE_STORAGE_TEXTURES,
		maxUniformBuffersPerShaderStage: GPU_MAX_UNIFORM_BLOCKS,
		maxUniformBufferBindingSize: MAX_UNIFORM_BUFFER_BINDING_SIZE,
		maxStorageBufferBindingSize: MAX_STORAGE_BUFFER_BINDING_SIZE,
		maxVertexBuffers: GPU_MAX_VERTEX_BUFFERS,
		maxVertexAttributes: GPU_MAX_VERTEX_ATTRIBUTES,
		maxColorAttachments: GPU_MAX_COLOR_ATTACHMENTS,
		maxComputeWorkgroupSizeX: MAX_WORKGROUP_SIZE_XY,
		maxComputeWorkgroupSizeY: MAX_WORKGROUP_SIZE_XY,
		maxComputeWorkgroupSizeZ: MAX_WORKGROUP_SIZE_Z,
		maxComputeInvocationsPerWorkgroup: MAX_WORKGROUP_INVOCATIONS,
		maxComputeWorkgroupsPerDimension: MAX_DISPATCH_GROUPS,
		minUniformBufferOffsetAlignment: UNIFORM_OFFSET_ALIGNMENT,
		minStorageBufferOffsetAlignment: STORAGE_OFFSET_ALIGNMENT,
	};
}

export function features(): GPUSupportedFeatures {
	const bits = featureBit("timestamp-query")
		| featureBit("float32-filterable")
		| featureBit("float32-blendable")
		| featureBit("rg11b10ufloat-renderable");
	return { bits: bits };
}

export function pushDebugGroup(label: string): void {}

export function popDebugGroup(): void {}

export function insertDebugMarker(label: string): void {}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	if (kind != "timestamp" && kind != "occlusion") { stopOnMember("GPUQuerySetDescriptor.type", kind); }
	checkedQuerySetCount(descriptor.count);
	const id = allocate(querySets);
	const slot: QuerySetSlot = {
		id: id,
		timestamp: kind == "timestamp",
		count: descriptor.count,
		state: new Array(descriptor.count),
		usedPass: new Array(descriptor.count),
		values: new Array(descriptor.count),
	};
	store(querySets, slot);
	return { id: id };
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySets.slotIndex(querySet.id);
	querySets.slots[index] = { id: 0 };
	release(querySets, querySet.id);
}

function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySets.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets.slots[q].timestamp, querySets.slots[q].count);
}

function writeTimestamp(querySet: uint32, queryIndex: int32): void {
	const q = querySets.slotIndex(querySet);
	ticks += TIMESTAMP_STEP;
	querySets.slots[q].values[queryIndex] = ticks;
	querySets.slots[q].state[queryIndex] = QueryState.Written;
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
		if (state == QueryState.Unwritten) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QueryState.Open) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	dummyCopyBytes(buffers.slots[b].bytes[0], destinationOffset, querySets.slots[q].values[firstQuery], bytes);
}

export function beginOcclusionQuery(queryIndex: int32): void {
	const q = querySets.slotIndex(occlusionSetId());
	checkedOcclusionRange(queryIndex, querySets.slots[q].count);
	checkedOcclusionReuse(queryIndex, querySets.slots[q].usedPass[queryIndex]);
	querySets.slots[q].usedPass[queryIndex] = passSerial();
	querySets.slots[q].state[queryIndex] = QueryState.Open;
}

export function endOcclusionQuery(): void {
	const q = querySets.slotIndex(occlusionSetId());
	querySets.slots[q].values[occlusionQueryIndex()] = 0;
	querySets.slots[q].state[occlusionQueryIndex()] = QueryState.Written;
}
