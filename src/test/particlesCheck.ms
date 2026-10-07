import { Vec3, vec3, Mat4, identity, translation, rotationZ, scaling } from "../math/math3d";
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
	SortMode,
	PARTICLE_INSTANCE_STRIDE,
	constant,
	nextUnit,
	updateEmitter,
	writeInstances,
	writeSortedInstances,
	clearParticles,
} from "../void3d/particles";
import { approx } from "./helpers";
import { noiseDirection, shaderNoiseScale } from "../void3d/particleNoise";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../void3d/camera";

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

test "a poly value is Heaps' VPoly: Horner over the coefficients, and a size curve over a life" {
	const parabola: ParticleValue = { kind: ValueKind.Poly, values: [0.0, 4.0, -4.0] };
	assert approx(parabola.evaluate(0.5, 0.9), 1.0);
	assert approx(parabola.evaluate(0.25, 0.9), 0.75);
	const cubic: ParticleValue = { kind: ValueKind.Poly, values: [1.0, 2.0, 3.0] };
	assert approx(cubic.evaluate(0.5, 0.9), 2.75);
	const empty: ParticleValue = { kind: ValueKind.Poly, values: [] };
	assert approx(empty.evaluate(0.5, 0.9), 0.0);
	assert !parabola.drawsRandom();
	let emitter: ParticleEmitter = emitterFor({ ...still(0.0), size: parabola, life: constant(1.0) }, 1);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.25) == 1;
	assert approx(emitter.particles[0].size, 0.75);
	assert step(emitter, 0.25) == 1;
	assert approx(emitter.particles[0].size, 1.0);
	assert step(emitter, 0.25) == 1;
	assert approx(emitter.particles[0].size, 0.75);
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

function placedAt(depths: Vec<float32>, sortMode: SortMode): ParticleEmitter {
	let emitter: ParticleEmitter =
		emitterFor({ ...still(0.0), sortMode: sortMode, life: constant(10.0) }, 1);
	emitter.emitCount = depths.length as float64;
	if (step(emitter, 0.0) != (depths.length as int32)) { unreachable; }
	for (let i = 0; i < (depths.length as int32); i++) {
		emitter.particles[i].position = vec3(i as float32, 0.0, depths[i]);
	}
	return emitter;
}

function writtenOrder(ref emitter: ParticleEmitter, view: Mat4): Vec<float32> {
	let out: Vec<float32> = new Array(emitter.state.maxParts * PARTICLE_INSTANCE_STRIDE);
	const written: Result<int32, ParticleError> = writeSortedInstances(emitter, identity(), view, out);
	let xs: Vec<float32> = [];
	if (written.ok) {
		for (let i = 0; i < written.value; i++) { xs.push(out[i * PARTICLE_INSTANCE_STRIDE]); }
	}
	return xs;
}

test "Sort draws the farthest particle first and InvSort the nearest, as Particles.draw does" {
	let far: ParticleEmitter = placedAt([3.0, 1.0, 4.0, 0.0, 2.0], SortMode.Sort);
	const back: Vec<float32> = writtenOrder(far, identity());
	assert back.length == 5;
	assert back[0] == 2.0 && back[1] == 0.0 && back[2] == 4.0 && back[3] == 1.0 && back[4] == 3.0;
	let near: ParticleEmitter = placedAt([3.0, 1.0, 4.0, 0.0, 2.0], SortMode.InvSort);
	const front: Vec<float32> = writtenOrder(near, identity());
	assert front[0] == 3.0 && front[1] == 1.0 && front[2] == 4.0 && front[3] == 0.0 && front[4] == 2.0;
}

test "the order follows the view: a flipped view reverses what is farthest" {
	let emitter: ParticleEmitter = placedAt([3.0, 1.0, 4.0, 0.0, 2.0], SortMode.Sort);
	const flipped: Vec<float32> = writtenOrder(emitter, scaling(1.0, 1.0, -1.0));
	assert flipped[0] == 3.0 && flipped[4] == 2.0;
}

test "particles at equal depth keep the order they were emitted in" {
	let emitter: ParticleEmitter = placedAt([1.0, 1.0, 0.0, 1.0, 0.0], SortMode.Sort);
	const order: Vec<float32> = writtenOrder(emitter, identity());
	assert order[0] == 0.0 && order[1] == 1.0 && order[2] == 3.0 && order[3] == 2.0 && order[4] == 4.0;
}

