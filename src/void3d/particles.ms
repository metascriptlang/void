// Port of h3d.parts at Heaps 2b84cc2, CPU only: Data (Value, Shape, State), Particle, and the
// simulation half of Particles and Emitter. The draw half writes one billboard instance per
// particle for a stream mesh (draw.ms writeStream) instead of four vertices into a buffer made
// every frame. GpuParticles is not ported (docs/VOID3D.md, Porting rules).
//
// Heaps is Z up and left-handed; this frame is Y up and right-handed. Exchanging y and z maps
// one onto the other, so every local axis Heaps names z is y here: the cone and the line point
// up +Y, the disc lies in XZ, and gravity pulls along -Y.

import { Vec3, vec3, Mat4, transformDirection } from "../math/math3d";

export enum ValueKind {
	Const,
	Linear,
	Pow,
	Sin,
	Cos,
	Random,
}

export enum Converge {
	No,
	Start,
	End,
}

// h3d.parts.Data.Value without VPoly and VCustom.
export type ParticleValue = match (kind: ValueKind) {
	ValueKind.Const => { value: float32 },
	ValueKind.Linear => { start: float32, length: float32 },
	ValueKind.Pow => { start: float32, length: float32, power: float32 },
	ValueKind.Sin => { frequency: float32, amplitude: float32, offset: float32 },
	ValueKind.Cos => { frequency: float32, amplitude: float32, offset: float32 },
	ValueKind.Random => { start: float32, length: float32, converge: Converge },
};

export enum ShapeKind {
	Line,
	Sphere,
	Cone,
	Disc,
}

// h3d.parts.Data.Shape without SCustom.
export type EmitterShape = match (kind: ShapeKind) {
	ShapeKind.Line => { size: ParticleValue },
	ShapeKind.Sphere => { radius: ParticleValue },
	ShapeKind.Cone => { radius: ParticleValue, angle: ParticleValue },
	ShapeKind.Disc => { radius: ParticleValue },
};

export struct Burst {
	time: float32;
	count: int32;
}

// One row of State.colors: a time in the particle's life and 0xRRGGBB.
export struct ColorKey {
	time: float32;
	color: uint32;
}

export struct ValueXYZ {
	x: ParticleValue;
	y: ParticleValue;
	z: ParticleValue;
}

// h3d.parts.Data.State, the fields the simulation reads. `force` is never null here: Heaps'
// null force and a force of three VConst(0) move no particle and draw no random value.
export struct EmitterState {
	loop: boolean;
	emitRate: ParticleValue;
	bursts: Vec<Burst>;
	maxParts: int32;
	shape: EmitterShape;
	emitFromShell: boolean;
	emitLocal: boolean;
	randomDir: boolean;
	globalLife: float32;
	globalSpeed: ParticleValue;
	globalSize: ParticleValue;
	life: ParticleValue;
	size: ParticleValue;
	speed: ParticleValue;
	gravity: ParticleValue;
	force: ValueXYZ;
	colors: Vec<ColorKey>;
	light: ParticleValue;
	alpha: ParticleValue;
}

export struct Particle {
	position: Vec3;
	direction: Vec3;
	force: Vec3;
	time: float32;
	lifeTimeFactor: float32;
	size: float32;
	red: float32;
	green: float32;
	blue: float32;
	alpha: float32;
	randomIndex: int32;
	randomsDrawn: int32;
}

// xorshift32, read as 24 bits so the value is exact in float32 and float64 alike.
export struct ParticleRandom {
	state: uint32;
}

export struct ParticleEmitter {
	state: EmitterState;
	time: float32;
	emitCount: float32;
	random: ParticleRandom;
	// The first `count` are live, in the order Heaps' list keeps them.
	particles: Vec<Particle>;
	randoms: Vec<float32>;
	count: int32;
}

export enum ParticleError {
	NoCapacity,
	NonPositiveLife,
	NonFiniteStep,
	ShortInstances,
}

