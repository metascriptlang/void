import {
	Scene3D, NodeId3D, SceneError, Transform3D, NO_NODE_ID,
	addGroup, addMeshNode, setVisible, setLayers, remove, closeScene,
} from "../void3d/scene";
import { MaterialId } from "../void3d/draw";
import { bits } from "../void3d/gpu3d";
import { contextOf } from "./drawHelpers";

function meshNode(scene: Scene3D, parent: NodeId3D, material: int32): NodeId3D {
	const result = addMeshNode(scene, parent, Transform3D.identity(),
		scene.context.meshAt(0), scene.context.materialAt(material));
	return result.ok ? result.value : NO_NODE_ID;
}

function sameMaterial(first: MaterialId, second: MaterialId): boolean {
	return first.store == second.store && first.index == second.index
		&& first.generation == second.generation;
}

function matches(result: Result<Vec<MaterialId>, SceneError>, expected: Vec<MaterialId>): boolean {
	if (!result.ok || result.value.length != expected.length) { return false; }
	for (let i = 0; i < (expected.length as int32); i++) {
		if (!sameMaterial(result.value[i], expected[i])) { return false; }
	}
	return true;
}

test "subtree materials deduplicate handles in first mesh encounter order" {
	const context = contextOf(1, 3);
	const scene = Scene3D.create(context);
	const first = meshNode(scene, scene.rootId(), 0);
	const child = meshNode(scene, first, 2);
	const group = addGroup(scene, scene.rootId(), Transform3D.identity());
	const second = meshNode(scene, group, 1);
	const shared = meshNode(scene, group, 0);
	assert scene.isLive(first) && scene.isLive(child)
		&& scene.isLive(second) && scene.isLive(shared);
	assert matches(scene.getMaterials(scene.rootId()),
		[context.materialAt(0), context.materialAt(2), context.materialAt(1)]);
	assert context.materialPins[0] == 2;
	assert context.materialPins[1] == 1;
	assert context.materialPins[2] == 1;
}

test "nonrecursive material lookup reads only the starting mesh" {
	const context = contextOf(1, 2);
	const scene = Scene3D.create(context);
	const first = meshNode(scene, scene.rootId(), 0);
	const child = meshNode(scene, first, 1);
	assert scene.isLive(child);
	assert matches(scene.getMaterials(scene.rootId(), false), []);
	assert matches(scene.getMaterials(first, false), [context.materialAt(0)]);
	assert matches(scene.getMaterials(first), [context.materialAt(0), context.materialAt(1)]);
	setVisible(scene, first, false);
	setLayers(scene, child, 0);
	assert matches(scene.getMaterials(scene.rootId()),
		[context.materialAt(0), context.materialAt(1)]);
}

test "distinct material handles remain distinct even when their values match" {
	const context = contextOf(1, 2);
	const scene = Scene3D.create(context);
	const first = meshNode(scene, scene.rootId(), 0);
	const second = meshNode(scene, scene.rootId(), 1);
	assert scene.isLive(first) && scene.isLive(second);
	assert context.materials[0].program.bits() == context.materials[1].program.bits();
	assert !sameMaterial(context.materialAt(0), context.materialAt(1));
	assert matches(scene.getMaterials(scene.rootId()),
		[context.materialAt(0), context.materialAt(1)]);
}

test "detached material queries and caller-owned results leave scene ownership alone" {
	const context = contextOf(1, 2);
	const scene = Scene3D.create(context);
	const detached = addGroup(scene, null, Transform3D.identity());
	const node = meshNode(scene, detached, 1);
	assert scene.isLive(node);
	assert matches(scene.getMaterials(scene.rootId()), []);
	const result = scene.getMaterials(detached);
	assert matches(result, [context.materialAt(1)]);
	if (result.ok) {
		let owned = result.value;
		owned.pop();
	}
	assert matches(scene.getMaterials(detached), [context.materialAt(1)]);
	assert context.materialPins[1] == 1;
}

test "material enumeration rejects stale foreign and closed node handles" {
	const scene = Scene3D.create(contextOf(1, 1));
	const foreign = Scene3D.create(contextOf(1, 1));
	const old = meshNode(scene, scene.rootId(), 0);
	assert remove(scene, old) == 1;
	const stale = scene.getMaterials(old);
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == SceneError.StaleNode; }
	const wrongScene = scene.getMaterials(foreign.rootId(), false);
	assert !wrongScene.ok;
	if (!wrongScene.ok) { assert wrongScene.error == SceneError.StaleNode; }
	const root = scene.rootId();
	closeScene(scene);
	const closed = scene.getMaterials(root);
	assert !closed.ok;
	if (!closed.ok) { assert closed.error == SceneError.StaleNode; }
}