test "Back keeps emission order, Front reverses it, and neither needs a view" {
	let back: ParticleEmitter = placedAt([3.0, 1.0, 4.0], SortMode.Back);
	let front: ParticleEmitter = placedAt([3.0, 1.0, 4.0], SortMode.Front);
	const kept: Vec<float32> = instancesOf(back, identity());
	const turned: Vec<float32> = instancesOf(front, identity());
	assert kept[0] == 0.0 && kept[PARTICLE_INSTANCE_STRIDE] == 1.0 && kept[2 * PARTICLE_INSTANCE_STRIDE] == 2.0;
	assert turned[0] == 2.0 && turned[PARTICLE_INSTANCE_STRIDE] == 1.0 && turned[2 * PARTICLE_INSTANCE_STRIDE] == 0.0;
}

test "a mode that sorts by view refuses a write that has no view" {
	let emitter: ParticleEmitter = placedAt([3.0, 1.0], SortMode.Sort);
	let out: Vec<float32> = new Array(2 * PARTICLE_INSTANCE_STRIDE);
	assert !writeInstances(emitter, identity(), out).ok;
}

test "a sorted write moves a particle's whole instance, and sorts many particles into depth order" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: { kind: ShapeKind.Box, extents: { x: constant(2.0), y: constant(2.0), z: constant(10.0) } },
		sortMode: SortMode.Sort,
		size: { kind: ValueKind.Random, start: 0.5, length: 1.0, converge: Converge.No },
		maxParts: 200,
		life: constant(10.0),
	}, 31);
	emitter.emitCount = 200.0;
	assert step(emitter, 0.0) == 200;
	let out: Vec<float32> = new Array(200 * PARTICLE_INSTANCE_STRIDE);
	assert writeSortedInstances(emitter, identity(), identity(), out).ok;
	for (let i = 1; i < 200; i++) {
		assert out[(i - 1) * PARTICLE_INSTANCE_STRIDE + 2] >= out[i * PARTICLE_INSTANCE_STRIDE + 2];
	}
	let matched: int32 = 0;
	for (let i = 0; i < 200; i++) {
		for (let j = 0; j < 200; j++) {
			if (out[i * PARTICLE_INSTANCE_STRIDE] == emitter.particles[j].position.x
				&& out[i * PARTICLE_INSTANCE_STRIDE + 3] == emitter.particles[j].size) {
				matched = matched + 1;
				break;
			}
		}
	}
	assert matched == 200;
}

test "an emitLocal emitter sorts by the place it is drawn at" {
	let emitter: ParticleEmitter = emitterFor(
		{ ...still(0.0), emitLocal: true, sortMode: SortMode.Sort, life: constant(10.0) },
		1,
	);
	emitter.emitCount = 2.0;
	assert step(emitter, 0.0) == 2;
	emitter.particles[0].position = vec3(0.0, 0.0, 1.0);
	emitter.particles[1].position = vec3(1.0, 0.0, 2.0);
	let out: Vec<float32> = new Array(2 * PARTICLE_INSTANCE_STRIDE);
	assert writeSortedInstances(emitter, translation(0.0, 0.0, 5.0), identity(), out).ok;
	assert out[0] == 1.0 && out[2] == 7.0 && out[PARTICLE_INSTANCE_STRIDE + 2] == 6.0;
}

function boxOf(x: float32, y: float32, z: float32): EmitterShape {
	return { kind: ShapeKind.Box, extents: { x: constant(x), y: constant(y), z: constant(z) } };
}

function near(a: float32, b: float32, tolerance: float32): boolean {
	return absf(a - b) <= tolerance;
}

