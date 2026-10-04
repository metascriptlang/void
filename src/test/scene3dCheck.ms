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
	addCameraNode,
	setCameraOf,
	setActiveCamera,
	cameraOf,
	attach,
	insertBefore,
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
	NO_NODE_ID,
} from "../void3d/scene";
import { approx } from "./helpers";
import { contextOf } from "./drawHelpers";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../void3d/camera";

function translationOf(m: Mat4): Vec3 {
	return vec3(m.m41, m.m42, m.m43);
}

function near(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(a.x, x) && approx(a.y, y) && approx(a.z, z);
}

// A mesh node under the root, at `where`. A failure comes back as NO_NODE_3D rather than an
// assert, which only a test block may use; every caller checks the index it gets.
function oneMesh(scene: Scene3D, context: DrawContext, where: Vec3, mesh: int32): NodeId3D {
	const added: Result<NodeId3D, SceneError> = addMeshNode(
		scene,
		scene.rootId(),
		Transform3D.fromTranslation(where),
		context.meshAt(mesh),
		context.materialAt(0),
	);
	return added.ok ? added.value : NO_NODE_ID;
}

test "a new scene is one root group and nothing else" {
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	assert scene.nodeCount() == 1;
	assert scene.root != NO_NODE_3D;
	assert scene.isLive(scene.rootId());
	assert scene.nodes[scene.root].kind == NodeKind.Group;
	assert scene.nodes[scene.root].parent == NO_NODE_3D;
}

test "a child is parented both ways, and the structure is marked" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const child: NodeId3D = oneMesh(scene, context, vec3(1.0, 0.0, 0.0), 7);
	assert scene.nodeCount() == 2;
	assert scene.nodes[child.index].parent == scene.root;
	assert (scene.nodes[scene.root].children.length as int32) == 1;
	assert scene.nodes[scene.root].children[0] == child.index;
	assert scene.structureChanged;
}

test "sync places a child at local times parent, in that order" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.fromTranslation(vec3(10.0, 0.0, 0.0)));
	const child: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
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
	let scene: Scene3D = Scene3D.create(context);
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
	let scene: Scene3D = Scene3D.create(context);
	const _child: NodeId3D = oneMesh(scene, context, vec3(1.0, 0.0, 0.0), 0);
	assert syncWorld(scene) == 2;
	assert syncWorld(scene) == 0;
}

test "moving a parent re-syncs its children and nothing above it" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	const child: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
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
	let scene: Scene3D = Scene3D.create(context);
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
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	const under: Result<NodeId3D, SceneError> =
		addMeshNode(
			scene,
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
	let scene: Scene3D = Scene3D.create(context);
	const _mesh: NodeId3D = oneMesh(scene, context, vec3(3.0, 4.0, 5.0), 1);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 1;
	assert near(translationOf(items[0].world), 3.0, 4.0, 5.0);
}

test "an invisible node takes its whole subtree out of the draw list" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene,
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
	let scene: Scene3D = Scene3D.create(context);
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
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene,
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	assert scene.nodeCount() == 4;
	assert remove(scene, group) == 3;
	assert scene.nodeCount() == 1;
	assert (scene.nodes[scene.root].children.length as int32) == 0;
}

test "an id that named a removed node is not live, and its slot's new id is" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const gone: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 1);
	assert scene.isLive(gone);
	assert remove(scene, gone) > 0;
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
	let scene: Scene3D = Scene3D.create(context);
	const first: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 1);
	const second: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 2);
	assert remove(scene, first) > 0;
	assert remove(scene, second) > 0;
	// `second` was freed last, so it is handed out first.
	const next: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 3);
	assert next.index == second.index;
}

test "an empty scene collects nothing and syncs only its root" {
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(context);
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
	let scene: Scene3D = Scene3D.create(context);
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
	let scene: Scene3D = Scene3D.create(context);
	const node: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 5);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 1;
	assert items[0].mesh.index == 5;
	assert setMeshOf(scene, node, context.meshAt(9)).ok;
	assert !scene.structureChanged;
	assert refresh(scene, items) == 1;
	assert items[0].mesh.index == 9;
}

test "a hidden subtree comes back when it is shown again" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
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
	let scene: Scene3D = Scene3D.create(context);
	const _a: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 10);
	const b: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 20);
	const _c: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 30);
	const _d: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 40);
	assert remove(scene, b) > 0;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert items[0].mesh.index == 10;
	assert items[1].mesh.index == 30;
	assert items[2].mesh.index == 40;
}

test "a removed subtree leaves the draw list" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
		group,
		Transform3D.identity(),
		context.meshAt(1),
		context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene,
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	const kept: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 3);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 3;
	assert remove(scene, group) > 0;
	assert refresh(scene, items) == 1;
	assert items[0].mesh.index == 3;
	assert scene.isLive(kept);
}

test "the questions answer a stale id with an error" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const gone: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 1);
	assert remove(scene, gone) > 0;
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	scene: Scene3D,
	where: Vec3,
	light: LightInstance,
): NodeId3D {
	return addLightNode(scene, scene.rootId(), Transform3D.fromTranslation(where), light);
}

