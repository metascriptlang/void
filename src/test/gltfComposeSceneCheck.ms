import { approx } from "./helpers";
import { DrawContext, closeContext } from "../void3d/draw";
import {
	Scene3D, Transform3D, NodeId3D, NodeFlag, addGroup, rootId, setLocal,
	syncWorld, remove, closeScene, toMatrix,
} from "../void3d/scene";
import { multiplyAffine } from "../math/math3d";
import { loadGltf, GltfData, GltfError } from "../void3d/gltf";
import { addGltfBoundNodes } from "../void3d/gltfScene";
import {
	GltfCurve, GltfCurvePath, GltfCurveMode, GltfCurveError, GltfPoseTrack, forValues,
} from "../void3d/gltfCurve";
import {
	GltfPose, GltfPoseError, bind, samplePose, stageTrsChild, commitSmoothTrs, commitExclusiveTrs,
} from "../void3d/gltfPose";
import {
	AnimationCompose, AnimationRestTarget, AnimationChildSample, AnimationComponent,
	AnimationTrsSample,
	stageSmoothCompose,
} from "../void3d/animationCompose";

function importedGroups(): Result<GltfData, GltfError> {
	return loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[2]}]," +
		"\"nodes\":[" +
		"{\"name\":\"same\",\"translation\":[1,2,3],\"scale\":[2,3,5]," +
		"\"rotation\":[0,0,0.6,0.8]}," +
		"{\"name\":\"same\"}," +
		"{\"name\":\"same\",\"children\":[3,0],\"translation\":[10,0,0]," +
		"\"scale\":[3,4,7],\"rotation\":[0,0.6,0,0.8]}," +
		"{\"name\":\"unowned\",\"translation\":[-4,8,2]}]," +
		"\"meshes\":[],\"accessors\":[],\"bufferViews\":[],\"buffers\":[]}", [],
	);
}

function capturedTargets(
	scene: Scene3D,
	nodes: Readonly<Span<NodeId3D>>,
): Vec<AnimationRestTarget> {
	return [
		{ sourceNode: 0, rest: scene.nodes[nodes[0].index].local },
		{ sourceNode: 2, rest: scene.nodes[nodes[2].index].local },
	];
}

function firstTracks(): Result<Vec<GltfPoseTrack>, GltfCurveError> {
	const translation = try GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Linear,
		[0.0, 3.0], [1.0, 2.0, 3.0, 13.0, 2.0, 3.0],
	);
	const rotation = try GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.Linear,
		[0.0, 3.0], [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0],
	);
	return Result.ok([
		{ sourceNode: 0, curve: translation }, { sourceNode: 2, curve: rotation },
	]);
}

function secondTracks(): Result<Vec<GltfPoseTrack>, GltfCurveError> {
	const scale = try GltfCurve.forValues(
		GltfCurvePath.Scale, GltfCurveMode.Linear,
		[0.0, 2.0], [2.0, 6.0, 10.0, 6.0, 10.0, 14.0],
	);
	const rotation = try GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.Linear,
		[0.0, 2.0], [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
	);
	return Result.ok([
		{ sourceNode: 0, curve: scale }, { sourceNode: 2, curve: rotation },
	]);
}

function sameLocals(
	scene: Scene3D,
	locals: Readonly<Span<Transform3D>>,
	flags: Readonly<Span<BitSet<NodeFlag>>>,
): boolean {
	if (scene.nodes.length != locals.length || locals.length != flags.length) { return false; }
	for (let i = 0; i < locals.length; i++) {
		if (scene.nodes[i].local != locals[i] || scene.nodes[i].flags != flags[i]) {
			return false;
		}
	}
	return true;
}

function localSnapshot(scene: Scene3D): Vec<Transform3D> {
	let locals: Vec<Transform3D> = [];
	for (const node of scene.nodes) { locals.push(node.local); }
	return locals;
}

