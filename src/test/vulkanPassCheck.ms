import { GPUTextureUsage } from "../webgpu/types.ms";
import {
	ACCESS_COLOR_ATTACHMENT_READ,
	ACCESS_COLOR_ATTACHMENT_WRITE,
	ASPECT_COLOR,
	LAYOUT_COLOR_ATTACHMENT,
	LAYOUT_PRESENT,
	LOAD_OP_CLEAR,
	LOAD_OP_DONT_CARE,
	LOAD_OP_LOAD,
	STAGE_COLOR_ATTACHMENT_OUTPUT,
	STORE_OP_DONT_CARE,
	STORE_OP_STORE,
	swapchainRest,
	textureRest,
} from "../webgpu/vulkan/conv";
import { LAYOUT_UNDEFINED, acquireTexture, cleared, endPass, newTracker, writeToTexture } from "../webgpu/vulkan/tracker";
import {
	COLOR_KEY_WORDS,
	DEPTH_KEY_WORDS,
	cachedPass,
	colorKeyWords,
	depthKeyWords,
	newPassKey,
	newRenderPassCache,
	noDepthKeyWords,
	rememberPass,
} from "../webgpu/vulkan/pass";
import {
	ALPHA_INHERIT,
	ALPHA_OPAQUE,
	ALPHA_POST_MULTIPLIED,
	PRESENT_FIFO,
	PRESENT_FIFO_RELAXED,
	PRESENT_IMMEDIATE,
	PRESENT_MAILBOX,
	SurfaceCaps,
	SurfaceConfig,
	SurfaceError,
	SurfaceInfo,
	TRANSFORM_IDENTITY,
	TRANSFORM_ROTATE_270,
	TRANSFORM_ROTATE_90,
	UNDEFINED_EXTENT,
	chooseCompositeAlpha,
	chooseFormat,
	chooseImageCount,
	choosePresentMode,
	planSwapchain,
	rotationDegrees,
} from "../webgpu/vulkan/surface";
import { frameSubmitted, newFrameRing, reuseSerial, slot } from "../webgpu/vulkan/frame";

const RGBA8: int32 = 37;
const BGRA8: int32 = 44;
const BGRA8_SRGB: int32 = 50;
const D24S8: int32 = 129;
const D32: int32 = 126;
const COLOR_ACCESS: uint32 = ACCESS_COLOR_ATTACHMENT_READ | ACCESS_COLOR_ATTACHMENT_WRITE;

function caps(width: uint32, height: uint32, transform: uint32): SurfaceCaps {
	return {
		minImages: 2,
		maxImages: 8,
		currentWidth: width,
		currentHeight: height,
		minWidth: 16,
		minHeight: 16,
		maxWidth: 4096,
		maxHeight: 4096,
		currentTransform: transform,
		transforms: TRANSFORM_IDENTITY | TRANSFORM_ROTATE_90 | TRANSFORM_ROTATE_270,
		compositeAlpha: ALPHA_OPAQUE,
		usage: 0x10,
	};
}

function surface(width: uint32, height: uint32, transform: uint32): SurfaceInfo {
	return {
		caps: caps(width, height, transform),
		formats: [{ native: BGRA8, colorSpace: 0 }, { native: BGRA8_SRGB, colorSpace: 0 }],
		presentModes: [PRESENT_FIFO, PRESENT_MAILBOX],
	};
}

test "a render pass key holds each color's five words and eight depth words" {
	let key = newPassKey();
	colorKeyWords(key, RGBA8, 1, LOAD_OP_CLEAR, STORE_OP_STORE, 0);
	colorKeyWords(key, BGRA8, 4, LOAD_OP_LOAD, STORE_OP_DONT_CARE, BGRA8);
	noDepthKeyWords(key);
	assert key[0] == 2;
	assert key.length == 1 + 2 * COLOR_KEY_WORDS + DEPTH_KEY_WORDS;
	assert key[1] == (RGBA8 as uint32) && key[3] == LOAD_OP_CLEAR && key[5] == 0;
	assert key[6] == (BGRA8 as uint32) && key[7] == 4 && key[9] == STORE_OP_DONT_CARE && key[10] == (BGRA8 as uint32);
	assert key[11] == 0;
}

