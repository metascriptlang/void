import { beginWindowFrame, endWindowFrame } from "./backend.ms";
import { Swapchain, SurfaceError, acquireImage, configureSurface, newSwapchain, present, releaseSurface } from "./surface";
import { cachedCanvas } from "../validate.ms";
import { GPUTextureUsage, stop } from "../types.ms";

@passC("-I../../../deps/vulkan-headers/include");

extern function voidPresentMode(): int32;

struct Screen {
	chain: Swapchain;
	stale: boolean;
}

let screens: Vec<Screen> = [];
let frameOpen = false;
let holding: uint64 = 0;

@noinline function stopOnSurface(call: string, error: SurfaceError): never {
	match (error) {
		SurfaceError.Outdated => stop(`vulkan window: ${call} found the swapchain out of date right after recreating it`),
		SurfaceError.Lost => stop(`vulkan window: ${call} lost the surface; recreating it is not built`),
		SurfaceError.ZeroExtent => stop(`vulkan window: ${call} met a zero extent`),
		SurfaceError.OutOfMemory => stop(`vulkan window: ${call} ran out of memory`),
		SurfaceError.DeviceLost => stop(`vulkan window: ${call} lost the device; recovering it is not built`),
	};
}

function screenAt(surface: uint64, call: string): int32 {
	for (let i: int32 = 0; i < screens.length; i++) {
		if (screens[i].chain.surface == surface) { return i; }
	}
	stop(`vulkan window: ${call} on surface ${surface}, which voidVulkanSurfaceOpen did not open`);
}

function configured(ref screen: Screen, width: int32, height: int32): boolean {
	const config = screen.chain.config;
	if (screen.chain.images.length != 0 && !screen.stale && config.width == width && config.height == height) { return true; }
	screen.chain.config.format = cachedCanvas().format;
	screen.chain.config.width = width;
	screen.chain.config.height = height;
	const result = configureSurface(screen.chain);
	if (!result.ok) {
		if (result.error == SurfaceError.ZeroExtent) { return false; }
		stopOnSurface("configureSurface", result.error);
	}
	screen.stale = false;
	if (screen.chain.plan.format != screen.chain.config.format) {
		const offered: string = screen.chain.plan.format;
		const wanted: string = screen.chain.config.format;
		stop(`vulkan window: the surface offers '${offered}', not the canvas format '${wanted}' the door's pipelines are made for`);
	}
	return true;
}

@exportName("voidVulkanSurfaceOpen")
export function openSurface(surface: uint64): void {
	for (const screen of screens) {
		if (screen.chain.surface == surface) { stop(`vulkan window: surface ${surface} is already open`); }
	}
	screens.push({
		chain: newSwapchain(surface, {
			format: "bgra8unorm",
			usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
			width: 0,
			height: 0,
			presentMode: voidPresentMode() == 1 ? "immediate" : "fifo",
		}),
		stale: false,
	});
}

@exportName("voidVulkanSurfaceAwait")
export function surfaceAwait(surface: uint64, width: int32, height: int32): int32 {
	if (holding == surface) { return 1; }
	if (holding != 0) { stop(`vulkan window: surface ${surface} awaits a frame while surface ${holding} holds an image`); }
	const at = screenAt(surface, "voidVulkanSurfaceAwait");
	if (width <= 0 || height <= 0 || !configured(screens[at], width, height)) { return 0; }
	if (!frameOpen) {
		beginWindowFrame();
		frameOpen = true;
	}
	const image = acquireImage(screens[at].chain);
	if (!image.ok) {
		if (image.error == SurfaceError.ZeroExtent) { return 0; }
		stopOnSurface("acquireImage", image.error);
	}
	holding = surface;
	return 1;
}

@exportName("voidVulkanSurfacePresent")
export function surfacePresent(surface: uint64): void {
	if (holding != surface) { stop(`vulkan window: present on surface ${surface}, which holds no acquired swapchain image`); }
	const at = screenAt(surface, "voidVulkanSurfacePresent");
	endWindowFrame(screens[at].chain.images[screens[at].chain.current].image);
	frameOpen = false;
	holding = 0;
	const presented = present(screens[at].chain);
	if (!presented.ok) {
		if (presented.error != SurfaceError.Outdated) { stopOnSurface("present", presented.error); }
		screens[at].stale = true;
	}
}

@exportName("voidVulkanSurfaceView")
export function surfaceView(surface: uint64): uint64 {
	if (holding != surface) { stop(`vulkan window: the swapchain view of surface ${surface} is read outside a frame that acquired its image`); }
	const chain = screens[screenAt(surface, "voidVulkanSurfaceView")].chain;
	return chain.images[chain.current].view;
}

@exportName("voidVulkanSurfaceWidth")
export function surfaceWidth(surface: uint64): int32 { return screens[screenAt(surface, "voidVulkanSurfaceWidth")].chain.plan.width as int32; }

@exportName("voidVulkanSurfaceHeight")
export function surfaceHeight(surface: uint64): int32 { return screens[screenAt(surface, "voidVulkanSurfaceHeight")].chain.plan.height as int32; }

@exportName("voidVulkanSurfaceClose")
export function closeSurface(surface: uint64): void {
	if (holding == surface) { stop(`vulkan window: surface ${surface} closes while it holds an acquired swapchain image`); }
	const at = screenAt(surface, "voidVulkanSurfaceClose");
	let chain = screens[at].chain;
	screens.splice(at, 1);
	const released = releaseSurface(chain);
	if (!released.ok) { stopOnSurface("releaseSurface", released.error); }
}
