// Render targets and passes, through the GPU door: the target half of h3d.mat.Texture (a
// texture allocated with TextureFlags.Target) plus the attachments + clear that Heaps splits
// between Engine.pushTargets and Engine.clear. sokol wants both at sg_begin_pass, so here they
// are one call. A target keeps its size and format, so it can be allocated again after context
// loss. Any layer draws through this (docs/VOID3D.md, "Shared with void2d").

import { Vec4 } from "../math/math3d";
import {
	PixelFormat,
	LoadAction,
	makeTargetImage,
	makeAttachmentView,
	makeTextureView,
	makeSampler,
	destroyImage,
	destroyView,
	destroySampler,
	imageAlive,
	viewAlive,
	samplerAlive,
	contextGeneration,
	beginPassWith,
	beginScreenPassWith,
	environmentColorFormat,
	environmentDepthFormat,
	environmentSampleCount,
} from "./door";
import { FilterMode, Wrap } from "./state";
import {
	DOOR_MAX_COLOR_ATTACHMENTS,
	DOOR_PASS_COLOR_VIEW,
	DOOR_PASS_COLOR_LOAD,
	DOOR_PASS_DEPTH_VIEW,
	DOOR_PASS_DEPTH_LOAD,
	DOOR_PASS_LENGTH,
	DOOR_PASS_CLEAR_DEPTH,
	DOOR_PASS_CLEAR_LENGTH,
} from "./door.h";

export struct RenderTarget {
	width: int32;
	height: int32;
	format: PixelFormat;
	sampled: boolean;
	image: uint32;
	attachment: uint32;
	texture: uint32;
	generation: int32;
}

export struct ColorAttachment {
	view: uint32;
	format: PixelFormat;
	load: LoadAction;
	clear: Vec4;
	generation: int32;
}

export struct DepthAttachment {
	view: uint32;
	format: PixelFormat;
	load: LoadAction;
	clear: float32;
	generation: int32;
}

// The attachment formats a pipeline is built for (the render-target half of Heaps'
// PipelineBuilder signature). A pipeline only draws into a pass with the same layout.
export struct TargetLayout {
	color0: PixelFormat;
	color1: PixelFormat;
	color2: PixelFormat;
	color3: PixelFormat;
	depth: PixelFormat;
	sampleCount: int32;
}

// A sampler keeps its settings for the same reason a target does.
export struct Sampler {
	filter: FilterMode;
	wrap: Wrap;
	handle: uint32;
	generation: int32;
}

export const NO_DEPTH: DepthAttachment = {
	view: 0,
	format: PixelFormat.None,
	load: LoadAction.DontCare,
	clear: 1.0,
	generation: 0,
};

const UNUSED_COLOR: ColorAttachment = {
	view: 0,
	format: PixelFormat.None,
	load: LoadAction.DontCare,
	clear: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	generation: 0,
};

// The swapchain: formats and MSAA sample count are whatever the host set up.
export const SWAPCHAIN_LAYOUT: TargetLayout = {
	color0: PixelFormat.Default,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.Default,
	sampleCount: 0,
};

const FORMAT_BITS: int32 = 4;

let passDescriptor: Vec<uint32> = new Array(DOOR_PASS_LENGTH);
let passClear: Vec<float32> = new Array(DOOR_PASS_CLEAR_LENGTH);

// A `sampled` target also gets a texture view, for a later pass to read it.
export function allocate(
	this typeof RenderTarget,
	width: int32,
	height: int32,
	format: PixelFormat,
	sampled: boolean,
): RenderTarget {
	const image: uint32 = makeTargetImage(width, height, format);
	return {
		width: width,
		height: height,
		format: format,
		sampled: sampled,
		image: image,
		attachment: makeAttachmentView(image, format),
		texture: sampled ? makeTextureView(image) : 0,
		generation: contextGeneration(),
	};
}

