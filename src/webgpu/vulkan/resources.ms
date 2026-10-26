import {
	vulkanAdapterLimit,
	vulkanBarrierFlush,
	vulkanBarrierImage,
	vulkanBufferBind,
	vulkanBufferCreate,
	vulkanBufferDestroy,
	vulkanBufferRequirements,
	vulkanCompletedSerial,
	vulkanCopyBuffer,
	vulkanCopyBufferToImage,
	vulkanCopyImage,
	vulkanCopyImageToBuffer,
	vulkanError,
	vulkanFormatOptimalFeatures,
	vulkanImageBind,
	vulkanImageCreate,
	vulkanImageDestroy,
	vulkanImageRequirements,
	vulkanMappedRead,
	vulkanMappedWrite,
	vulkanMemoryAllocate,
	vulkanMemoryFree,
	vulkanMemoryHeapCount,
	vulkanMemoryHeapSize,
	vulkanMemoryMap,
	vulkanMemoryType,
	vulkanMemoryTypeCount,
	vulkanPipelineDestroy,
	vulkanQueueStream,
	vulkanRecordingOpen,
	vulkanRecordingSerial,
	vulkanSamplerCreate,
	vulkanSamplerDestroy,
	vulkanShaderModuleDestroy,
	vulkanSubmit,
	vulkanViewCreate,
	vulkanViewDestroy,
	vulkanWaitSerial,
} from "./vulkan.h";
import {
	DedicatedOwner,
	Dedication,
	MemoryAllocation,
	MemoryAllocator,
	MemoryDevice,
	MemoryError,
	MemoryKind,
	MemoryRequest,
	OpenedBlock,
	Tiling,
	memoryAllocate,
	memoryFree,
	memoryPropertiesOf,
} from "./memory";
import { DescriptorCache, closeDescriptors, finishDeallocations, newDescriptorCache } from "./descriptor";
import {
	ACCESS_TRANSFER_WRITE,
	ASPECT_DEPTH,
	ASPECT_STENCIL,
	FormatInfo,
	IMAGE_CREATE_CUBE_COMPATIBLE,
	IMAGE_TYPE_2D,
	IMAGE_TYPE_3D,
	LAYOUT_SHADER_READ_ONLY,
	LAYOUT_TRANSFER_DST,
	addressMode,
	bufferMemoryKind,
	bufferRest,
	bufferUsageFlags,
	compareOp,
	cubeCompatible,
	d24s8Format,
	depthStencilNative,
	filter,
	formatInfo,
	imageUsageFlags,
	rowLength,
	swapchainRest,
	textureRest,
	viewType,
} from "./conv";
import {
	BufferRest,
	STAGE_TRANSFER,
	StateTracker,
	TextureRest,
	acquireTexture,
	cleared,
	copyFromBuffer,
	copyFromTexture,
	endPass,
	initTexture,
	newTracker,
	writeToBuffer,
	writeToTexture,
} from "./tracker";
import {
	GPUBuffer,
	GPUBufferDescriptor,
	GPUBufferUsage,
	GPUExtent3D,
	GPUSamplerDescriptor,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTextureDescriptor,
	GPUTextureUsage,
	GPUTextureViewDescriptor,
	checkedDepthTexelCopy,
	checkedTexelBufferLayout,
	checkedTexelWritePitch,
	samplerMaxLod,
	stop,
} from "../types.ms";
import { clampedAnisotropy } from "../validate.ms";
import {
	TextureRecord,
	ViewRecord,
	bufferRecords,
	put,
	slotOf,
	textureRecords,
	vacate,
	viewRecords,
} from "../pool.ms";

