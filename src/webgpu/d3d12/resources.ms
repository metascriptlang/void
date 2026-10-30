import {
	dx12BufferCreate,
	dx12CopyBufferRegion,
	dx12CopyBufferTexture,
	dx12CopyTexture,
	dx12CopyableFootprint,
	dx12MemoryRead,
	dx12MemoryWrite,
	dx12MemoryWriteRows,
	dx12Release,
	dx12ResourceAddress,
	dx12ResourceMap,
	dx12ResourceUnmap,
	dx12TextureCreate,
} from "./d3d12.h";
import { FormatInfo, copyableFormat, formatInfo } from "./conv.ms";
import { FrameRing, NativeError, checked, retire, stop } from "./frame.ms";
import {
	STATE_COMMON,
	STATE_COPY_DEST,
	STATE_COPY_SOURCE,
	STATE_GENERIC_READ,
	StateTracker,
	SubresourceRange,
	Tracking,
	flushTransitions,
	newTracker,
	track,
	trackTexture,
	transition,
	transitionRange,
	untrack,
} from "./tracker.ms";
import {
	GPUBuffer,
	GPUBufferDescriptor,
	GPUBufferUsage,
	GPUExtent3D,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTextureUsage,
	checkedDepthTexelCopy,
	checkedTexelBufferLayout,
	checkedTexelWritePitch,
} from "../types.ms";
import { TextureRecord, bufferRecords, put, slotOf, textureRecords, vacate } from "../pool.ms";

const HEAP_DEFAULT: int32 = 1;
const HEAP_UPLOAD: int32 = 2;
const HEAP_READBACK: int32 = 3;
const NO_TRACKING: int32 = -1;
const CONSTANT_BUFFER_ALIGNMENT: uint64 = 256;
const UPLOAD_ALIGNMENT: uint64 = 256;
const TEXTURE_DATA_PLACEMENT_ALIGNMENT: uint64 = 512;
const TEXTURE_DATA_PITCH_ALIGNMENT: uint64 = 256;
const RESOURCE_FLAG_ALLOW_RENDER_TARGET: uint32 = 0x1;
const RESOURCE_FLAG_ALLOW_DEPTH_STENCIL: uint32 = 0x2;
const RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS: uint32 = 0x4;
const UPLOAD_FIRST_PAGE: uint64 = 2 * 1024 * 1024;
const UPLOAD_KEEP_UNUSED_FRAMES: int32 = 3600;
const UPLOAD_DISPOSE_ALL_BYTES: uint64 = 512 * 1024 * 1024;

export struct BufferNative {
	native: uint64;
	address: uint64;
	heap: int32;
	tracked: int32;
	lastUse: uint64;
}

export struct TextureNative {
	native: uint64;
	info: FormatInfo;
	tracked: int32;
}

export struct CopySplit {
	alignedOffset: uint64;
	bufferX: int32;
	bufferY: int32;
	textureX: int32;
	width: int32;
	bufferWidth: int32;
	bufferHeight: int32;
}

struct Footprint {
	rowPitch: uint32;
	rows: uint32;
	rowBytes: uint64;
	bytes: uint64;
}

struct UploadPage {
	native: uint64;
	pointer: uint64;
	capacity: uint64;
	offset: uint64;
	unusedFrames: int32;
}

struct UploadPages {
	pages: Vec<UploadPage>;
}

struct Staged {
	native: uint64;
	offset: uint64;
	pointer: uint64;
}

export struct Resources {
	device: uint64;
	tracker: StateTracker;
	buffers: Vec<BufferNative>;
	textures: Vec<TextureNative>;
	uploads: Vec<UploadPages>;
}

const NO_BUFFER: BufferNative = { native: 0, address: 0, heap: 0, tracked: NO_TRACKING, lastUse: 0 };
const NO_FORMAT: FormatInfo = {
	texture: 0,
	shaderResource: 0,
	renderTarget: 0,
	depthStencil: 0,
	bytesPerPixel: 0,
	depth: false,
	stencil: false,
};
const NO_TEXTURE: TextureNative = { native: 0, info: NO_FORMAT, tracked: NO_TRACKING };

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function alignUp(value: uint64, alignment: uint64): uint64 {
	return (value + alignment - 1) / alignment * alignment;
}

export function closedResources(): Resources {
	return { device: 0, tracker: newTracker(), buffers: [NO_BUFFER], textures: [NO_TEXTURE], uploads: [] };
}

