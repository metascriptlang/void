// One Unity particle system at runtime (docs/PARTICLES-SIM.md §1, §5, §6): the authored asset,
// its curves compiled once, and the live particles as columns. Time advances in fixed steps with
// a remainder, every random value is a hash of the particle's seed, so a system's columns are a
// pure function of its asset, seed and per-update inputs at any frame rate.

import { Vec3, vec3, Mat4, identity, inverseAffine, transformDirection, position, translation } from "../math/math3d";
import {
	ParticleSystemAsset, SimulationSpace, RingBufferMode, InheritVelocityMode, NoiseQuality,
	TextureSheetAnimationType, TextureSheetRowMode, TextureSheetTimeMode, CustomDataMode,
	CustomDataStream, EmitterVelocityMode, Range, Burst, SubEmitterType, SubEmitterProperty,
	ParticleCollider, ForceField, TriggerAction, CollisionType, TrailMode, MainModule, EmissionModule, NoiseModule, CollisionModule, TriggerModule, TextureSheetAnimationModule, TrailModule} from "./asset";
import { ParticleColor, CompiledMinMaxCurve, MinMaxGradient, unitDraw, pcgHash } from "./curve";
import { CompiledCurves, compileCurves } from "./compiled";
import { ShapeSample, ShapeSlot, sampleShape } from "./shape";
import { noise3 } from "./noise";
import { Hit, MISS, sweep, overlaps, fieldPush, FieldPush } from "./collision";
import { TrailRings } from "./trailRing";

// Column c of particle i is data[c * capacity + i]; the first `count` slots are live, oldest first.
export const POS_X: int32 = 0;
export const POS_Y: int32 = 1;
export const POS_Z: int32 = 2;
export const VEL_X: int32 = 3;
export const VEL_Y: int32 = 4;
export const VEL_Z: int32 = 5;
// Unity's totalVelocity: stored plus animated, before speedModifier scales the displacement.
export const MOVE_X: int32 = 6;
export const MOVE_Y: int32 = 7;
export const MOVE_Z: int32 = 8;
export const AGE: int32 = 9;
export const LIFETIME: int32 = 10;
export const START_SIZE_X: int32 = 11;
export const START_SIZE_Y: int32 = 12;
export const START_SIZE_Z: int32 = 13;
export const SIZE_X: int32 = 14;
export const SIZE_Y: int32 = 15;
export const SIZE_Z: int32 = 16;
// Radians, integrated from the start rotation by the angular velocity of each step.
export const ROT_X: int32 = 17;
export const ROT_Y: int32 = 18;
export const ROT_Z: int32 = 19;
export const START_R: int32 = 20;
export const START_G: int32 = 21;
export const START_B: int32 = 22;
export const START_A: int32 = 23;
export const COLOR_R: int32 = 24;
export const COLOR_G: int32 = 25;
export const COLOR_B: int32 = 26;
export const COLOR_A: int32 = 27;
// The texture sheet frame index, a whole number stored as float.
export const FRAME: int32 = 28;
export const CUSTOM1_X: int32 = 29;
export const CUSTOM2_X: int32 = 33;
// The seconds a particle born this step still has to simulate; -1 once it has.
export const PENDING: int32 = 37;
// Each Birth sub-emitter's emission carry for this parent particle (Unity's m_EmitAccumulator0/1).
export const BIRTH_CARRY: int32 = 38;
export const MAX_BIRTH_LINKS: int32 = 2;
// Which Ribbon trail the particle joins: its emission number modulo the ribbon count.
export const RIBBON: int32 = 40;
export const PARTICLE_COLUMNS: int32 = 41;
export const MAX_TRIGGER_COLLIDERS: int32 = 32;

export enum ParticleSystemError {
	InvalidCurve,
	InvalidGradient,
	InvalidShape,
	NoCapacity,
	NonPositiveDuration,
	PrewarmNeedsLoop,
	PrewarmWithDelay,
	EmptyRange,
	EndlessBurst,
	NoTiles,
	NonFiniteStep,
	TooManyTriggerColliders,
	// Sub-emitter children splitting their parent's ribbon: not drawn yet.
	SplitSubEmitterRibbons,
}

// How a system turns frame time into steps: whole fixed steps with the rest carried, or one
// step of the frame's length when `fixedStep` is 0.
export struct StepClock {
	fixedStep: float64;
	maxSubSteps: int32;
	// A longer frame is simulated as this long, so a stall never runs away.
	maxFrameTime: float64;
	remainder: float64;
}

export struct FrameSteps {
	count: int32;
	h: float64;
	// The remainder the frame started with and the frame's length after the clamp.
	before: float64;
	dt: float64;
}

export enum TriggerEvent {
	Inside,
	Outside,
	Enter,
	Exit,
}

// Something that happened to a particle during the update: what sub-emitters consume and what an
// app reads for collision messages and trigger callbacks. Valid until the next update.
export struct ParticleEvent {
	kind: SubEmitterType;
	trigger: TriggerEvent;
	// The Birth link that emitted it, else -1.
	link: int32;
	// Children to spawn for a Birth link's rate; -1 runs the child's bursts.
	count: int32;
	position: Vec3;
	// Where a Birth event's path started this step.
	from: Vec3;
	velocity: Vec3;
	normal: Vec3;
	collider: int32;
	color: ParticleColor;
	size: Vec3;
	rotation: Vec3;
	ageFraction: float32;
	// Seconds before the end of the step at which it happened.
	before: float32;
	seed: uint32;
}

// A Birth sub-emitter of this system: the child's rates, evaluated over the parent's age.
export struct BirthLink {
	rate: CompiledMinMaxCurve;
	distanceRate: CompiledMinMaxCurve;
}

export struct ParticleSystem {
	asset: ParticleSystemAsset;
	curves: CompiledCurves;
	data: Vec<float32>;
	seeds: Vec<uint32>;
	count: int32;
	capacity: int32;
	systemSeed: uint32;
	spawned: uint32;
	playing: boolean;
	emitting: boolean;
	// Seconds into the current cycle, in [0, duration].
	time: float64;
	cycle: int32;
	delayLeft: float64;
	emitCarry: float64;
	distanceCarry: float64;
	stepIndex: uint32;
	clock: StepClock;
	// Scene gravity in world space; gravityModifier scales it.
	gravity: Vec3;
	world: Mat4;
	placed: boolean;
	frameFrom: Vec3;
	frameTo: Vec3;
	stepFrom: Vec3;
	stepTo: Vec3;
	emitterVelocity: Vec3;
	arcPhase: float64;
	radiusPhase: float64;
	noiseScroll: float32;
	noiseOffset: float32;
	ringIndex: int32;
	// Emission ended and the last particle died: the stop action is due.
	finished: boolean;
	// PerParticle trail points, sized when the system plays.
	trails: TrailRings;
	// Set by the app, in the system's simulation space: the colliders of World collision and the
	// force fields External Forces reads.
	colliders: Vec<ParticleCollider>;
	forceFields: Vec<ForceField>;
	// One bit per trigger collider the particle overlapped last step.
	inside: Vec<uint32>;
	events: Vec<ParticleEvent>;
	births: Vec<BirthLink>;
	// Whether anything consumes Death, Collision and Trigger events; the effect sets these.
	wantDeath: boolean;
	wantCollision: boolean;
	wantTrigger: boolean;
}

// The salts of the per-particle draws: one stream per property, so adding a module never moves
// another module's values.
const DRAW_LIFETIME: uint32 = 1;
const DRAW_SPEED: uint32 = 2;
const DRAW_SIZE: uint32 = 3;
const DRAW_SIZE_Y: uint32 = 4;
const DRAW_SIZE_Z: uint32 = 5;
const DRAW_ROTATION: uint32 = 6;
const DRAW_ROTATION_Y: uint32 = 7;
const DRAW_ROTATION_Z: uint32 = 8;
const DRAW_FLIP: uint32 = 9;
const DRAW_COLOR: uint32 = 10;
const DRAW_GRAVITY: uint32 = 11;
const DRAW_VELOCITY: uint32 = 12;
const DRAW_LIMIT: uint32 = 13;
const DRAW_INHERIT: uint32 = 14;
const DRAW_FORCE: uint32 = 15;
const DRAW_NOISE: uint32 = 16;
const DRAW_COLOR_LIFE: uint32 = 17;
const DRAW_COLOR_SPEED: uint32 = 18;
const DRAW_SIZE_LIFE: uint32 = 19;
const DRAW_SIZE_SPEED: uint32 = 20;
const DRAW_ROTATION_LIFE: uint32 = 21;
const DRAW_ROTATION_SPEED: uint32 = 22;
const DRAW_FRAME: uint32 = 23;
const DRAW_START_FRAME: uint32 = 24;
const DRAW_ROW: uint32 = 25;
const DRAW_CUSTOM: uint32 = 26;
const DRAW_LIFETIME_SPEED: uint32 = 27;
const DRAW_START_DELAY: uint32 = 40;
const DRAW_RATE: uint32 = 41;
const DRAW_BURST: uint32 = 42;
const DRAW_BURST_COUNT: uint32 = 43;
const DRAW_NOISE_OFFSET: uint32 = 44;
const DRAW_COLLISION: uint32 = 28;
const DRAW_BIRTH: uint32 = 29;
export const DRAW_SUB_EMITTER: uint32 = 30;
// The renderer's and the texture sheet's flip proportions, drawn by the writers (2D and 3D).
export const DRAW_FLIP_U: uint32 = 31;
export const DRAW_FLIP_V: uint32 = 32;
// Whether a particle carries a light, when the Lights module draws them at random.
export const DRAW_LIGHT: uint32 = 33;
export const DRAW_TRAIL: uint32 = 34;
const DRAW_TRAIL_LIFETIME: uint32 = 35;