@passC("-I../../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

export enum ResourceError {
	OutOfMemory,
	DeviceLost,
}

export const VULKAN_OK: int32 = 0;
const VULKAN_OUT_OF_MEMORY: int32 = 10;
const VULKAN_DEVICE_LOST: int32 = 11;
const LIMIT_NON_COHERENT_ATOM_SIZE: int32 = 22;
const LIMIT_MEMORY_ALLOCATION_COUNT: int32 = 23;
const UPLOAD_PAGE_SIZE: uint64 = 64 * 1024 * 1024;
const UPLOAD_ALIGNMENT: uint64 = 256;

export struct BufferNative {
	native: uint64;
	rest: BufferRest;
	memory: MemoryAllocation;
	lastUse: uint64;
}

export struct TextureNative {
	native: uint64;
	info: FormatInfo;
	rest: TextureRest;
	memory: MemoryAllocation;
}

export struct ViewNative {
	native: uint64;
	binding: uint64;
}

export enum RetiredKind {
	Buffer,
	Image,
	View,
	Sampler,
	Page,
	Shader,
	Pipeline,
}

struct UploadPage {
	native: uint64;
	memory: MemoryAllocation;
	next: uint64;
}

struct Retired {
	serial: uint64;
	kind: RetiredKind;
	native: uint64;
	memory: MemoryAllocation;
}

struct Staged {
	native: uint64;
	memory: MemoryAllocation;
	offset: uint64;
}

struct CanvasExtent {
	width: int32;
	height: int32;
}

export struct VulkanResources {
	memory: MemoryAllocator;
	tracker: StateTracker;
	queue: StateTracker;
	descriptors: DescriptorCache;
	buffers: Vec<BufferNative>;
	textures: Vec<TextureNative>;
	views: Vec<ViewNative>;
	samplers: Vec<uint64>;
	retired: Vec<Retired>;
	freePages: Vec<UploadPage>;
	page: UploadPage;
	depthStencil: int32;
	acquired: uint64;
	adopted: uint64;
	submitted: uint64;
	swapchainColor: uint32;
	swapchainDepth: uint32;
	swapchainDepthView: uint32;
	canvasMsaa: TextureNative;
	canvasMsaaView: uint64;
	canvasExtent: CanvasExtent;
}

export const NO_ALLOCATION: MemoryAllocation = {
	memory: 0,
	mapped: 0,
	offset: 0,
	size: 0,
	typeIndex: -1,
	group: -1,
	slot: -1,
	node: 0,
};
const NO_PAGE: UploadPage = { native: 0, memory: NO_ALLOCATION, next: 0 };
const NO_BLOCK: OpenedBlock = { memory: 0, mapped: 0 };
const NO_BUFFER: BufferNative = { native: 0, rest: { stages: 0, access: 0 }, memory: NO_ALLOCATION, lastUse: 0 };
const NO_TEXTURE: TextureNative = {
	native: 0,
	info: { native: 0, texelBytes: 0, aspect: 0, depth: false },
	rest: { stages: 0, access: 0, layout: 0, aspect: 0 },
	memory: NO_ALLOCATION,
};
const NO_VIEW: ViewNative = { native: 0, binding: 0 };

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function alignUp(value: uint64, alignment: uint64): uint64 {
	return (value + alignment - 1) / alignment * alignment;
}

@noinline export function stopOnVulkan(): never {
	stop(`vulkan: ${vulkanError()}`);
}

export function failure(code: int32): ResourceError {
	if (code == VULKAN_OUT_OF_MEMORY) { return ResourceError.OutOfMemory; }
	if (code == VULKAN_DEVICE_LOST) { return ResourceError.DeviceLost; }
	stopOnVulkan();
}

export function checked(code: int32): Result<void, ResourceError> {
	if (code != VULKAN_OK) { return Result.err(failure(code)); }
	return Result.ok(null);
}

function memoryDevice(): MemoryDevice {
	let device: MemoryDevice = {
		types: [],
		heapSizes: [],
		nonCoherentAtomSize: vulkanAdapterLimit(LIMIT_NON_COHERENT_ATOM_SIZE) as uint64,
		maxAllocationCount: vulkanAdapterLimit(LIMIT_MEMORY_ALLOCATION_COUNT) as uint32,
		openBlock: (typeIndex: int32, size: uint64, owner: DedicatedOwner, map: boolean): OpenedBlock => {
			let memory: uint64 = 0;
			const allocated = vulkanMemoryAllocate(typeIndex, size, owner.buffer, owner.image, memory);
			if (allocated == VULKAN_OUT_OF_MEMORY) { return NO_BLOCK; }
			if (allocated != VULKAN_OK) { stopOnVulkan(); }
			let mapped: uint64 = 0;
			if (map) {
				const mapping = vulkanMemoryMap(memory, mapped);
				if (mapping == VULKAN_OUT_OF_MEMORY) {
					vulkanMemoryFree(memory);
					return NO_BLOCK;
				}
				if (mapping != VULKAN_OK) { stopOnVulkan(); }
			}
			return { memory: memory, mapped: mapped };
		},
		closeBlock: (memory: uint64): void => { vulkanMemoryFree(memory); },
	};
	for (let i: int32 = 0; i < vulkanMemoryTypeCount(); i++) {
		let flags: uint32 = 0;
		let heap: int32 = 0;
		if (vulkanMemoryType(i, flags, heap) != VULKAN_OK) { stopOnVulkan(); }
		device.types.push({ properties: memoryPropertiesOf(flags), heap: heap });
	}
	for (let i: int32 = 0; i < vulkanMemoryHeapCount(); i++) { device.heapSizes.push(vulkanMemoryHeapSize(i)); }
	return device;
}

@noinline function refuseClosed(): never {
	stop("vulkan: a resource was made before requestDevice or after destroy");
}

function closedMemory(): MemoryDevice {
	return {
		types: [],
		heapSizes: [],
		nonCoherentAtomSize: 1,
		maxAllocationCount: 0,
		openBlock: (typeIndex: int32, size: uint64, owner: DedicatedOwner, map: boolean): OpenedBlock => { refuseClosed(); },
		closeBlock: (memory: uint64): void => { refuseClosed(); },
	};
}

export function closedResources(): VulkanResources {
	return resourcesOn(closedMemory(), 0);
}

export function openResources(): VulkanResources {
	return resourcesOn(memoryDevice(), depthStencilNative(vulkanFormatOptimalFeatures(d24s8Format())));
}

function resourcesOn(device: MemoryDevice, depthStencil: int32): VulkanResources {
	return {
		memory: MemoryAllocator.forDevice(device),
		tracker: newTracker(),
		queue: newTracker(),
		descriptors: newDescriptorCache(),
		buffers: [NO_BUFFER],
		textures: [NO_TEXTURE],
		views: [NO_VIEW],
		samplers: [0],
		retired: [],
		freePages: [],
		page: NO_PAGE,
		depthStencil: depthStencil,
		acquired: 0,
		adopted: 0,
		submitted: 0,
		swapchainColor: 0,
		swapchainDepth: 0,
		swapchainDepthView: 0,
		canvasMsaa: NO_TEXTURE,
		canvasMsaaView: 0,
		canvasExtent: { width: 0, height: 0 },
	};
}

function dedicationOf(code: int32): Dedication {
	return match (code) {
		0 => Dedication.None,
		1 => Dedication.Preferred,
		2 => Dedication.Required,
		_ => { stop(`vulkan: a memory requirement query answered dedication ${code}`); },
	};
}

function place(ref r: VulkanResources, request: MemoryRequest): Result<MemoryAllocation, ResourceError> {
	const placed = memoryAllocate(r.memory, request);
	if (placed.ok) { return Result.ok(placed.value); }
	return match (placed.error) {
		MemoryError.OutOfMemory | MemoryError.AllocationCountExceeded | MemoryError.BlockAllocationFailed =>
			Result.err(ResourceError.OutOfMemory),
		MemoryError.NoCompatibleMemory => {
			stop(`vulkan: no memory type in memoryTypeBits ${request.typeBits} is ${request.kind.toString()}`);
		},
		MemoryError.InvalidAllocation => { stop("vulkan: memoryAllocate answered InvalidAllocation"); },
	};
}

function freeMemory(ref r: VulkanResources, allocation: MemoryAllocation): void {
	const freed = memoryFree(r.memory, allocation);
	if (!freed.ok) {
		stop(`vulkan: freeing ${allocation.size} bytes at ${allocation.offset} answered ${freed.error.toString()}`);
	}
}

function placeBuffer(ref r: VulkanResources, native: uint64, kind: MemoryKind): Result<MemoryAllocation, ResourceError> {
	let size: uint64 = 0;
	let alignment: uint64 = 0;
	let typeBits: uint32 = 0;
	let dedication: int32 = 0;
	vulkanBufferRequirements(native, size, alignment, typeBits, dedication);
	const placed = try place(r, {
		size: size,
		alignment: alignment,
		typeBits: typeBits,
		kind: kind,
		tiling: Tiling.Linear,
		dedication: dedicationOf(dedication),
		owner: { buffer: native, image: 0 },
	});
	const bound = vulkanBufferBind(native, placed.memory, placed.offset);
	if (bound != VULKAN_OK) {
		freeMemory(r, placed);
		return Result.err(failure(bound));
	}
	return Result.ok(placed);
}

function placeImage(ref r: VulkanResources, native: uint64): Result<MemoryAllocation, ResourceError> {
	let size: uint64 = 0;
	let alignment: uint64 = 0;
	let typeBits: uint32 = 0;
	let dedication: int32 = 0;
	vulkanImageRequirements(native, size, alignment, typeBits, dedication);
	const placed = try place(r, {
		size: size,
		alignment: alignment,
		typeBits: typeBits,
		kind: MemoryKind.DeviceLocal,
		tiling: Tiling.Optimal,
		dedication: dedicationOf(dedication),
		owner: { buffer: 0, image: native },
	});
	const bound = vulkanImageBind(native, placed.memory, placed.offset);
	if (bound != VULKAN_OK) {
		freeMemory(r, placed);
		return Result.err(failure(bound));
	}
	return Result.ok(placed);
}

export function flush(ref r: VulkanResources): Result<void, ResourceError> {
	return flushTracker(r.tracker);
}

function flushTracker(ref t: StateTracker): Result<void, ResourceError> {
	if (!t.pending()) { return Result.ok(null); }
	for (const barrier of t.images) {
		const code = vulkanBarrierImage(
			barrier.image,
			barrier.aspect,
			barrier.sourceAccess,
			barrier.targetAccess,
			barrier.oldLayout,
			barrier.newLayout,
		);
		if (code != VULKAN_OK) {
			cleared(t);
			return Result.err(failure(code));
		}
	}
	const code = vulkanBarrierFlush(t.sourceStages, t.targetStages, t.sourceAccess, t.targetAccess);
	cleared(t);
	return checked(code);
}

function queued(ref r: VulkanResources, recorded: Result<void, ResourceError>): Result<void, ResourceError> {
	let flushed = recorded;
	if (recorded.ok) {
		endPass(r.queue);
		flushed = flushTracker(r.queue);
	} else {
		cleared(r.queue);
	}
	const switched = checked(vulkanQueueStream(0));
	if (!flushed.ok) { return flushed; }
	return switched;
}

export function createBuffer(ref r: VulkanResources, id: uint32, descriptor: GPUBufferDescriptor): Result<void, ResourceError> {
	const size = Math.max(descriptor.size, 4 as int64);
	let native: uint64 = 0;
	try checked(vulkanBufferCreate(size as uint64, bufferUsageFlags(descriptor.usage), native));
	const placed = placeBuffer(r, native, bufferMemoryKind(descriptor.usage));
	if (!placed.ok) {
		vulkanBufferDestroy(native);
		return Result.err(placed.error);
	}
	put(r.buffers, id, { native: native, rest: bufferRest(descriptor.usage), memory: placed.value, lastUse: 0 });
	return Result.ok(null);
}

function createImage(
	ref r: VulkanResources,
	info: FormatInfo,
	texture: TextureRecord,
): Result<TextureNative, ResourceError> {
	const volume = texture.volume;
	const layers = texture.layers;
	let native: uint64 = 0;
	try checked(vulkanImageCreate(
		volume ? IMAGE_TYPE_3D : IMAGE_TYPE_2D,
		info.native,
		texture.width as uint32,
		texture.height as uint32,
		(volume ? layers : 1) as uint32,
		texture.mipLevels as uint32,
		(volume ? 1 : layers) as uint32,
		texture.sampleCount as uint32,
		imageUsageFlags(texture.usage, info.depth),
		cubeCompatible(volume, texture.width, texture.height, layers, texture.sampleCount) ? IMAGE_CREATE_CUBE_COMPATIBLE : 0,
		native,
	));
	const placed = placeImage(r, native);
	if (!placed.ok) {
		vulkanImageDestroy(native);
		return Result.err(placed.error);
	}
	const rest = textureRest(texture.usage, info.aspect);
	let initialized = checked(vulkanQueueStream(1));
	if (initialized.ok) {
		initTexture(r.queue, native, rest);
		initialized = queued(r, Result.ok(null));
	}
	if (!initialized.ok) {
		freeMemory(r, placed.value);
		vulkanImageDestroy(native);
		return Result.err(initialized.error);
	}
	return Result.ok({ native: native, info: info, rest: rest, memory: placed.value });
}

export function createTexture(ref r: VulkanResources, texture: TextureRecord, descriptor: GPUTextureDescriptor): Result<void, ResourceError> {
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") {
		stop(`GPUTextureDescriptor.dimension '${dimension}' is not supported`);
	}
	const info = formatInfo(texture.format, r.depthStencil, "GPUTextureDescriptor.format");
	put(r.textures, texture.id, try createImage(r, info, texture));
	return Result.ok(null);
}

