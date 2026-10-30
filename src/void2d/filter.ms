import { RenderTarget } from "../gpu/target";
import { drawImage, setEffect, beginTarget, endTarget } from "./draw";
import { blurTargetPooled } from "./render";
import { colorMatrixAlphaOnly, NO_COLOR_MATRIX } from "./effect";
import { Color, premultipliedTargetTile, vec2, rgba } from "./types";
import { BlendMode } from "../gpu/state";

const CLEAR: Color = rgba(0.0, 0.0, 0.0, 0.0);
const WHITE: Color = rgba(1.0, 1.0, 1.0, 1.0);

export function blurToTarget(
	src: RenderTarget,
	dst: RenderTarget,
	radius: float32,
	size: float32,
): void {
	const px: int32 = size as int32;
	const blurred: RenderTarget = blurTargetPooled(src, px, px, radius);
	beginTarget(dst, size, size, 1.0, 0.0, 0.0, CLEAR);
	drawImage(
		premultipliedTargetTile(blurred, size, size), vec2(0.0, 0.0), vec2(size, size),
		WHITE, BlendMode.None);
	endTarget();
}

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
	setEffect(colorMatrixAlphaOnly(gain), rgba(color.r, color.g, color.b, 0.0), CLEAR);
	drawImage(
		premultipliedTargetTile(blurredRT, w, h), vec2(x, y), vec2(w, h), WHITE, blend,
	);
	setEffect(NO_COLOR_MATRIX, CLEAR, CLEAR);
}

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
