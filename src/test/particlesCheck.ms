import { Vec3, vec3, Mat4, identity, translation, rotationZ } from "../math/math3d";
import {
	ParticleValue,
	ValueKind,
	Converge,
	ShapeKind,
	EmitterState,
	EmitterShape,
	Particle,
	ParticleEmitter,
	ParticleError,
	ParticleRandom,
	Turbulence,
	turbulenceAt,
	PARTICLE_INSTANCE_STRIDE,
	constant,
	nextUnit,
	updateEmitter,
	writeInstances,
	clearParticles,
} from "../void3d/particles";
import { approx } from "./helpers";

function emitterFor(state: EmitterState, seed: uint32): ParticleEmitter {
	const made: Result<ParticleEmitter, ParticleError> = ParticleEmitter.create(state, seed);
	if (made.ok) { return made.value; }
	unreachable;
}

function step(ref emitter: ParticleEmitter, dt: float64): int32 {
	const stepped: Result<int32, ParticleError> = updateEmitter(emitter, dt, identity());
	return stepped.ok ? stepped.value : -1;
}

function instancesOf(ref emitter: ParticleEmitter, world: Mat4): Vec<float32> {
	let out: Vec<float32> = new Array(emitter.state.maxParts * PARTICLE_INSTANCE_STRIDE);
	const written: Result<int32, ParticleError> = writeInstances(emitter, world, out);
	if (!written.ok) { return []; }
	return out;
}

// A still emitter: particles appear at the origin and do not move, so counts and times are
// the only things that change.
function still(rate: float32): EmitterState {
	return {
		...EmitterState.defaults(),
		emitRate: constant(rate),
		shape: { kind: ShapeKind.Line, size: constant(0.0) },
		speed: constant(0.0),
		maxParts: 64,
	};
}

// ---- values: State.eval ----

test "each value kind evaluates as State.eval does" {
	const linear: ParticleValue = { kind: ValueKind.Linear, start: 1.0, length: 2.0 };
	const power: ParticleValue = { kind: ValueKind.Pow, start: 1.0, length: 2.0, power: 2.0 };
	const sine: ParticleValue = {
		kind: ValueKind.Sin, frequency: 2.0, amplitude: 3.0, offset: 1.0,
	};
	const cosine: ParticleValue = {
		kind: ValueKind.Cos, frequency: 2.0, amplitude: 3.0, offset: 1.0,
	};
	assert approx(constant(4.0).evaluate(0.3, 0.9), 4.0);
	assert approx(linear.evaluate(0.25, 0.9), 1.5);
	assert approx(power.evaluate(0.5, 0.9), 1.5);
	assert approx(sine.evaluate(0.25, 0.9), (Math.sin(0.5) as float32) * 3.0 + 1.0);
	assert approx(cosine.evaluate(0.25, 0.9), (Math.cos(0.5) as float32) * 3.0 + 1.0);
}

function randomSpan(converge: Converge): ParticleValue {
	return { kind: ValueKind.Random, start: 1.0, length: 4.0, converge: converge };
}

test "a random value converges its span toward the start or the end of the life" {
	const none: ParticleValue = randomSpan(Converge.No);
	const toStart: ParticleValue = randomSpan(Converge.Start);
	const toEnd: ParticleValue = randomSpan(Converge.End);
	assert approx(none.evaluate(0.25, 0.5), 3.0);
	assert approx(toStart.evaluate(0.25, 0.5), 1.5);
	assert approx(toEnd.evaluate(0.25, 0.5), 2.5);
	assert none.drawsRandom() && !constant(1.0).drawsRandom();
}

test "the random sequence is fixed by its seed and stays in [0, 1)" {
	let a: ParticleRandom = ParticleRandom.seeded(7);
	let b: ParticleRandom = ParticleRandom.seeded(7);
	let c: ParticleRandom = ParticleRandom.seeded(8);
	let differs: boolean = false;
	for (let i = 0; i < 1000; i++) {
		const x: float32 = nextUnit(a);
		assert x >= 0.0 && x < 1.0;
		assert x == nextUnit(b);
		if (x != nextUnit(c)) { differs = true; }
	}
	assert differs;
	let zero: ParticleRandom = ParticleRandom.seeded(0);
	assert nextUnit(zero) != nextUnit(zero);
}

