import {
	vulkanSurfaceCapability,
	vulkanSurfaceDestroy,
	vulkanSurfaceFormat,
	vulkanSurfaceFormatCount,
	vulkanSurfacePresentMode,
	vulkanSurfacePresentModeCount,
	vulkanSurfaceQuery,
	vulkanSwapchainAcquire,
	vulkanSwapchainCreate,
	vulkanSwapchainDestroy,
	vulkanSwapchainImage,
	vulkanSwapchainImageCount,
	vulkanSwapchainPresent,
	vulkanSwapchainView,
} from "./vulkan.h";
import { formatInfo, imageUsageFlags } from "./conv";
import {
	ResourceError,
	SwapchainImage,
	VULKAN_OK,
	VulkanResources,
	adoptSwapchainImage,
	failure,
	markAcquired,
	releaseSwapchainImage,
} from "./resources";
import { GPUTextureFormat, stop } from "../types.ms";

@passC("-I../../../deps/vulkan-headers/include");

export type PresentMode = "fifo" | "fifo-relaxed" | "immediate" | "mailbox";

export enum SurfaceError {
	Outdated,
	Lost,
	ZeroExtent,
	OutOfMemory,
	DeviceLost,
}

export const PRESENT_IMMEDIATE: uint32 = 0;
export const PRESENT_MAILBOX: uint32 = 1;
export const PRESENT_FIFO: uint32 = 2;
export const PRESENT_FIFO_RELAXED: uint32 = 3;

export const TRANSFORM_IDENTITY: uint32 = 0x1;
export const TRANSFORM_ROTATE_90: uint32 = 0x2;
export const TRANSFORM_ROTATE_180: uint32 = 0x4;
export const TRANSFORM_ROTATE_270: uint32 = 0x8;

export const ALPHA_OPAQUE: uint32 = 0x1;
export const ALPHA_PRE_MULTIPLIED: uint32 = 0x2;
export const ALPHA_POST_MULTIPLIED: uint32 = 0x4;
export const ALPHA_INHERIT: uint32 = 0x8;

export const UNDEFINED_EXTENT: uint32 = 0xFFFFFFFF;
export const COLOR_SPACE_SRGB_NONLINEAR: uint32 = 0;

const VULKAN_SUBOPTIMAL: int32 = 7;
const VULKAN_OUT_OF_DATE: int32 = 8;
const VULKAN_SURFACE_LOST: int32 = 9;

export struct SurfaceCaps {
	minImages: uint32;
	maxImages: uint32;
	currentWidth: uint32;
	currentHeight: uint32;
	minWidth: uint32;
	minHeight: uint32;
	maxWidth: uint32;
	maxHeight: uint32;
	currentTransform: uint32;
	transforms: uint32;
	compositeAlpha: uint32;
	usage: uint32;
}

export struct SurfaceFormat {
	native: int32;
	colorSpace: uint32;
}

export struct SurfaceInfo {
	caps: SurfaceCaps;
	formats: Vec<SurfaceFormat>;
	presentModes: Vec<uint32>;
}

export struct SurfaceConfig {
	format: GPUTextureFormat;
	usage: int32;
	width: int32;
	height: int32;
	presentMode: PresentMode;
}

export struct SwapchainPlan {
	format: GPUTextureFormat;
	native: int32;
	colorSpace: uint32;
	width: uint32;
	height: uint32;
	imageCount: uint32;
	usage: uint32;
	preTransform: uint32;
	rotation: int32;
	compositeAlpha: uint32;
	presentMode: uint32;
}

export struct Swapchain {
	config: SurfaceConfig;
	plan: SwapchainPlan;
	images: Vec<SwapchainImage>;
	current: int32;
	suboptimal: boolean;
}

function surfaceFailure(code: int32): SurfaceError {
	if (code == VULKAN_OUT_OF_DATE) { return SurfaceError.Outdated; }
	if (code == VULKAN_SURFACE_LOST) { return SurfaceError.Lost; }
	return match (failure(code)) {
		ResourceError.OutOfMemory => SurfaceError.OutOfMemory,
		ResourceError.DeviceLost => SurfaceError.DeviceLost,
	};
}

function surfaceChecked(code: int32): Result<void, SurfaceError> {
	if (code != VULKAN_OK) { return Result.err(surfaceFailure(code)); }
	return Result.ok(null);
}

function swappedOrder(format: GPUTextureFormat): GPUTextureFormat {
	if (format == "rgba8unorm") { return "bgra8unorm"; }
	if (format == "bgra8unorm") { return "rgba8unorm"; }
	if (format == "rgba8unorm-srgb") { return "bgra8unorm-srgb"; }
	if (format == "bgra8unorm-srgb") { return "rgba8unorm-srgb"; }
	const value: string = format;
	stop(`GPUCanvasConfiguration.format '${value}' is not a swapchain format: use rgba8unorm, bgra8unorm or their -srgb forms`);
}

function listed(formats: Readonly<Span<SurfaceFormat>>, native: int32): boolean {
	for (const entry of formats) {
		if (entry.native == native && entry.colorSpace == COLOR_SPACE_SRGB_NONLINEAR) { return true; }
	}
	return false;
}

