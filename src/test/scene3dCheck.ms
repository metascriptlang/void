import { Vec3, vec3, Mat4, eulerQuat } from "../math/math3d";
import { LIGHT_UNIFORM_LENGTH, MAX_POINT_LIGHTS } from "../void3d/gpu3d";
import { DrawContext, DrawItem } from "../void3d/draw";
import {
	Scene3D,
	NodeId3D,
	NodeKind,
	Transform3D,
	SceneError,
	LightError,
	LightKind,
	LightInstance,
	setMeshOf,
	NodeFlag,
	NO_NODE_3D,
	addGroup,
	addMeshNode,
	addLightNode,
	setLocal,
	setLightPower,
	setAmbient,
	setVisible,
	setName,
	nameOf,
	findByName,
	remove,
	syncWorld,
	collectDrawList,
	collectLights,
	refresh,
} from "../void3d/scene";
import { approx } from "./helpers";
import { contextOf } from "./drawHelpers";

function translationOf(m: Mat4): Vec3 {
	return vec3(m.m41, m.m42, m.m43);
}

function near(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(a.x, x) && approx(a.y, y) && approx(a.z, z);
}

// A mesh node under the root, at `where`. A failure comes back as NO_NODE_3D rather than an
// assert, which only a test block may use; every caller checks the index it gets.
function oneMesh(ref scene: Scene3D, context: DrawContext, where: Vec3, mesh: int32): NodeId3D {
	const added: Result<NodeId3D, SceneError> = addMeshNode(
		scene,
		context,
		scene.rootId(),
		Transform3D.fromTranslation(where),
		context.meshAt(mesh),
		context.materialAt(0),
	);
	return added.ok ? added.value : { index: NO_NODE_3D, generation: 0 };
}

test "a new scene is one root group and nothing else" {
	let scene: Scene3D = Scene3D.create();
	assert scene.nodeCount() == 1;
	assert scene.root != NO_NODE_3D;
	assert scene.isLive(scene.rootId());
	assert scene.nodes[scene.root].kind == NodeKind.Group;
	assert scene.nodes[scene.root].parent == NO_NODE_3D;
}

test "a child is parented both ways, and the structure is marked" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const child: NodeId3D = oneMesh(scene, context, vec3(1.0, 0.0, 0.0), 7);
	assert scene.nodeCount() == 2;
	assert scene.nodes[child.index].parent == scene.root;
	assert (scene.nodes[scene.root].children.length as int32) == 1;
	assert scene.nodes[scene.root].children[0] == child.index;
	assert scene.structureChanged;
}

test "sync places a child at local times parent, in that order" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.fromTranslation(vec3(10.0, 0.0, 0.0)));
	const child: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
			context,
			group,
			Transform3D.fromTranslation(vec3(0.0, 2.0, 0.0)),
			context.meshAt(0),
			context.materialAt(0),
		);
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
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const quarter: float32 = 1.5707963;
	const turned: Transform3D = {
		position: vec3(0.0, 0.0, 0.0),
		rotation: eulerQuat(0.0, quarter, 0.0),
		scale: vec3(1.0, 1.0, 1.0),
	};
	const group: NodeId3D = addGroup(scene, scene.rootId(), turned);
	const child: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
			context,
			group,
			Transform3D.fromTranslation(vec3(1.0, 0.0, 0.0)),
			context.meshAt(0),
			context.materialAt(0),
		);
	assert child.ok;
	if (!child.ok) { return; }
	const _synced: int32 = syncWorld(scene);
	const world: Result<Mat4, SceneError> = scene.worldOf(child.value);
	assert world.ok;
	// A quarter turn about Y takes +X to -Z in this right-handed, Y-up world.
	if (world.ok) { assert near(translationOf(world.value), 0.0, 0.0, -1.0); }
}

test "a synced tree is clean, and syncing again moves nothing" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const _child: NodeId3D = oneMesh(scene, context, vec3(1.0, 0.0, 0.0), 0);
	assert syncWorld(scene) == 2;
	assert syncWorld(scene) == 0;
}

test "moving a parent re-syncs its children and nothing above it" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	const child: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
			context,
			group,
			Transform3D.fromTranslation(vec3(0.0, 1.0, 0.0)),
			context.meshAt(0),
			context.materialAt(0),
		);
	assert child.ok;
	if (!child.ok) { return; }
	assert syncWorld(scene) == 3;
	setLocal(scene, group, Transform3D.fromTranslation(vec3(5.0, 0.0, 0.0)));
	// The group and its one child, and not the root.
	assert syncWorld(scene) == 2;
	const world: Result<Mat4, SceneError> = scene.worldOf(child.value);
	assert world.ok;
	if (world.ok) { assert near(translationOf(world.value), 5.0, 1.0, 0.0); }
}

