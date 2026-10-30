import { dx12BarrierFlush, dx12BarrierTransition } from "./d3d12.h";
import { stop } from "../types.ms";

export const STATE_COMMON: uint32 = 0;
export const STATE_UNORDERED_ACCESS: uint32 = 0x8;
export const STATE_COPY_DEST: uint32 = 0x400;
export const STATE_COPY_SOURCE: uint32 = 0x800;
export const STATE_GENERIC_READ: uint32 = 0xac3;
const DX12_OK: int32 = 0;

struct Tracked {
	native: uint64;
	state: uint32;
	target: uint32;
	decays: boolean;
}

export struct StateTracker {
	resources: Vec<Tracked>;
	free: Vec<int32>;
	queued: Vec<int32>;
	uav: boolean;
}

const UNTRACKED: Tracked = { native: 0, state: STATE_COMMON, target: STATE_COMMON, decays: false };

export function newTracker(): StateTracker {
	return { resources: [], free: [], queued: [], uav: false };
}

export function track(ref t: StateTracker, native: uint64, state: uint32, decays: boolean): int32 {
	const tracked: Tracked = { native: native, state: state, target: state, decays: decays };
	if (t.free.length > 0) {
		const index = t.free[t.free.length - 1];
		t.free.pop();
		t.resources[index] = tracked;
		return index;
	}
	t.resources.push(tracked);
	return t.resources.length as int32 - 1;
}

export function untrack(ref t: StateTracker, index: int32): void {
	if (t.resources[index].state != t.resources[index].target) { cancelTransition(t, index); }
	t.resources[index] = UNTRACKED;
	t.free.push(index);
}

function cancelTransition(ref t: StateTracker, index: int32): void {
	for (let i: int32 = 0; i < t.queued.length; i++) {
		if (t.queued[i] == index) {
			t.queued.splice(i, 1);
			t.resources[index].target = t.resources[index].state;
			return;
		}
	}
	stop(`the transition of tracked resource ${index} is not queued`);
}

export function transition(ref t: StateTracker, index: int32, to: uint32): void {
	const tracked = t.resources[index];
	if (tracked.target == to) { return; }
	if (tracked.state == to) {
		cancelTransition(t, index);
		return;
	}
	if (tracked.decays && tracked.state == STATE_COMMON && tracked.target == STATE_COMMON) {
		t.resources[index].state = to;
		t.resources[index].target = to;
		return;
	}
	if (tracked.state == tracked.target) { t.queued.push(index); }
	t.resources[index].target = to;
}

export function queueUavBarrier(ref t: StateTracker): void { t.uav = true; }

export function flushTransitions(ref t: StateTracker, list: uint64): int32 {
	for (const index of t.queued) {
		const tracked = t.resources[index];
		const code = dx12BarrierTransition(tracked.native, tracked.state, tracked.target);
		if (code != DX12_OK) {
			t.queued.length = 0;
			t.uav = false;
			return code;
		}
		t.resources[index].state = tracked.target;
	}
	t.queued.length = 0;
	const uav = t.uav;
	t.uav = false;
	return dx12BarrierFlush(list, uav ? 1 : 0);
}

export function decay(ref t: StateTracker): void {
	for (let i: int32 = 0; i < t.resources.length; i++) {
		if (t.resources[i].decays) {
			t.resources[i].state = STATE_COMMON;
			t.resources[i].target = STATE_COMMON;
		}
	}
}
