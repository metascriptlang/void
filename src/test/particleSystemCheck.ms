import { Vec3, vec3, identity, translation } from "../math/math3d";
import { ParticleSystemAsset, RingBufferMode, SimulationSpace } from "../particles/asset";
import { constantCurve, twoConstants } from "../particles/curve";
import {
	ParticleSystem, ParticleSystemError, playSystem, stopSystem, updateSystem,
	POS_X, POS_Y, POS_Z, MOVE_X, MOVE_Y, MOVE_Z, AGE, PARTICLE_COLUMNS,
} from "../particles/system";

const TWO_PI: float32 = 6.283185307179586;

function near(a: float32, b: float32, tol: float32): boolean {
	const d: float32 = a - b;
	return d < tol && d > -tol;
}

// A still system: long lives, no speed, no shape spread, no gravity.
function quiet(): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.startLifetime = constantCurve(100.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.duration = 100.0;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	return a;
}

function started(asset: ParticleSystemAsset, step: float64): ParticleSystem {
	const made = ParticleSystem.create(asset, 7);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.fixedStep = step;
	sys.maxFrameTime = 1.0;
	playSystem(sys, identity());
	return sys;
}

function run(ref sys: ParticleSystem, frame: float64, frames: int32): void {
	for (let k = 0; k < frames; k++) {
		const done = updateSystem(sys, frame, identity());
		if (!done.ok) { unreachable; }
	}
}

function speedOf(sys: ParticleSystem, i: int32): float32 {
	const cap: int32 = sys.capacity;
	return vec3(sys.data[MOVE_X * cap + i], sys.data[MOVE_Y * cap + i], sys.data[MOVE_Z * cap + i]).length();
}

function positionOf(sys: ParticleSystem, i: int32): Vec3 {
	const cap: int32 = sys.capacity;
	return vec3(sys.data[POS_X * cap + i], sys.data[POS_Y * cap + i], sys.data[POS_Z * cap + i]);
}

test "rate 10 at 60 steps a second spawns once every sixth step" {
	let a = quiet();
	a.emission.rateOverTime = constantCurve(10.0);
	let sys = started(a, 1.0 / 60.0);
	let firsts: Vec<int32> = [];
	for (let k = 1; k <= 60; k++) {
		const before: uint32 = sys.spawned;
		run(sys, 1.0 / 60.0, 1);
		if (sys.spawned != before) { firsts.push(k); }
	}
	assert sys.spawned == 10;
	assert firsts[0] >= 5 && firsts[0] <= 7;
}

test "a fractional rate carries its remainder: rate 7 at 0.1 s steps" {
	let a = quiet();
	a.emission.rateOverTime = constantCurve(7.0);
	let sys = started(a, 0.1);
	for (let k = 1; k <= 9; k++) {
		run(sys, 0.1, 1);
		const expected: uint32 = Math.floor((k as float64) * 0.7 + 1e-9) as uint32;
		assert sys.spawned == expected;
	}
}