const DEGREE: float32 = 0.017453292519943295;
const PI: float32 = 3.141592653589793;
const DEFAULT_STEP: float64 = 1.0 / 60.0;

export function mix(a: uint32, b: uint32): uint32 {
	return pcgHash(a ^ (b * 0x9E3779B9 + 0x7F4A7C15));
}

function saturate(v: float32): float32 {
	if (v < 0.0) { return 0.0; }
	if (v > 1.0) { return 1.0; }
	return v;
}

function fract(v: float32): float32 {
	return v - (Math.floor(v) as float32);
}

// Where `value` sits in `range`, as the by-speed modules sample their curves.
function within(range: Range, value: float32): float32 {
	return saturate((value - range.min) / (range.max - range.min));
}

function okRange(enabled: boolean, range: Range): boolean {
	return !enabled || range.max > range.min;
}

function gradientOk(value: MinMaxGradient): boolean {
	return value.validate().ok;
}

function streamOk(stream: CustomDataStream): boolean {
	return stream.mode != CustomDataMode.Color || gradientOk(stream.color);
}

// Refuses an asset the simulation cannot run as authored: Unity's editor rules, ranges a
// by-speed module divides by, and a burst that would fire every instant forever.
function validateAsset(asset: ParticleSystemAsset): Result<int32, ParticleSystemError> {
	const m: Borrow<MainModule> = asset.main;
	if (!(m.duration > 0.0)) { return Result.err(ParticleSystemError.NonPositiveDuration); }
	if (m.maxParticles <= 0 || m.maxParticles > 2147483647 / PARTICLE_COLUMNS) {
		return Result.err(ParticleSystemError.NoCapacity);
	}
	if (m.prewarm && !m.loop) { return Result.err(ParticleSystemError.PrewarmNeedsLoop); }
	if (m.prewarm && !(m.startDelay.scalar == 0.0 && m.startDelay.minScalar == 0.0)) {
		return Result.err(ParticleSystemError.PrewarmWithDelay);
	}
	if (!asset.shape.validate().ok) { return Result.err(ParticleSystemError.InvalidShape); }
	for (const burst of asset.emission.bursts) {
		if (burst.cycleCount != 1 && !(burst.repeatInterval > 0.0)) {
			return Result.err(ParticleSystemError.EndlessBurst);
		}
	}
	const rangesOk: boolean = okRange(asset.lifetimeByEmitterSpeed.enabled, asset.lifetimeByEmitterSpeed.range)
		&& okRange(asset.colorBySpeed.enabled, asset.colorBySpeed.range)
		&& okRange(asset.sizeBySpeed.enabled, asset.sizeBySpeed.range)
		&& okRange(asset.rotationBySpeed.enabled, asset.rotationBySpeed.range)
		&& okRange(asset.textureSheetAnimation.enabled
			&& asset.textureSheetAnimation.timeMode == TextureSheetTimeMode.Speed,
			asset.textureSheetAnimation.speedRange);
	if (!rangesOk) { return Result.err(ParticleSystemError.EmptyRange); }
	if (asset.trigger.enabled && (asset.trigger.colliders.length as int32) > MAX_TRIGGER_COLLIDERS) {
		return Result.err(ParticleSystemError.TooManyTriggerColliders);
	}
	const sheet: Borrow<TextureSheetAnimationModule> = asset.textureSheetAnimation;
	if (sheet.enabled && (sheet.numTilesX <= 0 || sheet.numTilesY <= 0)) {
		return Result.err(ParticleSystemError.NoTiles);
	}
	const gradientsOk: boolean = gradientOk(m.startColor) && gradientOk(asset.colorOverLifetime.color)
		&& gradientOk(asset.trails.colorOverLifetime) && gradientOk(asset.trails.colorOverTrail)
		&& gradientOk(asset.colorBySpeed.color) && streamOk(asset.customData.first)
		&& streamOk(asset.customData.second);
	if (!gradientsOk) { return Result.err(ParticleSystemError.InvalidGradient); }
	if (asset.trails.enabled && asset.trails.mode == TrailMode.Ribbon && asset.trails.splitSubEmitterRibbons) {
		return Result.err(ParticleSystemError.SplitSubEmitterRibbons);
	}
	return Result.ok(1);
}

// A system ready to play: the asset checked, its curves compiled and its columns allocated.
export function create(
	this typeof ParticleSystem,
	asset: ParticleSystemAsset,
	seed: uint32,
): Result<ParticleSystem, ParticleSystemError> {
	const _valid = try validateAsset(asset);
	const compiled = compileCurves(asset);
	if (!compiled.ok) { return Result.err(ParticleSystemError.InvalidCurve); }
	const capacity: int32 = asset.main.maxParticles;
	let data: Vec<float32> = new Array(capacity * PARTICLE_COLUMNS);
	for (let i = 0; i < capacity * PARTICLE_COLUMNS; i++) { data[i] = 0.0; }
	let seeds: Vec<uint32> = new Array(capacity);
	let inside: Vec<uint32> = new Array(capacity);
	for (let i = 0; i < capacity; i++) {
		seeds[i] = 0;
		inside[i] = 0;
	}
	const systemSeed: uint32 = asset.main.useAutoRandomSeed ? seed : asset.main.randomSeed;
	return Result.ok({
		asset: asset,
		curves: compiled.value,
		data: data,
		seeds: seeds,
		count: 0,
		capacity: capacity,
		systemSeed: systemSeed,
		spawned: 0,
		playing: false,
		emitting: false,
		time: 0.0,
		cycle: 0,
		delayLeft: 0.0,
		emitCarry: 0.0,
		distanceCarry: 0.0,
		stepIndex: 0,
		clock: { fixedStep: DEFAULT_STEP, maxSubSteps: 8, maxFrameTime: 0.1, remainder: 0.0 },
		gravity: vec3(0.0, -9.81, 0.0),
		world: identity(),
		placed: false,
		frameFrom: vec3(0.0, 0.0, 0.0),
		frameTo: vec3(0.0, 0.0, 0.0),
		stepFrom: vec3(0.0, 0.0, 0.0),
		stepTo: vec3(0.0, 0.0, 0.0),
		emitterVelocity: vec3(0.0, 0.0, 0.0),
		arcPhase: 0.0,
		radiusPhase: 0.0,
		noiseScroll: 0.0,
		noiseOffset: unitDraw(systemSeed, DRAW_NOISE_OFFSET) * 1000.0,
		ringIndex: 0,
		finished: false,
		trails: TrailRings.create(0, 0),
		colliders: [],
		forceFields: [],
		inside: inside,
		events: [],
		births: [],
		wantDeath: false,
		wantCollision: asset.collision.enabled && asset.collision.sendCollisionMessages,
		wantTrigger: false,
	});
}

export function column(this sys: ParticleSystem, c: int32): int32 {
	return c * sys.capacity;
}

export function isAlive(this sys: ParticleSystem): boolean {
	return sys.playing || sys.count > 0;
}

