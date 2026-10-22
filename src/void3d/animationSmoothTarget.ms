import { Scene3D, NodeId3D } from "./scene";
import {
	AnimationCompose, AnimationRestTarget, AnimationChildSample,
	AnimationComponent, blendedScalar, stageSmoothCompose,
} from "./animationCompose";
import {
	AnimationTransitionClip, AnimationTransitionError, AnimationWeightRest, TransitionSide,
	bindSide, sampleSide, steppedTime, checkedWeightRests, commitCompose,
} from "./animationTransition";

export enum AnimationSmoothTargetError {
	Duration,
	Easing,
	Delta,
	Speed,
	Target,
	WeightShape,
	Curve,
	Compose,
}

export struct AnimationSmoothTarget {
	compose: AnimationCompose;
	frozen: AnimationChildSample;
	frozenWeights: Vec<AnimationWeightRest>;
	target: TransitionSide;
	weights: Vec<Vec<float32>>;
	blend: float64;
	blendSeconds: float64;
	easing: float64;
	ignoreTranslate: boolean;
	targetSpeed: float64;
	blendSpeed: float64;
}

// Animation.hx:279 isPlaying, EPSILON at Animation.hx:30.
const pausedBelow: float64 = 0.000001;

function noComponents(): BitSet<AnimationComponent> {
	return 0 as BitSet<AnimationComponent>;
}

// hxd.Math.easeFactor (Math.hx:188).
export function easeFactor(k: float64, easing: float64): float64 {
	const p: float64 = Math.pow(k, 1.0 + easing);
	return p / (p + Math.pow(1.0 - k, easing + 1.0));
}

// PENDING3D: anim-frozen-rotation-unscaled
export function frozenPose(this compose: Readonly<AnimationCompose>): Vec<AnimationRestTarget> {
	let pose: Vec<AnimationRestTarget> = [];
	for (const sample of compose.output) {
		pose.push({ sourceNode: sample.sourceNode, rest: sample.value });
	}
	return move pose;
}

export function frozenWeights(
	rests: Readonly<Span<AnimationWeightRest>>,
	weights: Readonly<Span<Vec<float32>>>,
): Vec<AnimationWeightRest> {
	let frozen: Vec<AnimationWeightRest> = [];
	for (let i = 0; i < rests.length; i++) {
		let copy: Vec<float32> = [];
		for (const value of weights[i]) { copy.push(value); }
		frozen.push({ sourceNode: rests[i].sourceNode, rest: move copy });
	}
	return move frozen;
}

export function create(
	this typeof AnimationSmoothTarget,
	pose: Readonly<Span<AnimationRestTarget>>,
	weights: Readonly<Span<AnimationWeightRest>>,
	clip: Readonly<AnimationTransitionClip>,
	blendSeconds: float64,
	easing: float64,
	ignoreTranslate: boolean,
): Result<AnimationSmoothTarget, AnimationSmoothTargetError> {
	if (!Number.isFinite(blendSeconds) || blendSeconds <= 0.0) {
		return Result.err(AnimationSmoothTargetError.Duration);
	}
	if (!Number.isFinite(easing) || easing <= -1.0) {
		return Result.err(AnimationSmoothTargetError.Easing);
	}
	if (!checkedWeightRests(weights).ok) { return Result.err(AnimationSmoothTargetError.WeightShape); }
	const composed = AnimationCompose.create(pose);
	if (!composed.ok) { return Result.err(AnimationSmoothTargetError.Compose); }
	const side = bindSide(pose, weights, clip);
	if (!side.ok) {
		return Result.err(side.error == AnimationTransitionError.WeightShape
			? AnimationSmoothTargetError.WeightShape : AnimationSmoothTargetError.Target);
	}
	let smooth: AnimationSmoothTarget = {
		compose: composed.value, frozen: { seconds: 0.0, samples: [] },
		frozenWeights: [],
		target: side.value, weights: [], blend: 0.0, blendSeconds: blendSeconds, easing: easing,
		ignoreTranslate: ignoreTranslate, targetSpeed: 1.0, blendSpeed: 1.0,
	};
	for (const target of pose) {
		smooth.frozen.samples.push({
			sourceNode: target.sourceNode, value: target.rest, present: noComponents(),
		});
	}
	for (const weight of weights) {
		let held: Vec<float32> = [];
		let current: Vec<float32> = [];
		for (const value of weight.rest) { held.push(value); current.push(value); }
		smooth.frozenWeights.push({ sourceNode: weight.sourceNode, rest: move held });
		smooth.weights.push(move current);
	}
	return Result.ok(move smooth);
}

export function setSmoothTargetSpeeds(
	ref smooth: AnimationSmoothTarget,
	target: float64,
	blend: float64,
): Result<void, AnimationSmoothTargetError> {
	if (!Number.isFinite(target) || !Number.isFinite(blend)) {
		return Result.err(AnimationSmoothTargetError.Speed);
	}
	smooth.targetSpeed = target;
	smooth.blendSpeed = blend;
	return Result.ok(null);
}

// SmoothTarget.hx:98: a blend speed at or under EPSILON pauses the target clip too.
export function advanceSmoothTarget(
	ref smooth: AnimationSmoothTarget,
	dt: float64,
): Result<void, AnimationSmoothTargetError> {
	if (!Number.isFinite(dt) || dt < 0.0) { return Result.err(AnimationSmoothTargetError.Delta); }
	if (Math.abs(smooth.blendSpeed) <= pausedBelow) { return Result.ok(null); }
	smooth.target.time = smooth.target.clip.steppedTime(
		smooth.target.time, dt, smooth.targetSpeed);
	smooth.blend = Math.min(1.0, Math.max(
		0.0, smooth.blend + dt * smooth.blendSpeed / smooth.blendSeconds));
	return Result.ok(null);
}

export function isSmoothTargetFinished(this smooth: Readonly<AnimationSmoothTarget>): boolean {
	return smooth.blend >= 1.0;
}

export function evaluateSmoothTarget(
	ref smooth: AnimationSmoothTarget,
): Result<void, AnimationSmoothTargetError> {
	if (!sampleSide(smooth.compose.targets, smooth.frozenWeights, smooth.target).ok) {
		return Result.err(AnimationSmoothTargetError.Curve);
	}
	for (let i = 0; i < smooth.frozen.samples.length; i++) {
		if (smooth.ignoreTranslate) {
			smooth.frozen.samples[i].value.position = smooth.target.child.samples[i].value.position;
			smooth.frozen.samples[i].present = noComponents().incl(AnimationComponent.Translation);
		} else {
			smooth.frozen.samples[i].present = noComponents();
		}
	}
	const eased: float64 = easeFactor(smooth.blend, smooth.easing);
	if (!stageSmoothCompose(smooth.compose, smooth.frozen, smooth.target.child, eased as float32).ok) {
		return Result.err(AnimationSmoothTargetError.Compose);
	}
	for (let i = 0; i < smooth.weights.length; i++) {
		for (let k = 0; k < smooth.weights[i].length; k++) {
			smooth.weights[i][k] = blendedScalar(
				smooth.frozenWeights[i].rest[k], smooth.target.weights[i][k], eased as float32);
		}
	}
	return Result.ok(null);
}

export function commitSmoothTarget(
	this smooth: Readonly<AnimationSmoothTarget>,
	scene: Scene3D,
	nodes: Readonly<Span<NodeId3D>>,
): Result<int32, AnimationTransitionError> {
	return commitCompose(smooth.compose, scene, nodes);
}
