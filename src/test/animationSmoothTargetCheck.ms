import { vec3 } from "../math/math3d";
import { DrawContext } from "../void3d/draw";
import { Scene3D, Transform3D, NodeId3D, addGroup, rootId } from "../void3d/scene";
import {
	GltfCurve, GltfCurvePath, GltfCurveMode, GltfPoseTrack, GltfWeightCurve, GltfWeightTrack,
	forValues, forWeightValues,
} from "../void3d/gltfCurve";
import { AnimationRestTarget } from "../void3d/animationCompose";
import {
	AnimationTransition, AnimationTransitionClip, AnimationWeightRest,
	forTracks, setSpeeds, advance, evaluate,
} from "../void3d/animationTransition";
import {
	AnimationSmoothTarget, AnimationSmoothTargetError, easeFactor, frozenPose, frozenWeights,
	setSmoothTargetSpeeds, advanceSmoothTarget, evaluateSmoothTarget, commitSmoothTarget,
	isSmoothTargetFinished,
} from "../void3d/animationSmoothTarget";

function close(actual: float32, expected: float32): boolean {
	return Math.abs(actual - expected) < 0.000002;
}

function curve(path: GltfCurvePath, times: Vec<float32>, values: Vec<float32>): GltfCurve {
	const made = GltfCurve.forValues(path, GltfCurveMode.Linear, times, values);
	if (!made.ok) { unreachable; }
	return made.value;
}

function weightCurve(count: int32, times: Vec<float32>, values: Vec<float32>): GltfWeightCurve {
	const made = GltfWeightCurve.forWeightValues(GltfCurveMode.Linear, count, times, values);
	if (!made.ok) { unreachable; }
	return made.value;
}

function pose(): Vec<AnimationRestTarget> {
	return [
		{ sourceNode: 3, rest: Transform3D.fromTranslation(vec3(2.0, 0.0, 0.0)) },
		{
			sourceNode: 5,
			rest: { ...Transform3D.identity(), position: vec3(1.0, 1.0, 1.0), scale: vec3(2.0, 2.0, 2.0) },
		},
	];
}

function heldWeights(): Vec<AnimationWeightRest> {
	return [{ sourceNode: 3, rest: [0.5, 0.5] }, { sourceNode: 5, rest: [0.25] }];
}

function targetClip(loops: boolean): AnimationTransitionClip {
	const half: float32 = 0.70710678;
	const tracks: Vec<GltfPoseTrack> = [
		{
			sourceNode: 3,
			curve: curve(GltfCurvePath.Translation, [0.0, 2.0], [10.0, 0.0, 0.0, 10.0, 8.0, 0.0]),
		},
		{
			sourceNode: 3,
			curve: curve(GltfCurvePath.Rotation, [0.0, 2.0], [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, half, half]),
		},
		{
			sourceNode: 5,
			curve: curve(GltfCurvePath.Scale, [0.0, 1.0], [1.0, 1.0, 1.0, 5.0, 5.0, 5.0]),
		},
	];
	const weights: Vec<GltfWeightTrack> = [
		{ sourceNode: 3, curve: weightCurve(2, [0.0, 2.0], [0.0, 1.0, 2.0, 3.0]) },
	];
	const made = AnimationTransitionClip.forTracks(tracks, weights, loops);
	if (!made.ok) { unreachable; }
	return made.value;
}

function slideClip(seconds: float32, y: float32): AnimationTransitionClip {
	const tracks: Vec<GltfPoseTrack> = [
		{
			sourceNode: 3,
			curve: curve(GltfCurvePath.Translation, [0.0, seconds], [0.0, 0.0, 0.0, 0.0, y, 0.0]),
		},
	];
	const made = AnimationTransitionClip.forTracks(tracks, [], false);
	if (!made.ok) { unreachable; }
	return made.value;
}

