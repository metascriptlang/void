import {
	vulkanAdapterName,
	vulkanAdapterSelect,
	vulkanDeviceCreate,
	vulkanError,
	vulkanInstanceCreate,
	vulkanLoaderOpen,
	vulkanShutdown,
	vulkanValidationEnabled,
	vulkanValidationErrors,
	vulkanValidationWarnings,
} from "../../src/webgpu/vulkan/vulkan.h";
import { vulkanHostView, vulkanHostWindowClose, vulkanHostWindowOpen, vulkanHostWindowResize } from "./vulkanSwapchainHost.h";
import { closeSurface, openSurface, surfaceAwait, surfaceHeight, surfacePresent, surfaceView, surfaceWidth } from "../../src/webgpu/vulkan/window";
import { getCurrentDepthTexture, getCurrentTexture, requestDevice } from "../../src/webgpu/device.ms";
import { GPUBuffer, GPUBufferUsage, GPUDevice, GPUMapMode, GPURenderPassDescriptor, GPUTexture } from "../../src/webgpu/types.ms";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_OK: int32 = 0;
const VULKAN_POWER_HIGH: int32 = 2;
const SAMPLES = 4;
const FRAMES = 8;
const RESIZE_AFTER = 3;
const WIDTH = 64;
const HEIGHT = 48;
const RESIZED_WIDTH = 96;
const RESIZED_HEIGHT = 72;
const SIDE_FRAMES = 4;
const SIDE_WIDTH = 40;
const SIDE_HEIGHT = 32;
const RED_BGRA: uint32 = 0x0000FFFF;
const GREEN_BGRA: uint32 = 0x00FF00FF;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan swapchain: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	vulkanHostWindowClose();
	return false;
}

function screen(surface: uint64): GPUTexture {
	return getCurrentTexture({
		width: surfaceWidth(surface),
		height: surfaceHeight(surface),
		sampleCount: SAMPLES,
		renderView: vulkanHostView(surfaceView(surface)),
		resolveView: null,
		depthStencilView: null,
	});
}

function rowPitch(width: int32): int32 { return (width * 4 + 255) & ~255; }

function clearScreen(device: GPUDevice, surface: uint64, index: int32): void {
	let descriptor: GPURenderPassDescriptor = { label: "swapchain clear" };
	descriptor.colorAttachments[0].view = screen(surface).createView({ label: null });
	descriptor.colorAttachments[0].loadOp = "clear";
	descriptor.colorAttachments[0].storeOp = "store";
	descriptor.colorAttachments[0].clearValue = index % 2 == 0 ? { r: 1.0, g: 0.0, b: 0.0, a: 1.0 } : { r: 0.0, g: 1.0, b: 0.0, a: 1.0 };
	descriptor.depthStencilAttachment.view = getCurrentDepthTexture().createView({ label: null });
	descriptor.depthStencilAttachment.depthLoadOp = "clear";
	descriptor.depthStencilAttachment.depthStoreOp = "store";
	descriptor.depthStencilAttachment.depthClearValue = 1.0;
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
}

