import { Tile } from "./types";
import { CornerRadii } from "./boxStyle";

export enum ObjectFit {
	Fill,
	Contain,
	Cover,
	ScaleDown,
	None,
}

export struct ImageStyle {
	radii: CornerRadii;
	grayscale: boolean;
	fit: ObjectFit;
}

export struct FittedImage {
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	u0: float32;
	v0: float32;
	u1: float32;
	v1: float32;
}

export const NO_IMAGE_STYLE: int32 = -1;

export function imageStyle(radii: CornerRadii, grayscale: boolean, fit: ObjectFit): ImageStyle {
	return { radii: radii, grayscale: grayscale, fit: fit };
}


function interpolate(a: float32, b: float32, t: float32): float32 {
	return a + (b - a) * t;
}

function emptyFit(t: Tile): FittedImage {
	return { x: 0.0, y: 0.0, w: 0.0, h: 0.0, u0: t.u0, v0: t.v0, u1: t.u1, v1: t.v1 };
}

export function fitImage(t: Tile, boxW: float32, boxH: float32, fit: ObjectFit): FittedImage {
	if (t.w <= 0.0 || t.h <= 0.0 || boxW <= 0.0 || boxH <= 0.0) { return emptyFit(t); }
	if (fit == ObjectFit.Fill) {
		return { x: 0.0, y: 0.0, w: boxW, h: boxH, u0: t.u0, v0: t.v0, u1: t.u1, v1: t.v1 };
	}
	const imageRatio: float32 = t.w / t.h;
	const boxRatio: float32 = boxW / boxH;
	if (fit == ObjectFit.Cover) {
		let u0: float32 = t.u0;
		let v0: float32 = t.v0;
		let u1: float32 = t.u1;
		let v1: float32 = t.v1;
		if (boxRatio > imageRatio) {
			const visible: float32 = t.w / boxRatio;
			const margin: float32 = (t.h - visible) * 0.5 / t.h;
			v0 = interpolate(t.v0, t.v1, margin);
			v1 = interpolate(t.v0, t.v1, 1.0 - margin);
		} else {
			const visible: float32 = t.h * boxRatio;
			const margin: float32 = (t.w - visible) * 0.5 / t.w;
			u0 = interpolate(t.u0, t.u1, margin);
			u1 = interpolate(t.u0, t.u1, 1.0 - margin);
		}
		return { x: 0.0, y: 0.0, w: boxW, h: boxH, u0: u0, v0: v0, u1: u1, v1: v1 };
	}
	let w: float32 = t.w;
	let h: float32 = t.h;
	if (fit == ObjectFit.Contain || (fit == ObjectFit.ScaleDown && (t.w > boxW || t.h > boxH))) {
		if (boxRatio > imageRatio) {
			h = boxH;
			w = t.w * (boxH / t.h);
		} else {
			w = boxW;
			h = t.h * (boxW / t.w);
		}
	}
	let x: float32 = 0.0;
	let y: float32 = 0.0;
	if (fit != ObjectFit.None) {
		x = (boxW - w) * 0.5;
		y = (boxH - h) * 0.5;
	}
	let visibleW: float32 = w;
	let visibleH: float32 = h;
	if (visibleW > boxW - x) { visibleW = boxW - x; }
	if (visibleH > boxH - y) { visibleH = boxH - y; }
	if (visibleW <= 0.0 || visibleH <= 0.0) { return emptyFit(t); }
	return {
		x: x,
		y: y,
		w: visibleW,
		h: visibleH,
		u0: t.u0,
		v0: t.v0,
		u1: interpolate(t.u0, t.u1, visibleW / w),
		v1: interpolate(t.v0, t.v1, visibleH / h),
	};
}

export const imageStyles: Vec<ImageStyle> = [];
const freeImageStyles: Vec<int32> = [];

export function allocateImageStyle(style: ImageStyle): int32 {
	const freeCount: int32 = freeImageStyles.length as int32;
	if (freeCount > 0) {
		const index: int32 = freeImageStyles[freeCount - 1];
		freeImageStyles.pop();
		imageStyles[index] = style;
		return index;
	}
	const index: int32 = imageStyles.length as int32;
	imageStyles.push(style);
	return index;
}

export function updateImageStyle(index: int32, style: ImageStyle): void {
	imageStyles[index] = style;
}

export function releaseImageStyle(index: int32): void {
	if (index == NO_IMAGE_STYLE) { return; }
	freeImageStyles.push(index);
}
