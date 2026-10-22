import { vec3 } from "../math/math3d";
import { DrawContext } from "../void3d/draw";
import { Scene3D, Transform3D, NodeId3D, addGroup, rootId } from "../void3d/scene";
import {
	GltfCurve, GltfCurvePath, GltfCurveMode, GltfPoseTrack, GltfWeightCurve, GltfWeightTrack,
	forValues, forWeightValues, sampleWeightsInto, sampleWeights,
} from "../void3d/gltfCurve";
import { AnimationRestTarget } from "../void3d/animationCompose";
import {
	AnimationTransition, AnimationTransitionClip, AnimationTransitionError, AnimationWeightRest,
	advance, evaluate, evaluateMasked, isFinished, commit,
} from "../void3d/animationTransition";


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

function targets(): Vec<AnimationRestTarget> {
	return [
		{ sourceNode: 3, rest: Transform3D.fromTranslation(vec3(1.0, 1.0, 1.0)) },
		{
			sourceNode: 5,
			rest: { ...Transform3D.identity(), scale: vec3(4.0, 4.0, 4.0) },
		},
	];
}

function rests(): Vec<AnimationWeightRest> {
	return [{ sourceNode: 3, rest: [0.5, 0.5] }, { sourceNode: 5, rest: [0.25] }];
}

function clipA(loops: boolean): AnimationTransitionClip {
	const tracks: Vec<GltfPoseTrack> = [
		{
			sourceNode: 3,
			curve: curve(GltfCurvePath.Translation, [0.0, 2.0], [0.0, 0.0, 0.0, 4.0, 0.0, 0.0]),
		},
		{
			sourceNode: 5,
			curve: curve(GltfCurvePath.Scale, [0.0, 1.0], [1.0, 1.0, 1.0, 3.0, 3.0, 3.0]),
		},
	];
	const weights: Vec<GltfWeightTrack> = [
		{ sourceNode: 3, curve: weightCurve(2, [0.0, 2.0], [0.0, 1.0, 2.0, 3.0]) },
	];
	const made = AnimationTransitionClip.forTracks(tracks, weights, loops);
	if (!made.ok) { unreachable; }
	return made.value;
}

function clipB(loops: boolean): AnimationTransitionClip {
	const half: float32 = 0.70710678;
	const tracks: Vec<GltfPoseTrack> = [
		{
			sourceNode: 3,
			curve: curve(GltfCurvePath.Translation, [0.0, 1.0], [10.0, 0.0, 0.0, 10.0, 8.0, 0.0]),
		},
		{
			sourceNode: 3,
			curve: curve(GltfCurvePath.Rotation, [0.0, 2.0], [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, half, half]),
		},
	];
	const weights: Vec<GltfWeightTrack> = [
		{ sourceNode: 5, curve: weightCurve(1, [0.0, 1.0], [1.0, 3.0]) },
	];
	const made = AnimationTransitionClip.forTracks(tracks, weights, loops);
	if (!made.ok) { unreachable; }
	return made.value;
}

function fixture(blendSeconds: float64, loopA: boolean): AnimationTransition {
	const made = AnimationTransition.create(
		targets(), rests(), clipA(loopA), clipB(false), blendSeconds);
	if (!made.ok) { unreachable; }
	return made.value;
}