// ---- spawn and lifetime ----

test "an emitter owes rate times elapsed particles and carries the fraction over" {
	let emitter: ParticleEmitter = emitterFor({ ...still(10.0), globalLife: 4.0 }, 1);
	assert step(emitter, 0.25) == 3;
	assert approx(emitter.emitCount as float32, -0.5);
	assert step(emitter, 0.25) == 5;
}

test "no more than maxParts live, and the particles owed past it are dropped, not queued" {
	let emitter: ParticleEmitter =
		emitterFor({ ...still(100.0), maxParts: 8, life: constant(10.0), globalLife: 10.0 }, 1);
	assert step(emitter, 0.5) == 8;
	assert approx(emitter.emitCount as float32, 0.0);
	assert step(emitter, 0.001) == 8;
}

test "a particle lives `life` seconds and a one-shot emitter then goes quiet" {
	let emitter: ParticleEmitter = emitterFor(
		{ ...still(4.0), loop: false, life: constant(0.5), globalLife: 1.0 },
		1,
	);
	assert step(emitter, 0.25) == 1;
	assert step(emitter, 0.25) == 2;
	assert step(emitter, 0.25) == 2;
	assert emitter.isActive();
	assert step(emitter, 0.25) == 1;
	assert step(emitter, 0.3) == 0;
	assert !emitter.isActive();
}

test "a burst fires once when the cycle crosses its time" {
	let emitter: ParticleEmitter = emitterFor(
		{ ...still(0.0), bursts: [{ time: 0.5, count: 6 }], life: constant(10.0), globalLife: 1.0 },
		1,
	);
	assert step(emitter, 0.4) == 0;
	assert step(emitter, 0.2) == 6;
	assert step(emitter, 0.2) == 6;
}

test "dead particles leave the live range and the survivors keep their order" {
	const sizes: ParticleValue = {
		kind: ValueKind.Random, start: 0.0, length: 1.0, converge: Converge.No,
	};
	let emitter: ParticleEmitter = emitterFor(
		{ ...still(0.0), life: { kind: ValueKind.Linear, start: 1.0, length: 4.0 }, size: sizes },
		3,
	);
	emitter.emitCount = 3.0;
	emitter.time = 0.0;
	assert step(emitter, 0.0) == 3;
	const first: float32 = emitter.particles[0].size;
	const third: float32 = emitter.particles[2].size;
	emitter.particles[1].lifeTimeFactor = 100.0;
	assert step(emitter, 0.1) == 2;
	assert emitter.particles[0].size == first;
	assert emitter.particles[1].size == third;
}

test "the same seed and the same steps write the same instances; another seed does not" {
	const state: EmitterState = {
		...EmitterState.defaults(),
		maxParts: 128,
		emitRate: constant(60.0),
		size: { kind: ValueKind.Random, start: 0.1, length: 0.2, converge: Converge.End },
		speed: { kind: ValueKind.Random, start: 1.0, length: 2.0, converge: Converge.No },
		gravity: constant(0.5),
	};
	let a: ParticleEmitter = emitterFor(state, 42);
	let b: ParticleEmitter = emitterFor(state, 42);
	let c: ParticleEmitter = emitterFor(state, 43);
	for (let i = 0; i < 90; i++) {
		assert step(a, 1.0 / 30.0) == step(b, 1.0 / 30.0);
		const _c: int32 = step(c, 1.0 / 30.0);
	}
	assert a.count > 50;
	const left: Vec<float32> = instancesOf(a, identity());
	const right: Vec<float32> = instancesOf(b, identity());
	const other: Vec<float32> = instancesOf(c, identity());
	let same: boolean = true;
	let differs: boolean = false;
	for (let i = 0; i < a.count * PARTICLE_INSTANCE_STRIDE; i++) {
		if (left[i] != right[i]) { same = false; }
		if (left[i] != other[i]) { differs = true; }
	}
	assert same && differs;
}