// ParticleSystem.Play: starts a cycle from time 0, draws the start delay once, and prewarms.
export function playSystem(ref sys: ParticleSystem, world: Mat4): void {
	sys.playing = true;
	sys.emitting = true;
	sys.finished = false;
	sys.time = 0.0;
	sys.cycle = 0;
	sys.emitCarry = 0.0;
	sys.distanceCarry = 0.0;
	sys.world = world;
	sys.placed = true;
	sys.stepFrom = world.position();
	sys.stepTo = world.position();
	const delayDraw: float32 = unitDraw(sys.systemSeed, DRAW_START_DELAY);
	sys.delayLeft = sys.curves.startDelay.evaluate(0.0, delayDraw) as float64;
	if (hasTrailRings(sys)) {
		const h: float64 = sys.clock.fixedStep > 0.0 ? sys.clock.fixedStep : DEFAULT_STEP;
		sys.trails = TrailRings.create(sys.capacity, (Math.ceil(maxTrailSeconds(sys) / h) as int32) + 2);
	}
	if (sys.asset.main.prewarm) {
		const h: float64 = sys.clock.fixedStep > 0.0 ? sys.clock.fixedStep : DEFAULT_STEP;
		const steps: int32 = Math.ceil(sys.asset.main.duration as float64 / h) as int32;
		for (let k = 0; k < steps; k++) { step(sys, h); }
	}
}

// ParticleSystem.Stop: emission ends; `clear` also removes the live particles.
export function stopSystem(ref sys: ParticleSystem, clear: boolean): void {
	sys.emitting = false;
	if (clear) {
		sys.count = 0;
		sys.trails.orphans.length = 0;
	}
}

// The steps a frame of `frameTime` seconds runs, carrying the rest of a fixed step in `clock`.
export function frameSteps(ref clock: StepClock, frameTime: float64): FrameSteps {
	const dt: float64 = frameTime > clock.maxFrameTime ? clock.maxFrameTime : frameTime;
	if (!(clock.fixedStep > 0.0)) {
		return { count: dt > 0.0 ? 1 : 0, h: dt, before: 0.0, dt: dt };
	}
	const h: float64 = clock.fixedStep;
	const before: float64 = clock.remainder;
	let pending: float64 = before + dt;
	let count: int32 = Math.floor(pending / h) as int32;
	if (count > clock.maxSubSteps) { count = clock.maxSubSteps; }
	pending = pending - (count as float64) * h;
	clock.remainder = pending < h ? pending : h;
	return { count: count, h: h, before: before, dt: dt };
}

// Starts a frame with the emitter moving to `world`: its velocity over the frame, its path for
// the frame's steps, and an empty event list.
export function beginFrame(ref sys: ParticleSystem, world: Mat4, frame: FrameSteps): void {
	if (!sys.placed) {
		sys.world = world;
		sys.placed = true;
	}
	sys.frameFrom = sys.world.position();
	sys.frameTo = world.position();
	const dt: float64 = frame.dt * (sys.asset.main.simulationSpeed as float64);
	if (sys.asset.main.emitterVelocityMode == EmitterVelocityMode.Custom) {
		sys.emitterVelocity = sys.asset.main.emitterVelocity;
	} else if (dt > 0.0) {
		sys.emitterVelocity = (sys.frameTo - sys.frameFrom).scaled((1.0 / dt) as float32);
	}
	sys.world = world;
	sys.events.length = 0;
}

// Runs the frame's step `k`, with the emitter where that step starts and ends along the frame.
export function stepWithin(ref sys: ParticleSystem, frame: FrameSteps, k: int32): void {
	const start: float64 = (k as float64) * frame.h - frame.before;
	sys.stepFrom = sys.frameFrom.lerp(sys.frameTo, frameFraction(start, frame.dt));
	sys.stepTo = sys.frameFrom.lerp(sys.frameTo, frameFraction(start + frame.h, frame.dt));
	step(sys, frame.h * (sys.asset.main.simulationSpeed as float64));
}

// Advance by one frame of `frameTime` seconds with the emitter at `world`. Runs whole fixed steps
// and keeps the rest for the next update; the emitter moves linearly across the frame's steps.
// A system inside an effect is advanced by the effect instead.
export function updateSystem(
	ref sys: ParticleSystem,
	frameTime: float64,
	world: Mat4,
): Result<int32, ParticleSystemError> {
	if (!Number.isFinite(frameTime) || frameTime < 0.0) {
		return Result.err(ParticleSystemError.NonFiniteStep);
	}
	const frame: FrameSteps = frameSteps(sys.clock, frameTime);
	beginFrame(sys, world, frame);
	for (let k = 0; k < frame.count; k++) { stepWithin(sys, frame, k); }
	return Result.ok(sys.count);
}

function frameFraction(at: float64, dt: float64): float32 {
	if (!(dt > 0.0)) { return 1.0; }
	return saturate((at / dt) as float32);
}

// The emitter matrix `age` seconds before the end of the current step of length `h`.
function emitterAt(sys: ParticleSystem, age: float32, h: float32): Mat4 {
	const back: float32 = h > 0.0 ? saturate(age / h) : 0.0;
	const p: Vec3 = sys.stepTo.lerp(sys.stepFrom, back);
	return { ...sys.world, m41: p.x, m42: p.y, m43: p.z };
}

// ---- one step (SIM §6.3) ----

function step(ref sys: ParticleSystem, h64: float64): void {
	const h: float32 = h64 as float32;
	sys.stepIndex = sys.stepIndex + 1;
	sys.arcPhase = sys.arcPhase
		+ (sys.curves.arcSpeed.evaluate(normalizedTime(sys), 0.0) as float64) * h64;
	sys.radiusPhase = sys.radiusPhase
		+ (sys.curves.radiusSpeed.evaluate(normalizedTime(sys), 0.0) as float64) * h64;
	if (sys.asset.noise.enabled) {
		sys.noiseScroll = sys.noiseScroll + sys.curves.noiseScroll.evaluate(normalizedTime(sys), 0.0) * h;
	}
	if (sys.playing) { advanceTime(sys, h64); }
	sys.trails.drainOrphans(h);
	updateParticles(sys, h);
	if (!sys.emitting && sys.count == 0 && sys.playing) {
		sys.playing = false;
		sys.finished = true;
	}
}

function normalizedTime(sys: ParticleSystem): float32 {
	return saturate((sys.time / (sys.asset.main.duration as float64)) as float32);
}

// Start delay, then the cycle clock: a step that crosses the end of a looping cycle emits over
// two spans, so a burst at 0 fires on every loop and one just before the end fires before the wrap.
function advanceTime(ref sys: ParticleSystem, h: float64): void {
	let dt: float64 = h;
	if (sys.delayLeft > 0.0) {
		sys.delayLeft = sys.delayLeft - dt;
		if (sys.delayLeft > 0.0) { return; }
		dt = -sys.delayLeft;
		sys.delayLeft = 0.0;
	}
	if (!sys.emitting) { return; }
	const duration: float64 = sys.asset.main.duration as float64;
	const t0: float64 = sys.time;
	const t1: float64 = t0 + dt;
	if (t1 < duration) {
		emitSpan(sys, t0, t1, 0.0, h);
		sys.time = t1;
		return;
	}
	emitSpan(sys, t0, duration, t1 - duration, h);
	if (!sys.asset.main.loop) {
		sys.time = duration;
		sys.emitting = false;
		return;
	}
	sys.cycle = sys.cycle + 1;
	let rest: float64 = t1 - duration;
	while (rest >= duration) {
		rest = rest - duration;
		sys.cycle = sys.cycle + 1;
	}
	emitSpan(sys, 0.0, rest, 0.0, h);
	sys.time = rest;
}

// Emission over the cycle span [a, b), which ends `after` seconds before the step does. Rate
// spawns carry the fractional count to the next span and are placed at their own instants;
// a burst spawns at its time; both are pre-advanced to the end of the step.
function emitSpan(ref sys: ParticleSystem, a: float64, b: float64, after: float64, h: float64): void {
	const emission = sys.asset.emission;
	if (!emission.enabled || !(b > a)) { return; }
	const duration: float64 = sys.asset.main.duration as float64;
	const cycleN: float32 = saturate((a / duration) as float32);
	const rateDraw: float32 = unitDraw(mix(sys.systemSeed, sys.stepIndex), DRAW_RATE);
	const rate: float64 = sys.curves.rateOverTime.evaluate(cycleN, rateDraw) as float64;
	const span: float64 = b - a;
	const hs: float32 = h as float32;
	if (rate > 0.0) {
		sys.emitCarry = sys.emitCarry + rate * span;
		const n: int32 = Math.floor(sys.emitCarry) as int32;
		sys.emitCarry = sys.emitCarry - (n as float64);
		for (let k = n - 1; k >= 0; k--) {
			// The k-th most recent spawn of the span, oldest first.
			const back: float64 = (sys.emitCarry + (k as float64)) / rate;
			const age: float32 = ((back < span ? back : span) + after) as float32;
			const at: float32 = saturate(((b - back) / duration) as float32);
			spawnParticle(sys, age, at, hs, { index: n - 1 - k, count: n, arcTimer: 0.0, radiusTimer: 0.0 });
		}
	}
	const distanceRate: float32 = sys.curves.rateOverDistance.evaluate(cycleN, rateDraw);
	if (distanceRate > 0.0) {
		const moved: float32 = (sys.stepTo - sys.stepFrom).length();
		const share: float64 = h > 0.0 ? span / h : 1.0;
		sys.distanceCarry = sys.distanceCarry + ((distanceRate * moved) as float64) * share;
		const n: int32 = Math.floor(sys.distanceCarry) as int32;
		sys.distanceCarry = sys.distanceCarry - (n as float64);
		for (let k = 0; k < n; k++) {
			const back: float64 = span * (((n - k) as float64) - 0.5) / (n as float64);
			spawnParticle(sys, (back + after) as float32, cycleN, hs, { index: k, count: n, arcTimer: 0.0, radiusTimer: 0.0 });
		}
	}
	for (let i = 0; i < (emission.bursts.length as int32); i++) {
		emitBurst(sys, i, a, b, after, hs);
	}
}

