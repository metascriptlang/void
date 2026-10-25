import {
	TextureRecord,
	ViewRecord,
	bindGroupRecords,
	bufferRecords,
	layoutRecords,
	pipelineRecords,
	put,
	querySetRecords,
	samplerRecords,
	shaderRecords,
	slotIndex,
	textureRecords,
	vacate,
	viewRecords,
} from "../pool.ms";
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
	GPUBlendComponent,
	GPUBuffer,
	GPUBufferDescriptor,
	GPUBufferUsage,
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
	checkedDepthTexelCopy,
	checkedDispatchIndirect,
	checkedMapAsync,
	checkedMappedRange,
	checkedResolveQuerySet,
	checkedTexelBufferLayout,
	checkedTexelWritePitch,
	checkedTextureToTextureCopy,
	checkedTimestampWrites,
	checkedUnmap,
	checkedWriteBuffer,
	featureBit,
	firstInstanceRefusal,
	linearFilter,
	vertexOffsetRefusal,
	labelOf,
} from "../types.ms";
import {
	cachedCanvas,
	currentFrame,
	checkedCopyRegion,
	entryOf,
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
	bytes: Vec<uint8>;
	writtenFrame: int64;
	writtenEnd: int64;
	inPlace: boolean;
	mapMode: int32;
	mapOffset: int64;
	mapSize: int64;
}

struct ShaderBinding {
	binding: int32;
	kind: BindingKind;
	visibility: int32;
	size: int32;
	storageFormat: GPUTextureFormat;
}

struct ShaderSlot {
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
	label: string | null;
	shader: uint32;
	compute: boolean;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	primitive: int32;
	stripIndexSize: int32;
	strides: int32[2];
}

struct BindGroupSlot {
	group: int32;
	entries: GPUBindGroupEntry[16];
	entryCount: int32;
	dynamicIndex: int32[16];
	dynamicCount: int32;
}

struct QuerySetSlot {
	timestamp: boolean;
	count: int32;
	state: Vec<QueryState>;
	usedPass: Vec<int64>;
	values: Vec<uint64>;
}

