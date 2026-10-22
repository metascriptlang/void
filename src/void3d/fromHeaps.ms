import { Vec3, vec3 } from "../math/math3d";
import { ParticleValue, ValueKind, Converge, ShapeKind, EmitterState, SortMode } from "./particles";
import { shaderNoiseScale } from "../particles/noise";
import {
	ParticleSystemAsset, ShapeModule, ShapeType, SimulationSpace, ParticleSortMode, Burst,
} from "../particles/asset";
import {
	MinMaxCurve, AnimationCurve, CurveKey, ColorKey, AlphaKey, ParticleColor, Gradient, GradientMode,
	ParticleColorSpace, MAX_GRADIENT_KEYS, constantCurve, twoConstants, twoCurves, curveOf,
	linearCurve, key, gradientOf,
} from "../particles/curve";

export enum HeapsLoweringError {
	NoCapacity,
	NonPositiveLife,
	NoFrames,
	GlobalSpeedNotConstant,
	NegativeGlobalSpeed,
	GlobalSizeNotConstant,
	ShapeValueNotConstant,
	NegativeShapeValue,
	ConeAngleOutOfRange,
	RingNotFlat,
	RingAxisNotAligned,
	RingInnerAboveOuter,
	BurstOutsideCycle,
	TooManyColorKeys,
	ColorKeysUnordered,
	RandomLightOrAlpha,
	SizeRatioNotRepresentable,
	SpeedAndInitialSpeedBothVary,
	RotationNotRepresentable,
}

export enum HeapsDivergence {
	EmissionCeil,
	SpawnAge,
	ShapeDistribution,
	ConeAsApex,
	SpeedScalesForces,
	DampingReachesSpeed,
	ForceTimeAxis,
	ForceSharedDraw,
	GravityFollowsWorld,
	GradientSampled,
	ValueSampled,
	RotationIntegrated,
	FrameBoundary,
	TurbulenceAsNoise,
	// Every particle draws from its own hash, where Heaps draws from one stream in order, so a
	// random value or a shape position matches Heaps in distribution, not per particle.
	RandomStream,
	// A system that does not loop stops its clock at its duration; Heaps' clock keeps counting.
	OneShotClock,
}

export const HEAPS_GRAVITY: Vec3 = { x: 0.0, y: -1.0, z: 0.0 };

const SAMPLES: int32 = 32;
const SLOPE_STEP: float64 = 1e-4;
const POW_FLOOR: float64 = 1e-6;
const BURST_EDGE_BIAS: float64 = 3e-7;
const GRADIENT_FIT: float64 = 1e-5;
const NO_SPEED_LIMIT: float32 = 1e30;
const HALF_PI: float64 = 1.5707963267948966;
const DEGREES: float64 = 57.29577951308232;
const MIN_RING_RADIUS: float32 = 0.001;

function isZero(this v: ParticleValue): boolean {
	return match (v.kind) {
		ValueKind.Const => v.value == 0.0,
		_ => false,
	};
}

function timeIndependent(this v: ParticleValue): boolean {
	return match (v.kind) {
		ValueKind.Const => true,
		ValueKind.Random => v.converge == Converge.No,
		_ => false,
	};
}

function sampledKind(this v: ParticleValue): boolean {
	return match (v.kind) {
		ValueKind.Pow | ValueKind.Sin | ValueKind.Cos | ValueKind.Poly => true,
		_ => false,
	};
}

function constantOf(v: ParticleValue, error: HeapsLoweringError): Result<float32, HeapsLoweringError> {
	return match (v.kind) {
		ValueKind.Const => Result.ok(v.value),
		_ => Result.err(error),
	};
}

function shapeConstant(v: ParticleValue): Result<float32, HeapsLoweringError> {
	const c: float32 = try constantOf(v, HeapsLoweringError.ShapeValueNotConstant);
	if (c < 0.0) { return Result.err(HeapsLoweringError.NegativeShapeValue); }
	return Result.ok(c);
}

