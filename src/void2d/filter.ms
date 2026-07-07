// Void 2D filters (h2d.filter.Glow / DropShadow) — composite a blurred silhouette of a source
// render-target as an additive glow halo or an offset drop shadow. Built entirely on the F2
// separable blur + a silhouette-tint effect (colorMatrixAlphaOnly + colorAdd), so there is no
// filter-specific shader: the colour of the blurred source is discarded and replaced by a
// single tint, alpha-shaped by the blur. The composite draws into the currently-open pass.

import { renderTargetView, beginRenderTargetPass, endPass } from "../sokol/gpu";
import { blurPass, drawImage, setEffect } from "./draw";
import { colorMatrixAlphaOnly } from "./effect";
import { Color, BlendMode, tile, vec2, rgba } from "./types";

const zeroColor: Color = rgba(0.0, 0.0, 0.0, 0.0);
const white: Color = rgba(1.0, 1.0, 1.0, 1.0);
const noMat: float32[] = [];

// Separable blur of `src` into `dst`, ping-ponging through `tmp` — `src` is left intact so the
// caller can still composite the sharp original on top. `radius` is the per-tap offset in pixels,
// `size` the render-target dimension (both temps and dst must be `size`×`size`). Runs its own two
// RT passes, so call it between the source-render pass and the composite pass.
export function blurToTarget(src: uint32, tmp: uint32, dst: uint32, radius: float32, size: float32): void {
	const step: float32 = radius / size;
	beginRenderTargetPass(tmp, 0.0, 0.0, 0.0, 0.0);
	blurPass(renderTargetView(src), step, 0.0);
	endPass();
	beginRenderTargetPass(dst, 0.0, 0.0, 0.0, 0.0);
	blurPass(renderTargetView(tmp), 0.0, step);
	endPass();
}

// Draw a blurred render-target `blurredRT` as a solid `color` silhouette (alpha = its blur × gain)
// at (x,y) size (w,h) with `blend`. Sets the silhouette effect, emits one quad, resets the batch
// effect. Use Add for a glow, Alpha for a drop shadow.
export function drawSilhouette(blurredRT: uint32, x: float32, y: float32, w: float32, h: float32, color: Color, gain: float32, blend: BlendMode): void {
	setEffect(colorMatrixAlphaOnly(gain), rgba(color.r, color.g, color.b, 0.0), zeroColor);
	drawImage(tile(renderTargetView(blurredRT), w, h), vec2(x, y), vec2(w, h), white, blend);
	setEffect(noMat, zeroColor, zeroColor);
}

// Additive glow halo (no offset) — draw the sharp original on top afterwards.
export function drawGlow(blurredRT: uint32, x: float32, y: float32, w: float32, h: float32, color: Color, gain: float32): void {
	drawSilhouette(blurredRT, x, y, w, h, color, gain, BlendMode.Add);
}

// Offset drop shadow (behind) — draw it first, then the sharp original on top.
export function drawDropShadow(blurredRT: uint32, x: float32, y: float32, w: float32, h: float32, color: Color, gain: float32): void {
	drawSilhouette(blurredRT, x, y, w, h, color, gain, BlendMode.Alpha);
}