struct PassState {
	timestampSet: uint32;
	timestampEnd: int32;
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

let ticks: uint64 = 0;
let pass: PassState = { timestampSet: 0 };
let computeBound: ComputeState = { pipeline: 0 };
let bound: BoundState = { pipeline: 0 };
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;

export const BACKEND = "dummy";

let buffers: Vec<BufferSlot> = [{}];
let shaders: Vec<ShaderSlot> = [{}];
let pipelines: Vec<PipelineSlot> = [{}];
let bindGroups: Vec<BindGroupSlot> = [{}];
let querySets: Vec<QuerySetSlot> = [{}];

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

export function setup(environment: NativeEnvironment): GPUDevice {
	ticks = 0;
	pass = { timestampSet: 0 };
	computeBound = { pipeline: 0 };
	bound = { pipeline: 0 };
	const sampleCount = cachedCanvas().sampleCount;
	if (sampleCount != 1 && sampleCount != 4) { stopOnMember("NativeEnvironment.sampleCount", `${sampleCount}`); }
	return { id: 1, queue: { id: 1 } };
}

export function adoptSwapchain(color: uint32, depth: uint32): void {
	swapchainColor = color;
	swapchainDepth = depth;
	formatInfo(cachedCanvas().format, "NativeEnvironment.colorFormat");
	if (depth != 0) { formatInfo(cachedCanvas().depthFormat, "NativeEnvironment.depthFormat"); }
}

export function formatRenderable(format: GPUTextureFormat): boolean {
	formatInfo(format, "formatRenderable format");
	return true;
}

export function shutdown(): void {}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "dummy", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(id: uint32, descriptor: GPUBufferDescriptor): void {
	const usage = descriptor.usage;
	const inPlace = has(usage, GPUBufferUsage.MAP_READ as int32)
		|| has(usage, GPUBufferUsage.MAP_WRITE as int32)
		|| has(usage, GPUBufferUsage.STORAGE as int32)
		|| has(usage, GPUBufferUsage.QUERY_RESOLVE as int32);
	const slot: BufferSlot = {
		bytes: new Array(descriptor.size),
		writtenFrame: has(usage, GPUBufferUsage.COPY_DST as int32) ? -1 : -2,
		writtenEnd: 0,
		inPlace: inPlace,
	};
	put(buffers, id, slot);
}

export function destroyBuffer(buffer: GPUBuffer): void {
	vacate(buffers, buffer.id);
}

function claimBufferWrite(index: int32, offset: int64, bytes: int64, member: string): void {
	const id = bufferRecords.slots[index].id;
	if (buffers[index].writtenFrame == -2) { stop(`GPUBuffer ${id} was created without COPY_DST`); }
	if (buffers[index].mapMode != 0) { stop(`${member} on GPUBuffer ${id}, which is mapped`); }
	if (buffers[index].inPlace) { return; }
	const fresh = buffers[index].writtenFrame != currentFrame();
	if (!fresh && offset < buffers[index].writtenEnd) {
		stop(`${member} at ${offset} on GPUBuffer ${id} rewrites bytes this frame already wrote, up to ${buffers[index].writtenEnd}`);
	}
	buffers[index].writtenFrame = currentFrame();
	buffers[index].writtenEnd = offset + bytes;
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferRecords.slotIndex(buffer.id);
	checkedWriteBuffer(buffer.id, bufferRecords.slots[index].size, offset, bytes);
	claimBufferWrite(index, offset, bytes, "writeBuffer");
	dummyCopyBytes(buffers[index].bytes[0], offset, data[0], bytes);
}

export function createTexture(texture: TextureRecord, descriptor: GPUTextureDescriptor): void {
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const sampleCount = texture.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) { stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`); }
	if (has(texture.usage, GPUTextureUsage.STORAGE_BINDING as int32) && (sampleCount != 1 || info.depth)) {
		stop("GPUTextureUsage.STORAGE_BINDING takes a single-sample colour texture");
	}
}

export function destroyTexture(texture: GPUTexture): void {}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textureRecords.slotIndex(destination.texture.id);
	const id = textureRecords.slots[index].id;
	if (!has(textureRecords.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${id}, created without COPY_DST`);
	}
	if (textureRecords.slots[index].sampleCount != 1) { stop(`writeTexture on GPUTexture ${id}, which is multisampled`); }
	const volume = textureRecords.slots[index].volume;
	const mip = destination.mipLevel;
	const mips = textureRecords.slots[index].mipLevels;
	const layers = textureRecords.slots[index].layers;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, layers >> mip) : layers;
	checkedTexelWritePitch(
		textureRecords.slots[index].width,
		textureRecords.slots[index].height,
		mips,
		depth,
		formatInfo(textureRecords.slots[index].format, "texture format").bytesPerPixel,
		(data.length as int64) * (sizeof T as int64),
		destination,
		layout,
		size,
	);
}

function viewDimensionOf(name: string): ViewDimension {
	return match (name) {
		"2d" => ViewDimension.TwoD,
		"2d-array" => ViewDimension.TwoDArray,
		"cube" => ViewDimension.Cube,
		"cube-array" => ViewDimension.CubeArray,
		"3d" => ViewDimension.ThreeD,
		_ => stopOnMember("GPUTextureViewDescriptor.dimension", name) as ViewDimension,
	};
}

export function createView(view: ViewRecord, descriptor: GPUTextureViewDescriptor): void { viewDimensionOf(view.dimension); }

export function destroyView(view: GPUTextureView): void {}

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
	const t = textureRecords.slotIndex(id);
	textureRecords.slots[t].width = swapchain.width;
	textureRecords.slots[t].height = swapchain.height;
	textureRecords.slots[t].sampleCount = swapchain.sampleCount == 0 ? 1 : swapchain.sampleCount;
}

export function createSampler(id: uint32, descriptor: GPUSamplerDescriptor): void {
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter", "dummy");
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter", "dummy");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter", "dummy");
	addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU");
	addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV");
	addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW");
	compareFunction(descriptor.compare, "GPUSamplerDescriptor.compare");
}