function polynomial(values: Span<float32>, t: float64): float64 {
	let y: float64 = 0.0;
	let j: int32 = (values.length as int32) - 1;
	while (j >= 0) {
		y = (values[j] as float64) + t * y;
		j = j - 1;
	}
	return y;
}

function polynomialSlope(values: Span<float32>, t: float64): float64 {
	let y: float64 = 0.0;
	let j: int32 = (values.length as int32) - 1;
	while (j >= 1) {
		y = (j as float64) * (values[j] as float64) + t * y;
		j = j - 1;
	}
	return y;
}

function valueAt(v: ParticleValue, t: float64): float64 {
	return match (v.kind) {
		ValueKind.Const => v.value as float64,
		ValueKind.Linear => (v.start as float64) + (v.length as float64) * t,
		ValueKind.Pow => (v.start as float64) + Math.pow(t, v.power as float64) * (v.length as float64),
		ValueKind.Sin => Math.sin(t * (v.frequency as float64)) * (v.amplitude as float64) + (v.offset as float64),
		ValueKind.Cos => Math.cos(t * (v.frequency as float64)) * (v.amplitude as float64) + (v.offset as float64),
		ValueKind.Poly => polynomial(v.values, t),
		ValueKind.Random => v.start as float64,
	};
}

function slopeAt(v: ParticleValue, t: float64): float64 {
	return match (v.kind) {
		ValueKind.Const => 0.0,
		ValueKind.Linear => v.length as float64,
		ValueKind.Pow => {
			const floor: float64 = t > POW_FLOOR ? t : POW_FLOOR;
			return (v.length as float64) * (v.power as float64) * Math.pow(floor, (v.power as float64) - 1.0);
		},
		ValueKind.Sin => (v.amplitude as float64) * (v.frequency as float64) * Math.cos(t * (v.frequency as float64)),
		ValueKind.Cos => -(v.amplitude as float64) * (v.frequency as float64) * Math.sin(t * (v.frequency as float64)),
		ValueKind.Poly => polynomialSlope(v.values, t),
		ValueKind.Random => 0.0,
	};
}

function curvature(v: ParticleValue, t: float64): float64 {
	const low: float64 = t - SLOPE_STEP < 0.0 ? 0.0 : t - SLOPE_STEP;
	const high: float64 = t + SLOPE_STEP > 1.0 ? 1.0 : t + SLOPE_STEP;
	return (slopeAt(v, high) - slopeAt(v, low)) / (high - low);
}

function curveTrack(v: ParticleValue, derivative: boolean, t: float64): float64 {
	return derivative ? slopeAt(v, t) : valueAt(v, t);
}

// `m * v(t) + a` on 33 Hermite keys, or the same for the slope of `v` when `derivative`. A first
// key steeper than four chords (a power below one at 0) takes the chord instead of overshooting.
function sampledCurve(v: ParticleValue, derivative: boolean, m: float64, a: float64): MinMaxCurve {
	let keys: Vec<CurveKey> = [];
	const chord: float64 = (curveTrack(v, derivative, 1.0 / (SAMPLES as float64)) - curveTrack(v, derivative, 0.0))
		* (SAMPLES as float64);
	for (let i = 0; i <= SAMPLES; i++) {
		const t: float64 = (i as float64) / (SAMPLES as float64);
		let slope: float64 = derivative ? curvature(v, t) : slopeAt(v, t);
		if (i == 0 && Math.abs(slope) > 4.0 * Math.abs(chord)) { slope = chord; }
		let point: CurveKey = key(t as float32, (m * curveTrack(v, derivative, t) + a) as float32);
		point.inSlope = (m * slope) as float32;
		point.outSlope = point.inSlope;
		keys.push(point);
	}
	return curveOf(1.0, { keys: keys });
}