test "stencil ops follow the depth ops only when the format has stencil" {
	let stencil = newPassKey();
	depthKeyWords(stencil, D24S8, 1, LOAD_OP_CLEAR, STORE_OP_STORE, true, false);
	assert stencil[1] == 1 && stencil[6] == LOAD_OP_CLEAR && stencil[7] == STORE_OP_STORE && stencil[8] == 0;
	let depthOnly = newPassKey();
	depthKeyWords(depthOnly, D32, 1, LOAD_OP_CLEAR, STORE_OP_STORE, false, true);
	assert depthOnly[6] == LOAD_OP_DONT_CARE && depthOnly[7] == STORE_OP_DONT_CARE && depthOnly[8] == 1;
}

test "the render pass cache answers an equal key and misses a key differing in one op" {
	let cache = newRenderPassCache();
	let clear = newPassKey();
	colorKeyWords(clear, RGBA8, 1, LOAD_OP_CLEAR, STORE_OP_STORE, 0);
	noDepthKeyWords(clear);
	let load = newPassKey();
	colorKeyWords(load, RGBA8, 1, LOAD_OP_LOAD, STORE_OP_STORE, 0);
	noDepthKeyWords(load);
	assert cache.cachedPass(clear) == 0;
	rememberPass(cache, clear, 7);
	let again = newPassKey();
	colorKeyWords(again, RGBA8, 1, LOAD_OP_CLEAR, STORE_OP_STORE, 0);
	noDepthKeyWords(again);
	assert cache.cachedPass(again) == 7;
	assert cache.cachedPass(load) == 0;
	rememberPass(cache, load, 9);
	assert cache.cachedPass(load) == 9 && cache.passes.length == 2;
}

test "present modes fall back immediate, mailbox, fifo-relaxed, fifo as Dawn does" {
	const fifoOnly: Vec<uint32> = [PRESENT_FIFO];
	const mailbox: Vec<uint32> = [PRESENT_FIFO, PRESENT_MAILBOX];
	const relaxed: Vec<uint32> = [PRESENT_FIFO_RELAXED, PRESENT_FIFO];
	const all: Vec<uint32> = [PRESENT_FIFO, PRESENT_IMMEDIATE, PRESENT_MAILBOX];
	assert choosePresentMode(mailbox, "fifo") == PRESENT_FIFO;
	assert choosePresentMode(mailbox, "mailbox") == PRESENT_MAILBOX;
	assert choosePresentMode(fifoOnly, "mailbox") == PRESENT_FIFO;
	assert choosePresentMode(mailbox, "immediate") == PRESENT_MAILBOX;
	assert choosePresentMode(all, "immediate") == PRESENT_IMMEDIATE;
	assert choosePresentMode(relaxed, "immediate") == PRESENT_FIFO_RELAXED;
	assert choosePresentMode(mailbox, "fifo-relaxed") == PRESENT_FIFO;
}

test "the image count is two, three for mailbox, clamped to the surface's range" {
	let c = caps(64, 48, TRANSFORM_IDENTITY);
	assert chooseImageCount(c, PRESENT_FIFO) == 2;
	assert chooseImageCount(c, PRESENT_MAILBOX) == 3;
	c.minImages = 3;
	assert chooseImageCount(c, PRESENT_FIFO) == 3;
	c.minImages = 1;
	c.maxImages = 2;
	assert chooseImageCount(c, PRESENT_MAILBOX) == 2;
	c.maxImages = 0;
	c.minImages = 5;
	assert chooseImageCount(c, PRESENT_MAILBOX) == 5;
}

test "the format is the one asked, else its other channel order, keeping srgb" {
	const formats = surface(64, 48, TRANSFORM_IDENTITY).formats;
	assert chooseFormat(formats, "bgra8unorm") == "bgra8unorm";
	assert chooseFormat(formats, "rgba8unorm") == "bgra8unorm";
	assert chooseFormat(formats, "rgba8unorm-srgb") == "bgra8unorm-srgb";
}

