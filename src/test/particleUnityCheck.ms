import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { Vec3, vec3, Mat4, identity, translation } from "../math/math3d";
import {
	ParticleSystemAsset, ParticleEffect, SimulationSpace, RingBufferMode, EmitterVelocityMode,
	InheritVelocityMode, ShapeType, ShapeMultiModeValue, ColliderShape,
	TriggerAction, SubEmitterType, SubEmitterProperty, TextureSheetAnimationType,
} from "../particles/asset";
import {
	constantCurve, twoConstants, curveOf, linearCurve, key, constantColor, rgbaColor, gradientOf,
	Gradient, GradientMode, ParticleColorSpace,
} from "../particles/curve";
import {
	ParticleSystem, playSystem, updateSystem,
	POS_X, VEL_X, MOVE_X, AGE, LIFETIME, START_SIZE_X, SIZE_X, ROT_X, START_R, COLOR_R, FRAME,
} from "../particles/system";
import { EffectInstance, playEffect, updateEffect } from "../particles/effect";

// Each golden in tests/unity/goldens is read at test time and replayed through the Void
// simulation at the same dt, one step per frame. A case whose particles depend on Unity's RNG
// compares only what holds for any draw (counts, bounds, relations between a particle's own
// quantities) and says so in its name.

const GOLDEN_DIR: string = "tests/unity/goldens/";
const SEED: uint32 = 12345;
const TOL: float32 = 1e-4;
// The goldens store colours as Color32.
const COLOR_TOL: float32 = 1.0 / 255.0 + 1e-6;

const Q_COUNT: int32 = 0;
const Q_POS: int32 = 1;
const Q_VEL: int32 = 2;
const Q_TOTAL: int32 = 3;
const Q_SIZE: int32 = 4;
const Q_START_SIZE: int32 = 5;
const Q_ROT: int32 = 6;
const Q_COLOR: int32 = 7;
const Q_START_COLOR: int32 = 8;
const Q_REMAINING: int32 = 9;
const Q_FACT: int32 = 10;
const ALL: int32 = 0x3FE;
// Pair particles by remaining lifetime rather than by slot.
const SORT: int32 = 0x800;
const M_COUNT: int32 = 0x1;
const M_POS: int32 = 0x2;
const M_REMAINING: int32 = 0x200;
const M_FACT: int32 = 0x400;

let reported: int32 = 0;
let mismatches: int32 = 0;
let unexpected: int32 = 0;
// A case Void is known to disagree with Unity on lists what may differ: quantities, and frames
// (all of them when empty). Any other disagreement is unexpected and fails the case.
let allowedQuantities: int32 = 0;
let allowedFrames: Vec<int32> = [];

function begin(): void {
	reported = 0;
	mismatches = 0;
	unexpected = 0;
}

function expectOnly(quantities: int32, frames: Vec<int32>): void {
	allowedQuantities = quantities;
	allowedFrames = frames;
}

function allowed(q: int32, k: int32): boolean {
	if ((allowedQuantities & ((1 as int32) << q)) == 0) { return false; }
	if (allowedFrames.length == 0) { return true; }
	for (const f of allowedFrames) {
		if (f == k) { return true; }
	}
	return false;
}

// A pending case still disagrees, and only where it said it would. One that agrees fails, so the
// marker is deleted with the fix.
function diverges(found: int32): boolean {
	allowedQuantities = 0;
	allowedFrames = [];
	if (found == 0) {
		console.log("unity parity: this case agrees now, delete its pending marker");
		return false;
	}
	return unexpected == 0;
}

// Prints the first disagreement of each quantity of a case and counts all of them.
function fact(ok: boolean, label: string, k: int32, what: string): void {
	if (!ok) { disagree(Q_FACT, label, k, -1, what, 0.0, 1.0); }
}

function disagree(q: int32, label: string, k: int32, i: int32, what: string, unity: float64, actual: float64): void {
	mismatches = mismatches + 1;
	if (allowed(q, k)) { return; }
	unexpected = unexpected + 1;
	const bit: int32 = (1 as int32) << q;
	if ((reported & bit) != 0) { return; }
	reported = reported | bit;
	console.log(`unity parity: ${label} frame ${k} particle ${i} ${what}: unity ${unity}, void ${actual}`);
}

function agree(q: int32, label: string, k: int32, i: int32, what: string, unity: float64, actual: float32, tol: float32): void {
	const d: float64 = unity - (actual as float64);
	if (d > (tol as float64) || d < -(tol as float64) || d != d) { disagree(q, label, k, i, what, unity, actual as float64); }
}

function golden(name: string): JsonValue {
	const text = readFile(`${GOLDEN_DIR}${name}.json`);
	if (!text.ok) { unreachable; }
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) { unreachable; }
	return parsed.value;
}

function numberAt(v: JsonValue, k: int32): float64 {
	return v.at(k).asNumber();
}

function vecOf(v: JsonValue): Vec3 {
	return vec3(numberAt(v, 0) as float32, numberAt(v, 1) as float32, numberAt(v, 2) as float32);
}

function at(sys: ParticleSystem, c: int32, i: int32): float32 {
	return sys.data[c * sys.capacity + i];
}

function voidVec(sys: ParticleSystem, c: int32, i: int32): Vec3 {
	return vec3(at(sys, c, i), at(sys, c + 1, i), at(sys, c + 2, i));
}

function agreeVec3(q: int32, label: string, k: int32, i: int32, what: string, unity: JsonValue, sys: ParticleSystem, slot: int32, c: int32, tol: float32): void {
	for (let a = 0; a < 3; a++) {
		agree(q, label, k, i, `${what}[${a}]`, numberAt(unity, a), at(sys, c + a, slot), tol);
	}
}

// Unity's Particle.rotation3D is in degrees; Void integrates radians.
function agreeDegrees(label: string, k: int32, i: int32, unity: JsonValue, sys: ParticleSystem, slot: int32, tol: float32): void {
	for (let a = 0; a < 3; a++) {
		agree(Q_ROT, label, k, i, `rot[${a}]`, numberAt(unity, a) * 0.017453292519943295, at(sys, ROT_X + a, slot), tol);
	}
}

function agreeColor(q: int32, label: string, k: int32, i: int32, what: string, unity: JsonValue, sys: ParticleSystem, slot: int32, c: int32): void {
	for (let a = 0; a < 4; a++) {
		agree(q, label, k, i, `${what}[${a}]`, numberAt(unity, a), at(sys, c + a, slot), COLOR_TOL);
	}
}

