// Unity's animatable particle values (docs/PARTICLES.md, AUTHORING §2): AnimationCurve,
// MinMaxCurve, Gradient and MinMaxGradient, as authored, plus the compiled forms the simulation
// evaluates. Authored values keep Unity's serialized shape so an importer is a rename.

import { srgbToLinear, linearToSrgb } from "../math/math3d";

export enum WeightedMode {
	None,
	In,
	Out,
	Both,
}

// One AnimationCurve key; an infinite slope is Unity's Constant tangent, a step.
export struct CurveKey {
	time: float32;
	value: float32;
	inSlope: float32;
	outSlope: float32;
	weightedMode: WeightedMode;
	inWeight: float32;
	outWeight: float32;
}

export struct AnimationCurve {
	keys: Vec<CurveKey>;
}

// ParticleSystemCurveMode (PSE:93).
export enum CurveMode {
	Constant,
	Curve,
	TwoCurves,
	TwoConstants,
}

// MinMaxCurve's serialized shape: `scalar` is the max constant and the curve multiplier.
export struct MinMaxCurve {
	mode: CurveMode;
	scalar: float32;
	minScalar: float32;
	maxCurve: AnimationCurve;
	minCurve: AnimationCurve;
}

export enum GradientMode {
	Blend,
	Fixed,
	PerceptualBlend,
}

// The colour space a gradient blends in; keys are always stored sRGB-encoded, as Unity stores them.
export enum ParticleColorSpace {
	Gamma,
	Linear,
}

export struct ParticleColor {
	r: float32;
	g: float32;
	b: float32;
	a: float32;
}

export struct ColorKey {
	color: ParticleColor;
	time: float32;
}

export struct AlphaKey {
	alpha: float32;
	time: float32;
}

export struct Gradient {
	colorKeys: Vec<ColorKey>;
	alphaKeys: Vec<AlphaKey>;
	mode: GradientMode;
	colorSpace: ParticleColorSpace;
}

// ParticleSystemGradientMode (PSE:112).
export enum GradientKind {
	Color,
	Gradient,
	TwoColors,
	TwoGradients,
	RandomColor,
}

export struct MinMaxGradient {
	mode: GradientKind;
	minColor: ParticleColor;
	maxColor: ParticleColor;
	maxGradient: Gradient;
	minGradient: Gradient;
}

export enum CurveError {
	TooManyKeys,
	UnorderedKeys,
	NonFiniteKey,
}

export const MAX_GRADIENT_KEYS: int32 = 8;
const ONE_THIRD: float32 = (1.0 / 3.0) as float32;
const BEZIER_STEPS: int32 = 24;

export const WHITE: ParticleColor = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };

export function rgbaColor(r: float32, g: float32, b: float32, a: float32): ParticleColor {
	return { r: r, g: g, b: b, a: a };
}

export function key(time: float32, value: float32): CurveKey {
	return {
		time: time, value: value, inSlope: 0.0, outSlope: 0.0,
		weightedMode: WeightedMode.None, inWeight: ONE_THIRD, outWeight: ONE_THIRD,
	};
}

// A straight line through the keys: each key's slopes point at its neighbours.
export function linearCurve(points: Span<CurveKey>): AnimationCurve {
	let keys: Vec<CurveKey> = [];
	for (const p of points) { keys.push(p); }
	const n: int32 = keys.length as int32;
	for (let i = 0; i < n; i++) {
		if (i > 0) {
			keys[i].inSlope = (keys[i].value - keys[i - 1].value) / (keys[i].time - keys[i - 1].time);
		}
		if (i + 1 < n) {
			keys[i].outSlope = (keys[i + 1].value - keys[i].value) / (keys[i + 1].time - keys[i].time);
		}
	}
	return { keys: keys };
}

export function constantCurve(value: float32): MinMaxCurve {
	return {
		mode: CurveMode.Constant, scalar: value, minScalar: value,
		maxCurve: { keys: [] }, minCurve: { keys: [] },
	};
}