test "animationTransition blends two clips at their own local times with a weight that advances" {
	let t = fixture(2.0, false);
	assert advance(t, 0.5).ok && evaluate(t).ok;
	assert close(t.blend as float32, 0.25);
	assert close(t.compose.output[0].value.position.x, 3.25);
	assert close(t.compose.output[0].value.position.y, 1.0);
	assert close(t.compose.output[0].value.position.z, 0.0);
	assert close(t.compose.output[0].value.rotation.z, 0.04894925);
	assert close(t.compose.output[0].value.rotation.w, 0.99880127);
	assert t.compose.output[0].value.scale == vec3(1.0, 1.0, 1.0);
	assert close(t.compose.output[1].value.scale.x, 2.5);
	assert t.compose.output[1].value.position == vec3(0.0, 0.0, 0.0);
	assert close(t.weights[0][0], 0.5) && close(t.weights[0][1], 1.25);
	assert close(t.weights[1][0], 0.6875);
	assert advance(t, 1.0).ok && evaluate(t).ok;
	assert close(t.compose.output[0].value.position.x, 8.25);
	assert close(t.compose.output[0].value.position.y, 6.0);
	assert close(t.compose.output[0].value.rotation.z, 0.43050335);
	assert close(t.compose.output[0].value.rotation.w, 0.90258898);
	assert close(t.compose.output[1].value.scale.x, 3.75);
	assert close(t.weights[0][0], 0.75) && close(t.weights[0][1], 1.0);
	assert close(t.weights[1][0], 2.3125);
	assert !isFinished(t);
}

test "animationTransition ends on the second clip and clamps the weight at one" {
	let t = fixture(2.0, false);
	assert advance(t, 5.0).ok && evaluate(t).ok;
	assert t.blend == 1.0 && isFinished(t);
	assert t.first.time == 2.0 && t.second.time == 2.0;
	assert t.compose.output[0].value.position == vec3(10.0, 8.0, 0.0);
	assert close(t.compose.output[0].value.rotation.z, 0.70710678);
	assert close(t.compose.output[0].value.rotation.w, 0.70710678);
	assert t.compose.output[1].value.scale == vec3(4.0, 4.0, 4.0);
	assert close(t.weights[0][0], 0.5) && close(t.weights[0][1], 0.5);
	assert close(t.weights[1][0], 3.0);
	assert advance(t, 1.0).ok && t.blend == 1.0;
}

test "animationTransition loop wraps a clip onto its first key and clamp holds the last" {
	let looped = fixture(4.0, true);
	assert advance(looped, 2.0).ok && evaluate(looped).ok;
	assert looped.first.time == 0.0;
	assert close(looped.compose.output[0].value.position.x, 5.0);
	assert close(looped.compose.output[0].value.position.y, 4.0);
	let clamped = fixture(4.0, false);
	assert advance(clamped, 2.0).ok && evaluate(clamped).ok;
	assert clamped.first.time == 2.0;
	assert close(clamped.compose.output[0].value.position.x, 7.0);
	let later = fixture(100.0, true);
	assert advance(later, 2.5).ok && evaluate(later).ok;
	assert close(later.first.time as float32, 0.5);
	assert close(later.compose.output[0].value.position.x, 1.225);
	assert close(later.compose.output[0].value.position.y, 0.2);
}

test "animationTransition masked blend takes listed nodes whole from the second clip" {
	let t = fixture(2.0, false);
	assert advance(t, 0.5).ok && evaluateMasked(t, [3]).ok;
	assert close(t.compose.output[0].value.position.x, 10.0);
	assert close(t.compose.output[0].value.position.y, 4.0);
	assert close(t.compose.output[0].value.rotation.z, 0.19509032);
	assert t.compose.output[0].value.scale == vec3(1.0, 1.0, 1.0);
	assert close(t.compose.output[1].value.scale.x, 2.0);
	assert close(t.weights[0][0], 0.5) && close(t.weights[0][1], 0.5);
	assert close(t.weights[1][0], 0.25);
	assert evaluateMasked(t, [5]).ok;
	assert close(t.compose.output[0].value.position.x, 1.0);
	assert close(t.compose.output[1].value.scale.x, 4.0);
	assert close(t.weights[0][1], 1.5);
	assert close(t.weights[1][0], 2.0);
	assert t.blend == 0.25;
	assert !evaluateMasked(t, [9]).ok;
	assert !evaluateMasked(t, [3, 3]).ok;
}

test "animationTransition two instances over one clip keep independent clocks and scratch" {
	let a = fixture(2.0, false);
	let b = fixture(2.0, false);
	assert advance(a, 1.0).ok && advance(b, 0.5).ok;
	assert evaluate(a).ok && evaluate(b).ok;
	assert close(a.compose.output[0].value.position.x, 6.0);
	assert close(b.compose.output[0].value.position.x, 3.25);
}