function flagSnapshot(scene: Scene3D): Vec<BitSet<NodeFlag>> {
	let flags: Vec<BitSet<NodeFlag>> = [];
	for (const node of scene.nodes) { flags.push(node.flags); }
	return flags;
}

function sameAccepted(this compose: AnimationCompose, accepted: AnimationCompose): boolean {
	if (compose.firstSeconds != accepted.firstSeconds ||
		compose.secondSeconds != accepted.secondSeconds ||
		compose.output.length != accepted.output.length) { return false; }
	for (let i = 0; i < compose.output.length; i++) {
		if (compose.output[i] != accepted.output[i]) { return false; }
	}
	return true;
}

test "TRS Scene smooth publication keeps source holes, actor rest and independent clocks" {
	const loaded = importedGroups();
	const tracksA = firstTracks();
	const tracksB = secondTracks();
	assert loaded.ok && tracksA.ok && tracksB.ok;
	if (!loaded.ok || !tracksA.ok || !tracksB.ok) { return; }
	const context = DrawContext.withUniformCapacity(0);
	defer closeContext(context);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const actorA = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	const actorB = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	assert actorA.ok && actorB.ok;
	if (!actorA.ok || !actorB.ok) { return; }
	assert actorA.value.count == 3 && actorA.value.nodes.length == 4;
	assert actorA.value.nodes[1].index == -1;
	assert actorA.value.nodes[2].index < actorA.value.nodes[0].index;
	assert actorA.value.nodes[0] != actorB.value.nodes[0];
	const restA = capturedTargets(scene, actorA.value.nodes);
	const capturedB = scene.nodes[actorB.value.nodes[0].index].local;
	setLocal(scene, actorB.value.nodes[0], {
		...capturedB, scale: { x: 10.0, y: 13.0, z: 17.0 },
	});
	const restB = capturedTargets(scene, actorB.value.nodes);
	const madeA = AnimationCompose.create(restA);
	const madeB = AnimationCompose.create(restB);
	const firstA = GltfPose.bind(scene, actorA.value.nodes, tracksA.value);
	const secondA = GltfPose.bind(scene, actorA.value.nodes, tracksB.value);
	const firstB = GltfPose.bind(scene, actorB.value.nodes, tracksA.value);
	const secondB = GltfPose.bind(scene, actorB.value.nodes, tracksB.value);
	assert madeA.ok && madeB.ok && firstA.ok && secondA.ok && firstB.ok && secondB.ok;
	if (!madeA.ok || !madeB.ok || !firstA.ok || !secondA.ok || !firstB.ok || !secondB.ok) {
		return;
	}
	let composeA = madeA.value;
	let composeB = madeB.value;
	const unowned = scene.nodes[actorA.value.nodes[3].index].local;
	const committed = commitSmoothTrs(composeA, firstA.value, secondA.value, 2.0, 0.5, 0.75);
	assert committed.ok;
	if (committed.ok) { assert committed.value == 2; }
	const child = scene.nodes[actorA.value.nodes[0].index].local;
	const parent = scene.nodes[actorA.value.nodes[2].index].local;
	assert approx(child.position.x, 3.0);
	assert approx(child.scale.x, 2.75) && approx(child.scale.y, 6.0);
	assert approx(child.scale.z, 9.5) && child.rotation == restA[0].rest.rotation;
	assert approx(parent.rotation.z, 0.24019223) && approx(parent.rotation.w, 0.97072534);
	assert parent.position == restA[1].rest.position && parent.scale == restA[1].rest.scale;
	assert composeA.firstSeconds == 2.0 && composeA.secondSeconds == 0.5;
	assert scene.nodes[actorA.value.nodes[3].index].local == unowned;
	assert commitSmoothTrs(composeB, firstB.value, secondB.value, 0.0, 2.0, 0.75).ok;
	const childB = scene.nodes[actorB.value.nodes[0].index].local;
	assert approx(childB.scale.x, 7.0) && approx(childB.scale.y, 10.75);
	assert approx(childB.scale.z, 14.75) && childB.rotation == restB[0].rest.rotation;
	assert scene.nodes[actorA.value.nodes[0].index].local == child;
	const accepted = composeA;
	assert commitSmoothTrs(composeA, firstA.value, secondA.value, 2.0, 0.5, 0.75).ok;
	assert scene.nodes[actorA.value.nodes[0].index].local == child;
	assert scene.nodes[actorA.value.nodes[2].index].local == parent;
	assert composeA.sameAccepted(accepted);
	const synced = syncWorld(scene);
	assert synced > 0;
	assert scene.nodes[actorA.value.nodes[0].index].world ==
		child.toMatrix().multiplyAffine(parent.toMatrix());
}