// Indices 0..n-1 ordered by `key` descending, or as they are when `sort` is off. Unity swaps the
// last particle into a dead one's slot, Void slides the survivors down, so a case with deaths
// pairs particles by remaining lifetime instead of by slot.
function orderOf(keys: Vec<float32>, sort: boolean): Vec<int32> {
	let order: Vec<int32> = [];
	for (let i = 0; i < (keys.length as int32); i++) { order.push(i); }
	if (!sort) { return order; }
	for (let i = 1; i < (order.length as int32); i++) {
		const moving: int32 = order[i];
		let j: int32 = i - 1;
		while (j >= 0 && keys[order[j]] < keys[moving]) {
			order[j + 1] = order[j];
			j = j - 1;
		}
		order[j + 1] = moving;
	}
	return order;
}

// One golden frame's particles against the system's.
function compareFrame(label: string, sys: ParticleSystem, frame: JsonValue, k: int32, mask: int32, tol: float32): void {
	const expected: int32 = frame.getDynamicField("count").asNumber() as int32;
	if ((mask & ((1 as int32) << Q_COUNT)) != 0 && sys.count != expected) {
		disagree(Q_COUNT, label, k, -1, "count", expected as float64, sys.count as float64);
		return;
	}
	const parts = frame.getDynamicField("particles");
	const n: int32 = parts.length() as int32;
	const sort: boolean = (mask & SORT) != 0;
	let unityKeys: Vec<float32> = [];
	let voidKeys: Vec<float32> = [];
	for (let i = 0; i < n; i++) { unityKeys.push(parts.at(i).getDynamicField("remaining").asNumber() as float32); }
	for (let i = 0; i < sys.count; i++) { voidKeys.push(at(sys, LIFETIME, i) - at(sys, AGE, i)); }
	const unityOrder = orderOf(unityKeys, sort);
	const voidOrder = orderOf(voidKeys, sort);
	const shown: int32 = n < sys.count ? n : sys.count;
	for (let i = 0; i < shown; i++) {
		const u = parts.at(unityOrder[i]);
		const slot: int32 = voidOrder[i];
		if ((mask & ((1 as int32) << Q_POS)) != 0) { agreeVec3(Q_POS, label, k, i, "pos", u.getDynamicField("pos"), sys, slot, POS_X, tol); }
		if ((mask & ((1 as int32) << Q_VEL)) != 0) { agreeVec3(Q_VEL, label, k, i, "vel", u.getDynamicField("vel"), sys, slot, VEL_X, tol); }
		if ((mask & ((1 as int32) << Q_TOTAL)) != 0) { agreeVec3(Q_TOTAL, label, k, i, "total", u.getDynamicField("total"), sys, slot, MOVE_X, tol); }
		if ((mask & ((1 as int32) << Q_SIZE)) != 0) { agreeVec3(Q_SIZE, label, k, i, "size", u.getDynamicField("size"), sys, slot, SIZE_X, tol); }
		if ((mask & ((1 as int32) << Q_START_SIZE)) != 0) { agreeVec3(Q_START_SIZE, label, k, i, "startSize", u.getDynamicField("startSize"), sys, slot, START_SIZE_X, tol); }
		if ((mask & ((1 as int32) << Q_ROT)) != 0) { agreeDegrees(label, k, i, u.getDynamicField("rot"), sys, slot, tol); }
		if ((mask & ((1 as int32) << Q_COLOR)) != 0) { agreeColor(Q_COLOR, label, k, i, "color", u.getDynamicField("color"), sys, slot, COLOR_R); }
		if ((mask & ((1 as int32) << Q_START_COLOR)) != 0) { agreeColor(Q_START_COLOR, label, k, i, "startColor", u.getDynamicField("startColor"), sys, slot, START_R); }
		if ((mask & ((1 as int32) << Q_REMAINING)) != 0) {
			agree(Q_REMAINING, label, k, i, "remaining", u.getDynamicField("remaining").asNumber(), voidKeys[slot], tol);
		}
	}
}

// ---- the asset a capture builds ----

// ParticleCapture.Base: no shape, no gravity, white, size 1, local space, seed 12345.
function base(rate: float32, speed: float32, life: float32): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 5.0;
	a.main.loop = true;
	a.main.startLifetime = constantCurve(life);
	a.main.startSpeed = constantCurve(speed);
	a.main.maxParticles = 1000;
	a.emission.rateOverTime = constantCurve(rate);
	a.emission.bursts = [];
	a.shape.enabled = false;
	return a;
}

function oneBurst(a: ParticleSystemAsset): ParticleSystemAsset {
	let b = a;
	b.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	return b;
}