function emitBurst(ref sys: ParticleSystem, index: int32, a: float64, b: float64, after: float64, h: float32): void {
	const burst: Burst = sys.asset.emission.bursts[index];
	const duration: float64 = sys.asset.main.duration as float64;
	const interval: float64 = burst.repeatInterval as float64;
	let j: int32 = 0;
	if (burst.cycleCount != 1 && a > (burst.time as float64)) {
		j = Math.ceil((a - (burst.time as float64)) / interval) as int32;
	}
	while (burst.cycleCount == 0 || j < burst.cycleCount) {
		const at: float64 = (burst.time as float64) + (j as float64) * (burst.cycleCount == 1 ? 0.0 : interval);
		if (at >= b) { return; }
		if (at >= a) {
			const key: uint32 = mix(mix(mix(sys.systemSeed, index as uint32), sys.cycle as uint32), j as uint32);
			if (unitDraw(key, DRAW_BURST) < burst.probability) {
				const atN: float32 = saturate((at / duration) as float32);
				const countValue: float32 =
					sys.curves.burstCounts[index].evaluate(atN, unitDraw(key, DRAW_BURST_COUNT));
				const n: int32 = Math.round(countValue) as int32;
				const age: float32 = ((b - at) + after) as float32;
				for (let k = 0; k < n; k++) {
					spawnParticle(sys, age, atN, h, { index: k, count: n, arcTimer: 0.0, radiusTimer: 0.0 });
				}
			}
		}
		if (burst.cycleCount == 1) { return; }
		j = j + 1;
	}
}

// ---- spawn (SIM §6.3 step 4) ----

function put(ref sys: ParticleSystem, c: int32, i: int32, value: float32): void {
	sys.data[c * sys.capacity + i] = value;
}

function get(sys: ParticleSystem, c: int32, i: int32): float32 {
	return sys.data[c * sys.capacity + i];
}

// The slot a new particle takes: the next free one, or with a ring buffer the oldest; -1 drops it.
function claimSlot(ref sys: ParticleSystem): int32 {
	if (sys.count < sys.capacity) {
		sys.count = sys.count + 1;
		return sys.count - 1;
	}
	if (sys.asset.main.ringBufferMode == RingBufferMode.Disabled) { return -1; }
	const slot: int32 = sys.ringIndex;
	sys.ringIndex = (sys.ringIndex + 1) % sys.capacity;
	return slot;
}

// A particle born `age` seconds before the end of the step, at normalized cycle time `cycleN`.
function spawnParticle(ref sys: ParticleSystem, age: float32, cycleN: float32, h: float32, slot: ShapeSlot): void {
	sys.spawned = sys.spawned + 1;
	const local: boolean = sys.asset.main.simulationSpace == SimulationSpace.Local;
	const origin: Mat4 = local ? identity() : emitterAt(sys, age, h);
	const _slot = spawnAt(sys, origin, sys.emitterVelocity, mix(sys.systemSeed, sys.spawned), age, cycleN, slot);
}

// A particle from the shape placed by `origin`, which carries simulation space; `emitterVelocity`
// feeds Inherit Velocity. Returns its slot, or -1 when the system is full.
function spawnAt(
	ref sys: ParticleSystem, origin: Mat4, emitterVelocity: Vec3, seed: uint32, age: float32,
	cycleN: float32, slot: ShapeSlot,
): int32 {
	const i: int32 = claimSlot(sys);
	if (i < 0) { return -1; }
	// PENDING3D: particle-random-per-life
	sys.seeds[i] = seed;
	sys.inside[i] = 0;
	const m: Borrow<MainModule> = sys.asset.main;
	const c: Borrow<CompiledCurves> = sys.curves;
	const world: Mat4 = origin;
	const timers: ShapeSlot = {
		...slot,
		arcTimer: (sys.arcPhase as float32) - c.arcSpeed.evaluate(cycleN, 0.0) * age,
		radiusTimer: (sys.radiusPhase as float32) - c.radiusSpeed.evaluate(cycleN, 0.0) * age,
	};
	const sample: ShapeSample = sampleShape(sys.asset.shape, seed, timers);
	let lifetime: float32 = c.startLifetime.evaluate(cycleN, unitDraw(seed, DRAW_LIFETIME));
	if (sys.asset.lifetimeByEmitterSpeed.enabled) {
		const u: float32 = within(sys.asset.lifetimeByEmitterSpeed.range, sys.emitterVelocity.length());
		lifetime = lifetime * c.lifetimeByEmitterSpeed.evaluate(u, unitDraw(seed, DRAW_LIFETIME_SPEED));
	}
	const speed: float32 = c.startSpeed.evaluate(cycleN, unitDraw(seed, DRAW_SPEED));
	let pos: Vec3 = sample.position;
	let vel: Vec3 = sample.direction.scaled(speed);
	pos = pos * world;
	vel = vel.transformDirection(world);
	if (sys.asset.inheritVelocity.enabled && sys.asset.inheritVelocity.mode == InheritVelocityMode.Initial
		&& m.simulationSpace == SimulationSpace.World) {
		const k: float32 = c.inheritVelocity.evaluate(cycleN, unitDraw(seed, DRAW_INHERIT));
		vel = vel + emitterVelocity.scaled(k);
	}
	if (sys.asset.space2D) {
		pos = vec3(pos.x, pos.y, 0.0);
		vel = vec3(vel.x, vel.y, 0.0);
	}
	const sx: float32 = c.startSizeX.evaluate(cycleN, unitDraw(seed, DRAW_SIZE));
	const sy: float32 = m.startSize3D ? c.startSizeY.evaluate(cycleN, unitDraw(seed, DRAW_SIZE_Y)) : sx;
	const sz: float32 = m.startSize3D ? c.startSizeZ.evaluate(cycleN, unitDraw(seed, DRAW_SIZE_Z)) : sx;
	const flip: float32 = unitDraw(seed, DRAW_FLIP) < m.flipRotation ? -1.0 : 1.0;
	const rz: float32 = c.startRotationZ.evaluate(cycleN, unitDraw(seed, DRAW_ROTATION_Z)) * flip;
	const rx: float32 = m.startRotation3D ? c.startRotationX.evaluate(cycleN, unitDraw(seed, DRAW_ROTATION)) * flip : 0.0;
	const ry: float32 = m.startRotation3D ? c.startRotationY.evaluate(cycleN, unitDraw(seed, DRAW_ROTATION_Y)) * flip : 0.0;
	const color: ParticleColor = m.startColor.evaluate(cycleN, unitDraw(seed, DRAW_COLOR));
	put(sys, POS_X, i, pos.x);
	put(sys, POS_Y, i, pos.y);
	put(sys, POS_Z, i, pos.z);
	put(sys, VEL_X, i, vel.x);
	put(sys, VEL_Y, i, vel.y);
	put(sys, VEL_Z, i, vel.z);
	put(sys, MOVE_X, i, vel.x);
	put(sys, MOVE_Y, i, vel.y);
	put(sys, MOVE_Z, i, vel.z);
	put(sys, AGE, i, 0.0);
	put(sys, PENDING, i, age);
	put(sys, LIFETIME, i, lifetime);
	put(sys, START_SIZE_X, i, sx);
	put(sys, START_SIZE_Y, i, sy);
	put(sys, START_SIZE_Z, i, sz);
	put(sys, ROT_X, i, rx);
	put(sys, ROT_Y, i, ry);
	put(sys, ROT_Z, i, rz);
	put(sys, START_R, i, color.r);
	put(sys, START_G, i, color.g);
	put(sys, START_B, i, color.b);
	put(sys, START_A, i, color.a);
	startAppearance(sys, i);
	put(sys, BIRTH_CARRY, i, 0.0);
	put(sys, BIRTH_CARRY + 1, i, 0.0);
	const ribbons: uint32 = sys.asset.trails.ribbonCount > 1 ? sys.asset.trails.ribbonCount as uint32 : 1;
	put(sys, RIBBON, i, (sys.spawned % ribbons) as float32);
	if (sys.trails.perSlot > 0) { sys.trails.clearSlot(i); }
	return i;
}

