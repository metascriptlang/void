import { Vec3, vec3, identity } from "../math/math3d";
import { noiseDirection, shaderNoiseScale } from "../particles/noise";
import {
	ParticleValue, ValueKind, Converge, ShapeKind, EmitterState, HeapsBurst, constant,
	fromHeaps, divergences, HEAPS_GRAVITY, HeapsLoweringError, HeapsDivergence,
} from "../void3d/fromHeaps";
import { CompiledMinMaxCurve } from "../particles/curve";
import {
	ParticleSystem, playSystem, updateSystem, POS_X, POS_Y, POS_Z, AGE, SIZE_X,
	COLOR_R, COLOR_G, COLOR_B, COLOR_A,
} from "../particles/system";

function near(a: float32, b: float32, tol: float32): boolean {
	const d: float32 = a - b;
	return d < tol && d > -tol;
}

function heapsState(): EmitterState {
	return {
		...EmitterState.defaults(), shape: { kind: ShapeKind.Point }, emitRate: constant(8.0),
		speed: constant(0.0), life: constant(100.0), maxParts: 100,
	};
}

function lowered(state: EmitterState, step: float64): ParticleSystem {
	const asset = fromHeaps(state);
	if (!asset.ok) { unreachable; }
	const made = ParticleSystem.create(asset.value, 7);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = step;
	sys.clock.maxFrameTime = 1.0;
	sys.gravity = HEAPS_GRAVITY;
	playSystem(sys, identity());
	return sys;
}

function advance(ref sys: ParticleSystem, frame: float64, frames: int32): void {
	for (let k = 0; k < frames; k++) {
		const done = updateSystem(sys, frame, identity());
		if (!done.ok) { unreachable; }
	}
}

function column(sys: ParticleSystem, c: int32, i: int32): float32 {
	return sys.data[c * sys.capacity + i];
}

function slotAged(sys: ParticleSystem, age: float64): int32 {
	for (let i = 0; i < sys.count; i++) {
		if (near(column(sys, AGE, i), age as float32, 1e-3)) { return i; }
	}
	return -1;
}

function gap(a: float32, b: float32): float32 {
	const d: float32 = a - b;
	return d < 0.0 ? -d : d;
}

function larger(a: float32, b: float32): float32 {
	return a > b ? a : b;
}

function rateCurve(v: ParticleValue): CompiledMinMaxCurve {
	const asset = fromHeaps({ ...EmitterState.defaults(), emitRate: v });
	if (!asset.ok) { unreachable; }
	const compiled = asset.value.emission.rateOverTime.compile();
	if (!compiled.ok) { unreachable; }
	return compiled.value;
}

// tests/oracle/particles3d.snapshot values-evaluate: every value kind at time 0.3 with the
// draw fixed at 0.625, tol 1e-6.
test "every Heaps value kind lowers to a curve that reads the oracle's numbers" {
	const values: Vec<ParticleValue> = [
		constant(2.0),
		{ kind: ValueKind.Linear, start: 1.0, length: 2.0 },
		{ kind: ValueKind.Pow, start: 1.0, length: 2.0, power: 3.0 },
		{ kind: ValueKind.Sin, frequency: 2.0, amplitude: 3.0, offset: 1.0 },
		{ kind: ValueKind.Cos, frequency: 2.0, amplitude: 3.0, offset: 1.0 },
		{ kind: ValueKind.Random, start: 1.0, length: 4.0, converge: Converge.No },
		{ kind: ValueKind.Random, start: 1.0, length: 4.0, converge: Converge.Start },
		{ kind: ValueKind.Random, start: 1.0, length: 4.0, converge: Converge.End },
	];
	const expected: Vec<float32> = [
		2.0, 1.6, 1.054, 2.6939274201851062, 3.476006844729035, 3.5, 1.75, 2.75,
	];
	for (let i = 0; i < 8; i++) {
		assert near(rateCurve(values[i]).evaluate(0.3, 0.625), expected[i], 1e-6);
	}
}

