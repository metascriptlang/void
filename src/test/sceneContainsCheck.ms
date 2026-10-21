import {
	Scene3D, NodeId3D, SceneError, Transform3D,
	addGroup, attach, insertBefore, remove, closeScene,
} from "../void3d/scene";
import { DrawContext } from "../void3d/draw";

function relationIs(scene: Scene3D, ancestor: NodeId3D, node: NodeId3D,
	expected: boolean): boolean {
	const result = scene.containsNode(ancestor, node);
	return result.ok && result.value == expected;
}

test "node containment means strict descendant not self or sibling" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const root = scene.rootId();
	const parent = addGroup(scene, root, Transform3D.identity());
	const child = addGroup(scene, parent, Transform3D.identity());
	const leaf = addGroup(scene, child, Transform3D.identity());
	const sibling = addGroup(scene, root, Transform3D.identity());
	assert relationIs(scene, parent, child, true);
	assert relationIs(scene, parent, leaf, true);
	assert relationIs(scene, root, leaf, true);
	assert relationIs(scene, child, parent, false);
	assert relationIs(scene, parent, sibling, false);
	assert relationIs(scene, parent, parent, false);
	assert relationIs(scene, root, root, false);
}

test "node containment follows reparenting while child order does not affect ancestry" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = addGroup(scene, scene.rootId(), Transform3D.identity());
	const second = addGroup(scene, scene.rootId(), Transform3D.identity());
	const child = addGroup(scene, first, Transform3D.identity());
	assert relationIs(scene, first, child, true);
	assert relationIs(scene, second, child, false);
	attach(scene, second, child);
	assert relationIs(scene, first, child, false);
	assert relationIs(scene, second, child, true);
	insertBefore(scene, scene.rootId(), second, first);
	assert relationIs(scene, second, child, true);
	assert relationIs(scene, scene.rootId(), child, true);
}

test "live detached subtrees retain ancestry without becoming connected to root" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const detached = addGroup(scene, null, Transform3D.identity());
	const other = addGroup(scene, null, Transform3D.identity());
	const child = addGroup(scene, detached, Transform3D.identity());
	assert relationIs(scene, detached, child, true);
	assert relationIs(scene, scene.rootId(), child, false);
	assert relationIs(scene, other, child, false);
	assert relationIs(scene, detached, detached, false);
	attach(scene, scene.rootId(), detached);
	assert relationIs(scene, scene.rootId(), child, true);
	assert relationIs(scene, detached, child, true);
}

test "node containment walks a deep parent chain without a renderer traversal" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const top = addGroup(scene, scene.rootId(), Transform3D.identity());
	let leaf = top;
	for (let i = 0; i < 256; i++) {
		leaf = addGroup(scene, leaf, Transform3D.identity());
	}
	assert relationIs(scene, top, leaf, true);
	assert relationIs(scene, leaf, top, false);
	assert relationIs(scene, top, top, false);
}

test "node containment rejects either stale foreign or closed identifier" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const foreign = Scene3D.create(DrawContext.withUniformCapacity(0));
	const root = scene.rootId();
	const parent = addGroup(scene, root, Transform3D.identity());
	const child = addGroup(scene, parent, Transform3D.identity());
	assert remove(scene, parent) == 2;
	const staleAncestor = scene.containsNode(parent, root);
	const staleChild = scene.containsNode(root, child);
	assert !staleAncestor.ok && !staleChild.ok;
	if (!staleAncestor.ok) { assert staleAncestor.error == SceneError.StaleNode; }
	if (!staleChild.ok) { assert staleChild.error == SceneError.StaleNode; }
	const foreignAncestor = scene.containsNode(foreign.rootId(), root);
	const foreignChild = scene.containsNode(root, foreign.rootId());
	assert !foreignAncestor.ok && !foreignChild.ok;
	if (!foreignAncestor.ok) { assert foreignAncestor.error == SceneError.StaleNode; }
	if (!foreignChild.ok) { assert foreignChild.error == SceneError.StaleNode; }
	closeScene(scene);
	const closed = scene.containsNode(root, root);
	assert !closed.ok;
	if (!closed.ok) { assert closed.error == SceneError.StaleNode; }
}
