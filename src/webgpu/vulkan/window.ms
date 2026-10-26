import { beginWindowFrame, endWindowFrame } from "./backend.ms";
import { Swapchain, SurfaceError, acquireImage, configureSurface, newSwapchain, present } from "./surface";
import { cachedCanvas } from "../validate.ms";
import { GPUTextureUsage, stop } from "../types.ms";

@passC("-I../../../deps/vulkan-headers/include");

let chain: Swapchain = newSwapchain({
	format: "bgra8unorm",
	usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
	width: 0,
	height: 0,
	presentMode: "fifo",
});
let frameOpen = false;
let holding = false;
let stale = false;

@noinline function stopOnSurface(call: string, error: SurfaceError): never {
	match (error) {
		SurfaceError.Outdated => stop(`vulkan window: ${call} found the swapchain out of date right after recreating it`),
		SurfaceError.Lost => stop(`vulkan window: ${call} lost the surface; recreating it is not built`),
		SurfaceError.ZeroExtent => stop(`vulkan window: ${call} met a zero extent`),
		SurfaceError.OutOfMemory => stop(`vulkan window: ${call} ran out of memory`),
		SurfaceError.DeviceLost => stop(`vulkan window: ${call} lost the device; recovering it is not built`),
	};
}

function configured(width: int32, height: int32): boolean {
	if (chain.images.length != 0 && !stale && chain.config.width == width && chain.config.height == height) { return true; }
	chain.config.format = cachedCanvas().format;
	chain.config.width = width;
	chain.config.height = height;
	const result = configureSurface(chain);
	if (!result.ok) {
		if (result.error == SurfaceError.ZeroExtent) { return false; }
		stopOnSurface("configureSurface", result.error);
	}
	stale = false;
	if (chain.plan.format != chain.config.format) {
		const offered: string = chain.plan.format;
		const wanted: string = chain.config.format;
		stop(`vulkan window: the surface offers '${offered}', not the canvas format '${wanted}' the door's pipelines are made for`);
	}
	return true;
}

@exportName("voidVulkanWindowAwait")
export function windowAwait(width: int32, height: int32): int32 {
	if (holding) { return 1; }
	if (width <= 0 || height <= 0 || !configured(width, height)) { return 0; }
	if (!frameOpen) {
		beginWindowFrame();
		frameOpen = true;
	}
	const image = acquireImage(chain);
	if (!image.ok) {
		if (image.error == SurfaceError.ZeroExtent) { return 0; }
		stopOnSurface("acquireImage", image.error);
	}
	holding = true;
	return 1;
}

@exportName("voidVulkanWindowPresent")
export function windowPresent(): void {
	if (!holding) { stop("vulkan window: present without an acquired swapchain image"); }
	endWindowFrame(chain.images[chain.current].image);
	frameOpen = false;
	holding = false;
	const presented = present(chain);
	if (!presented.ok) {
		if (presented.error != SurfaceError.Outdated) { stopOnSurface("present", presented.error); }
		stale = true;
	}
}

@exportName("voidVulkanWindowView")
export function windowView(): uint64 {
	if (!holding) { stop("vulkan window: the swapchain view is read outside a frame that acquired an image"); }
	return chain.images[chain.current].view;
}

@exportName("voidVulkanWindowWidth")
export function windowWidth(): int32 { return chain.plan.width as int32; }

@exportName("voidVulkanWindowHeight")
export function windowHeight(): int32 { return chain.plan.height as int32; }

@exportName("voidVulkanWindowClose")
export function windowClose(): void {
	chain = newSwapchain(chain.config);
	frameOpen = false;
	holding = false;
	stale = false;
}