function flatLine(value: float32): AnimationCurve {
	return linearCurve([key(0.0, value), key(1.0, value)]);
}

function randomCurve(low: float32, high: float32, converge: Converge): MinMaxCurve {
	return match (converge) {
		Converge.No => twoConstants(low, high),
		Converge.Start => twoCurves(1.0, flatLine(low), linearCurve([key(0.0, low), key(1.0, high)])),
		Converge.End => twoCurves(1.0, flatLine(low), linearCurve([key(0.0, high), key(1.0, low)])),
	};
}

function curveFor(v: ParticleValue, m: float32, a: float32): MinMaxCurve {
	return match (v.kind) {
		ValueKind.Const => constantCurve(m * v.value + a),
		ValueKind.Linear => curveOf(
			1.0, linearCurve([key(0.0, m * v.start + a), key(1.0, m * (v.start + v.length) + a)]),
		),
		ValueKind.Random => randomCurve(m * v.start + a, m * (v.start + v.length) + a, v.converge),
		_ => sampledCurve(v, false, m as float64, a as float64),
	};
}

function burstSeconds(time: float64, duration: float64): float32 {
	return (time * duration * (1.0 - BURST_EDGE_BIAS)) as float32;
}

function channel(color: uint32, shift: uint32): float64 {
	return (((color >> shift) & 0xFF) as float64) / 255.0;
}

function heapsColor(state: EmitterState, t: float64): ParticleColor {
	const light: float64 = valueAt(state.light, t);
	const keys: int32 = state.colors.length as int32;
	if (keys == 0) {
		return { r: light as float32, g: light as float32, b: light as float32, a: 1.0 };
	}
	let from: int32 = 0;
	let to: int32 = 0;
	let weight: float64 = 0.0;
	if (state.colors[0].time < t) {
		to = 1;
		while (to < keys && state.colors[to].time < t) {
			from = to;
			to = to + 1;
		}
		if (to == keys) {
			to = from;
		} else {
			const start: float64 = state.colors[from].time;
			weight = (t - start) / (state.colors[to].time - start);
		}
	}
	const a: uint32 = state.colors[from].color;
	const b: uint32 = state.colors[to].color;
	return {
		r: ((channel(a, 16) * (1.0 - weight) + channel(b, 16) * weight) * light) as float32,
		g: ((channel(a, 8) * (1.0 - weight) + channel(b, 8) * weight) * light) as float32,
		b: ((channel(a, 0) * (1.0 - weight) + channel(b, 0) * weight) * light) as float32,
		a: 1.0,
	};
}

function trackAt(state: EmitterState, alpha: boolean, t: float64): ParticleColor {
	if (!alpha) { return heapsColor(state, t); }
	return { r: valueAt(state.alpha, t) as float32, g: 0.0, b: 0.0, a: 0.0 };
}

function midpointGap(state: EmitterState, alpha: boolean, t0: float64, t1: float64): float64 {
	const a: ParticleColor = trackAt(state, alpha, t0);
	const b: ParticleColor = trackAt(state, alpha, t1);
	const mid: ParticleColor = trackAt(state, alpha, (t0 + t1) * 0.5);
	const dr: float64 = Math.abs(((mid.r - (a.r + b.r) * 0.5)) as float64);
	const dg: float64 = Math.abs(((mid.g - (a.g + b.g) * 0.5)) as float64);
	const db: float64 = Math.abs(((mid.b - (a.b + b.b) * 0.5)) as float64);
	return Math.max(dr, Math.max(dg, db));
}