function stopOnOtherContext(call: string, what: string, generation: int32, remedy: string): void {
	console.log(`gpu door: ${call} on a ${what} of GPU context ${generation}; the context is now ` +
		`${contextGeneration()}, and ${remedy}`);
	unreachable;
}

function stopOnReleased(call: string, what: string): void {
	console.log(`gpu door: ${call} on a ${what} that was released`);
	unreachable;
}

function stopOnDestroyedView(call: string, view: uint32): void {
	console.log(`gpu door: ${call} on a render target whose view ${view} was destroyed`);
	unreachable;
}

function holdsLive(this target: RenderTarget, call: string): boolean {
	if (target.image == 0 || target.generation != contextGeneration()) { return false; }
	if (!imageAlive(target.image)) { stopOnReleased(call, "render target"); }
	return true;
}

export function requireCurrent(this target: RenderTarget, call: string): void {
	if (target.image == 0 || target.generation == contextGeneration()) { return; }
	stopOnOtherContext(call, "render target", target.generation, "forgotten() drops its handles");
}

function requireLive(this target: RenderTarget, call: string, view: uint32): void {
	if (target.image == 0) { return; }
	target.requireCurrent(call);
	if (!imageAlive(target.image)) { stopOnReleased(call, "render target"); }
	if (view != 0 && !viewAlive(view)) { stopOnDestroyedView(call, view); }
}

function destroyHandles(target: RenderTarget): void {
	if (target.texture != 0) { destroyView(target.texture); }
	destroyView(target.attachment);
	destroyImage(target.image);
}

export function released(this target: RenderTarget): RenderTarget {
	if (target.holdsLive("released")) { destroyHandles(target); }
	return target.forgotten();
}

// A target that knows its format but has no size or GPU objects yet; `resized` allocates it.
export function unallocated(
	this typeof RenderTarget,
	format: PixelFormat,
	sampled: boolean,
): RenderTarget {
	return {
		width: 0,
		height: 0,
		format: format,
		sampled: sampled,
		image: 0,
		attachment: 0,
		texture: 0,
		generation: 0,
	};
}

// After a context loss: the same target with its handles dropped, not destroyed (they are
// stale and may name objects of the new context). `resized` allocates it again.
export function forgotten(this target: RenderTarget): RenderTarget {
	return { ...target, image: 0, attachment: 0, texture: 0, generation: 0 };
}

// The same target at a new size; the old GPU objects are released when the size changed.
export function resized(this target: RenderTarget, width: int32, height: int32): RenderTarget {
	if (target.holdsLive("resized")) {
		if (target.width == width && target.height == height) { return target; }
		destroyHandles(target);
	}
	return RenderTarget.allocate(width, height, target.format, target.sampled);
}

export function asColor(
	this target: RenderTarget,
	load: LoadAction,
	clear: Vec4,
): ColorAttachment {
	target.requireLive("asColor", target.attachment);
	return {
		view: target.attachment,
		format: target.format,
		load: load,
		clear: clear,
		generation: target.generation,
	};
}

export function asDepth(
	this target: RenderTarget,
	load: LoadAction,
	clear: float32,
): DepthAttachment {
	target.requireLive("asDepth", target.attachment);
	return {
		view: target.attachment,
		format: target.format,
		load: load,
		clear: clear,
		generation: target.generation,
	};
}

export function asTexture(this target: RenderTarget): uint32 {
	if (target.image == 0) {
		console.log("gpu door: asTexture on a render target with no GPU objects; " +
			"resized allocates it");
		unreachable;
	}
	target.requireLive("asTexture", target.texture);
	if (target.image != 0 && target.texture == 0) {
		console.log("gpu door: asTexture on a render target allocated without a texture view");
		unreachable;
	}
	return target.texture;
}

export function create(this typeof Sampler, filter: FilterMode, wrap: Wrap): Sampler {
	return {
		filter: filter,
		wrap: wrap,
		handle: makeSampler(filter, wrap),
		generation: contextGeneration(),
	};
}

