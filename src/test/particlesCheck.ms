import { Vec3, vec3, Mat4, identity, translation, rotationZ } from "../math/math3d";
import {
	ParticleValue,
	ValueKind,
	Converge,
	ShapeKind,
	EmitterState,
	ParticleEmitter,
	ParticleError,
	ParticleRandom,
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
	const fallback: Result<ParticleEmitter, ParticleError> =
		ParticleEmitter.create(EmitterState.defaults(), seed);
	return fallback.value;
}

function step(ref emitter: ParticleEmitter, dt: float64): int32 {
	const stepped: Result<int32, ParticleError> = updateEmitter(emitter, dt, identity());
	return stepped.ok ? stepped.value : -1;
}

function instancesOf(ref emitter: ParticleEmitter, world: Mat4): Vec<float32> {
	const out: Vec<float32> = new Array(emitter.state.maxParts * PARTICLE_INSTANCE_STRIDE);
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
	const short: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE);
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