// A newborn shows its start colour and size until its first update, so a Birth event and the
// collision radius of its first step read real values.
function startAppearance(ref sys: ParticleSystem, i: int32): void {
	for (let k = 0; k < 3; k++) { put(sys, SIZE_X + k, i, get(sys, START_SIZE_X + k, i)); }
	for (let k = 0; k < 4; k++) { put(sys, COLOR_R + k, i, get(sys, START_R + k, i)); }
}

// Spawns a sub-emitter's children for one event of its parent, with the parent's properties the
// entry inherits: colour and size multiply, rotation adds, lifetime shrinks with the parent's age.
export function spawnFromEvent(
	ref sys: ParticleSystem, event: ParticleEvent, properties: BitSet<SubEmitterProperty>, key: uint32,
): void {
	const local: boolean = sys.asset.main.simulationSpace == SimulationSpace.Local;
	let n: int32 = event.count;
	if (n < 0) {
		n = 0;
		for (let b = 0; b < (sys.asset.emission.bursts.length as int32); b++) {
			const value: float32 = sys.curves.burstCounts[b].evaluate(0.0, unitDraw(mix(key, b as uint32), DRAW_BURST_COUNT));
			n = n + (Math.round(value) as int32);
		}
	}
	for (let k = 0; k < n; k++) {
		// Rate children spread along the parent's path over the step, oldest first.
		const along: float32 = event.count < 0 ? 1.0 : ((k + 1) as float32) / (n as float32);
		const p: Vec3 = event.from.lerp(event.position, along);
		const age: float32 = event.count < 0 ? event.before : event.before * (1.0 - along);
		const origin: Mat4 = local ? translation(p.x, p.y, p.z) : { ...sys.world, m41: p.x, m42: p.y, m43: p.z };
		sys.spawned = sys.spawned + 1;
		const i: int32 = spawnAt(sys, origin, event.velocity, mix(key, k as uint32), age, 0.0,
			{ index: k, count: n, arcTimer: 0.0, radiusTimer: 0.0 });
		if (i < 0) { return; }
		if (properties.has(SubEmitterProperty.InheritColor)) {
			put(sys, START_R, i, get(sys, START_R, i) * event.color.r);
			put(sys, START_G, i, get(sys, START_G, i) * event.color.g);
			put(sys, START_B, i, get(sys, START_B, i) * event.color.b);
			put(sys, START_A, i, get(sys, START_A, i) * event.color.a);
		}
		if (properties.has(SubEmitterProperty.InheritSize)) {
			put(sys, START_SIZE_X, i, get(sys, START_SIZE_X, i) * event.size.x);
			put(sys, START_SIZE_Y, i, get(sys, START_SIZE_Y, i) * event.size.y);
			put(sys, START_SIZE_Z, i, get(sys, START_SIZE_Z, i) * event.size.z);
		}
		startAppearance(sys, i);
		if (properties.has(SubEmitterProperty.InheritRotation)) {
			put(sys, ROT_X, i, get(sys, ROT_X, i) + event.rotation.x);
			put(sys, ROT_Y, i, get(sys, ROT_Y, i) + event.rotation.y);
			put(sys, ROT_Z, i, get(sys, ROT_Z, i) + event.rotation.z);
		}
		if (properties.has(SubEmitterProperty.InheritLifetime)) {
			put(sys, LIFETIME, i, get(sys, LIFETIME, i) * (1.0 - event.ageFraction));
		}
	}
}

// The event a particle makes, carrying the state its children may inherit.
export function eventOf(
	sys: ParticleSystem, i: int32, kind: SubEmitterType, position: Vec3, velocity: Vec3, before: float32,
	ageFraction: float32,
): ParticleEvent {
	return {
		kind: kind, trigger: TriggerEvent.Inside, link: -1, count: -1,
		position: position, from: position, velocity: velocity, normal: vec3(0.0, 1.0, 0.0), collider: -1,
		color: { r: get(sys, COLOR_R, i), g: get(sys, COLOR_G, i), b: get(sys, COLOR_B, i), a: get(sys, COLOR_A, i) },
		size: vec3(get(sys, SIZE_X, i), get(sys, SIZE_Y, i), get(sys, SIZE_Z, i)),
		rotation: vec3(get(sys, ROT_X, i), get(sys, ROT_Y, i), get(sys, ROT_Z, i)),
		ageFraction: ageFraction, before: before, seed: sys.seeds[i],
	};
}

// ---- update of the live particles (SIM §6.3 steps 5-14) ----

// Rotates `v` about X, then Y, then Z by the given angles.
function rotateXYZ(v: Vec3, ax: float32, ay: float32, az: float32): Vec3 {
	let p: Vec3 = v;
	if (ax != 0.0) {
		const c: float32 = Math.cos(ax) as float32;
		const s: float32 = Math.sin(ax) as float32;
		p = vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
	}
	if (ay != 0.0) {
		const c: float32 = Math.cos(ay) as float32;
		const s: float32 = Math.sin(ay) as float32;
		p = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
	}
	if (az != 0.0) {
		const c: float32 = Math.cos(az) as float32;
		const s: float32 = Math.sin(az) as float32;
		p = vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
	}
	return p;
}

// The matrices that carry a direction between the module's space and the simulation's.
struct Spaces {
	toWorld: Mat4;
	toLocal: Mat4;
	local: boolean;
}

function intoSimulation(spaces: Spaces, moduleSpace: SimulationSpace, v: Vec3): Vec3 {
	if (spaces.local && moduleSpace == SimulationSpace.World) { return v.transformDirection(spaces.toLocal); }
	if (!spaces.local && moduleSpace == SimulationSpace.Local) { return v.transformDirection(spaces.toWorld); }
	return v;
}

function noiseAt(sys: ParticleSystem, p: Vec3): Vec3 {
	const n: Borrow<NoiseModule> = sys.asset.noise;
	let sum: Vec3 = vec3(0.0, 0.0, 0.0);
	let amplitude: float32 = 1.0;
	let frequency: float32 = n.frequency;
	let total: float32 = 0.0;
	for (let o = 0; o < n.octaveCount; o++) {
		const v: Vec3 = noise3(
			p.x * frequency + sys.noiseOffset, p.y * frequency, p.z * frequency, sys.noiseScroll,
		);
		sum = sum + v.scaled(amplitude);
		total = total + amplitude;
		amplitude = amplitude * n.octaveMultiplier;
		frequency = frequency * n.octaveScale;
	}
	if (total > 0.0) { sum = sum.scaled(1.0 / total); }
	return match (n.quality) {
		NoiseQuality.Low => vec3(sum.x, sum.x, sum.x),
		NoiseQuality.Medium => vec3(sum.x, sum.y, sum.x),
		NoiseQuality.High => sum,
	};
}