function holdsLive(this sampler: Sampler, call: string): boolean {
	if (sampler.handle == 0 || sampler.generation != contextGeneration()) { return false; }
	if (!samplerAlive(sampler.handle)) { stopOnReleased(call, "sampler"); }
	return true;
}

export function released(this sampler: Sampler): Sampler {
	if (sampler.holdsLive("released")) { destroySampler(sampler.handle); }
	return { ...sampler, handle: 0, generation: 0 };
}

export function asHandle(this sampler: Sampler): uint32 {
	if (sampler.handle == 0) {
		console.log("gpu door: asHandle on a sampler with no handle; Sampler.create makes one");
		unreachable;
	}
	if (sampler.generation != contextGeneration()) {
		stopOnOtherContext("asHandle", "sampler", sampler.generation,
			"Sampler.create makes it again");
	}
	if (!samplerAlive(sampler.handle)) { stopOnReleased("asHandle", "sampler"); }
	return sampler.handle;
}

function formatAt(colors: Span<ColorAttachment>, index: int32): PixelFormat {
	return index < (colors.length as int32) ? colors[index].format : PixelFormat.None;
}

function stopOnTooManyColors(call: string, colors: Span<ColorAttachment>): void {
	if ((colors.length as int32) <= DOOR_MAX_COLOR_ATTACHMENTS) { return; }
	console.log(`gpu door: ${call} takes at most ${DOOR_MAX_COLOR_ATTACHMENTS} color ` +
		`attachments, given ${colors.length}`);
	unreachable;
}

// Offscreen targets are single-sampled (door.c makes them with sample_count 1).
export function layoutOf(colors: Span<ColorAttachment>, depth: DepthAttachment): TargetLayout {
	stopOnTooManyColors("layoutOf", colors);
	return {
		color0: formatAt(colors, 0),
		color1: formatAt(colors, 1),
		color2: formatAt(colors, 2),
		color3: formatAt(colors, 3),
		depth: depth.format,
		sampleCount: 1,
	};
}

export function environment(this typeof TargetLayout): TargetLayout {
	return {
		color0: environmentColorFormat(),
		color1: PixelFormat.None,
		color2: PixelFormat.None,
		color3: PixelFormat.None,
		depth: environmentDepthFormat(),
		sampleCount: environmentSampleCount(),
	};
}

function resolvedFormat(format: PixelFormat, environment: PixelFormat): PixelFormat {
	return format == PixelFormat.Default ? environment : format;
}

export function resolvedIn(this layout: TargetLayout, environment: TargetLayout): TargetLayout {
	return {
		color0: resolvedFormat(layout.color0, environment.color0),
		color1: resolvedFormat(layout.color1, environment.color0),
		color2: resolvedFormat(layout.color2, environment.color0),
		color3: resolvedFormat(layout.color3, environment.color0),
		depth: resolvedFormat(layout.depth, environment.depth),
		sampleCount: layout.sampleCount == 0 ? environment.sampleCount : layout.sampleCount,
	};
}

export function namesEnvironment(this layout: TargetLayout): boolean {
	return layout.color0 == PixelFormat.Default ||
		layout.color1 == PixelFormat.Default ||
		layout.color2 == PixelFormat.Default ||
		layout.color3 == PixelFormat.Default ||
		layout.depth == PixelFormat.Default ||
		layout.sampleCount == 0;
}

export function resolved(this layout: TargetLayout): TargetLayout {
	return layout.namesEnvironment() ? layout.resolvedIn(TargetLayout.environment()) : layout;
}

function formatField(format: PixelFormat, index: int32): uint32 {
	return ((format as int32) as uint32) << ((index * FORMAT_BITS) as uint32);
}

export function formatBits(this layout: TargetLayout): uint32 {
	return formatField(layout.color0, 0) |
		formatField(layout.color1, 1) |
		formatField(layout.color2, 2) |
		formatField(layout.color3, 3) |
		formatField(layout.depth, 4) |
		((layout.sampleCount as uint32) << ((5 * FORMAT_BITS) as uint32));
}

