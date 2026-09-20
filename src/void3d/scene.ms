// The scene tree, in the role of h3d.scene.Object, h3d.scene.Mesh and h3d.scene.Scene: a
// retained tree of nodes that the renderer never walks. Heaps' `emitRec` fills per-pass object
// lists during its walk; here the walk happens only when the tree's *structure* changes and it
// produces a flat `Vec<DrawItem>`, which is what the renderer consumes (docs/VOID3D.md,
// "Porting rules"). The renderer still works, and is still tested, with no scene at all.
//
// Storage is a plain retained tree rather than columns, because a Hibernal scene is tens of
// objects and at that size layout costs nothing measurable; what is taken from SCENE-SCALE.md
// is how the types are cut, so the tree could move to columns later without changing callers
// (docs/VOID3D.md, "Data types").
//
// Three things are read out of Bevy at `2bddbdfd7` rather than invented here:
//   - children are a contiguous array and there are no sibling links, the same reason the draw
//     list is flat (`bevy_ecs/src/hierarchy.rs:154`, `pub struct Children(Vec<Entity>)`);
//   - descent uses an explicit stack, not firstChild/nextSibling pointer-chasing;
//   - a row is addressed by index plus a generation, with a dense LIFO free list, and a
//     generation that would wrap retires the slot instead of aliasing it silently
//     (`entity/mod.rs:710-755`, `:885-892`). A silently reused node id in a scene graph is
//     unfindable from the symptom it produces.
import { Vec3, vec3, Quat, identityQuat, Mat4, identity, composeTransform, multiplyAffine } from "../math/math3d";
import { DrawItem } from "./draw";

// Flags are bits in an int32 rather than `BitSet<NodeFlag>`, which is what CODE-STYLE section 4
// would otherwise ask for. This is a version floor, not a preference: the installed msc
// (0.2.53) has no BitSet. A reader on 0.2.54+ should check whether it has arrived and replace
// these three constants with an enum and a BitSet field.
export const FLAG_VISIBLE: int32 = 1;
export const FLAG_POS_CHANGED: int32 = 2;
export const FLAG_CULLED: int32 = 4;

export const NO_NODE: int32 = -1;

// The kinds a node can be. `payload` indexes the scene table this names: Mesh -> `meshes`.
// Lights join in M7 and get their own table rather than fields on the node.
export enum NodeKind {
	Group,
	Mesh,
}

export enum SceneError {
	UnknownNode,
	StaleNode,
	SlotsExhausted,
	CycleWouldForm,
}

// h3d.scene.Object's position/rotation/scale, kept as one value struct because every pass that
// reads one reads all three. Heaps stores x/y/z, qRot and scaleX/Y/Z as separate fields on the
// object and allocates `qRot` separately; here the node owns this inline.
export struct Transform3D {
	position: Vec3;
	rotation: Quat;
	scale: Vec3;
}

// A node id is a plain value: index plus the generation the slot had when it was handed out, so
// a stale id is caught rather than silently addressing whatever now lives in that slot.
export struct NodeId {
	index: int32;
	generation: int32;
}

// The opposite of Node2D's 71 fields. Anything only one kind reads belongs in a side table.
export struct Object3D {
	kind: NodeKind;
	flags: int32;
	parent: int32;
	payload: int32;
	local: Transform3D;
	world: Mat4;
	children: Vec<int32>;
}

// The Mesh side table: what h3d.scene.Mesh carries beyond an Object. Both are indices into the
// DrawContext, so a draw item built from one is a plain value.
export struct MeshInstance {
	mesh: int32;
	material: int32;
}

export struct Scene {
	nodes: Vec<Object3D>;
	generations: Vec<int32>;
	retired: Vec<boolean>;
	free: Vec<int32>;
	meshes: Vec<MeshInstance>;
	stack: Vec<int32>;
	root: int32;
	structureChanged: boolean;
}

export function identityTransform(): Transform3D {
	return { position: vec3(0.0, 0.0, 0.0), rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0) };
}

export function at(position: Vec3): Transform3D {
	return { ...identityTransform(), position: position };
}

// The matrix a node's own transform describes, before its parent is applied.
export function toMatrix(this t: Transform3D): Mat4 {
	return composeTransform(t.position, t.rotation, t.scale);
}

export function has(this node: Object3D, flag: int32): boolean {
	return (node.flags & flag) != 0;
}

export function isVisible(this node: Object3D): boolean {
	return node.has(FLAG_VISIBLE) && !node.has(FLAG_CULLED);
}

export function nodeCount(this scene: Scene): int32 {
	return (scene.nodes.length as int32) - (scene.free.length as int32);
}

// True when `id` still names the node it was handed out for.
export function isLive(this scene: Scene, id: NodeId): boolean {
	if (id.index < 0 || id.index >= (scene.nodes.length as int32)) { return false; }
	return scene.generations[id.index] == id.generation;
}