function updateParticles(ref sys: ParticleSystem, h: float32): void {
	const asset = sys.asset;
	const c = sys.curves;
	const local: boolean = asset.main.simulationSpace == SimulationSpace.Local;
	const spaces: Spaces = { toWorld: sys.world, toLocal: sys.world.inverseAffine(), local: local };
	const emitterN: float32 = normalizedTime(sys);
	const gravityWorld: Vec3 = sys.gravity;
	const gravity: Vec3 = local ? gravityWorld.transformDirection(spaces.toLocal) : gravityWorld;
	const origin: Vec3 = local ? vec3(0.0, 0.0, 0.0) : sys.world.position();
	const ring: RingBufferMode = asset.main.ringBufferMode;
	const vol = asset.velocityOverLifetime;
	const limit = asset.limitVelocityOverLifetime;
	const noise = asset.noise;
	const inheritCurrent: boolean = asset.inheritVelocity.enabled && !local
		&& asset.inheritVelocity.mode == InheritVelocityMode.Current;
	const collision = asset.collision;
	const trigger = asset.trigger;
	const triggerAll: uint32 = trigger.enabled ? allBits(trigger.colliders.length as int32) : 0;
	const worldColliders: boolean = collision.enabled && collision.collisionType == CollisionType.World;
	const noColliders: Vec<ParticleCollider> = [];
	const fields: boolean = asset.externalForces.enabled && sys.forceFields.length > 0;
	// Unity's removal: the last particle moves into a dead one's slot and is updated there.
	let live: int32 = sys.count;
	let i: int32 = 0;
	while (i < live) {
		const seed: uint32 = sys.seeds[i];
		const lifetime: float32 = get(sys, LIFETIME, i);
		// A particle born this step simulates from its spawn instant, as Unity's do.
		const pending: float32 = get(sys, PENDING, i);
		const dt: float32 = pending >= 0.0 ? pending : h;
		let age: float32 = get(sys, AGE, i) + dt;
		if (ring == RingBufferMode.PauseUntilReplaced && age >= lifetime) {
			age = lifetime * 0.99999;
		} else if (ring == RingBufferMode.LoopUntilReplaced && age >= lifetime * asset.main.ringBufferLoopRange.max) {
			const lo: float32 = lifetime * asset.main.ringBufferLoopRange.min;
			const span: float32 = lifetime * asset.main.ringBufferLoopRange.max - lo;
			age = span > 0.0 ? lo + fract((age - lo) / span) * span : lo;
		}
		let dead: boolean = age >= lifetime;
		if (dead && !sys.wantDeath) {
			endTrail(sys, i, age);
			live = live - 1;
			moveSlot(sys, live, i);
			continue;
		}
		const tN: float32 = saturate(age / lifetime);
		let pos: Vec3 = vec3(get(sys, POS_X, i), get(sys, POS_Y, i), get(sys, POS_Z, i));
		let vel: Vec3 = vec3(get(sys, VEL_X, i), get(sys, VEL_Y, i), get(sys, VEL_Z, i));
		// Animated velocity: recomputed from zero each step, never integrated into `vel`.
		let animated: Vec3 = vec3(0.0, 0.0, 0.0);
		let speedScale: float32 = 1.0;
		if (vol.enabled) {
			const r: float32 = unitDraw(seed, DRAW_VELOCITY);
			const linear: Vec3 = vec3(c.velocityX.evaluate(tN, r), c.velocityY.evaluate(tN, r), c.velocityZ.evaluate(tN, r));
			animated = animated + intoSimulation(spaces, vol.space, linear);
			const centre: Vec3 = origin + vec3(
				c.orbitalOffsetX.evaluate(tN, r), c.orbitalOffsetY.evaluate(tN, r), c.orbitalOffsetZ.evaluate(tN, r),
			);
			const rel: Vec3 = pos - centre;
			const ox: float32 = c.orbitalX.evaluate(tN, r);
			const oy: float32 = c.orbitalY.evaluate(tN, r);
			const oz: float32 = c.orbitalZ.evaluate(tN, r);
			if ((ox != 0.0 || oy != 0.0 || oz != 0.0) && dt > 0.0) {
				// Godot's exact orbit: rotate the offset by the step's angle, so the radius holds.
				const turned: Vec3 = rotateXYZ(rel, ox * dt, oy * dt, oz * dt);
				animated = animated + (turned - rel).scaled(1.0 / dt);
			}
			const radial: float32 = c.radial.evaluate(tN, r);
			if (radial != 0.0) {
				const distance: float32 = rel.length();
				let push: float32 = radial;
				// Inward never overshoots the centre in one step.
				if (push < 0.0 && -push * dt > distance) { push = dt > 0.0 ? -distance / dt : 0.0; }
				animated = animated + rel.normalized().scaled(push);
			}
			speedScale = c.speedModifier.evaluate(tN, r);
		}
		if (inheritCurrent) {
			animated = animated + sys.emitterVelocity.scaled(c.inheritVelocity.evaluate(tN, unitDraw(seed, DRAW_INHERIT)));
		}
		if (asset.forceOverLifetime.enabled) {
			const force = asset.forceOverLifetime;
			const r: float32 = force.randomized
				? unitDraw(mix(seed, sys.stepIndex), DRAW_FORCE)
				: unitDraw(seed, DRAW_FORCE);
			const f: Vec3 = vec3(c.forceX.evaluate(tN, r), c.forceY.evaluate(tN, r), c.forceZ.evaluate(tN, r));
			vel = vel + intoSimulation(spaces, force.space, f).scaled(dt);
		}
		const g: float32 = c.gravityModifier.evaluate(emitterN, unitDraw(seed, DRAW_GRAVITY));
		if (g != 0.0) { vel = vel + gravity.scaled(g * dt); }
		if (fields) {
			const multiplier: float32 = c.externalMultiplier.evaluate(tN, unitDraw(seed, DRAW_GRAVITY));
			for (const field of sys.forceFields) {
				if ((asset.externalForces.influenceMask & ((1 as uint32) << (field.layer as uint32))) == 0) { continue; }
				const push: FieldPush = fieldPush(field, pos, vel.length(), get(sys, SIZE_X, i));
				vel = vel + push.acceleration.scaled(multiplier * dt);
				const speedNow: float32 = vel.length();
				if (push.drag > 0.0 && speedNow > 0.0) {
					const slower: float32 = speedNow - push.drag * multiplier * dt;
					vel = vel.scaled(slower > 0.0 ? slower / speedNow : 0.0);
				}
			}
		}
		let noiseRotation: float32 = 0.0;
		let noiseSize: float32 = 1.0;
		if (noise.enabled) {
			const r: float32 = unitDraw(seed, DRAW_NOISE);
			let n: Vec3 = noiseAt(sys, pos);
			if (noise.remapEnabled) {
				n = vec3(
					c.noiseRemapX.evaluate((n.x + 1.0) * 0.5, r),
					c.noiseRemapY.evaluate((n.y + 1.0) * 0.5, r),
					c.noiseRemapZ.evaluate((n.z + 1.0) * 0.5, r),
				);
			}
			const sx: float32 = c.noiseStrengthX.evaluate(tN, r);
			const sy: float32 = noise.separateAxes ? c.noiseStrengthY.evaluate(tN, r) : sx;
			const sz: float32 = noise.separateAxes ? c.noiseStrengthZ.evaluate(tN, r) : sx;
			// Damping keeps the displacement of the field the same at any frequency (measured 2x
			// the undamped amplitude at frequency 0.5, tests/unity/goldens/noise_*).
			const damp: float32 = noise.damping ? 1.0 / noise.frequency : 1.0;
			const amount: float32 = c.noisePosition.evaluate(tN, r) * damp;
			animated = animated + vec3(n.x * sx, n.y * sy, n.z * sz).scaled(amount);
			noiseRotation = n.x * c.noiseRotation.evaluate(tN, r) * DEGREE;
			noiseSize = 1.0 + n.y * c.noiseSize.evaluate(tN, r);
		}
		if (limit.enabled) {
			const r: float32 = unitDraw(seed, DRAW_LIMIT);
			// Drag takes a fixed amount off the speed and keeps the direction; by size it scales
			// with the particle's cross-section, by velocity with the speed squared
			// (tests/unity/goldens/drag1_size2_speed10*).
			let drag: float32 = c.drag.evaluate(tN, r);
			const speedBefore: float32 = vel.length();
			if (drag > 0.0 && speedBefore > 0.0) {
				if (limit.multiplyDragByParticleSize) {
					const radius: float32 = get(sys, SIZE_X, i) * 0.5;
					drag = drag * PI * radius * radius;
				}
				if (limit.multiplyDragByParticleVelocity) { drag = drag * speedBefore * speedBefore; }
				const slower: float32 = speedBefore - drag * dt;
				vel = vel.scaled(slower > 0.0 ? slower / speedBefore : 0.0);
			}
			// The excess over the limit decays by (1 - dampen) every 1/30 s, at any step size
			// (tests/unity/goldens/limit_velocity_dampen05_dt30, _dt60).
			const removed: float32 = 1.0 - (Math.pow((1.0 - limit.dampen) as float64, (30.0 * dt) as float64) as float32);
			const total: Vec3 = vel + animated;
			if (limit.separateAxes) {
				const t: Vec3 = intoSimulation(spaces, limit.space, total);
				vel = vel - vec3(
					excess(t.x, c.limitX.evaluate(tN, r)),
					excess(t.y, c.limitY.evaluate(tN, r)),
					excess(t.z, c.limitZ.evaluate(tN, r)),
				).scaled(removed);
			} else {
				const speed: float32 = total.length();
				const cap: float32 = c.limit.evaluate(tN, r);
				if (speed > cap) {
					vel = vel - total.scaled(removed * (speed - cap) / speed);
				}
			}
		}
		// speedModifier scales the displacement only; the stored velocity keeps its full value.
		let move: Vec3 = vel + animated;
		if (asset.space2D) {
			move = vec3(move.x, move.y, 0.0);
			vel = vec3(vel.x, vel.y, 0.0);
		}
		const start: Vec3 = pos;
		const displacement: Vec3 = move.scaled(speedScale * dt);
		let hit: Hit = MISS;
		if (collision.enabled && !dead) {
			const radius: float32 = get(sys, SIZE_X, i) * 0.5 * collision.radiusScale;
			hit = sweep(pos, displacement, radius, collision.planes,
				worldColliders ? sys.colliders : noColliders, collision.collidesWith);
		}
		if (hit.hit) {
			// Unity's response: the normal part scaled by bounce, all of it by (1 - dampen), and
			// the rest of the step spent at the new velocity (tests/unity/goldens/collision_plane_*).
			const r: float32 = unitDraw(seed, DRAW_COLLISION);
			const speedBefore: float32 = vel.length();
			const vn: Vec3 = hit.normal.scaled(vel.dot(hit.normal));
			const vt: Vec3 = vel - vn;
			vel = (vt - vn.scaled(c.collisionBounce.evaluate(tN, r))).scaled(1.0 - c.collisionDampen.evaluate(tN, r));
			if (asset.space2D) { vel = vec3(vel.x, vel.y, 0.0); }
			age = age + c.collisionLifetimeLoss.evaluate(tN, r) * lifetime;
			const contact: Vec3 = pos + displacement.scaled(hit.fraction);
			move = vel + animated;
			pos = contact + move.scaled(speedScale * dt * (1.0 - hit.fraction));
			// A collision kill ends the lifetime and the particle leaves on the next update, as Unity
			// shows it one more frame with no lifetime left (tests/unity/goldens/collision_plane_minkill3).
			if (speedBefore < collision.minKillSpeed || speedBefore > collision.maxKillSpeed || age > lifetime) {
				age = lifetime;
			}
			if (sys.wantCollision) {
				sys.events.push({
					...eventOf(sys, i, SubEmitterType.Collision, contact, vel, dt * (1.0 - hit.fraction), saturate(age / lifetime)),
					normal: hit.normal, collider: hit.collider,
				});
			}
		} else {
			pos = pos + displacement;
		}
		const speed: float32 = move.length();
		if (trigger.enabled && !dead) {
			const radius: float32 = get(sys, SIZE_X, i) * 0.5 * trigger.radiusScale;
			const now: uint32 = overlaps(pos, radius, trigger.colliders);
			const was: uint32 = sys.inside[i];
			sys.inside[i] = now;
			// A particle born inside a collider enters it (tests/unity/goldens/trigger_enter_kill).
			dead = applyTrigger(sys, i, trigger.enter, TriggerEvent.Enter, now & ~was, pos, vel) || dead;
			dead = applyTrigger(sys, i, trigger.exit, TriggerEvent.Exit, was & ~now, pos, vel) || dead;
			dead = applyTrigger(sys, i, trigger.inside, TriggerEvent.Inside, now, pos, vel) || dead;
			dead = applyTrigger(sys, i, trigger.outside, TriggerEvent.Outside, triggerAll & ~now, pos, vel) || dead;
		}
		for (let b = 0; b < (sys.births.length as int32); b++) {
			emitBirth(sys, i, b, start, pos, vel, pending >= 0.0, tN, dt);
		}
		if (dead) {
			if (sys.wantDeath) {
				sys.events.push(eventOf(sys, i, SubEmitterType.Death, pos, vel, 0.0, 1.0));
			}
			endTrail(sys, i, age);
			live = live - 1;
			moveSlot(sys, live, i);
			continue;
		}
		if (sys.trails.perSlot > 0 && hasTrail(sys, i)) {
			sys.trails.record(i, pos, age, trailSeconds(sys, i), asset.trails.minVertexDistance);
		}
		const k: int32 = i;
		i = i + 1;
		put(sys, POS_X, k, pos.x);
		put(sys, POS_Y, k, pos.y);
		put(sys, POS_Z, k, pos.z);
		put(sys, VEL_X, k, vel.x);
		put(sys, VEL_Y, k, vel.y);
		put(sys, VEL_Z, k, vel.z);
		put(sys, MOVE_X, k, move.x);
		put(sys, MOVE_Y, k, move.y);
		put(sys, MOVE_Z, k, move.z);
		put(sys, AGE, k, age);
		put(sys, PENDING, k, -1.0);
		integrateRotation(sys, k, tN, speed, dt, noiseRotation);
		writeAppearance(sys, k, speed, noiseSize);
	}
	sys.count = live;
}

