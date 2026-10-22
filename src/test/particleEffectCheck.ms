import { Vec3, vec3, identity } from "../math/math3d";
import {
	ParticleSystemAsset, ParticleEffect, SimulationSpace, SubEmitterType, SubEmitterProperty,
} from "../particles/asset";
import { constantCurve, constantColor, rgbaColor } from "../particles/curve";
import { POS_X, POS_Y, POS_Z, AGE, START_R, START_G, START_B, START_SIZE_X } from "../particles/system";
import {
	EffectInstance, EffectErrorKind, playEffect, updateEffect, triggerSubEmitter,
} from "../particles/effect";

function near(a: float32, b: float32, tol: float32): boolean {
	const d: float32 = a - b;
	return d < tol && d > -tol;
}

// tests/unity/goldens/subemitter_*: a parent of one particle along +z for 0.5 s, and a child of
// three still particles from a burst at time 0.
function parentAsset(kind: SubEmitterType): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 5.0;
	a.main.loop = false;
	a.main.startLifetime = constantCurve(0.5);
	a.main.startSpeed = constantCurve(1.0);
	a.main.startSizeX = constantCurve(2.0);
	a.main.startColor = constantColor(rgbaColor(1.0, 0.5, 0.25, 1.0));
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	a.subEmitters.enabled = true;
	a.subEmitters.subEmitters = [{
		system: 1, subEmitterType: kind,
		properties: SubEmitterProperty.InheritColor | SubEmitterProperty.InheritSize, emitProbability: 1.0,
	}];
	return a;
}

function childAsset(): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.startLifetime = constantCurve(5.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.startSizeX = constantCurve(0.5);
	a.main.startColor = constantColor(rgbaColor(0.5, 1.0, 1.0, 1.0));
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(3.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	return a;
}

function played(kind: SubEmitterType): EffectInstance {
	const effect: ParticleEffect = { systems: [parentAsset(kind), childAsset()] };
	const made = EffectInstance.create(effect, 12345);
	if (!made.ok) { unreachable; }
	let fx = made.value;
	playEffect(fx, identity());
	return fx;
}

function step(ref fx: EffectInstance, frames: int32): void {
	for (let k = 0; k < frames; k++) {
		const done = updateEffect(fx, 1.0 / 60.0, identity());
		if (!done.ok) { unreachable; }
	}
}

function column(fx: EffectInstance, s: int32, c: int32, i: int32): float32 {
	return fx.systems[s].data[c * fx.systems[s].capacity + i];
}

function positionOf(fx: EffectInstance, s: int32, i: int32): Vec3 {
	return vec3(column(fx, s, POS_X, i), column(fx, s, POS_Y, i), column(fx, s, POS_Z, i));
}

function inheritsColorAndSize(fx: EffectInstance, i: int32): boolean {
	return near(column(fx, 1, START_R, i), 0.5, 1e-5) && near(column(fx, 1, START_G, i), 0.5, 1e-5)
		&& near(column(fx, 1, START_B, i), 0.25, 1e-5) && near(column(fx, 1, START_SIZE_X, i), 1.0, 1e-6);
}

test "a death sub-emitter bursts where the parent died, in the step it died, at age 0" {
	let fx = played(SubEmitterType.Death);
	step(fx, 29);
	assert fx.systems[0].count == 1 && fx.systems[1].count == 0;
	step(fx, 1);
	assert fx.systems[0].count == 0;
	assert fx.systems[1].count == 3;
	for (let i = 0; i < 3; i++) {
		assert (positionOf(fx, 1, i) - vec3(0.0, 0.0, 0.5)).length() < 1e-4;
		assert column(fx, 1, AGE, i) == 0.0;
		assert inheritsColorAndSize(fx, i);
	}
	step(fx, 1);
	assert near(column(fx, 1, AGE, 0), 1.0 / 60.0, 1e-6);
}

test "a birth sub-emitter bursts at the spawn point with the parent's age" {
	let fx = played(SubEmitterType.Birth);
	step(fx, 1);
	assert fx.systems[1].count == 3;
	for (let i = 0; i < 3; i++) {
		assert positionOf(fx, 1, i).length() < 1e-6;
		assert near(column(fx, 1, AGE, i), 1.0 / 60.0, 1e-6);
		assert inheritsColorAndSize(fx, i);
	}
	step(fx, 5);
	assert fx.systems[1].count == 3;
}

test "a birth child's rate emits per parent particle over its life" {
	let child = childAsset();
	child.emission.bursts = [];
	child.emission.rateOverTime = constantCurve(60.0);
	const effect: ParticleEffect = { systems: [parentAsset(SubEmitterType.Birth), child] };
	const made = EffectInstance.create(effect, 12345);
	if (!made.ok) { unreachable; }
	let fx = made.value;
	playEffect(fx, identity());
	step(fx, 10);
	assert fx.systems[1].count >= 9 && fx.systems[1].count <= 10;
	// Children trail the parent along +z, the newest closest to it.
	const last: int32 = fx.systems[1].count - 1;
	assert column(fx, 1, POS_Z, last) > column(fx, 1, POS_Z, 0);
}

test "an effect refuses a child before its parent, a space mismatch and an event child with a rate" {
	let backwards = parentAsset(SubEmitterType.Death);
	backwards.subEmitters.subEmitters[0].system = 0;
	const order = EffectInstance.create({ systems: [backwards, childAsset()] }, 1);
	assert !order.ok && order.error.kind == EffectErrorKind.ChildOrder;
	let local = childAsset();
	local.main.simulationSpace = SimulationSpace.Local;
	const space = EffectInstance.create({ systems: [parentAsset(SubEmitterType.Death), local] }, 1);
	assert !space.ok && space.error.kind == EffectErrorKind.SpaceMismatch;
	let rated = childAsset();
	rated.emission.rateOverTime = constantCurve(5.0);
	const rate = EffectInstance.create({ systems: [parentAsset(SubEmitterType.Death), rated] }, 1);
	assert !rate.ok && rate.error.kind == EffectErrorKind.ChildEmission;
}

test "a manual sub-emitter fires only when the app triggers it" {
	let fx = played(SubEmitterType.Manual);
	step(fx, 3);
	assert fx.systems[1].count == 0;
	const fired = triggerSubEmitter(fx, 0, 0, 0);
	assert fired.ok && fired.value == 3;
	const missing = triggerSubEmitter(fx, 0, 0, 5);
	assert !missing.ok && missing.error.kind == EffectErrorKind.NoParticle;
}

test "the same effect replays the same children" {
	let a = played(SubEmitterType.Death);
	let b = played(SubEmitterType.Death);
	step(a, 40);
	step(b, 40);
	assert a.systems[1].count == b.systems[1].count;
	for (let i = 0; i < a.systems[1].count; i++) {
		assert (positionOf(a, 1, i) - positionOf(b, 1, i)).length() == 0.0;
	}
}
