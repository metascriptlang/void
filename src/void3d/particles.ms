// Port of h3d.parts at Heaps 2b84cc2, CPU only (docs/VOID3D.md, M11 as built). Heaps is Z up
// and left-handed: every local axis Heaps names z is y here, and y is z.

import { Vec3, vec3, Vec4, vec4, Mat4, identity, transformDirection, cross } from "../math/math3d";
import { noiseDirection, shaderNoiseScale } from "./particleNoise";

export enum ValueKind {
	Const,
	Linear,
	Pow,
	Sin,
	Cos,
	Poly,
	Random,
}

export enum Converge {
	No,
	Start,
	End,
}

// h3d.parts.Data.Value without VCustom. Poly is VPoly without its `points`, which only the editor
// reads (Data.hx:193 evaluates `values` alone).
export type ParticleValue = match (kind: ValueKind) {
	ValueKind.Const => { value: float32 },
	ValueKind.Linear => { start: float32, length: float32 },
	ValueKind.Pow => { start: float32, length: float32, power: float32 },
	ValueKind.Sin => { frequency: float32, amplitude: float32, offset: float32 },
	ValueKind.Cos => { frequency: float32, amplitude: float32, offset: float32 },
	ValueKind.Poly => { values: Vec<float32> },
	ValueKind.Random => { start: float32, length: float32, converge: Converge },
};

// h3d.parts.Data.SortMode: the order a draw lists the particles in. Front and Back are the order
// they were emitted in, newest first or oldest first; Sort and InvSort order them by view depth,
// farthest first or nearest first.
export enum SortMode {
	Front,
	Back,
	Sort,
	InvSort,
}

export enum ShapeKind {
	Line,
	Sphere,
	Cone,
	Disc,
	Point,
	Box,
	Ring,
}

// h3d.parts.Data.Shape without SCustom, plus the three shapes a Heaps user writes as an
// SCustom: Point, Box and Ring, with Godot 4.5's emission shapes as their reference
// (particle_process_material.cpp: point 642-644, box 659-661, ring 668-695). Box `extents` are
// half-widths, as Godot's `emission_box_extents`. Ring is Godot's `emission_ring_*`: `height`
// along `axis`, `coneAngle` in degrees (90 is a cylinder).
export type EmitterShape = match (kind: ShapeKind) {
	ShapeKind.Line => { size: ParticleValue },
	ShapeKind.Sphere => { radius: ParticleValue },
	ShapeKind.Cone => { radius: ParticleValue, angle: ParticleValue },
	ShapeKind.Disc => { radius: ParticleValue },
	ShapeKind.Point => {},
	ShapeKind.Box => { extents: ValueXYZ },
	ShapeKind.Ring => {
		radius: ParticleValue,
		inner: ParticleValue,
		height: float32,
		axis: Vec3,
		coneAngle: float32,
	},
};

export struct Burst {
	time: float64;
	count: int32;
}

// One row of State.colors: a time in the particle's life and 0xRRGGBB.
export struct ColorKey {
	time: float64;
	color: uint32;
}

export struct ValueXYZ {
	x: ParticleValue;
	y: ParticleValue;
	z: ParticleValue;
}

// Godot 4.5's turbulence (particle_process_material.cpp:381-396 uniforms, 1032-1052 use) with its
// defaults (2364-2420): a curl-noise field that turns a particle's velocity toward it. `noiseScale`
// is the property an author sets (0 to 10, default 9), `noiseSpeed` and `noiseSpeedRandom` how fast
// the field drifts, `influence` how far a particle turns, 0 to 1, per particle and over its life as
// a `ParticleValue` on the particle's time of life (Godot's min/max pair times a curve).
export struct Turbulence {
	enabled: boolean;
	noiseStrength: float32;
	noiseScale: float32;
	noiseSpeed: Vec3;
	noiseSpeedRandom: float32;
	influence: ParticleValue;
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
	globalLife: float64;
	globalSpeed: ParticleValue;
	globalSize: ParticleValue;
	life: ParticleValue;
	size: ParticleValue;
	speed: ParticleValue;
	// Godot's `initial_linear_velocity` (particle_process_material.cpp:204-205, 576, 893): a speed
	// along the emission direction drawn once at spawn, which seeds the velocity that damping and
	// turbulence act on. Heaps has none; `speed` stays Heaps' displacement curve.
	initialSpeed: ParticleValue;
	gravity: ParticleValue;
	sortMode: SortMode;
	damping: ParticleValue;
	turbulence: Turbulence;
	force: ValueXYZ;
	colors: Vec<ColorKey>;
	light: ParticleValue;
	alpha: ParticleValue;
}

