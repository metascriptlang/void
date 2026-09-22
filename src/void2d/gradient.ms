import { Color, rgba } from "./types";

export enum GradientSpace {
	Srgb,
	Oklab,
}

export struct Oklab {
	l: float32;
	a: float32;
	b: float32;
}

function clamp01(v: float32): float32 {
	if (v < 0.0) { return 0.0; }
	if (v > 1.0) { return 1.0; }
	return v;
}

function srgbToLinear(v: float32): float32 {
	if (v <= 0.04045) { return (v / 12.92) as float32; }
	return Math.pow((v + 0.055) / 1.055, 2.4) as float32;
}

function linearToSrgb(v: float32): float32 {
	if (v <= 0.0031308) { return (12.92 * v) as float32; }
	return (1.055 * (Math.pow(v, 1.0 / 2.4) as float32) - 0.055) as float32;
}

function cubeRoot(v: float32): float32 {
	if (v < 0.0) { return -(Math.pow(-v, 1.0 / 3.0) as float32); }
	return Math.pow(v, 1.0 / 3.0) as float32;
}

export function toOklab(c: Color): Oklab {
	const r: float32 = srgbToLinear(c.r);
	const g: float32 = srgbToLinear(c.g);
	const b: float32 = srgbToLinear(c.b);
	const l: float32 = cubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
	const m: float32 = cubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
	const s: float32 = cubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
	return {
		l: (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s) as float32,
		a: (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s) as float32,
		b: (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s) as float32,
	};
}

export function fromOklab(c: Oklab, alpha: float32): Color {
	const l0: float32 = c.l + 0.3963377774 * c.a + 0.2158037573 * c.b;
	const m0: float32 = c.l - 0.1055613458 * c.a - 0.0638541728 * c.b;
	const s0: float32 = c.l - 0.0894841775 * c.a - 1.2914855480 * c.b;
	const l: float32 = l0 * l0 * l0;
	const m: float32 = m0 * m0 * m0;
	const s: float32 = s0 * s0 * s0;
	return rgba(
		clamp01(linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
		clamp01(linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
		clamp01(linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)),
		clamp01(alpha),
	);
}

export function mixGradient(a: Color, b: Color, t: float32, space: GradientSpace): Color {
	const u: float32 = clamp01(t);
	if (space == GradientSpace.Srgb) {
		return rgba(
			a.r + (b.r - a.r) * u,
			a.g + (b.g - a.g) * u,
			a.b + (b.b - a.b) * u,
			a.a + (b.a - a.a) * u,
		);
	}
	const la: Oklab = toOklab(a);
	const lb: Oklab = toOklab(b);
	return fromOklab({
		l: la.l + (lb.l - la.l) * u,
		a: la.a + (lb.a - la.a) * u,
		b: la.b + (lb.b - la.b) * u,
	}, a.a + (b.a - a.a) * u);
}

export function dither4x4(x: int32, y: int32): float32 {
	let ix: int32 = x % 4;
	let iy: int32 = y % 4;
	if (ix < 0) { ix = ix + 4; }
	if (iy < 0) { iy = iy + 4; }
	const index: int32 = match (iy * 4 + ix) {
		0 => 0, 1 => 8, 2 => 2, 3 => 10,
		4 => 12, 5 => 4, 6 => 14, 7 => 6,
		8 => 3, 9 => 11, 10 => 1, 11 => 9,
		12 => 15, 13 => 7, 14 => 13, _ => 5,
	};
	return (((index as float32) - 7.5) * (2.0 / (7.5 * 255.0))) as float32;
}