function copyScreen(device: GPUDevice, surface: uint64): GPUBuffer {
	const width = surfaceWidth(surface);
	const height = surfaceHeight(surface);
	const destination = device.createBuffer({
		label: "screen readback",
		size: (rowPitch(width) * height) as int64,
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: screen(surface) },
		{ buffer: destination, offset: 0, bytesPerRow: rowPitch(width), rowsPerImage: height },
		{ width: width, height: height, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	return destination;
}

function cornerTexel(buffer: GPUBuffer, width: int32, height: int32): uint32 {
	buffer.mapAsync(GPUMapMode.READ as int32, 0, 0);
	const bytes = buffer.getMappedRange(0, 0);
	buffer.unmap();
	buffer.destroy();
	const at = (height - 1) * rowPitch(width) + (width - 1) * 4;
	return ((bytes[at] as uint32) << 24) | ((bytes[at + 1] as uint32) << 16) | ((bytes[at + 2] as uint32) << 8) | (bytes[at + 3] as uint32);
}

function acquired(surface: uint64, name: string, index: int32, width: int32, height: int32): boolean {
	if (surfaceAwait(surface, width, height) != 1) {
		console.log(`FAIL vulkan swapchain: ${name} frame ${index} acquired no image at ${width}x${height}`);
		return false;
	}
	if (surfaceWidth(surface) != width || surfaceHeight(surface) != height) {
		console.log(`FAIL vulkan swapchain: ${name} frame ${index} renders ${surfaceWidth(surface)}x${surfaceHeight(surface)}, not ${width}x${height}`);
		return false;
	}
	return true;
}

function drawn(device: GPUDevice, surface: uint64, name: string, index: int32, colour: int32, width: int32, height: int32): boolean {
	if (!acquired(surface, name, index, width, height)) { return false; }
	clearScreen(device, surface, colour);
	const copied = copyScreen(device, surface);
	surfacePresent(surface);
	const texel = cornerTexel(copied, width, height);
	const expected = colour % 2 == 0 ? RED_BGRA : GREEN_BGRA;
	if (texel != expected) {
		console.log(`FAIL vulkan swapchain: ${name} frame ${index} resolved corner 0x${texel.toString(16)}, not 0x${expected.toString(16)}`);
		return false;
	}
	return true;
}

function frames(device: GPUDevice, primary: uint64, side: uint64): int32 {
	let width = WIDTH;
	let height = HEIGHT;
	for (let index = 0; index < FRAMES; index++) {
		if (index == RESIZE_AFTER + 1) {
			if (!step("vulkanHostWindowResize", vulkanHostWindowResize(0, RESIZED_WIDTH, RESIZED_HEIGHT))) { return 1; }
			width = RESIZED_WIDTH;
			height = RESIZED_HEIGHT;
		}
		if (index == FRAMES - 1) {
			if (!acquired(primary, "primary", index, width, height)) { return 1; }
			surfacePresent(primary);
			continue;
		}
		if (!drawn(device, primary, "primary", index, index, width, height)) { return 1; }
		if (index < SIDE_FRAMES && !drawn(device, side, "side", index, index + 1, SIDE_WIDTH, SIDE_HEIGHT)) { return 1; }
		if (index == SIDE_FRAMES - 1) { closeSurface(side); }
	}
	console.log(`frames: ${FRAMES} presented at ${SAMPLES}x MSAA, ${WIDTH}x${HEIGHT} resized to ${RESIZED_WIDTH}x${RESIZED_HEIGHT} ` +
		`after frame ${RESIZE_AFTER}; each cleared frame resolved, re-read through a second getCurrentTexture and read back; ` +
		`the last frame presented without getCurrentTexture; a second surface made after the device presented ` +
		`${SIDE_FRAMES} frames at ${SIDE_WIDTH}x${SIDE_HEIGHT} between them and closed`);
	return 0;
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	let primary: uint64 = 0;
	if (!step("vulkanHostWindowOpen", vulkanHostWindowOpen(0, WIDTH, HEIGHT, primary))) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH, primary))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	console.log(`adapter ${vulkanAdapterName()}`);
	let side: uint64 = 0;
	if (!step("vulkanHostWindowOpen", vulkanHostWindowOpen(1, SIDE_WIDTH, SIDE_HEIGHT, side))) { return 1; }
	openSurface(primary);
	openSurface(side);
	const device = requestDevice({
		device: null,
		context: null,
		colorFormat: "bgra8unorm",
		depthFormat: "depth32float",
		sampleCount: SAMPLES,
	});
	if (frames(device, primary, side) != 0) {
		vulkanShutdown();
		vulkanHostWindowClose();
		return 1;
	}
	closeSurface(primary);
	device.destroy();
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	vulkanHostWindowClose();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ${vulkanValidationWarnings()} warnings`);
	if (errors != 0) {
		console.log(`FAIL vulkan swapchain: ${errors} validation errors`);
		return 1;
	}
	console.log("PASS vulkan swapchain: multisampled frames resolve into two surfaces' swapchains and present through a resize and a close");
	return 0;
}

process.exit(main());