export struct Particle {
	position: Vec3;
	direction: Vec3;
	force: Vec3;
	time: float64;
	lifeTimeFactor: float64;
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
	time: float64;
	clock: float64;
	emitCount: float64;
	sequence: ParticleRandom;
	// The first `count` are live, in the order Heaps' list keeps them.
	particles: Vec<Particle>;
	randoms: Vec<float32>;
	// The write order, and what a view-depth sort needs to make it: all sized at create.
	order: Vec<int32>;
	scratch: Vec<int32>;
	depth: Vec<float32>;
	count: int32;
	capacity: int32;
}

export enum ParticleError {
	NoCapacity,
	NonPositiveLife,
	NonFiniteStep,
	ShortInstances,
	NeedsView,
}

// Per-particle draws per update: force x, y, z, gravity, damping, turbulence, speed, size,
// light, alpha.
export const PARTICLE_RANDOM_SLOTS: int32 = 10;
export const PARTICLE_INSTANCE_STRIDE: int32 = 8;

const TWO_PI: float64 = 6.283185307179586;
const UNIT_SCALE: float32 = 1.0 / 16777216.0;
const BYTE_SCALE: float32 = (1.0 / 255.0) as float32;
const ONE: float32 = 1.0;
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
		initialSpeed: constant(0.0),
		gravity: constant(0.0),
		sortMode: SortMode.Back,
		damping: constant(0.0),
		turbulence: {
			enabled: false,
			noiseStrength: 1.0,
			noiseScale: 9.0,
			noiseSpeed: vec3(0.0, 0.0, 0.0),
			noiseSpeedRandom: 0.2,
			influence: constant(0.1),
		},
		force: { x: constant(0.0), y: constant(0.0), z: constant(0.0) },
		colors: [],
		light: constant(1.0),
		alpha: constant(1.0),
	};
}

export function seeded(this typeof ParticleRandom, seed: uint32): ParticleRandom {
	return { state: seed == 0 ? DEFAULT_SEED : seed };
}

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
		ValueKind.Poly => polynomial(v.values, time),
		ValueKind.Random => v.start + randomSpan(v.length, v.converge, time) * random,
	};
}

function polynomial(values: Vec<float32>, time: float32): float32 {
	let y: float32 = 0.0;
	let j: int32 = (values.length as int32) - 1;
	while (j >= 0) {
		y = values[j] + time * y;
		j = j - 1;
	}
	return y;
}