export function twoConstants(min: float32, max: float32): MinMaxCurve {
	return {
		mode: CurveMode.TwoConstants, scalar: max, minScalar: min,
		maxCurve: { keys: [] }, minCurve: { keys: [] },
	};
}

export function curveOf(multiplier: float32, curve: AnimationCurve): MinMaxCurve {
	return {
		mode: CurveMode.Curve, scalar: multiplier, minScalar: 0.0,
		maxCurve: curve, minCurve: { keys: [] },
	};
}

export function twoCurves(multiplier: float32, min: AnimationCurve, max: AnimationCurve): MinMaxCurve {
	return {
		mode: CurveMode.TwoCurves, scalar: multiplier, minScalar: 0.0,
		maxCurve: max, minCurve: min,
	};
}

export function solidGradient(color: ParticleColor): Gradient {
	return {
		colorKeys: [{ color: color, time: 0.0 }],
		alphaKeys: [{ alpha: color.a, time: 0.0 }],
		mode: GradientMode.Blend,
		colorSpace: ParticleColorSpace.Gamma,
	};
}

export function constantColor(color: ParticleColor): MinMaxGradient {
	return {
		mode: GradientKind.Color, minColor: color, maxColor: color,
		maxGradient: solidGradient(color), minGradient: solidGradient(color),
	};
}

export function gradientOf(gradient: Gradient): MinMaxGradient {
	return {
		mode: GradientKind.Gradient, minColor: WHITE, maxColor: WHITE,
		maxGradient: gradient, minGradient: solidGradient(WHITE),
	};
}

// ---- compiled forms ----

// One curve segment from t0 to t0 + 1/invSpan: a cubic in the local s, or a step, or a weighted
// Bezier whose x must be solved for s.
export struct CurveSegment {
	t0: float32;
	invSpan: float32;
	a: float32;
	b: float32;
	c: float32;
	d: float32;
	step: boolean;
	bezier: boolean;
	x1: float32;
	x2: float32;
	y1: float32;
	y2: float32;
	y3: float32;
}

export struct CompiledCurve {
	segments: Vec<CurveSegment>;
	first: float32;
	firstValue: float32;
	last: float32;
	lastValue: float32;
	empty: boolean;
}

export struct CompiledMinMaxCurve {
	mode: CurveMode;
	scalar: float32;
	minScalar: float32;
	maxCurve: CompiledCurve;
	minCurve: CompiledCurve;
}

function clamp01(v: float32): float32 {
	if (v < 0.0) { return 0.0; }
	if (v > 1.0) { return 1.0; }
	return v;
}

function finiteOrStep(slope: float32): boolean {
	return Number.isFinite(slope);
}

export function compile(this curve: AnimationCurve): Result<CompiledCurve, CurveError> {
	const n: int32 = curve.keys.length as int32;
	let segments: Vec<CurveSegment> = [];
	if (n == 0) {
		return Result.ok({
			segments: segments, first: 0.0, firstValue: 0.0, last: 0.0, lastValue: 0.0, empty: true,
		});
	}
	for (let i = 0; i < n; i++) {
		const k: CurveKey = curve.keys[i];
		if (!Number.isFinite(k.time) || !Number.isFinite(k.value)) {
			return Result.err(CurveError.NonFiniteKey);
		}
		if (i > 0 && !(k.time > curve.keys[i - 1].time)) { return Result.err(CurveError.UnorderedKeys); }
	}
	for (let i = 0; i + 1 < n; i++) {
		const k0: CurveKey = curve.keys[i];
		const k1: CurveKey = curve.keys[i + 1];
		const span: float32 = k1.time - k0.time;
		const step: boolean = !finiteOrStep(k0.outSlope) || !finiteOrStep(k1.inSlope);
		const outWeighted: boolean =
			k0.weightedMode == WeightedMode.Out || k0.weightedMode == WeightedMode.Both;
		const inWeighted: boolean =
			k1.weightedMode == WeightedMode.In || k1.weightedMode == WeightedMode.Both;
		const bezier: boolean = !step && (outWeighted || inWeighted);
		const w0: float32 = outWeighted ? clamp01(k0.outWeight) : ONE_THIRD;
		const w1: float32 = inWeighted ? clamp01(k1.inWeight) : ONE_THIRD;
		const m0: float32 = step ? 0.0 : k0.outSlope * span;
		const m1: float32 = step ? 0.0 : k1.inSlope * span;
		segments.push({
			t0: k0.time,
			invSpan: 1.0 / span,
			a: 2.0 * k0.value + m0 - 2.0 * k1.value + m1,
			b: -3.0 * k0.value - 2.0 * m0 + 3.0 * k1.value - m1,
			c: m0,
			d: k0.value,
			step: step,
			bezier: bezier,
			x1: w0,
			x2: 1.0 - w1,
			y1: k0.value + w0 * m0,
			y2: k1.value - w1 * m1,
			y3: k1.value,
		});
	}
	return Result.ok({
		segments: segments,
		first: curve.keys[0].time,
		firstValue: curve.keys[0].value,
		last: curve.keys[n - 1].time,
		lastValue: curve.keys[n - 1].value,
		empty: false,
	});
}

