// A ParticleEffect played as one thing: its systems step together on one clock, and each step
// hands the parent's events to its sub-emitters before the children step, so a child is born in
// the step its parent's particle died, collided or was born (tests/unity/goldens/subemitter_*).

import { Vec3, vec3, Mat4 } from "../math/math3d";
import { ParticleEffect, SubEmitter, SubEmitterType } from "./asset";
import { CompiledMinMaxCurve, CurveMode, unitDraw } from "./curve";
import {
	ParticleSystem, ParticleSystemError, ParticleEvent, StepClock, FrameSteps, MAX_BIRTH_LINKS,
	DRAW_SUB_EMITTER, frameSteps, beginFrame, stepWithin, playSystem, stopSystem, spawnFromEvent,
	eventOf, mix, POS_X, POS_Y, POS_Z, VEL_X, VEL_Y, VEL_Z,
} from "./system";

export enum EffectErrorKind {
	// A system failed to build; `cause` says why.
	System,
	// A sub-emitter names no system after its parent: children step after their parents.
	ChildOrder,
	// Parent and child simulate in different spaces.
	SpaceMismatch,
	// An event child emits over time or distance, or has a burst after time 0; only a Birth child's
	// rate has a meaning (per parent particle).
	ChildEmission,
	TooManyBirthLinks,
	// A system is the child of a Manual sub-emitter but triggerSubEmitter names another entry.
	NotASubEmitter,
	// triggerSubEmitter names a slot past the parent's live particles.
	NoParticle,
}

export struct EffectError {
	kind: EffectErrorKind;
	system: int32;
	cause: ParticleSystemError;
}

// One sub-emitter entry of a parent system.
struct EffectLink {
	parent: int32;
	entry: SubEmitter;
	// The parent's Birth link this entry owns, else -1.
	birth: int32;
}

export struct EffectInstance {
	systems: Vec<ParticleSystem>;
	clock: StepClock;
	links: Vec<EffectLink>;
	// Per system: whether it plays on its own, and the first event not yet handed to children.
	roots: Vec<boolean>;
	cursors: Vec<int32>;
}

function fail(kind: EffectErrorKind, system: int32): EffectError {
	return { kind: kind, system: system, cause: ParticleSystemError.EmptyRange };
}

function emitsNothing(c: CompiledMinMaxCurve): boolean {
	return c.scalar == 0.0 && (c.mode != CurveMode.TwoConstants || c.minScalar == 0.0);
}

export function create(this typeof EffectInstance, effect: ParticleEffect, seed: uint32): Result<EffectInstance, EffectError> {
	let systems: Vec<ParticleSystem> = [];
	let roots: Vec<boolean> = [];
	let cursors: Vec<int32> = [];
	for (let s = 0; s < (effect.systems.length as int32); s++) {
		const made = ParticleSystem.create(effect.systems[s], mix(seed, s as uint32));
		if (!made.ok) { return Result.err({ kind: EffectErrorKind.System, system: s, cause: made.error }); }
		systems.push(made.value);
		roots.push(true);
		cursors.push(0);
	}
	let links: Vec<EffectLink> = [];
	for (let p = 0; p < (systems.length as int32); p++) {
		const parentAsset = effect.systems[p];
		if (!parentAsset.subEmitters.enabled) { continue; }
		for (const entry of parentAsset.subEmitters.subEmitters) {
			const child: int32 = entry.system;
			if (child <= p || child >= (systems.length as int32)) { return Result.err(fail(EffectErrorKind.ChildOrder, p)); }
			const childAsset = effect.systems[child];
			if (childAsset.main.simulationSpace != parentAsset.main.simulationSpace) {
				return Result.err(fail(EffectErrorKind.SpaceMismatch, child));
			}
			const curves = systems[child].curves;
			for (const burst of childAsset.emission.bursts) {
				if (burst.time != 0.0) { return Result.err(fail(EffectErrorKind.ChildEmission, child)); }
			}
			const birth: boolean = entry.subEmitterType == SubEmitterType.Birth;
			if (!birth && (!emitsNothing(curves.rateOverTime) || !emitsNothing(curves.rateOverDistance))) {
				return Result.err(fail(EffectErrorKind.ChildEmission, child));
			}
			roots[child] = false;
			let birthIndex: int32 = -1;
			if (birth) {
				birthIndex = systems[p].births.length as int32;
				if (birthIndex >= MAX_BIRTH_LINKS) { return Result.err(fail(EffectErrorKind.TooManyBirthLinks, p)); }
				systems[p].births.push({ rate: curves.rateOverTime, distanceRate: curves.rateOverDistance });
			}
			match (entry.subEmitterType) {
				SubEmitterType.Death => { systems[p].wantDeath = true; },
				SubEmitterType.Collision => { systems[p].wantCollision = true; },
				SubEmitterType.Trigger => { systems[p].wantTrigger = true; },
				SubEmitterType.Birth => {},
				SubEmitterType.Manual => {},
			}
			links.push({ parent: p, entry: entry, birth: birthIndex });
		}
	}
	return Result.ok({
		systems: systems,
		clock: { fixedStep: 1.0 / 60.0, maxSubSteps: 8, maxFrameTime: 0.1, remainder: 0.0 },
		links: links,
		roots: roots,
		cursors: cursors,
	});
}

