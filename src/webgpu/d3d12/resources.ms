import {
	dx12BufferCreate,
	dx12CopyBufferRegion,
	dx12MemoryRead,
	dx12MemoryWrite,
	dx12Release,
	dx12ResourceAddress,
	dx12ResourceMap,
	dx12ResourceUnmap,
} from "./d3d12.h";
import { FrameRing, NativeError, checked, retire, stop } from "./frame.ms";
import {
	STATE_COMMON,
	STATE_COPY_DEST,
	STATE_COPY_SOURCE,
	STATE_GENERIC_READ,
	StateTracker,
	Tracking,
	flushTransitions,
	newTracker,
	track,
	transition,
	untrack,
} from "./tracker.ms";
import { GPUBuffer, GPUBufferDescriptor, GPUBufferUsage } from "../types.ms";
import { bufferRecords, put, vacate } from "../pool.ms";

const HEAP_DEFAULT: int32 = 1;
const HEAP_UPLOAD: int32 = 2;
const HEAP_READBACK: int32 = 3;
const NO_TRACKING: int32 = -1;
const CONSTANT_BUFFER_ALIGNMENT: uint64 = 256;
const UPLOAD_ALIGNMENT: uint64 = 256;
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
	uploads: Vec<UploadPages>;
}

const NO_BUFFER: BufferNative = { native: 0, address: 0, heap: 0, tracked: NO_TRACKING, lastUse: 0 };

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function alignUp(value: uint64, alignment: uint64): uint64 {
	return (value + alignment - 1) / alignment * alignment;
}

export function closedResources(): Resources {
	return { device: 0, tracker: newTracker(), buffers: [NO_BUFFER], uploads: [] };
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

function upload(ref r: Resources, frame: int32, bytes: uint64): Result<Staged, NativeError> {
	const size = alignUp(bytes, UPLOAD_ALIGNMENT);
	const pages = r.uploads[frame].pages;
	for (let i: int32 = 0; i < pages.length; i++) {
		const offset = alignUp(pages[i].offset, UPLOAD_ALIGNMENT);
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
	const staged = try upload(r, ring.slot(), bytes);
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

export function closeResources(ref r: Resources): void {
	for (const frame of r.uploads) {
		for (const page of frame.pages) { dx12Release(page.native); }
	}
	r = closedResources();
}