function fixture(blendSeconds: float64, easing: float64, ignoreTranslate: boolean): AnimationSmoothTarget {
	const made = AnimationSmoothTarget.create(
		pose(), heldWeights(), targetClip(false), blendSeconds, easing, ignoreTranslate);
	if (!made.ok) { unreachable; }
	return made.value;
}

function transitionFixture(): AnimationTransition {
	const made = AnimationTransition.create(
		pose(), heldWeights(), targetClip(false), slideClip(1.0, 6.0), 2.0);
	if (!made.ok) { unreachable; }
	return made.value;
}

test "animationSmoothTarget eases from the frozen pose toward the target clip" {
	let s = fixture(2.0, 0.0, false);
	assert evaluateSmoothTarget(s).ok;
	assert s.compose.output[0].value.position == vec3(2.0, 0.0, 0.0);
	assert s.compose.output[1].value.scale == vec3(2.0, 2.0, 2.0);
	assert advanceSmoothTarget(s, 0.5).ok && evaluateSmoothTarget(s).ok;
	assert close(s.blend as float32, 0.25);
	assert close(s.compose.output[0].value.position.x, 4.0);
	assert close(s.compose.output[0].value.position.y, 0.5);
	assert close(s.compose.output[0].value.rotation.z, 0.04894925);
	assert close(s.compose.output[0].value.rotation.w, 0.99880127);
	assert s.compose.output[0].value.scale == vec3(1.0, 1.0, 1.0);
	assert close(s.compose.output[1].value.scale.x, 2.25);
	assert s.compose.output[1].value.position == vec3(1.0, 1.0, 1.0);
	assert close(s.weights[0][0], 0.5) && close(s.weights[0][1], 0.75);
	assert close(s.weights[1][0], 0.25);
	assert !isSmoothTargetFinished(s);
}

test "animationSmoothTarget ends on the target clip and holds it" {
	let s = fixture(2.0, 0.0, false);
	assert advanceSmoothTarget(s, 5.0).ok && evaluateSmoothTarget(s).ok;
	assert s.blend == 1.0 && isSmoothTargetFinished(s) && s.target.time == 2.0;
	assert s.compose.output[0].value.position == vec3(10.0, 8.0, 0.0);
	assert close(s.compose.output[0].value.rotation.w, 0.70710678);
	assert s.compose.output[1].value.scale == vec3(5.0, 5.0, 5.0);
	assert close(s.weights[0][0], 2.0) && close(s.weights[0][1], 3.0);
	assert close(s.weights[1][0], 0.25);
}

test "animationSmoothTarget ignoreTranslate takes translation from the target while rotation and scale blend" {
	let s = fixture(2.0, 0.0, true);
	assert advanceSmoothTarget(s, 0.5).ok && evaluateSmoothTarget(s).ok;
	assert close(s.compose.output[0].value.position.x, 10.0);
	assert close(s.compose.output[0].value.position.y, 2.0);
	assert close(s.compose.output[0].value.rotation.z, 0.04894925);
	assert s.compose.output[1].value.position == vec3(1.0, 1.0, 1.0);
	assert close(s.compose.output[1].value.scale.x, 2.25);
	s.ignoreTranslate = false;
	assert evaluateSmoothTarget(s).ok;
	assert close(s.compose.output[0].value.position.x, 4.0);
}

test "animationSmoothTarget easing reshapes the blend with hxd.Math.easeFactor" {
	assert easeFactor(0.0, 1.0) == 0.0 && easeFactor(1.0, 1.0) == 1.0;
	assert Math.abs(easeFactor(0.25, 1.0) - 0.1) < 0.000000001;
	assert Math.abs(easeFactor(0.25, 0.0) - 0.25) < 0.000000001;
	let s = fixture(2.0, 1.0, false);
	assert advanceSmoothTarget(s, 0.5).ok && evaluateSmoothTarget(s).ok;
	assert close(s.compose.output[0].value.position.x, 2.8);
	assert close(s.weights[0][1], 0.5 * 0.9 + 1.5 * 0.1);
}