test "a light node is a node whose payload indexes the lights table" {
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	setAmbient(scene, vec3(0.33, 0.36, 0.6));
	const block: Vec<float32> = blockOf();
	assert collectLights(scene, block).ok;
	assert nearAt(block, AMBIENT_AT, 0.33, 0.36, 0.6);
	assert approx(block[DIR_AT + 3], 0.0);
}

test "setLightPower moves what the flicker drives" {
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
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
	let scene: Scene3D = Scene3D.create(context);
	const light: LightInstance = {
		kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 1.0, power: 1.0, priority: 0,
	};
	for (let round = 0; round < 50; round++) {
		const mesh: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), round);
		const lit: NodeId3D = oneLight(scene, vec3(0.0, 0.0, 0.0), light);
		assert remove(scene, mesh) > 0;
		assert remove(scene, lit) > 0;
	}
	assert scene.nodeCount() == 1;
	assert (scene.meshes.length as int32) == 0;
	assert (scene.lights.length as int32) == 0;
	assert (scene.meshOwners.length as int32) == 0;
	assert (scene.lightOwners.length as int32) == 0;
}

test "removing an early mesh node repoints the node whose row moved, and draws the same" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 10);
	const b: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 20);
	const c: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 30);
	assert remove(scene, a) > 0;
	assert (scene.meshes.length as int32) == 2;
	assert scene.meshes[scene.nodes[b.index].payload].mesh.index == 20;
	assert scene.meshes[scene.nodes[c.index].payload].mesh.index == 30;
	assert setMeshOf(scene, c, context.meshAt(31)).ok;
	assert scene.meshes[scene.nodes[b.index].payload].mesh.index == 20;
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 2;
	assert items[0].mesh.index == 20;
	assert items[1].mesh.index == 31;
}

test "removing a subtree gives back every row under it and keeps the rest addressable" {
	let context: DrawContext = contextOf(64, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D =
		addGroup(scene, scene.rootId(), Transform3D.identity());
	assert addMeshNode(
		scene,
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
		group,
		Transform3D.identity(),
		context.meshAt(2),
		context.materialAt(0),
	).ok;
	const kept: NodeId3D = oneMesh(scene, context, vec3(0.0, 0.0, 0.0), 3);
	const keptLight: NodeId3D = oneLight(scene, vec3(1.0, 2.0, 3.0), { ...light, power: 0.75 });
	assert remove(scene, group) > 0;
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

function cameraRequest(): Camera3D {
	return {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 40.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
}

test "a camera binding follows a moving rolled parent through the scene world pass" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const parent: NodeId3D = addGroup(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(1.0, 2.0, 4.0)),
	);
	const camera: NodeId3D = addCameraNode(
		scene, parent, Transform3D.identity(), cameraRequest(),
	);
	const before: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert before.ok;
	if (before.ok) { assert before.value.position == cameraRequest().position; }
	setActiveCamera(scene, camera);
	const plain: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert plain.ok;
	if (plain.ok) { assert plain.value.position == vec3(1.0, 2.0, 4.0); }
	setLocal(scene, parent, {
		...Transform3D.fromTranslation(vec3(3.0, 1.0, 5.0)),
		rotation: eulerQuat(0.0, 0.0, 0.5), scale: vec3(2.0, 4.0, 8.0),
	});
	const moved: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert moved.ok;
	if (moved.ok) {
		assert moved.value.position == vec3(3.0, 1.0, 5.0);
		const basis = moved.value.basisOf();
		assert basis.right.y > 0.4;
		assert Math.abs(basis.right.lengthSquared() - 1.0) < 1e-5;
	}
	setCameraOf(scene, camera, {
		...cameraRequest(), projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: true,
		},
	});
	const changed: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert changed.ok;
	if (changed.ok) {
		const view: Result<CameraView, CameraError> = changed.value.resolve(320, 240);
		assert view.ok;
	}
}

test "a removed active camera reports staleness and never reuses a fresh node's matrix" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const camera: NodeId3D = addCameraNode(
		scene, scene.rootId(), Transform3D.identity(), cameraRequest(),
	);
	setActiveCamera(scene, camera);
	assert remove(scene, camera) == 1;
	assert scene.cameras.length == 0;
	const replacement: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	assert replacement.index == camera.index && replacement.generation != camera.generation;
	const stale: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == CameraError.StaleCameraNode; }
	setActiveCamera(scene, null);
	const fallback: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert fallback.ok;
	if (fallback.ok) { assert fallback.value.position == cameraRequest().position; }
}