test "collect emits one item per mesh node, in sibling order" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const _first: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 11);
	const _second: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 22);
	const _third: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 33);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert items[0].mesh.index == 11;
	assert items[1].mesh.index == 22;
	assert items[2].mesh.index == 33;
	assert !scene.structureChanged;
}

test "a group contributes no draw item but its children still do" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	const under: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
			context,
			group,
			Transform3D.identity(),
			context.meshAt(5),
			context.materialAt(0),
		);
	assert under.ok;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	assert items[0].mesh.index == 5;
}

test "collect carries the synced world matrix onto the draw item" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const _mesh: NodeId3D = oneMesh(scene, context, vec3(3.0, 4.0, 5.0), 1);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	assert near(translationOf(items[0].world), 3.0, 4.0, 5.0);
}

test "an invisible node takes its whole subtree out of the draw list" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	const _visible: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 9);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	setVisible(scene, group, false);
	assert collectDrawList(scene, items) == 1;
	assert items[0].mesh.index == 9;
}

test "refresh rewrites world matrices without rebuilding the list" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const moving: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 4);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 1;
	assert !scene.structureChanged;
	setLocal(scene, moving, Transform3D.fromTranslation(vec3(0.0, 8.0, 0.0)));
	assert refresh(scene, items) == 1;
	assert near(translationOf(items[0].world), 0.0, 8.0, 0.0);
	// Still one item, still the same mesh: the structure never changed.
	assert items[0].mesh.index == 4;
	assert !scene.structureChanged;
}

test "removing a node takes its subtree with it and unlinks it from its parent" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	assert scene.nodeCount() == 4;
	const freed: Result<int32, SceneError> = remove(scene, context, group);
	assert freed.ok;
	if (freed.ok) { assert freed.value == 3; }
	assert scene.nodeCount() == 1;
	assert (scene.nodes[scene.root].children.length as int32) == 0;
}

test "an id that named a removed node is not live, and its slot's new id is" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const gone: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 1);
	assert scene.isLive(gone);
	assert remove(scene, context, gone).ok;
	assert !scene.isLive(gone);
	// The slot comes back under a new generation, and the old id still does not address it.
	const fresh: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 2);
	assert fresh.index == gone.index;
	assert fresh.generation != gone.generation;
	assert !scene.isLive(gone);
	assert scene.isLive(fresh);
}

test "the free list hands slots back in LIFO order" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const first: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 1);
	const second: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 2);
	assert remove(scene, context, first).ok;
	assert remove(scene, context, second).ok;
	// `second` was freed last, so it is handed out first.
	const next: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 3);
	assert next.index == second.index;
}

test "an empty scene collects nothing and syncs only its root" {
	let scene: Scene3D = Scene3D.create();
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
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const first: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 11);
	const _second: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 22);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 2;
	scene.nodes[first.index].flags = scene.nodes[first.index].flags.incl(NodeFlag.Culled);
	assert refresh(scene, items) == 1;
	assert (items.length as int32) == 1;
	assert items[0].mesh.index == 22;
}

test "un-culling a node puts it back without writing past the end" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const first: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 11);
	const _second: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 22);
	let items: Vec<DrawItem> = [];
	scene.nodes[first.index].flags = scene.nodes[first.index].flags.incl(NodeFlag.Culled);
	assert refresh(scene, items) == 1;
	scene.nodes[first.index].flags = scene.nodes[first.index].flags.excl(NodeFlag.Culled);
	assert refresh(scene, items) == 2;
	assert items[0].mesh.index == 11;
	assert items[1].mesh.index == 22;
}

// setMeshOf runs on every campfire frame and had no test at all: its only evidence was pixels.
test "a mesh node can swap which mesh it draws without the structure changing" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 5);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 1;
	assert items[0].mesh.index == 5;
	assert setMeshOf(scene, context, node, context.meshAt(9)).ok;
	assert !scene.structureChanged;
	assert refresh(scene, items) == 1;
	assert items[0].mesh.index == 9;
}

test "a hidden subtree comes back when it is shown again" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	setVisible(scene, group, false);
	assert collectDrawList(scene, items) == 0;
	setVisible(scene, group, true);
	assert collectDrawList(scene, items) == 1;
	assert items[0].mesh.index == 1;
}