function newSlot(ref scene: Scene, node: Object3D): Result<NodeId, SceneError> {
	const reusable: int32 = scene.free.length as int32;
	if (reusable > 0) {
		// Dense LIFO: the last freed slot is the next handed out.
		const index: int32 = scene.free[reusable - 1];
		scene.free.pop();
		scene.nodes[index] = node;
		return Result.ok({ index: index, generation: scene.generations[index] });
	}
	const index: int32 = scene.nodes.length as int32;
	scene.nodes.push(node);
	scene.generations.push(1);
	scene.retired.push(false);
	scene.stack.push(NO_NODE);
	return Result.ok({ index: index, generation: 1 });
}

export function create(this typeof Scene): Scene {
	let scene: Scene = {
		nodes: [],
		generations: [],
		retired: [],
		free: [],
		meshes: [],
		stack: [],
		root: NO_NODE,
		structureChanged: true,
	};
	const root: Result<NodeId, SceneError> = newSlot(scene, {
		kind: NodeKind.Group,
		flags: FLAG_VISIBLE | FLAG_POS_CHANGED,
		parent: NO_NODE,
		payload: NO_NODE,
		local: identityTransform(),
		world: identity(),
		children: [],
	});
	if (root.ok) { scene.root = root.value.index; }
	return scene;
}

export function rootId(this scene: Scene): NodeId {
	return { index: scene.root, generation: scene.generations[scene.root] };
}

// Adds an empty group under `parent`. Structure changed, so the draw list is rebuilt next collect.
export function addGroup(ref scene: Scene, parent: NodeId, local: Transform3D): Result<NodeId, SceneError> {
	if (!scene.isLive(parent)) { return Result.err(SceneError.StaleNode); }
	const id: NodeId = try newSlot(scene, {
		kind: NodeKind.Group,
		flags: FLAG_VISIBLE | FLAG_POS_CHANGED,
		parent: parent.index,
		payload: NO_NODE,
		local: local,
		world: identity(),
		children: [],
	});
	scene.nodes[parent.index].children.push(id.index);
	scene.structureChanged = true;
	return Result.ok(id);
}

// h3d.scene.Mesh: an object that carries a primitive and a material. Both are DrawContext
// indices, so this node adds exactly one draw item.
//
// Named `addMeshNode` rather than Heaps' `Mesh`, because `draw.ms` already exports
// `addMesh(ref context: DrawContext, ...)` and two `ref`-receiver free functions with one name
// do not merely collide — the compiler resolves the call to whichever won and runs it on the
// wrong type, with no diagnostic. Measured in `out/tmp/overload`; see the compiler card
// `2026-09-20-ref-receiver-not-an-extension.md`, which lists this as a site to rename back.
export function addMeshNode(
	ref scene: Scene,
	parent: NodeId,
	local: Transform3D,
	mesh: int32,
	material: int32,
): Result<NodeId, SceneError> {
	if (!scene.isLive(parent)) { return Result.err(SceneError.StaleNode); }
	const payload: int32 = scene.meshes.length as int32;
	scene.meshes.push({ mesh: mesh, material: material });
	const id: NodeId = try newSlot(scene, {
		kind: NodeKind.Mesh,
		flags: FLAG_VISIBLE | FLAG_POS_CHANGED,
		parent: parent.index,
		payload: payload,
		local: local,
		world: identity(),
		children: [],
	});
	scene.nodes[parent.index].children.push(id.index);
	scene.structureChanged = true;
	return Result.ok(id);
}

function detach(ref scene: Scene, index: int32): void {
	const parent: int32 = scene.nodes[index].parent;
	if (parent == NO_NODE) { return; }
	let siblings: Vec<int32> = scene.nodes[parent].children;
	const count: int32 = siblings.length as int32;
	for (let i = 0; i < count; i++) {
		if (siblings[i] == index) {
			// Order among siblings is draw order, so close the gap rather than swapping the tail in.
			for (let j = i; j < count - 1; j++) { siblings[j] = siblings[j + 1]; }
			siblings.pop();
			break;
		}
	}
	scene.nodes[parent].children = siblings;
}

// Frees `id` and everything under it. The slots go on the free list with their generation bumped;
// a slot whose generation would wrap is retired instead, so an id can never come back aliased.
export function remove(ref scene: Scene, id: NodeId): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	if (id.index == scene.root) { return Result.err(SceneError.UnknownNode); }
	detach(scene, id.index);
	let removed: int32 = 0;
	let top: int32 = 0;
	scene.stack[top] = id.index;
	top = top + 1;
	while (top > 0) {
		top = top - 1;
		const index: int32 = scene.stack[top];
		for (const child of scene.nodes[index].children) {
			scene.stack[top] = child;
			top = top + 1;
		}
		scene.nodes[index].children = [];
		scene.nodes[index].parent = NO_NODE;
		const generation: int32 = scene.generations[index];
		if (generation == 2147483647) {
			// Wrap detected rather than silent: the slot is never handed out again.
			scene.retired[index] = true;
		} else {
			scene.generations[index] = generation + 1;
			scene.free.push(index);
		}
		removed = removed + 1;
	}
	scene.structureChanged = true;
	return Result.ok(removed);
}

// Heaps' `posChanged`: writing a transform marks only this node, and the descent propagates it.
export function setLocal(ref scene: Scene, id: NodeId, local: Transform3D): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	scene.nodes[id.index].local = local;
	scene.nodes[id.index].flags = scene.nodes[id.index].flags | FLAG_POS_CHANGED;
	return Result.ok(id.index);
}