function burstsAt0(a: ParticleSystemAsset, count: float32): ParticleSystemAsset {
	let b = a;
	b.emission.bursts = [{ time: 0.0, count: constantCurve(count), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	return b;
}

// ---- running a golden ----

struct Place {
	origin: Vec3;
	// The emitter moves along +x by this much per second, set before each step.
	moveX: float32;
}

function stay(): Place {
	return { origin: vec3(0.0, 0.0, 0.0), moveX: 0.0 };
}

function worldAt(place: Place, k: int32, dt: float64): Mat4 {
	const t: float32 = place.moveX * (k as float32) * (dt as float32);
	return translation(place.origin.x + t, place.origin.y, place.origin.z);
}

// Unity splits a Simulate(dt) longer than Time.maximumParticleDeltaTime (0.03 s) into equal
// sub-steps, each its own simulation step; the harness drives Void the same way.
const MAX_PARTICLE_DT: float32 = 0.03;

function substeps(dt: float64): int32 {
	return Math.ceil(((dt as float32) / MAX_PARTICLE_DT) as float64) as int32;
}

// One sub-step in float32, as Unity divides it.
function substep(dt: float64): float64 {
	return ((dt as float32) / (substeps(dt) as float32)) as float64;
}

function started(asset: ParticleSystemAsset, dt: float64, place: Place): ParticleSystem {
	const made = ParticleSystem.create(asset, SEED);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = substep(dt);
	sys.clock.maxFrameTime = 1.0;
	playSystem(sys, worldAt(place, 0, dt));
	return sys;
}

function advance(ref sys: ParticleSystem, dt: float64, place: Place, k: int32): void {
	const n: int32 = substeps(dt);
	for (let s = 0; s < n; s++) {
		const done = updateSystem(sys, substep(dt), worldAt(place, k, dt));
		if (!done.ok) { unreachable; }
	}
}

function replay(name: string, asset: ParticleSystemAsset, place: Place, mask: int32, tol: float32): int32 {
	begin();
	const g = golden(name);
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	let sys = started(asset, dt, place);
	for (let k = 0; k < (frames.length() as int32); k++) {
		if (k > 0) { advance(sys, dt, place, k); }
		compareFrame(name, sys, frames.at(k), k, mask, tol);
	}
	return mismatches;
}

function sorted(name: string, asset: ParticleSystemAsset): int32 {
	return replay(name, asset, stay(), ALL | 1 | SORT, TOL);
}

function same(name: string, asset: ParticleSystemAsset): int32 {
	return replay(name, asset, stay(), ALL | 1, TOL);
}

// ---- emission ----

test "emission_rate10_dt60: the spawn at t = 0.1 lands in the next step, at age 0, as the float32 clock puts it" {
	assert same("emission_rate10_dt60", base(10.0, 1.0, 5.0)) == 0;
}

test "emission_rate7_dt100ms: the 14th spawn at t = 2.0 lands in the next step" {
	assert same("emission_rate7_dt100ms", base(7.0, 1.0, 10.0)) == 0;
}

test "burst_loop_t0: a burst of a later cycle starts at the sub-step that holds it" {
	let a = burstsAt0(base(0.0, 1.0, 10.0), 5.0);
	a.main.duration = 1.0;
	assert same("burst_loop_t0", a) == 0;
}

test "burst_cycles: the first burst is placed at its time, its repeats at the sub-step that holds them" {
	let a = base(0.0, 1.0, 10.0);
	a.main.duration = 2.0;
	a.main.loop = false;
	a.emission.bursts = [{ time: 0.1, count: constantCurve(2.0), cycleCount: 3, repeatInterval: 0.2, probability: 1.0 }];
	assert same("burst_cycles", a) == 0;
}

test "prewarm_rate10_life1 (pending, death tie): the particle that reaches remaining 0 at frame 12 is still alive" {
	let a = base(10.0, 1.0, 1.0);
	a.main.duration = 1.0;
	a.main.prewarm = true;
	expectOnly(M_COUNT, [12]);
	assert diverges(sorted("prewarm_rate10_life1", a));
}

test "ring_pause_until_replaced_max4 (pending, death tie): a replacement one frame early at frame 14" {
	let a = base(10.0, 1.0, 0.1);
	a.main.maxParticles = 4;
	a.main.ringBufferMode = RingBufferMode.PauseUntilReplaced;
	expectOnly(M_COUNT | M_POS | M_REMAINING, []);
	assert diverges(sorted("ring_pause_until_replaced_max4", a));
}

// ---- ties: a spawn or a death that lands exactly on a step end, captured as counts and remaining ----

const TIE_MASK: int32 = M_COUNT | M_REMAINING | SORT;

function tie(name: string, a: ParticleSystemAsset): int32 {
	return replay(name, a, stay(), TIE_MASK | 1, TOL);
}

function tieBurst(time: float32, cycles: int32, interval: float32): ParticleSystemAsset {
	let a = base(0.0, 0.0, 2.0);
	a.emission.bursts = [{ time: time, count: constantCurve(1.0), cycleCount: cycles, repeatInterval: interval, probability: 1.0 }];
	return a;
}

function tieDeath(name: string, life: float32): int32 {
	return tie(name, oneBurst(base(0.0, 0.0, life)));
}

test "tie_emission: a rate spawn on a step end follows the float32 carry of each sub-step" {
	assert tie("tie_emission_r10_hz60", base(10.0, 0.0, 2.0)) == 0;
	assert tie("tie_emission_r10_hz40", base(10.0, 0.0, 2.0)) == 0;
	assert tie("tie_emission_r10_hz10", base(10.0, 0.0, 2.0)) == 0;
	assert tie("tie_emission_r10_hz120", base(10.0, 0.0, 2.0)) == 0;
	assert tie("tie_emission_r25_hz50", base(25.0, 0.0, 2.0)) == 0;
	assert tie("tie_emission_r50_hz25", base(50.0, 0.0, 2.0)) == 0;
	assert tie("tie_emission_r13_hz144", base(13.0, 0.0, 2.0)) == 0;
}

test "tie_burst_t100: a burst at time 0.1 fires in the step with t0 <= 0.1 < t1" {
	for (const hz of ["10", "20", "40", "60", "100", "120", "144"]) {
		assert tie("tie_burst_t100_hz" + hz, tieBurst(0.1, 1, 0.01)) == 0;
	}
}

test "tie_burst_t300: a burst at time 0.3 fires in the step with t0 <= 0.3 < t1" {
	for (const hz of ["10", "20", "40", "60", "100", "120", "144"]) {
		assert tie("tie_burst_t300_hz" + hz, tieBurst(0.3, 1, 0.01)) == 0;
	}
}

test "tie_burst_inside: the first occurrence is placed at its time inside the step" {
	for (const hz of ["10", "20", "60"]) {
		assert tie("tie_burst_inside_hz" + hz, tieBurst(0.113, 1, 0.01)) == 0;
	}
}

test "tie_burst_repeat: a repeat starts at the sub-step that holds it" {
	for (const hz of ["10", "20", "60"]) {
		assert tie("tie_burst_repeat_hz" + hz, tieBurst(0.113, 4, 0.0733)) == 0;
	}
}

test "tie_wrap: a looping cycle wraps by subtraction and fires its burst at time 0" {
	for (const hz of ["10", "16", "40", "60"]) {
		let a = base(10.0, 0.0, 5.0);
		a.main.duration = 1.0;
		a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
		assert tie("tie_wrap_hz" + hz, a) == 0;
	}
}

test "tie_world_moved: a spawn of a moving emitter sits at the step end moved back by its velocity" {
	let a = base(10.0, 0.0, 2.0);
	a.main.simulationSpace = SimulationSpace.World;
	assert replay("tie_world_moved_hz60", a, { origin: vec3(0.0, 0.0, 0.0), moveX: 5.0 }, ALL | 1, TOL) == 0;
	assert replay("tie_world_moved_hz10", a, { origin: vec3(0.0, 0.0, 0.0), moveX: 5.0 }, ALL | 1, TOL) == 0;
}

function worldCustom(speed: float32, inherited: float32): ParticleSystemAsset {
	let a = base(10.0, speed, 2.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.main.emitterVelocityMode = EmitterVelocityMode.Custom;
	a.main.emitterVelocity = vec3(5.0, 0.0, 0.0);
	a.inheritVelocity.enabled = true;
	a.inheritVelocity.mode = InheritVelocityMode.Initial;
	a.inheritVelocity.curve = constantCurve(inherited);
	return a;
}

test "tie_world_custom: the inherited part of the velocity is integrated over the birth age" {
	assert same("tie_world_custom_speed1_hz60", worldCustom(1.0, 1.0)) == 0;
	assert same("tie_world_custom_half_hz60", worldCustom(0.0, 0.5)) == 0;
}

test "tie_death: a particle dies when its age passes its lifetime, one that reaches it exactly stays" {
	for (const hz of ["10", "20", "40", "60", "100", "120", "144"]) {
		if (hz != "60" && hz != "120") { assert tieDeath("tie_death_life100_hz" + hz, 0.1) == 0; }
		if (hz != "100") { assert tieDeath("tie_death_life300_hz" + hz, 0.3) == 0; }
		if (hz != "120") { assert tieDeath("tie_death_life1000_hz" + hz, 1.0) == 0; }
	}
}

test "tie_death_life100_hz60 (pending, death arithmetic): Unity's remaining time falls faster than the float32 chain" {
	expectOnly(M_COUNT, [6]);
	assert diverges(tieDeath("tie_death_life100_hz60", 0.1));
}

test "tie_death_life100_hz120 (pending, death arithmetic): Unity's remaining time falls faster than the float32 chain" {
	expectOnly(M_COUNT, [12]);
	assert diverges(tieDeath("tie_death_life100_hz120", 0.1));
}

test "tie_death_life300_hz100 (pending, death arithmetic): Unity's remaining time falls faster than the float32 chain" {
	expectOnly(M_COUNT, [30]);
	assert diverges(tieDeath("tie_death_life300_hz100", 0.3));
}

test "tie_death_life1000_hz120 (pending, death arithmetic): Unity's remaining time falls faster than the float32 chain" {
	expectOnly(M_COUNT, [120]);
	assert diverges(tieDeath("tie_death_life1000_hz120", 1.0));
}

// ---- burst probability: Unity draws from its own RNG and per frame ----

function bornOnOccurrence(born: float32, sub: float32): boolean {
	const behind: float32 = Math.ceil((born * 10.0 - 1e-3) as float64) as float32 / 10.0 - born;
	return behind >= -1e-3 && behind <= sub + 1e-3;
}

function burstProbability(name: string): int32 {
	begin();
	const g = golden(name);
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	let a = base(0.0, 1.0, 10.0);
	a.main.duration = 5.0;
	a.main.loop = false;
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 0, repeatInterval: 0.1, probability: 0.5 }];
	let sys = started(a, dt, stay());
	const last: int32 = (frames.length() as int32) - 1;
	for (let k = 1; k <= last; k++) { advance(sys, dt, stay(), k); }
	// 50 occurrences at probability 0.5: 25 +- 14 is four standard deviations of a binomial.
	const unity: int32 = frames.at(last).getDynamicField("count").asNumber() as int32;
	fact(unity >= 11 && unity <= 39, name, last, "unity count outside the binomial bounds");
	fact(sys.count >= 11 && sys.count <= 39, name, last, "void count outside the binomial bounds");
	// Every particle was born on an occurrence j * 0.1 s, or up to one sub-step before it: Unity
	// places a burst at the start of the sub-step that holds it. The end of the run is time 5.
	const sub: float32 = (dt / (substeps(dt) as float64)) as float32;
	for (let i = 0; i < sys.count; i++) {
		fact(bornOnOccurrence(at(sys, LIFETIME, i) - at(sys, AGE, i) - 5.0, sub), name, last, "void particle not born on an occurrence");
	}
	const parts = frames.at(last).getDynamicField("particles");
	for (let i = 0; i < (parts.length() as int32); i++) {
		fact(bornOnOccurrence(parts.at(i).getDynamicField("remaining").asNumber() as float32 - 5.0, sub), name, last, "unity particle not born on an occurrence");
	}
	return mismatches;
}

test "burst_probability_dt30: count within binomial bounds, born on occurrences (RNG, Unity draws per frame)" {
	assert burstProbability("burst_probability_dt30") == 0;
}

test "burst_probability_dt144: count within binomial bounds, born on occurrences (RNG, Unity draws per frame)" {
	assert burstProbability("burst_probability_dt144") == 0;
}

// ---- shape: a burst of 512 at dt 0.0001, so a particle sits one step past its spawn point ----

function shapeBurst(a: ParticleSystemAsset, count: float32): ParticleSystemAsset {
	let b = burstsAt0(a, count);
	b.shape.enabled = true;
	return b;
}

function burstPositions(name: string, asset: ParticleSystemAsset, ref dt: float64): Vec<Vec3> {
	const g = golden(name);
	dt = g.getDynamicField("dt").asNumber();
	let sys = started(asset, dt, stay());
	advance(sys, dt, stay(), 1);
	let out: Vec<Vec3> = [];
	for (let i = 0; i < sys.count; i++) {
		out.push(voidVec(sys, POS_X, i));
		out.push(voidVec(sys, VEL_X, i));
	}
	return out;
}

function unityBurst(name: string): Vec<Vec3> {
	const parts = golden(name).getDynamicField("frames").at(1).getDynamicField("particles");
	let out: Vec<Vec3> = [];
	for (let i = 0; i < (parts.length() as int32); i++) {
		out.push(vecOf(parts.at(i).getDynamicField("pos")));
		out.push(vecOf(parts.at(i).getDynamicField("vel")));
	}
	return out;
}

// The largest departure from a cone's rule: a particle left its base disc at the direction
// normalize(radial * (r / R) * tan(angle) + z), and a volume cone adds a distance along it.
function coneError(samples: Vec<Vec3>, dt: float32, radius: float32, angleDeg: float32, length: float32, volume: boolean): float32 {
	const spread: float32 = Math.tan((angleDeg * 0.017453292519943295) as float64) as float32;
	let worst: float32 = 0.0;
	for (let i = 0; i + 1 < (samples.length as int32); i += 2) {
		const vel: Vec3 = samples[i + 1];
		const shape: Vec3 = samples[i] - vel.scaled(dt);
		let origin: Vec3 = shape;
		if (volume) {
			const along: float32 = shape.z;
			origin = shape - vel.scaled(along / vel.z);
			if (along < -1e-4 || along > length + 1e-4) { worst = 1.0; }
			if (origin.z > 1e-4 || origin.z < -1e-4) { worst = 1.0; }
		}
		const r: float32 = Math.sqrt((origin.x * origin.x + origin.y * origin.y) as float64) as float32;
		if (r > radius * (1.0 + 1e-4)) { worst = 1.0; }
		let expected: Vec3 = vec3(0.0, 0.0, 1.0);
		if (r > 0.0) {
			const k: float32 = (r / radius) * spread / r;
			expected = vec3(origin.x * k, origin.y * k, 1.0).normalized();
		}
		const e: float32 = (expected - vel).length();
		if (e > worst) { worst = e; }
	}
	return worst;
}

// The largest departure from a sphere's rule: direction is the unit position, radius in [inner, 1].
function sphereError(samples: Vec<Vec3>, dt: float32, inner: float32): float32 {
	let worst: float32 = 0.0;
	for (let i = 0; i + 1 < (samples.length as int32); i += 2) {
		const vel: Vec3 = samples[i + 1];
		const shape: Vec3 = samples[i] - vel.scaled(dt);
		const r: float32 = shape.length();
		if (r < inner - 1e-4 || r > 1.0 + 1e-4) { worst = 1.0; }
		const e: float32 = (shape.scaled(1.0 / r) - vel).length();
		if (e > worst) { worst = e; }
	}
	return worst;
}

function coneAsset(radius: float32, angle: float32, volume: boolean): ParticleSystemAsset {
	let a = shapeBurst(base(0.0, 1.0, 5.0), 512.0);
	a.shape.shapeType = volume ? ShapeType.ConeVolume : ShapeType.Cone;
	a.shape.radius = radius;
	a.shape.angle = angle;
	a.shape.length = 5.0;
	return a;
}

function coneCase(name: string, radius: float32, angle: float32, volume: boolean): int32 {
	begin();
	let dt: float64 = 0.0;
	const mine = burstPositions(name, coneAsset(radius, angle, volume), dt);
	const theirs = unityBurst(name);
	fact((theirs.length as int32) == 1024 && (mine.length as int32) == 1024, name, 1, "particle count");
	fact(coneError(theirs, dt as float32, radius, angle, 5.0, volume) < 1e-5, name, 1, "unity breaks the cone rule");
	fact(coneError(mine, dt as float32, radius, angle, 5.0, volume) < 1e-5, name, 1, "void breaks the cone rule");
	return mismatches;
}

test "shape_cone_r0_a30_base: each particle leaves the base disc on the cone's direction rule (RNG: positions)" {
	assert coneCase("shape_cone_r0_a30_base", 0.0001, 30.0, false) == 0;
}

test "shape_cone_r1_a30_base: each particle leaves the base disc on the cone's direction rule (RNG: positions)" {
	assert coneCase("shape_cone_r1_a30_base", 1.0, 30.0, false) == 0;
}

test "shape_cone_r1_a30_volume: each particle sits 0 to 5 along the cone's direction (RNG: positions)" {
	assert coneCase("shape_cone_r1_a30_volume", 1.0, 30.0, true) == 0;
}

test "shape_sphere_thickness05: direction is the unit position, radius in [0.5, 1] (RNG: positions)" {
	begin();
	let a = shapeBurst(base(0.0, 1.0, 5.0), 512.0);
	a.shape.shapeType = ShapeType.Sphere;
	a.shape.radius = 1.0;
	a.shape.radiusThickness = 0.5;
	let dt: float64 = 0.0;
	const mine = burstPositions("shape_sphere_thickness05", a, dt);
	const theirs = unityBurst("shape_sphere_thickness05");
	fact((theirs.length as int32) == 1024 && (mine.length as int32) == 1024, "shape_sphere_thickness05", 1, "particle count");
	fact(sphereError(theirs, dt as float32, 0.5) < 1e-5, "shape_sphere_thickness05", 1, "unity breaks the sphere rule");
	fact(sphereError(mine, dt as float32, 0.5) < 1e-5, "shape_sphere_thickness05", 1, "void breaks the sphere rule");
	assert mismatches == 0;
}

function circleBurst(arc: float32): ParticleSystemAsset {
	let a = shapeBurst(base(0.0, 1.0, 5.0), 4.0);
	a.shape.shapeType = ShapeType.Circle;
	a.shape.radius = 1.0;
	a.shape.radiusThickness = 0.0;
	a.shape.arc = arc;
	a.shape.arcMode = ShapeMultiModeValue.BurstSpread;
	return a;
}

test "shape_circle_arc180_burstspread4: four particles spread over half a circle" {
	assert same("shape_circle_arc180_burstspread4", circleBurst(180.0)) == 0;
}

test "shape_circle_arc360_burstspread4: four particles spread over a full circle" {
	assert same("shape_circle_arc360_burstspread4", circleBurst(360.0)) == 0;
}

test "shape_circle_loop_speed1: spawns on a step end land in the next step" {
	let a = base(10.0, 1.0, 10.0);
	a.shape.enabled = true;
	a.shape.shapeType = ShapeType.Circle;
	a.shape.radius = 1.0;
	a.shape.radiusThickness = 0.0;
	a.shape.arc = 360.0;
	a.shape.arcMode = ShapeMultiModeValue.Loop;
	a.shape.arcSpeed = constantCurve(1.0);
	assert same("shape_circle_loop_speed1", a) == 0;
}

// ---- velocity over lifetime, limit, drag ----

function volCase(name: string, speed: float32, gravity: float32, linearX: float32, modifier: float32): int32 {
	let a = oneBurst(base(0.0, speed, 5.0));
	a.main.gravityModifier = constantCurve(gravity);
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.x = constantCurve(linearX);
	a.velocityOverLifetime.speedModifier = constantCurve(modifier);
	return same(name, a);
}

test "vol_speedmod05_gravity: speed modifier 0.5 scales the displacement, not the stored velocity" {
	assert volCase("vol_speedmod05_gravity", 2.0, 1.0, 0.0, 0.5) == 0;
}

test "vol_speedmod1_gravity: speed modifier 1 leaves gravity alone" {
	assert volCase("vol_speedmod1_gravity", 2.0, 1.0, 0.0, 1.0) == 0;
}

test "vol_speedmod05_linearx1: speed modifier 0.5 scales a linear velocity" {
	assert volCase("vol_speedmod05_linearx1", 0.0, 0.0, 1.0, 0.5) == 0;
}

test "vol_orbitalz_2pi: a particle at (1,0,0) orbits z at 2 pi rad/s" {
	let a = oneBurst(base(0.0, 0.0, 5.0));
	a.shape.enabled = true;
	a.shape.shapeType = ShapeType.Box;
	a.shape.scale = vec3(1e-6, 1e-6, 1e-6);
	a.shape.position = vec3(1.0, 0.0, 0.0);
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.orbitalZ = constantCurve(6.2831853);
	assert same("vol_orbitalz_2pi", a) == 0;
}

function limitCase(name: string): int32 {
	let a = oneBurst(base(0.0, 10.0, 5.0));
	a.limitVelocityOverLifetime.enabled = true;
	a.limitVelocityOverLifetime.limit = constantCurve(5.0);
	a.limitVelocityOverLifetime.dampen = 0.5;
	a.limitVelocityOverLifetime.drag = constantCurve(0.0);
	return same(name, a);
}

test "limit_velocity_dampen05_dt60: the excess halves every 1/30 s" {
	assert limitCase("limit_velocity_dampen05_dt60") == 0;
}

test "limit_velocity_dampen05_dt30: the excess halves every 1/30 s at a 1/30 s step" {
	assert limitCase("limit_velocity_dampen05_dt30") == 0;
}

function dragCase(name: string, bySize: boolean, byVelocity: boolean): int32 {
	let a = oneBurst(base(0.0, 10.0, 5.0));
	a.main.startSizeX = constantCurve(2.0);
	a.limitVelocityOverLifetime.enabled = true;
	a.limitVelocityOverLifetime.limit = constantCurve(100000.0);
	a.limitVelocityOverLifetime.dampen = 0.0;
	a.limitVelocityOverLifetime.drag = constantCurve(1.0);
	a.limitVelocityOverLifetime.multiplyDragByParticleSize = bySize;
	a.limitVelocityOverLifetime.multiplyDragByParticleVelocity = byVelocity;
	return same(name, a);
}

test "drag1_size2_speed10: drag 1 takes a fixed amount off the speed" {
	assert dragCase("drag1_size2_speed10", false, false) == 0;
}

test "drag1_size2_speed10_bySize: drag scales with the particle's cross-section" {
	assert dragCase("drag1_size2_speed10_bySize", true, false) == 0;
}

test "drag1_size2_speed10_byVelocity: drag scales with the speed squared" {
	assert dragCase("drag1_size2_speed10_byVelocity", false, true) == 0;
}

test "drag1_size2_speed10_bySize_byVelocity: drag scales with both" {
	assert dragCase("drag1_size2_speed10_bySize_byVelocity", true, true) == 0;
}

// ---- force over lifetime: TwoConstants(-1, 1) is a per-particle draw, so only its shape is compared ----

function forceVelocities(sys: ParticleSystem, ref out: Vec<float32>, ref bad: boolean): void {
	for (let i = 0; i < 4; i++) {
		out.push(at(sys, VEL_X, i));
		if (at(sys, VEL_X + 1, i) != 0.0 || at(sys, VEL_X + 2, i) != 0.0) { bad = true; }
	}
}

// Frames 1 to 30 of 4 particles: fixed means one acceleration per particle for good, randomized
// means a new one every step, and either way each lies in [-1, 1].
function forceFacts(label: string, series: Vec<float32>, frames: int32, dt: float32, randomized: boolean, who: string): void {
	let steady: boolean = true;
	let inRange: boolean = true;
	let firsts: Vec<float32> = [];
	for (let i = 0; i < 4; i++) {
		const first: float32 = (series[4 + i] - series[i]) / dt;
		firsts.push(first);
		let low: float32 = first;
		let high: float32 = first;
		for (let k = 0; k + 1 < frames; k++) {
			const a: float32 = (series[(k + 1) * 4 + i] - series[k * 4 + i]) / dt;
			if (a < low) { low = a; }
			if (a > high) { high = a; }
			if (a > 1.001 || a < -1.001) { inRange = false; }
		}
		if (high - low > 5e-3) { steady = false; }
	}
	fact(inRange, label, 1, `${who} acceleration outside [-1, 1]`);
	fact(randomized ? !steady : steady, label, 1, `${who} acceleration ${randomized ? "does not change per step" : "changes per step"}`);
	let distinct: boolean = false;
	for (let i = 1; i < 4; i++) {
		if (firsts[i] - firsts[0] > 1e-3 || firsts[0] - firsts[i] > 1e-3) { distinct = true; }
	}
	fact(distinct, label, 1, `${who} particles draw the same acceleration`);
}

function forceCase(name: string, randomized: boolean): int32 {
	begin();
	let a = burstsAt0(base(0.0, 0.0, 5.0), 4.0);
	a.forceOverLifetime.enabled = true;
	a.forceOverLifetime.x = twoConstants(-1.0, 1.0);
	a.forceOverLifetime.randomized = randomized;
	const g = golden(name);
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	let sys = started(a, dt, stay());
	let mine: Vec<float32> = [];
	let theirs: Vec<float32> = [];
	let bad: boolean = false;
	let badUnity: boolean = false;
	const last: int32 = (frames.length() as int32) - 1;
	for (let k = 1; k <= last; k++) {
		advance(sys, dt, stay(), k);
		forceVelocities(sys, mine, bad);
		const parts = frames.at(k).getDynamicField("particles");
		for (let i = 0; i < 4; i++) {
			const v = vecOf(parts.at(i).getDynamicField("vel"));
			theirs.push(v.x);
			if (v.y != 0.0 || v.z != 0.0) { badUnity = true; }
		}
	}
	fact(!bad && !badUnity, name, 1, "velocity left the x axis");
	forceFacts(name, mine, last, dt as float32, randomized, "void");
	forceFacts(name, theirs, last, dt as float32, randomized, "unity");
	return mismatches;
}

test "force_twoconstants_fixed: one acceleration in [-1, 1] per particle for its life (RNG: the draw)" {
	assert forceCase("force_twoconstants_fixed", false) == 0;
}

test "force_twoconstants_randomized: a new acceleration in [-1, 1] every step (RNG: the draw)" {
	assert forceCase("force_twoconstants_randomized", true) == 0;
}

test "gravity_modifier_curve: the modifier rises with the system's time over a 2 s duration" {
	let a = base(0.0, 0.0, 5.0);
	a.main.duration = 2.0;
	a.main.loop = false;
	a.main.gravityModifier = curveOf(1.0, linearCurve([key(0.0, 0.0), key(1.0, 1.0)]));
	a.emission.bursts = [
		{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 },
		{ time: 0.5, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 },
	];
	assert same("gravity_modifier_curve", a) == 0;
}

// ---- collision and trigger ----

function collisionCase(name: string, bounce: float32, dampen: float32, loss: float32, minKill: float32): int32 {
	let a = oneBurst(base(0.0, 1.0, 5.0));
	a.main.simulationSpace = SimulationSpace.World;
	a.main.gravityModifier = constantCurve(1.0);
	a.main.startSizeX = constantCurve(0.02);
	a.collision.enabled = true;
	a.collision.planes = [{ point: vec3(0.0, 0.0, 0.0), normal: vec3(0.0, 1.0, 0.0) }];
	a.collision.bounce = constantCurve(bounce);
	a.collision.dampen = constantCurve(dampen);
	a.collision.lifetimeLoss = constantCurve(loss);
	a.collision.minKillSpeed = minKill;
	a.collision.radiusScale = 1.0;
	return replay(name, a, { origin: vec3(0.0, 1.0, 0.0), moveX: 0.0 }, ALL | 1, TOL);
}

test "collision_plane_bounce05_dampen025_loss02: a particle bounces off a plane" {
	assert collisionCase("collision_plane_bounce05_dampen025_loss02", 0.5, 0.25, 0.2, 0.0) == 0;
}

test "collision_plane_minkill3: a particle slower than 3 on impact is killed" {
	assert collisionCase("collision_plane_minkill3", 0.5, 0.0, 0.0, 3.0) == 0;
}

function triggerCase(name: string, event: string): int32 {
	let a = oneBurst(base(0.0, 1.0, 5.0));
	a.main.simulationSpace = SimulationSpace.World;
	a.main.startSizeX = constantCurve(0.01);
	a.trigger.enabled = true;
	a.trigger.colliders = [{
		shape: ColliderShape.Sphere, center: vec3(0.0, 0.0, 0.0), extents: vec3(0.0, 0.0, 0.0),
		end: vec3(0.0, 0.0, 0.0), radius: 1.0, layer: 0,
	}];
	a.trigger.radiusScale = 1.0;
	a.trigger.enter = event.equals("enter") ? TriggerAction.Kill : TriggerAction.Ignore;
	a.trigger.inside = event.equals("inside") ? TriggerAction.Kill : TriggerAction.Ignore;
	a.trigger.exit = event.equals("exit") ? TriggerAction.Kill : TriggerAction.Ignore;
	a.trigger.outside = event.equals("outside") ? TriggerAction.Kill : TriggerAction.Ignore;
	return same(name, a);
}

test "trigger_enter_kill: a particle born inside a sphere enters it" {
	assert triggerCase("trigger_enter_kill", "enter") == 0;
}

test "trigger_inside_kill: a particle inside a sphere is killed" {
	assert triggerCase("trigger_inside_kill", "inside") == 0;
}

test "trigger_exit_kill: a particle leaving a sphere is killed" {
	assert triggerCase("trigger_exit_kill", "exit") == 0;
}

test "trigger_outside_kill: a particle outside a sphere is killed" {
	assert triggerCase("trigger_outside_kill", "outside") == 0;
}

// ---- appearance ----

test "size_over_lifetime_linear: size rises from 0 to the start size over the life" {
	let a = oneBurst(base(0.0, 0.0, 1.0));
	a.main.startSizeX = constantCurve(2.0);
	a.sizeOverLifetime.enabled = true;
	a.sizeOverLifetime.x = curveOf(1.0, linearCurve([key(0.0, 0.0), key(1.0, 1.0)]));
	assert same("size_over_lifetime_linear", a) == 0;
}

test "rotation_over_lifetime_90dps: rotation integrates 90 degrees a second" {
	let a = oneBurst(base(0.0, 0.0, 5.0));
	a.rotationOverLifetime.enabled = true;
	a.rotationOverLifetime.z = constantCurve(90.0 * 0.017453292519943295);
	assert same("rotation_over_lifetime_90dps", a) == 0;
}

function redToGreen(space: ParticleColorSpace): Gradient {
	return {
		colorKeys: [{ color: rgbaColor(1.0, 0.0, 0.0, 1.0), time: 0.0 }, { color: rgbaColor(0.0, 1.0, 0.0, 1.0), time: 1.0 }],
		alphaKeys: [{ alpha: 1.0, time: 0.0 }, { alpha: 1.0, time: 1.0 }],
		mode: GradientMode.Blend,
		colorSpace: space,
	};
}

function spaceOf(name: string): ParticleColorSpace {
	const word = golden(name).getDynamicField("settings").getDynamicField("gradientColorSpace").asString();
	return word.equals("Linear") ? ParticleColorSpace.Linear : ParticleColorSpace.Gamma;
}

function colorCase(name: string): int32 {
	let a = oneBurst(base(0.0, 0.0, 1.0));
	a.colorOverLifetime.enabled = true;
	a.colorOverLifetime.color = gradientOf(redToGreen(spaceOf(name)));
	return same(name, a);
}

test "color_over_lifetime_gamma: a red to green gradient blends in gamma space" {
	assert colorCase("color_over_lifetime_gamma") == 0;
}

test "color_over_lifetime_linear: the same gradient blends in linear space" {
	assert colorCase("color_over_lifetime_linear") == 0;
}

test "texture_sheet_4x4_wholesheet (pending, frame tie and death tie): the frame at age 6/16 to 8/16 reads one tile low in Unity, and the particle dies a frame early" {
	begin();
	expectOnly(M_FACT | M_COUNT, [6, 7, 8, 16]);
	let a = oneBurst(base(0.0, 0.0, 1.0));
	a.textureSheetAnimation.enabled = true;
	a.textureSheetAnimation.numTilesX = 4;
	a.textureSheetAnimation.numTilesY = 4;
	a.textureSheetAnimation.animation = TextureSheetAnimationType.WholeSheet;
	const g = golden("texture_sheet_4x4_wholesheet");
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	let sys = started(a, dt, stay());
	for (let k = 0; k < (frames.length() as int32); k++) {
		if (k > 0) { advance(sys, dt, stay(), k); }
		const f = frames.at(k);
		const expected: int32 = f.getDynamicField("count").asNumber() as int32;
		if (sys.count != expected) {
			disagree(Q_COUNT, "texture_sheet", k, -1, "count", expected as float64, sys.count as float64);
			continue;
		}
		if (expected == 1) {
			// The baked quad's min corner: u is the column over 4, v counts rows up from the bottom.
			const corner = f.getDynamicField("bakedQuadUVMin").at(0);
			const column: int32 = Math.round(numberAt(corner, 0) * 4.0) as int32;
			const row: int32 = 3 - (Math.round(numberAt(corner, 1) * 4.0) as int32);
			agree(Q_FACT, "texture_sheet", k, 0, "frame", (row * 4 + column) as float64, at(sys, FRAME, 0), 0.0);
		}
	}
	assert diverges(mismatches);
}

// ---- inherit velocity ----

test "inherit_velocity_initial_transform: the spawn at t = 0.1 lands in the next step" {
	let a = base(10.0, 0.0, 5.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.inheritVelocity.enabled = true;
	a.inheritVelocity.mode = InheritVelocityMode.Initial;
	a.inheritVelocity.curve = constantCurve(1.0);
	assert replay("inherit_velocity_initial_transform", a, { origin: vec3(0.0, 0.0, 0.0), moveX: 5.0 }, ALL | 1, TOL) == 0;
}

test "inherit_velocity_initial_custom: a spawn is placed at the step end moved back by the emitter velocity, the inherited part included" {
	let a = base(10.0, 0.0, 5.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.main.emitterVelocityMode = EmitterVelocityMode.Custom;
	a.main.emitterVelocity = vec3(5.0, 0.0, 0.0);
	a.inheritVelocity.enabled = true;
	a.inheritVelocity.mode = InheritVelocityMode.Initial;
	a.inheritVelocity.curve = constantCurve(1.0);
	assert same("inherit_velocity_initial_custom", a) == 0;
}

// ---- noise: Void's field is Godot's curl by design, so only what the damping switch changes ----

function noiseMean(damping: boolean, name: string): float32 {
	let a = burstsAt0(base(0.0, 0.0, 5.0), 64.0);
	a.shape.enabled = true;
	a.shape.shapeType = ShapeType.Sphere;
	a.shape.radius = 5.0;
	a.noise.enabled = true;
	a.noise.frequency = 0.5;
	a.noise.damping = damping;
	a.noise.scrollSpeed = constantCurve(0.0);
	const dt: float64 = golden(name).getDynamicField("dt").asNumber();
	let sys = started(a, dt, stay());
	advance(sys, dt, stay(), 1);
	fact(sys.count == 64, name, 1, "count");
	let sum: float32 = 0.0;
	for (let i = 0; i < sys.count; i++) { sum = sum + (voidVec(sys, MOVE_X, i) - voidVec(sys, VEL_X, i)).length(); }
	return sum / (sys.count as float32);
}

test "noise_strength1_freq05: damping at frequency 0.5 doubles the animated speed (Void's field differs by design)" {
	begin();
	const damped = noiseMean(true, "noise_strength1_freq05_damped");
	const undamped = noiseMean(false, "noise_strength1_freq05_undamped");
	const unityDamped: float64 = golden("noise_strength1_freq05_damped").getDynamicField("frames").at(1).getDynamicField("animSpeedMean").asNumber();
	const unityUndamped: float64 = golden("noise_strength1_freq05_undamped").getDynamicField("frames").at(1).getDynamicField("animSpeedMean").asNumber();
	agree(Q_FACT, "noise", 1, 0, "damped / undamped mean animated speed", unityDamped / unityUndamped, damped / undamped, 1e-3);
	assert mismatches == 0;
}

// ---- sub-emitters ----

function parentAsset(kind: SubEmitterType): ParticleSystemAsset {
	let a = oneBurst(base(0.0, 1.0, 0.5));
	a.main.simulationSpace = SimulationSpace.World;
	a.main.startColor = constantColor(rgbaColor(1.0, 0.5, 0.25, 1.0));
	a.main.startSizeX = constantCurve(2.0);
	a.subEmitters.enabled = true;
	a.subEmitters.subEmitters = [{
		system: 1, subEmitterType: kind,
		properties: SubEmitterProperty.InheritColor | SubEmitterProperty.InheritSize, emitProbability: 1.0,
	}];
	return a;
}

function childAsset(): ParticleSystemAsset {
	let a = burstsAt0(base(0.0, 0.0, 5.0), 3.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.main.startColor = constantColor(rgbaColor(0.5, 1.0, 1.0, 1.0));
	a.main.startSizeX = constantCurve(0.5);
	return a;
}

function subEmitterCase(name: string, kind: SubEmitterType): int32 {
	begin();
	const g = golden(name);
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	const effect: ParticleEffect = { systems: [parentAsset(kind), childAsset()] };
	const made = EffectInstance.create(effect, SEED);
	if (!made.ok) { unreachable; }
	let fx = made.value;
	const n: int32 = substeps(dt);
	fx.clock.fixedStep = dt / (n as float64);
	fx.clock.maxFrameTime = 1.0;
	playEffect(fx, identity());
	for (let k = 0; k < (frames.length() as int32); k++) {
		if (k > 0) {
			for (let sub = 0; sub < n; sub++) {
				const done = updateEffect(fx, dt / (n as float64), identity());
				if (!done.ok) { unreachable; }
			}
		}
		compareFrame(`${name} parent`, fx.systems[0], frames.at(k), k, ALL | 1, TOL);
		compareFrame(`${name} child`, fx.systems[1], frames.at(k).getDynamicField("children").at(0), k, ALL | 1, TOL);
	}
	return mismatches;
}

test "subemitter_birth: a Birth sub-emitter bursts its 3 children as the parent is born" {
	assert subEmitterCase("subemitter_birth", SubEmitterType.Birth) == 0;
}

test "subemitter_death: a Death sub-emitter bursts its 3 children where the parent died" {
	assert subEmitterCase("subemitter_death", SubEmitterType.Death) == 0;
}

test "subemitter_death_linear: the same under a linear colour space" {
	assert subEmitterCase("subemitter_death_linear", SubEmitterType.Death) == 0;
}

// ---- stretched and aligned billboards: the state the 2D writer reads ----

function drifting(vx: float32, vy: float32): ParticleSystemAsset {
	let a = oneBurst(base(0.0, 0.0, 5.0));
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.x = constantCurve(vx);
	a.velocityOverLifetime.y = constantCurve(vy);
	a.velocityOverLifetime.z = constantCurve(0.0);
	return a;
}

test "stretch_ls1_vs0: velocityOverLifetime is animated velocity, so stored velocity stays zero and total holds it" {
	assert same("stretch_ls1_vs0", drifting(3.0, 4.0)) == 0;
}

test "stretch_size2_rot45_total: totalVelocity is the stored force velocity plus the animated drift" {
	let a = drifting(3.0, 0.0);
	a.main.startSizeX = constantCurve(2.0);
	a.main.startRotationZ = constantCurve(45.0 * 0.017453292519943295);
	a.forceOverLifetime.enabled = true;
	a.forceOverLifetime.y = constantCurve(4.0);
	assert same("stretch_size2_rot45_total", a) == 0;
}