export function openResources(device: uint64, frames: int32): Resources {
	let r = closedResources();
	r.device = device;
	for (let i: int32 = 0; i < frames; i++) { r.uploads.push({ pages: [] }); }
	return r;
}

function heapOf(usage: int32): int32 {
	if (has(usage, GPUBufferUsage.MAP_READ as int32)) { return HEAP_READBACK; }
	if (has(usage, GPUBufferUsage.MAP_WRITE as int32)) { return HEAP_UPLOAD; }
	return HEAP_DEFAULT;
}

function fixedState(heap: int32): uint32 {
	return heap == HEAP_READBACK ? STATE_COPY_DEST : STATE_GENERIC_READ;
}

export function createBuffer(ref r: Resources, id: uint32, descriptor: GPUBufferDescriptor): Result<void, NativeError> {
	const heap = heapOf(descriptor.usage);
	const size = has(descriptor.usage, GPUBufferUsage.UNIFORM as int32)
		? alignUp(descriptor.size as uint64, CONSTANT_BUFFER_ALIGNMENT)
		: descriptor.size as uint64;
	const unordered = heap == HEAP_DEFAULT && has(descriptor.usage, GPUBufferUsage.STORAGE as int32);
	const state = heap == HEAP_DEFAULT ? STATE_COMMON : fixedState(heap);
	let native: uint64 = 0;
	try checked(dx12BufferCreate(r.device, size, heap, state, unordered ? 1 : 0, native));
	let address: uint64 = 0;
	try checked(dx12ResourceAddress(native, address));
	const tracked = heap == HEAP_DEFAULT ? track(r.tracker, native, state, Tracking.Buffer) : NO_TRACKING;
	put(r.buffers, id, { native: native, address: address, heap: heap, tracked: tracked, lastUse: 0 });
	return Result.ok(null);
}

export function destroyBuffer(ref r: Resources, ref ring: FrameRing, id: uint32): void {
	const index = bufferRecords.slotIndex(id);
	retire(ring, r.buffers[index].native);
	if (r.buffers[index].tracked != NO_TRACKING) { untrack(r.tracker, r.buffers[index].tracked); }
	vacate(r.buffers, id);
}

function useBuffer(ref r: Resources, id: uint32, index: int32, state: uint32): void {
	const buffer = r.buffers[index];
	if (buffer.tracked != NO_TRACKING) {
		transition(r.tracker, buffer.tracked, state);
		return;
	}
	const fixed = fixedState(buffer.heap);
	if ((fixed & state) != state) {
		stop(`GPUBuffer ${id} lives on heap type ${buffer.heap} in state ${fixed} and cannot take state ${state}`);
	}
}

function copyRegion(
	ref r: Resources,
	ref ring: FrameRing,
	target: int32,
	targetOffset: uint64,
	source: uint64,
	sourceOffset: uint64,
	bytes: uint64,
): Result<void, NativeError> {
	try checked(flushTransitions(r.tracker, ring.list));
	try checked(dx12CopyBufferRegion(ring.list, r.buffers[target].native, targetOffset, source, sourceOffset, bytes));
	r.buffers[target].lastUse = ring.recording();
	return Result.ok(null);
}

function uploadPage(ref r: Resources, capacity: uint64): Result<UploadPage, NativeError> {
	let native: uint64 = 0;
	try checked(dx12BufferCreate(r.device, capacity, HEAP_UPLOAD, STATE_GENERIC_READ, 0, native));
	let pointer: uint64 = 0;
	const mapped = checked(dx12ResourceMap(native, 0, 0, pointer));
	if (!mapped.ok) {
		dx12Release(native);
		return Result.err(mapped.error);
	}
	return Result.ok({ native: native, pointer: pointer, capacity: capacity, offset: 0, unusedFrames: 0 });
}

function upload(ref r: Resources, frame: int32, bytes: uint64, alignment: uint64): Result<Staged, NativeError> {
	const size = alignUp(bytes, UPLOAD_ALIGNMENT);
	const pages = r.uploads[frame].pages;
	for (let i: int32 = 0; i < pages.length; i++) {
		const offset = alignUp(pages[i].offset, alignment);
		if (offset + size <= pages[i].capacity) {
			r.uploads[frame].pages[i].offset = offset + size;
			return Result.ok({ native: pages[i].native, offset: offset, pointer: pages[i].pointer + offset });
		}
	}
	const capacity = pages.length == 0
		? Math.max(UPLOAD_FIRST_PAGE, size)
		: Math.max(pages[pages.length - 1].capacity / 2 * 3, size);
	let page = try uploadPage(r, capacity);
	page.offset = size;
	r.uploads[frame].pages.push(page);
	return Result.ok({ native: page.native, offset: 0, pointer: page.pointer });
}