function bezier1(p0: float32, p1: float32, p2: float32, p3: float32, u: float32): float32 {
	const v: float32 = 1.0 - u;
	return v * v * v * p0 + 3.0 * v * v * u * p1 + 3.0 * v * u * u * p2 + u * u * u * p3;
}

// The weighted segment: x(u) = s is solved by bisection (x is monotonic for weights in 0..1).
function bezierAt(seg: CurveSegment, s: float32): float32 {
	let low: float32 = 0.0;
	let high: float32 = 1.0;
	for (let i = 0; i < BEZIER_STEPS; i++) {
		const mid: float32 = (low + high) * 0.5;
		if (bezier1(0.0, seg.x1, seg.x2, 1.0, mid) < s) { low = mid; } else { high = mid; }
	}
	return bezier1(seg.d, seg.y1, seg.y2, seg.y3, (low + high) * 0.5);
}

// Clamped at both ends, as particle curves always are.
export function evaluate(this curve: CompiledCurve, t: float32): float32 {
	if (curve.empty) { return 0.0; }
	if (!(t > curve.first)) { return curve.firstValue; }
	if (!(t < curve.last)) { return curve.lastValue; }
	const n: int32 = curve.segments.length as int32;
	let i: int32 = 0;
	while (i + 1 < n && curve.segments[i + 1].t0 <= t) { i = i + 1; }
	const seg: CurveSegment = curve.segments[i];
	const s: float32 = (t - seg.t0) * seg.invSpan;
	if (seg.step) { return seg.d; }
	if (seg.bezier) { return bezierAt(seg, s); }
	return ((seg.a * s + seg.b) * s + seg.c) * s + seg.d;
}

export function compile(this value: MinMaxCurve): Result<CompiledMinMaxCurve, CurveError> {
	const usesMax: boolean = value.mode == CurveMode.Curve || value.mode == CurveMode.TwoCurves;
	const usesMin: boolean = value.mode == CurveMode.TwoCurves;
	const empty: AnimationCurve = { keys: [] };
	const maxCurve: CompiledCurve = try (usesMax ? value.maxCurve : empty).compile();
	const minCurve: CompiledCurve = try (usesMin ? value.minCurve : empty).compile();
	return Result.ok({
		mode: value.mode, scalar: value.scalar, minScalar: value.minScalar,
		maxCurve: maxCurve, minCurve: minCurve,
	});
}

// MinMaxCurve.Evaluate (PSS:520-533): `t` on the field's axis, `r` the particle's stable draw.
export function evaluate(this value: CompiledMinMaxCurve, t: float32, r: float32): float32 {
	return match (value.mode) {
		CurveMode.Constant => value.scalar,
		CurveMode.TwoConstants => value.minScalar + (value.scalar - value.minScalar) * r,
		CurveMode.Curve => value.maxCurve.evaluate(t) * value.scalar,
		CurveMode.TwoCurves => {
			const low: float32 = value.minCurve.evaluate(t);
			const high: float32 = value.maxCurve.evaluate(t);
			return (low + (high - low) * r) * value.scalar;
		},
	};
}