// Per-particle draws per update: force x, y, z, gravity, speed, size, light, alpha.
export const PARTICLE_RANDOM_SLOTS: int32 = 8;
export const PARTICLE_INSTANCE_STRIDE: int32 = 8;

const TWO_PI: float64 = 6.283185307179586;
const UNIT_SCALE: float32 = 1.0 / 16777216.0;
const BYTE_SCALE: float32 = 1.0 / 255.0;
const DEFAULT_SEED: uint32 = 2463534242;

export function constant(value: float32): ParticleValue {
	return { kind: ValueKind.Const, value: value };
}

// State.setDefaults.
export function defaults(this typeof EmitterState): EmitterState {
	return {
		loop: true,
		emitRate: constant(100.0),
		bursts: [],
		maxParts: 1000,
		shape: { kind: ShapeKind.Cone, radius: constant(1.0), angle: constant(0.7853981633974483) },
		emitFromShell: false,
		emitLocal: false,
		randomDir: false,
		globalLife: 1.0,
		globalSpeed: constant(1.0),
		globalSize: constant(1.0),
		life: constant(1.0),
		size: constant(1.0),
		speed: constant(0.1),
		gravity: constant(0.0),
		force: { x: constant(0.0), y: constant(0.0), z: constant(0.0) },
		colors: [],
		light: constant(1.0),
		alpha: constant(1.0),
	};
}

export function seeded(this typeof ParticleRandom, seed: uint32): ParticleRandom {
	return { state: seed == 0 ? DEFAULT_SEED : seed };
}

// The next value in [0, 1), in the role of Math.random.
export function nextUnit(ref random: ParticleRandom): float32 {
	let x: uint32 = random.state;
	x = x ^ (x << 13);
	x = x ^ (x >> 17);
	x = x ^ (x << 5);
	random.state = x;
	return ((x >> 8) as float32) * UNIT_SCALE;
}

export function drawsRandom(this v: ParticleValue): boolean {
	return v.kind == ValueKind.Random;
}

// State.eval; `random` is read only by a Random value and is its r.rand().
export function evaluate(this v: ParticleValue, time: float32, random: float32): float32 {
	return match (v.kind) {
		ValueKind.Const => v.value,
		ValueKind.Linear => v.start + v.length * time,
		ValueKind.Pow => v.start + (Math.pow(time, v.power) as float32) * v.length,
		ValueKind.Sin => (Math.sin(time * v.frequency) as float32) * v.amplitude + v.offset,
		ValueKind.Cos => (Math.cos(time * v.frequency) as float32) * v.amplitude + v.offset,
		ValueKind.Random => v.start + randomSpan(v.length, v.converge, time) * random,
	};
}

function randomSpan(length: float32, converge: Converge, time: float32): float32 {
	return match (converge) {
		Converge.No => length,
		Converge.Start => length * time,
		Converge.End => length * (1.0 - time),
	};
}

export function create(
	this typeof ParticleEmitter,
	state: EmitterState,
	seed: uint32,
): Result<ParticleEmitter, ParticleError> {
	if (state.maxParts <= 0) { return Result.err(ParticleError.NoCapacity); }
	if (!(state.globalLife > 0.0)) { return Result.err(ParticleError.NonPositiveLife); }
	const idle: Particle = {
		position: vec3(0.0, 0.0, 0.0),
		direction: vec3(0.0, 0.0, 0.0),
		force: vec3(0.0, 0.0, 0.0),
		time: 0.0,
		lifeTimeFactor: 0.0,
		size: 0.0,
		red: 1.0,
		green: 1.0,
		blue: 1.0,
		alpha: 1.0,
		randomIndex: 0,
		randomsDrawn: 0,
	};
	const particles: Vec<Particle> = new Array(state.maxParts);
	for (let i = 0; i < state.maxParts; i++) { particles[i] = idle; }
	const randoms: Vec<float32> = new Array(state.maxParts * PARTICLE_RANDOM_SLOTS);
	for (let i = 0; i < state.maxParts * PARTICLE_RANDOM_SLOTS; i++) { randoms[i] = 0.0; }
	return Result.ok({
		state: state,
		time: 0.0,
		emitCount: 0.0,
		random: ParticleRandom.seeded(seed),
		particles: particles,
		randoms: randoms,
		count: 0,
	});
}