test "a polynomial and a power below one are sampled within a bound across the whole life" {
	const poly: ParticleValue = { kind: ValueKind.Poly, values: [0.5, -1.0, 3.0, 2.0] };
	const root: ParticleValue = { kind: ValueKind.Pow, start: 0.0, length: 1.0, power: 0.5 };
	const wave: ParticleValue = { kind: ValueKind.Sin, frequency: 12.0, amplitude: 2.0, offset: 0.0 };
	let worstPoly: float32 = 0.0;
	let worstWave: float32 = 0.0;
	let worstRoot: float32 = 0.0;
	const polyCurve = rateCurve(poly);
	const waveCurve = rateCurve(wave);
	const rootCurve = rateCurve(root);
	for (let i = 0; i <= 200; i++) {
		const t: float32 = (i as float32) / 200.0;
		worstPoly = larger(worstPoly, gap(polyCurve.evaluate(t, 0.0), poly.evaluate(t, 0.0)));
		worstWave = larger(worstWave, gap(waveCurve.evaluate(t, 0.0), wave.evaluate(t, 0.0)));
		worstRoot = larger(worstRoot, gap(rootCurve.evaluate(t, 0.0), root.evaluate(t, 0.0)));
	}
	assert worstPoly < 1e-5;
	assert worstWave < 1e-3;
	assert worstRoot < 0.05;
	assert divergences({ ...EmitterState.defaults(), emitRate: poly }).has(HeapsDivergence.ValueSampled);
}

function atAge(sys: ParticleSystem, age: float64): int32 {
	const i: int32 = slotAged(sys, age);
	if (i < 0) { unreachable; }
	return i;
}

function colorState(): EmitterState {
	return {
		...EmitterState.defaults(), emitRate: constant(10.0), life: constant(1.0),
		colors: [{ time: 0.0, color: 0xFF8000 }, { time: 0.5, color: 0x0040FF }, { time: 0.9, color: 0xFFFFFF }],
		light: { kind: ValueKind.Linear, start: 1.0, length: -0.5 },
		alpha: { kind: ValueKind.Linear, start: 1.0, length: -1.0 },
	};
}

// color-keys-light-alpha: the oracle's particles 0 and 5 are 0.8 and 0.3 of a life old. The
// light is the one lossy part (GradientSampled); alpha is exact.
test "colour keys, light and alpha read the oracle's colours at the same particle age" {
	const state = colorState();
	let sys = lowered(state, 0.1);
	advance(sys, 0.1, 9);
	const old: int32 = atAge(sys, 0.8);
	const young: int32 = atAge(sys, 0.3);
	assert near(column(sys, COLOR_A, old), 0.20000000000000007, 1e-5);
	assert near(column(sys, COLOR_A, young), 0.7000000000000001, 1e-5);
	const bound: float32 = 0.02;
	assert near(column(sys, COLOR_R, old), 0.44999999999999996, bound);
	assert near(column(sys, COLOR_G, old), 0.4876470588235294, bound);
	assert near(column(sys, COLOR_B, old), 0.6000000000000001, bound);
	assert near(column(sys, COLOR_R, young), 0.34000000000000014, bound);
	assert near(column(sys, COLOR_G, young), 0.29866666666666675, bound);
	assert near(column(sys, COLOR_B, young), 0.5099999999999999, bound);
	assert divergences(state).has(HeapsDivergence.GradientSampled);
}

function refused(state: EmitterState, why: HeapsLoweringError): boolean {
	const r = fromHeaps(state);
	return !r.ok && r.error == why;
}

test "every input Unity cannot carry is refused by name" {
	const base = heapsState();
	const ramp: ParticleValue = { kind: ValueKind.Linear, start: 1.0, length: 1.0 };
	let s = base;
	s.maxParts = 0;
	assert refused(s, HeapsLoweringError.NoCapacity);
	s = base;
	s.globalLife = 0.0;
	assert refused(s, HeapsLoweringError.NonPositiveLife);
	s = base;
	s.frame = constant(0.5);
	s.frameCount = 0;
	assert refused(s, HeapsLoweringError.NoFrames);
	s = base;
	s.globalSpeed = ramp;
	assert refused(s, HeapsLoweringError.GlobalSpeedNotConstant);
	s = base;
	s.globalSpeed = constant(-1.0);
	assert refused(s, HeapsLoweringError.NegativeGlobalSpeed);
	s = base;
	s.globalSize = ramp;
	assert refused(s, HeapsLoweringError.GlobalSizeNotConstant);
	s = base;
	s.shape = { kind: ShapeKind.Sphere, radius: ramp };
	assert refused(s, HeapsLoweringError.ShapeValueNotConstant);
	s = base;
	s.shape = { kind: ShapeKind.Sphere, radius: constant(-1.0) };
	assert refused(s, HeapsLoweringError.NegativeShapeValue);
	s = base;
	s.shape = { kind: ShapeKind.Cone, radius: constant(1.0), angle: constant(2.0) };
	assert refused(s, HeapsLoweringError.ConeAngleOutOfRange);
	s = base;
	s.shape = { kind: ShapeKind.Ring, radius: constant(2.0), inner: constant(1.0), height: 1.0, axis: vec3(0.0, 1.0, 0.0), coneAngle: 90.0 };
	assert refused(s, HeapsLoweringError.RingNotFlat);
	s = base;
	s.shape = { kind: ShapeKind.Ring, radius: constant(2.0), inner: constant(1.0), height: 0.0, axis: vec3(1.0, 1.0, 0.0), coneAngle: 90.0 };
	assert refused(s, HeapsLoweringError.RingAxisNotAligned);
	s = base;
	s.shape = { kind: ShapeKind.Ring, radius: constant(1.0), inner: constant(2.0), height: 0.0, axis: vec3(0.0, 1.0, 0.0), coneAngle: 90.0 };
	assert refused(s, HeapsLoweringError.RingInnerAboveOuter);
	s = base;
	s.bursts = [{ time: 1.0, count: 3 }];
	assert refused(s, HeapsLoweringError.BurstOutsideCycle);
	s.bursts = [{ time: 0.0, count: 3 }];
	assert refused(s, HeapsLoweringError.BurstOutsideCycle);
	s = base;
	s.colors = [{ time: 0.5, color: 0xFF0000 }, { time: 0.2, color: 0x00FF00 }];
	assert refused(s, HeapsLoweringError.ColorKeysUnordered);
	s = base;
	s.light = { kind: ValueKind.Random, start: 0.0, length: 1.0, converge: Converge.No };
	assert refused(s, HeapsLoweringError.RandomLightOrAlpha);
	s = base;
	s.size = ramp;
	s.ratio = ramp;
	assert refused(s, HeapsLoweringError.SizeRatioNotRepresentable);
	s = base;
	s.speed = ramp;
	s.initialSpeed = ramp;
	assert refused(s, HeapsLoweringError.SpeedAndInitialSpeedBothVary);
	s = base;
	s.rotation = { kind: ValueKind.Linear, start: 0.0, length: 1.0 };
	s.life = { kind: ValueKind.Random, start: 1.0, length: 1.0, converge: Converge.No };
	assert refused(s, HeapsLoweringError.RotationNotRepresentable);
}