// Plays every system that is no one's sub-emitter; children emit only from their parents' events.
export function playEffect(ref effect: EffectInstance, world: Mat4): void {
	for (let s = 0; s < (effect.systems.length as int32); s++) {
		if (effect.roots[s]) { playSystem(effect.systems[s], world); }
	}
}

export function stopEffect(ref effect: EffectInstance, clear: boolean): void {
	for (let s = 0; s < (effect.systems.length as int32); s++) { stopSystem(effect.systems[s], clear); }
}

export function isAlive(this effect: EffectInstance): boolean {
	for (const sys of effect.systems) {
		if (sys.isAlive()) { return true; }
	}
	return false;
}

// Advances the effect by `frameTime` with its root at `world`. Each system's `events` then holds
// what happened to its particles during the frame. Returns the live particle count.
export function updateEffect(ref effect: EffectInstance, frameTime: float64, world: Mat4): Result<int32, ParticleSystemError> {
	if (!Number.isFinite(frameTime) || frameTime < 0.0) {
		return Result.err(ParticleSystemError.NonFiniteStep);
	}
	const frame: FrameSteps = frameSteps(effect.clock, frameTime);
	const n: int32 = effect.systems.length as int32;
	for (let s = 0; s < n; s++) {
		beginFrame(effect.systems[s], world, frame);
		effect.cursors[s] = 0;
	}
	for (let k = 0; k < frame.count; k++) {
		for (let s = 0; s < n; s++) {
			stepWithin(effect.systems[s], frame, k);
			dispatch(effect, s);
		}
	}
	let count: int32 = 0;
	for (const sys of effect.systems) { count = count + sys.count; }
	return Result.ok(count);
}

// Hands system `s`'s new events to the sub-emitters that consume them.
function dispatch(ref effect: EffectInstance, s: int32): void {
	const end: int32 = effect.systems[s].events.length as int32;
	for (let e = effect.cursors[s]; e < end; e++) {
		const event: ParticleEvent = effect.systems[s].events[e];
		for (let l = 0; l < (effect.links.length as int32); l++) {
			const link: EffectLink = effect.links[l];
			if (link.parent != s || link.entry.subEmitterType != event.kind) { continue; }
			if (event.kind == SubEmitterType.Birth && event.link != link.birth) { continue; }
			emitChild(effect, link, l, event, effect.systems[s].stepIndex);
		}
	}
	effect.cursors[s] = end;
}

function emitChild(ref effect: EffectInstance, link: EffectLink, l: int32, event: ParticleEvent, stepIndex: uint32): void {
	// Keyed by the particle, the entry and the step, so a replay draws the same children.
	const key: uint32 = mix(mix(mix(event.seed, l as uint32), stepIndex), event.count as uint32);
	if (unitDraw(key, DRAW_SUB_EMITTER) >= link.entry.emitProbability) { return; }
	spawnFromEvent(effect.systems[link.entry.system], event, link.entry.properties, key);
}

// ParticleSystem.TriggerSubEmitter: runs every Manual entry `entry` of system `parent` for its
// particle `particle` now, at the particle's position.
export function triggerSubEmitter(ref effect: EffectInstance, parent: int32, entry: int32, particle: int32): Result<int32, EffectError> {
	let seen: int32 = 0;
	for (let l = 0; l < (effect.links.length as int32); l++) {
		const link: EffectLink = effect.links[l];
		if (link.parent != parent) { continue; }
		if (seen == entry) {
			if (link.entry.subEmitterType != SubEmitterType.Manual) { return Result.err(fail(EffectErrorKind.NotASubEmitter, parent)); }
			const sys = effect.systems[parent];
			if (particle < 0 || particle >= sys.count) { return Result.err(fail(EffectErrorKind.NoParticle, parent)); }
			const cap: int32 = sys.capacity;
			const position: Vec3 = vec3(sys.data[POS_X * cap + particle], sys.data[POS_Y * cap + particle], sys.data[POS_Z * cap + particle]);
			const velocity: Vec3 = vec3(sys.data[VEL_X * cap + particle], sys.data[VEL_Y * cap + particle], sys.data[VEL_Z * cap + particle]);
			const event: ParticleEvent = eventOf(sys, particle, SubEmitterType.Manual, position, velocity, 0.0, 0.0);
			emitChild(effect, link, l, event, sys.stepIndex);
			return Result.ok(effect.systems[link.entry.system].count);
		}
		seen = seen + 1;
	}
	return Result.err(fail(EffectErrorKind.NotASubEmitter, parent));
}