test "a box fills its volume, centred, and its extents are half-widths as in Godot" {
	const emitter: ParticleEmitter = emittedFrom(boxOf(1.0, 2.0, 3.0), false, 300, 11);
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

test "a box draws x, y, z as three uniform values in [-1, 1] times its extents, as Godot's does" {
	let reference: ParticleRandom = ParticleRandom.seeded(11);
	const emitter: ParticleEmitter = emittedFrom(boxOf(1.0, 2.0, 3.0), false, 1, 11);
	const x: float32 = (nextUnit(reference) * 2.0 - 1.0) * 1.0;
	const y: float32 = (nextUnit(reference) * 2.0 - 1.0) * 2.0;
	const z: float32 = (nextUnit(reference) * 2.0 - 1.0) * 3.0;
	assert emitter.particles[0].position.x == x;
	assert emitter.particles[0].position.y == y;
	assert emitter.particles[0].position.z == z;
	assert emitter.sequence.state == reference.state;
}

function faceCounts(seed: uint32, wide: float32): Vec<int32> {
	const emitter: ParticleEmitter = emittedFrom(boxOf(wide, 1.0, 1.0), true, 900, seed);
	let counts: Vec<int32> = [0, 0, 0, 0, 0, 0];
	for (let i = 0; i < 900; i++) {
		const p: Vec3 = emitter.particles[i].position;
		if (approx(p.x, wide)) { counts[0] = counts[0] + 1; }
		if (approx(p.x, -wide)) { counts[1] = counts[1] + 1; }
		if (approx(p.y, 1.0)) { counts[2] = counts[2] + 1; }
		if (approx(p.y, -1.0)) { counts[3] = counts[3] + 1; }
		if (approx(p.z, 1.0)) { counts[4] = counts[4] + 1; }
		if (approx(p.z, -1.0)) { counts[5] = counts[5] + 1; }
	}
	return counts;
}

test "a box emitted from its shell lies on a face, and the faces are weighted by area, on two seeds" {
	const seeds: Vec<uint32> = [5, 77];
	for (let k = 0; k < 2; k++) {
		const counts: Vec<int32> = faceCounts(seeds[k], 4.0);
		let total: int32 = 0;
		for (let f = 0; f < 6; f++) { total = total + counts[f]; }
		assert total >= 900 && total <= 910;
		assert counts[0] > 900 / 18 - 30 && counts[0] < 900 / 18 + 30;
		assert counts[1] > 900 / 18 - 30 && counts[1] < 900 / 18 + 30;
		assert counts[2] > 900 * 4 / 18 - 60 && counts[2] < 900 * 4 / 18 + 60;
		assert counts[5] > 900 * 4 / 18 - 60 && counts[5] < 900 * 4 / 18 + 60;
	}
}

function ringOf(radius: float32, inner: float32, height: float32, cone: float32): EmitterShape {
	return {
		kind: ShapeKind.Ring,
		radius: constant(radius),
		inner: constant(inner),
		height: height,
		axis: vec3(0.0, 1.0, 0.0),
		coneAngle: cone,
	};
}

test "a ring is Godot's: area-uniform radius between inner and outer, a height along its axis" {
	const emitter: ParticleEmitter = emittedFrom(ringOf(2.0, 1.0, 0.5, 90.0), false, 2000, 7);
	let meanSquare: float32 = 0.0;
	let low: float32 = 9.0;
	let high: float32 = -9.0;
	for (let i = 0; i < 2000; i++) {
		const p: Particle = emitter.particles[i];
		const r2: float32 = p.position.x * p.position.x + p.position.z * p.position.z;
		assert r2 >= 0.99 && r2 <= 4.01;
		assert p.position.y >= -0.2501 && p.position.y <= 0.2501;
		const r: float32 = Math.sqrt(r2 as float64) as float32;
		assert approx(p.direction.x * r, p.position.x) && approx(p.direction.z * r, p.position.z);
		assert approx(p.direction.y, 0.0);
		meanSquare = meanSquare + r2;
		low = minf(low, p.position.y);
		high = maxf(high, p.position.y);
	}
	// sqrt(u (R^2 - r^2) + r^2) makes r^2 uniform on [1, 4]: mean 2.5. A radius linear in u gives 2.33.
	assert near(meanSquare / 2000.0, 2.5, 0.07);
	assert low < -0.2 && high > 0.2;
}

test "a ring's cone angle narrows it toward the top, by Godot's top radius" {
	const emitter: ParticleEmitter = emittedFrom(ringOf(2.0, 0.0, 1.0, 45.0), false, 600, 3);
	let seenHigh: boolean = false;
	for (let i = 0; i < 600; i++) {
		const p: Vec3 = emitter.particles[i].position;
		const y: float32 = p.y + 0.5;
		const r: float32 = Math.sqrt((p.x * p.x + p.z * p.z) as float64) as float32;
		assert r <= 2.0 * (1.0 - y * 0.5) + 0.01;
		if (y > 0.8) {
			seenHigh = true;
			assert r <= 1.21;
		}
	}
	assert seenHigh;
}

function ringCase(seed: uint32, outer: float32, inner: float32, height: float32, axis: Vec3, cone: float32): Particle {
	const shape: EmitterShape = {
		kind: ShapeKind.Ring,
		radius: constant(outer),
		inner: constant(inner),
		height: height,
		axis: axis,
		coneAngle: cone,
	};
	return emittedFrom(shape, false, 1, seed).particles[0];
}

function nearVec(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return near(a.x, x, 0.002) && near(a.y, y, 0.002) && near(a.z, z, 0.002);
}

test "a ring point is Godot's, draw for draw: a narrowing cone both ways, and a tilted and an x axis" {
	// Expected values: the `ring` lines of tests/oracle/godotNoise.js.
	const narrowing: Particle = ringCase(7, 2.0, 1.0, 1.0, vec3(1.0, 2.0, 3.0), 45.0);
	assert nearVec(narrowing.position, 0.72993, 0.79554, -0.17624);
	assert nearVec(narrowing.direction, 0.61200, 0.54855, -0.56970);
	const widening: Particle = ringCase(9, 2.0, 0.5, 1.5, vec3(0.0, 0.0, 1.0), 135.0);
	assert nearVec(widening.position, 0.82890, 0.67890, -0.72907);
	assert nearVec(widening.direction, 0.77363, 0.63364, 0.0);
	const sideways: Particle = ringCase(5, 3.0, 1.0, 2.0, vec3(1.0, 0.0, 0.0), 90.0);
	assert nearVec(sideways.position, 0.99937, 1.29036, 2.40902);
	assert nearVec(sideways.direction, 0.0, 0.47217, 0.88151);
}

test "a ring on a tilted axis lies in the plane that axis is normal to" {
	const tilted: EmitterShape = {
		kind: ShapeKind.Ring,
		radius: constant(2.0),
		inner: constant(1.0),
		height: 0.0,
		axis: vec3(1.0, 0.0, 0.0),
		coneAngle: 90.0,
	};
	const emitter: ParticleEmitter = emittedFrom(tilted, false, 100, 4);
	for (let i = 0; i < 100; i++) {
		const p: Vec3 = emitter.particles[i].position;
		assert approx(p.x, 0.0);
		const r2: float32 = p.y * p.y + p.z * p.z;
		assert r2 >= 0.99 && r2 <= 4.01;
	}
}

function forcedAlong(x: float32, y: float32, z: float32, damping: float32): ParticleEmitter {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		force: { x: constant(x), y: constant(y), z: constant(z) },
		damping: constant(damping),
		life: constant(100.0),
	}, 1);
	emitter.emitCount = 1.0;
	return emitter;
}