// Emitter.isActive.
export function isActive(this emitter: ParticleEmitter): boolean {
	return emitter.count != 0 || emitter.time < 1.0 || emitter.state.loop;
}

// Emitter.clear. The random sequence goes on where it was.
export function clearParticles(ref emitter: ParticleEmitter): void {
	emitter.count = 0;
	emitter.time = 0.0;
	emitter.emitCount = 0.0;
}

// Emitter.eval: a Random value draws a fresh value from the emitter's sequence.
function emitterValue(ref emitter: ParticleEmitter, v: ParticleValue, time: float32): float32 {
	const random: float32 = v.drawsRandom() ? nextUnit(emitter.random) : 0.0;
	return v.evaluate(time, random);
}

// Particle.eval: the k-th Random value a particle evaluates in an update reads its k-th value,
// drawn from the emitter's sequence the first time this life asks for it.
function particleValue(
	ref emitter: ParticleEmitter,
	slot: int32,
	v: ParticleValue,
	time: float32,
): float32 {
	if (!v.drawsRandom()) { return v.evaluate(time, 0.0); }
	const index: int32 = emitter.particles[slot].randomIndex;
	const at: int32 = slot * PARTICLE_RANDOM_SLOTS + index;
	if (index >= emitter.particles[slot].randomsDrawn) {
		emitter.randoms[at] = nextUnit(emitter.random);
		emitter.particles[slot].randomsDrawn = index + 1;
	}
	emitter.particles[slot].randomIndex = index + 1;
	return v.evaluate(time, emitter.randoms[at]);
}

function unitRandom(ref emitter: ParticleEmitter): float64 {
	return nextUnit(emitter.random) as float64;
}

// Heaps' (sin phi cos theta, sin phi sin theta, cos phi) with its y and z exchanged.
function polar(theta: float64, phi: float64): Vec3 {
	const ring: float64 = Math.sin(phi);
	return vec3(
		(ring * Math.cos(theta)) as float32,
		Math.cos(phi) as float32,
		(ring * Math.sin(theta)) as float32,
	);
}

// Emitter.initPosDir, then initPart.
function spawn(ref emitter: ParticleEmitter, world: Mat4): void {
	const slot: int32 = emitter.count;
	emitter.count = slot + 1;
	emitter.particles[slot].randomsDrawn = 0;
	const time: float32 = emitter.time;
	const shell: boolean = emitter.state.emitFromShell;
	let position: Vec3 = vec3(0.0, 0.0, 0.0);
	let direction: Vec3 = vec3(0.0, 1.0, 0.0);
	match (emitter.state.shape.kind) {
		ShapeKind.Line => {
			let height: float32 = emitterValue(emitter, emitter.state.shape.size, time);
			if (!shell) { height = height * nextUnit(emitter.random); }
			position = vec3(0.0, height, 0.0);
		},
		ShapeKind.Sphere => {
			const theta: float64 = unitRandom(emitter) * TWO_PI;
			const phi: float64 = Math.acos(unitRandom(emitter) * 2.0 - 1.0);
			let radius: float32 = emitterValue(emitter, emitter.state.shape.radius, time);
			if (!shell) { radius = radius * nextUnit(emitter.random); }
			direction = polar(theta, phi);
			position = direction.scaled(radius);
		},
		ShapeKind.Cone => {
			const theta: float64 = unitRandom(emitter) * TWO_PI;
			const angle: float32 = emitterValue(emitter, emitter.state.shape.angle, time);
			const spread: float64 = angle as float64;
			const phi: float64 = spread * unitRandom(emitter);
			let radius: float32 = emitterValue(emitter, emitter.state.shape.radius, time);
			if (!shell) { radius = radius * nextUnit(emitter.random); }
			direction = polar(theta, phi);
			position = direction.scaled(radius);
		},
		ShapeKind.Disc => {
			let radius: float32 = emitterValue(emitter, emitter.state.shape.radius, time);
			if (!shell) { radius = radius * nextUnit(emitter.random); }
			const angle: float64 = unitRandom(emitter) * TWO_PI;
			direction = vec3(Math.cos(angle) as float32, 0.0, Math.sin(angle) as float32);
			position = direction.scaled(radius);
		},
	};
	if (emitter.state.randomDir) {
		const theta: float64 = unitRandom(emitter) * TWO_PI;
		const phi: float64 = Math.acos(unitRandom(emitter) * 2.0 - 1.0);
		direction = polar(theta, phi);
	}
	if (!emitter.state.emitLocal) {
		position = position * world;
		direction = direction.transformDirection(world);
	}
	emitter.particles[slot].position = position;
	emitter.particles[slot].direction = direction;
	emitter.particles[slot].force = vec3(0.0, 0.0, 0.0);
	emitter.particles[slot].time = 0.0;
	emitter.particles[slot].lifeTimeFactor = 1.0 / emitterValue(emitter, emitter.state.life, time);
}

