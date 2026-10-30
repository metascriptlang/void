import {
	dx12Release,
	dx12SwapchainBuffer,
	dx12SwapchainCreate,
	dx12SwapchainCurrent,
	dx12SwapchainRelease,
	dx12SwapchainResize,
} from "./d3d12.h";
import { DX12_OK, NativeError, checked, stop, stopOnNative } from "./frame.ms";
import { StateTracker, trackTexture, untrack } from "./tracker.ms";

export const PRESENT_MODE_VSYNC: int32 = 0;
export const PRESENT_MODE_IMMEDIATE: int32 = 1;

const SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE: uint32 = 0x40;
const SWAP_CHAIN_FLAG_ALLOW_TEARING: uint32 = 0x800;
const PRESENT_ALLOW_TEARING: uint32 = 0x200;
const PRESENT_DO_NOT_WAIT: uint32 = 0x8;
const FRAME_LATENCY: uint32 = 2;
const DXGI_R16G16B16A16_FLOAT: int32 = 10;
const DXGI_R10G10B10A2_UNORM: int32 = 24;
const DXGI_R8G8B8A8_UNORM: int32 = 28;
const DXGI_B8G8R8A8_UNORM: int32 = 87;

export struct PresentPlan {
	bufferCount: uint32;
	interval: uint32;
	presentFlags: uint32;
	swapFlags: uint32;
}

export struct Swapchain {
	id: uint32;
	native: uint64;
	waitable: uint64;
	composition: boolean;
	width: int32;
	height: int32;
	plan: PresentPlan;
	buffers: Vec<uint64>;
	tracked: Vec<int32>;
}

@noinline function stopOnPresentMode(mode: int32): never {
	stop(`present mode ${mode} is neither ${PRESENT_MODE_VSYNC} (vsync) nor ${PRESENT_MODE_IMMEDIATE} (immediate)`);
}

export function planPresent(mode: int32, tearing: boolean): PresentPlan {
	if (mode == PRESENT_MODE_VSYNC) {
		return { bufferCount: 2, interval: 1, presentFlags: 0, swapFlags: SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE };
	}
	if (mode != PRESENT_MODE_IMMEDIATE) { stopOnPresentMode(mode); }
	return {
		bufferCount: 2,
		interval: 0,
		presentFlags: tearing ? PRESENT_ALLOW_TEARING : 0,
		swapFlags: SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE | (tearing ? SWAP_CHAIN_FLAG_ALLOW_TEARING : 0),
	};
}

export struct PresentCall {
	interval: uint32;
	flags: uint32;
}

export function presentCall(plan: PresentPlan, modal: boolean): PresentCall {
	if (modal) { return { interval: 0, flags: PRESENT_DO_NOT_WAIT }; }
	return { interval: plan.interval, flags: plan.presentFlags };
}

export function flipFormat(format: int32): boolean {
	return format == DXGI_B8G8R8A8_UNORM || format == DXGI_R8G8B8A8_UNORM || format == DXGI_R10G10B10A2_UNORM || format == DXGI_R16G16B16A16_FLOAT;
}

export function fits(chain: Swapchain, width: int32, height: int32): boolean {
	return chain.width == width && chain.height == height;
}

export function openSwapchain(
	ref tracker: StateTracker,
	adapter: uint64,
	queue: uint64,
	window: uint64,
	composition: boolean,
	width: int32,
	height: int32,
	format: int32,
	plan: PresentPlan,
): Result<Swapchain, NativeError> {
	let native: uint64 = 0;
	let waitable: uint64 = 0;
	try checked(dx12SwapchainCreate(
		adapter,
		queue,
		window,
		composition ? 1 : 0,
		width as uint32,
		height as uint32,
		format,
		plan.bufferCount,
		plan.swapFlags,
		FRAME_LATENCY,
		native,
		waitable,
	));
	let chain: Swapchain = {
		id: 0,
		native: native,
		waitable: waitable,
		composition: composition,
		width: width,
		height: height,
		plan: plan,
		buffers: [],
		tracked: [],
	};
	const collected = collectBuffers(tracker, chain);
	if (!collected.ok) {
		closeSwapchain(tracker, chain);
		return Result.err(collected.error);
	}
	return Result.ok(chain);
}

function collectBuffers(ref tracker: StateTracker, ref chain: Swapchain): Result<void, NativeError> {
	for (let i: uint32 = 0; i < chain.plan.bufferCount; i++) {
		let buffer: uint64 = 0;
		try checked(dx12SwapchainBuffer(chain.native, i, buffer));
		chain.buffers.push(buffer);
		chain.tracked.push(trackTexture(tracker, buffer, 1, 1, 1));
	}
	return Result.ok(null);
}

function releaseBuffers(ref tracker: StateTracker, ref chain: Swapchain): void {
	for (const tracked of chain.tracked) { untrack(tracker, tracked); }
	for (const buffer of chain.buffers) { dx12Release(buffer); }
	chain.buffers.length = 0;
	chain.tracked.length = 0;
}

export function resizeSwapchain(ref tracker: StateTracker, ref chain: Swapchain, width: int32, height: int32): Result<void, NativeError> {
	releaseBuffers(tracker, chain);
	try checked(dx12SwapchainResize(chain.native, chain.plan.bufferCount, width as uint32, height as uint32, chain.plan.swapFlags));
	chain.width = width;
	chain.height = height;
	return collectBuffers(tracker, chain);
}

export function currentBuffer(chain: Swapchain): int32 {
	let index: uint32 = 0;
	if (dx12SwapchainCurrent(chain.native, index) != DX12_OK) { stopOnNative(); }
	if (index >= (chain.buffers.length as uint32)) {
		stop(`swapchain ${chain.id} names back buffer ${index} of ${chain.buffers.length}`);
	}
	return index as int32;
}

export function closeSwapchain(ref tracker: StateTracker, ref chain: Swapchain): void {
	releaseBuffers(tracker, chain);
	if (dx12SwapchainRelease(chain.native, chain.waitable) != DX12_OK) { stopOnNative(); }
	chain.native = 0;
	chain.waitable = 0;
}