test "TRS child staging owns samples without Scene writes or legacy fallback changes" {
	const loaded = importedGroups();
	const tracks = firstTracks();
	assert loaded.ok && tracks.ok;
	if (!loaded.ok || !tracks.ok) { return; }
	const context = DrawContext.withUniformCapacity(0);
	defer closeContext(context);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const actor = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	assert actor.ok;
	if (!actor.ok) { return; }
	const targets = capturedTargets(scene, actor.value.nodes);
	const bound = GltfPose.bind(scene, actor.value.nodes, tracks.value);
	assert bound.ok;
	if (!bound.ok) { return; }
	const node = actor.value.nodes[0];
	let live = targets[0].rest;
	live.scale = { x: 19.0, y: 23.0, z: 29.0 };
	setLocal(scene, node, live);
	assert bound.value.samplePose(1.0).ok;
	assert approx(scene.nodes[node.index].local.position.x, 5.0);
	assert scene.nodes[node.index].local.scale == live.scale;
	const locals = localSnapshot(scene);
	const flags = flagSnapshot(scene);
	const staged = bound.value.stageTrsChild(targets, 2.0);
	assert staged.ok;
	if (!staged.ok) { return; }
	let child = staged.value;
	assert child.seconds == 2.0 && child.samples.length == 2;
	let translationIndex: int32 = -1;
	let rotationIndex: int32 = -1;
	for (let i = 0; i < child.samples.length; i++) {
		if (child.samples[i].sourceNode == 0) { translationIndex = i; }
		if (child.samples[i].sourceNode == 2) { rotationIndex = i; }
	}
	assert translationIndex >= 0 && rotationIndex >= 0;
	if (translationIndex < 0 || rotationIndex < 0) { return; }
	assert child.samples[translationIndex].value.scale == targets[0].rest.scale;
	assert child.samples[translationIndex].present.has(AnimationComponent.Translation);
	assert !child.samples[translationIndex].present.has(AnimationComponent.Scale);
	assert approx(child.samples[rotationIndex].value.rotation.z, 0.8660254);
	assert approx(child.samples[rotationIndex].value.rotation.w, 0.5);
	const savedTranslation = child.samples[translationIndex].value;
	const savedRotation = child.samples[rotationIndex].value;
	const stagedAgain = bound.value.stageTrsChild(targets, 0.0);
	assert stagedAgain.ok;
	if (!stagedAgain.ok) { return; }
	const other = stagedAgain.value;
	assert other.samples.length == child.samples.length;
	assert child.samples[translationIndex].value == savedTranslation;
	assert child.samples[rotationIndex].value == savedRotation;
	const otherTranslation = other.samples[translationIndex].value.position;
	child.samples[translationIndex].value.position.x = 99.0;
	assert other.samples[translationIndex].value.position == otherTranslation;
	assert bound.value.pending[0].position.x != 99.0;
	assert targets[0].rest.position.x == 1.0;
	assert sameLocals(scene, locals, flags);
	const hole: Vec<AnimationRestTarget> = [{ sourceNode: 1, rest: Transform3D.identity() }];
	assert !bound.value.stageTrsChild(hole, 2.0).ok;
	assert sameLocals(scene, locals, flags);
}