function channel(color: uint32, shift: uint32): float32 {
	return (((color >> shift) & 0xFF) as float32) * BYTE_SCALE;
}

// Emitter.updateParticle's color: the keys around the particle's time, blended, times light.
function colorAt(ref emitter: ParticleEmitter, slot: int32, light: float32): void {
	const keys: int32 = emitter.state.colors.length as int32;
	const at: float32 = emitter.particles[slot].time;
	if (keys == 0) {
		emitter.particles[slot].red = light;
		emitter.particles[slot].green = light;
		emitter.particles[slot].blue = light;
		return;
	}
	let from: int32 = 0;
	let to: int32 = 0;
	let weight: float32 = 0.0;
	if (emitter.state.colors[0].time < at) {
		to = 1;
		while (to < keys && emitter.state.colors[to].time < at) {
			from = to;
			to = to + 1;
		}
		if (to == keys) {
			to = from;
		} else {
			const start: float32 = emitter.state.colors[from].time;
			weight = (at - start) / (emitter.state.colors[to].time - start);
		}
	}
	const a: uint32 = emitter.state.colors[from].color;
	const b: uint32 = emitter.state.colors[to].color;
	const keep: float32 = 1.0 - weight;
	emitter.particles[slot].red = (channel(a, 16) * keep + channel(b, 16) * weight) * light;
	emitter.particles[slot].green = (channel(a, 8) * keep + channel(b, 8) * weight) * light;
	emitter.particles[slot].blue = (channel(a, 0) * keep + channel(b, 0) * weight) * light;
}

// Emitter.updateParticle: false when the particle's life is over.
function stepParticle(ref emitter: ParticleEmitter, slot: int32, dt: float32): boolean {
	const factor: float32 = emitter.particles[slot].lifeTimeFactor;
	const life: float32 = emitter.particles[slot].time + dt * factor;
	emitter.particles[slot].time = life;
	if (life > 1.0) { return false; }
	emitter.particles[slot].randomIndex = 0;
	const cycle: float32 = emitter.time;
	const forceX: float32 = particleValue(emitter, slot, emitter.state.force.x, cycle);
	const forceZ: float32 = particleValue(emitter, slot, emitter.state.force.z, cycle);
	const forceY: float32 = particleValue(emitter, slot, emitter.state.force.y, cycle);
	const gravity: float32 = particleValue(emitter, slot, emitter.state.gravity, cycle);
	const force: Vec3 = emitter.particles[slot].force;
	const pushed: Vec3 = vec3(
		force.x + forceX * dt,
		force.y + forceY * dt - gravity * dt,
		force.z + forceZ * dt,
	);
	emitter.particles[slot].force = pushed;
	const speed: float32 = particleValue(emitter, slot, emitter.state.speed, life);
	const ds: float32 = speed * dt;
	const direction: Vec3 = emitter.particles[slot].direction;
	const position: Vec3 = emitter.particles[slot].position;
	emitter.particles[slot].position = vec3(
		position.x + direction.x * ds + pushed.x * dt,
		position.y + direction.y * ds + pushed.y * dt,
		position.z + direction.z * ds + pushed.z * dt,
	);
	emitter.particles[slot].size = particleValue(emitter, slot, emitter.state.size, life);
	const light: float32 = particleValue(emitter, slot, emitter.state.light, life);
	colorAt(emitter, slot, light);
	emitter.particles[slot].alpha = particleValue(emitter, slot, emitter.state.alpha, life);
	return true;
}