// Splits the segment whose midpoint is furthest from the chord until the keys are spent.
function refinedTimes(state: EmitterState, alpha: boolean, base: Vec<float64>): Vec<float64> {
	let times: Vec<float64> = base;
	while ((times.length as int32) < MAX_GRADIENT_KEYS) {
		let worst: float64 = GRADIENT_FIT;
		let at: int32 = -1;
		for (let i = 0; i + 1 < (times.length as int32); i++) {
			const gap: float64 = midpointGap(state, alpha, times[i], times[i + 1]);
			if (gap > worst) {
				worst = gap;
				at = i;
			}
		}
		if (at < 0) { return times; }
		let next: Vec<float64> = [];
		for (let i = 0; i < (times.length as int32); i++) {
			next.push(times[i]);
			if (i == at) { next.push((times[i] + times[i + 1]) * 0.5); }
		}
		times = next;
	}
	return times;
}

function colorTimes(state: EmitterState): Vec<float64> {
	let times: Vec<float64> = [];
	const flat: boolean = state.light.kind == ValueKind.Const;
	if (flat) {
		for (const k of state.colors) { times.push(k.time); }
		if (times.length == 0) { times.push(0.0); }
		return times;
	}
	times.push(0.0);
	for (const k of state.colors) {
		if (k.time > times[times.length - 1] && k.time < 1.0) { times.push(k.time); }
	}
	times.push(1.0);
	return times;
}

function lowerColor(ref a: ParticleSystemAsset, state: EmitterState): Result<void, HeapsLoweringError> {
	if (state.light.drawsRandom() || state.alpha.drawsRandom()) {
		return Result.err(HeapsLoweringError.RandomLightOrAlpha);
	}
	for (let i = 1; i < (state.colors.length as int32); i++) {
		if (state.colors[i].time < state.colors[i - 1].time) {
			return Result.err(HeapsLoweringError.ColorKeysUnordered);
		}
	}
	const plain: boolean = state.colors.length == 0 && state.light.kind == ValueKind.Const
		&& state.alpha.kind == ValueKind.Const && valueAt(state.light, 0.0) == 1.0
		&& valueAt(state.alpha, 0.0) == 1.0;
	if (plain) { return Result.ok(null); }
	let times: Vec<float64> = colorTimes(state);
	if ((times.length as int32) > MAX_GRADIENT_KEYS) { return Result.err(HeapsLoweringError.TooManyColorKeys); }
	if (state.light.kind != ValueKind.Const) { times = refinedTimes(state, false, times); }
	let colorKeys: Vec<ColorKey> = [];
	for (const t of times) { colorKeys.push({ color: heapsColor(state, t), time: t as float32 }); }
	let alphaTimes: Vec<float64> = [0.0];
	if (state.alpha.kind != ValueKind.Const) { alphaTimes = refinedTimes(state, true, [0.0, 1.0]); }
	let alphaKeys: Vec<AlphaKey> = [];
	for (const t of alphaTimes) {
		alphaKeys.push({ alpha: valueAt(state.alpha, t) as float32, time: t as float32 });
	}
	const gradient: Gradient = {
		colorKeys: colorKeys, alphaKeys: alphaKeys, mode: GradientMode.Blend,
		colorSpace: ParticleColorSpace.Gamma,
	};
	a.colorOverLifetime = { enabled: true, color: gradientOf(gradient) };
	return Result.ok(null);
}

// Local +Z is the emission axis of every Unity shape; this turns it into the port's +Y.
const EMIT_UP: Vec3 = { x: -90.0, y: 0.0, z: 0.0 };

function pointShape(shape: ShapeModule, y: float32): ShapeModule {
	return {
		...shape, shapeType: ShapeType.Cone, radius: 0.0, angle: 0.0, position: vec3(0.0, y, 0.0),
	};
}

// A Unity Circle lies in local XY, so the port's ring axis picks the turn that puts it
// perpendicular to the axis.
function ringRotation(axis: Vec3): Result<Vec3, HeapsLoweringError> {
	const x: boolean = axis.x != 0.0;
	const y: boolean = axis.y != 0.0;
	const z: boolean = axis.z != 0.0;
	const count: int32 = (x ? 1 : 0) + (y ? 1 : 0) + (z ? 1 : 0);
	if (count == 0 || (count == 1 && z)) { return Result.ok(vec3(0.0, 0.0, 0.0)); }
	if (count == 1 && y) { return Result.ok(EMIT_UP); }
	if (count == 1 && x) { return Result.ok(vec3(0.0, 90.0, 0.0)); }
	return Result.err(HeapsLoweringError.RingAxisNotAligned);
}

