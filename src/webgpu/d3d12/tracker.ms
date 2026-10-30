import { dx12BarrierFlush, dx12BarrierTransition } from "./d3d12.h";
import { stop } from "../types.ms";

export const STATE_COMMON: uint32 = 0;
export const STATE_UNORDERED_ACCESS: uint32 = 0x8;
export const STATE_COPY_DEST: uint32 = 0x400;
export const STATE_COPY_SOURCE: uint32 = 0x800;
export const STATE_GENERIC_READ: uint32 = 0xac3;
const STATE_ALL_SHADER_RESOURCE: uint32 = 0xc0;
const TEXTURE_PROMOTABLE_READS: uint32 = STATE_COPY_SOURCE | STATE_ALL_SHADER_RESOURCE;
const ALL_SUBRESOURCES: uint32 = 0xffffffff;
const DX12_OK: int32 = 0;

export enum Tracking {
	Buffer,
	Texture,
}

struct SubState {
	state: uint32;
	target: uint32;
	decays: boolean;
}

export struct SubresourceRange {
	baseMip: int32;
	mips: int32;
	baseLayer: int32;
	layers: int32;
}

struct Tracked {
	native: uint64;
	tracking: Tracking;
	whole: SubState;
	subs: Vec<SubState>;
	mips: int32;
	layers: int32;
	planes: int32;
}

export struct StateTracker {
	resources: Vec<Tracked>;
	free: Vec<int32>;
	queued: Vec<int32>;
	uav: boolean;
}

function untracked(): Tracked {
	return {
		native: 0,
		tracking: Tracking.Buffer,
		whole: { state: STATE_COMMON, target: STATE_COMMON, decays: false },
		subs: [],
		mips: 1,
		layers: 1,
		planes: 1,
	};
}

export function newTracker(): StateTracker {
	return { resources: [], free: [], queued: [], uav: false };
}

function place(ref t: StateTracker, tracked: Tracked): int32 {
	if (t.free.length > 0) {
		const index = t.free[t.free.length - 1];
		t.free.pop();
		t.resources[index] = tracked;
		return index;
	}
	t.resources.push(tracked);
	return t.resources.length as int32 - 1;
}

export function track(ref t: StateTracker, native: uint64, state: uint32, tracking: Tracking): int32 {
	return place(t, {
		native: native,
		tracking: tracking,
		whole: { state: state, target: state, decays: tracking == Tracking.Buffer },
		subs: [],
		mips: 1,
		layers: 1,
		planes: 1,
	});
}

export function trackTexture(ref t: StateTracker, native: uint64, mips: int32, layers: int32, planes: int32): int32 {
	return place(t, {
		native: native,
		tracking: Tracking.Texture,
		whole: { state: STATE_COMMON, target: STATE_COMMON, decays: false },
		subs: [],
		mips: mips,
		layers: layers,
		planes: planes,
	});
}

export function untrack(ref t: StateTracker, index: int32): void {
	if (pending(t.resources[index])) { dequeue(t, index); }
	t.resources[index] = untracked();
	t.free.push(index);
}

function pending(tracked: Tracked): boolean {
	if (tracked.subs.length == 0) { return tracked.whole.state != tracked.whole.target; }
	for (const sub of tracked.subs) {
		if (sub.state != sub.target) { return true; }
	}
	return false;
}

function dequeue(ref t: StateTracker, index: int32): void {
	for (let i: int32 = 0; i < t.queued.length; i++) {
		if (t.queued[i] == index) {
			t.queued.splice(i, 1);
			return;
		}
	}
	stop(`the transition of tracked resource ${index} is not queued`);
}

function requeue(ref t: StateTracker, index: int32, was: boolean): void {
	const now = pending(t.resources[index]);
	if (now && !was) { t.queued.push(index); }
	if (was && !now) { dequeue(t, index); }
}

function moved(sub: SubState, tracking: Tracking, to: uint32): SubState {
	if (sub.target == to) { return sub; }
	if (sub.state == to) { return { state: to, target: to, decays: sub.decays }; }
	if (sub.state == STATE_COMMON && sub.target == STATE_COMMON && promotes(tracking, to)) {
		return { state: to, target: to, decays: tracking == Tracking.Buffer || to != STATE_COPY_DEST };
	}
	return { state: sub.state, target: to, decays: sub.decays };
}

function promotes(tracking: Tracking, to: uint32): boolean {
	return match (tracking) {
		Tracking.Buffer => true,
		Tracking.Texture => to == STATE_COPY_DEST || (to & ~TEXTURE_PROMOTABLE_READS) == 0,
	};
}

function sameSub(a: SubState, b: SubState): boolean {
	return a.state == b.state && a.target == b.target && a.decays == b.decays;
}