export function resetUploads(ref r: Resources, frame: int32): void {
	let total: uint64 = 0;
	for (const page of r.uploads[frame].pages) { total += page.capacity; }
	const disposeAll = total >= UPLOAD_DISPOSE_ALL_BYTES;
	let kept: Vec<UploadPage> = [];
	for (const page of r.uploads[frame].pages) {
		const unusedFrames = page.offset == 0 ? page.unusedFrames + 1 : 0;
		if (kept.length > 0 && (unusedFrames > UPLOAD_KEEP_UNUSED_FRAMES || disposeAll)) {
			dx12Release(page.native);
		} else {
			kept.push({ native: page.native, pointer: page.pointer, capacity: page.capacity, offset: 0, unusedFrames: unusedFrames });
		}
	}
	r.uploads[frame].pages = kept;
}

export function writeBuffer<T>(ref r: Resources, ref ring: FrameRing, buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): Result<void, NativeError> {
	const target = bufferRecords.slotIndex(buffer.id);
	const bytes = (data.length as uint64) * (sizeof T as uint64);
	const staged = try upload(r, ring.slot(), bytes, UPLOAD_ALIGNMENT);
	try checked(dx12MemoryWrite(staged.pointer, data[0], bytes));
	useBuffer(r, buffer.id, target, STATE_COPY_DEST);
	return copyRegion(r, ring, target, offset as uint64, staged.native, staged.offset, bytes);
}

export function copyBufferToBuffer(
	ref r: Resources,
	ref ring: FrameRing,
	source: GPUBuffer,
	sourceOffset: int64,
	destination: GPUBuffer,
	destinationOffset: int64,
	size: int64,
): Result<void, NativeError> {
	const from = bufferRecords.slotIndex(source.id);
	const target = bufferRecords.slotIndex(destination.id);
	useBuffer(r, source.id, from, STATE_COPY_SOURCE);
	useBuffer(r, destination.id, target, STATE_COPY_DEST);
	try copyRegion(r, ring, target, destinationOffset as uint64, r.buffers[from].native, sourceOffset as uint64, size as uint64);
	r.buffers[from].lastUse = ring.recording();
	return Result.ok(null);
}

export function lastUse(this r: Resources, buffer: GPUBuffer): uint64 {
	return r.buffers[bufferRecords.slotIndex(buffer.id)].lastUse;
}

export function readMapped(ref r: Resources, buffer: GPUBuffer, offset: int64, size: int64): Result<Vec<uint8>, NativeError> {
	const native = r.buffers[bufferRecords.slotIndex(buffer.id)].native;
	let pointer: uint64 = 0;
	try checked(dx12ResourceMap(native, offset as uint64, (offset + size) as uint64, pointer));
	let bytes: Vec<uint8> = new Array(size);
	try checked(dx12MemoryRead(pointer + (offset as uint64), bytes[0], size as uint64));
	try checked(dx12ResourceUnmap(native, 0, 0));
	return Result.ok(bytes);
}

export function writeMapped<T>(ref r: Resources, buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): Result<void, NativeError> {
	const native = r.buffers[bufferRecords.slotIndex(buffer.id)].native;
	const bytes = (data.length as uint64) * (sizeof T as uint64);
	let pointer: uint64 = 0;
	try checked(dx12ResourceMap(native, 0, 0, pointer));
	try checked(dx12MemoryWrite(pointer + (offset as uint64), data[0], bytes));
	return checked(dx12ResourceUnmap(native, offset as uint64, (offset as uint64) + bytes));
}