function createNativeView(
	texture: TextureNative,
	dimension: string,
	baseMip: int32,
	mipCount: int32,
	baseLayer: int32,
	layerCount: int32,
): Result<ViewNative, ResourceError> {
	let native: uint64 = 0;
	try checked(vulkanViewCreate(
		texture.native,
		viewType(dimension),
		texture.info.native,
		texture.info.aspect,
		baseMip as uint32,
		mipCount as uint32,
		baseLayer as uint32,
		layerCount as uint32,
		native,
	));
	let binding = native;
	if (texture.info.aspect == (ASPECT_DEPTH | ASPECT_STENCIL) && texture.rest.layout == LAYOUT_SHADER_READ_ONLY) {
		const depthOnly = checked(vulkanViewCreate(
			texture.native,
			viewType(dimension),
			texture.info.native,
			ASPECT_DEPTH,
			baseMip as uint32,
			mipCount as uint32,
			baseLayer as uint32,
			layerCount as uint32,
			binding,
		));
		if (!depthOnly.ok) {
			vulkanViewDestroy(native);
			return Result.err(depthOnly.error);
		}
	}
	return Result.ok({ native: native, binding: binding });
}

export function createView(ref r: VulkanResources, view: ViewRecord, descriptor: GPUTextureViewDescriptor): Result<void, ResourceError> {
	const texture = r.textures[textureRecords.slotIndex(view.texture)];
	const native = try createNativeView(texture, view.dimension, view.baseMip, view.mipCount, view.baseLayer, view.layerCount);
	put(r.views, view.id, native);
	return Result.ok(null);
}