// True when the value cannot change with `t`.
export function isConstantOverTime(this value: CompiledMinMaxCurve): boolean {
	return value.mode == CurveMode.Constant || value.mode == CurveMode.TwoConstants;
}

// ---- gradients ----

export function validate(this gradient: Gradient): Result<int32, CurveError> {
	const colors: int32 = gradient.colorKeys.length as int32;
	const alphas: int32 = gradient.alphaKeys.length as int32;
	if (colors > MAX_GRADIENT_KEYS || alphas > MAX_GRADIENT_KEYS) {
		return Result.err(CurveError.TooManyKeys);
	}
	for (let i = 1; i < colors; i++) {
		if (gradient.colorKeys[i].time < gradient.colorKeys[i - 1].time) {
			return Result.err(CurveError.UnorderedKeys);
		}
	}
	for (let i = 1; i < alphas; i++) {
		if (gradient.alphaKeys[i].time < gradient.alphaKeys[i - 1].time) {
			return Result.err(CurveError.UnorderedKeys);
		}
	}
	return Result.ok(colors);
}

function toSpace(c: ParticleColor, space: ParticleColorSpace): ParticleColor {
	if (space == ParticleColorSpace.Gamma) { return c; }
	return { r: srgbToLinear(c.r), g: srgbToLinear(c.g), b: srgbToLinear(c.b), a: c.a };
}

function fromSpace(c: ParticleColor, space: ParticleColorSpace): ParticleColor {
	if (space == ParticleColorSpace.Gamma) { return c; }
	return { r: linearToSrgb(c.r), g: linearToSrgb(c.g), b: linearToSrgb(c.b), a: c.a };
}

function cubeRoot(v: float32): float32 {
	if (v < 0.0) { return -(Math.pow(-v, 1.0 / 3.0) as float32); }
	return Math.pow(v, 1.0 / 3.0) as float32;
}

// Oklab mix of two sRGB colours, Unity's PerceptualBlend.
function oklabMix(a: ParticleColor, b: ParticleColor, u: float32): ParticleColor {
	const la: ParticleColor = toOklab(a);
	const lb: ParticleColor = toOklab(b);
	return fromOklab({
		r: la.r + (lb.r - la.r) * u, g: la.g + (lb.g - la.g) * u, b: la.b + (lb.b - la.b) * u, a: 1.0,
	});
}

function toOklab(c: ParticleColor): ParticleColor {
	const r: float32 = srgbToLinear(c.r);
	const g: float32 = srgbToLinear(c.g);
	const b: float32 = srgbToLinear(c.b);
	const l: float32 = cubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
	const m: float32 = cubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
	const s: float32 = cubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
	return {
		r: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		g: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
		a: 1.0,
	};
}