function textureFlags(texture: TextureRecord, info: FormatInfo): uint32 {
	let flags: uint32 = 0;
	if (has(texture.usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) {
		flags |= info.depth ? RESOURCE_FLAG_ALLOW_DEPTH_STENCIL : RESOURCE_FLAG_ALLOW_RENDER_TARGET;
	}
	if (has(texture.usage, GPUTextureUsage.STORAGE_BINDING as int32)) {
		if (info.depth || info.texture != info.renderTarget || texture.sampleCount > 1) {
			stop(`STORAGE_BINDING on GPUTexture ${texture.id} needs a single-sample color format that is not sRGB on d3d12`);
		}
		flags |= RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
	}
	return flags;
}

export function createTexture(ref r: Resources, texture: TextureRecord): Result<void, NativeError> {
	const info = formatInfo(texture.format, "GPUTextureDescriptor.format");
	let native: uint64 = 0;
	try checked(dx12TextureCreate(
		r.device,
		texture.volume ? 1 : 0,
		texture.width as uint32,
		texture.height as uint32,
		texture.layers as uint32,
		texture.mipLevels as uint32,
		info.texture,
		texture.sampleCount as uint32,
		textureFlags(texture, info),
		native,
	));
	const layers = texture.volume ? 1 : texture.layers;
	const tracked = trackTexture(r.tracker, native, texture.mipLevels, layers, info.stencil ? 2 : 1);
	put(r.textures, texture.id, { native: native, info: info, tracked: tracked });
	return Result.ok(null);
}

export function destroyTexture(ref r: Resources, ref ring: FrameRing, id: uint32): void {
	const index = textureRecords.slotIndex(id);
	retire(ring, r.textures[index].native);
	untrack(r.tracker, r.textures[index].tracked);
	vacate(r.textures, id);
}

function rangeOf(texture: TextureRecord, mipLevel: int32, z: int32, images: int32): SubresourceRange {
	return texture.volume
		? { baseMip: mipLevel, mips: 1, baseLayer: 0, layers: 1 }
		: { baseMip: mipLevel, mips: 1, baseLayer: z, layers: images };
}

function useSubresources(ref r: Resources, texture: TextureRecord, range: SubresourceRange, state: uint32): void {
	transitionRange(r.tracker, r.textures[slotOf(texture.id)].tracked, state, range);
}

function subresourceOf(texture: TextureRecord, mipLevel: int32, z: int32): uint32 {
	return (texture.volume ? mipLevel : mipLevel + z * texture.mipLevels) as uint32;
}

function sliceOf(texture: TextureRecord, z: int32): uint32 {
	return (texture.volume ? z : 0) as uint32;
}

function copiedTexel(ref r: Resources, member: string, texture: TextureRecord, writes: boolean, mipLevel: int32, size: GPUExtent3D): FormatInfo {
	const info = r.textures[slotOf(texture.id)].info;
	if (info.depth) {
		checkedDepthTexelCopy(member, texture.id, texture.format, info.stencil, writes, texture.width, texture.height, mipLevel, size);
	}
	return info;
}

function footprintOf(ref r: Resources, format: int32, width: int32, height: int32): Result<Footprint, NativeError> {
	let rowPitch: uint32 = 0;
	let rows: uint32 = 0;
	let rowBytes: uint64 = 0;
	let bytes: uint64 = 0;
	try checked(dx12CopyableFootprint(r.device, format, width as uint32, height as uint32, rowPitch, rows, rowBytes, bytes));
	return Result.ok({ rowPitch: rowPitch, rows: rows, rowBytes: rowBytes, bytes: bytes });
}

export function writeTexture<T>(
	ref r: Resources,
	ref ring: FrameRing,
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): Result<void, NativeError> {
	const texture = textureRecords.record(destination.texture.id);
	if (!has(texture.usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${texture.id}, created without COPY_DST`);
	}
	if (texture.sampleCount != 1) { stop(`writeTexture on GPUTexture ${texture.id}, which is multisampled`); }
	const mip = destination.mipLevel;
	const info = copiedTexel(r, "writeTexture", texture, true, mip, size);
	const depth = texture.volume && mip >= 0 && mip < texture.mipLevels ? Math.max(1, texture.layers >> mip) : texture.layers;
	const dataPitch = checkedTexelWritePitch(
		texture.width,
		texture.height,
		texture.mipLevels,
		depth,
		info.bytesPerPixel,
		(data.length as int64) * (sizeof T as int64),
		destination,
		layout,
		size,
	);
	const rowsPerImage = layout.rowsPerImage == 0 ? size.height : layout.rowsPerImage;
	const index = slotOf(texture.id);
	const format = copyableFormat(info);
	const footprint = try footprintOf(r, format, size.width, size.height);
	useSubresources(r, texture, rangeOf(texture, mip, destination.origin.z, size.depthOrArrayLayers), STATE_COPY_DEST);
	try checked(flushTransitions(r.tracker, ring.list));
	for (let image: int32 = 0; image < size.depthOrArrayLayers; image++) {
		const staged = try upload(r, ring.slot(), footprint.bytes, TEXTURE_DATA_PLACEMENT_ALIGNMENT);
		const dataOffset = (layout.offset as uint64) + (dataPitch as uint64) * (rowsPerImage as uint64) * (image as uint64);
		try checked(dx12MemoryWriteRows(
			staged.pointer,
			data[0],
			dataOffset,
			dataPitch as uint64,
			footprint.rowBytes,
			footprint.rowPitch as uint64,
			footprint.rows,
		));
		const z = destination.origin.z + image;
		try checked(dx12CopyBufferTexture(
			ring.list,
			1,
			r.textures[index].native,
			subresourceOf(texture, mip, z),
			destination.origin.x as uint32,
			destination.origin.y as uint32,
			sliceOf(texture, z),
			staged.native,
			staged.offset,
			format,
			size.width as uint32,
			size.height as uint32,
			footprint.rowPitch,
			0,
			0,
			size.width as uint32,
			size.height as uint32,
		));
	}
	return Result.ok(null);
}

function alignDownForPlacement(offset: uint64): uint64 {
	return offset / TEXTURE_DATA_PLACEMENT_ALIGNMENT * TEXTURE_DATA_PLACEMENT_ALIGNMENT;
}

export function splitTextureCopy(
	offset: uint64,
	bytesPerPixel: int32,
	bytesPerRow: int32,
	originX: int32,
	width: int32,
	height: int32,
): Vec<CopySplit> {
	const alignedOffset = alignDownForPlacement(offset);
	if (offset == alignedOffset) {
		return [{
			alignedOffset: alignedOffset,
			bufferX: 0,
			bufferY: 0,
			textureX: originX,
			width: width,
			bufferWidth: width,
			bufferHeight: height,
		}];
	}
	const texelsPerRow = bytesPerRow / bytesPerPixel;
	const skipped = ((offset - alignedOffset) as int32) / bytesPerPixel;
	const bufferX = skipped % texelsPerRow;
	const bufferY = skipped / texelsPerRow;
	if (width + bufferX <= texelsPerRow) {
		return [{
			alignedOffset: alignedOffset,
			bufferX: bufferX,
			bufferY: bufferY,
			textureX: originX,
			width: width,
			bufferWidth: width + bufferX,
			bufferHeight: height + bufferY,
		}];
	}
	const firstWidth = texelsPerRow - bufferX;
	const secondOffset = offset + ((firstWidth * bytesPerPixel) as uint64);
	const secondAligned = alignDownForPlacement(secondOffset);
	const secondSkipped = ((secondOffset - secondAligned) as int32) / bytesPerPixel;
	const secondX = secondSkipped % texelsPerRow;
	const secondY = secondSkipped / texelsPerRow;
	return [
		{
			alignedOffset: alignedOffset,
			bufferX: bufferX,
			bufferY: bufferY,
			textureX: originX,
			width: firstWidth,
			bufferWidth: texelsPerRow,
			bufferHeight: height + bufferY,
		},
		{
			alignedOffset: secondAligned,
			bufferX: secondX,
			bufferY: secondY,
			textureX: originX + firstWidth,
			width: width - firstWidth,
			bufferWidth: width - firstWidth + secondX,
			bufferHeight: height + secondY,
		},
	];
}

function copyBufferTexture(
	ref r: Resources,
	ref ring: FrameRing,
	toTexture: boolean,
	buffer: uint64,
	offset: int64,
	bytesPerRow: int32,
	rowsPerImage: int32,
	texture: TextureRecord,
	info: FormatInfo,
	copy: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): Result<void, NativeError> {
	const index = slotOf(texture.id);
	const rowPitch = alignUp(bytesPerRow as uint64, TEXTURE_DATA_PITCH_ALIGNMENT);
	const imageBytes = (bytesPerRow as uint64) * (rowsPerImage as uint64);
	try checked(flushTransitions(r.tracker, ring.list));
	for (let image: int32 = 0; image < size.depthOrArrayLayers; image++) {
		const z = copy.origin.z + image;
		const splits = splitTextureCopy(
			(offset as uint64) + imageBytes * (image as uint64),
			info.bytesPerPixel,
			rowPitch as int32,
			copy.origin.x,
			size.width,
			size.height,
		);
		for (const split of splits) {
			try checked(dx12CopyBufferTexture(
				ring.list,
				toTexture ? 1 : 0,
				r.textures[index].native,
				subresourceOf(texture, copy.mipLevel, z),
				split.textureX as uint32,
				copy.origin.y as uint32,
				sliceOf(texture, z),
				buffer,
				split.alignedOffset,
				copyableFormat(info),
				split.bufferWidth as uint32,
				split.bufferHeight as uint32,
				rowPitch as uint32,
				split.bufferX as uint32,
				split.bufferY as uint32,
				split.width as uint32,
				size.height as uint32,
			));
		}
	}
	return Result.ok(null);
}

export function copyBufferToTexture(
	ref r: Resources,
	ref ring: FrameRing,
	source: GPUTexelCopyBufferInfo,
	destination: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): Result<void, NativeError> {
	const from = bufferRecords.slotIndex(source.buffer.id);
	const texture = textureRecords.record(destination.texture.id);
	const info = copiedTexel(r, "copyBufferToTexture destination", texture, true, destination.mipLevel, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", info.bytesPerPixel, bufferRecords.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	useBuffer(r, source.buffer.id, from, STATE_COPY_SOURCE);
	useSubresources(r, texture, rangeOf(texture, destination.mipLevel, destination.origin.z, size.depthOrArrayLayers), STATE_COPY_DEST);
	const native = r.buffers[from].native;
	try copyBufferTexture(r, ring, true, native, source.offset, bytesPerRow, rowsPerImage, texture, info, destination, size);
	r.buffers[from].lastUse = ring.recording();
	return Result.ok(null);
}

export function copyTextureToBuffer(
	ref r: Resources,
	ref ring: FrameRing,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyBufferInfo,
	size: GPUExtent3D,
): Result<void, NativeError> {
	const texture = textureRecords.record(source.texture.id);
	const target = bufferRecords.slotIndex(destination.buffer.id);
	const info = copiedTexel(r, "copyTextureToBuffer source", texture, false, source.mipLevel, size);
	const bytesPerRow = checkedTexelBufferLayout(
		"copyTextureToBuffer destination",
		info.bytesPerPixel,
		bufferRecords.slots[target].size,
		destination,
		size,
	);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	useSubresources(r, texture, rangeOf(texture, source.mipLevel, source.origin.z, size.depthOrArrayLayers), STATE_COPY_SOURCE);
	useBuffer(r, destination.buffer.id, target, STATE_COPY_DEST);
	const native = r.buffers[target].native;
	try copyBufferTexture(r, ring, false, native, destination.offset, bytesPerRow, rowsPerImage, texture, info, source, size);
	r.buffers[target].lastUse = ring.recording();
	return Result.ok(null);
}

export function copyTextureToTexture(
	ref r: Resources,
	ref ring: FrameRing,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): Result<void, NativeError> {
	const fromRecord = textureRecords.record(source.texture.id);
	const toRecord = textureRecords.record(destination.texture.id);
	const from = slotOf(fromRecord.id);
	const to = slotOf(toRecord.id);
	const images = fromRecord.volume ? 1 : size.depthOrArrayLayers;
	const read = rangeOf(fromRecord, source.mipLevel, source.origin.z, images);
	const written = rangeOf(toRecord, destination.mipLevel, destination.origin.z, images);
	if (
		from == to && read.baseMip == written.baseMip
			&& read.baseLayer < written.baseLayer + written.layers && written.baseLayer < read.baseLayer + read.layers
	) {
		stop(`copyTextureToTexture reads and writes one subresource of mip ${source.mipLevel} of GPUTexture ${source.texture.id}, which d3d12 holds in one state`);
	}
	useSubresources(r, fromRecord, read, STATE_COPY_SOURCE);
	useSubresources(r, toRecord, written, STATE_COPY_DEST);
	try checked(flushTransitions(r.tracker, ring.list));
	const depth = fromRecord.volume ? size.depthOrArrayLayers : 1;
	for (let image: int32 = 0; image < images; image++) {
		try checked(dx12CopyTexture(
			ring.list,
			r.textures[to].native,
			subresourceOf(toRecord, destination.mipLevel, destination.origin.z + image),
			destination.origin.x as uint32,
			destination.origin.y as uint32,
			sliceOf(toRecord, destination.origin.z),
			r.textures[from].native,
			subresourceOf(fromRecord, source.mipLevel, source.origin.z + image),
			source.origin.x as uint32,
			source.origin.y as uint32,
			sliceOf(fromRecord, source.origin.z),
			size.width as uint32,
			size.height as uint32,
			depth as uint32,
		));
	}
	return Result.ok(null);
}

export function closeResources(ref r: Resources): void {
	for (const frame of r.uploads) {
		for (const page of frame.pages) { dx12Release(page.native); }
	}
	r = closedResources();
}