// Sibling order is draw order, so `detach` closes the gap rather than swapping the tail in.
// Removing an only child never exercises that loop; removing the middle one does.
test "removing a middle child keeps its siblings in order" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const _a: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 10);
	const b: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 20);
	const _c: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 30);
	const _d: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 40);
	assert remove(scene, context, b).ok;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert items[0].mesh.index == 10;
	assert items[1].mesh.index == 30;
	assert items[2].mesh.index == 40;
}

test "a removed subtree leaves the draw list" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	const kept: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 3);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert remove(scene, context, group).ok;
	assert refresh(scene, items) == 1;
	assert items[0].mesh.index == 3;
	assert scene.isLive(kept);
}

test "the questions answer a stale id with an error" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const gone: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 1);
	assert remove(scene, context, gone).ok;
	const world: Result<Mat4, SceneError> = scene.worldOf(gone);
	assert !world.ok;
	if (!world.ok) { assert world.error == SceneError.StaleNode; }
	const name: Result<string, SceneError> = scene.nameOf(gone);
	assert !name.ok;
	if (!name.ok) { assert name.error == SceneError.StaleNode; }
	const found: Result<NodeId3D, SceneError> = scene.findByName(gone, "x");
	assert !found.ok;
	if (!found.ok) { assert found.error == SceneError.StaleNode; }
	assert !scene.findByName(scene.rootId(), "x").ok;
}

// ---- names, in the role of h3d.scene.Object.name / getObjectByName ----

test "findByName walks self first, then children in order" {
	let scene: Scene3D = Scene3D.create();
	const root: NodeId3D = scene.rootId();
	const _a: NodeId3D = addGroup(scene, root, Transform3D.identity());
	const b: NodeId3D = addGroup(scene, root, Transform3D.identity());
	const _c: NodeId3D = addGroup(scene, b, Transform3D.identity());
	setName(scene, b, "arm");
	setName(scene, root, "root");
	const named: Result<NodeId3D, SceneError> = scene.findByName(root, "arm");
	assert named.ok;
	if (named.ok) { assert named.value.index == b.index; }
	const missed: Result<NodeId3D, SceneError> = scene.findByName(root, "leg");
	assert !missed.ok;
	if (!missed.ok) { assert missed.error == SceneError.NodeNotFound; }
}

test "a name given twice finds the first in walk order, not the last set" {
	let scene: Scene3D = Scene3D.create();
	const root: NodeId3D = scene.rootId();
	const first: NodeId3D = addGroup(scene, root, Transform3D.identity());
	const second: NodeId3D = addGroup(scene, root, Transform3D.identity());
	setName(scene, second, "twin");
	setName(scene, first, "twin");
	const named: Result<NodeId3D, SceneError> = scene.findByName(root, "twin");
	assert named.ok;
	if (named.ok) { assert named.value.index == first.index; }
	const deep: Result<NodeId3D, SceneError> = scene.findByName(second, "twin");
	assert deep.ok;
	if (deep.ok) { assert deep.value.index == second.index; }
}

test "nameOf reads back what setName wrote, and a fresh node is unnamed" {
	let scene: Scene3D = Scene3D.create();
	const fresh: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	const before: Result<string, SceneError> = scene.nameOf(fresh);
	assert before.ok;
	if (before.ok) { assert before.value == ""; }
	setName(scene, fresh, "pet-body");
	const after: Result<string, SceneError> = scene.nameOf(fresh);
	assert after.ok;
	if (after.ok) { assert after.value == "pet-body"; }
}

// ---- lights, in the role of h3d.scene.Light / fwd.DirLight / fwd.PointLight ----

const AMBIENT_AT: int32 = 0;
const COUNT_AT: int32 = 3;
const DIR_AT: int32 = 4;
const DIR_COLOR_AT: int32 = 8;
const POINT_AT: int32 = 12;
const COLOR_AT: int32 = POINT_AT + MAX_POINT_LIGHTS * 4;
const POINT_STRIDE: int32 = 4;

function blockOf(): Vec<float32> {
	return new Array(LIGHT_UNIFORM_LENGTH);
}

function oneLight(
	ref scene: Scene3D,
	where: Vec3,
	light: LightInstance,
): NodeId3D {
	return addLightNode(scene, scene.rootId(), Transform3D.fromTranslation(where), light);
}

test "a light node is a node whose payload indexes the lights table" {
	let scene: Scene3D = Scene3D.create();
	const light: NodeId3D = oneLight(scene, vec3(1.0, 2.0, 3.0), {
		kind: LightKind.Point,
		color: vec3(1.0, 0.45, 0.16),
		radius: 9.0,
		power: 1.35,
		priority: 0,
	});
	assert scene.nodeCount() == 2;
	assert scene.nodes[light.index].kind == NodeKind.Light;
	assert scene.nodes[light.index].payload == 0;
	assert (scene.lights.length as int32) == 1;
}