// ---- motion, frame and color ----

test "gravity pulls along -Y, the axis Heaps calls z" {
	let emitter: ParticleEmitter = emitterFor(
		{ ...still(0.0), gravity: constant(2.0), life: constant(10.0) },
		1,
	);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.5) == 1;
	const at: Vec3 = emitter.particles[0].position;
	assert approx(at.x, 0.0) && approx(at.z, 0.0);
	assert approx(at.y, -0.5);
}

test "a cone points up +Y and speed moves a particle along its direction" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: { kind: ShapeKind.Cone, radius: constant(0.0), angle: constant(0.0) },
		speed: constant(3.0),
		life: constant(10.0),
	}, 1);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.5) == 1;
	assert approx(emitter.particles[0].direction.y, 1.0);
	assert approx(emitter.particles[0].position.y, 1.5);
}

test "a disc lies in XZ, and emitting from its shell puts every particle on the rim" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: { kind: ShapeKind.Disc, radius: constant(2.0) },
		emitFromShell: true,
		life: constant(10.0),
	}, 5);
	emitter.emitCount = 20.0;
	assert step(emitter, 0.0) == 20;
	for (let i = 0; i < 20; i++) {
		const p: Vec3 = emitter.particles[i].position;
		assert approx(p.y, 0.0);
		assert approx(p.x * p.x + p.z * p.z, 4.0);
	}
}

function absf(x: float32): float32 {
	return x < 0.0 ? -x : x;
}

function minf(a: float32, b: float32): float32 {
	return a < b ? a : b;
}

function maxf(a: float32, b: float32): float32 {
	return a > b ? a : b;
}

function emittedFrom(shape: EmitterShape, shell: boolean, count: int32, seed: uint32): ParticleEmitter {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: shape,
		emitFromShell: shell,
		life: constant(10.0),
		maxParts: count,
	}, seed);
	emitter.emitCount = count as float64;
	if (step(emitter, 0.0) != count) { unreachable; }
	return emitter;
}

test "a point emits every particle at the origin, pointing up, and draws no random" {
	const before: uint32 = ParticleRandom.seeded(3).state;
	const emitter: ParticleEmitter = emittedFrom({ kind: ShapeKind.Point }, false, 10, 3);
	assert emitter.sequence.state == before;
	for (let i = 0; i < 10; i++) {
		const p: Particle = emitter.particles[i];
		assert approx(p.position.x, 0.0) && approx(p.position.y, 0.0) && approx(p.position.z, 0.0);
		assert approx(p.direction.y, 1.0);
	}
}

function boxOf(x: float32, y: float32, z: float32): EmitterShape {
	return { kind: ShapeKind.Box, size: { x: constant(x), y: constant(y), z: constant(z) } };
}

test "a box fills its volume, centred on the emitter, and its size is the full extent" {
	const emitter: ParticleEmitter = emittedFrom(boxOf(2.0, 4.0, 6.0), false, 300, 11);
	let low: Vec3 = vec3(9.0, 9.0, 9.0);
	let high: Vec3 = vec3(-9.0, -9.0, -9.0);
	for (let i = 0; i < 300; i++) {
		const p: Vec3 = emitter.particles[i].position;
		assert p.x >= -1.0 && p.x <= 1.0 && p.y >= -2.0 && p.y <= 2.0 && p.z >= -3.0 && p.z <= 3.0;
		assert approx(emitter.particles[i].direction.y, 1.0);
		low = vec3(minf(low.x, p.x), minf(low.y, p.y), minf(low.z, p.z));
		high = vec3(maxf(high.x, p.x), maxf(high.y, p.y), maxf(high.z, p.z));
	}
	assert low.x < -0.9 && high.x > 0.9 && low.y < -1.8 && high.y > 1.8 && low.z < -2.7 && high.z > 2.7;
}