test "animationSmoothTarget speeds scale the target clip and the blend independently" {
	let s = fixture(2.0, 0.0, false);
	assert setSmoothTargetSpeeds(s, 2.0, 1.0).ok;
	assert advanceSmoothTarget(s, 0.5).ok && evaluateSmoothTarget(s).ok;
	assert s.target.time == 1.0 && close(s.blend as float32, 0.25);
	assert close(s.compose.output[0].value.position.y, 1.0);
	let b = fixture(2.0, 0.0, false);
	assert setSmoothTargetSpeeds(b, 1.0, 2.0).ok;
	assert advanceSmoothTarget(b, 0.5).ok && evaluateSmoothTarget(b).ok;
	assert b.target.time == 0.5 && close(b.blend as float32, 0.5);
	assert close(b.compose.output[0].value.position.x, 6.0);
	assert close(b.compose.output[0].value.position.y, 1.0);
}

test "animationSmoothTarget a zero blend speed pauses the target clip as well, as Heaps does" {
	let s = fixture(2.0, 0.0, false);
	assert setSmoothTargetSpeeds(s, 1.0, 0.0).ok;
	assert advanceSmoothTarget(s, 1.0).ok;
	assert s.target.time == 0.0 && s.blend == 0.0;
}

test "animationSmoothTarget a negative speed plays back and holds the first key, never wrapping" {
	let s = fixture(4.0, 0.0, false);
	assert advanceSmoothTarget(s, 1.5).ok;
	assert setSmoothTargetSpeeds(s, -1.0, 1.0).ok;
	assert advanceSmoothTarget(s, 1.0).ok && close(s.target.time as float32, 0.5);
	assert advanceSmoothTarget(s, 1.0).ok && s.target.time == 0.0;
	assert setSmoothTargetSpeeds(s, 1.0, -1.0).ok;
	assert advanceSmoothTarget(s, 10.0).ok && s.blend == 0.0;
	assert evaluateSmoothTarget(s).ok;
	assert s.compose.output[0].value.position == vec3(2.0, 0.0, 0.0);
	const looped = AnimationSmoothTarget.create(
		pose(), heldWeights(), targetClip(true), 4.0, 0.0, false);
	assert looped.ok;
	if (looped.ok) {
		let l = looped.value;
		assert setSmoothTargetSpeeds(l, -1.0, 1.0).ok && advanceSmoothTarget(l, 1.0).ok;
		assert l.target.time == 0.0;
	}
}

test "animationSmoothTarget freezes a transition caught mid-blend and starts from that exact pose" {
	let t = transitionFixture();
	assert advance(t, 0.5).ok && evaluate(t).ok;
	const frozen = AnimationSmoothTarget.create(
		t.compose.frozenPose(), frozenWeights(t.weightRest, t.weights),
		targetClip(false), 2.0, 0.0, false);
	assert frozen.ok;
	if (!frozen.ok) { return; }
	let s = frozen.value;
	assert evaluateSmoothTarget(s).ok;
	assert s.compose.output[0].value == t.compose.output[0].value;
	assert s.compose.output[1].value == t.compose.output[1].value;
	assert s.weights[0][0] == t.weights[0][0] && s.weights[0][1] == t.weights[0][1];
	assert s.weights[1][0] == t.weights[1][0];
	assert advanceSmoothTarget(s, 1.0).ok && evaluateSmoothTarget(s).ok;
	const chained = AnimationSmoothTarget.create(
		s.compose.frozenPose(), frozenWeights(s.frozenWeights, s.weights),
		targetClip(false), 1.0, 0.0, false);
	assert chained.ok;
	if (chained.ok) {
		let c = chained.value;
		assert evaluateSmoothTarget(c).ok;
		assert c.compose.output[0].value == s.compose.output[0].value;
	}
}

