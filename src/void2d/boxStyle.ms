import { Color, rgba } from "./types";
import { GradientSpace } from "./gradient";

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

export enum BoxFillKind {
	Solid,
	Linear,
	Slash,
	Checker,
}

export struct BoxFill {
	kind: BoxFillKind;
	space: GradientSpace;
	dither: boolean;
	from: Color;
	to: Color;
	angle: float32;
	fromStop: float32;
	toStop: float32;
	stripe: float32;
	gap: float32;
	cell: float32;
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
	fill: BoxFill;
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
		fill: solidFill(),
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

export function solidFill(): BoxFill {
	const clear: Color = rgba(0.0, 0.0, 0.0, 0.0);
	return {
		kind: BoxFillKind.Solid, space: GradientSpace.Srgb, dither: false, from: clear, to: clear,
		angle: 0.0, fromStop: 0.0, toStop: 1.0, stripe: 0.0, gap: 0.0, cell: 0.0,
	};
}

function stopOnBadFill(call: string, what: string): void {
	console.log(`void2d: ${call} ${what}`);
	unreachable;
}

// GPUI's `linear_gradient` (color.rs:865) over the box, `angle` in CSS degrees (0 runs up,
// 90 runs right). A stop before an earlier one sits on it, the CSS rule for stop positions.
export function linearFill(
	this s: BoxStyle,
	angle: float32,
	from: Color,
	fromStop: float32,
	to: Color,
	toStop: float32,
	space: GradientSpace,
): BoxStyle {
	if (!(fromStop >= 0.0 && fromStop <= 1.0) || !(toStop >= 0.0 && toStop <= 1.0)) {
		stopOnBadFill("linearFill", `got stops ${fromStop} and ${toStop}; both must be in 0..1`);
	}
	return {
		...s,
		fill: {
			...solidFill(), kind: BoxFillKind.Linear, space: space, from: from, to: to,
			angle: angle, fromStop: fromStop, toStop: toStop < fromStop ? fromStop : toStop,
		},
	};
}

// GPUI's `pattern_slash` (color.rs:827): 45-degree stripes `width` wide with `gap` between.
export function slashFill(
	this s: BoxStyle,
	stripe: Color,
	between: Color,
	width: float32,
	gap: float32,
): BoxStyle {
	if (!(width > 0.0) || !(gap >= 0.0)) {
		stopOnBadFill("slashFill", `got width ${width} and gap ${gap}; width > 0, gap >= 0`);
	}
	return {
		...s,
		fill: {
			...solidFill(), kind: BoxFillKind.Slash, from: stripe, to: between,
			stripe: width, gap: gap,
		},
	};
}

// GPUI's `checkerboard` (color.rs:841): `cell`-sized squares from the box's top-left corner.
export function checkerFill(this s: BoxStyle, cell: Color, between: Color, size: float32): BoxStyle {
	if (!(size > 0.0)) { stopOnBadFill("checkerFill", `got cell size ${size}; it must be > 0`); }
	return {
		...s,
		fill: { ...solidFill(), kind: BoxFillKind.Checker, from: cell, to: between, cell: size },
	};
}

export function ditheredFill(this s: BoxStyle): BoxStyle {
	return { ...s, fill: { ...s.fill, dither: true } };
}

export let boxStyles: Vec<BoxStyle> = [];
let freeBoxStyles: Vec<int32> = [];

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
