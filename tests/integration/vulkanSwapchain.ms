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
import { windowAwait, windowClose, windowHeight, windowPresent, windowView, windowWidth } from "../../src/webgpu/vulkan/window";
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
const RED_BGRA: uint32 = 0x0000FFFF;
const GREEN_BGRA: uint32 = 0x00FF00FF;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan swapchain: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	vulkanHostWindowClose();
	return false;
}

function screen(): GPUTexture {
	return getCurrentTexture({
		width: windowWidth(),
		height: windowHeight(),
		sampleCount: SAMPLES,
		renderView: vulkanHostView(windowView()),
		resolveView: null,
		depthStencilView: null,
	});
}

function rowPitch(width: int32): int32 { return (width * 4 + 255) & ~255; }

function clearScreen(device: GPUDevice, index: int32): void {
	let descriptor: GPURenderPassDescriptor = { label: "swapchain clear" };
	descriptor.colorAttachments[0].view = screen().createView({ label: null });
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

function copyScreen(device: GPUDevice): GPUBuffer {
	const width = windowWidth();
	const height = windowHeight();
	const destination = device.createBuffer({
		label: "screen readback",
		size: (rowPitch(width) * height) as int64,
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: screen() },
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

function frames(device: GPUDevice): int32 {
	let width = WIDTH;
	let height = HEIGHT;
	for (let index = 0; index < FRAMES; index++) {
		if (index == RESIZE_AFTER + 1) {
			if (!step("vulkanHostWindowResize", vulkanHostWindowResize(RESIZED_WIDTH, RESIZED_HEIGHT))) { return 1; }
			width = RESIZED_WIDTH;
			height = RESIZED_HEIGHT;
		}
		if (windowAwait(width, height) != 1) {
			console.log(`FAIL vulkan swapchain: frame ${index} acquired no image at ${width}x${height}`);
			return 1;
		}
		if (windowWidth() != width || windowHeight() != height) {
			console.log(`FAIL vulkan swapchain: frame ${index} renders ${windowWidth()}x${windowHeight()}, not ${width}x${height}`);
			return 1;
		}
		if (index == FRAMES - 1) {
			windowPresent();
			continue;
		}
		clearScreen(device, index);
		const copied = copyScreen(device);
		windowPresent();
		const texel = cornerTexel(copied, width, height);
		const expected = index % 2 == 0 ? RED_BGRA : GREEN_BGRA;
		if (texel != expected) {
			console.log(`FAIL vulkan swapchain: frame ${index} resolved corner 0x${texel.toString(16)}, not 0x${expected.toString(16)}`);
			return 1;
		}
	}
	console.log(`frames: ${FRAMES} presented at ${SAMPLES}x MSAA, ${WIDTH}x${HEIGHT} resized to ${RESIZED_WIDTH}x${RESIZED_HEIGHT} ` +
		`after frame ${RESIZE_AFTER}; each cleared frame resolved, re-read through a second getCurrentTexture and read back; ` +
		`the last frame presented without getCurrentTexture`);
	return 0;
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	if (!step("vulkanHostWindowOpen", vulkanHostWindowOpen(WIDTH, HEIGHT))) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	console.log(`adapter ${vulkanAdapterName()}`);
	const device = requestDevice({
		device: null,
		context: null,
		colorFormat: "bgra8unorm",
		depthFormat: "depth32float",
		sampleCount: SAMPLES,
	});
	if (frames(device) != 0) {
		vulkanShutdown();
		vulkanHostWindowClose();
		return 1;
	}
	windowClose();
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
	console.log("PASS vulkan swapchain: multisampled frames resolve into the swapchain and present through a resize");
	return 0;
}

process.exit(main());