test "a box emitted from its shell lies on a face, and every face is reached" {
	const emitter: ParticleEmitter = emittedFrom(boxOf(2.0, 2.0, 2.0), true, 600, 5);
	let faces: int32 = 0;
	let reached: Vec<boolean> = [false, false, false, false, false, false];
	for (let i = 0; i < 600; i++) {
		const p: Vec3 = emitter.particles[i].position;
		assert absf(p.x) <= 1.0001 && absf(p.y) <= 1.0001 && absf(p.z) <= 1.0001;
		const onFace: boolean = approx(absf(p.x), 1.0) || approx(absf(p.y), 1.0) || approx(absf(p.z), 1.0);
		assert onFace;
		if (approx(p.x, 1.0)) { reached[0] = true; }
		if (approx(p.x, -1.0)) { reached[1] = true; }
		if (approx(p.y, 1.0)) { reached[2] = true; }
		if (approx(p.y, -1.0)) { reached[3] = true; }
		if (approx(p.z, 1.0)) { reached[4] = true; }
		if (approx(p.z, -1.0)) { reached[5] = true; }
	}
	for (let f = 0; f < 6; f++) { if (reached[f]) { faces = faces + 1; } }
	assert faces == 6;
}

test "a shell box weighs its faces by area" {
	const emitter: ParticleEmitter = emittedFrom(boxOf(8.0, 2.0, 2.0), true, 800, 21);
	let ends: int32 = 0;
	for (let i = 0; i < 800; i++) {
		if (approx(absf(emitter.particles[i].position.x), 4.0)) { ends = ends + 1; }
	}
	assert ends > 800 / 9 - 40 && ends < 800 / 9 + 40;
}

function ringOf(radius: float32, inner: float32): EmitterShape {
	return { kind: ShapeKind.Ring, radius: constant(radius), inner: constant(inner) };
}

test "a ring lies in XZ between its radii and points away from its centre" {
	const emitter: ParticleEmitter = emittedFrom(ringOf(2.0, 1.0), false, 200, 7);
	for (let i = 0; i < 200; i++) {
		const p: Particle = emitter.particles[i];
		const r2: float32 = p.position.x * p.position.x + p.position.z * p.position.z;
		assert approx(p.position.y, 0.0) && r2 >= 0.99 && r2 <= 4.01;
		const r: float32 = Math.sqrt(r2) as float32;
		assert approx(p.direction.x * r, p.position.x) && approx(p.direction.z * r, p.position.z);
	}
}

test "a ring emitted from its shell sits on the outer rim, and with no hole it is Heaps' disc" {
	const rim: ParticleEmitter = emittedFrom(ringOf(2.0, 1.0), true, 50, 7);
	for (let i = 0; i < 50; i++) {
		const p: Vec3 = rim.particles[i].position;
		assert approx(p.x * p.x + p.z * p.z, 4.0);
	}
	const ring: ParticleEmitter = emittedFrom(ringOf(2.0, 0.0), false, 50, 9);
	const disc: ParticleEmitter = emittedFrom({ kind: ShapeKind.Disc, radius: constant(2.0) }, false, 50, 9);
	for (let i = 0; i < 50; i++) {
		assert ring.particles[i].position.x == disc.particles[i].position.x;
		assert ring.particles[i].position.z == disc.particles[i].position.z;
	}
}

test "damping bleeds the velocity that gravity and forces built, and leaves the speed curve alone" {
	let emitter: ParticleEmitter = emitterFor(
		{ ...still(0.0), gravity: constant(2.0), damping: constant(2.0), life: constant(100.0) },
		1,
	);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.5) == 1;
	assert approx(emitter.particles[0].force.y, -0.36788);
	assert approx(emitter.particles[0].position.y, -0.18394);
	for (let i = 0; i < 100; i++) { const _s: int32 = step(emitter, 0.1); }
	assert emitter.particles[0].force.y < -0.85 && emitter.particles[0].force.y > -1.0;
	let free: ParticleEmitter = emitterFor(
		{ ...still(0.0), gravity: constant(2.0), life: constant(100.0) },
		1,
	);
	free.emitCount = 1.0;
	for (let i = 0; i < 101; i++) { const _s: int32 = step(free, 0.1); }
	assert free.particles[0].force.y < -15.0;
	let driven: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: { kind: ShapeKind.Cone, radius: constant(0.0), angle: constant(0.0) },
		speed: constant(3.0),
		damping: constant(5.0),
		life: constant(10.0),
	}, 1);
	driven.emitCount = 1.0;
	assert step(driven, 0.5) == 1;
	assert approx(driven.particles[0].position.y, 1.5);
}