export function adoptSwapchain(ref r: VulkanResources, color: uint32, depth: uint32): void {
	r.swapchainColor = color;
	r.swapchainDepth = depth;
	r.swapchainDepthView = depth == 0 ? 0 : textureRecords.record(depth).swapchainView;
	const colorRecord = textureRecords.record(color);
	put(r.textures, color, {
		native: 0,
		info: formatInfo(colorRecord.format, r.depthStencil, "NativeEnvironment.colorFormat"),
		rest: swapchainRest(),
		memory: NO_ALLOCATION,
	});
	put(r.views, colorRecord.swapchainView, NO_VIEW);
	if (depth == 0) { return; }
	const depthRecord = textureRecords.record(depth);
	const info = formatInfo(depthRecord.format, r.depthStencil, "NativeEnvironment.depthFormat");
	put(r.textures, depth, { native: 0, info: info, rest: textureRest(depthRecord.usage, info.aspect), memory: NO_ALLOCATION });
	put(r.views, depthRecord.swapchainView, NO_VIEW);
}

function retireCanvas(ref r: VulkanResources): void {
	if (r.swapchainDepth != 0) {
		const t = slotOf(r.swapchainDepth);
		const v = slotOf(r.swapchainDepthView);
		if (r.views[v].native != 0) { retire(r, RetiredKind.View, r.views[v].native, NO_ALLOCATION); }
		if (r.textures[t].native != 0) { retire(r, RetiredKind.Image, r.textures[t].native, r.textures[t].memory); }
		r.views[v] = NO_VIEW;
		r.textures[t].native = 0;
		r.textures[t].memory = NO_ALLOCATION;
	}
	if (r.canvasMsaa.native != 0) {
		retire(r, RetiredKind.View, r.canvasMsaaView, NO_ALLOCATION);
		retire(r, RetiredKind.Image, r.canvasMsaa.native, r.canvasMsaa.memory);
	}
	r.canvasMsaa = NO_TEXTURE;
	r.canvasMsaaView = 0;
	r.canvasExtent = { width: 0, height: 0 };
}

