import {
	Scene3D, NodeId3D, SceneError, Transform3D, NodeFlag, NO_NODE_ID,
	addGroup, addMeshNode, addLightNode, LightKind, setVisible, setLayers,
	insertBefore, attach, remove, closeScene,
} from "../void3d/scene";
import { vec3 } from "../math/math3d";
import { contextOf } from "./drawHelpers";

function meshNode(scene: Scene3D, parent: NodeId3D): NodeId3D {
	const result = addMeshNode(scene, parent, Transform3D.identity(),
		scene.context.meshAt(0), scene.context.materialAt(0));
	return result.ok ? result.value : NO_NODE_ID;
}

function sameId(first: NodeId3D, second: NodeId3D): boolean {
	return first.scene == second.scene && first.index == second.index
		&& first.generation == second.generation;
}

function matches(result: Result<Vec<NodeId3D>, SceneError>, expected: Vec<NodeId3D>): boolean {
	if (!result.ok) { return false; }
	if (result.value.length != expected.length) { return false; }
	for (let i = 0; i < (expected.length as int32); i++) {
		if (!sameId(result.value[i], expected[i])) { return false; }
	}
	return true;
}

test "subtree mesh enumeration includes self then descendants in child order" {
	const scene = Scene3D.create(contextOf(1, 1));
	const group = addGroup(scene, scene.rootId(), Transform3D.identity());
	const first = meshNode(scene, group);
	const nested = addGroup(scene, group, Transform3D.identity());
	const second = meshNode(scene, nested);
	const third = meshNode(scene, scene.rootId());
	const child = meshNode(scene, first);
	assert scene.isLive(first) && scene.isLive(second) && scene.isLive(third);
	assert matches(scene.getMeshes(scene.rootId()), [first, child, second, third]);
	assert matches(scene.getMeshes(group), [first, child, second]);
	assert matches(scene.getMeshes(first), [first, child]);
}

test "mesh enumeration ignores render visibility layers and world synchronization" {
	const scene = Scene3D.create(contextOf(1, 1));
	const group = addGroup(scene, scene.rootId(), Transform3D.identity());
	const first = meshNode(scene, group);
	const second = meshNode(scene, scene.rootId());
	setVisible(scene, group, false);
	setVisible(scene, second, false);
	setLayers(scene, first, 0);
	assert scene.nodes[first.index].flags.has(NodeFlag.PosChanged);
	assert matches(scene.getMeshes(scene.rootId()), [first, second]);
	assert scene.nodes[first.index].flags.has(NodeFlag.PosChanged);
}

test "mesh enumeration follows insertion and reparenting without changing old results" {
	const scene = Scene3D.create(contextOf(1, 1));
	const first = meshNode(scene, scene.rootId());
	const second = meshNode(scene, scene.rootId());
	const group = addGroup(scene, scene.rootId(), Transform3D.identity());
	const before = scene.getMeshes(scene.rootId());
	assert matches(before, [first, second]);
	insertBefore(scene, scene.rootId(), second, first);
	assert matches(scene.getMeshes(scene.rootId()), [second, first]);
	attach(scene, group, second);
	assert matches(scene.getMeshes(scene.rootId()), [first, second]);
	assert matches(before, [first, second]);
	assert matches(scene.getMeshes(group), [second]);
}

test "live detached subtrees can enumerate meshes without acquiring world state" {
	const scene = Scene3D.create(contextOf(1, 1));
	const detached = addGroup(scene, null, Transform3D.identity());
	const mesh = meshNode(scene, detached);
	assert matches(scene.getMeshes(scene.rootId()), []);
	assert matches(scene.getMeshes(detached), [mesh]);
	const world = scene.worldOf(mesh);
	assert !world.ok;
	if (!world.ok) { assert world.error == SceneError.DetachedNode; }
	attach(scene, scene.rootId(), detached);
	assert matches(scene.getMeshes(scene.rootId()), [mesh]);
}

test "groups and lights are not meshes and empty subtrees are successful queries" {
	const scene = Scene3D.create(contextOf(1, 1));
	const group = addGroup(scene, scene.rootId(), Transform3D.identity());
	const light = addLightNode(scene, group, Transform3D.identity(), {
		kind: LightKind.Point, color: vec3(1, 1, 1), radius: 1.0, power: 1.0, priority: 0,
	});
	assert matches(scene.getMeshes(scene.rootId()), []);
	assert matches(scene.getMeshes(group), []);
	assert matches(scene.getMeshes(light), []);
}

test "mesh enumeration rejects foreign stale reused and closed scene identifiers" {
	const scene = Scene3D.create(contextOf(1, 1));
	const foreign = Scene3D.create(contextOf(1, 1));
	const old = meshNode(scene, scene.rootId());
	assert remove(scene, old) == 1;
	const replacement = meshNode(scene, scene.rootId());
	assert old.index == replacement.index;
	assert old.generation != replacement.generation;
	const stale = scene.getMeshes(old);
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == SceneError.StaleNode; }
	const wrongScene = scene.getMeshes(foreign.rootId());
	assert !wrongScene.ok;
	if (!wrongScene.ok) { assert wrongScene.error == SceneError.StaleNode; }
	assert matches(scene.getMeshes(scene.rootId()), [replacement]);
	const root = scene.rootId();
	closeScene(scene);
	const closed = scene.getMeshes(root);
	assert !closed.ok;
	if (!closed.ok) { assert closed.error == SceneError.StaleNode; }
}
