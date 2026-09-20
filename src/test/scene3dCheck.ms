import { Vec3, vec3, Mat4, eulerQuat } from "../math/math3d";
import { DrawItem } from "../void3d/draw";
import {
	Scene,
	NodeId,
	NodeKind,
	Transform3D,
	SceneError,
	setMeshOf,
	FLAG_CULLED,
	identityTransform,
	transformAt,
	NO_NODE,
	addGroup,
	addMeshNode,
	setLocal,
	setVisible,
	remove,
	syncWorld,
	collectDrawList,
	refresh,
} from "../void3d/scene";
import { approx } from "./helpers";

function translationOf(m: Mat4): Vec3 {
	return vec3(m.m41, m.m42, m.m43);
}

function near(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(a.x, x) && approx(a.y, y) && approx(a.z, z);
}

// A mesh node under the root, at `where`. A failure comes back as NO_NODE rather than an
// assert, which only a test block may use; every caller checks the index it gets.
function oneMesh(ref scene: Scene, where: Vec3, mesh: int32): NodeId {
	const added: Result<NodeId, SceneError> = addMeshNode(scene, scene.rootId(), transformAt(where), mesh, 0);
	return added.ok ? added.value : { index: NO_NODE, generation: 0 };
}

test "a new scene is one root group and nothing else" {
	let scene: Scene = Scene.create();
	assert scene.nodeCount() == 1;
	assert scene.root != NO_NODE;
	assert scene.isLive(scene.rootId());
	assert scene.nodes[scene.root].kind == NodeKind.Group;
	assert scene.nodes[scene.root].parent == NO_NODE;
}

test "a child is parented both ways, and the structure is marked" {
	let scene: Scene = Scene.create();
	const child: NodeId = oneMesh(scene, vec3(1.0, 0.0, 0.0), 7);
	assert scene.nodeCount() == 2;
	assert scene.nodes[child.index].parent == scene.root;
	assert (scene.nodes[scene.root].children.length as int32) == 1;
	assert scene.nodes[scene.root].children[0] == child.index;
	assert scene.structureChanged;
}

test "sync places a child at local times parent, in that order" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), transformAt(vec3(10.0, 0.0, 0.0)));
	assert group.ok;
	if (!group.ok) { return; }
	const child: Result<NodeId, SceneError> = addMeshNode(scene, group.value, transformAt(vec3(0.0, 2.0, 0.0)), 0, 0);
	assert child.ok;
	if (!child.ok) { return; }
	const synced: int32 = syncWorld(scene);
	assert synced == 3;
	const world: Result<Mat4, SceneError> = scene.worldOf(child.value);
	assert world.ok;
	if (world.ok) { assert near(translationOf(world.value), 10.0, 2.0, 0.0); }
}

// Heaps' rule: the parent's rotation turns the child's offset, which is what `local * parent`
// in row-vector order means and what `parent * local` would get backwards.
test "a parent's rotation carries its child around, not the other way" {
	let scene: Scene = Scene.create();
	const quarter: float32 = 1.5707963;
	const turned: Transform3D = { ...identityTransform(), rotation: eulerQuat(0.0, quarter, 0.0) };
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), turned);
	assert group.ok;
	if (!group.ok) { return; }
	const child: Result<NodeId, SceneError> = addMeshNode(scene, group.value, transformAt(vec3(1.0, 0.0, 0.0)), 0, 0);
	assert child.ok;
	if (!child.ok) { return; }
	const _synced: int32 = syncWorld(scene);
	const world: Result<Mat4, SceneError> = scene.worldOf(child.value);
	assert world.ok;
	// A quarter turn about Y takes +X to -Z in this right-handed, Y-up world.
	if (world.ok) { assert near(translationOf(world.value), 0.0, 0.0, -1.0); }
}

test "a synced tree is clean, and syncing again moves nothing" {
	let scene: Scene = Scene.create();
	const _child: NodeId = oneMesh(scene, vec3(1.0, 0.0, 0.0), 0);
	assert syncWorld(scene) == 2;
	assert syncWorld(scene) == 0;
}