function split(ref t: StateTracker, index: int32): void {
	if (t.resources[index].subs.length > 0) { return; }
	const count = t.resources[index].mips * t.resources[index].layers * t.resources[index].planes;
	const whole = t.resources[index].whole;
	for (let i: int32 = 0; i < count; i++) { t.resources[index].subs.push(whole); }
}

function recompress(ref t: StateTracker, index: int32): void {
	const subs = t.resources[index].subs;
	if (subs.length == 0) { return; }
	for (const sub of subs) {
		if (!sameSub(sub, subs[0])) { return; }
	}
	t.resources[index].whole = subs[0];
	t.resources[index].subs.length = 0;
}

export function transition(ref t: StateTracker, index: int32, to: uint32): void {
	const was = pending(t.resources[index]);
	const tracking = t.resources[index].tracking;
	if (t.resources[index].subs.length == 0) {
		t.resources[index].whole = moved(t.resources[index].whole, tracking, to);
	} else {
		for (let i: int32 = 0; i < t.resources[index].subs.length; i++) {
			t.resources[index].subs[i] = moved(t.resources[index].subs[i], tracking, to);
		}
		recompress(t, index);
	}
	requeue(t, index, was);
}

export function transitionRange(ref t: StateTracker, index: int32, to: uint32, range: SubresourceRange): void {
	const mips = t.resources[index].mips;
	const layers = t.resources[index].layers;
	if (range.baseMip == 0 && range.mips == mips && range.baseLayer == 0 && range.layers == layers) {
		transition(t, index, to);
		return;
	}
	const was = pending(t.resources[index]);
	const tracking = t.resources[index].tracking;
	split(t, index);
	for (let plane: int32 = 0; plane < t.resources[index].planes; plane++) {
		for (let layer = range.baseLayer; layer < range.baseLayer + range.layers; layer++) {
			for (let mip = range.baseMip; mip < range.baseMip + range.mips; mip++) {
				const sub = mip + layer * mips + plane * mips * layers;
				t.resources[index].subs[sub] = moved(t.resources[index].subs[sub], tracking, to);
			}
		}
	}
	requeue(t, index, was);
}

export function settledAt(t: StateTracker, index: int32, state: uint32): boolean {
	const whole = t.resources[index].whole;
	return t.resources[index].subs.length == 0 && whole.state == state && whole.target == state;
}

export function queueUavBarrier(ref t: StateTracker): void { t.uav = true; }

function settled(sub: SubState, tracking: Tracking): SubState {
	return { state: sub.target, target: sub.target, decays: tracking == Tracking.Texture ? false : sub.decays };
}

function flushResource(ref t: StateTracker, index: int32): int32 {
	recompress(t, index);
	const native = t.resources[index].native;
	const tracking = t.resources[index].tracking;
	if (t.resources[index].subs.length == 0) {
		const whole = t.resources[index].whole;
		const code = dx12BarrierTransition(native, ALL_SUBRESOURCES, whole.state, whole.target);
		if (code == DX12_OK) { t.resources[index].whole = settled(whole, tracking); }
		return code;
	}
	for (let i: int32 = 0; i < t.resources[index].subs.length; i++) {
		const sub = t.resources[index].subs[i];
		if (sub.state != sub.target) {
			const code = dx12BarrierTransition(native, i as uint32, sub.state, sub.target);
			if (code != DX12_OK) { return code; }
			t.resources[index].subs[i] = settled(sub, tracking);
		}
	}
	recompress(t, index);
	return DX12_OK;
}

export function flushTransitions(ref t: StateTracker, list: uint64): int32 {
	for (const index of t.queued) {
		const code = flushResource(t, index);
		if (code != DX12_OK) {
			t.queued.length = 0;
			t.uav = false;
			return code;
		}
	}
	t.queued.length = 0;
	const uav = t.uav;
	t.uav = false;
	return dx12BarrierFlush(list, uav ? 1 : 0);
}

function decayed(sub: SubState, tracking: Tracking): SubState {
	if (!sub.decays) { return sub; }
	return { state: STATE_COMMON, target: STATE_COMMON, decays: tracking == Tracking.Buffer };
}

export function decay(ref t: StateTracker): void {
	for (let i: int32 = 0; i < t.resources.length; i++) {
		const tracking = t.resources[i].tracking;
		if (t.resources[i].subs.length == 0) {
			t.resources[i].whole = decayed(t.resources[i].whole, tracking);
		} else {
			for (let s: int32 = 0; s < t.resources[i].subs.length; s++) {
				t.resources[i].subs[s] = decayed(t.resources[i].subs[s], tracking);
			}
			recompress(t, i);
		}
	}
}