// The sys.count after each of the first `expected.length` steps, with `count: 3` bursts at `times`
// and no emission. Heaps' emitter fires the same bursts in the same steps: the expected counts
// are what it counted before it was retired (commit efd64688).
function burstCountsMatch(times: float64[], expected: int32[], dt: float64, globalLife: float64): boolean {
	let state = heapsState();
	state.emitRate = constant(0.0);
	state.globalLife = globalLife;
	let list: Vec<HeapsBurst> = [];
	for (const t of times) { list.push({ time: t, count: 3 }); }
	state.bursts = list;
	for (let n = 1; n <= expected.length; n++) {
		let sys = lowered(state, dt);
		advance(sys, dt, n);
		if (sys.count != expected[n - 1]) { return false; }
	}
	return true;
}

test "bursts fire in the same step as the Heaps emitter, including a burst off the step grid" {
	assert burstCountsMatch([0.1, 0.2, 0.3, 0.4, 0.7], [3, 6, 9, 12, 12, 15, 15, 15, 18, 21], 0.125, 1.0);
}

test "a burst on a step boundary fires once, in the step that ends on it" {
	assert burstCountsMatch([0.25, 0.5], [0, 3, 3, 6, 6, 6, 6, 6, 6, 9], 0.125, 1.0);
}

test "a burst scales with the global life" {
	assert burstCountsMatch([0.35], [0, 0, 3, 3, 3], 0.25, 2.0);
}

test "a one-shot stops emitting after its cycle" {
	let state = heapsState();
	state.loop = false;
	state.life = constant(0.25);
	let sys = lowered(state, 0.125);
	advance(sys, 0.125, 20);
	assert sys.count == 0;
}

test "a spawned particle has a fresh random draw per life" {
	let state = heapsState();
	state.maxParts = 1;
	state.emitRate = constant(5.0);
	state.life = constant(0.3);
	state.size = { kind: ValueKind.Random, start: 0.1, length: 1.0, converge: Converge.No };
	let sys = lowered(state, 0.2);
	advance(sys, 0.2, 1);
	const first: float32 = column(sys, SIZE_X, 0);
	advance(sys, 0.2, 3);
	assert sys.count == 1 && !near(first, column(sys, SIZE_X, 0), 1e-6);
}

test "a cone spawns upward in the Y-up convention" {
	let state = heapsState();
	state.speed = constant(1.0);
	state.shape = { kind: ShapeKind.Cone, radius: constant(0.0), angle: constant(0.7853981633974483) };
	let sys = lowered(state, 0.125);
	advance(sys, 0.125, 9);
	assert sys.count > 0;
	for (let i = 0; i < sys.count; i++) {
		const y: float32 = column(sys, POS_Y, i);
		const x: float32 = column(sys, POS_X, i);
		const z: float32 = column(sys, POS_Z, i);
		assert y >= 0.0;
		assert x * x + z * z <= y * y * 1.0001;
	}
}

