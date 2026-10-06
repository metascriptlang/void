// Void 2D filters (h2d.filter.Glow / DropShadow) — composite a blurred silhouette of a source
// render-target as an additive glow halo or an offset drop shadow. Built entirely on the F2
// separable blur + a silhouette-tint effect (colorMatrixAlphaOnly + colorAdd), so there is no
// filter-specific shader: the colour of the blurred source is discarded and replaced by a
// single tint, alpha-shaped by the blur. The composite draws into the currently-open pass.

import { RenderTarget } from "../gpu/target";
import { drawImage, setEffect, beginTarget, endTarget } from "./draw";
import { blurTargetPooled } from "./render";
import { colorMatrixAlphaOnly, NO_COLOR_MATRIX } from "./effect";
import { Color, premultipliedTargetTile, vec2, rgba } from "./types";
import { BlendMode } from "../gpu/state";

const zeroColor: Color = rgba(0.0, 0.0, 0.0, 0.0);
const white: Color = rgba(1.0, 1.0, 1.0, 1.0);

// Blur `src` into `dst`; `src` is left intact so the caller can still composite the sharp
// original on top. Both are `size` square.
//
// Nothing here touches the GPU. `beginTarget` brackets a region of the display list and the
// replay opens the pass, after the walk and before the swapchain pass - so this can be called
// from inside a frame without nesting a pass, which the pre-P1 version could not.
//
// The kernel is guardrail 3's, and it is literally the same code the node-filter path runs:
// downsample by 2^k, then blur at a one-texel step. Two implementations of one kernel is how
// the two paths would drift apart. The old code passed `radius / size` as the tap step, which
// put the outer taps 3.2 * radius texels away - at radius 5 that sampled 16 texels out, so it
// combed rather than blurred, and it is why the demo asked for 5 to get a 16-pixel spread.
export function blurToTarget(
	src: RenderTarget,
	dst: RenderTarget,
	radius: float32,
	size: float32,
): void {
	const px: int32 = size as int32;
	const blurred: RenderTarget = blurTargetPooled(src, px, px, radius);
	// The pooled result is smaller than `dst` by 2^k; the upscale is the linear filter doing
	// the last, widest step of the blur, which is the point of downsampling in the first place.
	beginTarget(dst, size, size, 1.0, 0.0, 0.0, zeroColor);
	drawImage(
		premultipliedTargetTile(blurred, size, size), vec2(0.0, 0.0), vec2(size, size),
		white, BlendMode.None);
	endTarget();
}

// Draw a blurred render-target `blurredRT` as a solid `color` silhouette (alpha = its blur × gain)
// at (x,y) size (w,h) with `blend`. Sets the silhouette effect, emits one quad, resets the batch
// effect. Use Add for a glow, Alpha for a drop shadow.
export function drawSilhouette(
	blurredRT: RenderTarget,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	color: Color,
	gain: float32,
	blend: BlendMode,
): void {
	setEffect(colorMatrixAlphaOnly(gain), rgba(color.r, color.g, color.b, 0.0), zeroColor);
	drawImage(
		premultipliedTargetTile(blurredRT, w, h), vec2(x, y), vec2(w, h), white, blend,
	);
	setEffect(NO_COLOR_MATRIX, zeroColor, zeroColor);
}

// Additive glow halo (no offset) — draw the sharp original on top afterwards.
export function drawGlow(
	blurredRT: RenderTarget,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	color: Color,
	gain: float32,
): void {
	drawSilhouette(blurredRT, x, y, w, h, color, gain, BlendMode.Add);
}

// Offset drop shadow (behind) — draw it first, then the sharp original on top.
export function drawDropShadow(
	blurredRT: RenderTarget,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	color: Color,
	gain: float32,
): void {
	drawSilhouette(blurredRT, x, y, w, h, color, gain, BlendMode.Alpha);
}