function fromOklab(c: ParticleColor): ParticleColor {
	const l0: float32 = c.r + 0.3963377774 * c.g + 0.2158037573 * c.b;
	const m0: float32 = c.r - 0.1055613458 * c.g - 0.0638541728 * c.b;
	const s0: float32 = c.r - 0.0894841775 * c.g - 1.2914855480 * c.b;
	const l: float32 = l0 * l0 * l0;
	const m: float32 = m0 * m0 * m0;
	const s: float32 = s0 * s0 * s0;
	return {
		r: clamp01(linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
		g: clamp01(linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
		b: clamp01(linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)),
		a: 1.0,
	};
}

function mixRgb(a: ParticleColor, b: ParticleColor, u: float32, g: Gradient): ParticleColor {
	if (g.mode == GradientMode.PerceptualBlend) { return oklabMix(a, b, u); }
	const x: ParticleColor = toSpace(a, g.colorSpace);
	const y: ParticleColor = toSpace(b, g.colorSpace);
	return fromSpace({
		r: x.r + (y.r - x.r) * u, g: x.g + (y.g - x.g) * u, b: x.b + (y.b - x.b) * u, a: 1.0,
	}, g.colorSpace);
}

function colorAt(g: Gradient, t: float32): ParticleColor {
	const n: int32 = g.colorKeys.length as int32;
	if (n == 0) { return WHITE; }
	if (t <= g.colorKeys[0].time) { return g.colorKeys[0].color; }
	for (let i = 1; i < n; i++) {
		const right: ColorKey = g.colorKeys[i];
		if (t <= right.time) {
			const left: ColorKey = g.colorKeys[i - 1];
			if (g.mode == GradientMode.Fixed) { return right.color; }
			const span: float32 = right.time - left.time;
			const u: float32 = span > 0.0 ? (t - left.time) / span : 1.0;
			return mixRgb(left.color, right.color, u, g);
		}
	}
	return g.colorKeys[n - 1].color;
}

function alphaAt(g: Gradient, t: float32): float32 {
	const n: int32 = g.alphaKeys.length as int32;
	if (n == 0) { return 1.0; }
	if (t <= g.alphaKeys[0].time) { return g.alphaKeys[0].alpha; }
	for (let i = 1; i < n; i++) {
		const right: AlphaKey = g.alphaKeys[i];
		if (t <= right.time) {
			const left: AlphaKey = g.alphaKeys[i - 1];
			if (g.mode == GradientMode.Fixed) { return right.alpha; }
			const span: float32 = right.time - left.time;
			const u: float32 = span > 0.0 ? (t - left.time) / span : 1.0;
			return left.alpha + (right.alpha - left.alpha) * u;
		}
	}
	return g.alphaKeys[n - 1].alpha;
}

// Gradient.Evaluate: colour and alpha on their own key tracks.
export function evaluate(this g: Gradient, t: float32): ParticleColor {
	const rgb: ParticleColor = colorAt(g, t);
	return { r: rgb.r, g: rgb.g, b: rgb.b, a: alphaAt(g, t) };
}

function lerpColor(a: ParticleColor, b: ParticleColor, u: float32): ParticleColor {
	return {
		r: a.r + (b.r - a.r) * u, g: a.g + (b.g - a.g) * u,
		b: a.b + (b.b - a.b) * u, a: a.a + (b.a - a.a) * u,
	};
}

// MinMaxGradient.Evaluate (PSS:845-860).
export function evaluate(this value: MinMaxGradient, t: float32, r: float32): ParticleColor {
	return match (value.mode) {
		GradientKind.Color => value.maxColor,
		GradientKind.Gradient => value.maxGradient.evaluate(t),
		GradientKind.TwoColors => lerpColor(value.minColor, value.maxColor, r),
		GradientKind.TwoGradients =>
			lerpColor(value.minGradient.evaluate(t), value.maxGradient.evaluate(t), r),
		GradientKind.RandomColor => value.maxGradient.evaluate(r),
	};
}

export function validate(this value: MinMaxGradient): Result<int32, CurveError> {
	const _max = try value.maxGradient.validate();
	return value.minGradient.validate();
}

export function times(this a: ParticleColor, b: ParticleColor): ParticleColor {
	return { r: a.r * b.r, g: a.g * b.g, b: a.b * b.b, a: a.a * b.a };
}

// ---- stable randoms ----

// PCG's output hash (O'Neill; hanabi's `pcg_hash`, Godot's `idhash` serves the same role).
export function pcgHash(input: uint32): uint32 {
	const state: uint32 = input * 747796405 + 2891336453;
	const word: uint32 = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
	return (word >> 22) ^ word;
}

// The particle's k-th stable draw in [0, 1), read as 24 bits so it is exact in float32.
export function unitDraw(seed: uint32, stream: uint32): float32 {
	const h: uint32 = pcgHash(seed ^ (stream * 0x9E3779B9));
	return ((h >> 8) as float32) * ((1.0 / 16777216.0) as float32);
}