function lowerShape(ref a: ParticleSystemAsset, state: EmitterState): Result<void, HeapsLoweringError> {
	const shell: boolean = state.emitFromShell;
	let shape: ShapeModule = {
		...a.shape, rotation: EMIT_UP, radiusThickness: shell ? 0.0 : 1.0,
		randomDirectionAmount: state.randomDir ? 1.0 : 0.0,
	};
	match (state.shape.kind) {
		ShapeKind.Line => {
			const size: float32 = try shapeConstant(state.shape.size);
			if (shell || size == 0.0) {
				shape = pointShape(shape, size);
			} else {
				shape = {
					...shape, shapeType: ShapeType.Box, scale: vec3(0.0, 0.0, size),
					position: vec3(0.0, size * 0.5, 0.0),
				};
			}
		},
		ShapeKind.Sphere => {
			const radius: float32 = try shapeConstant(state.shape.radius);
			shape = { ...shape, shapeType: ShapeType.Sphere, radius: radius };
		},
		ShapeKind.Cone => {
			const angle: float32 = try constantOf(state.shape.angle, HeapsLoweringError.ShapeValueNotConstant);
			if (!(angle >= 0.0 && (angle as float64) < HALF_PI)) {
				return Result.err(HeapsLoweringError.ConeAngleOutOfRange);
			}
			shape = {
				...pointShape(shape, 0.0), angle: ((angle as float64) * DEGREES) as float32,
			};
		},
		ShapeKind.Disc => {
			const radius: float32 = try shapeConstant(state.shape.radius);
			shape = { ...shape, shapeType: ShapeType.Circle, radius: radius };
		},
		ShapeKind.Point => { shape = pointShape(shape, 0.0); },
		ShapeKind.Box => {
			const ex: float32 = try constantOf(state.shape.extents.x, HeapsLoweringError.ShapeValueNotConstant);
			const ey: float32 = try constantOf(state.shape.extents.y, HeapsLoweringError.ShapeValueNotConstant);
			const ez: float32 = try constantOf(state.shape.extents.z, HeapsLoweringError.ShapeValueNotConstant);
			const width: float32 = ex < 0.0 ? -2.0 * ex : 2.0 * ex;
			const height: float32 = ey < 0.0 ? -2.0 * ey : 2.0 * ey;
			const depth: float32 = ez < 0.0 ? -2.0 * ez : 2.0 * ez;
			if (height == 0.0) {
				shape = { ...shape, shapeType: ShapeType.Rectangle, scale: vec3(width, depth, 1.0) };
			} else {
				shape = {
					...shape, shapeType: shell ? ShapeType.BoxShell : ShapeType.Box,
					scale: vec3(width, depth, height),
				};
			}
		},
		ShapeKind.Ring => {
			const outer: float32 = try shapeConstant(state.shape.radius);
			const inner: float32 = try shapeConstant(state.shape.inner);
			if (state.shape.height != 0.0) { return Result.err(HeapsLoweringError.RingNotFlat); }
			const turn: Vec3 = try ringRotation(state.shape.axis);
			const reach: float32 = outer > MIN_RING_RADIUS ? outer : MIN_RING_RADIUS;
			if (inner > reach) { return Result.err(HeapsLoweringError.RingInnerAboveOuter); }
			shape = {
				...shape, shapeType: ShapeType.Circle, radius: reach, radiusThickness: 1.0 - inner / reach,
				rotation: turn,
			};
		},
	};
	a.shape = shape;
	return Result.ok(null);
}

