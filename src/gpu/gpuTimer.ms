import { stop } from "./stop";
import {
	GPUBuffer,
	GPUBufferUsage,
	GPUCommandEncoder,
	GPUDevice,
	GPUMapMode,
	GPUPassTimestampWrites,
	GPUQuerySet,
} from "../webgpu/types.ms";
import "../webgpu/device.ms";

export const GPU_TIMER_OFF: int32 = 0;
export const GPU_TIMER_UNSUPPORTED: int32 = 1;
export const GPU_TIMER_ON: int32 = 2;

export const GPU_TIMER_RING: int32 = 3;
export const GPU_TIMER_MAX_PASSES: int32 = 1024;
const QUERY_BYTES: int64 = 8;
const NANOSECONDS_PER_MILLISECOND: float64 = 1000000.0;

export function timerWriteSlot(frame: int64, ring: int32): int32 {
	return (frame % (ring as int64)) as int32;
}

export function timerReadFrame(frame: int64, ring: int32): int64 {
	return frame - ((ring - 1) as int64);
}

export function timerReadSlot(frame: int64, ring: int32): int32 {
	return timerWriteSlot(timerReadFrame(frame, ring) + (ring as int64), ring);
}

struct TimerSlot {
	set: GPUQuerySet;
	resolved: GPUBuffer;
	readback: GPUBuffer;
	passes: int32;
	labels: Vec<string>;
}

let state: int32 = GPU_TIMER_OFF;
let maxPasses: int32 = 0;
let slots: Vec<TimerSlot> = [];
let frame: int64 = 0;
let resultFrame: int64 = -1;
let resultLabels: Vec<string> = [];
let resultMs: Vec<float64> = [];

export function timerState(): int32 { return state; }
export function timerBufferCount(): int32 { return state == GPU_TIMER_ON ? GPU_TIMER_RING * 2 : 0; }

function clearResults(): void {
	frame = 0;
	resultFrame = -1;
	resultLabels.length = 0;
	resultMs.length = 0;
}

// A device that is gone took its sets with it, so the ring is made again on the new one and the
// frames numbered from 0; `maxPasses` of 0 means the timer was never asked for.
export function timerBuild(device: GPUDevice): void {
	slots.length = 0;
	clearResults();
	if (maxPasses == 0) { state = GPU_TIMER_OFF; return; }
	if (!device.features().has("timestamp-query")) { state = GPU_TIMER_UNSUPPORTED; return; }
	for (let i = 0; i < GPU_TIMER_RING; i++) {
		const bytes = (maxPasses as int64) * 2 * QUERY_BYTES;
		slots.push({
			set: device.createQuerySet({
				label: "gpuTimer",
				type: "timestamp",
				count: maxPasses * 2,
			}),
			resolved: device.createBuffer({
				label: "gpuTimerResolve",
				size: bytes,
				usage: (GPUBufferUsage.QUERY_RESOLVE as int32) | (GPUBufferUsage.COPY_SRC as int32),
			}),
			readback: device.createBuffer({
				label: "gpuTimerRead",
				size: bytes,
				usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
			}),
			passes: 0,
			labels: [],
		});
	}
	state = GPU_TIMER_ON;
}

export function timerEnable(device: GPUDevice, max: int32): int32 {
	if (max < 1 || max > GPU_TIMER_MAX_PASSES) {
		stop(
			"the GPU timer takes 1.." + String(GPU_TIMER_MAX_PASSES) + " passes per frame, given " +
				String(max),
		);
	}
	if (state != GPU_TIMER_OFF) { stop("the GPU timer is already enabled"); }
	maxPasses = max;
	timerBuild(device);
	return state;
}