test "detached nodes keep their holds but do not draw light or expose a world" {
	const context: DrawContext = contextOf(1, 1);
	const scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(
		scene, null, Transform3D.fromTranslation(vec3(10.0, 0.0, 0.0)),
	);
	const mesh: Result<NodeId3D, SceneError> = addMeshNode(
		scene, group, Transform3D.fromTranslation(vec3(2.0, 0.0, 0.0)),
		context.meshAt(0), context.materialAt(0),
	);
	assert mesh.ok;
	if (!mesh.ok) { return; }
	const light: NodeId3D = addLightNode(
		scene, null, Transform3D.fromTranslation(vec3(3.0, 0.0, 0.0)), {
			kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0),
			radius: 1.0, power: 1.0, priority: 0,
		},
	);
	let items: Vec<DrawItem> = [];
	const _synced: int32 = syncWorld(scene);
	assert collectDrawList(scene, items) == 0;
	assert context.meshPinned(context.meshAt(0)) == 1;
	const detached: Result<Mat4, SceneError> = scene.worldOf(mesh.value);
	assert !detached.ok;
	if (!detached.ok) { assert detached.error == SceneError.DetachedNode; }
	const block: Vec<float32> = blockOf();
	const dark: Result<int32, LightError> = collectLights(scene, block);
	assert dark.ok;
	if (dark.ok) { assert dark.value == 0; }
	attach(scene, scene.rootId(), group);
	attach(scene, scene.rootId(), light);
	assert refresh(scene, items) == 1;
	assert near(translationOf(items[0].world), 12.0, 0.0, 0.0);
	const lit: Result<int32, LightError> = collectLights(scene, block);
	assert lit.ok;
	if (lit.ok) { assert lit.value == 1; }
	assert nearAt(block, POINT_AT, 3.0, 0.0, 0.0);
}

test "moving into a detached parent hides the old world until same-frame attachment" {
	const context: DrawContext = contextOf(1, 1);
	const scene: Scene3D = Scene3D.create(context);
	const first: NodeId3D = addGroup(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(10.0, 0.0, 0.0)),
	);
	const second: NodeId3D = addGroup(
		scene, null, Transform3D.fromTranslation(vec3(20.0, 0.0, 0.0)),
	);
	const mesh: NodeId3D = oneMesh(scene, context, vec3(2.0, 0.0, 0.0), 0);
	attach(scene, first, mesh);
	let items: Vec<DrawItem> = [];
	const _first: int32 = refresh(scene, items);
	assert near(translationOf(items[0].world), 12.0, 0.0, 0.0);
	attach(scene, second, mesh);
	assert refresh(scene, items) == 0;
	const detached: Result<Mat4, SceneError> = scene.worldOf(mesh);
	assert !detached.ok;
	if (!detached.ok) { assert detached.error == SceneError.DetachedNode; }
	assert context.meshPinned(context.meshAt(0)) == 1;
	attach(scene, scene.rootId(), second);
	assert refresh(scene, items) == 1;
	assert near(translationOf(items[0].world), 22.0, 0.0, 0.0);
}

test "same-parent insertBefore changes subtree order without recreating its drawables" {
	const context: DrawContext = contextOf(3, 1);
	const scene: Scene3D = Scene3D.create(context);
	const first: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const second: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const third: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	for (const parent of [first, second, third]) {
		const mesh: int32 = parent == first ? 0 : parent == second ? 1 : 2;
		assert addMeshNode(
			scene, parent, Transform3D.identity(), context.meshAt(mesh), context.materialAt(0),
		).ok;
	}
	let items: Vec<DrawItem> = [];
	const _first: int32 = refresh(scene, items);
	insertBefore(scene, scene.rootId(), third, first);
	assert refresh(scene, items) == 3;
	assert items[0].mesh == context.meshAt(2);
	assert items[1].mesh == context.meshAt(0);
	assert items[2].mesh == context.meshAt(1);
	insertBefore(scene, scene.rootId(), first, first);
	const _same: int32 = refresh(scene, items);
	assert items[0].mesh == context.meshAt(2) && items[1].mesh == context.meshAt(0);
	for (let i = 0; i < 3; i++) { assert context.meshPinned(context.meshAt(i)) == 1; }
}

test "a detached camera refuses and its live mount survives moving between parents" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first: NodeId3D = addGroup(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(1.0, 0.0, 0.0)),
	);
	const second: NodeId3D = addGroup(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(-1.0, 1.0, 0.0)),
	);
	const camera: NodeId3D = addCameraNode(
		scene, null, Transform3D.fromTranslation(vec3(0.0, 0.0, 5.0)), cameraRequest(),
	);
	setActiveCamera(scene, camera);
	const detached: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert !detached.ok;
	if (!detached.ok) { assert detached.error == CameraError.DetachedCameraNode; }
	attach(scene, first, camera);
	const before: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert before.ok;
	if (!before.ok) { return; }
	const firstView: Result<CameraView, CameraError> = before.value.resolve(320, 240);
	assert firstView.ok;
	if (!firstView.ok) { return; }
	attach(scene, second, camera);
	const after: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	assert after.ok;
	if (!after.ok) { return; }
	const secondView: Result<CameraView, CameraError> = after.value.resolve(320, 240);
	assert secondView.ok;
	if (!secondView.ok) { return; }
	assert firstView.value.eye == vec3(1.0, 0.0, 5.0);
	assert secondView.value.eye == vec3(-1.0, 1.0, 5.0);
	assert scene.activeCamera == camera;
}