test "a line spawns along Y and a disc in the XZ plane" {
	let state = heapsState();
	state.shape = { kind: ShapeKind.Line, size: constant(3.0) };
	let sys = lowered(state, 0.125);
	advance(sys, 0.125, 9);
	assert sys.count > 0;
	for (let i = 0; i < sys.count; i++) {
		assert near(column(sys, POS_X, i), 0.0, 1e-5) && near(column(sys, POS_Z, i), 0.0, 1e-5);
		assert column(sys, POS_Y, i) >= -1e-5 && column(sys, POS_Y, i) <= 3.00001;
	}
	state.shape = { kind: ShapeKind.Disc, radius: constant(2.0) };
	sys = lowered(state, 0.125);
	advance(sys, 0.125, 9);
	assert sys.count > 0;
	for (let i = 0; i < sys.count; i++) {
		const x: float32 = column(sys, POS_X, i);
		const z: float32 = column(sys, POS_Z, i);
		assert near(column(sys, POS_Y, i), 0.0, 1e-5) && x * x + z * z <= 4.0001;
	}
}

test "a box keeps the Heaps extents on the port axes" {
	let state = heapsState();
	state.shape = {
		kind: ShapeKind.Box,
		extents: { x: constant(1.0), y: constant(2.0), z: constant(3.0) },
	};
	let sys = lowered(state, 0.125);
	advance(sys, 0.125, 17);
	let reachX: float32 = 0.0;
	let reachY: float32 = 0.0;
	let reachZ: float32 = 0.0;
	for (let i = 0; i < sys.count; i++) {
		const x: float32 = gap(column(sys, POS_X, i), 0.0);
		const y: float32 = gap(column(sys, POS_Y, i), 0.0);
		const z: float32 = gap(column(sys, POS_Z, i), 0.0);
		assert x <= 1.0001 && y <= 2.0001 && z <= 3.0001;
		reachX = larger(reachX, x);
		reachY = larger(reachY, y);
		reachZ = larger(reachZ, z);
	}
	assert reachY > reachX && reachZ > reachY;
}

test "the divergence set names what a state loses" {
	const plain = divergences(heapsState());
	assert plain.has(HeapsDivergence.EmissionCeil) && plain.has(HeapsDivergence.SpawnAge);
	assert !plain.has(HeapsDivergence.GradientSampled) && !plain.has(HeapsDivergence.ValueSampled);
	let s = heapsState();
	s.damping = constant(1.0);
	s.speed = constant(1.0);
	assert divergences(s).has(HeapsDivergence.DampingReachesSpeed);
	s = heapsState();
	s.rotation = { kind: ValueKind.Sin, frequency: 5.0, amplitude: 1.0, offset: 0.5 };
	assert divergences(s).has(HeapsDivergence.ValueSampled);
}

// Expected values: tests/oracle/godotNoise.js, a second float32 transcription of the shader text
// in particle_process_material.cpp:405-481 (no Godot build ran).
test "the noise direction matches Godot's GLSL transcribed in float32 on the Godot side" {
	const a: Vec3 = noiseDirection(vec3(0.3, -0.7, 1.1), 0.0, 1.0, 4.0, vec3(0.0, 0.0, 0.0), 0.0);
	assert near(a.x, 0.35435, 0.003) && near(a.y, -0.93215, 0.003) && near(a.z, 0.07436, 0.003);
	const b: Vec3 = noiseDirection(vec3(0.3, -0.7, 1.1), 0.5, 1.0, 4.0, vec3(1.0, 0.5, 0.25), 0.2);
	assert near(b.x, -0.67330, 0.003) && near(b.y, -0.31516, 0.003) && near(b.z, -0.66883, 0.003);
	const c: Vec3 = noiseDirection(vec3(-2.5, 3.1, 0.4), 1.25, 1.0, -0.104, vec3(0.0, 0.0, 0.0), 0.2);
	assert near(c.x, 0.17383, 0.003) && near(c.y, -0.57915, 0.003) && near(c.z, 0.79647, 0.003);
	const d: Vec3 = noiseDirection(vec3(1.9, 0.2, -3.3), 2.0, 3.0, 6.0, vec3(0.5, 0.5, 0.5), 0.2);
	assert near(d.x, 0.44212, 0.003) && near(d.y, 0.89155, 0.003) && near(d.z, 0.09837, 0.003);
}

test "the noise scale property becomes the shader's frequency as set_turbulence_noise_scale does" {
	assert near(shaderNoiseScale(9.0), -0.10399, 0.0005);
	assert near(shaderNoiseScale(10.0), 0.0, 0.0005);
	assert near(shaderNoiseScale(0.0), -4.0, 0.0005);
}