function nearAt(block: Vec<float32>, at: int32, x: float32, y: float32, z: float32): boolean {
	return approx(block[at], x) && approx(block[at + 1], y) && approx(block[at + 2], z);
}

test "collectLights writes a point light's world place, color and radius" {
	let scene: Scene3D = Scene3D.create();
	const _light: NodeId3D = oneLight(scene, vec3(1.0, 2.0, 3.0), {
		kind: LightKind.Point,
		color: vec3(1.0, 0.45, 0.16),
		radius: 9.0,
		power: 1.35,
		priority: 0,
	});
	const block: Vec<float32> = blockOf();
	const collected: Result<int32, LightError> = collectLights(scene, block);
	assert collected.ok;
	if (collected.ok) { assert collected.value == 1; }
	assert approx(block[COUNT_AT], 1.0);
	assert nearAt(block, POINT_AT, 1.0, 2.0, 3.0);
	assert approx(block[POINT_AT + 3], 1.35);
	assert nearAt(block, COLOR_AT, 1.0, 0.45, 0.16);
	assert approx(block[COLOR_AT + 3], 9.0);
}

test "a point light under a moved parent carries the parent's place" {
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.fromTranslation(vec3(10.0, 0.0, 0.0)));
	const added: NodeId3D = addLightNode(
		scene,
		group,
		Transform3D.fromTranslation(vec3(0.0, 2.0, 0.0)),
		{
			kind: LightKind.Point,
			color: vec3(1.0, 1.0, 1.0),
			radius: 1.0,
			power: 1.0,
			priority: 0,
		},
	);
	const block: Vec<float32> = blockOf();
	assert collectLights(scene, block).ok;
	assert nearAt(block, POINT_AT, 10.0, 2.0, 0.0);
}

test "a directional light's direction is its front vector negated and normalized" {
	let scene: Scene3D = Scene3D.create();
	const quarter: float32 = 1.5707963;
	const turned: Transform3D =
		{ ...Transform3D.identity(), rotation: eulerQuat(0.0, quarter, 0.0) };
	const added: NodeId3D = addLightNode(scene, scene.rootId(), turned, {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 0.22,
		priority: 100,
	});
	const block: Vec<float32> = blockOf();
	assert collectLights(scene, block).ok;
	assert nearAt(block, DIR_AT, -1.0, 0.0, 0.0);
	assert approx(block[DIR_AT + 3], 0.22);
	assert nearAt(block, DIR_COLOR_AT, 1.0, 1.0, 1.0);
}

test "point lights sort by priority and keep declaration order on ties" {
	let scene: Scene3D = Scene3D.create();
	const _low: NodeId3D = oneLight(scene, vec3(1.0, 0.0, 0.0), {
		kind: LightKind.Point, color: vec3(1.0, 0.0, 0.0), radius: 1.0, power: 1.0, priority: 0,
	});
	const _high: NodeId3D = oneLight(scene, vec3(2.0, 0.0, 0.0), {
		kind: LightKind.Point, color: vec3(0.0, 1.0, 0.0), radius: 1.0, power: 1.0, priority: 5,
	});
	const _tie: NodeId3D = oneLight(scene, vec3(3.0, 0.0, 0.0), {
		kind: LightKind.Point, color: vec3(0.0, 0.0, 1.0), radius: 1.0, power: 1.0, priority: 0,
	});
	const block: Vec<float32> = blockOf();
	const collected: Result<int32, LightError> = collectLights(scene, block);
	assert collected.ok;
	if (collected.ok) { assert collected.value == 3; }
	assert approx(block[POINT_AT], 2.0);
	assert approx(block[POINT_AT + POINT_STRIDE], 1.0);
	assert approx(block[POINT_AT + 2 * POINT_STRIDE], 3.0);
}

test "a light beyond the block's slots is an error, not a silent drop" {
	let scene: Scene3D = Scene3D.create();
	for (let i = 0; i <= MAX_POINT_LIGHTS; i++) {
		const _each: NodeId3D = oneLight(scene, vec3(0.0, 0.0, 0.0), {
			kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 1.0, power: 1.0, priority: 0,
		});
	}
	const block: Vec<float32> = blockOf();
	const collected: Result<int32, LightError> = collectLights(scene, block);
	assert !collected.ok;
	if (!collected.ok) { assert collected.error == LightError.TooManyPointLights; }
}

