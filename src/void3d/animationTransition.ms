import { vec3 } from "../math/math3d";
import { Scene3D, NodeId3D, isLive, setLocal } from "./scene";
import {
	GltfPoseTrack, GltfWeightTrack, GltfCurvePath, sample, sampleWeightsInto,
} from "./gltfCurve";
import {
	AnimationCompose, AnimationRestTarget, AnimationChildSample,
	AnimationComponent, blendedScalar, stageSmoothCompose, stageExclusiveCompose,
} from "./animationCompose";

export enum AnimationTransitionError {
	Duration,
	Delta,
	Target,
	DuplicateTrack,
	WeightShape,
	Curve,
	Compose,
	Speed,
}

export struct AnimationWeightRest {
	sourceNode: int32;
	rest: Vec<float32>;
}

export struct AnimationTransitionClip {
	tracks: Vec<GltfPoseTrack>;
	weightTracks: Vec<GltfWeightTrack>;
	loops: boolean;
	seconds: float64;
}

export struct TransitionSide {
	clip: AnimationTransitionClip;
	trackTarget: Vec<int32>;
	weightTarget: Vec<int32>;
	child: AnimationChildSample;
	weights: Vec<Vec<float32>>;
	time: float64;
}

export struct AnimationTransition {
	compose: AnimationCompose;
	weightRest: Vec<AnimationWeightRest>;
	first: TransitionSide;
	second: TransitionSide;
	weights: Vec<Vec<float32>>;
	blend: float64;
	blendSeconds: float64;
	firstSpeed: float64;
	secondSpeed: float64;
	blendSpeed: float64;
}

function noComponents(): BitSet<AnimationComponent> {
	return 0 as BitSet<AnimationComponent>;
}

export function forTracks(
	this typeof AnimationTransitionClip,
	tracks: Readonly<Span<GltfPoseTrack>>,
	weightTracks: Readonly<Span<GltfWeightTrack>>,
	loops: boolean,
): Result<AnimationTransitionClip, AnimationTransitionError> {
	let clip: AnimationTransitionClip = { tracks: [], weightTracks: [], loops: loops, seconds: 0.0 };
	for (let i = 0; i < tracks.length; i++) {
		for (let previous = 0; previous < i; previous++) {
			if (tracks[previous].sourceNode == tracks[i].sourceNode &&
				tracks[previous].curve.path == tracks[i].curve.path) {
				return Result.err(AnimationTransitionError.DuplicateTrack);
			}
		}
		if (!tracks[i].curve.sample(0.0).ok || tracks[i].curve.times.length < 1) {
			return Result.err(AnimationTransitionError.Curve);
		}
		clip.seconds = Math.max(
			clip.seconds, tracks[i].curve.times[tracks[i].curve.times.length - 1] as float64);
		clip.tracks.push({ sourceNode: tracks[i].sourceNode, curve: tracks[i].curve });
	}
	for (let i = 0; i < weightTracks.length; i++) {
		for (let previous = 0; previous < i; previous++) {
			if (weightTracks[previous].sourceNode == weightTracks[i].sourceNode) {
				return Result.err(AnimationTransitionError.DuplicateTrack);
			}
		}
		if (weightTracks[i].curve.times.length < 1) { return Result.err(AnimationTransitionError.Curve); }
		clip.seconds = Math.max(
			clip.seconds,
			weightTracks[i].curve.times[weightTracks[i].curve.times.length - 1] as float64);
		clip.weightTracks.push({ sourceNode: weightTracks[i].sourceNode, curve: weightTracks[i].curve });
	}
	return Result.ok(move clip);
}

export function localTime(this clip: Readonly<AnimationTransitionClip>, time: float64): float64 {
	if (clip.loops) { return clip.seconds > 0.0 ? time % clip.seconds : 0.0; }
	return Math.min(time, clip.seconds);
}

export function steppedTime(
	this clip: Readonly<AnimationTransitionClip>,
	time: float64,
	dt: float64,
	speed: float64,
): float64 {
	return clip.localTime(Math.max(0.0, time + dt * speed));
}

function copied(values: Readonly<Span<float32>>): Vec<float32> {
	let copy: Vec<float32> = [];
	for (const value of values) { copy.push(value); }
	return move copy;
}

function indexOfNode(targets: Readonly<Span<AnimationRestTarget>>, sourceNode: int32): int32 {
	for (let i = 0; i < targets.length; i++) {
		if (targets[i].sourceNode == sourceNode) { return i as int32; }
	}
	return -1;
}

function indexOfWeightNode(rests: Readonly<Span<AnimationWeightRest>>, sourceNode: int32): int32 {
	for (let i = 0; i < rests.length; i++) {
		if (rests[i].sourceNode == sourceNode) { return i as int32; }
	}
	return -1;
}