test "TRS Scene exclusive selects whole source and restores absent captured rest" {
	const loaded = importedGroups();
	const tracks = firstTracks();
	assert loaded.ok && tracks.ok;
	if (!loaded.ok || !tracks.ok) { return; }
	const context = DrawContext.withUniformCapacity(0);
	defer closeContext(context);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const actor = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	assert actor.ok;
	if (!actor.ok) { return; }
	const targets = capturedTargets(scene, actor.value.nodes);
	const made = AnimationCompose.create(targets);
	const first = GltfPose.bind(scene, actor.value.nodes, tracks.value);
	const second = GltfPose.bind(scene, actor.value.nodes, []);
	assert made.ok && first.ok && second.ok;
	if (!made.ok || !first.ok || !second.ok) { return; }
	let compose = made.value;
	const unowned = scene.nodes[actor.value.nodes[3].index].local;
	assert commitExclusiveTrs(compose, first.value, second.value, 2.0, 0.5, []).ok;
	assert approx(scene.nodes[actor.value.nodes[0].index].local.position.x, 9.0);
	assert commitExclusiveTrs(compose, first.value, second.value, 2.0, 0.5, [0]).ok;
	assert scene.nodes[actor.value.nodes[0].index].local == targets[0].rest;
	assert approx(scene.nodes[actor.value.nodes[2].index].local.rotation.z, 0.8660254);
	assert scene.nodes[actor.value.nodes[3].index].local == unowned;
	assert compose.firstSeconds == 2.0 && compose.secondSeconds == 0.5;
}

test "TRS Scene late second curve refusal preserves locals flags output and accepted clocks" {
	const loaded = importedGroups();
	const tracks = firstTracks();
	const badRotation = GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.CubicSpline,
		[0.0, 2.0], [
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0,
		],
	);
	assert loaded.ok && tracks.ok && badRotation.ok;
	if (!loaded.ok || !tracks.ok || !badRotation.ok) { return; }
	const context = DrawContext.withUniformCapacity(0);
	defer closeContext(context);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const actor = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	assert actor.ok;
	if (!actor.ok) { return; }
	const targets = capturedTargets(scene, actor.value.nodes);
	const made = AnimationCompose.create(targets);
	const first = GltfPose.bind(scene, actor.value.nodes, tracks.value);
	const second = GltfPose.bind(scene, actor.value.nodes, [
		tracks.value[0], { sourceNode: 2, curve: badRotation.value },
	]);
	assert made.ok && first.ok && second.ok;
	if (!made.ok || !first.ok || !second.ok) { return; }
	let compose = made.value;
	const seed: AnimationChildSample = {
		seconds: 0.125,
		samples: [{
			sourceNode: 0,
			value: { ...targets[0].rest, position: { x: 17.0, y: 2.0, z: 3.0 } },
			present: (0 as BitSet<AnimationComponent>).incl(AnimationComponent.Translation),
		}],
	};
	const empty: AnimationChildSample = { seconds: 0.375, samples: [] };
	assert stageSmoothCompose(compose, seed, empty, 0.25).ok;
	assert compose.firstSeconds == 0.125 && compose.secondSeconds == 0.375;
	assert approx(compose.output[0].value.position.x, 13.0);
	for (let i = 0; i < compose.output.length; i++) {
		setLocal(scene, actor.value.nodes[compose.output[i].sourceNode], compose.output[i].value);
	}
	const synced = syncWorld(scene);
	assert synced > 0;
	const accepted = compose;
	const locals = localSnapshot(scene);
	const flags = flagSnapshot(scene);
	assert !commitSmoothTrs(compose, first.value, second.value, 2.0, 1.0, 0.5).ok;
	assert sameLocals(scene, locals, flags) && compose.sameAccepted(accepted);
	assert !commitExclusiveTrs(compose, first.value, second.value, 2.0, 1.0, [2]).ok;
	assert sameLocals(scene, locals, flags) && compose.sameAccepted(accepted);
	const removed = remove(scene, actor.value.nodes[0]);
	assert removed == 1;
	const replacement = addGroup(scene, scene.rootId(), Transform3D.identity());
	assert replacement.index == actor.value.nodes[0].index;
	assert replacement.generation != actor.value.nodes[0].generation;
	const staleLocals = localSnapshot(scene);
	const staleFlags = flagSnapshot(scene);
	assert !commitSmoothTrs(compose, first.value, second.value, 2.0, 0.0, 0.5).ok;
	assert sameLocals(scene, staleLocals, staleFlags) && compose.sameAccepted(accepted);
	assert !commitExclusiveTrs(compose, first.value, second.value, 2.0, 0.0, [0]).ok;
	assert sameLocals(scene, staleLocals, staleFlags) && compose.sameAccepted(accepted);
}

