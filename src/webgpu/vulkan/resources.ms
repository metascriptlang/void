import {
	vulkanAdapterLimit,
	vulkanBarrierFlush,
	vulkanBarrierImage,
	vulkanBlockAllocate,
	vulkanBlockFree,
	vulkanBufferBind,
	vulkanBufferCreate,
	vulkanBufferDestroy,
	vulkanBufferRequirements,
	vulkanCompletedSerial,
	vulkanCopyBuffer,
	vulkanCopyBufferToImage,
	vulkanCopyImageToBuffer,
	vulkanError,
	vulkanFormatOptimalFeatures,
	vulkanImageBind,
	vulkanImageCreate,
	vulkanImageDestroy,
	vulkanImageRequirements,
	vulkanMappedRead,
	vulkanMappedWrite,
	vulkanMemoryHeapCount,
	vulkanMemoryHeapSize,
	vulkanMemoryType,
	vulkanMemoryTypeCount,
	vulkanRecordingSerial,
	vulkanSamplerCreate,
	vulkanSamplerDestroy,
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
	Tiling,
	memoryAllocate,
	memoryFree,
	memoryPropertiesOf,
} from "./memory";
import {
	ACCESS_TRANSFER_WRITE,
	FormatInfo,
	IMAGE_CREATE_CUBE_COMPATIBLE,
	IMAGE_TYPE_2D,
	IMAGE_TYPE_3D,
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
	textureRest,
	viewType,
} from "./conv";
import {
	BufferRest,
	STAGE_TRANSFER,
	StateTracker,
	TextureRest,
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
	GPUSampler,
	GPUSamplerDescriptor,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	checkedCubeView,
	checkedSamplerAnisotropy,
	checkedSamplerLod,
	checkedView3d,
	checkedViewLayers,
	checkedViewMips,
} from "../types.ms";
import { checkedViewDimension } from "../validate.ms";
import { Pool, allocate, newPool, release, slotIndex, store } from "../pool.ms";

