import { Quat, vec3 } from "../math/math3d";
import { Transform3D } from "../void3d/scene";
import { GltfCurve, GltfCurvePath, GltfCurveMode } from "../void3d/gltfCurve";
import {
	AnimationCompose,
	AnimationComposeError,
	AnimationComponent,
	AnimationRestTarget,
	AnimationChildSample,
	stageSmoothCompose,
	stageExclusiveCompose,
} from "../void3d/animationCompose";

function closeFloat(actual: float32, expected: float32): boolean {
	return Math.abs(actual - expected) < 0.000002;
}

function noComponents(): BitSet<AnimationComponent> {
	return 0 as BitSet<AnimationComponent>;
}

function restTargets(): Vec<AnimationRestTarget> {
	return [
		{
			sourceNode: 7,
			rest: {
				position: vec3(10.0, -2.0, 5.0),
				rotation: { x: 0.0, y: 0.0, z: 0.6, w: 0.8 },
				scale: vec3(2.0, 3.0, 4.0),
			},
		},
		{
			sourceNode: 2,
			rest: {
				...Transform3D.identity(),
				position: vec3(-4.0, 3.0, 6.0),
				scale: vec3(5.0, 6.0, 7.0),
			},
		},
		{ sourceNode: 19, rest: Transform3D.fromTranslation(vec3(9.0, 8.0, 7.0)) },
	];
}

function fixture(): AnimationCompose {
	const targets = restTargets();
	const created = AnimationCompose.create(targets);
	if (!created.ok) { unreachable; }
	return created.value;
}

function firstChild(): AnimationChildSample {
	return {
		seconds: 1.25,
		samples: [
			{
				sourceNode: 2,
				value: Transform3D.fromTranslation(vec3(6.0, 7.0, 8.0)),
				present: noComponents().incl(AnimationComponent.Translation),
			},
			{
				sourceNode: 7,
				value: Transform3D.fromTranslation(vec3(14.0, 2.0, 9.0)),
				present: noComponents().incl(AnimationComponent.Translation),
			},
			{
				sourceNode: 19,
				value: Transform3D.fromTranslation(vec3(100.0, 0.0, 0.0)),
				present: noComponents().incl(AnimationComponent.Translation),
			},
		],
	};
}

function secondChild(): AnimationChildSample {
	return {
		seconds: 3.75,
		samples: [
			{
				sourceNode: 7,
				value: { ...Transform3D.identity(), scale: vec3(6.0, 7.0, 8.0) },
				present: noComponents().incl(AnimationComponent.Scale),
			},
			{
				sourceNode: 2,
				value: {
					...Transform3D.identity(),
					position: vec3(-2.0, 1.0, 4.0),
					rotation: { x: 0.0, y: 0.0, z: -0.8, w: -0.6 },
				},
				present: AnimationComponent.Translation | AnimationComponent.Rotation,
			},
		],
	};
}

test "animationCompose smooth resolves disjoint and overlapping channels by source index" {
	let compose = fixture();
	const first = firstChild();
	const second = secondChild();
	assert stageSmoothCompose(compose, first, second, 0.25).ok;
	assert compose.output[0].sourceNode == 7 && compose.output[1].sourceNode == 2;
	assert compose.output[0].value.position == vec3(13.0, 1.0, 8.0);
	assert compose.output[0].value.scale == vec3(3.0, 4.0, 5.0);
	assert closeFloat(compose.output[0].value.rotation.z, 0.6);
	assert closeFloat(compose.output[0].value.rotation.w, 0.8);
	assert compose.output[0].present ==
		(AnimationComponent.Translation | AnimationComponent.Scale);
	assert compose.output[1].value.position == vec3(4.0, 5.5, 7.0);
	assert compose.output[1].value.scale == vec3(5.0, 6.0, 7.0);
	assert closeFloat(compose.output[1].value.rotation.z, 0.21693046);
	assert closeFloat(compose.output[1].value.rotation.w, 0.97618706);
	assert compose.output[1].present ==
		(AnimationComponent.Translation | AnimationComponent.Rotation);
	assert compose.firstSeconds == 1.25 && compose.secondSeconds == 3.75;
	assert stageSmoothCompose(compose, first, second, 0.0).ok;
	assert compose.output[0].value.position == vec3(14.0, 2.0, 9.0);
	assert compose.output[0].value.scale == vec3(2.0, 3.0, 4.0);
	assert compose.output[0].present ==
		(AnimationComponent.Translation | AnimationComponent.Scale);
	assert stageSmoothCompose(compose, first, second, 1.0).ok;
	assert compose.output[0].value.position == vec3(10.0, -2.0, 5.0);
	assert compose.output[0].value.scale == vec3(6.0, 7.0, 8.0);
}