test "a random damping is drawn once per life like any other particle value" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		gravity: constant(2.0),
		damping: { kind: ValueKind.Random, start: 0.0, length: 4.0, converge: Converge.No },
		life: constant(100.0),
	}, 9);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.1) == 1;
	const drawn: uint32 = emitter.sequence.state;
	assert step(emitter, 0.1) == 1;
	assert emitter.sequence.state == drawn;
}

test "the turbulence field is bounded, smooth, and changes with place and time" {
	const here: Vec3 = vec3(0.3, -0.7, 1.1);
	const a: Vec3 = turbulenceAt(here, 0.5, 2.0, 1.0);
	assert absf(a.x) <= 1.0 && absf(a.y) <= 1.0 && absf(a.z) <= 1.0;
	const near: Vec3 = turbulenceAt(vec3(0.301, -0.7, 1.1), 0.5, 2.0, 1.0);
	assert absf(near.x - a.x) < 0.01 && absf(near.y - a.y) < 0.01 && absf(near.z - a.z) < 0.01;
	const far: Vec3 = turbulenceAt(vec3(2.3, 0.7, -1.1), 0.5, 2.0, 1.0);
	assert absf(far.x - a.x) + absf(far.y - a.y) + absf(far.z - a.z) > 0.1;
	const later: Vec3 = turbulenceAt(here, 1.5, 2.0, 1.0);
	assert absf(later.x - a.x) + absf(later.y - a.y) + absf(later.z - a.z) > 0.1;
	const frozen: Vec3 = turbulenceAt(here, 1.5, 2.0, 0.0);
	const frozenAgain: Vec3 = turbulenceAt(here, 9.5, 2.0, 0.0);
	assert frozen.x == frozenAgain.x && frozen.y == frozenAgain.y && frozen.z == frozenAgain.z;
}

test "turbulence pushes a particle by its strength times the field at the particle" {
	const field: Turbulence = { strength: constant(4.0), scale: 2.0, speed: 1.0 };
	let calm: ParticleEmitter = emitterFor({ ...still(0.0), life: constant(10.0) }, 1);
	let shaken: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: { kind: ShapeKind.Box, size: { x: constant(2.0), y: constant(2.0), z: constant(2.0) } },
		turbulence: field,
		life: constant(10.0),
	}, 1);
	calm.emitCount = 1.0;
	shaken.emitCount = 1.0;
	assert step(calm, 0.1) == 1;
	assert step(shaken, 0.0) == 1;
	const at: Vec3 = shaken.particles[0].position;
	assert step(shaken, 0.1) == 1;
	const expected: Vec3 = turbulenceAt(at, 0.1, 2.0, 1.0);
	assert approx(shaken.particles[0].force.x, expected.x * 0.4);
	assert approx(shaken.particles[0].force.y, expected.y * 0.4);
	assert approx(shaken.particles[0].force.z, expected.z * 0.4);
	assert calm.particles[0].force.x == 0.0 && calm.particles[0].force.y == 0.0;
}

test "a calm emitter and one with zero turbulence write the same instances" {
	const state: EmitterState = {
		...EmitterState.defaults(),
		maxParts: 64,
		emitRate: constant(40.0),
		gravity: constant(0.5),
	};
	let a: ParticleEmitter = emitterFor(state, 4);
	let b: ParticleEmitter = emitterFor({ ...state, turbulence: { strength: constant(0.0), scale: 3.0, speed: 2.0 } }, 4);
	for (let i = 0; i < 40; i++) { assert step(a, 1.0 / 30.0) == step(b, 1.0 / 30.0); }
	const left: Vec<float32> = instancesOf(a, identity());
	const right: Vec<float32> = instancesOf(b, identity());
	for (let i = 0; i < a.count * PARTICLE_INSTANCE_STRIDE; i++) { assert left[i] == right[i]; }
}