test "a burst at 0 fires on every loop, split across the wrap" {
	let a = quiet();
	a.main.duration = 1.0;
	a.emission.bursts = [{ time: 0.0, count: constantCurve(5.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	let sys = started(a, 0.3);
	let spawnedAt: Vec<uint32> = [];
	for (let k = 0; k < 9; k++) {
		run(sys, 0.3, 1);
		spawnedAt.push(sys.spawned);
	}
	assert sys.spawned == 15;
	assert spawnedAt[0] == 5 && spawnedAt[2] == 5 && spawnedAt[3] == 10 && spawnedAt[6] == 15;
}

test "burst probability is keyed on the occurrence, not the frame rate" {
	let a = quiet();
	a.main.duration = 1.0;
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 0, repeatInterval: 0.125, probability: 0.5 }];
	let coarse = started(a, 1.0 / 32.0);
	run(coarse, 1.0 / 32.0, 64);
	let fine = started(a, 1.0 / 32.0);
	run(fine, 1.0 / 128.0, 256);
	assert coarse.spawned == fine.spawned;
	assert coarse.spawned > 2 && coarse.spawned < 14;
}

function oneShot(speed: float32): ParticleSystemAsset {
	let a = quiet();
	a.main.startSpeed = constantCurve(speed);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	return a;
}

// tests/unity/goldens/limit_velocity_dampen05_dt60: the excess halves every 1/30 s.
test "limit dampen decays the excess by (1 - dampen) per 1/30 s: 8.536, 7.5, 6.768" {
	let a = oneShot(10.0);
	a.limitVelocityOverLifetime.enabled = true;
	a.limitVelocityOverLifetime.limit = constantCurve(5.0);
	a.limitVelocityOverLifetime.dampen = 0.5;
	let sys = started(a, 1.0 / 60.0);
	run(sys, 1.0 / 60.0, 1);
	assert near(speedOf(sys, 0), 8.535534, 1e-4);
	run(sys, 1.0 / 60.0, 1);
	assert near(speedOf(sys, 0), 7.5, 1e-4);
	run(sys, 1.0 / 60.0, 1);
	assert near(speedOf(sys, 0), 6.767767, 1e-4);
}

// tests/unity/goldens/drag1_size2_speed10: drag 1 takes 1 unit/s off the speed.
test "drag takes a fixed amount off the speed" {
	let a = oneShot(10.0);
	a.limitVelocityOverLifetime.enabled = true;
	a.limitVelocityOverLifetime.limit = constantCurve(1000000.0);
	a.limitVelocityOverLifetime.drag = constantCurve(1.0);
	a.limitVelocityOverLifetime.multiplyDragByParticleSize = false;
	a.limitVelocityOverLifetime.multiplyDragByParticleVelocity = false;
	let sys = started(a, 1.0 / 60.0);
	run(sys, 1.0 / 60.0, 60);
	assert near(speedOf(sys, 0), 9.0, 1e-3);
}

test "an orbit turns exactly: one revolution a second returns to the start at radius 1" {
	let a = oneShot(0.0);
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.orbitalZ = constantCurve(TWO_PI);
	a.velocityOverLifetime.orbitalOffsetX = constantCurve(-1.0);
	let sys = started(a, 1.0 / 60.0);
	for (let k = 0; k < 60; k++) {
		run(sys, 1.0 / 60.0, 1);
		const p: Vec3 = positionOf(sys, 0);
		assert near((p - vec3(-1.0, 0.0, 0.0)).length(), 1.0, 1e-4);
	}
	assert positionOf(sys, 0).length() < 1e-3;
}

function busy(): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.startLifetime = twoConstants(0.5, 1.5);
	a.main.startSpeed = twoConstants(1.0, 4.0);
	a.main.gravityModifier = constantCurve(0.5);
	a.emission.rateOverTime = constantCurve(37.0);
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.x = twoConstants(-1.0, 1.0);
	a.velocityOverLifetime.orbitalY = constantCurve(2.0);
	a.limitVelocityOverLifetime.enabled = true;
	a.limitVelocityOverLifetime.limit = constantCurve(3.0);
	a.limitVelocityOverLifetime.dampen = 0.3;
	a.forceOverLifetime.enabled = true;
	a.forceOverLifetime.x = twoConstants(-2.0, 2.0);
	a.forceOverLifetime.randomized = true;
	a.sizeOverLifetime.enabled = true;
	a.rotationOverLifetime.enabled = true;
	return a;
}

test "the same asset gives byte-equal columns at 32 and 128 frames a second" {
	let coarse = started(busy(), 1.0 / 64.0);
	run(coarse, 1.0 / 32.0, 64);
	let fine = started(busy(), 1.0 / 64.0);
	run(fine, 1.0 / 128.0, 256);
	assert coarse.stepIndex == fine.stepIndex;
	assert coarse.count == fine.count && coarse.count > 20;
	for (let c = 0; c < PARTICLE_COLUMNS; c++) {
		for (let i = 0; i < coarse.count; i++) {
			assert coarse.data[c * coarse.capacity + i] == fine.data[c * fine.capacity + i];
		}
	}
}