@passC("-I../../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

export enum ResourceError {
	OutOfMemory,
	InvalidAllocation,
	NoCompatibleMemory,
	AllocationCountExceeded,
	BlockAllocationFailed,
	CreateFailed,
	BindFailed,
	ViewFailed,
	SamplerFailed,
	BarrierFailed,
	CopyFailed,
	UploadTooLarge,
	SubmitFailed,
	WaitFailed,
	NotMappable,
	StillInFlight,
	MapFailed,
}

const VULKAN_OK: int32 = 0;
const LIMIT_NON_COHERENT_ATOM_SIZE: int32 = 22;
const LIMIT_MEMORY_ALLOCATION_COUNT: int32 = 23;
const UPLOAD_PAGE_SIZE: uint64 = 64 * 1024 * 1024;
const UPLOAD_ALIGNMENT: uint64 = 256;
const MAX_ANISOTROPY = 16;

struct BufferRecord {
	id: uint32;
	native: uint32;
	size: int64;
	usage: int32;
	rest: BufferRest;
	memory: MemoryAllocation;
	lastWrite: uint64;
}

struct TextureRecord {
	id: uint32;
	native: uint32;
	format: GPUTextureFormat;
	info: FormatInfo;
	width: int32;
	height: int32;
	layers: int32;
	mipLevels: int32;
	volume: boolean;
	cube: boolean;
	rest: TextureRest;
	memory: MemoryAllocation;
}

struct ViewRecord {
	id: uint32;
	native: uint32;
}

struct SamplerRecord {
	id: uint32;
	native: uint32;
}

enum RetiredKind {
	Buffer,
	Image,
	View,
	Sampler,
	Page,
}

struct UploadPage {
	native: uint32;
	memory: MemoryAllocation;
	next: uint64;
}

struct Retired {
	serial: uint64;
	kind: RetiredKind;
	native: uint32;
	memory: MemoryAllocation;
}

struct Staged {
	native: uint32;
	block: uint32;
	blockOffset: uint64;
	bufferOffset: uint64;
}

export struct VulkanResources {
	memory: MemoryAllocator;
	tracker: StateTracker;
	buffers: Pool<BufferRecord>;
	textures: Pool<TextureRecord>;
	views: Pool<ViewRecord>;
	samplers: Pool<SamplerRecord>;
	retired: Vec<Retired>;
	freePages: Vec<UploadPage>;
	page: UploadPage;
	depthStencil: int32;
}

const NO_ALLOCATION: MemoryAllocation = { block: 0, offset: 0, size: 0, typeIndex: -1, group: -1, slot: -1, node: 0 };
const NO_PAGE: UploadPage = { native: 0, memory: NO_ALLOCATION, next: 0 };

@noinline function stop(message: string): void {
	console.log(`webgpu vulkan: ${message}`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function alignUp(value: uint64, alignment: uint64): uint64 {
	return (value + alignment - 1) / alignment * alignment;
}

function memoryFailure(error: MemoryError): ResourceError {
	return match (error) {
		MemoryError.OutOfMemory => ResourceError.OutOfMemory,
		MemoryError.InvalidAllocation => ResourceError.InvalidAllocation,
		MemoryError.NoCompatibleMemory => ResourceError.NoCompatibleMemory,
		MemoryError.AllocationCountExceeded => ResourceError.AllocationCountExceeded,
		MemoryError.BlockAllocationFailed => ResourceError.BlockAllocationFailed,
	};
}

function memoryDevice(): MemoryDevice {
	let device: MemoryDevice = {
		types: [],
		heapSizes: [],
		nonCoherentAtomSize: vulkanAdapterLimit(LIMIT_NON_COHERENT_ATOM_SIZE) as uint64,
		maxAllocationCount: vulkanAdapterLimit(LIMIT_MEMORY_ALLOCATION_COUNT) as uint32,
		openBlock: (typeIndex: int32, size: uint64, owner: DedicatedOwner): uint32 => {
			return vulkanBlockAllocate(typeIndex, size, owner.buffer, owner.image);
		},
		closeBlock: (block: uint32): void => {
			if (vulkanBlockFree(block) != VULKAN_OK) { stop(vulkanError()); }
		},
	};
	for (let i: int32 = 0; i < vulkanMemoryTypeCount(); i++) {
		let flags: uint32 = 0;
		let heap: int32 = 0;
		if (vulkanMemoryType(i, flags, heap) != VULKAN_OK) { stop(vulkanError()); }
		device.types.push({ properties: memoryPropertiesOf(flags), heap: heap });
	}
	for (let i: int32 = 0; i < vulkanMemoryHeapCount(); i++) { device.heapSizes.push(vulkanMemoryHeapSize(i)); }
	return device;
}

export function openResources(): VulkanResources {
	const noBuffer: BufferRecord = {
		id: 0,
		native: 0,
		size: 0,
		usage: 0,
		rest: { stages: 0, access: 0 },
		memory: NO_ALLOCATION,
		lastWrite: 0,
	};
	const noTexture: TextureRecord = {
		id: 0,
		native: 0,
		format: "rgba8unorm",
		info: { native: 0, texelBytes: 0, aspect: 0, depth: false },
		width: 0,
		height: 0,
		layers: 0,
		mipLevels: 0,
		volume: false,
		cube: false,
		rest: { stages: 0, access: 0, layout: 0 },
		memory: NO_ALLOCATION,
	};
	const noView: ViewRecord = { id: 0, native: 0 };
	const noSampler: SamplerRecord = { id: 0, native: 0 };
	return {
		memory: MemoryAllocator.forDevice(memoryDevice()),
		tracker: newTracker(),
		buffers: newPool<BufferRecord>("vulkan", "GPUBuffer", "buffer", noBuffer),
		textures: newPool<TextureRecord>("vulkan", "GPUTexture", "texture", noTexture),
		views: newPool<ViewRecord>("vulkan", "GPUTextureView", "texture view", noView),
		samplers: newPool<SamplerRecord>("vulkan", "GPUSampler", "sampler", noSampler),
		retired: [],
		freePages: [],
		page: NO_PAGE,
		depthStencil: depthStencilNative(vulkanFormatOptimalFeatures(d24s8Format())),
	};
}

function dedicationOf(code: int32): Dedication {
	return match (code) {
		0 => Dedication.None,
		1 => Dedication.Preferred,
		2 => Dedication.Required,
		_ => {
			stop(`a memory requirement query answered dedication ${code}`);
			return Dedication.Required;
		},
	};
}

function placeBuffer(ref r: VulkanResources, native: uint32, kind: MemoryKind): Result<MemoryAllocation, ResourceError> {
	let size: uint64 = 0;
	let alignment: uint64 = 0;
	let typeBits: uint32 = 0;
	let dedication: int32 = 0;
	if (vulkanBufferRequirements(native, size, alignment, typeBits, dedication) != VULKAN_OK) { stop(vulkanError()); }
	const request: MemoryRequest = {
		size: size,
		alignment: alignment,
		typeBits: typeBits,
		kind: kind,
		tiling: Tiling.Linear,
		dedication: dedicationOf(dedication),
		owner: { buffer: native, image: 0 },
	};
	const placed = memoryAllocate(r.memory, request);
	if (!placed.ok) { return Result.err(memoryFailure(placed.error)); }
	if (vulkanBufferBind(native, placed.value.block, placed.value.offset) != VULKAN_OK) {
		memoryFree(r.memory, placed.value);
		return Result.err(ResourceError.BindFailed);
	}
	return Result.ok(placed.value);
}

function placeImage(ref r: VulkanResources, native: uint32): Result<MemoryAllocation, ResourceError> {
	let size: uint64 = 0;
	let alignment: uint64 = 0;
	let typeBits: uint32 = 0;
	let dedication: int32 = 0;
	if (vulkanImageRequirements(native, size, alignment, typeBits, dedication) != VULKAN_OK) { stop(vulkanError()); }
	const request: MemoryRequest = {
		size: size,
		alignment: alignment,
		typeBits: typeBits,
		kind: MemoryKind.DeviceLocal,
		tiling: Tiling.Optimal,
		dedication: dedicationOf(dedication),
		owner: { buffer: 0, image: native },
	};
	const placed = memoryAllocate(r.memory, request);
	if (!placed.ok) { return Result.err(memoryFailure(placed.error)); }
	if (vulkanImageBind(native, placed.value.block, placed.value.offset) != VULKAN_OK) {
		memoryFree(r.memory, placed.value);
		return Result.err(ResourceError.BindFailed);
	}
	return Result.ok(placed.value);
}

function flush(ref r: VulkanResources): Result<void, ResourceError> {
	if (!r.tracker.pending()) { return Result.ok(null); }
	for (const barrier of r.tracker.images) {
		const code = vulkanBarrierImage(
			barrier.image,
			barrier.sourceAccess,
			barrier.targetAccess,
			barrier.oldLayout,
			barrier.newLayout,
		);
		if (code != VULKAN_OK) {
			cleared(r.tracker);
			return Result.err(ResourceError.BarrierFailed);
		}
	}
	const code = vulkanBarrierFlush(
		r.tracker.sourceStages,
		r.tracker.targetStages,
		r.tracker.sourceAccess,
		r.tracker.targetAccess,
	);
	cleared(r.tracker);
	if (code != VULKAN_OK) { return Result.err(ResourceError.BarrierFailed); }
	return Result.ok(null);
}

export function createBuffer(ref r: VulkanResources, descriptor: GPUBufferDescriptor): Result<GPUBuffer, ResourceError> {
	const size = Math.max(descriptor.size, 4 as int64);
	const native = vulkanBufferCreate(size as uint64, bufferUsageFlags(descriptor.usage));
	if (native == 0) { return Result.err(ResourceError.CreateFailed); }
	const placed = placeBuffer(r, native, bufferMemoryKind(descriptor.usage));
	if (!placed.ok) {
		vulkanBufferDestroy(native);
		return Result.err(placed.error);
	}
	const id = allocate(r.buffers);
	store(r.buffers, {
		id: id,
		native: native,
		size: descriptor.size,
		usage: descriptor.usage,
		rest: bufferRest(descriptor.usage),
		memory: placed.value,
		lastWrite: 0,
	});
	return Result.ok({ id: id });
}

export function createTexture(ref r: VulkanResources, descriptor: GPUTextureDescriptor): Result<GPUTexture, ResourceError> {
	const info = formatInfo(descriptor.format, r.depthStencil, "GPUTextureDescriptor.format");
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") {
		stop(`GPUTextureDescriptor.dimension '${dimension}' is not supported`);
	}
	const volume = dimension == "3d";
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const mipLevels = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	const samples = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	const cube = cubeCompatible(volume, width, height, layers, samples);
	const native = vulkanImageCreate(
		volume ? IMAGE_TYPE_3D : IMAGE_TYPE_2D,
		info.native,
		width as uint32,
		height as uint32,
		(volume ? layers : 1) as uint32,
		mipLevels as uint32,
		(volume ? 1 : layers) as uint32,
		samples as uint32,
		imageUsageFlags(descriptor.usage, info.depth),
		cube ? IMAGE_CREATE_CUBE_COMPATIBLE : 0,
		info.aspect,
	);
	if (native == 0) { return Result.err(ResourceError.CreateFailed); }
	const placed = placeImage(r, native);
	if (!placed.ok) {
		vulkanImageDestroy(native);
		return Result.err(placed.error);
	}
	const rest = textureRest(descriptor.usage, info.depth);
	initTexture(r.tracker, native, rest);
	const initialized = flush(r);
	if (!initialized.ok) {
		memoryFree(r.memory, placed.value);
		vulkanImageDestroy(native);
		return Result.err(initialized.error);
	}
	const id = allocate(r.textures);
	store(r.textures, {
		id: id,
		native: native,
		format: descriptor.format,
		info: info,
		width: width,
		height: height,
		layers: layers,
		mipLevels: mipLevels,
		volume: volume,
		cube: cube && has(descriptor.usage, GPUTextureUsage.TEXTURE_BINDING as int32) && layers % 6 == 0,
		rest: rest,
		memory: placed.value,
	});
	return Result.ok({ id: id });
}

export function createView(
	ref r: VulkanResources,
	texture: GPUTexture,
	descriptor: GPUTextureViewDescriptor,
): Result<GPUTextureView, ResourceError> {
	const t = r.textures.slots[r.textures.slotIndex(texture.id)];
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? t.mipLevels - baseMip : descriptor.mipLevelCount;
	checkedViewMips(texture.id, t.mipLevels, baseMip, mipCount);
	const dimension = checkedViewDimension(descriptor.dimension, t.volume, t.layers, texture.id);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (dimension == "3d") {
		checkedView3d(baseLayer, layerCount);
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (dimension == "2d") { layerCount = 1; }
		if (dimension == "cube") { layerCount = 6; }
		if (layerCount == 0) { layerCount = t.layers - baseLayer; }
		checkedViewLayers(texture.id, t.layers, baseLayer, layerCount);
	}
	if (dimension == "cube" || dimension == "cube-array") { checkedCubeView(texture.id, t.cube, baseLayer, layerCount); }
	const native = vulkanViewCreate(
		t.native,
		viewType(dimension),
		t.info.native,
		t.info.aspect,
		baseMip as uint32,
		mipCount as uint32,
		baseLayer as uint32,
		layerCount as uint32,
	);
	if (native == 0) { return Result.err(ResourceError.ViewFailed); }
	const id = allocate(r.views);
	store(r.views, { id: id, native: native });
	return Result.ok({ id: id });
}

export function createSampler(ref r: VulkanResources, descriptor: GPUSamplerDescriptor): Result<GPUSampler, ResourceError> {
	const magFilter = filter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter");
	const minFilter = filter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter");
	const mipmapMode = filter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter");
	const maxAnisotropy = descriptor.maxAnisotropy < 1 ? 1 : descriptor.maxAnisotropy;
	if (maxAnisotropy > MAX_ANISOTROPY) { stop(`GPUSamplerDescriptor.maxAnisotropy '${maxAnisotropy}' is not supported`); }
	checkedSamplerAnisotropy(maxAnisotropy, magFilter == 1 && minFilter == 1 && mipmapMode == 1);
	if (descriptor.lodMinClamp < 0) { stop(`GPUSamplerDescriptor.lodMinClamp '${descriptor.lodMinClamp}' is not supported`); }
	const maxLod = checkedSamplerLod(descriptor.lodMinClamp, descriptor.lodMaxClamp);
	const native = vulkanSamplerCreate(
		magFilter,
		minFilter,
		mipmapMode,
		addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"),
		addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"),
		addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW"),
		descriptor.lodMinClamp,
		maxLod,
		compareOp(descriptor.compare, "GPUSamplerDescriptor.compare"),
		maxAnisotropy as uint32,
	);
	if (native == 0) { return Result.err(ResourceError.SamplerFailed); }
	const id = allocate(r.samplers);
	store(r.samplers, { id: id, native: native });
	return Result.ok({ id: id });
}

function retire(ref r: VulkanResources, kind: RetiredKind, native: uint32, memory: MemoryAllocation): void {
	r.retired.push({ serial: vulkanRecordingSerial(), kind: kind, native: native, memory: memory });
}

export function destroyBuffer(ref r: VulkanResources, buffer: GPUBuffer): void {
	const index = r.buffers.slotIndex(buffer.id);
	retire(r, RetiredKind.Buffer, r.buffers.slots[index].native, r.buffers.slots[index].memory);
	r.buffers.slots[index].id = 0;
	release(r.buffers, buffer.id);
}

export function destroyTexture(ref r: VulkanResources, texture: GPUTexture): void {
	const index = r.textures.slotIndex(texture.id);
	retire(r, RetiredKind.Image, r.textures.slots[index].native, r.textures.slots[index].memory);
	r.textures.slots[index].id = 0;
	release(r.textures, texture.id);
}

export function destroyView(ref r: VulkanResources, view: GPUTextureView): void {
	const index = r.views.slotIndex(view.id);
	retire(r, RetiredKind.View, r.views.slots[index].native, NO_ALLOCATION);
	r.views.slots[index].id = 0;
	release(r.views, view.id);
}

export function destroySampler(ref r: VulkanResources, sampler: GPUSampler): void {
	const index = r.samplers.slotIndex(sampler.id);
	retire(r, RetiredKind.Sampler, r.samplers.slots[index].native, NO_ALLOCATION);
	r.samplers.slots[index].id = 0;
	release(r.samplers, sampler.id);
}

function nativeFree(kind: RetiredKind, native: uint32): int32 {
	return match (kind) {
		RetiredKind.Buffer => vulkanBufferDestroy(native),
		RetiredKind.Page => vulkanBufferDestroy(native),
		RetiredKind.Image => vulkanImageDestroy(native),
		RetiredKind.View => vulkanViewDestroy(native),
		RetiredKind.Sampler => vulkanSamplerDestroy(native),
	};
}

export function collect(ref r: VulkanResources): Result<uint64, ResourceError> {
	let completed: uint64 = 0;
	if (vulkanCompletedSerial(completed) != VULKAN_OK) { return Result.err(ResourceError.WaitFailed); }
	let kept: Vec<Retired> = [];
	for (const retired of r.retired) {
		if (retired.serial > completed) {
			kept.push(retired);
		} else if (retired.kind == RetiredKind.Page) {
			r.freePages.push({ native: retired.native, memory: retired.memory, next: 0 });
		} else {
			if (nativeFree(retired.kind, retired.native) != VULKAN_OK) { stop(vulkanError()); }
			if (retired.memory.block != 0) {
				const freed = memoryFree(r.memory, retired.memory);
				if (!freed.ok) { return Result.err(memoryFailure(freed.error)); }
			}
		}
	}
	r.retired = kept;
	return Result.ok(completed);
}

function uploadPage(ref r: VulkanResources): Result<UploadPage, ResourceError> {
	if (r.freePages.length > 0) {
		const page = r.freePages[r.freePages.length - 1];
		r.freePages.pop();
		return Result.ok(page);
	}
	const usage = (GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32);
	const native = vulkanBufferCreate(UPLOAD_PAGE_SIZE, bufferUsageFlags(usage));
	if (native == 0) { return Result.err(ResourceError.CreateFailed); }
	const placed = placeBuffer(r, native, MemoryKind.WriteMappable);
	if (!placed.ok) {
		vulkanBufferDestroy(native);
		return Result.err(placed.error);
	}
	return Result.ok({ native: native, memory: placed.value, next: 0 });
}

function upload(ref r: VulkanResources, bytes: uint64): Result<Staged, ResourceError> {
	if (bytes > UPLOAD_PAGE_SIZE) { return Result.err(ResourceError.UploadTooLarge); }
	if (r.page.native == 0 || r.page.next + bytes > UPLOAD_PAGE_SIZE) {
		if (r.page.native != 0) { retire(r, RetiredKind.Page, r.page.native, r.page.memory); }
		r.page = NO_PAGE;
		const page = uploadPage(r);
		if (!page.ok) { return Result.err(page.error); }
		r.page = page.value;
	}
	const offset = r.page.next;
	r.page.next = alignUp(offset + bytes, UPLOAD_ALIGNMENT);
	return Result.ok({
		native: r.page.native,
		block: r.page.memory.block,
		blockOffset: r.page.memory.offset + offset,
		bufferOffset: offset,
	});
}

function copyIntoBuffer(
	ref r: VulkanResources,
	source: uint32,
	sourceOffset: uint64,
	target: int32,
	targetOffset: uint64,
	bytes: uint64,
): Result<void, ResourceError> {
	copyFromBuffer(r.tracker, source);
	writeToBuffer(r.tracker, r.buffers.slots[target].native, r.buffers.slots[target].rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	try flush(r);
	if (vulkanCopyBuffer(source, sourceOffset, r.buffers.slots[target].native, targetOffset, bytes) != VULKAN_OK) {
		return Result.err(ResourceError.CopyFailed);
	}
	r.buffers.slots[target].lastWrite = vulkanRecordingSerial();
	return Result.ok(null);
}

export function writeBuffer(
	ref r: VulkanResources,
	buffer: GPUBuffer,
	offset: int64,
	data: Readonly<Span<uint8>>,
): Result<void, ResourceError> {
	const target = r.buffers.slotIndex(buffer.id);
	const bytes = data.length as uint64;
	if (bytes == 0) { return Result.ok(null); }
	const staged = try upload(r, bytes);
	if (vulkanMappedWrite(staged.block, staged.blockOffset, data[0], 0, bytes, bytes, bytes, 1) != VULKAN_OK) {
		return Result.err(ResourceError.MapFailed);
	}
	return copyIntoBuffer(r, staged.native, staged.bufferOffset, target, offset as uint64, bytes);
}

export function copyBufferToBuffer(
	ref r: VulkanResources,
	source: GPUBuffer,
	sourceOffset: int64,
	destination: GPUBuffer,
	destinationOffset: int64,
	size: int64,
): Result<void, ResourceError> {
	const from = r.buffers.slots[r.buffers.slotIndex(source.id)].native;
	const target = r.buffers.slotIndex(destination.id);
	return copyIntoBuffer(r, from, sourceOffset as uint64, target, destinationOffset as uint64, size as uint64);
}

@noinline function copyableTexel(member: string, t: TextureRecord): int32 {
	if (t.info.texelBytes == 0) {
		const name: string = t.format;
		stop(`${member}: ${name} GPUTexture ${t.id} has no single copyable aspect`);
	}
	return t.info.texelBytes;
}

export function writeTexture(
	ref r: VulkanResources,
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<uint8>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	const index = r.textures.slotIndex(destination.texture.id);
	const t = r.textures.slots[index];
	const texelBytes = copyableTexel("writeTexture", t);
	const rowBytes = (size.width * texelBytes) as uint64;
	const rows = size.height as uint32;
	const images = size.depthOrArrayLayers == 0 ? 1 : size.depthOrArrayLayers;
	const sourcePitch = (layout.bytesPerRow == 0 ? size.width * texelBytes : layout.bytesPerRow) as uint64;
	const rowsPerImage = (layout.rowsPerImage == 0 ? size.height : layout.rowsPerImage) as uint64;
	const staged = try upload(r, rowBytes * (rows as uint64) * (images as uint64));
	for (let image: int32 = 0; image < images; image++) {
		const imageBytes = rowBytes * (rows as uint64) * (image as uint64);
		const dataOffset = (layout.offset as uint64) + sourcePitch * rowsPerImage * (image as uint64);
		const code = vulkanMappedWrite(
			staged.block,
			staged.blockOffset + imageBytes,
			data[0],
			dataOffset,
			rowBytes,
			sourcePitch,
			rowBytes,
			rows,
		);
		if (code != VULKAN_OK) { return Result.err(ResourceError.MapFailed); }
	}
	copyFromBuffer(r.tracker, staged.native);
	writeToTexture(r.tracker, t.native, t.rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE, LAYOUT_TRANSFER_DST);
	try flush(r);
	const origin = destination.origin;
	const code = vulkanCopyBufferToImage(
		staged.native,
		staged.bufferOffset,
		size.width as uint32,
		rows,
		t.native,
		t.info.aspect,
		destination.mipLevel as uint32,
		origin.x,
		origin.y,
		t.volume ? origin.z : 0,
		(t.volume ? 0 : origin.z) as uint32,
		(t.volume ? 1 : images) as uint32,
		size.width as uint32,
		rows,
		(t.volume ? images : 1) as uint32,
	);
	if (code != VULKAN_OK) { return Result.err(ResourceError.CopyFailed); }
	return Result.ok(null);
}

export function copyTextureToBuffer(
	ref r: VulkanResources,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyBufferInfo,
	size: GPUExtent3D,
): Result<void, ResourceError> {
	const t = r.textures.slots[r.textures.slotIndex(source.texture.id)];
	const target = r.buffers.slotIndex(destination.buffer.id);
	const texelBytes = copyableTexel("copyTextureToBuffer", t);
	const bytesPerRow = destination.bytesPerRow == 0 ? size.width * texelBytes : destination.bytesPerRow;
	if (bytesPerRow % texelBytes != 0) {
		stop(`copyTextureToBuffer: bytesPerRow ${bytesPerRow} is not a multiple of the ${texelBytes}-byte texel`);
	}
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const images = size.depthOrArrayLayers == 0 ? 1 : size.depthOrArrayLayers;
	copyFromTexture(r.tracker, t.native, t.rest);
	writeToBuffer(r.tracker, r.buffers.slots[target].native, r.buffers.slots[target].rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	try flush(r);
	const origin = source.origin;
	const code = vulkanCopyImageToBuffer(
		r.buffers.slots[target].native,
		destination.offset as uint64,
		rowLength(bytesPerRow, texelBytes),
		rowsPerImage as uint32,
		t.native,
		t.info.aspect,
		source.mipLevel as uint32,
		origin.x,
		origin.y,
		t.volume ? origin.z : 0,
		(t.volume ? 0 : origin.z) as uint32,
		(t.volume ? 1 : images) as uint32,
		size.width as uint32,
		size.height as uint32,
		(t.volume ? images : 1) as uint32,
	);
	if (code != VULKAN_OK) { return Result.err(ResourceError.CopyFailed); }
	r.buffers.slots[target].lastWrite = vulkanRecordingSerial();
	return Result.ok(null);
}

export function submit(ref r: VulkanResources): Result<uint64, ResourceError> {
	endPass(r.tracker);
	try flush(r);
	let serial: uint64 = 0;
	if (vulkanSubmit(serial) != VULKAN_OK) { return Result.err(ResourceError.SubmitFailed); }
	if (r.page.native != 0) {
		r.retired.push({ serial: serial, kind: RetiredKind.Page, native: r.page.native, memory: r.page.memory });
		r.page = NO_PAGE;
	}
	return Result.ok(serial);
}

export function wait(ref r: VulkanResources, serial: uint64): Result<uint64, ResourceError> {
	if (vulkanWaitSerial(serial) != VULKAN_OK) { return Result.err(ResourceError.WaitFailed); }
	return collect(r);
}

export function readMapped(ref r: VulkanResources, buffer: GPUBuffer, offset: int64, size: int64): Result<Vec<uint8>, ResourceError> {
	const index = r.buffers.slotIndex(buffer.id);
	const slot = r.buffers.slots[index];
	if (!has(slot.usage, GPUBufferUsage.MAP_READ as int32)) { return Result.err(ResourceError.NotMappable); }
	const completed = try collect(r);
	if (slot.lastWrite > completed) { return Result.err(ResourceError.StillInFlight); }
	let bytes: Vec<uint8> = new Array(size);
	if (size == 0) { return Result.ok(bytes); }
	if (vulkanMappedRead(slot.memory.block, slot.memory.offset + (offset as uint64), bytes[0], size as uint64) != VULKAN_OK) {
		return Result.err(ResourceError.MapFailed);
	}
	return Result.ok(bytes);
}