function moveParticle(ref emitter: ParticleEmitter, from: int32, to: int32): void {
	emitter.particles[to] = emitter.particles[from];
	for (let k = 0; k < PARTICLE_RANDOM_SLOTS; k++) {
		emitter.randoms[to * PARTICLE_RANDOM_SLOTS + k] =
			emitter.randoms[from * PARTICLE_RANDOM_SLOTS + k];
	}
}

// Emitter.update: advance the emitter's cycle, emit what it owes, then step every particle,
// dropping the dead ones while keeping the others in order. `world` is the emitter's absPos.
export function update(
	ref emitter: ParticleEmitter,
	dt: float32,
	world: Mat4,
): Result<int32, ParticleError> {
	if (!Number.isFinite(dt as float64)) { return Result.err(ParticleError.NonFiniteStep); }
	const old: float32 = emitter.time;
	const life: float32 = emitter.state.globalLife;
	const rate: float32 = emitterValue(emitter, emitter.state.globalSpeed, old);
	emitter.time = old + dt * rate / life;
	const elapsed: float32 = (emitter.time - old) * life;
	if (emitter.time >= 1.0 && emitter.state.loop) { emitter.time = emitter.time - 1.0; }
	if (emitter.time < 1.0) {
		const emitted: float32 = emitterValue(emitter, emitter.state.emitRate, emitter.time);
		emitter.emitCount = emitter.emitCount + emitted * elapsed;
	}
	for (let i = 0; i < (emitter.state.bursts.length as int32); i++) {
		const at: float32 = emitter.state.bursts[i].time;
		if (at <= emitter.time && at > old) {
			emitter.emitCount = emitter.emitCount + (emitter.state.bursts[i].count as float32);
		}
	}
	while (emitter.emitCount > 0.0) {
		if (emitter.count < emitter.state.maxParts) { spawn(emitter, world); }
		emitter.emitCount = emitter.emitCount - 1.0;
	}
	let kept: int32 = 0;
	for (let i = 0; i < emitter.count; i++) {
		if (!stepParticle(emitter, i, elapsed)) { continue; }
		if (kept != i) { moveParticle(emitter, i, kept); }
		kept = kept + 1;
	}
	emitter.count = kept;
	return Result.ok(kept);
}

// Particles.draw, one instance per live particle: world position and side, then rgba. Heaps
// evaluates globalSize at draw time, from the emitter's own sequence, and not at all when
// nothing is alive; so does this.
export function writeInstances(
	ref emitter: ParticleEmitter,
	world: Mat4,
	out: Span<float32>,
): Result<int32, ParticleError> {
	const count: int32 = emitter.count;
	if ((out.length as int32) < count * PARTICLE_INSTANCE_STRIDE) {
		return Result.err(ParticleError.ShortInstances);
	}
	if (count == 0) { return Result.ok(0); }
	const scale: float32 = emitterValue(emitter, emitter.state.globalSize, emitter.time);
	for (let i = 0; i < count; i++) {
		let position: Vec3 = emitter.particles[i].position;
		if (emitter.state.emitLocal) { position = position * world; }
		const at: int32 = i * PARTICLE_INSTANCE_STRIDE;
		out[at] = position.x;
		out[at + 1] = position.y;
		out[at + 2] = position.z;
		out[at + 3] = emitter.particles[i].size * scale;
		out[at + 4] = emitter.particles[i].red;
		out[at + 5] = emitter.particles[i].green;
		out[at + 6] = emitter.particles[i].blue;
		out[at + 7] = emitter.particles[i].alpha;
	}
	return Result.ok(count);
}