function lowerSpeed(ref a: ParticleSystemAsset, state: EmitterState): Result<void, HeapsLoweringError> {
	const speed: ParticleValue = state.speed;
	const initial: ParticleValue = state.initialSpeed;
	if (speed.kind == ValueKind.Const) {
		a.main.startSpeed = curveFor(initial, 1.0, speed.value);
		return Result.ok(null);
	}
	const start: float32 = try constantOf(initial, HeapsLoweringError.SpeedAndInitialSpeedBothVary);
	if (speed.timeIndependent()) {
		a.main.startSpeed = curveFor(speed, 1.0, start);
		return Result.ok(null);
	}
	a.main.startSpeed = constantCurve(1.0);
	a.velocityOverLifetime = { ...a.velocityOverLifetime, enabled: true, speedModifier: curveFor(speed, 1.0, start) };
	return Result.ok(null);
}

function lowerRotation(ref a: ParticleSystemAsset, state: EmitterState): Result<void, HeapsLoweringError> {
	const angle: ParticleValue = state.rotation;
	if (angle.timeIndependent()) {
		a.main.startRotationZ = curveFor(angle, 1.0, 0.0);
		return Result.ok(null);
	}
	const life: float32 = try constantOf(state.life, HeapsLoweringError.RotationNotRepresentable);
	if (!(life > 0.0) || angle.drawsRandom()) { return Result.err(HeapsLoweringError.RotationNotRepresentable); }
	const perSecond: float64 = 1.0 / (life as float64);
	a.main.startRotationZ = constantCurve(valueAt(angle, 0.0) as float32);
	const spin: MinMaxCurve = match (angle.kind) {
		ValueKind.Linear => constantCurve((slopeAt(angle, 0.0) * perSecond) as float32),
		_ => sampledCurve(angle, true, perSecond, 0.0),
	};
	a.rotationOverLifetime = { ...a.rotationOverLifetime, enabled: true, z: spin };
	return Result.ok(null);
}

function lowerSize(ref a: ParticleSystemAsset, state: EmitterState, scale: float32): Result<void, HeapsLoweringError> {
	const size: ParticleValue = state.size;
	const ratio: ParticleValue = state.ratio;
	a.sizeOverLifetime.enabled = true;
	a.sizeOverLifetime.x = curveFor(size, scale, 0.0);
	if (ratio.kind == ValueKind.Const) {
		a.sizeOverLifetime.separateAxes = ratio.value != 1.0;
		a.sizeOverLifetime.y = curveFor(size, scale * ratio.value, 0.0);
		return Result.ok(null);
	}
	const fixed: float32 = try constantOf(size, HeapsLoweringError.SizeRatioNotRepresentable);
	a.sizeOverLifetime.separateAxes = true;
	a.sizeOverLifetime.y = curveFor(ratio, scale * fixed, 0.0);
	return Result.ok(null);
}

function lowerEmission(ref a: ParticleSystemAsset, state: EmitterState): Result<void, HeapsLoweringError> {
	a.emission.rateOverTime = curveFor(state.emitRate, 1.0, 0.0);
	let bursts: Vec<Burst> = [];
	for (const b of state.bursts) {
		if (!(b.time > 0.0 && b.time < 1.0)) { return Result.err(HeapsLoweringError.BurstOutsideCycle); }
		bursts.push({
			time: burstSeconds(b.time, state.globalLife), count: constantCurve(b.count as float32),
			cycleCount: 1, repeatInterval: 0.01, probability: 1.0,
		});
	}
	a.emission.bursts = bursts;
	return Result.ok(null);
}