function randomSpan(length: float32, converge: Converge, time: float32): float32 {
	return match (converge) {
		Converge.No => length,
		Converge.Start => length * time,
		Converge.End => length * (ONE - time),
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
	let particles: Vec<Particle> = new Array(state.maxParts);
	for (let i = 0; i < state.maxParts; i++) { particles[i] = idle; }
	let randoms: Vec<float32> = new Array(state.maxParts * PARTICLE_RANDOM_SLOTS);
	for (let i = 0; i < state.maxParts * PARTICLE_RANDOM_SLOTS; i++) { randoms[i] = 0.0; }
	let order: Vec<int32> = new Array(state.maxParts);
	let scratch: Vec<int32> = new Array(state.maxParts);
	let depth: Vec<float32> = new Array(state.maxParts);
	for (let i = 0; i < state.maxParts; i++) {
		order[i] = i;
		scratch[i] = i;
		depth[i] = 0.0;
	}
	return Result.ok({
		state: state,
		time: 0.0,
		clock: 0.0,
		emitCount: 0.0,
		sequence: ParticleRandom.seeded(seed),
		particles: particles,
		randoms: randoms,
		order: order,
		scratch: scratch,
		depth: depth,
		count: 0,
		capacity: state.maxParts,
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
	emitter.clock = 0.0;
	emitter.emitCount = 0.0;
}

// Emitter.eval.
function emitterValue(ref emitter: ParticleEmitter, v: ParticleValue, time: float32): float32 {
	const random: float32 = v.drawsRandom() ? nextUnit(emitter.sequence) : 0.0;
	return v.evaluate(time, random);
}

// Particle.eval with Particle.rand.
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
		emitter.randoms[at] = nextUnit(emitter.sequence);
		emitter.particles[slot].randomsDrawn = index + 1;
	}
	emitter.particles[slot].randomIndex = index + 1;
	return v.evaluate(time, emitter.randoms[at]);
}

function unitRandom(ref emitter: ParticleEmitter): float64 {
	return nextUnit(emitter.sequence) as float64;
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

function boxHalfExtent(ref emitter: ParticleEmitter, size: ValueXYZ, time: float32): Vec3 {
	const x: float32 = emitterValue(emitter, size.x, time);
	const y: float32 = emitterValue(emitter, size.y, time);
	const z: float32 = emitterValue(emitter, size.z, time);
	return vec3(absolute(x), absolute(y), absolute(z));
}

function absolute(x: float32): float32 {
	return x < 0.0 ? -x : x;
}

// A point of the box: three uniform draws, or, from the shell, a face chosen by its area and
// then two uniform draws on it.
function boxPosition(ref emitter: ParticleEmitter, half: Vec3, shell: boolean): Vec3 {
	let x: float32 = (nextUnit(emitter.sequence) * 2.0 - 1.0) * half.x;
	let y: float32 = (nextUnit(emitter.sequence) * 2.0 - 1.0) * half.y;
	let z: float32 = (nextUnit(emitter.sequence) * 2.0 - 1.0) * half.z;
	if (!shell) { return vec3(x, y, z); }
	const areaX: float32 = half.y * half.z;
	const areaY: float32 = half.x * half.z;
	const areaZ: float32 = half.x * half.y;
	const pick: float32 = nextUnit(emitter.sequence) * (areaX + areaY + areaZ);
	const side: float32 = nextUnit(emitter.sequence) < 0.5 ? -1.0 : 1.0;
	if (pick < areaX) {
		x = side * half.x;
	} else if (pick < areaX + areaY) {
		y = side * half.y;
	} else {
		z = side * half.z;
	}
	return vec3(x, y, z);
}

// The shape's values are read where the match narrows the variant and not through a local, whose
// copy of a value that may hold a Vec would be made on every spawn.
function shapeRadius(ref emitter: ParticleEmitter, time: float32): float32 {
	match (emitter.state.shape.kind) {
		ShapeKind.Line => { unreachable; },
		ShapeKind.Sphere => { return emitterValue(emitter, emitter.state.shape.radius, time); },
		ShapeKind.Cone => { return emitterValue(emitter, emitter.state.shape.radius, time); },
		ShapeKind.Disc => { return emitterValue(emitter, emitter.state.shape.radius, time); },
		ShapeKind.Point => { unreachable; },
		ShapeKind.Box => { unreachable; },
		ShapeKind.Ring => { return emitterValue(emitter, emitter.state.shape.radius, time); },
	};
}

function shapeAngle(ref emitter: ParticleEmitter, time: float32): float32 {
	match (emitter.state.shape.kind) {
		ShapeKind.Line => { unreachable; },
		ShapeKind.Sphere => { unreachable; },
		ShapeKind.Cone => { return emitterValue(emitter, emitter.state.shape.angle, time); },
		ShapeKind.Disc => { unreachable; },
		ShapeKind.Point => { unreachable; },
		ShapeKind.Box => { unreachable; },
		ShapeKind.Ring => { unreachable; },
	};
}

function shapeInner(ref emitter: ParticleEmitter, time: float32): float32 {
	match (emitter.state.shape.kind) {
		ShapeKind.Line => { unreachable; },
		ShapeKind.Sphere => { unreachable; },
		ShapeKind.Cone => { unreachable; },
		ShapeKind.Disc => { unreachable; },
		ShapeKind.Point => { unreachable; },
		ShapeKind.Box => { unreachable; },
		ShapeKind.Ring => { return emitterValue(emitter, emitter.state.shape.inner, time); },
	};
}

struct Ring {
	position: Vec3;
	outward: Vec3;
}

// Godot's ring (cpp:668-695), draw for draw: the height fraction, the angle, then the radius,
// which is area-uniform between the inner and outer radius and narrowed along the height by the
// cone angle. `outward` is the unit vector from the axis to the point. Godot's `pi` is the literal
// 3.14159; the exact value is used here.
function ringPoint(
	ref emitter: ParticleEmitter,
	outer: float32,
	inner: float32,
	height: float32,
	axisIn: Vec3,
	coneAngle: float32,
): Ring {
	const clamped: float32 = outer > 0.001 ? outer : 0.001;
	const slant: float64 = Math.tan((90.0 - (coneAngle as float64)) * 0.017453292519943295);
	const slope: float32 = (slant * (height as float64)) as float32;
	const topRaw: float32 = clamped - slope;
	const top: float32 = topRaw > 0.0 ? topRaw : 0.0;
	let along: float32 = nextUnit(emitter.sequence);
	const smaller: float32 = clamped < top ? clamped : top;
	const larger: float32 = clamped < top ? top : clamped;
	const ratio: float32 = smaller / larger;
	const skew: float32 = ratio > 0.5 ? ratio : 0.5;
	const lifted: float32 = Math.pow(along as float64, skew as float64) as float32;
	along = clamped < top ? lifted : 1.0 - lifted;
	const turn: float64 = unitRandom(emitter) * TWO_PI;
	const fill: float32 = nextUnit(emitter.sequence);
	let radius: float32 =
		Math.sqrt(
			(fill * (clamped * clamped - inner * inner) + inner * inner) as float64,
		) as float32;
	radius = radius + (radius * (top / clamped) - radius) * along;
	const isZero: boolean = axisIn.x == 0.0 && axisIn.y == 0.0 && axisIn.z == 0.0;
	const axis: Vec3 = isZero ? vec3(0.0, 0.0, 1.0) : axisIn.normalized();
	const alongX: boolean = absolute(axis.x) == 1.0 && axis.y == 0.0 && axis.z == 0.0;
	const start: Vec3 = alongX ? axis.cross(vec3(0.0, 1.0, 0.0)) : axis.cross(vec3(1.0, 0.0, 0.0));
	const side: Vec3 = start.normalized();
	const s: float32 = Math.sin(turn) as float32;
	const c: float32 = Math.cos(turn) as float32;
	const oc: float32 = 1.0 - c;
	const turned: Vec3 = vec3(
		(c + axis.x * axis.x * oc) * side.x + (axis.x * axis.y * oc + s * axis.z) * side.y
			+ (axis.z * axis.x * oc - axis.y * s) * side.z,
		(axis.x * axis.y * oc - axis.z * s) * side.x + (c + axis.y * axis.y * oc) * side.y
			+ (axis.z * axis.y * oc + axis.x * s) * side.z,
		(axis.x * axis.z * oc + axis.y * s) * side.x + (axis.y * axis.z * oc - axis.x * s) * side.y
			+ (c + axis.z * axis.z * oc) * side.z,
	);
	const outward: Vec3 = turned.normalized();
	const lift: float32 = along * height - height / 2.0;
	return { position: outward.scaled(radius) + axis.scaled(lift), outward: outward };
}

// Emitter.initPosDir, then initPart.
function spawn(ref emitter: ParticleEmitter, world: Mat4): void {
	const slot: int32 = emitter.count;
	emitter.count = slot + 1;
	// PENDING3D: particle-random-per-life
	emitter.particles[slot].randomsDrawn = 0;
	const time: float32 = emitter.time as float32;
	const shell: boolean = emitter.state.emitFromShell;
	let position: Vec3 = vec3(0.0, 0.0, 0.0);
	let direction: Vec3 = vec3(0.0, 1.0, 0.0);
	match (emitter.state.shape.kind) {
		ShapeKind.Line => {
			let height: float32 = emitterValue(emitter, emitter.state.shape.size, time);
			if (!shell) { height = height * nextUnit(emitter.sequence); }
			position = vec3(0.0, height, 0.0);
		},
		ShapeKind.Sphere => {
			const theta: float64 = unitRandom(emitter) * TWO_PI;
			const phi: float64 = Math.acos(unitRandom(emitter) * 2.0 - 1.0);
			let radius: float32 = shapeRadius(emitter, time);
			if (!shell) { radius = radius * nextUnit(emitter.sequence); }
			direction = polar(theta, phi);
			position = direction.scaled(radius);
		},
		ShapeKind.Cone => {
			const theta: float64 = unitRandom(emitter) * TWO_PI;
			const angle: float32 = shapeAngle(emitter, time);
			const spread: float64 = angle as float64;
			const phi: float64 = spread * unitRandom(emitter);
			let radius: float32 = shapeRadius(emitter, time);
			if (!shell) { radius = radius * nextUnit(emitter.sequence); }
			direction = polar(theta, phi);
			position = direction.scaled(radius);
		},
		ShapeKind.Point => {},
		ShapeKind.Box => {
			const half: Vec3 = boxHalfExtent(emitter, emitter.state.shape.extents, time);
			position = boxPosition(emitter, half, shell);
		},
		ShapeKind.Ring => {
			const height: float32 = emitter.state.shape.height;
			const axis: Vec3 = emitter.state.shape.axis;
			const coneAngle: float32 = emitter.state.shape.coneAngle;
			const outer: float32 = shapeRadius(emitter, time);
			const inner: float32 = shapeInner(emitter, time);
			const ring: Ring = ringPoint(emitter, outer, inner, height, axis, coneAngle);
			position = ring.position;
			direction = ring.outward;
		},
		ShapeKind.Disc => {
			let radius: float32 = shapeRadius(emitter, time);
			if (!shell) { radius = radius * nextUnit(emitter.sequence); }
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
	const life: float32 = emitterValue(emitter, emitter.state.life, time);
	emitter.particles[slot].lifeTimeFactor = 1.0 / (life as float64);
	const initial: float32 = emitterValue(emitter, emitter.state.initialSpeed, time);
	if (initial != 0.0) { emitter.particles[slot].force = direction.scaled(initial); }
}

function channel(color: uint32, shift: uint32): float32 {
	return (((color >> shift) & 0xFF) as float32) * BYTE_SCALE;
}

// Emitter.updateParticle's color: the keys around the particle's time, blended, times light.
function colorAt(ref emitter: ParticleEmitter, slot: int32, light: float32): void {
	const keys: int32 = emitter.state.colors.length as int32;
	const at: float64 = emitter.particles[slot].time;
	if (keys == 0) {
		emitter.particles[slot].red = light;
		emitter.particles[slot].green = light;
		emitter.particles[slot].blue = light;
		return;
	}
	let from: int32 = 0;
	let to: int32 = 0;
	let weight: float64 = 0.0;
	if (emitter.state.colors[0].time < at) {
		to = 1;
		while (to < keys && emitter.state.colors[to].time < at) {
			from = to;
			to = to + 1;
		}
		if (to == keys) {
			to = from;
		} else {
			const start: float64 = emitter.state.colors[from].time;
			weight = (at - start) / (emitter.state.colors[to].time - start);
		}
	}
	const a: uint32 = emitter.state.colors[from].color;
	const b: uint32 = emitter.state.colors[to].color;
	const mix: float32 = weight as float32;
	const keep: float32 = 1.0 - mix;
	emitter.particles[slot].red = (channel(a, 16) * keep + channel(b, 16) * mix) * light;
	emitter.particles[slot].green = (channel(a, 8) * keep + channel(b, 8) * mix) * light;
	emitter.particles[slot].blue = (channel(a, 0) * keep + channel(b, 0) * mix) * light;
}

// Emitter.updateParticle: false when the particle's life is over.
function stepParticle(ref emitter: ParticleEmitter, slot: int32, step: float64): boolean {
	const lived: float64 =
		emitter.particles[slot].time + step * emitter.particles[slot].lifeTimeFactor;
	emitter.particles[slot].time = lived;
	if (lived > 1.0) { return false; }
	const life: float32 = lived as float32;
	const dt: float32 = step as float32;
	emitter.particles[slot].randomIndex = 0;
	const cycle: float32 = emitter.time as float32;
	const forceX: float32 = particleValue(emitter, slot, emitter.state.force.x, cycle);
	const forceZ: float32 = particleValue(emitter, slot, emitter.state.force.z, cycle);
	const forceY: float32 = particleValue(emitter, slot, emitter.state.force.y, cycle);
	const gravity: float32 = particleValue(emitter, slot, emitter.state.gravity, cycle);
	const damping: float32 = particleValue(emitter, slot, emitter.state.damping, life);
	let influence: float32 = 0.0;
	if (emitter.state.turbulence.enabled && emitter.state.turbulence.noiseStrength > 0.0) {
		influence = particleValue(emitter, slot, emitter.state.turbulence.influence, life);
		influence = influence < 0.0 ? 0.0 : (influence > 1.0 ? 1.0 : influence);
	}
	const force: Vec3 = emitter.particles[slot].force;
	let velocity: Vec3 = vec3(
		force.x + forceX * dt,
		force.y + forceY * dt - gravity * dt,
		force.z + forceZ * dt,
	);
	if (damping > 0.0) { velocity = damped(velocity, damping * dt); }
	const speed: float32 = particleValue(emitter, slot, emitter.state.speed, life);
	const direction: Vec3 = emitter.particles[slot].direction;
	const position: Vec3 = emitter.particles[slot].position;
	if (influence > 0.0 && dt > 0.0) {
		const toward: Vec3 = noiseDirection(
			position,
			emitter.clock as float32,
			emitter.state.turbulence.noiseStrength,
			shaderNoiseScale(emitter.state.turbulence.noiseScale),
			emitter.state.turbulence.noiseSpeed,
			emitter.state.turbulence.noiseSpeedRandom,
		);
		const displacement: Vec3 = direction.scaled(speed);
		velocity = bentToward(velocity, toward, influence);
		const bent: Vec3 = bentToward(displacement, toward, influence);
		emitter.particles[slot].force = velocity;
		emitter.particles[slot].position = vec3(
			position.x + (bent.x + velocity.x) * dt,
			position.y + (bent.y + velocity.y) * dt,
			position.z + (bent.z + velocity.z) * dt,
		);
	} else {
		const ds: float32 = speed * dt;
		emitter.particles[slot].force = velocity;
		emitter.particles[slot].position = vec3(
			position.x + direction.x * ds + velocity.x * dt,
			position.y + direction.y * ds + velocity.y * dt,
			position.z + direction.z * ds + velocity.z * dt,
		);
	}
	emitter.particles[slot].size = particleValue(emitter, slot, emitter.state.size, life);
	const light: float32 = particleValue(emitter, slot, emitter.state.light, life);
	colorAt(emitter, slot, light);
	emitter.particles[slot].alpha = particleValue(emitter, slot, emitter.state.alpha, life);
	return true;
}

// Godot's damping (cpp:993-1011): the speed falls by `loss`, along its own direction, to a stop.
function damped(velocity: Vec3, loss: float32): Vec3 {
	const speed: float32 = velocity.length();
	if (!(speed > 0.0)) { return velocity; }
	const left: float32 = speed - loss;
	if (left < 0.0) { return vec3(0.0, 0.0, 0.0); }
	return velocity.scaled(left / speed);
}

// Godot's turbulence mix (cpp:1048-1052): `v` turned toward `toward` at its own length, a little
// longer the less it is turned, by `influence`.
function bentToward(v: Vec3, toward: Vec3, influence: float32): Vec3 {
	const reach: float32 = v.length() * (1.0 + (1.0 - influence) * 0.2);
	return v.scaled(1.0 - influence) + toward.scaled(reach * influence);
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
// PENDING3D: particle-update-name-collision
export function updateEmitter(
	ref emitter: ParticleEmitter,
	dt: float64,
	world: Mat4,
): Result<int32, ParticleError> {
	if (!Number.isFinite(dt)) { return Result.err(ParticleError.NonFiniteStep); }
	const old: float64 = emitter.time;
	const life: float64 = emitter.state.globalLife as float64;
	const rate: float32 = emitterValue(emitter, emitter.state.globalSpeed, old as float32);
	emitter.time = old + dt * (rate as float64) / life;
	const elapsed: float64 = (emitter.time - old) * life;
	emitter.clock = emitter.clock + elapsed;
	if (emitter.time >= 1.0 && emitter.state.loop) { emitter.time = emitter.time - 1.0; }
	if (emitter.time < 1.0) {
		const cycle: float32 = emitter.time as float32;
		const emitted: float32 = emitterValue(emitter, emitter.state.emitRate, cycle);
		emitter.emitCount = emitter.emitCount + (emitted as float64) * elapsed;
	}
	for (let i = 0; i < (emitter.state.bursts.length as int32); i++) {
		const at: float64 = emitter.state.bursts[i].time as float64;
		if (at <= emitter.time && at > old) {
			emitter.emitCount = emitter.emitCount + (emitter.state.bursts[i].count as float64);
		}
	}
	while (emitter.emitCount > 0.0) {
		if (emitter.count < emitter.capacity) { spawn(emitter, world); }
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

// Emitter.draw then Particles.draw: one instance per live particle, world position and side,
// then rgba, in the emitter's sort mode. Sort and InvSort need a view (writeSortedInstances).
export function writeInstances(
	ref emitter: ParticleEmitter,
	world: Mat4,
	out: Span<float32>,
): Result<int32, ParticleError> {
	if (emitter.state.sortMode == SortMode.Sort || emitter.state.sortMode == SortMode.InvSort) {
		return Result.err(ParticleError.NeedsView);
	}
	return writeOrdered(emitter, world, identity(), out);
}

// writeInstances for any sort mode; `viewProjection` gives Sort and InvSort their depth, the
// z over w a point has after it, as Particles.draw keys on (`Particles.hx:166`).
export function writeSortedInstances(
	ref emitter: ParticleEmitter,
	world: Mat4,
	viewProjection: Mat4,
	out: Span<float32>,
): Result<int32, ParticleError> {
	return writeOrdered(emitter, world, viewProjection, out);
}

function placeOf(ref emitter: ParticleEmitter, world: Mat4, slot: int32): Vec3 {
	const position: Vec3 = emitter.particles[slot].position;
	return emitter.state.emitLocal ? position * world : position;
}

// A stable merge sort of `order` by ascending `depth`, through `scratch`: no allocation.
function sortByDepth(ref emitter: ParticleEmitter): void {
	const count: int32 = emitter.count;
	let width: int32 = 1;
	while (width < count) {
		let start: int32 = 0;
		while (start < count) {
			const middle: int32 = start + width < count ? start + width : count;
			const end: int32 = start + 2 * width < count ? start + 2 * width : count;
			let left: int32 = start;
			let right: int32 = middle;
			for (let at = start; at < end; at++) {
				const takeLeft: boolean = right >= end || (left < middle
					&& !(emitter.depth[emitter.order[right]] < emitter.depth[emitter.order[left]]));
				if (takeLeft) {
					emitter.scratch[at] = emitter.order[left];
					left = left + 1;
				} else {
					emitter.scratch[at] = emitter.order[right];
					right = right + 1;
				}
			}
			start = end;
		}
		for (let i = 0; i < count; i++) { emitter.order[i] = emitter.scratch[i]; }
		width = width * 2;
	}
}

function writeOrdered(
	ref emitter: ParticleEmitter,
	world: Mat4,
	viewProjection: Mat4,
	out: Span<float32>,
): Result<int32, ParticleError> {
	const count: int32 = emitter.count;
	if ((out.length as int32) < count * PARTICLE_INSTANCE_STRIDE) {
		return Result.err(ParticleError.ShortInstances);
	}
	// PENDING3D: particle-size-world-units
	const cycle: float32 = emitter.time as float32;
	const scale: float32 = emitterValue(emitter, emitter.state.globalSize, cycle);
	if (count == 0) { return Result.ok(0); }
	const mode: SortMode = emitter.state.sortMode;
	for (let i = 0; i < count; i++) {
		emitter.order[i] = mode == SortMode.Front ? count - 1 - i : i;
	}
	if (mode == SortMode.Sort || mode == SortMode.InvSort) {
		const sign: float32 = mode == SortMode.Sort ? -1.0 : 1.0;
		for (let i = 0; i < count; i++) {
			emitter.depth[i] = depthKey(placeOf(emitter, world, i), viewProjection) * sign;
		}
		sortByDepth(emitter);
	}
	for (let i = 0; i < count; i++) {
		const slot: int32 = emitter.order[i];
		const position: Vec3 = placeOf(emitter, world, slot);
		const at: int32 = i * PARTICLE_INSTANCE_STRIDE;
		out[at] = position.x;
		out[at + 1] = position.y;
		out[at + 2] = position.z;
		out[at + 3] = emitter.particles[slot].size * scale;
		out[at + 4] = emitter.particles[slot].red;
		out[at + 5] = emitter.particles[slot].green;
		out[at + 6] = emitter.particles[slot].blue;
		out[at + 7] = emitter.particles[slot].alpha;
	}
	return Result.ok(count);
}

// Particles.draw's w: the z over w of the point through the view. A point at or behind the eye
// has none and counts as the farthest, so the order stays total.
function depthKey(position: Vec3, viewProjection: Mat4): float32 {
	const clip: Vec4 = vec4(position.x, position.y, position.z, 1.0) * viewProjection;
	if (!(clip.w > 0.0)) { return 3.0e38; }
	return clip.z / clip.w;
}