export function bindSide(
	targets: Readonly<Span<AnimationRestTarget>>,
	rests: Readonly<Span<AnimationWeightRest>>,
	clip: Readonly<AnimationTransitionClip>,
): Result<TransitionSide, AnimationTransitionError> {
	let side: TransitionSide = {
		clip: { tracks: [], weightTracks: [], loops: clip.loops, seconds: clip.seconds },
		trackTarget: [], weightTarget: [], child: { seconds: 0.0, samples: [] },
		weights: [], time: 0.0,
	};
	for (const track of clip.tracks) {
		const target: int32 = indexOfNode(targets, track.sourceNode);
		if (target < 0) { return Result.err(AnimationTransitionError.Target); }
		side.clip.tracks.push({ sourceNode: track.sourceNode, curve: track.curve });
		side.trackTarget.push(target);
	}
	for (const track of clip.weightTracks) {
		const target: int32 = indexOfWeightNode(rests, track.sourceNode);
		if (target < 0) { return Result.err(AnimationTransitionError.Target); }
		if (rests[target].rest.length != track.curve.targetCount) {
			return Result.err(AnimationTransitionError.WeightShape);
		}
		side.clip.weightTracks.push({ sourceNode: track.sourceNode, curve: track.curve });
		side.weightTarget.push(target);
	}
	for (const target of targets) {
		side.child.samples.push({
			sourceNode: target.sourceNode, value: target.rest, present: noComponents(),
		});
	}
	for (const rest of rests) { side.weights.push(copied(rest.rest)); }
	return Result.ok(move side);
}

export function checkedWeightRests(
	weightRests: Readonly<Span<AnimationWeightRest>>,
): Result<void, AnimationTransitionError> {
	for (let i = 0; i < weightRests.length; i++) {
		if (weightRests[i].rest.length < 1) { return Result.err(AnimationTransitionError.WeightShape); }
		for (const value of weightRests[i].rest) {
			if (!Number.isFinite(value)) { return Result.err(AnimationTransitionError.WeightShape); }
		}
		for (let previous = 0; previous < i; previous++) {
			if (weightRests[previous].sourceNode == weightRests[i].sourceNode) {
				return Result.err(AnimationTransitionError.Target);
			}
		}
	}
	return Result.ok(null);
}

export function create(
	this typeof AnimationTransition,
	targets: Readonly<Span<AnimationRestTarget>>,
	weightRests: Readonly<Span<AnimationWeightRest>>,
	first: Readonly<AnimationTransitionClip>,
	second: Readonly<AnimationTransitionClip>,
	blendSeconds: float64,
): Result<AnimationTransition, AnimationTransitionError> {
	if (!Number.isFinite(blendSeconds) || blendSeconds <= 0.0) {
		return Result.err(AnimationTransitionError.Duration);
	}
	const checkedRests = try checkedWeightRests(weightRests);
	const composed = AnimationCompose.create(targets);
	if (!composed.ok) { return Result.err(AnimationTransitionError.Compose); }
	const firstSide = try bindSide(targets, weightRests, first);
	const secondSide = try bindSide(targets, weightRests, second);
	let transition: AnimationTransition = {
		compose: composed.value, weightRest: [], first: firstSide, second: secondSide,
		weights: [], blend: 0.0, blendSeconds: blendSeconds,
		firstSpeed: 1.0, secondSpeed: 1.0, blendSpeed: 1.0,
	};
	for (const rest of weightRests) {
		transition.weightRest.push({ sourceNode: rest.sourceNode, rest: copied(rest.rest) });
		transition.weights.push(copied(rest.rest));
	}
	return Result.ok(move transition);
}

export function setSpeeds(
	ref transition: AnimationTransition,
	first: float64,
	second: float64,
	blend: float64,
): Result<void, AnimationTransitionError> {
	if (!Number.isFinite(first) || !Number.isFinite(second) || !Number.isFinite(blend)) {
		return Result.err(AnimationTransitionError.Speed);
	}
	transition.firstSpeed = first;
	transition.secondSpeed = second;
	transition.blendSpeed = blend;
	return Result.ok(null);
}

export function advance(
	ref transition: AnimationTransition,
	dt: float64,
): Result<void, AnimationTransitionError> {
	if (!Number.isFinite(dt) || dt < 0.0) { return Result.err(AnimationTransitionError.Delta); }
	transition.first.time = transition.first.clip.steppedTime(
		transition.first.time, dt, transition.firstSpeed);
	transition.second.time = transition.second.clip.steppedTime(
		transition.second.time, dt, transition.secondSpeed);
	transition.blend = Math.min(1.0, Math.max(
		0.0, transition.blend + dt * transition.blendSpeed / transition.blendSeconds));
	return Result.ok(null);
}

export function isFinished(this transition: Readonly<AnimationTransition>): boolean {
	return transition.blend >= 1.0;
}