test "TRS Scene rejects different actors sharing source ordinals in one Scene" {
	const loaded = importedGroups();
	const tracksA = firstTracks();
	const tracksB = secondTracks();
	assert loaded.ok && tracksA.ok && tracksB.ok;
	if (!loaded.ok || !tracksA.ok || !tracksB.ok) { return; }
	const context = DrawContext.withUniformCapacity(0);
	defer closeContext(context);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const actorA = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	const actorB = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	assert actorA.ok && actorB.ok;
	if (!actorA.ok || !actorB.ok) { return; }
	const targets = capturedTargets(scene, actorA.value.nodes);
	for (const target of targets) {
		const source = target.sourceNode;
		assert actorA.value.nodes[source].scene == actorB.value.nodes[source].scene;
		assert actorA.value.nodes[source].generation == actorB.value.nodes[source].generation;
		assert actorA.value.nodes[source].index != actorB.value.nodes[source].index;
	}
	const made = AnimationCompose.create(targets);
	const first = GltfPose.bind(scene, actorA.value.nodes, tracksA.value);
	const ownSecond = GltfPose.bind(scene, actorA.value.nodes, tracksB.value);
	const foreignSecond = GltfPose.bind(scene, actorB.value.nodes, tracksB.value);
	assert made.ok && first.ok && ownSecond.ok && foreignSecond.ok;
	if (!made.ok || !first.ok || !ownSecond.ok || !foreignSecond.ok) { return; }
	let compose = made.value;
	assert commitSmoothTrs(compose, first.value, ownSecond.value, 0.75, 1.25, 0.25).ok;
	assert compose.output.length == 2;
	assert compose.firstSeconds == 0.75 && compose.secondSeconds == 1.25;
	const acceptedFirst: AnimationTrsSample = compose.output[0];
	const acceptedSecond: AnimationTrsSample = compose.output[1];
	const firstSeconds = compose.firstSeconds;
	const secondSeconds = compose.secondSeconds;
	const synced = syncWorld(scene);
	assert synced > 0;
	const locals = localSnapshot(scene);
	const flags = flagSnapshot(scene);
	const smooth = commitSmoothTrs(compose, first.value, foreignSecond.value, 2.0, 0.5, 0.75);
	assert !smooth.ok;
	if (!smooth.ok) { assert smooth.error == GltfPoseError.Target; }
	assert sameLocals(scene, locals, flags);
	assert compose.output.length == 2;
	assert compose.output[0] == acceptedFirst && compose.output[1] == acceptedSecond;
	assert compose.firstSeconds == firstSeconds && compose.secondSeconds == secondSeconds;
	const exclusive = commitExclusiveTrs(compose, first.value, foreignSecond.value, 2.0, 0.5, [0]);
	assert !exclusive.ok;
	if (!exclusive.ok) { assert exclusive.error == GltfPoseError.Target; }
	assert sameLocals(scene, locals, flags);
	assert compose.output.length == 2;
	assert compose.output[0] == acceptedFirst && compose.output[1] == acceptedSecond;
	assert compose.firstSeconds == firstSeconds && compose.secondSeconds == secondSeconds;
}

