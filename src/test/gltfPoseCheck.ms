import { approx } from "./helpers";
import { DrawContext } from "../void3d/draw";
import {
	Scene3D, Transform3D, NodeId3D, addGroup, rootId, syncWorld, remove,
} from "../void3d/scene";
import { GltfCurve, GltfCurvePath, GltfCurveMode, forValues } from "../void3d/gltfCurve";
import { GltfPose, GltfPoseError, bind, samplePose } from "../void3d/gltfPose";
import { GltfData, GltfTransform } from "../void3d/gltf";
import { addGltfBoundNodes, addGltfNodes } from "../void3d/gltfScene";

function group(scene: Scene3D, parent: NodeId3D): NodeId3D {
	return addGroup(scene, parent, Transform3D.identity());
}

test "glTF source-index bindings survive duplicate names and separate model instances" {
	const identity = Transform3D.identity();
	const transform: GltfTransform = {
		position: identity.position, rotation: identity.rotation, scale: identity.scale,
	};
	const data: GltfData = {
		meshes: [], meshMaterials: [], materials: [], textures: [], sceneRoots: [0],
		nodes: [
			{ name: "bone", mesh: -1, local: transform, children: [1] },
			{ name: "bone", mesh: -1, local: transform, children: [] },
			{ name: "unselected", mesh: -1, local: transform, children: [] },
		],
	};
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = addGltfBoundNodes(scene, scene.rootId(), data, []);
	const second = addGltfBoundNodes(scene, scene.rootId(), data, []);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	assert first.value.count == 2 && first.value.nodes.length == 3;
	assert first.value.nodes[0].index != second.value.nodes[0].index;
	assert first.value.nodes[1].index != first.value.nodes[0].index;
	assert first.value.nodes[2].index == -1;
	const legacy = addGltfNodes(scene, scene.rootId(), data, []);
	assert legacy.ok;
	if (legacy.ok) { assert legacy.value == 2; }
}

test "glTF channels have independent times and combine TRS without overwriting each other" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const node = group(scene, scene.rootId());
	const translation = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Linear, [0.0, 4.0],
		[0.0, 0.0, 0.0, 8.0, 0.0, 0.0],
	);
	const scale = GltfCurve.forValues(
		GltfCurvePath.Scale, GltfCurveMode.Step, [1.0, 3.0],
		[2.0, 2.0, 2.0, 3.0, 3.0, 3.0],
	);
	assert translation.ok && scale.ok;
	if (!translation.ok || !scale.ok) { return; }
	const pose = GltfPose.bind(scene, [node], [
		{ sourceNode: 0, curve: translation.value }, { sourceNode: 0, curve: scale.value },
	]);
	assert pose.ok;
	if (!pose.ok) { return; }
	const sampled = pose.value.samplePose(2.0);
	assert sampled.ok;
	if (sampled.ok) { assert sampled.value == 1; }
	assert approx(scene.nodes[node.index].local.position.x, 4.0);
	assert approx(scene.nodes[node.index].local.scale.x, 2.0);
	const _world: int32 = syncWorld(scene);
	assert approx(scene.nodes[node.index].world.m41, 4.0);
}

test "two instances share clip values, not target ids, pose scratch or sample time" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = group(scene, scene.rootId());
	const second = group(scene, scene.rootId());
	const curve = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Linear, [0.0, 4.0],
		[0.0, 0.0, 0.0, 8.0, 0.0, 0.0],
	);
	assert curve.ok;
	if (!curve.ok) { return; }
	const a = GltfPose.bind(scene, [first], [{ sourceNode: 0, curve: curve.value }]);
	const b = GltfPose.bind(scene, [second], [{ sourceNode: 0, curve: curve.value }]);
	assert a.ok && b.ok;
	if (!a.ok || !b.ok) { return; }
	assert a.value.samplePose(1.0).ok;
	assert b.value.samplePose(3.0).ok;
	assert approx(scene.nodes[first.index].local.position.x, 2.0);
	assert approx(scene.nodes[second.index].local.position.x, 6.0);
}

test "stale recycled joint ids reject atomically rather than animating replacement nodes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = group(scene, scene.rootId());
	const second = group(scene, scene.rootId());
	const curve = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Linear, [0.0, 4.0],
		[0.0, 0.0, 0.0, 8.0, 0.0, 0.0],
	);
	assert curve.ok;
	if (!curve.ok) { return; }
	const pose = GltfPose.bind(scene, [first, second], [
		{ sourceNode: 0, curve: curve.value }, { sourceNode: 1, curve: curve.value },
	]);
	assert pose.ok;
	if (!pose.ok) { return; }
	const _removed: int32 = remove(scene, second);
	const replacement = group(scene, scene.rootId());
	const sampled = pose.value.samplePose(2.0);
	assert !sampled.ok;
	if (!sampled.ok) { assert sampled.error == GltfPoseError.Target; }
	assert scene.nodes[first.index].local.position.x == 0.0;
	assert scene.nodes[replacement.index].local.position.x == 0.0;
}

test "a late invalid quaternion leaves the whole scene pose unchanged" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const node = group(scene, scene.rootId());
	const translation = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Linear,
		[0.0, 2.0], [0.0, 0.0, 0.0, 8.0, 0.0, 0.0],
	);
	const rotation = GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.CubicSpline,
		[0.0, 2.0], [
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0,
		],
	);
	assert translation.ok && rotation.ok;
	if (!translation.ok || !rotation.ok) { return; }
	const pose = GltfPose.bind(scene, [node], [
		{ sourceNode: 0, curve: translation.value }, { sourceNode: 0, curve: rotation.value },
	]);
	assert pose.ok;
	if (!pose.ok) { return; }
	const sampled = pose.value.samplePose(1.0);
	assert !sampled.ok;
	if (!sampled.ok) { assert sampled.error == GltfPoseError.Curve; }
	assert scene.nodes[node.index].local.position.x == 0.0;
	assert scene.nodes[node.index].local.rotation.w == 1.0;
	assert pose.value.samplePose(0.0).ok;
}

test "duplicate node-property tracks fail at binding" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const node = group(scene, scene.rootId());
	const curve = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Linear, [0.0], [1.0, 0.0, 0.0],
	);
	assert curve.ok;
	if (!curve.ok) { return; }
	const pose = GltfPose.bind(scene, [node], [
		{ sourceNode: 0, curve: curve.value }, { sourceNode: 0, curve: curve.value },
	]);
	assert !pose.ok;
	if (!pose.ok) { assert pose.error == GltfPoseError.DuplicateTrack; }
}