function hasTrailRings(sys: ParticleSystem): boolean {
	return sys.asset.trails.enabled && sys.asset.trails.mode == TrailMode.PerParticle;
}

// Whether the Trails module's ratio gave particle `i` a trail.
export function hasTrail(sys: ParticleSystem, i: int32): boolean {
	return unitDraw(sys.seeds[i], DRAW_TRAIL) < sys.asset.trails.ratio;
}

// How long particle `i`'s trail points live: a share of its lifetime, scaled by its size when
// the module asks.
export function trailSeconds(sys: ParticleSystem, i: int32): float32 {
	const t: Borrow<TrailModule> = sys.asset.trails;
	let seconds: float32 = sys.curves.trailLifetime.evaluate(0.0, unitDraw(sys.seeds[i], DRAW_TRAIL_LIFETIME))
		* get(sys, LIFETIME, i);
	if (t.sizeAffectsLifetime) { seconds = seconds * get(sys, SIZE_X, i); }
	return seconds;
}

function maxTrailSeconds(sys: ParticleSystem): float64 {
	const c: Borrow<CompiledCurves> = sys.curves;
	let seconds: float64 = (c.trailLifetime.maxValue() * c.startLifetime.maxValue()) as float64;
	if (sys.asset.trails.sizeAffectsLifetime) { seconds = seconds * (c.startSizeX.maxValue() as float64); }
	return seconds > 0.0 ? seconds : 0.0;
}

// A dying particle's trail drains on its own when it outlives the particle, else goes with it.
function endTrail(ref sys: ParticleSystem, i: int32, age: float32): void {
	if (sys.trails.perSlot == 0) { return; }
	if (!sys.asset.trails.dieWithParticles && hasTrail(sys, i)) {
		sys.trails.orphan(i, age, trailSeconds(sys, i),
			{ r: get(sys, COLOR_R, i), g: get(sys, COLOR_G, i), b: get(sys, COLOR_B, i), a: get(sys, COLOR_A, i) },
			get(sys, SIZE_X, i), get(sys, LIFETIME, i), sys.seeds[i]);
	} else {
		sys.trails.clearSlot(i);
	}
}

function allBits(n: int32): uint32 {
	return n >= 32 ? 0xFFFFFFFF : ((1 as uint32) << (n as uint32)) - 1;
}

// One trigger event type for the colliders in `bits`: Kill reports death, Callback records an
// event for the app and the Trigger sub-emitters.
function applyTrigger(
	ref sys: ParticleSystem, i: int32, action: TriggerAction, kind: TriggerEvent, bits: uint32, pos: Vec3,
	vel: Vec3,
): boolean {
	if (bits == 0) { return false; }
	return match (action) {
		TriggerAction.Ignore => false,
		TriggerAction.Kill => true,
		TriggerAction.Callback => {
			let collider: int32 = 0;
			while (((bits >> (collider as uint32)) & 1) == 0) { collider = collider + 1; }
			sys.events.push({
				...eventOf(sys, i, SubEmitterType.Trigger, pos, vel, 0.0, 0.0),
				trigger: kind, collider: collider,
			});
			return false;
		},
	};
}

// A Birth link's children for one parent particle this step: the child's bursts when the parent
// is born, then its rate over time and distance carried per parent (Unity's m_EmitAccumulator).
function emitBirth(
	ref sys: ParticleSystem, i: int32, b: int32, from: Vec3, to: Vec3, vel: Vec3, born: boolean, tN: float32,
	dt: float32,
): void {
	const link: BirthLink = sys.births[b];
	if (born) {
		sys.events.push({ ...eventOf(sys, i, SubEmitterType.Birth, from, vel, dt, tN), link: b });
	}
	const r: float32 = unitDraw(sys.seeds[i], DRAW_BIRTH);
	const carry: float32 = get(sys, BIRTH_CARRY + b, i)
		+ link.rate.evaluate(tN, r) * dt + link.distanceRate.evaluate(tN, r) * (to - from).length();
	const n: int32 = Math.floor(carry as float64) as int32;
	put(sys, BIRTH_CARRY + b, i, carry - (n as float32));
	if (n > 0) {
		sys.events.push({ ...eventOf(sys, i, SubEmitterType.Birth, to, vel, dt, tN), link: b, count: n, from: from });
	}
}

// The signed part of `v` beyond `cap` in magnitude.
function excess(v: float32, cap: float32): float32 {
	if (v > cap) { return v - cap; }
	if (v < -cap) { return v + cap; }
	return 0.0;
}