test "moving a parent re-syncs its children and nothing above it" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	const child: Result<NodeId, SceneError> = addMeshNode(scene, group.value, transformAt(vec3(0.0, 1.0, 0.0)), 0, 0);
	assert child.ok;
	if (!child.ok) { return; }
	assert syncWorld(scene) == 3;
	assert setLocal(scene, group.value, transformAt(vec3(5.0, 0.0, 0.0))).ok;
	// The group and its one child, and not the root.
	assert syncWorld(scene) == 2;
	const world: Result<Mat4, SceneError> = scene.worldOf(child.value);
	assert world.ok;
	if (world.ok) { assert near(translationOf(world.value), 5.0, 1.0, 0.0); }
}

test "collect emits one item per mesh node, in sibling order" {
	let scene: Scene = Scene.create();
	const _first: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 11);
	const _second: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 22);
	const _third: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 33);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert items[0].mesh == 11;
	assert items[1].mesh == 22;
	assert items[2].mesh == 33;
	assert !scene.structureChanged;
}

test "a group contributes no draw item but its children still do" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	const under: Result<NodeId, SceneError> = addMeshNode(scene, group.value, identityTransform(), 5, 0);
	assert under.ok;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	assert items[0].mesh == 5;
}

test "collect carries the synced world matrix onto the draw item" {
	let scene: Scene = Scene.create();
	const _mesh: NodeId = oneMesh(scene, vec3(3.0, 4.0, 5.0), 1);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	assert near(translationOf(items[0].world), 3.0, 4.0, 5.0);
}

test "an invisible node takes its whole subtree out of the draw list" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	assert addMeshNode(scene, group.value, identityTransform(), 1, 0).ok;
	assert addMeshNode(scene, group.value, identityTransform(), 2, 0).ok;
	const _visible: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 9);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert setVisible(scene, group.value, false).ok;
	assert collectDrawList(scene, items) == 1;
	assert items[0].mesh == 9;
}

test "refresh rewrites world matrices without rebuilding the list" {
	let scene: Scene = Scene.create();
	const moving: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 4);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 1;
	assert !scene.structureChanged;
	assert setLocal(scene, moving, transformAt(vec3(0.0, 8.0, 0.0))).ok;
	assert refresh(scene, items) == 1;
	assert near(translationOf(items[0].world), 0.0, 8.0, 0.0);
	// Still one item, still the same mesh: the structure never changed.
	assert items[0].mesh == 4;
	assert !scene.structureChanged;
}

test "removing a node takes its subtree with it and unlinks it from its parent" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	assert addMeshNode(scene, group.value, identityTransform(), 1, 0).ok;
	assert addMeshNode(scene, group.value, identityTransform(), 2, 0).ok;
	assert scene.nodeCount() == 4;
	const freed: Result<int32, SceneError> = remove(scene, group.value);
	assert freed.ok;
	if (freed.ok) { assert freed.value == 3; }
	assert scene.nodeCount() == 1;
	assert (scene.nodes[scene.root].children.length as int32) == 0;
}

test "an id that named a removed node is refused, not silently reused" {
	let scene: Scene = Scene.create();
	const gone: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 1);
	assert scene.isLive(gone);
	assert remove(scene, gone).ok;
	assert !scene.isLive(gone);
	// The slot comes back under a new generation, and the old id still does not address it.
	const fresh: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 2);
	assert fresh.index == gone.index;
	assert fresh.generation != gone.generation;
	assert !scene.isLive(gone);
	assert scene.isLive(fresh);
	assert setLocal(scene, gone, identityTransform()).ok == false;
}

test "the free list hands slots back in LIFO order" {
	let scene: Scene = Scene.create();
	const first: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 1);
	const second: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 2);
	assert remove(scene, first).ok;
	assert remove(scene, second).ok;
	// `second` was freed last, so it is handed out first.
	const next: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 3);
	assert next.index == second.index;
}

test "the root cannot be removed" {
	let scene: Scene = Scene.create();
	const refused: Result<int32, SceneError> = remove(scene, scene.rootId());
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == SceneError.RootCannotBeRemoved; }
	assert scene.nodeCount() == 1;
}

test "a stale parent is refused rather than adopting the child into a dead slot" {
	let scene: Scene = Scene.create();
	const gone: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 1);
	assert remove(scene, gone).ok;
	const orphan: Result<NodeId, SceneError> = addMeshNode(scene, gone, identityTransform(), 2, 0);
	assert !orphan.ok;
	if (!orphan.ok) { assert orphan.error == SceneError.StaleNode; }
}

test "an empty scene collects nothing and syncs only its root" {
	let scene: Scene = Scene.create();
	let items: Vec<DrawItem> = [];
	assert syncWorld(scene) == 1;
	assert collectDrawList(scene, items) == 0;
	assert (items.length as int32) == 0;
}