test "animationCompose exclusive whole-object mask never overlays other child properties" {
	let compose = fixture();
	const first = firstChild();
	const second = secondChild();
	assert stageExclusiveCompose(compose, first, second, [7, 19]).ok;
	assert compose.output[0].value.position == vec3(10.0, -2.0, 5.0);
	assert compose.output[0].value.scale == vec3(6.0, 7.0, 8.0);
	assert compose.output[0].value.rotation == compose.targets[0].rest.rotation;
	assert compose.output[0].present == noComponents().incl(AnimationComponent.Scale);
	assert compose.output[1].value.position == vec3(6.0, 7.0, 8.0);
	assert compose.output[1].value.rotation == compose.targets[1].rest.rotation;
	assert compose.output[1].present == noComponents().incl(AnimationComponent.Translation);
	assert compose.output[2].present.isEmpty();
	assert compose.output[2].value.position == vec3(9.0, 8.0, 7.0);
	assert stageExclusiveCompose(compose, first, second, [2]).ok;
	assert compose.output[1].value.position == vec3(-2.0, 1.0, 4.0);
	assert compose.output[1].present.has(AnimationComponent.Rotation);
	assert compose.output[2].value.position.x == 100.0;
}

test "animationCompose captured rest never feeds back previous composed output" {
	let targets = restTargets();
	const created = AnimationCompose.create(targets);
	assert created.ok;
	if (!created.ok) { return; }
	let compose = created.value;
	targets[0].rest.position.x = 500.0;
	let first = firstChild();
	const second = secondChild();
	assert stageSmoothCompose(compose, first, second, 0.25).ok;
	first.samples[1].value.position.x = 200.0;
	assert compose.output[0].value.position.x == 13.0;
	assert compose.first[0].value.position.x == 14.0;
	const empty: AnimationChildSample = { seconds: -5.0, samples: [] };
	assert stageSmoothCompose(compose, empty, second, 0.5).ok;
	assert compose.output[0].value.position == vec3(10.0, -2.0, 5.0);
	assert compose.output[0].value.scale == vec3(4.0, 5.0, 6.0);
	assert !compose.output[0].present.has(AnimationComponent.Translation);
	assert compose.output[2].present.isEmpty();
	assert compose.output[2].value.position == vec3(9.0, 8.0, 7.0);
}

test "animationCompose two value owners retain independent scratch and unequal child clocks" {
	let a = fixture();
	let b = fixture();
	const first = firstChild();
	const second = secondChild();
	assert stageSmoothCompose(a, first, second, 0.25).ok;
	let later = secondChild();
	later.seconds = 8.125;
	later.samples[0].value.scale = vec3(10.0, 11.0, 12.0);
	assert stageExclusiveCompose(b, first, later, [7]).ok;
	assert a.output[0].value.position.x == 13.0;
	assert a.output[0].value.scale == vec3(3.0, 4.0, 5.0);
	assert a.second[0].value.scale == vec3(6.0, 7.0, 8.0);
	assert a.secondSeconds == 3.75 && b.secondSeconds == 8.125;
	assert b.output[0].value.scale == vec3(10.0, 11.0, 12.0);
	let copied = a;
	assert stageExclusiveCompose(copied, first, later, [7]).ok;
	assert a.output[0].value.scale == vec3(3.0, 4.0, 5.0);
}

test "animationCompose crossfade nlerp stays distinct from independently sampled glTF SLERP" {
	const curve = GltfCurve.forValues(
		GltfCurvePath.Rotation,
		GltfCurveMode.Linear,
		[0.0, 3.0],
		[0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0],
	);
	assert curve.ok;
	if (!curve.ok) { return; }
	const sampled = curve.value.sample(2.0);
	assert sampled.ok;
	if (!sampled.ok) { return; }
	const rotation: Quat = {
		x: sampled.value.x, y: sampled.value.y, z: sampled.value.z, w: sampled.value.w,
	};
	assert closeFloat(rotation.z, 0.8660254) && closeFloat(rotation.w, 0.5);
	let compose = fixture();
	const first: AnimationChildSample = {
		seconds: 0.125,
		samples: [{
			sourceNode: 2, value: Transform3D.identity(),
			present: noComponents().incl(AnimationComponent.Rotation),
		}],
	};
	let second: AnimationChildSample = {
		seconds: 2.0,
		samples: [{
			sourceNode: 2, value: { ...Transform3D.identity(), rotation: rotation },
			present: noComponents().incl(AnimationComponent.Rotation),
		}],
	};
	assert stageSmoothCompose(compose, first, second, 0.25).ok;
	assert closeFloat(compose.output[1].value.rotation.z, 0.24019223);
	assert closeFloat(compose.output[1].value.rotation.w, 0.97072534);
	second.samples[0].value.rotation = { x: 0.0, y: 0.0, z: -rotation.z, w: -rotation.w };
	assert stageSmoothCompose(compose, first, second, 0.25).ok;
	assert closeFloat(compose.output[1].value.rotation.z, 0.24019223);
	assert closeFloat(compose.output[1].value.rotation.w, 0.97072534);
}