export function chooseFormat(formats: Readonly<Span<SurfaceFormat>>, wanted: GPUTextureFormat): GPUTextureFormat {
	const other = swappedOrder(wanted);
	if (listed(formats, formatInfo(wanted, 0, "GPUCanvasConfiguration.format").native)) { return wanted; }
	if (listed(formats, formatInfo(other, 0, "GPUCanvasConfiguration.format").native)) { return other; }
	const value: string = wanted;
	stop(`GPUCanvasConfiguration.format '${value}' is not supported by the surface, nor is its swapped channel order`);
}

function presentModeCode(mode: PresentMode): uint32 {
	const value: string = mode;
	const code = match (value) {
		"immediate" => PRESENT_IMMEDIATE as int32,
		"mailbox" => PRESENT_MAILBOX as int32,
		"fifo-relaxed" => PRESENT_FIFO_RELAXED as int32,
		"fifo" => PRESENT_FIFO as int32,
		_ => { stop(`present mode '${value}' is not supported`); },
	};
	return code as uint32;
}

export function choosePresentMode(modes: Readonly<Span<uint32>>, wanted: PresentMode): uint32 {
	const fallbacks: uint32[4] = [PRESENT_IMMEDIATE, PRESENT_MAILBOX, PRESENT_FIFO_RELAXED, PRESENT_FIFO];
	const target = presentModeCode(wanted);
	let index: int32 = 0;
	while (fallbacks[index] != target) { index++; }
	while (index < 4) {
		for (const mode of modes) {
			if (mode == fallbacks[index]) { return mode; }
		}
		index++;
	}
	stop("the surface lists no FIFO present mode, which every Vulkan surface must support");
}

export function chooseImageCount(caps: SurfaceCaps, presentMode: uint32): uint32 {
	let count: uint32 = presentMode == PRESENT_MAILBOX ? 3 : 2;
	if (count < caps.minImages) { count = caps.minImages; }
	if (caps.maxImages != 0 && count > caps.maxImages) { count = caps.maxImages; }
	return count;
}

function clamp(value: uint32, low: uint32, high: uint32): uint32 {
	return value < low ? low : (value > high ? high : value);
}

export function rotationDegrees(transform: uint32): int32 {
	if (transform == TRANSFORM_ROTATE_90) { return 90; }
	if (transform == TRANSFORM_ROTATE_180) { return 180; }
	if (transform == TRANSFORM_ROTATE_270) { return 270; }
	return 0;
}

export function chooseCompositeAlpha(supported: uint32): uint32 {
	const order: uint32[4] = [ALPHA_OPAQUE, ALPHA_PRE_MULTIPLIED, ALPHA_POST_MULTIPLIED, ALPHA_INHERIT];
	for (let i: int32 = 0; i < 4; i++) {
		if ((supported & order[i]) != 0) { return order[i]; }
	}
	stop(`the surface supports no composite alpha mode (flags ${supported})`);
}

export function planSwapchain(info: SurfaceInfo, config: SurfaceConfig): Result<SwapchainPlan, SurfaceError> {
	const caps = info.caps;
	const format = chooseFormat(info.formats, config.format);
	const usage = imageUsageFlags(config.usage, false);
	if ((usage & ~caps.usage) != 0) {
		stop(`GPUCanvasConfiguration.usage ${config.usage} needs image usage ${usage}, beyond the surface's ${caps.usage}`);
	}
	let width = caps.currentWidth;
	let height = caps.currentHeight;
	if (width == UNDEFINED_EXTENT) {
		width = clamp(config.width as uint32, caps.minWidth, caps.maxWidth);
		height = clamp(config.height as uint32, caps.minHeight, caps.maxHeight);
	} else if ((caps.currentTransform & (TRANSFORM_ROTATE_90 | TRANSFORM_ROTATE_270)) != 0) {
		width = caps.currentHeight;
		height = caps.currentWidth;
	}
	if (width == 0 || height == 0) { return Result.err(SurfaceError.ZeroExtent); }
	const presentMode = choosePresentMode(info.presentModes, config.presentMode);
	return Result.ok({
		format: format,
		native: formatInfo(format, 0, "GPUCanvasConfiguration.format").native,
		colorSpace: COLOR_SPACE_SRGB_NONLINEAR,
		width: width,
		height: height,
		imageCount: chooseImageCount(caps, presentMode),
		usage: usage,
		preTransform: caps.currentTransform,
		rotation: rotationDegrees(caps.currentTransform),
		compositeAlpha: chooseCompositeAlpha(caps.compositeAlpha),
		presentMode: presentMode,
	});
}

