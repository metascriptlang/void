// Render targets and passes: the target half of h3d.mat.Texture (a texture allocated with
// TextureFlags.Target) plus the attachments + clear that Heaps splits between
// Engine.pushTargets and Engine.clear. sokol wants both at sg_begin_pass, so here they are one
// call. A target keeps its size and format, so it can be allocated again after context loss.

import { Vec4 } from "../math/math3d";
import {
	PixelFormat,
	LoadAction,
	Filter,
	Wrap,
	makeTargetImage,
	makeAttachmentView,
	makeTextureView,
	makeSampler,
	destroyImage,
	destroyView,
	destroySampler,
	beginPassWith,
	beginSwapchainPass,
} from "./gpu3d";
import {
	GPU3D_MAX_COLOR_ATTACHMENTS,
	GPU3D_PASS_COLOR_VIEW,
	GPU3D_PASS_COLOR_LOAD,
	GPU3D_PASS_DEPTH_VIEW,
	GPU3D_PASS_DEPTH_LOAD,
	GPU3D_PASS_LENGTH,
	GPU3D_PASS_CLEAR_DEPTH,
	GPU3D_PASS_CLEAR_LENGTH,
} from "./gpu3d.h";

export struct RenderTarget {
	width: int32;
	height: int32;
	format: PixelFormat;
	sampled: boolean;
	image: uint32;
	attachment: uint32;
	texture: uint32;
}

export struct ColorAttachment {
	view: uint32;
	format: PixelFormat;
	load: LoadAction;
	clear: Vec4;
}

export struct DepthAttachment {
	view: uint32;
	format: PixelFormat;
	load: LoadAction;
	clear: float32;
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
	filter: Filter;
	wrap: Wrap;
	handle: uint32;
}

export const NO_DEPTH: DepthAttachment = {
	view: 0,
	format: PixelFormat.None,
	load: LoadAction.DontCare,
	clear: 1.0,
};

const UNUSED_COLOR: ColorAttachment = {
	view: 0,
	format: PixelFormat.None,
	load: LoadAction.DontCare,
	clear: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
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

const passDescriptor: Vec<uint32> = new Array(GPU3D_PASS_LENGTH);
const passClear: Vec<float32> = new Array(GPU3D_PASS_CLEAR_LENGTH);

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
	};
}

export function release(this target: RenderTarget): void {
	if (target.texture != 0) { destroyView(target.texture); }
	destroyView(target.attachment);
	destroyImage(target.image);
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
	};
}

// After a context loss: the same target with its handles dropped, not destroyed (they are
// stale and may name objects of the new context). `resized` allocates it again.
export function forgotten(this target: RenderTarget): RenderTarget {
	return { ...target, image: 0, attachment: 0, texture: 0 };
}

// The same target at a new size; the old GPU objects are released when the size changed.
export function resized(this target: RenderTarget, width: int32, height: int32): RenderTarget {
	if (target.image != 0 && target.width == width && target.height == height) {
		return target;
	}
	if (target.image != 0) { target.release(); }
	return RenderTarget.allocate(width, height, target.format, target.sampled);
}

export function asColor(
	this target: RenderTarget,
	load: LoadAction,
	clear: Vec4,
): ColorAttachment {
	return { view: target.attachment, format: target.format, load: load, clear: clear };
}

export function asDepth(
	this target: RenderTarget,
	load: LoadAction,
	clear: float32,
): DepthAttachment {
	return { view: target.attachment, format: target.format, load: load, clear: clear };
}

export function create(this typeof Sampler, filter: Filter, wrap: Wrap): Sampler {
	return { filter: filter, wrap: wrap, handle: makeSampler(filter, wrap) };
}

export function release(this sampler: Sampler): void {
	destroySampler(sampler.handle);
}

function formatAt(colors: Span<ColorAttachment>, index: int32): PixelFormat {
	return index < (colors.length as int32) ? colors[index].format : PixelFormat.None;
}

// Offscreen targets are single-sampled (gpu3d.c makes them with sample_count 1).
export function layoutOf(colors: Span<ColorAttachment>, depth: DepthAttachment): TargetLayout {
	return {
		color0: formatAt(colors, 0),
		color1: formatAt(colors, 1),
		color2: formatAt(colors, 2),
		color3: formatAt(colors, 3),
		depth: depth.format,
		sampleCount: 1,
	};
}

function formatField(format: PixelFormat, index: int32): uint32 {
	return ((format as int32) as uint32) << ((index * FORMAT_BITS) as uint32);
}

// 4 bits per format, then the sample count: 24 bits.
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

// sg_begin_pass on up to four color attachments and an optional depth attachment.
export function beginPass(colors: Span<ColorAttachment>, depth: DepthAttachment): void {
	for (let i = 0; i < GPU3D_MAX_COLOR_ATTACHMENTS; i++) {
		const color: ColorAttachment = i < (colors.length as int32) ? colors[i] : UNUSED_COLOR;
		passDescriptor[GPU3D_PASS_COLOR_VIEW + i] = color.view;
		passDescriptor[GPU3D_PASS_COLOR_LOAD + i] = (color.load as int32) as uint32;
		passClear[i * 4] = color.clear.x;
		passClear[i * 4 + 1] = color.clear.y;
		passClear[i * 4 + 2] = color.clear.z;
		passClear[i * 4 + 3] = color.clear.w;
	}
	passDescriptor[GPU3D_PASS_DEPTH_VIEW] = depth.view;
	passDescriptor[GPU3D_PASS_DEPTH_LOAD] = (depth.load as int32) as uint32;
	passClear[GPU3D_PASS_CLEAR_DEPTH] = depth.clear;
	beginPassWith(passDescriptor, passClear);
}

// The host's swapchain, color cleared to `clear` and depth to 1; pipelines use SWAPCHAIN_LAYOUT.
export function beginScreenPass(clear: Vec4): void {
	beginSwapchainPass(clear.x, clear.y, clear.z, clear.w);
}