test "animationCompose late invalid child leaves staged output and accepted times atomic" {
	let compose = fixture();
	let first = firstChild();
	let second = secondChild();
	assert stageSmoothCompose(compose, first, second, 0.25).ok;
	first.seconds = 88.0;
	second.seconds = 99.0;
	second.samples[0].value.scale = vec3(20.0, 21.0, 22.0);
	second.samples[1].value.rotation = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	const refused = stageSmoothCompose(compose, first, second, 0.5);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == AnimationComposeError.InvalidQuaternion; }
	assert compose.output[0].value.position.x == 13.0;
	assert compose.output[0].value.scale == vec3(3.0, 4.0, 5.0);
	assert compose.output[1].value.position == vec3(4.0, 5.5, 7.0);
	assert compose.firstSeconds == 1.25 && compose.secondSeconds == 3.75;
	assert !stageExclusiveCompose(compose, first, second, []).ok;
	assert compose.output[0].value.scale == vec3(3.0, 4.0, 5.0);
	assert stageSmoothCompose(compose, first, secondChild(), 0.5).ok;
	assert compose.output[0].value.scale == vec3(4.0, 5.0, 6.0);
}

test "animationCompose refuses bad source identities masks presence clocks and shape" {
	let compose = fixture();
	const second = secondChild();
	let first = firstChild();
	assert stageSmoothCompose(compose, first, second, 0.25).ok;
	const unknownMask = stageExclusiveCompose(compose, first, second, [99]);
	assert !unknownMask.ok;
	if (!unknownMask.ok) { assert unknownMask.error == AnimationComposeError.Target; }
	const duplicateMask = stageExclusiveCompose(compose, first, second, [7, 7]);
	assert !duplicateMask.ok;
	if (!duplicateMask.ok) { assert duplicateMask.error == AnimationComposeError.DuplicateTarget; }
	first.samples[0].sourceNode = 99;
	const unknown = stageSmoothCompose(compose, first, second, 0.25);
	assert !unknown.ok;
	if (!unknown.ok) { assert unknown.error == AnimationComposeError.Target; }
	first.samples[0].sourceNode = 7;
	const duplicate = stageSmoothCompose(compose, first, second, 0.25);
	assert !duplicate.ok;
	if (!duplicate.ok) { assert duplicate.error == AnimationComposeError.DuplicateTarget; }
	first = firstChild();
	first.samples[0].present = (8 as uint8) as BitSet<AnimationComponent>;
	const presence = stageSmoothCompose(compose, first, second, 0.25);
	assert !presence.ok;
	if (!presence.ok) { assert presence.error == AnimationComposeError.Shape; }
	first = firstChild();
	first.seconds = NaN;
	assert !stageSmoothCompose(compose, first, second, 0.25).ok;
	assert !stageSmoothCompose(compose, firstChild(), second, NaN as float32).ok;
	assert !stageSmoothCompose(compose, firstChild(), second, -0.1).ok;
	assert !stageSmoothCompose(compose, firstChild(), second, 1.1).ok;
	assert compose.output[0].value.position.x == 13.0;
	compose.pending.pop();
	const shape = stageExclusiveCompose(compose, firstChild(), second, []);
	assert !shape.ok;
	if (!shape.ok) { assert shape.error == AnimationComposeError.Shape; }
}

test "animationCompose finite convex extremes and absent components do not auto-repair input" {
	let compose = fixture();
	let first = firstChild();
	let second = secondChild();
	first.samples[1].value.position.x = 3.0e38;
	second.samples[0].present = noComponents().incl(AnimationComponent.Translation);
	second.samples[0].value.position.x = -3.0e38;
	second.samples[0].value.scale.x = NaN as float32;
	assert stageSmoothCompose(compose, first, second, 0.5).ok;
	assert compose.output[0].value.position.x == 0.0;
	assert compose.output[0].value.scale == vec3(2.0, 3.0, 4.0);
	second.samples[0].value.position.x = NaN as float32;
	const nonfinite = stageSmoothCompose(compose, first, second, 0.5);
	assert !nonfinite.ok;
	if (!nonfinite.ok) { assert nonfinite.error == AnimationComposeError.NonFinite; }
	assert compose.output[0].value.position.x == 0.0;
}

test "animationCompose validates captured rest and supports empty composition" {
	let targets = restTargets();
	targets[1].sourceNode = 7;
	const duplicate = AnimationCompose.create(targets);
	assert !duplicate.ok;
	if (!duplicate.ok) { assert duplicate.error == AnimationComposeError.DuplicateTarget; }
	targets = restTargets();
	targets[0].rest.rotation.w = 2.0;
	const rotation = AnimationCompose.create(targets);
	assert !rotation.ok;
	if (!rotation.ok) { assert rotation.error == AnimationComposeError.InvalidQuaternion; }
	targets = restTargets();
	targets[0].rest.scale.z = NaN as float32;
	const nonfinite = AnimationCompose.create(targets);
	assert !nonfinite.ok;
	if (!nonfinite.ok) { assert nonfinite.error == AnimationComposeError.NonFinite; }
	const created = AnimationCompose.create([]);
	assert created.ok;
	if (!created.ok) { return; }
	let compose = created.value;
	const empty: AnimationChildSample = { seconds: 9.0, samples: [] };
	assert stageSmoothCompose(compose, empty, empty, 0.25).ok;
	assert compose.output.length == 0;
	assert stageExclusiveCompose(compose, empty, empty, []).ok;
}