function formatAtBits(bits: uint32, index: int32): PixelFormat {
	const mask: uint32 = ((1 as uint32) << (FORMAT_BITS as uint32)) - 1;
	const ordinal: int32 = ((bits >> ((index * FORMAT_BITS) as uint32)) & mask) as int32;
	return ordinal as PixelFormat;
}

// Reads back formatBits(), for decoding a pipeline key.
export function fromFormatBits(this typeof TargetLayout, bits: uint32): TargetLayout {
	return {
		color0: formatAtBits(bits, 0),
		color1: formatAtBits(bits, 1),
		color2: formatAtBits(bits, 2),
		color3: formatAtBits(bits, 3),
		depth: formatAtBits(bits, 4),
		sampleCount: (bits >> ((5 * FORMAT_BITS) as uint32)) as int32,
	};
}

// `colors=Rgba8,Rgba8 depth=Depth sampleCount=1`; unused color slots are left out.
export function toString(this layout: TargetLayout): string {
	let colors: string = layout.color0.toString();
	if (layout.color1 != PixelFormat.None) { colors += "," + layout.color1.toString(); }
	if (layout.color2 != PixelFormat.None) { colors += "," + layout.color2.toString(); }
	if (layout.color3 != PixelFormat.None) { colors += "," + layout.color3.toString(); }
	return `colors=${colors} depth=${layout.depth.toString()} sampleCount=${layout.sampleCount}`;
}

function stopOnEmptyAttachment(index: int32): void {
	const what: string = index < 0 ? "the depth attachment" : `color attachment ${index}`;
	console.log(`gpu door: beginPass on ${what}, which has no view; resized allocates its target`);
	unreachable;
}

function stopOnStaleAttachment(index: int32, generation: int32): void {
	const what: string = index < 0 ? "the depth attachment" : `color attachment ${index}`;
	console.log(`gpu door: beginPass on ${what} of GPU context ${generation}; the context is now ` +
		`${contextGeneration()}`);
	unreachable;
}

export function beginPass(colors: Span<ColorAttachment>, depth: DepthAttachment): void {
	stopOnTooManyColors("beginPass", colors);
	const generation: int32 = contextGeneration();
	for (let i = 0; i < (colors.length as int32); i++) {
		if (colors[i].view == 0) { stopOnEmptyAttachment(i); }
		if (colors[i].generation != generation) { stopOnStaleAttachment(i, colors[i].generation); }
	}
	if (depth.view == 0 && depth.format != PixelFormat.None) { stopOnEmptyAttachment(-1); }
	if (depth.view != 0 && depth.generation != generation) {
		stopOnStaleAttachment(-1, depth.generation);
	}
	for (let i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
		const color: ColorAttachment = i < (colors.length as int32) ? colors[i] : UNUSED_COLOR;
		passDescriptor[DOOR_PASS_COLOR_VIEW + i] = color.view;
		passDescriptor[DOOR_PASS_COLOR_LOAD + i] = (color.load as int32) as uint32;
		passClear[i * 4] = color.clear.x;
		passClear[i * 4 + 1] = color.clear.y;
		passClear[i * 4 + 2] = color.clear.z;
		passClear[i * 4 + 3] = color.clear.w;
	}
	passDescriptor[DOOR_PASS_DEPTH_VIEW] = depth.view;
	passDescriptor[DOOR_PASS_DEPTH_LOAD] = (depth.load as int32) as uint32;
	passClear[DOOR_PASS_CLEAR_DEPTH] = depth.clear;
	beginPassWith(passDescriptor, passClear);
}

// The host's swapchain, color cleared to `clear` and depth to 1; pipelines use SWAPCHAIN_LAYOUT.
export function beginScreenPass(clear: Vec4): void {
	beginScreenPassWith(clear.x, clear.y, clear.z, clear.w);
}