export function sampleSide(
	targets: Readonly<Span<AnimationRestTarget>>,
	rests: Readonly<Span<AnimationWeightRest>>,
	ref side: TransitionSide,
): Result<void, AnimationTransitionError> {
	const seconds: float64 = side.clip.localTime(side.time);
	side.child.seconds = seconds;
	for (let i = 0; i < side.child.samples.length; i++) {
		side.child.samples[i].present = noComponents();
	}
	for (let i = 0; i < side.clip.tracks.length; i++) {
		const track = side.clip.tracks[i];
		const at: int32 = side.trackTarget[i];
		const sampled = track.curve.sample(seconds);
		if (!sampled.ok) { return Result.err(AnimationTransitionError.Curve); }
		const value = sampled.value;
		match (track.curve.path) {
			GltfCurvePath.Translation => {
				side.child.samples[at].value.position = vec3(value.x, value.y, value.z);
				side.child.samples[at].present =
					side.child.samples[at].present.incl(AnimationComponent.Translation);
			},
			GltfCurvePath.Rotation => {
				side.child.samples[at].value.rotation = {
					x: value.x, y: value.y, z: value.z, w: value.w,
				};
				side.child.samples[at].present =
					side.child.samples[at].present.incl(AnimationComponent.Rotation);
			},
			GltfCurvePath.Scale => {
				side.child.samples[at].value.scale = vec3(value.x, value.y, value.z);
				side.child.samples[at].present =
					side.child.samples[at].present.incl(AnimationComponent.Scale);
			},
		}
	}
	for (let i = 0; i < rests.length; i++) {
		for (let k = 0; k < rests[i].rest.length; k++) { side.weights[i][k] = rests[i].rest[k]; }
	}
	for (let i = 0; i < side.clip.weightTracks.length; i++) {
		const at: int32 = side.weightTarget[i];
		if (!side.clip.weightTracks[i].curve.sampleWeightsInto(seconds, side.weights[at]).ok) {
			return Result.err(AnimationTransitionError.Curve);
		}
	}
	return Result.ok(null);
}

function sampleBoth(ref transition: AnimationTransition): Result<void, AnimationTransitionError> {
	const first = try sampleSide(transition.compose.targets, transition.weightRest, transition.first);
	const second = try sampleSide(transition.compose.targets, transition.weightRest, transition.second);
	return Result.ok(null);
}

export function evaluate(ref transition: AnimationTransition): Result<void, AnimationTransitionError> {
	const sampled = try sampleBoth(transition);
	const toward: float32 = transition.blend as float32;
	const staged = stageSmoothCompose(
		transition.compose, transition.first.child, transition.second.child, toward);
	if (!staged.ok) { return Result.err(AnimationTransitionError.Compose); }
	for (let i = 0; i < transition.weights.length; i++) {
		for (let k = 0; k < transition.weights[i].length; k++) {
			transition.weights[i][k] = blendedScalar(
				transition.first.weights[i][k], transition.second.weights[i][k], toward);
		}
	}
	return Result.ok(null);
}

export function evaluateMasked(
	ref transition: AnimationTransition,
	secondSources: Readonly<Span<int32>>,
): Result<void, AnimationTransitionError> {
	const sampled = try sampleBoth(transition);
	const staged = stageExclusiveCompose(
		transition.compose, transition.first.child, transition.second.child, secondSources);
	if (!staged.ok) { return Result.err(AnimationTransitionError.Compose); }
	for (let i = 0; i < transition.weights.length; i++) {
		let fromSecond: boolean = false;
		for (const source of secondSources) {
			if (source == transition.weightRest[i].sourceNode) { fromSecond = true; }
		}
		for (let k = 0; k < transition.weights[i].length; k++) {
			transition.weights[i][k] = fromSecond
				? transition.second.weights[i][k] : transition.first.weights[i][k];
		}
	}
	return Result.ok(null);
}

export function commitCompose(
	compose: Readonly<AnimationCompose>,
	scene: Scene3D,
	nodes: Readonly<Span<NodeId3D>>,
): Result<int32, AnimationTransitionError> {
	for (const target of compose.targets) {
		if (target.sourceNode >= nodes.length || !scene.isLive(nodes[target.sourceNode])) {
			return Result.err(AnimationTransitionError.Target);
		}
	}
	for (let i = 0; i < compose.targets.length; i++) {
		setLocal(scene, nodes[compose.targets[i].sourceNode], compose.output[i].value);
	}
	return Result.ok(compose.targets.length as int32);
}

export function commit(
	this transition: Readonly<AnimationTransition>,
	scene: Scene3D,
	nodes: Readonly<Span<NodeId3D>>,
): Result<int32, AnimationTransitionError> {
	return commitCompose(transition.compose, scene, nodes);
}