// The defect review found this armed and waiting: `refresh` used to return `items.length` and
// never truncate, so a node culled after the list was collected left the previous frame's tail
// in place and drew it again, and un-culling it wrote past the end. Culling deliberately does
// not set `structureChanged` — if it did, the fast path would never be taken.
test "a node culled after collection leaves the list, and does not leave a ghost behind" {
	let scene: Scene = Scene.create();
	const first: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 11);
	const _second: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 22);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 2;
	scene.nodes[first.index].flags = scene.nodes[first.index].flags | FLAG_CULLED;
	assert refresh(scene, items) == 1;
	assert (items.length as int32) == 1;
	assert items[0].mesh == 22;
}

test "un-culling a node puts it back without writing past the end" {
	let scene: Scene = Scene.create();
	const first: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 11);
	const _second: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 22);
	let items: Vec<DrawItem> = [];
	scene.nodes[first.index].flags = scene.nodes[first.index].flags | FLAG_CULLED;
	assert refresh(scene, items) == 1;
	scene.nodes[first.index].flags = scene.nodes[first.index].flags & ~FLAG_CULLED;
	assert refresh(scene, items) == 2;
	assert items[0].mesh == 11;
	assert items[1].mesh == 22;
}

// setMeshOf runs on every campfire frame and had no test at all: its only evidence was pixels.
test "a mesh node can swap which mesh it draws without the structure changing" {
	let scene: Scene = Scene.create();
	const node: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 5);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 1;
	assert items[0].mesh == 5;
	assert setMeshOf(scene, node, 9).ok;
	assert !scene.structureChanged;
	assert refresh(scene, items) == 1;
	assert items[0].mesh == 9;
}

test "setMeshOf refuses a group and refuses a stale id" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	const wrongKind: Result<int32, SceneError> = setMeshOf(scene, group.value, 1);
	assert !wrongKind.ok;
	if (!wrongKind.ok) { assert wrongKind.error == SceneError.NotAMeshNode; }
	const gone: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 1);
	assert remove(scene, gone).ok;
	const stale: Result<int32, SceneError> = setMeshOf(scene, gone, 2);
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == SceneError.StaleNode; }
}

test "a hidden subtree comes back when it is shown again" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	assert addMeshNode(scene, group.value, identityTransform(), 1, 0).ok;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	assert setVisible(scene, group.value, false).ok;
	assert collectDrawList(scene, items) == 0;
	assert setVisible(scene, group.value, true).ok;
	assert collectDrawList(scene, items) == 1;
	assert items[0].mesh == 1;
}

// Sibling order is draw order, so `detach` closes the gap rather than swapping the tail in.
// Removing an only child never exercises that loop; removing the middle one does.
test "removing a middle child keeps its siblings in order" {
	let scene: Scene = Scene.create();
	const _a: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 10);
	const b: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 20);
	const _c: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 30);
	const _d: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 40);
	assert remove(scene, b).ok;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert items[0].mesh == 10;
	assert items[1].mesh == 30;
	assert items[2].mesh == 40;
}

test "a removed subtree leaves the draw list" {
	let scene: Scene = Scene.create();
	const group: Result<NodeId, SceneError> = addGroup(scene, scene.rootId(), identityTransform());
	assert group.ok;
	if (!group.ok) { return; }
	assert addMeshNode(scene, group.value, identityTransform(), 1, 0).ok;
	assert addMeshNode(scene, group.value, identityTransform(), 2, 0).ok;
	const kept: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 3);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert remove(scene, group.value).ok;
	assert refresh(scene, items) == 1;
	assert items[0].mesh == 3;
	assert scene.isLive(kept);
}

test "every guarded entry point refuses a stale id" {
	let scene: Scene = Scene.create();
	const gone: NodeId = oneMesh(scene, vec3(0.0, 0.0, 0.0), 1);
	assert remove(scene, gone).ok;
	assert !addGroup(scene, gone, identityTransform()).ok;
	assert !addMeshNode(scene, gone, identityTransform(), 1, 0).ok;
	assert !setLocal(scene, gone, identityTransform()).ok;
	assert !setVisible(scene, gone, false).ok;
	assert !setMeshOf(scene, gone, 1).ok;
	assert !scene.worldOf(gone).ok;
	assert !remove(scene, gone).ok;
}