test "animationTransition commit writes the blended pose to the bound nodes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	let nodes: Vec<NodeId3D> = [];
	for (let i = 0; i < 6; i++) { nodes.push(addGroup(scene, scene.rootId(), Transform3D.identity())); }
	let t = fixture(2.0, false);
	assert advance(t, 0.5).ok && evaluate(t).ok;
	const written = t.commit(scene, nodes);
	assert written.ok;
	if (written.ok) { assert written.value == 2; }
	assert close(scene.nodes[nodes[3].index].local.position.x, 3.25);
	assert close(scene.nodes[nodes[5].index].local.scale.x, 2.5);
	assert scene.nodes[nodes[4].index].local.position == vec3(0.0, 0.0, 0.0);
	assert !t.commit(scene, [nodes[0]]).ok;
}

test "animationTransition refuses unusable durations, steps and unmappable clips" {
	const bad = [0.0, -1.0, NaN, Infinity];
	for (const seconds of bad) {
		const made = AnimationTransition.create(targets(), rests(), clipA(false), clipB(false), seconds);
		assert !made.ok;
		if (!made.ok) { assert made.error == AnimationTransitionError.Duration; }
	}
	let t = fixture(2.0, false);
	assert advance(t, 0.5).ok;
	for (const dt of [-0.1, NaN, Infinity]) {
		const stepped = advance(t, dt);
		assert !stepped.ok;
		if (!stepped.ok) { assert stepped.error == AnimationTransitionError.Delta; }
	}
	assert t.blend == 0.25 && t.first.time == 0.5;
	const missing = AnimationTransition.create(
		[targets()[0]], rests(), clipA(false), clipB(false), 1.0);
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == AnimationTransitionError.Target; }
	const noWeights = AnimationTransition.create(
		targets(), [rests()[0]], clipA(false), clipB(false), 1.0);
	assert !noWeights.ok;
	if (!noWeights.ok) { assert noWeights.error == AnimationTransitionError.Target; }
	const wrongCount = AnimationTransition.create(
		targets(), [{ sourceNode: 3, rest: [0.5] }, rests()[1]], clipA(false), clipB(false), 1.0);
	assert !wrongCount.ok;
	if (!wrongCount.ok) { assert wrongCount.error == AnimationTransitionError.WeightShape; }
	const nan = AnimationTransition.create(
		targets(), [{ sourceNode: 3, rest: [NaN as float32, 0.5] }, rests()[1]],
		clipA(false), clipB(false), 1.0);
	assert !nan.ok;
	const dup = AnimationTransitionClip.forTracks(
		[clipA(false).tracks[0], clipA(false).tracks[0]], [], false);
	assert !dup.ok;
	if (!dup.ok) { assert dup.error == AnimationTransitionError.DuplicateTrack; }
}

test "gltfCurve sampleWeightsInto fills a caller buffer and agrees with sampleWeights" {
	const c = weightCurve(2, [0.0, 2.0], [0.0, 1.0, 2.0, 3.0]);
	let buffer: Vec<float32> = [9.0, 9.0];
	assert c.sampleWeightsInto(0.5, buffer).ok;
	assert close(buffer[0], 0.5) && close(buffer[1], 1.5);
	const owned = c.sampleWeights(0.5);
	assert owned.ok;
	if (owned.ok) { assert owned.value[0] == buffer[0] && owned.value[1] == buffer[1]; }
	assert c.sampleWeightsInto(-1.0, buffer).ok && buffer[0] == 0.0 && buffer[1] == 1.0;
	assert c.sampleWeightsInto(7.0, buffer).ok && buffer[0] == 2.0 && buffer[1] == 3.0;
	let short: Vec<float32> = [0.0];
	assert !c.sampleWeightsInto(0.5, short).ok;
	assert !c.sampleWeightsInto(NaN, buffer).ok;
}