export function destroySampler(sampler: GPUSampler): void {}

export function createShaderModule(id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	let slot: ShaderSlot = {};
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const binding: ShaderBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName, "dummy"),
			visibility: descriptor.bindings[i].visibility,
			size: descriptor.bindings[i].size,
			storageFormat: descriptor.bindings[i].storageFormat,
		};
		bindingWritable(descriptor.bindings[i]);
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
	slot.compute = compute;
	slot.readsInstanceIndex = descriptor.readsInstanceIndex;
	slot.readsVertexIndex = descriptor.readsVertexIndex;
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
	vacate(shaders, module.id);
}

export function createRenderPipeline(id: uint32, descriptor: GPURenderPipelineDescriptor): void {
	const s = shaderRecords.slotIndex(descriptor.vertex.module.id);
	checkedRenderModule(shaders[s].compute);
	let slot: PipelineSlot = {
		label: descriptor.label,
		shader: descriptor.vertex.module.id,
		readsInstanceIndex: shaders[s].readsInstanceIndex,
		readsVertexIndex: shaders[s].readsVertexIndex,
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
	put(pipelines, id, slot);
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
			const uniform = slot.entries[j].buffer.id != 0 && uniformOf(shader, group, slot.entries[j].binding) >= 0;
			if (uniform && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
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

function resourceOf(shader: int32, group: int32, binding: int32, kind: BindingKind): int32 {
	for (let r = 0; r < shaders[shader].resourceCount; r++) {
		const resource = shaders[shader].resources[r];
		if (resource.kind == kind && addressesBinding(group, binding, resource.binding, resource.kind)) { return r; }
	}
	return -1;
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = bufferRecords.slotIndex(entry.buffer.id);
		const u = uniformOf(shader, group, entry.binding);
		if (u >= 0) {
			checkedUniformEntry(
				entry,
				has(bufferRecords.slots[b].usage, GPUBufferUsage.UNIFORM as int32),
				bufferRecords.slots[b].size,
				shaders[shader].uniforms[u].size,
				UNIFORM_OFFSET_ALIGNMENT as int64,
			);
			return;
		}
		if (resourceOf(shader, group, entry.binding, BindingKind.StorageBuffer) >= 0) {
			checkedStorageEntry(
				entry,
				has(bufferRecords.slots[b].usage, GPUBufferUsage.STORAGE as int32),
				bufferRecords.slots[b].size,
				STORAGE_OFFSET_ALIGNMENT as int64,
				MAX_STORAGE_BUFFER_BINDING_SIZE,
			);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	if (entry.textureView.id != 0) {
		const v = viewRecords.slotIndex(entry.textureView.id);
		const t = textureRecords.slotIndex(viewRecords.slots[v].texture);
		if (resourceOf(shader, group, entry.binding, BindingKind.Texture) >= 0) {
			const sampled = has(textureRecords.slots[t].usage, GPUTextureUsage.TEXTURE_BINDING as int32);
			checkedSampledView(entry.binding, sampled);
			return;
		}
		const r = resourceOf(shader, group, entry.binding, BindingKind.StorageTexture);
		if (r >= 0) {
			const storage = has(textureRecords.slots[t].usage, GPUTextureUsage.STORAGE_BINDING as int32);
			checkedStorageView(entry.binding, storage, viewRecords.slots[v].mipCount);
			const expected: string = shaders[shader].resources[r].storageFormat;
			const actual: string = textureRecords.slots[t].format;
			if (expected != "" && expected != actual) {
				stop(`bind group entry ${entry.binding}: the shader declares storage format '${expected}' and the view's texture is '${actual}'`);
			}
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplerRecords.slotIndex(entry.sampler.id);
	if (resourceOf(shader, group, entry.binding, BindingKind.Sampler) >= 0) { return; }
	stop(`bind group ${group} entry ${entry.binding} (sampler) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	vacate(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(submitted: GPUCommandBuffer): void {
}

export function beginRenderPass(passEncoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor, extent: GPUExtent3D): GPURenderPassEncoder {
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	const occlusionSet = descriptor.occlusionQuerySet.id;
	if (occlusionSet != 0) {
		checkedOcclusionSetKind(querySets[querySetRecords.slotIndex(occlusionSet)].timestamp);
	}
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (descriptor.colorAttachments[i].view.id == 0) { continue; }
		loadOp(descriptor.colorAttachments[i].loadOp, `colorAttachments[${i}].loadOp`);
		storeOp(descriptor.colorAttachments[i].storeOp, `colorAttachments[${i}].storeOp`);
	}
	if (descriptor.depthStencilAttachment.view.id != 0) {
		loadOp(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp");
		storeOp(descriptor.depthStencilAttachment.depthStoreOp, "depthStencilAttachment.depthStoreOp");
	}
	const writes = descriptor.timestampWrites;
	pass = { timestampSet: writes.querySet.id, timestampEnd: writes.endOfPassWriteIndex };
	if (writes.querySet.id != 0 && writes.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(writes.querySet.id, writes.beginningOfPassWriteIndex);
	}
	return { id: 1 };
}

export function endPass(): void {
	if (pass.timestampSet != 0 && pass.timestampEnd >= 0) { writeTimestamp(pass.timestampSet, pass.timestampEnd); }
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	checkedRenderPassPipeline(pipeline.id, pipelines[pipelineRecords.slotIndex(pipeline.id)].compute);
	bound.pipeline = pipeline.id;
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) { stopOnMember("setVertexBuffer slot", `${slot}`); }
	bufferRecords.slotIndex(buffer.id);
	bound.vertexBuffers[slot] = buffer.id;
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	bufferRecords.slotIndex(buffer.id);
	bound.indexSize = indexSize(format);
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	bound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroupRecords.slotIndex(bindGroup.id);
	checkedBindGroupSet(
		index,
		bindGroups[g].group,
		bindGroups[g].dynamicCount,
		dynamicOffsets,
		UNIFORM_OFFSET_ALIGNMENT,
	);
	for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
		bound.dynamicOffsets[i] = dynamicOffsets[i];
	}
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
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
	const p = pipelineRecords.slotIndex(bound.pipeline);
	const primitive = pipelines[p].primitive;
	const strip = primitive == PRIMITIVE_LINE_STRIP || primitive == PRIMITIVE_TRIANGLE_STRIP;
	checkedStripDraw(strip, pipelines[p].stripIndexSize == bound.indexSize);
}

function checkDrawOffsets(call: string, vertexMember: string, vertexOffset: int32, firstInstance: int32): void {
	if (vertexOffset == 0 && firstInstance == 0) { return; }
	const p = pipelineRecords.slotIndex(bound.pipeline);
	const label = labelOf(pipelines[p].label);
	if (firstInstance != 0 && pipelines[p].readsInstanceIndex) { stop(firstInstanceRefusal(call, label, firstInstance)); }
	if (vertexOffset != 0 && pipelines[p].readsVertexIndex) {
		stop(vertexOffsetRefusal(call, label, vertexMember, vertexOffset));
	}
}

function flush(): void {
	const p = pipelineRecords.slotIndex(bound.pipeline);
	if (!shaderRecords.alive(pipelines[p].shader)) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		if (pipelines[p].strides[slot] == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		bufferRecords.slotIndex(bound.vertexBuffers[slot]);
	}
	const s = shaderRecords.slotIndex(pipelines[p].shader);
	checkBoundGroups(s, bound.bindGroups, bound.dynamicOffsets, "pipeline");
}


function checkBoundGroups(s: int32, groups: uint32[2], dynamicOffsets: uint32[8], what: string): void {
	if (shaders[s].uniformCount > 0) {
		if (groups[GPU_UNIFORM_GROUP] == 0) { stop(`the ${what} reads bind group 0, which is not set`); }
		const g = bindGroupRecords.slotIndex(groups[GPU_UNIFORM_GROUP]);
		for (let u = 0; u < shaders[s].uniformCount; u++) {
			const binding = shaders[s].uniforms[u].binding;
			const e = entryOf(bindGroups[g], binding);
			const dynamic = dynamicOffsets[bindGroups[g].dynamicIndex[e]] as int64;
			const offset = dynamic + bindGroups[g].entries[e].offset;
			const b = bufferRecords.slotIndex(bindGroups[g].entries[e].buffer.id);
			if (offset + (shaders[s].uniforms[u].size as int64) > bufferRecords.slots[b].size) {
				stop(`uniform binding ${binding} at offset ${offset} overruns its buffer`);
			}
		}
	}
	if (shaders[s].resourceCount > 0) {
		if (groups[GPU_RESOURCE_GROUP] == 0) { stop(`the ${what} reads bind group 1, which is not set`); }
		const g = bindGroupRecords.slotIndex(groups[GPU_RESOURCE_GROUP]);
		for (let r = 0; r < shaders[s].resourceCount; r++) {
			const e = entryOf(bindGroups[g], shaders[s].resources[r].binding);
			const entry: GPUBindGroupEntry = bindGroups[g].entries[e];
			if (entry.buffer.id != 0) { bufferRecords.slotIndex(entry.buffer.id); }
			if (entry.textureView.id != 0) { textureRecords.slotIndex(viewRecords.slots[viewRecords.slotIndex(entry.textureView.id)].texture); }
			if (entry.sampler.id != 0) { samplerRecords.slotIndex(entry.sampler.id); }
		}
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	const index = bufferRecords.slotIndex(buffer.id);
	if (!has(bufferRecords.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	const index = textureRecords.slotIndex(info.texture.id);
	if (!has(textureRecords.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textureRecords.slots[index].swapchainView != 0) { return index; }
	if (textureRecords.slots[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	return index;
}


function texelCopyBytes(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): int32 {
	const format = formatInfo(textureRecords.slots[index].format, "texture format");
	if (format.depth) {
		checkedDepthTexelCopy(
			member,
			textureRecords.slots[index].id,
			textureRecords.slots[index].format,
			format.stencil,
			writes,
			textureRecords.slots[index].width,
			textureRecords.slots[index].height,
			copy.mipLevel,
			size,
		);
	}
	return format.bytesPerPixel;
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination, "copyBufferToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedBufferCopy(source.id, bufferRecords.slots[from].size, sourceOffset, destination.id, bufferRecords.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	dummyCopyBytes(buffers[to].bytes[0], destinationOffset, buffers[from].bytes[sourceOffset], size);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableBuffer(destination.buffer, "copyTextureToBuffer destination", GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	checkedCopyRegion("copyTextureToBuffer source", textureRecords.slots[from], source, size);
	const bytesPerPixel = texelCopyBytes(from, "copyTextureToBuffer source", false, source, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", bytesPerPixel, bufferRecords.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const rowBytes = (size.width as int64) * (bytesPerPixel as int64);
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		for (let y = 0; y < size.height; y++) {
			const offset = destination.offset + imageBytes * (i as int64) + (bytesPerRow as int64) * (y as int64);
			dummyZeroBytes(buffers[to].bytes[0], offset, rowBytes);
		}
	}
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	checkedCopyRegion("copyBufferToTexture destination", textureRecords.slots[to], destination, size);
	const bytesPerPixel = texelCopyBytes(to, "copyBufferToTexture destination", true, destination, size);
	checkedTexelBufferLayout("copyBufferToTexture source", bytesPerPixel, bufferRecords.slots[from].size, source, size);
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyTextureToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
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
}

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	const index = bufferRecords.slotIndex(buffer.id);
	const length = checkedMapAsync(
		buffer.id,
		bufferRecords.slots[index].usage,
		buffers[index].mapMode,
		bufferRecords.slots[index].size,
		mode,
		offset,
		size,
	);
	buffers[index].mapMode = mode;
	buffers[index].mapOffset = offset;
	buffers[index].mapSize = length;
}

function mappedRange(member: string, index: int32, mode: int32, offset: int64, size: int64): int64 {
	return checkedMappedRange(
		member,
		bufferRecords.slots[index].id,
		bufferRecords.slots[index].size,
		buffers[index].mapMode,
		buffers[index].mapOffset,
		buffers[index].mapSize,
		mode,
		offset,
		size,
	);
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const index = bufferRecords.slotIndex(buffer.id);
	const length = mappedRange("getMappedRange", index, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	if (length > 0) { dummyCopyBytes(bytes[0], 0, buffers[index].bytes[offset], length); }
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferRecords.slotIndex(buffer.id);
	mappedRange("writeMappedRange", index, GPUMapMode.WRITE as int32, offset, bytes);
	dummyCopyBytes(buffers[index].bytes[0], offset, data[0], bytes);
}

export function unmap(buffer: GPUBuffer): void {
	const index = bufferRecords.slotIndex(buffer.id);
	checkedUnmap(buffer.id, buffers[index].mapMode);
	buffers[index].mapMode = 0;
}

export function createComputePipeline(id: uint32, descriptor: GPUComputePipelineDescriptor): void {
	const s = shaderRecords.slotIndex(descriptor.compute.module.id);
	const entry = descriptor.compute.entryPoint == "" ? "main" : descriptor.compute.entryPoint;
	checkedComputeModule(shaders[s].compute, entry, shaders[s].computeEntry);
	const slot: PipelineSlot = { label: descriptor.label, shader: descriptor.compute.module.id, compute: true };
	put(pipelines, id, slot);
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
	checkedComputePipeline(pipeline.id, pipelines[pipelineRecords.slotIndex(pipeline.id)].compute);
	computeBound.pipeline = pipeline.id;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	computeBound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroupRecords.slotIndex(bindGroup.id);
	checkedBindGroupSet(
		index,
		bindGroups[g].group,
		bindGroups[g].dynamicCount,
		dynamicOffsets,
		UNIFORM_OFFSET_ALIGNMENT,
	);
	for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
		computeBound.dynamicOffsets[i] = dynamicOffsets[i];
	}
}

function checkCompute(): void {
	const p = pipelineRecords.slotIndex(computeBound.pipeline);
	const s = shaderRecords.slotIndex(pipelines[p].shader);
	checkBoundGroups(s, computeBound.bindGroups, computeBound.dynamicOffsets, "compute pipeline");
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	checkCompute();
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = bufferRecords.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, bufferRecords.slots[b].usage, bufferRecords.slots[b].size, offset);
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

export function createQuerySet(id: uint32, descriptor: GPUQuerySetDescriptor): void {
	const kind: string = descriptor.type;
	const slot: QuerySetSlot = {
		timestamp: kind == "timestamp",
		count: descriptor.count,
		state: new Array(descriptor.count),
		usedPass: new Array(descriptor.count),
		values: new Array(descriptor.count),
	};
	put(querySets, id, slot);
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	vacate(querySets, querySet.id);
}

function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySetRecords.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets[q].timestamp, querySets[q].count);
}

function writeTimestamp(querySet: uint32, queryIndex: int32): void {
	const q = querySetRecords.slotIndex(querySet);
	ticks += TIMESTAMP_STEP;
	querySets[q].values[queryIndex] = ticks;
	querySets[q].state[queryIndex] = QueryState.Written;
}

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
	dummyCopyBytes(buffers[b].bytes[0], destinationOffset, querySets[q].values[firstQuery], bytes);
}

export function beginOcclusionQuery(queryIndex: int32): void {
	const q = querySetRecords.slotIndex(occlusionSetId());
	checkedOcclusionRange(queryIndex, querySets[q].count);
	checkedOcclusionReuse(queryIndex, querySets[q].usedPass[queryIndex]);
	querySets[q].usedPass[queryIndex] = passSerial();
	querySets[q].state[queryIndex] = QueryState.Open;
}

export function endOcclusionQuery(): void {
	const q = querySetRecords.slotIndex(occlusionSetId());
	querySets[q].values[occlusionQueryIndex()] = 0;
	querySets[q].state[occlusionQueryIndex()] = QueryState.Written;
}