function lowerForces(ref a: ParticleSystemAsset, state: EmitterState): void {
	const f = state.force;
	a.main.gravityModifier = curveFor(state.gravity, 1.0, 0.0);
	if (!(f.x.isZero() && f.y.isZero() && f.z.isZero())) {
		a.forceOverLifetime = {
			...a.forceOverLifetime, enabled: true, x: curveFor(f.x, 1.0, 0.0), y: curveFor(f.y, 1.0, 0.0),
			z: curveFor(f.z, 1.0, 0.0), space: a.main.simulationSpace,
		};
	}
	if (!state.damping.isZero()) {
		a.limitVelocityOverLifetime = {
			...a.limitVelocityOverLifetime, enabled: true, limit: constantCurve(NO_SPEED_LIMIT),
			drag: curveFor(state.damping, 1.0, 0.0), multiplyDragByParticleSize: false,
			multiplyDragByParticleVelocity: false,
		};
	}
	const t = state.turbulence;
	if (t.enabled && t.noiseStrength > 0.0) {
		const scale: float32 = shaderNoiseScale(t.noiseScale);
		a.noise = {
			...a.noise, enabled: true, strengthX: constantCurve(t.noiseStrength),
			frequency: scale < 0.0 ? -scale : scale, scrollSpeed: constantCurve(t.noiseSpeed.length()),
			damping: false, positionAmount: curveFor(t.influence, 1.0, 0.0),
		};
	}
}

function sortModeOf(mode: SortMode): ParticleSortMode {
	return match (mode) {
		SortMode.Front => ParticleSortMode.OldestInFront,
		SortMode.Back => ParticleSortMode.YoungestInFront,
		SortMode.Sort => ParticleSortMode.Depth,
		SortMode.InvSort => ParticleSortMode.DepthReverse,
	};
}

export function fromHeaps(state: EmitterState): Result<ParticleSystemAsset, HeapsLoweringError> {
	if (state.maxParts <= 0) { return Result.err(HeapsLoweringError.NoCapacity); }
	if (!(state.globalLife > 0.0)) { return Result.err(HeapsLoweringError.NonPositiveLife); }
	if (state.frame !== null && state.frameCount <= 0) { return Result.err(HeapsLoweringError.NoFrames); }
	const globalSpeed: float32 = try constantOf(state.globalSpeed, HeapsLoweringError.GlobalSpeedNotConstant);
	if (globalSpeed < 0.0) { return Result.err(HeapsLoweringError.NegativeGlobalSpeed); }
	const globalSize: float32 = try constantOf(state.globalSize, HeapsLoweringError.GlobalSizeNotConstant);
	let a = ParticleSystemAsset.defaults();
	a.main.loop = state.loop;
	a.main.duration = state.globalLife as float32;
	a.main.simulationSpeed = globalSpeed;
	a.main.maxParticles = state.maxParts;
	a.main.simulationSpace = state.emitLocal ? SimulationSpace.Local : SimulationSpace.World;
	a.main.startLifetime = curveFor(state.life, 1.0, 0.0);
	a.renderer.sortMode = sortModeOf(state.sortMode);
	const _emission = try lowerEmission(a, state);
	const _shape = try lowerShape(a, state);
	const _speed = try lowerSpeed(a, state);
	const _rotation = try lowerRotation(a, state);
	const _size = try lowerSize(a, state, globalSize);
	const _color = try lowerColor(a, state);
	lowerForces(a, state);
	if (state.frame !== null) {
		a.textureSheetAnimation = {
			...a.textureSheetAnimation, enabled: true, numTilesX: state.frameCount, numTilesY: 1,
			frameOverTime: curveFor(state.frame, 1.0, 0.0),
		};
	}
	return Result.ok(a);
}

function randomCount(a: ParticleValue, b: ParticleValue, c: ParticleValue): int32 {
	return (a.drawsRandom() ? 1 : 0) + (b.drawsRandom() ? 1 : 0) + (c.drawsRandom() ? 1 : 0);
}

