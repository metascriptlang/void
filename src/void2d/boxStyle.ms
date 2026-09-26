import { Color, rgba } from "./types";

export const NO_BOX_STYLE: int32 = -1;

export enum BorderStyle {
	Solid,
	Dashed,
}

export struct CornerRadii {
	topLeft: float32;
	topRight: float32;
	bottomRight: float32;
	bottomLeft: float32;
}

export struct BorderWidths {
	left: float32;
	top: float32;
	right: float32;
	bottom: float32;
}

export struct BoxStyle {
	radii: CornerRadii;
	borders: BorderWidths;
	borderColor: Color;
	borderStyle: BorderStyle;
	// The analytic shadow (GPUI's erf integral, no render target). A zero-alpha shadowColor
	// is no shadow; blur is the Gaussian sigma in local units; inset keeps it inside the box.
	shadowColor: Color;
	shadowBlur: float32;
	shadowOffsetX: float32;
	shadowOffsetY: float32;
	shadowInset: boolean;
}

// Free functions, not CornerRadii.uniform / BorderWidths.uniform: two same-name static extensions
// exported from one module resolve only the first in an importer
// (~/metascript/.inbox/compiler/2026-09-26-same-name-static-extensions-one-module.md).
export function uniformRadii(radius: float32): CornerRadii {
	return { topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius };
}

export function uniformBorders(width: float32): BorderWidths {
	return { left: width, top: width, right: width, bottom: width };
}

export function create(
	this typeof BoxStyle,
	radii: CornerRadii,
	borders: BorderWidths,
	borderColor: Color,
): BoxStyle {
	return {
		radii: radii,
		borders: borders,
		borderColor: borderColor,
		borderStyle: BorderStyle.Solid,
		shadowColor: rgba(0.0, 0.0, 0.0, 0.0),
		shadowBlur: 0.0,
		shadowOffsetX: 0.0,
		shadowOffsetY: 0.0,
		shadowInset: false,
	};
}

export function dashed(this s: BoxStyle): BoxStyle {
	return { ...s, borderStyle: BorderStyle.Dashed };
}

// A drop shadow cast by the box: offset in local units, positive down-right. The colour's
// alpha is the strength.
export function castShadow(
	this s: BoxStyle,
	color: Color,
	blur: float32,
	offsetX: float32,
	offsetY: float32,
): BoxStyle {
	return {
		...s,
		shadowColor: color,
		shadowBlur: blur,
		shadowOffsetX: offsetX,
		shadowOffsetY: offsetY,
		shadowInset: false,
	};
}

// An inset shadow: the blurred hole's complement, clipped to the element.
export function castInsetShadow(this s: BoxStyle, color: Color, blur: float32): BoxStyle {
	return {
		...s,
		shadowColor: color,
		shadowBlur: blur,
		shadowOffsetX: 0.0,
		shadowOffsetY: 0.0,
		shadowInset: true,
	};
}

export const boxStyles: Vec<BoxStyle> = [];
const freeBoxStyles: Vec<int32> = [];

export function allocateBoxStyle(style: BoxStyle): int32 {
	const freeCount: int32 = freeBoxStyles.length as int32;
	if (freeCount > 0) {
		const index: int32 = freeBoxStyles[freeCount - 1];
		freeBoxStyles.pop();
		boxStyles[index] = style;
		return index;
	}
	const index: int32 = boxStyles.length as int32;
	boxStyles.push(style);
	return index;
}

export function updateBoxStyle(index: int32, style: BoxStyle): void {
	boxStyles[index] = style;
}

export function releaseBoxStyle(index: int32): void {
	if (index == NO_BOX_STYLE) { return; }
	freeBoxStyles.push(index);
}