test "damping is Godot's: the speed falls by damping per second along its own direction, to a stop" {
	let slowed: ParticleEmitter = forcedAlong(3.0, 4.0, 0.0, 1.0);
	assert step(slowed, 0.5) == 1;
	assert approx(slowed.particles[0].force.x, 1.2) && approx(slowed.particles[0].force.y, 1.6);
	assert approx(slowed.particles[0].force.z, 0.0);
	let stopped: ParticleEmitter = forcedAlong(3.0, 4.0, 0.0, 6.0);
	assert step(stopped, 0.5) == 1;
	assert stopped.particles[0].force.x == 0.0 && stopped.particles[0].force.y == 0.0;
	let free: ParticleEmitter = forcedAlong(3.0, 4.0, 0.0, 0.0);
	assert step(free, 0.5) == 1;
	assert approx(free.particles[0].force.x, 1.5) && approx(free.particles[0].force.y, 2.0);
}

test "damping leaves the speed curve alone" {
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

test "the noise direction matches Godot's GLSL transcribed in float32 on the Godot side" {
	// Expected values: tests/oracle/godotNoise.js, a second float32 transcription of the shader
	// text in particle_process_material.cpp:405-481.
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

function shaken(influence: float32): ParticleEmitter {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		force: { x: constant(2.0), y: constant(0.0), z: constant(0.0) },
		turbulence: {
			enabled: true,
			noiseStrength: 1.0,
			noiseScale: 9.0,
			noiseSpeed: vec3(1.0, 0.5, 0.25),
			noiseSpeedRandom: 0.2,
			influence: constant(influence),
		},
		life: constant(100.0),
	}, 1);
	emitter.emitCount = 1.0;
	return emitter;
}