// What the lowering of `state` cannot carry exactly, by name.
export function divergences(this state: EmitterState): BitSet<HeapsDivergence> {
	let found: BitSet<HeapsDivergence> = 0 as BitSet<HeapsDivergence>;
	const f = state.force;
	const forced: boolean = !(f.x.isZero() && f.y.isZero() && f.z.isZero());
	const emits: boolean = !state.emitRate.isZero();
	if (emits) { found = found.incl(HeapsDivergence.EmissionCeil); }
	if (emits || state.bursts.length > 0) { found = found.incl(HeapsDivergence.SpawnAge); }
	const spread: boolean = match (state.shape.kind) {
		ShapeKind.Sphere | ShapeKind.Disc => !state.emitFromShell,
		ShapeKind.Box => state.emitFromShell,
		_ => false,
	};
	if (spread) { found = found.incl(HeapsDivergence.ShapeDistribution); }
	const apex: boolean = match (state.shape.kind) {
		ShapeKind.Cone => !(state.shape.radius.isZero() && state.shape.angle.isZero()),
		_ => false,
	};
	if (apex) { found = found.incl(HeapsDivergence.ConeAsApex); }
	if (!state.speed.timeIndependent() && (forced || !state.gravity.isZero())) {
		found = found.incl(HeapsDivergence.SpeedScalesForces);
	}
	if (!state.damping.isZero() && !state.speed.isZero()) { found = found.incl(HeapsDivergence.DampingReachesSpeed); }
	if (!(f.x.timeIndependent() && f.y.timeIndependent() && f.z.timeIndependent())) {
		found = found.incl(HeapsDivergence.ForceTimeAxis);
	}
	if (randomCount(f.x, f.y, f.z) > 1) { found = found.incl(HeapsDivergence.ForceSharedDraw); }
	if (state.emitLocal && !state.gravity.isZero()) { found = found.incl(HeapsDivergence.GravityFollowsWorld); }
	const lightSampled: boolean = state.light.kind != ValueKind.Const
		&& !(state.colors.length == 0 && state.light.kind == ValueKind.Linear);
	const alphaSampled: boolean = state.alpha.kind != ValueKind.Const && state.alpha.kind != ValueKind.Linear;
	if (lightSampled || alphaSampled) { found = found.incl(HeapsDivergence.GradientSampled); }
	const sampled: boolean = state.emitRate.sampledKind() || state.life.sampledKind()
		|| state.speed.sampledKind() || state.initialSpeed.sampledKind() || state.size.sampledKind()
		|| state.ratio.sampledKind() || state.gravity.sampledKind() || f.x.sampledKind()
		|| f.y.sampledKind() || f.z.sampledKind() || state.damping.sampledKind()
		|| state.rotation.sampledKind() || state.turbulence.influence.sampledKind();
	if (sampled) { found = found.incl(HeapsDivergence.ValueSampled); }
	if (!state.rotation.timeIndependent()) { found = found.incl(HeapsDivergence.RotationIntegrated); }
	if (state.frame !== null) { found = found.incl(HeapsDivergence.FrameBoundary); }
	if (state.turbulence.enabled && state.turbulence.noiseStrength > 0.0) {
		found = found.incl(HeapsDivergence.TurbulenceAsNoise);
	}
	const frame: ParticleValue | null = state.frame;
	const draws: boolean = state.shape.kind != ShapeKind.Point || state.randomDir
		|| state.emitRate.drawsRandom() || state.life.drawsRandom() || state.speed.drawsRandom()
		|| state.initialSpeed.drawsRandom() || state.size.drawsRandom() || state.ratio.drawsRandom()
		|| state.rotation.drawsRandom() || state.gravity.drawsRandom() || randomCount(f.x, f.y, f.z) > 0
		|| state.damping.drawsRandom() || state.light.drawsRandom() || state.alpha.drawsRandom()
		|| (frame !== null && frame.drawsRandom());
	if (draws) { found = found.incl(HeapsDivergence.RandomStream); }
	if (!state.loop) { found = found.incl(HeapsDivergence.OneShotClock); }
	return found;
}