export function querySurface(): Result<SurfaceInfo, SurfaceError> {
	try surfaceChecked(vulkanSurfaceQuery());
	let info: SurfaceInfo = {
		caps: {
			minImages: vulkanSurfaceCapability(0),
			maxImages: vulkanSurfaceCapability(1),
			currentWidth: vulkanSurfaceCapability(2),
			currentHeight: vulkanSurfaceCapability(3),
			minWidth: vulkanSurfaceCapability(4),
			minHeight: vulkanSurfaceCapability(5),
			maxWidth: vulkanSurfaceCapability(6),
			maxHeight: vulkanSurfaceCapability(7),
			currentTransform: vulkanSurfaceCapability(8),
			transforms: vulkanSurfaceCapability(9),
			compositeAlpha: vulkanSurfaceCapability(10),
			usage: vulkanSurfaceCapability(11),
		},
		formats: [],
		presentModes: [],
	};
	for (let i: int32 = 0; i < vulkanSurfaceFormatCount(); i++) {
		let native: int32 = 0;
		let colorSpace: uint32 = 0;
		try surfaceChecked(vulkanSurfaceFormat(i, native, colorSpace));
		info.formats.push({ native: native, colorSpace: colorSpace });
	}
	for (let i: int32 = 0; i < vulkanSurfacePresentModeCount(); i++) { info.presentModes.push(vulkanSurfacePresentMode(i)); }
	return Result.ok(info);
}

export function newSwapchain(config: SurfaceConfig): Swapchain {
	return {
		config: config,
		plan: {
			format: config.format,
			native: 0,
			colorSpace: 0,
			width: 0,
			height: 0,
			imageCount: 0,
			usage: 0,
			preTransform: 0,
			rotation: 0,
			compositeAlpha: 0,
			presentMode: 0,
		},
		images: [],
		current: -1,
		suboptimal: false,
	};
}

function dropImages(ref r: VulkanResources, ref chain: Swapchain): void {
	for (const image of chain.images) { releaseSwapchainImage(r, image); }
	chain.images.length = 0;
	chain.current = -1;
}

export function configureSurface(ref r: VulkanResources, ref chain: Swapchain): Result<void, SurfaceError> {
	const info = try querySurface();
	const plan = try planSwapchain(info, chain.config);
	dropImages(r, chain);
	try surfaceChecked(vulkanSwapchainCreate(
		plan.native,
		plan.colorSpace,
		plan.width,
		plan.height,
		plan.imageCount,
		plan.usage,
		plan.preTransform,
		plan.compositeAlpha,
		plan.presentMode,
	));
	chain.plan = plan;
	chain.suboptimal = false;
	for (let i: uint32 = 0; i < vulkanSwapchainImageCount(); i++) {
		const image = adoptSwapchainImage(
			r,
			vulkanSwapchainImage(i),
			vulkanSwapchainView(i),
			plan.format,
			plan.width as int32,
			plan.height as int32,
		);
		chain.images.push(image);
	}
	return Result.ok(null);
}

export function extentChanged(chain: Swapchain): Result<boolean, SurfaceError> {
	const info = try querySurface();
	if (info.caps.currentWidth == UNDEFINED_EXTENT) { return Result.ok(false); }
	const plan = try planSwapchain(info, chain.config);
	return Result.ok(plan.width != chain.plan.width || plan.height != chain.plan.height);
}

function acquireOnce(ref r: VulkanResources, ref chain: Swapchain): int32 {
	let index: uint32 = 0;
	const code = vulkanSwapchainAcquire(index);
	if (code == VULKAN_OK || code == VULKAN_SUBOPTIMAL) {
		chain.current = index as int32;
		chain.suboptimal = code == VULKAN_SUBOPTIMAL;
		markAcquired(r, chain.images[index as int32]);
	}
	return code;
}

export function acquireImage(ref r: VulkanResources, ref chain: Swapchain): Result<SwapchainImage, SurfaceError> {
	let code = acquireOnce(r, chain);
	if (code == VULKAN_OUT_OF_DATE) {
		try configureSurface(r, chain);
		code = acquireOnce(r, chain);
	}
	if (code == VULKAN_OK || code == VULKAN_SUBOPTIMAL) { return Result.ok(chain.images[chain.current]); }
	if (code == VULKAN_SURFACE_LOST) { try releaseSurface(r, chain); }
	return Result.err(surfaceFailure(code));
}

export function present(ref r: VulkanResources, ref chain: Swapchain): Result<void, SurfaceError> {
	const code = vulkanSwapchainPresent();
	chain.current = -1;
	if (code == VULKAN_OK) { return Result.ok(null); }
	if (code == VULKAN_SUBOPTIMAL) {
		chain.suboptimal = true;
		return Result.ok(null);
	}
	if (code == VULKAN_SURFACE_LOST) { try releaseSurface(r, chain); }
	return Result.err(surfaceFailure(code));
}

export function releaseSwapchain(ref r: VulkanResources, ref chain: Swapchain): Result<void, SurfaceError> {
	if (chain.images.length == 0) { return Result.ok(null); }
	dropImages(r, chain);
	return surfaceChecked(vulkanSwapchainDestroy());
}

export function releaseSurface(ref r: VulkanResources, ref chain: Swapchain): Result<void, SurfaceError> {
	dropImages(r, chain);
	return surfaceChecked(vulkanSurfaceDestroy());
}