function moveSlot(ref sys: ParticleSystem, from: int32, to: int32): void {
	for (let col = 0; col < PARTICLE_COLUMNS; col++) {
		const base: int32 = col * sys.capacity;
		sys.data[base + to] = sys.data[base + from];
	}
	sys.seeds[to] = sys.seeds[from];
	sys.inside[to] = sys.inside[from];
	if (sys.trails.perSlot > 0) { sys.trails.moveSlot(from, to); }
}

// Rotation over lifetime and by speed are angular velocities in rad/s, integrated per step.
function integrateRotation(ref sys: ParticleSystem, i: int32, tN: float32, speed: float32, h: float32, noiseSpin: float32): void {
	const asset: Borrow<ParticleSystemAsset> = sys.asset;
	const c: Borrow<CompiledCurves> = sys.curves;
	const seed: uint32 = sys.seeds[i];
	const flip: float32 = unitDraw(seed, DRAW_FLIP) < asset.main.flipRotation ? -1.0 : 1.0;
	let wx: float32 = 0.0;
	let wy: float32 = 0.0;
	let wz: float32 = noiseSpin;
	if (asset.rotationOverLifetime.enabled) {
		const r: float32 = unitDraw(seed, DRAW_ROTATION_LIFE);
		wz = wz + c.rotationZ.evaluate(tN, r);
		if (asset.rotationOverLifetime.separateAxes) {
			wx = wx + c.rotationX.evaluate(tN, r);
			wy = wy + c.rotationY.evaluate(tN, r);
		}
	}
	if (asset.rotationBySpeed.enabled) {
		const r: float32 = unitDraw(seed, DRAW_ROTATION_SPEED);
		const u: float32 = within(asset.rotationBySpeed.range, speed);
		wz = wz + c.rotationBySpeedZ.evaluate(u, r);
		if (asset.rotationBySpeed.separateAxes) {
			wx = wx + c.rotationBySpeedX.evaluate(u, r);
			wy = wy + c.rotationBySpeedY.evaluate(u, r);
		}
	}
	put(sys, ROT_X, i, get(sys, ROT_X, i) + wx * flip * h);
	put(sys, ROT_Y, i, get(sys, ROT_Y, i) + wy * flip * h);
	put(sys, ROT_Z, i, get(sys, ROT_Z, i) + wz * flip * h);
}

// Size, colour, texture sheet frame and custom data at the particle's current age and speed.
function writeAppearance(ref sys: ParticleSystem, i: int32, speed: float32, noiseSize: float32): void {
	const seed: uint32 = sys.seeds[i];
	const age: float32 = get(sys, AGE, i);
	const tN: float32 = saturate(age / get(sys, LIFETIME, i));
	let sx: float32 = get(sys, START_SIZE_X, i) * noiseSize;
	let sy: float32 = get(sys, START_SIZE_Y, i) * noiseSize;
	let sz: float32 = get(sys, START_SIZE_Z, i) * noiseSize;
	if (sys.asset.sizeOverLifetime.enabled) {
		const r: float32 = unitDraw(seed, DRAW_SIZE_LIFE);
		const x: float32 = sys.curves.sizeX.evaluate(tN, r);
		const separate: boolean = sys.asset.sizeOverLifetime.separateAxes;
		sx = sx * x;
		sy = sy * (separate ? sys.curves.sizeY.evaluate(tN, r) : x);
		sz = sz * (separate ? sys.curves.sizeZ.evaluate(tN, r) : x);
	}
	if (sys.asset.sizeBySpeed.enabled) {
		const r: float32 = unitDraw(seed, DRAW_SIZE_SPEED);
		const u: float32 = within(sys.asset.sizeBySpeed.range, speed);
		const x: float32 = sys.curves.sizeBySpeedX.evaluate(u, r);
		const separate: boolean = sys.asset.sizeBySpeed.separateAxes;
		sx = sx * x;
		sy = sy * (separate ? sys.curves.sizeBySpeedY.evaluate(u, r) : x);
		sz = sz * (separate ? sys.curves.sizeBySpeedZ.evaluate(u, r) : x);
	}
	put(sys, SIZE_X, i, sx);
	put(sys, SIZE_Y, i, sy);
	put(sys, SIZE_Z, i, sz);
	let color: ParticleColor = {
		r: get(sys, START_R, i), g: get(sys, START_G, i), b: get(sys, START_B, i), a: get(sys, START_A, i),
	};
	if (sys.asset.colorOverLifetime.enabled) {
		color = color.times(sys.asset.colorOverLifetime.color.evaluate(tN, unitDraw(seed, DRAW_COLOR_LIFE)));
	}
	if (sys.asset.colorBySpeed.enabled) {
		const u: float32 = within(sys.asset.colorBySpeed.range, speed);
		color = color.times(sys.asset.colorBySpeed.color.evaluate(u, unitDraw(seed, DRAW_COLOR_SPEED)));
	}
	put(sys, COLOR_R, i, color.r);
	put(sys, COLOR_G, i, color.g);
	put(sys, COLOR_B, i, color.b);
	put(sys, COLOR_A, i, color.a);
	if (sys.asset.textureSheetAnimation.enabled) { put(sys, FRAME, i, sheetFrame(sys, seed, tN, age, speed)); }
	if (sys.asset.customData.enabled) {
		writeCustom(sys, i, CUSTOM1_X, sys.asset.customData.first, sys.curves.custom1X, sys.curves.custom1Y, sys.curves.custom1Z, sys.curves.custom1W, tN, seed);
		writeCustom(sys, i, CUSTOM2_X, sys.asset.customData.second, sys.curves.custom2X, sys.curves.custom2Y, sys.curves.custom2Z, sys.curves.custom2W, tN, seed + 1);
	}
}

// Texture Sheet Animation: the frame over lifetime, by speed or at a frame rate, offset by the
// start frame and confined to one row in SingleRow mode.
function sheetFrame(sys: ParticleSystem, seed: uint32, tN: float32, age: float32, speed: float32): float32 {
	const sheet: Borrow<TextureSheetAnimationModule> = sys.asset.textureSheetAnimation;
	const c: Borrow<CompiledCurves> = sys.curves;
	const rowOnly: boolean = sheet.animation == TextureSheetAnimationType.SingleRow;
	const frames: int32 = rowOnly ? sheet.numTilesX : sheet.numTilesX * sheet.numTilesY;
	const r: float32 = unitDraw(seed, DRAW_FRAME);
	const start: float32 = c.startFrame.evaluate(0.0, unitDraw(seed, DRAW_START_FRAME));
	const cycles: float32 = sheet.cycleCount > 0 ? sheet.cycleCount as float32 : 1.0;
	const progress: float32 = match (sheet.timeMode) {
		TextureSheetTimeMode.Lifetime => {
			const local: float32 = tN * cycles;
			return c.frameOverTime.evaluate(tN >= 1.0 ? 1.0 : fract(local), r);
		},
		TextureSheetTimeMode.Speed => within(sheet.speedRange, speed),
		TextureSheetTimeMode.FPS => fract(age * sheet.fps / (frames as float32)),
	};
	// A frame starts just after its boundary: tN 1/16 of a 16-frame sheet is still frame 0
	// (tests/unity/goldens/texture_sheet_4x4_wholesheet).
	let index: int32 = (Math.ceil(((start + progress) * (frames as float32)) as float64) as int32) - 1;
	if (index >= frames) { index = index % frames; }
	if (index < 0) { index = 0; }
	if (rowOnly) {
		const row: int32 = sheet.rowMode == TextureSheetRowMode.Random
			? (Math.floor((unitDraw(seed, DRAW_ROW) * (sheet.numTilesY as float32)) as float64) as int32)
			: sheet.rowIndex;
		index = index + row * sheet.numTilesX;
	}
	return index as float32;
}

function writeCustom(
	ref sys: ParticleSystem, i: int32, first: int32, stream: CustomDataStream,
	x: CompiledMinMaxCurve, y: CompiledMinMaxCurve, z: CompiledMinMaxCurve, w: CompiledMinMaxCurve,
	tN: float32, seed: uint32,
): void {
	if (stream.mode == CustomDataMode.Disabled) { return; }
	const r: float32 = unitDraw(seed, DRAW_CUSTOM);
	if (stream.mode == CustomDataMode.Color) {
		const color: ParticleColor = stream.color.evaluate(tN, r);
		put(sys, first, i, color.r);
		put(sys, first + 1, i, color.g);
		put(sys, first + 2, i, color.b);
		put(sys, first + 3, i, color.a);
		return;
	}
	put(sys, first, i, x.evaluate(tN, r));
	put(sys, first + 1, i, y.evaluate(tN, r));
	put(sys, first + 2, i, z.evaluate(tN, r));
	put(sys, first + 3, i, w.evaluate(tN, r));
}