export function timerPassWrites(label: string): GPUPassTimestampWrites {
	const slot = timerWriteSlot(frame, GPU_TIMER_RING);
	const index = slots[slot].passes;
	if (index == maxPasses) {
		stop(
			"the GPU timer was enabled for at most " + String(maxPasses) +
				" passes per frame, and pass " + String(index + 1) + " (" + label + ") of frame " +
				String(frame) + " is one more",
		);
	}
	slots[slot].passes = index + 1;
	slots[slot].labels.push(label);
	return {
		querySet: slots[slot].set,
		beginningOfPassWriteIndex: index * 2,
		endOfPassWriteIndex: index * 2 + 1,
	};
}

// Reads the frame that finished `GPU_TIMER_RING - 1` frames ago, then resolves this frame's passes
// into the encoder; the read comes first because it is the slot this frame's successor writes.
export function timerFrameEnd(encoder: GPUCommandEncoder): void {
	const behind = timerReadFrame(frame, GPU_TIMER_RING);
	if (behind >= 0) { collect(timerReadSlot(frame, GPU_TIMER_RING), behind); }
	const slot = timerWriteSlot(frame, GPU_TIMER_RING);
	const queries = slots[slot].passes * 2;
	if (queries > 0) {
		const bytes = (queries as int64) * QUERY_BYTES;
		encoder.resolveQuerySet(slots[slot].set, 0, queries, slots[slot].resolved, 0);
		encoder.copyBufferToBuffer(slots[slot].resolved, 0, slots[slot].readback, 0, bytes);
	}
	frame += 1;
	const next = timerWriteSlot(frame, GPU_TIMER_RING);
	slots[next].passes = 0;
	slots[next].labels.length = 0;
}

function collect(slot: int32, which: int64): void {
	const count = slots[slot].passes;
	resultLabels.length = 0;
	resultMs.length = 0;
	if (count > 0) {
		const bytes = (count as int64) * 2 * QUERY_BYTES;
		slots[slot].readback.mapAsync(GPUMapMode.READ as int32, 0, bytes);
		const raw = slots[slot].readback.getMappedRange(0, bytes);
		slots[slot].readback.unmap();
		for (let i = 0; i < count; i++) {
			const begin = counter(raw, i * 2);
			const end = counter(raw, i * 2 + 1);
			if (end < begin) {
				stop(
					"GPU timer pass " + String(i) + " of frame " + String(which) +
						" ended before it began",
				);
			}
			resultLabels.push(slots[slot].labels[i]);
			resultMs.push(((end - begin) as float64) / NANOSECONDS_PER_MILLISECOND);
		}
	}
	resultFrame = which;
}

function counter(raw: Vec<uint8>, index: int32): uint64 {
	let value: uint64 = 0;
	for (let b = 7; b >= 0; b--) { value = (value << 8) | (raw[index * 8 + b] as uint64); }
	return value;
}

function stopUnlessResult(what: string): void {
	if (state == GPU_TIMER_OFF) { stop(what + ": the GPU timer is not enabled"); }
	if (state == GPU_TIMER_UNSUPPORTED) {
		stop(what + ": this device has no timestamp-query, so the GPU timer measures nothing");
	}
	if (resultFrame < 0) {
		stop(
			what + ": no frame has been read yet, the first result arrives " +
				String(GPU_TIMER_RING - 1) + " frames after the timer starts",
		);
	}
}

export function timerResultFrame(): int64 { return resultFrame; }

export function timerResultCount(): int32 {
	stopUnlessResult("gpu timer pass count");
	return resultMs.length as int32;
}

export function timerResultMs(index: int32): float64 {
	stopUnlessResult("gpu timer pass time");
	if (index < 0 || index >= (resultMs.length as int32)) {
		stop(
			"gpu timer pass " + String(index) + " is outside the " + String(resultMs.length) +
				" passes of frame " + String(resultFrame),
		);
	}
	return resultMs[index];
}

export function timerResultLabel(index: int32): string {
	stopUnlessResult("gpu timer pass label");
	if (index < 0 || index >= (resultMs.length as int32)) {
		stop(
			"gpu timer pass " + String(index) + " is outside the " + String(resultMs.length) +
				" passes of frame " + String(resultFrame),
		);
	}
	return resultLabels[index];
}