export function setVisible(ref scene: Scene, id: NodeId, visible: boolean): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	const flags: int32 = scene.nodes[id.index].flags;
	scene.nodes[id.index].flags = visible ? (flags | FLAG_VISIBLE) : (flags & ~FLAG_VISIBLE);
	// Visibility does not move anything, so the world matrices stay valid; only the draw list
	// changes, and `collect` reads the flag as it walks.
	scene.structureChanged = true;
	return Result.ok(id.index);
}

export function worldOf(this scene: Scene, id: NodeId): Result<Mat4, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	return Result.ok(scene.nodes[id.index].world);
}

// h3d.scene.Object.syncRec, minus the animation, culling-collider and follow machinery M6 has no
// use for. `calcAbsPos` is `local * parent` in row-vector order, Heaps' `multiply3x4inline`
// (Object.hx:772); the descent propagates `posChanged` to children and clears it on the way down
// (Object.hx:833-841). This is Heaps' shape rather than Bevy's descend-from-the-changed-set,
// because the brief's porting rules ask for Heaps' lazy `posChanged` and because at tens of
// nodes the two cost the same — the bench stage is what would show otherwise.
//
// Allocates nothing: the descent stack is `scene.stack`, sized when nodes were added.
export function sync(ref scene: Scene): int32 {
	if (scene.root == NO_NODE) { return 0; }
	let synced: int32 = 0;
	let top: int32 = 0;
	scene.stack[top] = scene.root;
	top = top + 1;
	while (top > 0) {
		top = top - 1;
		const index: int32 = scene.stack[top];
		const changed: boolean = scene.nodes[index].has(FLAG_POS_CHANGED);
		if (changed) {
			const local: Mat4 = scene.nodes[index].local.toMatrix();
			const parent: int32 = scene.nodes[index].parent;
			scene.nodes[index].world = parent == NO_NODE ? local : local.multiplyAffine(scene.nodes[parent].world);
			scene.nodes[index].flags = scene.nodes[index].flags & ~FLAG_POS_CHANGED;
			synced = synced + 1;
		}
		for (const child of scene.nodes[index].children) {
			if (changed) {
				scene.nodes[child].flags = scene.nodes[child].flags | FLAG_POS_CHANGED;
			}
			scene.stack[top] = child;
			top = top + 1;
		}
	}
	return synced;
}

// The walk h3d's `emitRec` does every frame, done here only when the structure changed. Writes
// into `items`, which the caller owns and keeps, so a steady frame allocates nothing.
export function collect(ref scene: Scene, ref items: Vec<DrawItem>): int32 {
	// Emptied by popping rather than by `items = []`, which would hand back a fresh array and
	// drop the capacity this list already has. Collect runs only on a structural change, but
	// keeping it allocation-free means the claim does not depend on how often that is.
	while ((items.length as int32) > 0) { items.pop(); }
	if (scene.root == NO_NODE) { return 0; }
	let top: int32 = 0;
	scene.stack[top] = scene.root;
	top = top + 1;
	while (top > 0) {
		top = top - 1;
		const index: int32 = scene.stack[top];
		if (!scene.nodes[index].isVisible()) { continue; }
		if (scene.nodes[index].kind == NodeKind.Mesh) {
			const instance: MeshInstance = scene.meshes[scene.nodes[index].payload];
			items.push({ mesh: instance.mesh, material: instance.material, world: scene.nodes[index].world });
		}
		// Children are pushed in reverse so the stack pops them in declaration order: sibling
		// order is draw order, and the draw list is what decides overdraw.
		const children: Vec<int32> = scene.nodes[index].children;
		const count: int32 = children.length as int32;
		for (let i = count - 1; i >= 0; i--) {
			scene.stack[top] = children[i];
			top = top + 1;
		}
	}
	scene.structureChanged = false;
	return items.length as int32;
}

// Each frame: sync the matrices, and rebuild the list only when the structure moved. A steady
// frame with a moving node rewrites `world` in place rather than walking the tree again.
export function refresh(ref scene: Scene, ref items: Vec<DrawItem>): int32 {
	const synced: int32 = sync(scene);
	if (scene.structureChanged) {
		return collect(scene, items);
	}
	if (synced > 0) {
		// The list and the tree are in the same order, so one pass rewrites the matrices.
		let at: int32 = 0;
		let top: int32 = 0;
		scene.stack[top] = scene.root;
		top = top + 1;
		while (top > 0) {
			top = top - 1;
			const index: int32 = scene.stack[top];
			if (!scene.nodes[index].isVisible()) { continue; }
			if (scene.nodes[index].kind == NodeKind.Mesh) {
				items[at].world = scene.nodes[index].world;
				at = at + 1;
			}
			const children: Vec<int32> = scene.nodes[index].children;
			const count: int32 = children.length as int32;
			for (let i = count - 1; i >= 0; i--) {
				scene.stack[top] = children[i];
				top = top + 1;
			}
		}
	}
	return items.length as int32;
}
