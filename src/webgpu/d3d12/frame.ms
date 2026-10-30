import {
	dx12AllocatorCreate,
	dx12AllocatorReset,
	dx12Error,
	dx12EventClose,
	dx12FenceCompleted,
	dx12FenceCreate,
	dx12FenceWait,
	dx12ListClose,
	dx12ListCreate,
	dx12ListReset,
	dx12QueueExecute,
	dx12QueueSignal,
	dx12Release,
} from "./d3d12.h";
import { StateTracker, decay, flushTransitions } from "./tracker.ms";

@passL("-ld3d12");
@passL("-ldxgi");
@passL("-ldxguid");

export const FRAMES_IN_FLIGHT: int32 = 2;
export const DX12_OK: int32 = 0;
const DX12_OUT_OF_MEMORY: int32 = -4;
const DX12_DEVICE_REMOVED: int32 = -5;

export enum NativeError {
	OutOfMemory,
	DeviceRemoved,
}

export struct Retired {
	serial: uint64;
	native: uint64;
}

export struct FrameRing {
	queue: uint64;
	fence: uint64;
	event: uint64;
	list: uint64;
	allocators: Vec<uint64>;
	serials: Vec<uint64>;
	next: uint64;
	submitted: uint64;
	executed: uint64;
	completed: uint64;
	retired: Vec<Retired>;
}

@noinline export function stop(message: string): never {
	console.log(`webgpu d3d12: ${message}`);
	unreachable;
}

@noinline export function stopOnNative(): never {
	stop(dx12Error());
}

export function failure(code: int32): NativeError {
	if (code == DX12_OUT_OF_MEMORY) { return NativeError.OutOfMemory; }
	if (code == DX12_DEVICE_REMOVED) { return NativeError.DeviceRemoved; }
	stopOnNative();
}

export function checked(code: int32): Result<void, NativeError> {
	if (code != DX12_OK) { return Result.err(failure(code)); }
	return Result.ok(null);
}

export function closedFrames(): FrameRing {
	return { queue: 0, fence: 0, event: 0, list: 0, allocators: [], serials: [], next: 0, submitted: 0, executed: 0, completed: 0, retired: [] };
}

export function slot(this ring: FrameRing): int32 {
	return (ring.next % (ring.allocators.length as uint64)) as int32;
}

export function openFrames(device: uint64, queue: uint64, count: int32): Result<FrameRing, NativeError> {
	let ring = closedFrames();
	ring.queue = queue;
	const made = makeFrames(ring, device, count);
	if (!made.ok) {
		releaseFrames(ring);
		return Result.err(made.error);
	}
	return Result.ok(ring);
}

function makeFrames(ref ring: FrameRing, device: uint64, count: int32): Result<void, NativeError> {
	let fence: uint64 = 0;
	let event: uint64 = 0;
	try checked(dx12FenceCreate(device, fence, event));
	ring.fence = fence;
	ring.event = event;
	for (let i: int32 = 0; i < count; i++) {
		let allocator: uint64 = 0;
		try checked(dx12AllocatorCreate(device, allocator));
		ring.allocators.push(allocator);
		ring.serials.push(0);
	}
	let list: uint64 = 0;
	try checked(dx12ListCreate(device, ring.allocators[0], list));
	ring.list = list;
	return Result.ok(null);
}

export function submit(ref ring: FrameRing, ref tracker: StateTracker): Result<uint64, NativeError> {
	try checked(flushTransitions(tracker, ring.list));
	try checked(dx12ListClose(ring.list));
	try checked(dx12QueueExecute(ring.queue, ring.list));
	decay(tracker);
	const serial = ring.submitted + 1;
	try checked(dx12QueueSignal(ring.queue, ring.fence, serial));
	ring.submitted = serial;
	ring.executed = ring.allocators[ring.slot()];
	ring.serials[ring.slot()] = serial;
	ring.next += 1;
	try reopen(ring);
	return Result.ok(serial);
}

function reopen(ref ring: FrameRing): Result<void, NativeError> {
	const s = ring.slot();
	try checked(dx12FenceWait(ring.fence, ring.event, ring.serials[s]));
	try checked(dx12AllocatorReset(ring.allocators[s]));
	try checked(dx12ListReset(ring.list, ring.allocators[s]));
	try collect(ring);
	return Result.ok(null);
}

export function recording(this ring: FrameRing): uint64 { return ring.submitted + 1; }

export function retire(ref ring: FrameRing, native: uint64): void {
	ring.retired.push({ serial: ring.recording(), native: native });
}

export function collect(ref ring: FrameRing): Result<uint64, NativeError> {
	let completed: uint64 = 0;
	try checked(dx12FenceCompleted(ring.fence, completed));
	let kept: Vec<Retired> = [];
	for (const retired of ring.retired) {
		if (retired.serial > completed) {
			kept.push(retired);
		} else {
			dx12Release(retired.native);
		}
	}
	ring.retired = kept;
	ring.completed = completed;
	return Result.ok(completed);
}

export function waitSerial(ref ring: FrameRing, serial: uint64): Result<uint64, NativeError> {
	try checked(dx12FenceWait(ring.fence, ring.event, serial));
	return collect(ring);
}

export function waitIdle(ref ring: FrameRing): Result<uint64, NativeError> {
	return waitSerial(ring, ring.submitted);
}

export function closeFrames(ref ring: FrameRing): Result<void, NativeError> {
	if (ring.fence == 0) { return Result.ok(null); }
	const idle = waitIdle(ring);
	releaseFrames(ring);
	if (!idle.ok) { return Result.err(idle.error); }
	return Result.ok(null);
}

function releaseFrames(ref ring: FrameRing): void {
	for (const retired of ring.retired) { dx12Release(retired.native); }
	dx12Release(ring.list);
	for (const allocator of ring.allocators) { dx12Release(allocator); }
	dx12Release(ring.fence);
	if (ring.event != 0 && dx12EventClose(ring.event) != DX12_OK) { stopOnNative(); }
	ring = closedFrames();
}