function sizeCanvas(ref r: VulkanResources, width: int32, height: int32): Result<void, ResourceError> {
	if (r.canvasExtent.width == width && r.canvasExtent.height == height) { return Result.ok(null); }
	retireCanvas(r);
	if (r.swapchainDepth != 0) {
		const record = textureRecords.record(r.swapchainDepth);
		const t = slotOf(r.swapchainDepth);
		const image = try createImage(r, r.textures[t].info, record);
		r.textures[t] = image;
		r.views[slotOf(r.swapchainDepthView)] = try createNativeView(image, "2d", 0, 1, 0, 1);
	}
	const color = textureRecords.record(r.swapchainColor);
	if (color.sampleCount > 1) {
		r.canvasMsaa = try createImage(r, r.textures[slotOf(r.swapchainColor)].info, color);
		r.canvasMsaaView = (try createNativeView(r.canvasMsaa, "2d", 0, 1, 0, 1)).native;
	}
	r.canvasExtent = { width: width, height: height };
	return Result.ok(null);
}

export function acquireSwapchain(ref r: VulkanResources, width: int32, height: int32, image: uint64, view: uint64): Result<void, ResourceError> {
	if (r.adopted == image) { return Result.ok(null); }
	const color = slotOf(r.swapchainColor);
	r.textures[color].native = image;
	r.views[slotOf(textureRecords.slots[color].swapchainView)] = { native: view, binding: view };
	r.acquired = image;
	r.adopted = image;
	return sizeCanvas(r, width, height);
}

export function presentSwapchain(ref r: VulkanResources, image: uint64): void {
	if (r.adopted != image) { acquireTexture(r.tracker, image, swapchainRest()); }
	r.adopted = 0;
}

export function settle(ref r: VulkanResources): void {
	endPass(r.tracker);
	if (r.acquired != 0) {
		acquireTexture(r.tracker, r.acquired, swapchainRest());
		r.acquired = 0;
	}
}

export function createSampler(ref r: VulkanResources, id: uint32, descriptor: GPUSamplerDescriptor): Result<void, ResourceError> {
	let native: uint64 = 0;
	try checked(vulkanSamplerCreate(
		filter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter"),
		filter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter"),
		filter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter"),
		addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"),
		addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"),
		addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW"),
		descriptor.lodMinClamp,
		samplerMaxLod(descriptor.lodMaxClamp),
		compareOp(descriptor.compare, "GPUSamplerDescriptor.compare"),
		clampedAnisotropy(descriptor.maxAnisotropy) as uint32,
		native,
	));
	put(r.samplers, id, native);
	return Result.ok(null);
}

export function retire(ref r: VulkanResources, kind: RetiredKind, native: uint64, memory: MemoryAllocation): void {
	r.retired.push({ serial: vulkanRecordingSerial(), kind: kind, native: native, memory: memory });
}

export function destroyBuffer(ref r: VulkanResources, id: uint32): void {
	const index = bufferRecords.slotIndex(id);
	retire(r, RetiredKind.Buffer, r.buffers[index].native, r.buffers[index].memory);
	vacate(r.buffers, id);
}

export function destroyTexture(ref r: VulkanResources, id: uint32): void {
	const index = textureRecords.slotIndex(id);
	retire(r, RetiredKind.Image, r.textures[index].native, r.textures[index].memory);
	vacate(r.textures, id);
}

export function destroyView(ref r: VulkanResources, id: uint32): void {
	const index = viewRecords.slotIndex(id);
	retire(r, RetiredKind.View, r.views[index].native, NO_ALLOCATION);
	if (r.views[index].binding != r.views[index].native) {
		retire(r, RetiredKind.View, r.views[index].binding, NO_ALLOCATION);
	}
	vacate(r.views, id);
}

export function destroySampler(ref r: VulkanResources, id: uint32): void {
	retire(r, RetiredKind.Sampler, r.samplers[slotOf(id)], NO_ALLOCATION);
	vacate(r.samplers, id);
}

function freeRetired(ref r: VulkanResources, retired: Retired): void {
	match (retired.kind) {
		RetiredKind.Buffer | RetiredKind.Page => vulkanBufferDestroy(retired.native),
		RetiredKind.Image => vulkanImageDestroy(retired.native),
		RetiredKind.View => vulkanViewDestroy(retired.native),
		RetiredKind.Sampler => vulkanSamplerDestroy(retired.native),
		RetiredKind.Shader => vulkanShaderModuleDestroy(retired.native),
		RetiredKind.Pipeline => vulkanPipelineDestroy(retired.native),
	};
	if (retired.memory.memory != 0) { freeMemory(r, retired.memory); }
}