test "animationSmoothTarget commit writes the eased pose to the bound nodes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	let nodes: Vec<NodeId3D> = [];
	for (let i = 0; i < 6; i++) { nodes.push(addGroup(scene, scene.rootId(), Transform3D.identity())); }
	let s = fixture(2.0, 0.0, false);
	assert advanceSmoothTarget(s, 0.5).ok && evaluateSmoothTarget(s).ok;
	assert s.commitSmoothTarget(scene, nodes).ok;
	assert close(scene.nodes[nodes[3].index].local.position.x, 4.0);
	assert close(scene.nodes[nodes[5].index].local.scale.x, 2.25);
	assert !s.commitSmoothTarget(scene, [nodes[0]]).ok;
}

test "animationSmoothTarget refuses unusable durations, easings, speeds, steps and unmappable clips" {
	for (const seconds of [0.0, -1.0, NaN, Infinity]) {
		const made = AnimationSmoothTarget.create(
			pose(), heldWeights(), targetClip(false), seconds, 0.0, false);
		assert !made.ok;
		if (!made.ok) { assert made.error == AnimationSmoothTargetError.Duration; }
	}
	for (const easing of [-1.0, -2.0, NaN, Infinity]) {
		const made = AnimationSmoothTarget.create(
			pose(), heldWeights(), targetClip(false), 1.0, easing, false);
		assert !made.ok;
		if (!made.ok) { assert made.error == AnimationSmoothTargetError.Easing; }
	}
	let s = fixture(2.0, 0.0, false);
	assert advanceSmoothTarget(s, 0.5).ok;
	for (const dt of [-0.1, NaN, Infinity]) {
		const stepped = advanceSmoothTarget(s, dt);
		assert !stepped.ok;
		if (!stepped.ok) { assert stepped.error == AnimationSmoothTargetError.Delta; }
	}
	for (const speed of [NaN, Infinity, -Infinity]) {
		const onTarget = setSmoothTargetSpeeds(s, speed, 1.0);
		assert !onTarget.ok && !setSmoothTargetSpeeds(s, 1.0, speed).ok;
		if (!onTarget.ok) { assert onTarget.error == AnimationSmoothTargetError.Speed; }
	}
	assert s.targetSpeed == 1.0 && s.blendSpeed == 1.0 && s.blend == 0.25 && s.target.time == 0.5;
	const missing = AnimationSmoothTarget.create(
		[pose()[0]], heldWeights(), targetClip(false), 1.0, 0.0, false);
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == AnimationSmoothTargetError.Target; }
	const wrongCount = AnimationSmoothTarget.create(
		pose(), [{ sourceNode: 3, rest: [0.5] }, heldWeights()[1]], targetClip(false), 1.0, 0.0, false);
	assert !wrongCount.ok;
	if (!wrongCount.ok) { assert wrongCount.error == AnimationSmoothTargetError.WeightShape; }
	const nan = AnimationSmoothTarget.create(
		pose(), [{ sourceNode: 3, rest: [NaN as float32, 0.5] }, heldWeights()[1]],
		targetClip(false), 1.0, 0.0, false);
	assert !nan.ok;
	if (!nan.ok) { assert nan.error == AnimationSmoothTargetError.WeightShape; }
}

test "animationTransition speeds scale each side's clock and the blend rate on their own" {
	let t = transitionFixture();
	assert setSpeeds(t, 2.0, 0.5, 1.0).ok && advance(t, 1.0).ok;
	assert t.first.time == 2.0 && t.second.time == 0.5 && close(t.blend as float32, 0.5);
	assert setSpeeds(t, -1.0, 1.0, -1.0).ok && advance(t, 3.0).ok;
	assert t.first.time == 0.0 && t.blend == 0.0;
	for (const speed of [NaN, Infinity]) {
		assert !setSpeeds(t, speed, 1.0, 1.0).ok;
		assert !setSpeeds(t, 1.0, speed, 1.0).ok;
		assert !setSpeeds(t, 1.0, 1.0, speed).ok;
	}
	assert t.firstSpeed == -1.0 && t.secondSpeed == 1.0 && t.blendSpeed == -1.0;
}