test "the extent is the surface's current one, the asked one clamped when undefined, swapped when rotated" {
	const config: SurfaceConfig = {
		format: "bgra8unorm",
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		width: 8,
		height: 9000,
		presentMode: "fifo",
	};
	const current = planSwapchain(surface(640, 480, TRANSFORM_IDENTITY), config);
	assert current.ok && current.value.width == 640 && current.value.height == 480 && current.value.rotation == 0;
	const undefinedExtent = planSwapchain(surface(UNDEFINED_EXTENT, UNDEFINED_EXTENT, TRANSFORM_IDENTITY), config);
	assert undefinedExtent.ok && undefinedExtent.value.width == 16 && undefinedExtent.value.height == 4096;
	const rotated = planSwapchain(surface(640, 480, TRANSFORM_ROTATE_90), config);
	assert rotated.ok && rotated.value.width == 480 && rotated.value.height == 640;
	assert rotated.value.preTransform == TRANSFORM_ROTATE_90 && rotated.value.rotation == 90;
	const minimized = planSwapchain(surface(0, 0, TRANSFORM_IDENTITY), config);
	assert !minimized.ok && minimized.error == SurfaceError.ZeroExtent;
}

test "composite alpha takes opaque, pre, post, inherit in that order; rotation reads the transform" {
	assert chooseCompositeAlpha(ALPHA_INHERIT | ALPHA_OPAQUE) == ALPHA_OPAQUE;
	assert chooseCompositeAlpha(ALPHA_INHERIT | ALPHA_POST_MULTIPLIED) == ALPHA_POST_MULTIPLIED;
	assert chooseCompositeAlpha(ALPHA_INHERIT) == ALPHA_INHERIT;
	assert rotationDegrees(TRANSFORM_ROTATE_270) == 270;
	assert rotationDegrees(TRANSFORM_IDENTITY) == 0;
}

test "the frame ring reuses a slot only after the serial submitted two frames earlier" {
	let ring = newFrameRing(2);
	assert ring.slot() == 0 && ring.reuseSerial() == 0;
	frameSubmitted(ring, 5);
	assert ring.slot() == 1 && ring.reuseSerial() == 0;
	frameSubmitted(ring, 9);
	assert ring.slot() == 0 && ring.reuseSerial() == 5;
	frameSubmitted(ring, 12);
	assert ring.slot() == 1 && ring.reuseSerial() == 9;
}

test "a second write in an unchanged layout carries the first write's access as a memory dependency" {
	let t = newTracker();
	const rest = textureRest((GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32), ASPECT_COLOR);
	assert rest.layout == LAYOUT_COLOR_ATTACHMENT;
	writeToTexture(t, 3, rest, STAGE_COLOR_ATTACHMENT_OUTPUT, COLOR_ACCESS, LAYOUT_COLOR_ATTACHMENT);
	assert t.images.length == 0 && t.targetAccess == COLOR_ACCESS;
	cleared(t);
	writeToTexture(t, 3, rest, STAGE_COLOR_ATTACHMENT_OUTPUT, COLOR_ACCESS, LAYOUT_COLOR_ATTACHMENT);
	assert t.images.length == 0;
	assert t.sourceStages == STAGE_COLOR_ATTACHMENT_OUTPUT;
	assert t.sourceAccess == COLOR_ACCESS && t.targetAccess == COLOR_ACCESS;
	cleared(t);
	endPass(t);
	assert t.images.length == 0;
	assert t.sourceAccess == COLOR_ACCESS && t.targetAccess == rest.access;
}

test "an acquired swapchain image leaves undefined for the attachment, then returns to present" {
	let t = newTracker();
	const rest = swapchainRest();
	acquireTexture(t, 4, rest);
	writeToTexture(t, 4, rest, STAGE_COLOR_ATTACHMENT_OUTPUT, COLOR_ACCESS, LAYOUT_COLOR_ATTACHMENT);
	assert t.images.length == 1;
	assert t.images[0].oldLayout == LAYOUT_UNDEFINED && t.images[0].newLayout == LAYOUT_COLOR_ATTACHMENT;
	assert t.images[0].sourceAccess == 0 && t.sourceStages == STAGE_COLOR_ATTACHMENT_OUTPUT;
	cleared(t);
	endPass(t);
	assert t.images.length == 1;
	assert t.images[0].oldLayout == LAYOUT_COLOR_ATTACHMENT && t.images[0].newLayout == LAYOUT_PRESENT;
	assert t.images[0].sourceAccess == COLOR_ACCESS && t.images[0].targetAccess == 0;
	cleared(t);
	acquireTexture(t, 4, rest);
	endPass(t);
	assert t.images.length == 1;
	assert t.images[0].oldLayout == LAYOUT_UNDEFINED && t.images[0].newLayout == LAYOUT_PRESENT;
}