export function collect(ref r: VulkanResources): Result<uint64, ResourceError> {
	let completed: uint64 = 0;
	try checked(vulkanCompletedSerial(completed));
	let kept: Vec<Retired> = [];
	for (const retired of r.retired) {
		if (retired.serial > completed) {
			kept.push(retired);
		} else if (retired.kind == RetiredKind.Page) {
			r.freePages.push({ native: retired.native, memory: retired.memory, next: 0 });
		} else {
			freeRetired(r, retired);
		}
	}
	r.retired = kept;
	finishDeallocations(r.descriptors, completed);
	return Result.ok(completed);
}

function uploadPage(ref r: VulkanResources): Result<UploadPage, ResourceError> {
	if (r.freePages.length > 0) {
		const page = r.freePages[r.freePages.length - 1];
		r.freePages.pop();
		return Result.ok(page);
	}
	const usage = (GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32);
	let native: uint64 = 0;
	try checked(vulkanBufferCreate(UPLOAD_PAGE_SIZE, bufferUsageFlags(usage), native));
	const placed = placeBuffer(r, native, MemoryKind.WriteMappable);
	if (!placed.ok) {
		vulkanBufferDestroy(native);
		return Result.err(placed.error);
	}
	return Result.ok({ native: native, memory: placed.value, next: 0 });
}

function upload(ref r: VulkanResources, bytes: uint64): Result<Staged, ResourceError> {
	if (bytes > UPLOAD_PAGE_SIZE) {
		stop(`vulkan: an upload of ${bytes} bytes is larger than the ${UPLOAD_PAGE_SIZE}-byte upload page`);
	}
	if (r.page.native == 0 || r.page.next + bytes > UPLOAD_PAGE_SIZE) {
		if (r.page.native != 0) { retire(r, RetiredKind.Page, r.page.native, r.page.memory); }
		r.page = NO_PAGE;
		r.page = try uploadPage(r);
	}
	const offset = r.page.next;
	r.page.next = alignUp(offset + bytes, UPLOAD_ALIGNMENT);
	return Result.ok({ native: r.page.native, memory: r.page.memory, offset: offset });
}

function mappedWrite<T>(
	ref r: VulkanResources,
	memory: MemoryAllocation,
	offset: uint64,
	data: Readonly<Span<T>>,
	dataOffset: uint64,
	rowBytes: uint64,
	sourcePitch: uint64,
	rows: uint32,
): Result<void, ResourceError> {
	const range = r.memory.mappedRange(memory, offset, rowBytes * (rows as uint64));
	return checked(vulkanMappedWrite(
		memory.memory,
		memory.mapped,
		memory.offset + offset,
		data[0],
		dataOffset,
		rowBytes,
		sourcePitch,
		rowBytes,
		rows,
		range.offset,
		range.size,
	));
}