test "spawn happens in world space; emitLocal defers the transform to the write" {
	const moved: Mat4 = translation(5.0, 1.0, -2.0);
	let world: ParticleEmitter = emitterFor({ ...still(0.0), life: constant(10.0) }, 1);
	world.emitCount = 1.0;
	const _w: Result<int32, ParticleError> = updateEmitter(world, 0.0, moved);
	let local: ParticleEmitter =
		emitterFor({ ...still(0.0), life: constant(10.0), emitLocal: true }, 1);
	local.emitCount = 1.0;
	const _l: Result<int32, ParticleError> = updateEmitter(local, 0.0, moved);
	assert approx(world.particles[0].position.x, 5.0);
	assert approx(local.particles[0].position.x, 0.0);
	const drawn: Vec<float32> = instancesOf(local, moved);
	assert approx(drawn[0], 5.0) && approx(drawn[1], 1.0) && approx(drawn[2], -2.0);
	const turned: Vec<float32> = instancesOf(world, rotationZ(1.0));
	assert approx(turned[0], 5.0);
}

test "color keys blend by the particle's time and multiply by light" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		colors: [{ time: 0.0, color: 0xFF0000 }, { time: 0.5, color: 0x0000FF }],
		light: constant(0.5),
		life: constant(1.0),
	}, 1);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.25) == 1;
	const p: Vec<float32> = instancesOf(emitter, identity());
	assert approx(p[4], 0.25) && approx(p[5], 0.0) && approx(p[6], 0.25);
	assert step(emitter, 0.5) == 1;
	const q: Vec<float32> = instancesOf(emitter, identity());
	assert approx(q[4], 0.0) && approx(q[6], 0.5);
}

test "an instance is position, side times globalSize, and rgba" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		size: constant(0.4),
		globalSize: constant(0.5),
		alpha: constant(0.75),
		life: constant(10.0),
	}, 1);
	emitter.emitCount = 2.0;
	assert step(emitter, 0.0) == 2;
	const out: Vec<float32> = instancesOf(emitter, identity());
	assert approx(out[3], 0.2);
	assert approx(out[4], 1.0) && approx(out[7], 0.75);
	assert approx(out[PARTICLE_INSTANCE_STRIDE + 3], 0.2);
	let short: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE);
	assert !writeInstances(emitter, identity(), short).ok;
}

test "a random value is drawn once per life, not once per update" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		size: { kind: ValueKind.Random, start: 0.0, length: 1.0, converge: Converge.No },
		life: constant(10.0),
	}, 9);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.1) == 1;
	const size: float32 = emitter.particles[0].size;
	assert step(emitter, 0.1) == 1;
	assert emitter.particles[0].size == size;
	clearParticles(emitter);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.1) == 1;
	assert emitter.particles[0].size != size;
}

test "a bad state or a non-finite step is refused" {
	assert !ParticleEmitter.create({ ...EmitterState.defaults(), maxParts: 0 }, 1).ok;
	assert !ParticleEmitter.create({ ...EmitterState.defaults(), globalLife: 0.0 }, 1).ok;
	let emitter: ParticleEmitter = emitterFor(EmitterState.defaults(), 1);
	const infinite: float64 = 1.0 / 0.0;
	assert !updateEmitter(emitter, infinite, identity()).ok;
	assert emitter.count == 0;
}

test "raising maxParts on a live emitter does not outgrow the arrays it was made with" {
	let emitter: ParticleEmitter = emitterFor({ ...still(100.0), maxParts: 4, life: constant(10.0) }, 1);
	emitter.state.maxParts = 64;
	assert step(emitter, 0.5) == 4;
}

test "globalSize is evaluated on every write, as Emitter.draw does, even with nothing alive" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		globalSize: { kind: ValueKind.Random, start: 1.0, length: 1.0, converge: Converge.No },
	}, 5);
	const before: uint32 = emitter.sequence.state;
	let out: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE);
	const written: Result<int32, ParticleError> = writeInstances(emitter, identity(), out);
	assert written.ok;
	assert emitter.sequence.state != before;
}
