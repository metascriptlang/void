import { env } from "std/process";
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
import { vulkanHostWindowClose, vulkanHostWindowOpen, vulkanHostWindowResize } from "./vulkanSwapchainHost.h";
import { VulkanResources, openResources } from "../../src/webgpu/vulkan/resources";
import { RenderPassCache, beginRenderPass, endRenderPass, newRenderPassCache } from "../../src/webgpu/vulkan/pass";
import { FRAMES_IN_FLIGHT, FrameRing, beginFrame, endFrame, openFrames } from "../../src/webgpu/vulkan/frame";
import {
	Swapchain,
	SurfaceError,
	acquireImage,
	configureSurface,
	extentChanged,
	newSwapchain,
	present,
	releaseSurface,
	releaseSwapchain,
} from "../../src/webgpu/vulkan/surface";
import { GPURenderPassDescriptor, GPUTextureUsage } from "../../src/webgpu/types.ms";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_OK: int32 = 0;
const VULKAN_POWER_HIGH: int32 = 2;
const FRAMES = 8;
const RESIZE_AFTER = 3;
const WIDTH = 64;
const HEIGHT = 48;
const RESIZED_WIDTH = 96;
const RESIZED_HEIGHT = 72;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan swapchain: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	vulkanHostWindowClose();
	return false;
}

function refused(name: string, error: string): int32 {
	console.log(`FAIL vulkan swapchain: ${name} refused with ${error}: ${vulkanError()}`);
	vulkanShutdown();
	vulkanHostWindowClose();
	return 1;
}

function frame(
	ref r: VulkanResources,
	ref cache: RenderPassCache,
	ref chain: Swapchain,
	ref ring: FrameRing,
	index: int32,
): int32 {
	const begun = beginFrame(r, ring);
	if (!begun.ok) { return refused(`beginFrame ${index}`, begun.error.toString()); }
	const image = acquireImage(r, chain);
	if (!image.ok) { return refused(`acquireImage ${index}`, image.error.toString()); }
	if (index < FRAMES - 1) {
		let descriptor: GPURenderPassDescriptor = { label: "swapchain clear" };
		descriptor.colorAttachments[0].view = image.value.view;
		descriptor.colorAttachments[0].loadOp = "clear";
		descriptor.colorAttachments[0].storeOp = "store";
		descriptor.colorAttachments[0].clearValue = { r: (index as float64) / (FRAMES as float64), g: 0.25, b: 0.5, a: 1.0 };
		descriptor.depthStencilAttachment.depthLoadOp = "load";
		descriptor.depthStencilAttachment.depthStoreOp = "store";
		const begin = beginRenderPass(r, cache, descriptor);
		if (!begin.ok) { return refused(`beginRenderPass ${index}`, begin.error.toString()); }
		const end = endRenderPass();
		if (!end.ok) { return refused(`endRenderPass ${index}`, end.error.toString()); }
	}
	const ended = endFrame(r, ring);
	if (!ended.ok) { return refused(`endFrame ${index}`, ended.error.toString()); }
	const shown = present(r, chain);
	if (!shown.ok && shown.error != SurfaceError.Outdated) { return refused(`present ${index}`, shown.error.toString()); }
	return 0;
}

function frames(ref r: VulkanResources): int32 {
	let chain = newSwapchain({
		format: "bgra8unorm",
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		width: WIDTH,
		height: HEIGHT,
		presentMode: "fifo",
	});
	const configured = configureSurface(r, chain);
	if (!configured.ok) { return refused("configureSurface", configured.error.toString()); }
	const firstWidth = chain.plan.width;
	const firstHeight = chain.plan.height;
	const ringOpened = openFrames(FRAMES_IN_FLIGHT);
	if (!ringOpened.ok) { return refused("openFrames", ringOpened.error.toString()); }
	let ring = ringOpened.value;
	let cache = newRenderPassCache();
	let recreated = 0;
	for (let index = 0; index < FRAMES; index++) {
		if (frame(r, cache, chain, ring, index) != 0) { return 1; }
		if (index == RESIZE_AFTER && !step("vulkanHostWindowResize", vulkanHostWindowResize(RESIZED_WIDTH, RESIZED_HEIGHT))) {
			return 1;
		}
		const changed = extentChanged(chain);
		if (!changed.ok) { return refused("extentChanged", changed.error.toString()); }
		if (changed.value || chain.suboptimal) {
			const again = configureSurface(r, chain);
			if (!again.ok) { return refused("configureSurface after resize", again.error.toString()); }
			recreated++;
		}
	}
	if (recreated == 0 || chain.plan.width != RESIZED_WIDTH || chain.plan.height != RESIZED_HEIGHT) {
		console.log(`FAIL vulkan swapchain: after the resize the swapchain is ${chain.plan.width}x${chain.plan.height} ` +
			`after ${recreated} recreations`);
		vulkanShutdown();
		vulkanHostWindowClose();
		return 1;
	}
	const released = releaseSwapchain(r, chain);
	if (!released.ok) { return refused("releaseSwapchain", released.error.toString()); }
	const dropped = releaseSurface(r, chain);
	if (!dropped.ok) { return refused("releaseSurface", dropped.error.toString()); }
	console.log(`frames: ${FRAMES} presented on ${FRAMES_IN_FLIGHT} frames in flight, ${firstWidth}x${firstHeight} ` +
		`recreated ${recreated} time(s) to ${RESIZED_WIDTH}x${RESIZED_HEIGHT}; the last frame presented unrendered; ` +
		`${cache.passes.length} render pass(es) cached`);
	return 0;
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	if (!step("vulkanHostWindowOpen", vulkanHostWindowOpen(WIDTH, HEIGHT))) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	console.log(`adapter ${vulkanAdapterName()}`);
	let r = openResources();
	if (frames(r) != 0) { return 1; }
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	vulkanHostWindowClose();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ${vulkanValidationWarnings()} warnings`);
	if (env.get("VOID_VULKAN_VALIDATION").equals("1") && !validated) {
		console.log("FAIL vulkan swapchain: VOID_VULKAN_VALIDATION=1 found no validation layer");
		return 1;
	}
	if (errors != 0) {
		console.log(`FAIL vulkan swapchain: ${errors} validation errors`);
		return 1;
	}
	console.log("PASS vulkan swapchain: cleared frames present through a resize-driven recreate");
	return 0;
}

process.exit(main());