test "rate spawns inside one step get their own ages" {
	let a = quiet();
	a.main.startSpeed = constantCurve(1.0);
	a.emission.rateOverTime = constantCurve(60.0);
	let sys = started(a, 0.1);
	run(sys, 0.1, 1);
	assert sys.count == 6;
	for (let i = 0; i < 6; i++) {
		const age: float32 = sys.data[AGE * sys.capacity + i];
		assert age >= 0.0 && age <= 0.1 + 1e-6;
		if (i > 0) { assert age < sys.data[AGE * sys.capacity + i - 1]; }
	}
}

test "prewarm shows a full loop at the first frame" {
	let a = quiet();
	a.main.duration = 1.0;
	a.main.prewarm = true;
	a.main.startLifetime = constantCurve(1.0);
	a.emission.rateOverTime = constantCurve(10.0);
	const sys = started(a, 1.0 / 30.0);
	assert sys.count >= 9 && sys.count <= 10;
}

test "prewarm without loop, or with a start delay, is refused" {
	let a = quiet();
	a.main.prewarm = true;
	a.main.loop = false;
	const noLoop = ParticleSystem.create(a, 1);
	assert !noLoop.ok;
	if (!noLoop.ok) { assert noLoop.error == ParticleSystemError.PrewarmNeedsLoop; }
	a.main.loop = true;
	a.main.startDelay = constantCurve(1.0);
	const delayed = ParticleSystem.create(a, 1);
	assert !delayed.ok;
}

test "the cap drops extra spawns; a ring buffer keeps the cap full of frozen particles" {
	let a = quiet();
	a.main.maxParticles = 4;
	a.main.startLifetime = constantCurve(0.1);
	a.emission.rateOverTime = constantCurve(10.0);
	let capped = started(a, 1.0 / 60.0);
	run(capped, 1.0 / 60.0, 60);
	assert capped.count <= 1;
	a.main.ringBufferMode = RingBufferMode.PauseUntilReplaced;
	let ring = started(a, 1.0 / 60.0);
	run(ring, 1.0 / 60.0, 60);
	assert ring.count == 4;
	for (let i = 0; i < 4; i++) { assert ring.data[AGE * ring.capacity + i] < 0.1; }
}

test "a one-shot system stops emitting and finishes when its last particle dies" {
	let a = quiet();
	a.main.duration = 1.0;
	a.main.loop = false;
	a.main.startLifetime = constantCurve(0.5);
	a.emission.rateOverTime = constantCurve(20.0);
	let sys = started(a, 1.0 / 60.0);
	run(sys, 1.0 / 60.0, 30);
	assert sys.count > 0 && sys.emitting;
	run(sys, 1.0 / 60.0, 120);
	assert sys.count == 0 && !sys.emitting && sys.finished;
}

test "a 2D system keeps every particle on z = 0" {
	let a = busy();
	a.space2D = true;
	let sys = started(a, 1.0 / 60.0);
	run(sys, 1.0 / 60.0, 90);
	assert sys.count > 0;
	for (let i = 0; i < sys.count; i++) { assert sys.data[POS_Z * sys.capacity + i] == 0.0; }
}

test "a world-space emitter moving across a step spreads that step's spawns along its path" {
	let a = quiet();
	a.main.simulationSpace = SimulationSpace.World;
	a.emission.rateOverTime = constantCurve(100.0);
	let sys = started(a, 0.1);
	const moved = updateSystem(sys, 0.1, translation(1.0, 0.0, 0.0));
	assert moved.ok;
	assert sys.count == 10;
	let low: float32 = 1.0;
	let high: float32 = 0.0;
	for (let i = 0; i < sys.count; i++) {
		const x: float32 = sys.data[POS_X * sys.capacity + i];
		if (x < low) { low = x; }
		if (x > high) { high = x; }
	}
	assert low < 0.2 && high > 0.8;
}

test "stop with clear removes the live particles" {
	let a = quiet();
	a.emission.rateOverTime = constantCurve(50.0);
	let sys = started(a, 1.0 / 60.0);
	run(sys, 1.0 / 60.0, 30);
	assert sys.count > 0;
	stopSystem(sys, true);
	assert sys.count == 0 && !sys.emitting;
}