test "turbulence turns the velocity toward the noise direction by its influence, as Godot mixes it" {
	let emitter: ParticleEmitter = shaken(0.5);
	assert step(emitter, 0.0) == 1;
	assert step(emitter, 0.1) == 1;
	const f: Vec3 = emitter.particles[0].force;
	assert near(f.x, 0.15167, 0.002) && near(f.y, -0.07771, 0.002) && near(f.z, 0.05823, 0.002);
}

test "turbulence at influence 0, or switched off, leaves the velocity to its forces" {
	let silent: ParticleEmitter = shaken(0.0);
	assert step(silent, 0.0) == 1;
	assert step(silent, 0.1) == 1;
	assert approx(silent.particles[0].force.x, 0.2) && silent.particles[0].force.y == 0.0;
	let off: ParticleEmitter = shaken(0.5);
	off.state.turbulence.enabled = false;
	assert step(off, 0.0) == 1;
	assert step(off, 0.1) == 1;
	assert approx(off.particles[0].force.x, 0.2) && off.particles[0].force.y == 0.0;
}

test "turbulence also bends the speed-curve displacement, keeping its length" {
	let emitter: ParticleEmitter = emitterFor({
		...still(0.0),
		shape: { kind: ShapeKind.Cone, radius: constant(0.0), angle: constant(0.0) },
		speed: constant(3.0),
		turbulence: {
			enabled: true,
			noiseStrength: 1.0,
			noiseScale: 9.0,
			noiseSpeed: vec3(1.0, 0.5, 0.25),
			noiseSpeedRandom: 0.2,
			influence: constant(1.0),
		},
		life: constant(100.0),
	}, 1);
	emitter.emitCount = 1.0;
	assert step(emitter, 0.0) == 1;
	assert step(emitter, 0.1) == 1;
	const p: Vec3 = emitter.particles[0].position;
	assert approx(p.x, 0.46976 * 0.3) && approx(p.y, -0.70645 * 0.3) && approx(p.z, 0.52938 * 0.3);
}

function along(out: Vec<float32>, index: int32, direction: Vec3): float32 {
	const at: int32 = index * PARTICLE_INSTANCE_STRIDE;
	return out[at] * direction.x + out[at + 1] * direction.y + out[at + 2] * direction.z;
}

function lookingForward(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 0.0),
		yaw: 0.0,
		pitch: 0.0,
		orientation: null,
		nearPlane: 0.1,
		farPlane: 100.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
	const resolved: Result<CameraView, CameraError> = camera.resolve(640, 360);
	if (resolved.ok) { return resolved.value; }
	unreachable;
}

test "Sort under the real perspective camera puts the far particles first and the one behind the eye first of all" {
	const view: CameraView = lookingForward();
	const ahead: Vec3 = view.basis.forward;
	let emitter: ParticleEmitter = emitterFor({ ...still(0.0), sortMode: SortMode.Sort, life: constant(10.0) }, 1);
	emitter.emitCount = 4.0;
	assert step(emitter, 0.0) == 4;
	emitter.particles[0].position = ahead.scaled(3.0);
	emitter.particles[1].position = ahead.scaled(-2.0);
	emitter.particles[2].position = ahead.scaled(10.0);
	emitter.particles[3].position = ahead.scaled(1.0);
	let out: Vec<float32> = new Array(4 * PARTICLE_INSTANCE_STRIDE);
	assert writeSortedInstances(emitter, identity(), view.viewProj, out).ok;
	assert near(along(out, 0, ahead), -2.0, 0.001) && near(along(out, 1, ahead), 10.0, 0.001);
	assert near(along(out, 2, ahead), 3.0, 0.001) && near(along(out, 3, ahead), 1.0, 0.001);
	emitter.state.sortMode = SortMode.InvSort;
	assert writeSortedInstances(emitter, identity(), view.viewProj, out).ok;
	assert near(along(out, 0, ahead), 1.0, 0.001) && near(along(out, 3, ahead), -2.0, 0.001);
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