test "a second directional light is an error" {
	let scene: Scene3D = Scene3D.create();
	const _first: NodeId3D = oneLight(scene, vec3(0.0, 0.0, 0.0), {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 0.2,
		priority: 100,
	});
	const _second: NodeId3D = oneLight(scene, vec3(0.0, 0.0, 0.0), {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 0.2,
		priority: 50,
	});
	const block: Vec<float32> = blockOf();
	const collected: Result<int32, LightError> = collectLights(scene, block);
	assert !collected.ok;
	if (!collected.ok) { assert collected.error == LightError.TooManyDirectionalLights; }
}

test "an invisible light is not collected" {
	let scene: Scene3D = Scene3D.create();
	const light: NodeId3D = oneLight(scene, vec3(1.0, 0.0, 0.0), {
		kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 1.0, power: 1.0, priority: 0,
	});
	setVisible(scene, light, false);
	const block: Vec<float32> = blockOf();
	const collected: Result<int32, LightError> = collectLights(scene, block);
	assert collected.ok;
	if (collected.ok) { assert collected.value == 0; }
	assert approx(block[COUNT_AT], 0.0);
}

test "ambient comes from the scene and zeroed slots mean unlit" {
	let scene: Scene3D = Scene3D.create();
	setAmbient(scene, vec3(0.33, 0.36, 0.6));
	const block: Vec<float32> = blockOf();
	assert collectLights(scene, block).ok;
	assert nearAt(block, AMBIENT_AT, 0.33, 0.36, 0.6);
	assert approx(block[DIR_AT + 3], 0.0);
}

test "setLightPower moves what the flicker drives" {
	let scene: Scene3D = Scene3D.create();
	const light: NodeId3D = oneLight(scene, vec3(0.0, 0.0, 0.0), {
		kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 1.0, power: 1.0, priority: 0,
	});
	setLightPower(scene, light, 1.4);
	const block: Vec<float32> = blockOf();
	assert collectLights(scene, block).ok;
	assert approx(block[POINT_AT + 3], 1.4);
}

// ---- side tables: remove gives rows back ----

test "churning mesh and light nodes keeps both side tables at the live count" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const light: LightInstance = {
		kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 1.0, power: 1.0, priority: 0,
	};
	for (let round = 0; round < 50; round++) {
		const mesh: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), round);
		const lit: NodeId3D = oneLight(scene, vec3(0.0, 0.0, 0.0), light);
		assert remove(scene, context, mesh).ok;
		assert remove(scene, context, lit).ok;
	}
	assert scene.nodeCount() == 1;
	assert (scene.meshes.length as int32) == 0;
	assert (scene.lights.length as int32) == 0;
	assert (scene.meshOwners.length as int32) == 0;
	assert (scene.lightOwners.length as int32) == 0;
}

test "removing an early mesh node repoints the node whose row moved, and draws the same" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const a: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 10);
	const b: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 20);
	const c: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 30);
	assert remove(scene, context, a).ok;
	assert (scene.meshes.length as int32) == 2;
	assert scene.meshes[scene.nodes[b.index].payload].mesh.index == 20;
	assert scene.meshes[scene.nodes[c.index].payload].mesh.index == 30;
	assert setMeshOf(scene, context, c, context.meshAt(31)).ok;
	assert scene.meshes[scene.nodes[b.index].payload].mesh.index == 20;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 2;
	assert items[0].mesh.index == 20;
	assert items[1].mesh.index == 31;
}

test "removing a subtree gives back every row under it and keeps the rest addressable" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	const light: LightInstance = {
		kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 2.0, power: 0.5, priority: 0,
	};
	const _light: NodeId3D = addLightNode(scene, group, Transform3D.identity(), light);
	assert addMeshNode(
		scene,
		context,
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	const kept: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 3);
	const keptLight: NodeId3D = oneLight(scene, vec3(1.0, 2.0, 3.0), { ...light, power: 0.75 });
	assert remove(scene, context, group).ok;
	assert (scene.meshes.length as int32) == 1;
	assert (scene.lights.length as int32) == 1;
	assert scene.meshes[scene.nodes[kept.index].payload].mesh.index == 3;
	setLightPower(scene, keptLight, 0.9);
	const block: Vec<float32> = blockOf();
	const collected: Result<int32, LightError> = collectLights(scene, block);
	assert collected.ok;
	if (collected.ok) { assert collected.value == 1; }
	assert approx(block[POINT_AT + 3], 0.9);
	assert nearAt(block, POINT_AT, 1.0, 2.0, 3.0);
}
