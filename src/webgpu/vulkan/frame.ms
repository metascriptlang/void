import { vulkanFrameBegin, vulkanFramesCreate } from "./vulkan.h";
import { VulkanResources, collect, submit } from "./resources";

@passC("-I../../../deps/vulkan-headers/include");

export enum FrameError {
	CreateFailed,
	SubmitFailed,
	BeginFailed,
	CollectFailed,
}

export const FRAMES_IN_FLIGHT: int32 = 2;

const VULKAN_OK: int32 = 0;

export struct FrameRing {
	serials: Vec<uint64>;
	next: uint64;
}

export function newFrameRing(count: int32): FrameRing {
	let serials: Vec<uint64> = [];
	for (let i: int32 = 0; i < count; i++) { serials.push(0); }
	return { serials: serials, next: 0 };
}

export function slot(this ring: FrameRing): uint32 {
	return (ring.next % (ring.serials.length as uint64)) as uint32;
}

export function reuseSerial(this ring: FrameRing): uint64 {
	return ring.serials[ring.slot() as int32];
}

export function frameSubmitted(ref ring: FrameRing, serial: uint64): void {
	ring.serials[ring.slot() as int32] = serial;
	ring.next += 1;
}

export function openFrames(count: int32): Result<FrameRing, FrameError> {
	if (vulkanFramesCreate(count as uint32) != VULKAN_OK) { return Result.err(FrameError.CreateFailed); }
	return Result.ok(newFrameRing(count));
}

export function beginFrame(ref r: VulkanResources, ring: FrameRing): Result<uint32, FrameError> {
	const flushed = submit(r);
	if (!flushed.ok) { return Result.err(FrameError.SubmitFailed); }
	if (vulkanFrameBegin(ring.slot(), ring.reuseSerial()) != VULKAN_OK) { return Result.err(FrameError.BeginFailed); }
	const collected = collect(r);
	if (!collected.ok) { return Result.err(FrameError.CollectFailed); }
	return Result.ok(ring.slot());
}

export function endFrame(ref r: VulkanResources, ref ring: FrameRing): Result<uint64, FrameError> {
	const serial = submit(r);
	if (!serial.ok) { return Result.err(FrameError.SubmitFailed); }
	frameSubmitted(ring, serial.value);
	return Result.ok(serial.value);
}