function recordBufferCopy(
	ref t: StateTracker,
	source: uint64,
	sourceOffset: uint64,
	target: BufferNative,
	targetOffset: uint64,
	bytes: uint64,
): Result<void, ResourceError> {
	copyFromBuffer(t, source);
	writeToBuffer(t, target.native, target.rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	try flushTracker(t);
	return checked(vulkanCopyBuffer(source, sourceOffset, target.native, targetOffset, bytes));
}

export function writeBuffer<T>(ref r: VulkanResources, buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): Result<void, ResourceError> {
	const target = bufferRecords.slotIndex(buffer.id);
	const bytes = (data.length as uint64) * (sizeof T as uint64);
	const staged = try upload(r, bytes);
	try mappedWrite(r, staged.memory, staged.offset, data, 0, bytes, bytes, 1);
	try checked(vulkanQueueStream(1));
	try queued(r, recordBufferCopy(r.queue, staged.native, staged.offset, r.buffers[target], offset as uint64, bytes));
	r.buffers[target].lastUse = vulkanRecordingSerial();
	return Result.ok(null);
}

export function copyBufferToBuffer(
	ref r: VulkanResources,
	source: GPUBuffer,
	sourceOffset: int64,
	destination: GPUBuffer,
	destinationOffset: int64,
	size: int64,
): Result<void, ResourceError> {
	const from = bufferRecords.slotIndex(source.id);
	const target = bufferRecords.slotIndex(destination.id);
	try recordBufferCopy(r.tracker, r.buffers[from].native, sourceOffset as uint64, r.buffers[target], destinationOffset as uint64, size as uint64);
	r.buffers[from].lastUse = vulkanRecordingSerial();
	r.buffers[target].lastUse = r.buffers[from].lastUse;
	return Result.ok(null);
}

function copiedTexel(ref r: VulkanResources, member: string, texture: TextureRecord, writes: boolean, mipLevel: int32, size: GPUExtent3D): int32 {
	const info = r.textures[slotOf(texture.id)].info;
	if (info.depth) {
		const stencil = (info.aspect & ASPECT_STENCIL) != 0;
		checkedDepthTexelCopy(member, texture.id, texture.format, stencil, writes, texture.width, texture.height, mipLevel, size);
	}
	return info.texelBytes;
}

function copyImageBuffer(
	buffer: uint64,
	offset: int64,
	bytesPerRow: int32,
	texelBytes: int32,
	rowsPerImage: int32,
	texture: TextureRecord,
	native: TextureNative,
	info: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
	toImage: boolean,
): Result<void, ResourceError> {
	const volume = texture.volume;
	const origin = info.origin;
	const images = size.depthOrArrayLayers;
	if (toImage) {
		return checked(vulkanCopyBufferToImage(
			buffer,
			offset as uint64,
			rowLength(bytesPerRow, texelBytes),
			rowsPerImage as uint32,
			native.native,
			native.info.aspect,
			info.mipLevel as uint32,
			origin.x,
			origin.y,
			volume ? origin.z : 0,
			(volume ? 0 : origin.z) as uint32,
			(volume ? 1 : images) as uint32,
			size.width as uint32,
			size.height as uint32,
			(volume ? images : 1) as uint32,
		));
	}
	return checked(vulkanCopyImageToBuffer(
		buffer,
		offset as uint64,
		rowLength(bytesPerRow, texelBytes),
		rowsPerImage as uint32,
		native.native,
		native.info.aspect,
		info.mipLevel as uint32,
		origin.x,
		origin.y,
		volume ? origin.z : 0,
		(volume ? 0 : origin.z) as uint32,
		(volume ? 1 : images) as uint32,
		size.width as uint32,
		size.height as uint32,
		(volume ? images : 1) as uint32,
	));
}

function recordBufferToImage(
	ref t: StateTracker,
	buffer: uint64,
	offset: int64,
	bytesPerRow: int32,
	texelBytes: int32,
	rowsPerImage: int32,
	texture: TextureRecord,
	native: TextureNative,
	destination: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	copyFromBuffer(t, buffer);
	writeToTexture(t, native.native, native.rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE, LAYOUT_TRANSFER_DST);
	try flushTracker(t);
	return copyImageBuffer(buffer, offset, bytesPerRow, texelBytes, rowsPerImage, texture, native, destination, size, true);
}

export function writeTexture<T>(
	ref r: VulkanResources,
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	const texture = textureRecords.record(destination.texture.id);
	if (!has(texture.usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${texture.id}, created without COPY_DST`);
	}
	if (texture.sampleCount != 1) { stop(`writeTexture on GPUTexture ${texture.id}, which is multisampled`); }
	const texelBytes = copiedTexel(r, "writeTexture", texture, true, destination.mipLevel, size);
	const mip = destination.mipLevel;
	const depth = texture.volume && mip >= 0 && mip < texture.mipLevels ? Math.max(1, texture.layers >> mip) : texture.layers;
	const sourcePitch = checkedTexelWritePitch(
		texture.width,
		texture.height,
		texture.mipLevels,
		depth,
		texelBytes,
		(data.length as int64) * (sizeof T as int64),
		destination,
		layout,
		size,
	);
	const rowBytes = (size.width * texelBytes) as uint64;
	const rows = size.height as uint32;
	const images = size.depthOrArrayLayers;
	const rowsPerImage = (layout.rowsPerImage == 0 ? size.height : layout.rowsPerImage) as uint64;
	const staged = try upload(r, rowBytes * (rows as uint64) * (images as uint64));
	for (let image: int32 = 0; image < images; image++) {
		const at = staged.offset + rowBytes * (rows as uint64) * (image as uint64);
		const dataOffset = (layout.offset as uint64) + (sourcePitch as uint64) * rowsPerImage * (image as uint64);
		try mappedWrite(r, staged.memory, at, data, dataOffset, rowBytes, sourcePitch as uint64, rows);
	}
	const native = r.textures[slotOf(texture.id)];
	try checked(vulkanQueueStream(1));
	return queued(r, recordBufferToImage(
		r.queue,
		staged.native,
		staged.offset as int64,
		rowBytes as int32,
		texelBytes,
		size.height,
		texture,
		native,
		destination,
		size,
	));
}

export function copyBufferToTexture(
	ref r: VulkanResources,
	source: GPUTexelCopyBufferInfo,
	destination: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	const from = bufferRecords.slotIndex(source.buffer.id);
	const texture = textureRecords.record(destination.texture.id);
	const texelBytes = copiedTexel(r, "copyBufferToTexture destination", texture, true, destination.mipLevel, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", texelBytes, bufferRecords.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const native = r.textures[slotOf(texture.id)];
	try recordBufferToImage(r.tracker, r.buffers[from].native, source.offset, bytesPerRow, texelBytes, rowsPerImage, texture, native, destination, size);
	r.buffers[from].lastUse = vulkanRecordingSerial();
	return Result.ok(null);
}

export function copyTextureToBuffer(
	ref r: VulkanResources,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyBufferInfo,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	const texture = textureRecords.record(source.texture.id);
	const target = bufferRecords.slotIndex(destination.buffer.id);
	const texelBytes = copiedTexel(r, "copyTextureToBuffer source", texture, false, source.mipLevel, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", texelBytes, bufferRecords.slots[target].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const native = r.textures[slotOf(texture.id)];
	copyFromTexture(r.tracker, native.native, native.rest);
	writeToBuffer(r.tracker, r.buffers[target].native, r.buffers[target].rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	try flush(r);
	try copyImageBuffer(r.buffers[target].native, destination.offset, bytesPerRow, texelBytes, rowsPerImage, texture, native, source, size, false);
	r.buffers[target].lastUse = vulkanRecordingSerial();
	return Result.ok(null);
}

export function copyTextureToTexture(
	ref r: VulkanResources,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	if (source.texture.id == destination.texture.id) {
		stop(`copyTextureToTexture within GPUTexture ${source.texture.id} is not built on Vulkan: the tracker keeps one layout per image`);
	}
	const fromRecord = textureRecords.record(source.texture.id);
	const toRecord = textureRecords.record(destination.texture.id);
	const from = r.textures[slotOf(fromRecord.id)];
	const to = r.textures[slotOf(toRecord.id)];
	copyFromTexture(r.tracker, from.native, from.rest);
	writeToTexture(r.tracker, to.native, to.rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE, LAYOUT_TRANSFER_DST);
	try flush(r);
	const images = size.depthOrArrayLayers;
	return checked(vulkanCopyImage(
		from.native,
		source.mipLevel as uint32,
		source.origin.x,
		source.origin.y,
		fromRecord.volume ? source.origin.z : 0,
		(fromRecord.volume ? 0 : source.origin.z) as uint32,
		to.native,
		destination.mipLevel as uint32,
		destination.origin.x,
		destination.origin.y,
		toRecord.volume ? destination.origin.z : 0,
		(toRecord.volume ? 0 : destination.origin.z) as uint32,
		from.info.aspect,
		(fromRecord.volume ? 1 : images) as uint32,
		size.width as uint32,
		size.height as uint32,
		(fromRecord.volume ? images : 1) as uint32,
	));
}

export function submit(ref r: VulkanResources): Result<uint64, ResourceError> {
	settle(r);
	endPass(r.tracker);
	try flush(r);
	let serial: uint64 = 0;
	try checked(vulkanSubmit(serial));
	r.submitted = serial;
	if (r.page.native != 0) {
		r.retired.push({ serial: serial, kind: RetiredKind.Page, native: r.page.native, memory: r.page.memory });
		r.page = NO_PAGE;
	}
	return Result.ok(serial);
}

export function wait(ref r: VulkanResources, serial: uint64): Result<uint64, ResourceError> {
	try checked(vulkanWaitSerial(serial));
	return collect(r);
}

export function mapAsync(ref r: VulkanResources, buffer: GPUBuffer): Result<void, ResourceError> {
	const lastUse = r.buffers[bufferRecords.slotIndex(buffer.id)].lastUse;
	if (lastUse > r.submitted) {
		if (vulkanRecordingOpen() != 0) {
			stop(`mapAsync: GPUBuffer ${buffer.id} has work that was not submitted while a command encoder records; submit the encoder first`);
		}
		try submit(r);
	}
	if (lastUse == 0) { return Result.ok(null); }
	try wait(r, lastUse);
	return Result.ok(null);
}

export function readMapped(ref r: VulkanResources, buffer: GPUBuffer, offset: int64, size: int64): Result<Vec<uint8>, ResourceError> {
	const memory = r.buffers[bufferRecords.slotIndex(buffer.id)].memory;
	let bytes: Vec<uint8> = new Array(size);
	const range = r.memory.mappedRange(memory, offset as uint64, size as uint64);
	try checked(vulkanMappedRead(
		memory.memory,
		memory.mapped,
		memory.offset + (offset as uint64),
		bytes[0],
		size as uint64,
		range.offset,
		range.size,
	));
	return Result.ok(bytes);
}

export function writeMapped<T>(ref r: VulkanResources, buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): Result<void, ResourceError> {
	const bytes = (data.length as uint64) * (sizeof T as uint64);
	return mappedWrite(r, r.buffers[bufferRecords.slotIndex(buffer.id)].memory, offset as uint64, data, 0, bytes, bytes, 1);
}

export function closeResources(ref r: VulkanResources): Result<void, ResourceError> {
	retireCanvas(r);
	const submitted = submit(r);
	const drained: Result<uint64, ResourceError> = submitted.ok ? wait(r, submitted.value) : Result.err(submitted.error);
	if (r.page.native != 0) { retire(r, RetiredKind.Page, r.page.native, r.page.memory); }
	r.page = NO_PAGE;
	for (const page of r.freePages) { retire(r, RetiredKind.Page, page.native, page.memory); }
	r.freePages.length = 0;
	for (const retired of r.retired) { freeRetired(r, retired); }
	r.retired.length = 0;
	closeDescriptors(r.descriptors);
	r.buffers = [NO_BUFFER];
	r.textures = [NO_TEXTURE];
	r.views = [NO_VIEW];
	r.samplers = [0];
	if (!drained.ok) { return Result.err(drained.error); }
	return Result.ok(null);
}