test "TRS Scene rejects cross-scene owners with matching node rows and generations" {
	const loaded = importedGroups();
	const tracksA = firstTracks();
	const tracksB = secondTracks();
	assert loaded.ok && tracksA.ok && tracksB.ok;
	if (!loaded.ok || !tracksA.ok || !tracksB.ok) { return; }
	const context = DrawContext.withUniformCapacity(0);
	defer closeContext(context);
	const sceneA = Scene3D.create(context);
	defer closeScene(sceneA);
	const sceneB = Scene3D.create(context);
	defer closeScene(sceneB);
	const actorA = addGltfBoundNodes(sceneA, sceneA.rootId(), loaded.value, []);
	const actorB = addGltfBoundNodes(sceneB, sceneB.rootId(), loaded.value, []);
	assert actorA.ok && actorB.ok;
	if (!actorA.ok || !actorB.ok) { return; }
	assert sceneA.serial != sceneB.serial;
	const targets = capturedTargets(sceneA, actorA.value.nodes);
	for (const target of targets) {
		const source = target.sourceNode;
		assert actorA.value.nodes[source].index == actorB.value.nodes[source].index;
		assert actorA.value.nodes[source].generation == actorB.value.nodes[source].generation;
		assert actorA.value.nodes[source].scene != actorB.value.nodes[source].scene;
	}
	const made = AnimationCompose.create(targets);
	const first = GltfPose.bind(sceneA, actorA.value.nodes, tracksA.value);
	const ownSecond = GltfPose.bind(sceneA, actorA.value.nodes, tracksB.value);
	const foreignSecond = GltfPose.bind(sceneB, actorB.value.nodes, tracksB.value);
	assert made.ok && first.ok && ownSecond.ok && foreignSecond.ok;
	if (!made.ok || !first.ok || !ownSecond.ok || !foreignSecond.ok) { return; }
	let compose = made.value;
	assert commitSmoothTrs(compose, first.value, ownSecond.value, 0.75, 1.25, 0.25).ok;
	assert compose.output.length == 2;
	assert compose.firstSeconds == 0.75 && compose.secondSeconds == 1.25;
	const acceptedFirst: AnimationTrsSample = compose.output[0];
	const acceptedSecond: AnimationTrsSample = compose.output[1];
	const firstSeconds = compose.firstSeconds;
	const secondSeconds = compose.secondSeconds;
	const syncedA = syncWorld(sceneA);
	const syncedB = syncWorld(sceneB);
	assert syncedA > 0 && syncedB > 0;
	const localsA = localSnapshot(sceneA);
	const flagsA = flagSnapshot(sceneA);
	const localsB = localSnapshot(sceneB);
	const flagsB = flagSnapshot(sceneB);
	const smooth = commitSmoothTrs(compose, first.value, foreignSecond.value, 2.0, 0.5, 0.75);
	assert !smooth.ok;
	if (!smooth.ok) { assert smooth.error == GltfPoseError.Target; }
	assert sameLocals(sceneA, localsA, flagsA) && sameLocals(sceneB, localsB, flagsB);
	assert compose.output.length == 2;
	assert compose.output[0] == acceptedFirst && compose.output[1] == acceptedSecond;
	assert compose.firstSeconds == firstSeconds && compose.secondSeconds == secondSeconds;
	const exclusive = commitExclusiveTrs(compose, first.value, foreignSecond.value, 2.0, 0.5, [0]);
	assert !exclusive.ok;
	if (!exclusive.ok) { assert exclusive.error == GltfPoseError.Target; }
	assert sameLocals(sceneA, localsA, flagsA) && sameLocals(sceneB, localsB, flagsB);
	assert compose.output.length == 2;
	assert compose.output[0] == acceptedFirst && compose.output[1] == acceptedSecond;
	assert compose.firstSeconds == firstSeconds && compose.secondSeconds == secondSeconds;
}
