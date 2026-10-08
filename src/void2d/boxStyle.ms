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

// GPUI's `BoxShadow` (style.rs), drawn by the analytic erf integral with no render target. A
// zero-alpha colour is no shadow; blur is the Gaussian sigma in local units. Spread grows a
// drop shadow's rect and shrinks an inset one's hole, and only the hole's radii shrink with it
// (window.rs:4401-4445).
export struct BoxShadow {
	color: Color;
	blur: float32;
	offsetX: float32;
	offsetY: float32;
	spread: float32;
	inset: boolean;
}

export struct BoxStyle {
	radii: CornerRadii;
	borders: BorderWidths;
	borderColor: Color;
	borderStyle: BorderStyle;
	shadows: BoxShadow[];
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
		shadows: [],
		fill: solidFill(),
	};
}

export function dashed(this s: BoxStyle): BoxStyle {
	return { ...s, borderStyle: BorderStyle.Dashed };
}

// The box's shadows, drawn in list order: the drop shadows under the fill, the inset ones over
// it and under the border, GPUI's `Style::paint` order (style.rs:711-740).
export function castShadows(this s: BoxStyle, shadows: Readonly<Span<BoxShadow>>): BoxStyle {
	const list: BoxShadow[] = [];
	for (const shadow of shadows) { list.push(shadow); }
	return { ...s, shadows: list };
}

function withShadow(s: BoxStyle, shadow: BoxShadow): BoxStyle {
	const list: BoxShadow[] = [];
	for (const kept of s.shadows) { list.push(kept); }
	list.push(shadow);
	return { ...s, shadows: list };
}

// Appends a drop shadow: offset in local units, positive down-right.
export function castShadow(
	this s: BoxStyle,
	color: Color,
	blur: float32,
	offsetX: float32,
	offsetY: float32,
): BoxStyle {
	return withShadow(s, {
		color: color, blur: blur, offsetX: offsetX, offsetY: offsetY, spread: 0.0, inset: false,
	});
}

// Appends an inset shadow: the blurred hole's complement, clipped to the element.
export function castInsetShadow(this s: BoxStyle, color: Color, blur: float32): BoxStyle {
	return withShadow(s, {
		color: color, blur: blur, offsetX: 0.0, offsetY: 0.0, spread: 0.0, inset: true,
	});
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
			...solidFill(), kind: BoxFillKind.Linear, space: space, dither: s.fill.dither,
			from: from, to: to,
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
			...solidFill(), kind: BoxFillKind.Slash, dither: s.fill.dither, from: stripe,
			to: between,
			stripe: width, gap: gap,
		},
	};
}

// GPUI's `checkerboard` (color.rs:841): `cell`-sized squares from the box's top-left corner.
export function checkerFill(this s: BoxStyle, cell: Color, between: Color, size: float32): BoxStyle {
	if (!(size > 0.0)) { stopOnBadFill("checkerFill", `got cell size ${size}; it must be > 0`); }
	return {
		...s,
		fill: {
			...solidFill(), kind: BoxFillKind.Checker, dither: s.fill.dither, from: cell,
			to: between, cell: size,
		},
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
