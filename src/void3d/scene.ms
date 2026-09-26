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
import {
	Vec3, vec3, transformDirection, normalized, Quat, identityQuat, Mat4, identity,
	composeTransform, multiplyAffine,
} from "../math/math3d";
import { MAX_POINT_LIGHTS } from "./gpu3d";
import { DrawItem } from "./draw";

export enum NodeFlag {
	Visible,
	PosChanged,
	Culled,
	Pickable,
}

export const NO_NODE: int32 = -1;

// The kinds a node can be. `payload` indexes the scene table this names: Mesh -> `meshes`,
// Light -> `lights`.
export enum NodeKind {
	Group,
	Mesh,
	Light,
}

export enum LightKind {
	Directional,
	Point,
}

// What h3d.scene.fwd.Light carries beyond an Object, cut for the toon shader: color and
// priority are Heaps'; `radius` and `power` stand where Heaps' fwd PointLight has `params`
// (constant, linear, quadratic attenuation) and where its DirLight folds intensity into
// color, because the pixel-art preset quantizes a point light's energy before it multiplies
// color, and folding power in would quantize at a different place. The core's are continuous.
// PENDING3D: light-params-divergence
export struct LightInstance {
	kind: LightKind;
	color: Vec3;
	radius: float32;
	power: float32;
	priority: int32;
}

export enum SceneError {
	StaleNode,
	RootCannotBeRemoved,
	NotAMeshNode,
	NotALightNode,
	NodeNotFound,
}

export enum LightError {
	TooManyDirectionalLights,
	TooManyPointLights,
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
	flags: BitSet<NodeFlag>;
	parent: int32;
	payload: int32;
	// h3d.scene.Object.name (default null there, "" here): glTF nodes are name-keyed, and
	// `findByName` is this port's getObjectByName.
	name: string;
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
	lights: Vec<LightInstance>;
	meshOwners: Vec<int32>;
	lightOwners: Vec<int32>;
	// Scratch for collectLights' priority sort; grows only when lights are added.
	lightOrder: Vec<int32>;
	// h3d.scene.Scene lighting.ambient, fwd.LightSystem's default grey.
	ambientLight: Vec3;
	stack: Vec<int32>;
	root: int32;
	structureChanged: boolean;
}

export function identityTransform(): Transform3D {
	return { position: vec3(0.0, 0.0, 0.0), rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0) };
}

export function transformAt(position: Vec3): Transform3D {
	return { ...identityTransform(), position: position };
}

// The matrix a node's own transform describes, before its parent is applied.
export function toMatrix(this t: Transform3D): Mat4 {
	return composeTransform(t.position, t.rotation, t.scale);
}

function freshFlags(): BitSet<NodeFlag> {
	return (0 as BitSet<NodeFlag>).incl(NodeFlag.Visible).incl(NodeFlag.PosChanged);
}

export function isVisible(this node: Object3D): boolean {
	return node.flags.has(NodeFlag.Visible) && !node.flags.has(NodeFlag.Culled);
}

export function nodeCount(this scene: Scene): int32 {
	let retired: int32 = 0;
	for (const gone of scene.retired) {
		if (gone) { retired = retired + 1; }
	}
	return (scene.nodes.length as int32) - (scene.free.length as int32) - retired;
}

// True when `id` still names the node it was handed out for.
export function isLive(this scene: Scene, id: NodeId): boolean {
	if (id.index < 0 || id.index >= (scene.nodes.length as int32)) { return false; }
	return scene.generations[id.index] == id.generation;
}

function newSlot(ref scene: Scene, node: Object3D): NodeId {
	const reusable: int32 = scene.free.length as int32;
	if (reusable > 0) {
		// Dense LIFO: the last freed slot is the next handed out.
		const index: int32 = scene.free[reusable - 1];
		scene.free.pop();
		scene.nodes[index] = node;
		return { index: index, generation: scene.generations[index] };
	}
	const index: int32 = scene.nodes.length as int32;
	scene.nodes.push(node);
	scene.generations.push(1);
	scene.retired.push(false);
	scene.stack.push(NO_NODE);
	return { index: index, generation: 1 };
}

export function create(this typeof Scene): Scene {
	let scene: Scene = {
		nodes: [],
		generations: [],
		retired: [],
		free: [],
		meshes: [],
		lights: [],
		meshOwners: [],
		lightOwners: [],
		lightOrder: [],
		ambientLight: vec3(0.5, 0.5, 0.5),
		stack: [],
		root: NO_NODE,
		structureChanged: true,
	};
	const root: NodeId = newSlot(scene, {
		kind: NodeKind.Group,
		flags: freshFlags(),
		parent: NO_NODE,
		payload: NO_NODE,
		name: "",
		local: identityTransform(),
		world: identity(),
		children: [],
	});
	scene.root = root.index;
	return scene;
}

export function rootId(this scene: Scene): NodeId {
	return { index: scene.root, generation: scene.generations[scene.root] };
}

// Adds an empty group under `parent`. Structure changed, so the draw list is rebuilt next collect.
export function addGroup(
	ref scene: Scene,
	parent: NodeId,
	local: Transform3D,
): Result<NodeId, SceneError> {
	if (!scene.isLive(parent)) { return Result.err(SceneError.StaleNode); }
	const id: NodeId = newSlot(scene, {
		kind: NodeKind.Group,
		flags: freshFlags(),
		parent: parent.index,
		payload: NO_NODE,
		name: "",
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
// PENDING3D: mesh-node-name-collision
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
	const id: NodeId = newSlot(scene, {
		kind: NodeKind.Mesh,
		flags: freshFlags(),
		parent: parent.index,
		payload: payload,
		name: "",
		local: local,
		world: identity(),
		children: [],
	});
	scene.meshOwners.push(id.index);
	scene.nodes[parent.index].children.push(id.index);
	scene.structureChanged = true;
	return Result.ok(id);
}

// h3d.scene.Light: an object whose payload is a light rather than a drawable. Named with the
// Node suffix for the same reason as `addMeshNode` (the compiler card above).
export function addLightNode(
	ref scene: Scene,
	parent: NodeId,
	local: Transform3D,
	light: LightInstance,
): Result<NodeId, SceneError> {
	if (!scene.isLive(parent)) { return Result.err(SceneError.StaleNode); }
	const payload: int32 = scene.lights.length as int32;
	scene.lights.push(light);
	const id: NodeId = newSlot(scene, {
		kind: NodeKind.Light,
		flags: freshFlags(),
		parent: parent.index,
		payload: payload,
		name: "",
		local: local,
		world: identity(),
		children: [],
	});
	scene.lightOwners.push(id.index);
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
			// Order among siblings is draw order, so close the gap rather than
			// swapping the tail in.
			for (let j = i; j < count - 1; j++) { siblings[j] = siblings[j + 1]; }
			siblings.pop();
			break;
		}
	}
	scene.nodes[parent].children = siblings;
}

function releasePayload(ref scene: Scene, index: int32): void {
	const row: int32 = scene.nodes[index].payload;
	match (scene.nodes[index].kind) {
		NodeKind.Mesh => {
			const last: int32 = (scene.meshes.length as int32) - 1;
			const mover: int32 = scene.meshOwners[last];
			scene.meshes[row] = scene.meshes[last];
			scene.meshOwners[row] = mover;
			scene.nodes[mover].payload = row;
			scene.meshes.pop();
			scene.meshOwners.pop();
		},
		NodeKind.Light => {
			const last: int32 = (scene.lights.length as int32) - 1;
			const mover: int32 = scene.lightOwners[last];
			scene.lights[row] = scene.lights[last];
			scene.lightOwners[row] = mover;
			scene.nodes[mover].payload = row;
			scene.lights.pop();
			scene.lightOwners.pop();
		},
		NodeKind.Group => {},
	};
	scene.nodes[index].payload = NO_NODE;
}

// Frees `id` and everything under it. The slots go on the free list with their generation bumped;
// a slot whose generation would wrap is retired instead, so an id can never come back aliased.
export function remove(ref scene: Scene, id: NodeId): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	if (id.index == scene.root) { return Result.err(SceneError.RootCannotBeRemoved); }
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
		releasePayload(scene, index);
		const generation: int32 = scene.generations[index];
		if (generation == 2147483647) {
			// Wrap detected rather than silent. Withholding the slot from the free list is only
			// half of it: the generation has to stop matching any id ever issued, or `isLive`
			// keeps answering true for the dead node and every guarded entry point lets a caller
			// through — including adopting a child under it, which would be unreachable from the
			// root forever. Generation 0 is issued by nothing; `newSlot` starts at 1.
			scene.retired[index] = true;
			scene.generations[index] = 0;
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
export function setLocal(
	ref scene: Scene,
	id: NodeId,
	local: Transform3D,
): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	scene.nodes[id.index].local = local;
	scene.nodes[id.index].flags = scene.nodes[id.index].flags.incl(NodeFlag.PosChanged);
	return Result.ok(id.index);
}

export function setVisible(
	ref scene: Scene,
	id: NodeId,
	visible: boolean,
): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	const flags: BitSet<NodeFlag> = scene.nodes[id.index].flags;
	scene.nodes[id.index].flags = visible ?
		flags.incl(NodeFlag.Visible) :
		flags.excl(NodeFlag.Visible);
	// Visibility does not move anything, so the world matrices stay valid; only the draw list
	// changes, and `collect` reads the flag as it walks.
	scene.structureChanged = true;
	return Result.ok(id.index);
}

// h3d.scene.Interactive cut to a flag: a pickable node owns every hit on the meshes under it.
export function setPickable(
	ref scene: Scene,
	id: NodeId,
	pickable: boolean,
): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	const flags: BitSet<NodeFlag> = scene.nodes[id.index].flags;
	scene.nodes[id.index].flags = pickable ?
		flags.incl(NodeFlag.Pickable) :
		flags.excl(NodeFlag.Pickable);
	return Result.ok(id.index);
}

export function setMeshOf(
	ref scene: Scene,
	id: NodeId,
	mesh: int32,
): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	if (scene.nodes[id.index].kind != NodeKind.Mesh) {
		return Result.err(SceneError.NotAMeshNode);
	}
	scene.meshes[scene.nodes[id.index].payload].mesh = mesh;
	return Result.ok(id.index);
}

// The flicker path: power moves every few frames, and `collectLights` re-reads it, so nothing
// else needs to hear about the change.
export function setLightPower(
	ref scene: Scene,
	id: NodeId,
	power: float32,
): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	if (scene.nodes[id.index].kind != NodeKind.Light) {
		return Result.err(SceneError.NotALightNode);
	}
	scene.lights[scene.nodes[id.index].payload].power = power;
	return Result.ok(id.index);
}

export function setAmbient(ref scene: Scene, ambient: Vec3): void {
	scene.ambientLight = ambient;
}

export function setName(ref scene: Scene, id: NodeId, name: string): Result<int32, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	scene.nodes[id.index].name = name;
	return Result.ok(id.index);
}

export function nameOf(this scene: Scene, id: NodeId): Result<string, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	return Result.ok(scene.nodes[id.index].name);
}

// h3d.scene.Object.getObjectByName: self first, then children in order, depth-first. A miss is
// an error rather than a null id, so a caller cannot quietly address the root by accident.
export function findByName(
	this scene: Scene,
	from: NodeId,
	name: string,
): Result<NodeId, SceneError> {
	if (!scene.isLive(from)) { return Result.err(SceneError.StaleNode); }
	const stack: Vec<int32> = [from.index];
	while ((stack.length as int32) > 0) {
		const last: int32 = (stack.length as int32) - 1;
		const index: int32 = stack[last];
		stack.pop();
		if (scene.nodes[index].name == name) {
			return Result.ok({ index: index, generation: scene.generations[index] });
		}
		const count: int32 = scene.nodes[index].children.length as int32;
		for (let i = count - 1; i >= 0; i--) {
			stack.push(scene.nodes[index].children[i]);
		}
	}
	return Result.err(SceneError.NodeNotFound);
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
export function syncWorld(ref scene: Scene): int32 {
	if (scene.root == NO_NODE) { return 0; }
	let synced: int32 = 0;
	let top: int32 = 0;
	scene.stack[top] = scene.root;
	top = top + 1;
	while (top > 0) {
		top = top - 1;
		const index: int32 = scene.stack[top];
		const changed: boolean = scene.nodes[index].flags.has(NodeFlag.PosChanged);
		if (changed) {
			const local: Mat4 = scene.nodes[index].local.toMatrix();
			const parent: int32 = scene.nodes[index].parent;
			const parentWorld: Mat4 = parent == NO_NODE ? identity() : scene.nodes[parent].world;
			scene.nodes[index].world =
				parent == NO_NODE ? local : local.multiplyAffine(parentWorld);
			scene.nodes[index].flags = scene.nodes[index].flags.excl(NodeFlag.PosChanged);
			synced = synced + 1;
		}
		for (const child of scene.nodes[index].children) {
			if (changed) {
				scene.nodes[child].flags = scene.nodes[child].flags.incl(NodeFlag.PosChanged);
			}
			scene.stack[top] = child;
			top = top + 1;
		}
	}
	return synced;
}

// The walk h3d's `emitRec` does every frame, done here only when the structure changed. Writes
// into `items`, which the caller owns and keeps, so a steady frame allocates nothing.
export function collectDrawList(ref scene: Scene, ref items: Vec<DrawItem>): int32 {
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
			items.push({
				mesh: instance.mesh,
				material: instance.material,
				world: scene.nodes[index].world,
			});
		}
		// Children are pushed in reverse so the stack pops them in declaration order: sibling
		// order is draw order, and the draw list is what decides overdraw.
		// Indexed, not copied and not sliced — see the note in `refresh`.
		const count: int32 = scene.nodes[index].children.length as int32;
		for (let i = count - 1; i >= 0; i--) {
			scene.stack[top] = scene.nodes[index].children[i];
			top = top + 1;
		}
	}
	scene.structureChanged = false;
	return items.length as int32;
}

// Each frame: sync the matrices, and rebuild the list only when the structure moved. A steady
// frame with a moving node rewrites `world` in place rather than walking the tree again.
export function refresh(ref scene: Scene, ref items: Vec<DrawItem>): int32 {
	if (scene.root == NO_NODE) { return 0; }
	const _synced: int32 = syncWorld(scene);
	if (scene.structureChanged) {
		return collectDrawList(scene, items);
	}
	// The tree and the list are in the same order, so one pass rewrites every item in place.
	// This runs on every steady frame rather than only when something moved, which is what
	// "the draw list is rebuilt only on structural change; each frame only rewrites world
	// matrices" describes (docs/VOID3D.md, Data types). It allocates nothing.
	{
		let at: int32 = 0;
		let top: int32 = 0;
		scene.stack[top] = scene.root;
		top = top + 1;
		while (top > 0) {
			top = top - 1;
			const index: int32 = scene.stack[top];
			if (!scene.nodes[index].isVisible()) { continue; }
			if (scene.nodes[index].kind == NodeKind.Mesh) {
				const instance: MeshInstance = scene.meshes[scene.nodes[index].payload];
				// The walk can produce more items than the list holds as well as fewer: a node
				// culled since the last collect drops out, and un-culling it puts it back.
				// Writing `items[at]` unconditionally would store past the end in that second
				// case, which is a fault, not a wrong pixel.
				if (at < (items.length as int32)) {
					items[at].world = scene.nodes[index].world;
					items[at].mesh = instance.mesh;
					items[at].material = instance.material;
				} else {
					items.push({
						mesh: instance.mesh,
						material: instance.material,
						world: scene.nodes[index].world,
					});
				}
				at = at + 1;
			}
			// Indexed through the field rather than bound to a local. `const children:
			// Vec<int32> = ...` is CODE-STYLE section 5's copy trap — it emits msArrayCopy plus
			// msArrayDestroy on every visit, measured at 16.42 ms against 2.92 ms over 680 000
			// visits (`out/tmp/copyTrap`) and visible in the emitted C. A `Span` view fixes that
			// but slicing an empty `Vec` yields a null view that faults, and a leaf has no
			// children, so the index is both the cheap form and the safe one. `sync` was already
			// written this way.
			const count: int32 = scene.nodes[index].children.length as int32;
			for (let i = count - 1; i >= 0; i--) {
				scene.stack[top] = scene.nodes[index].children[i];
				top = top + 1;
			}
		}
		// `at` is what this pass actually wrote, and it can be fewer than the list holds: a node
		// culled since the last collect emits no item, and `structureChanged` is deliberately not
		// set for culling or the fast path would never be taken. Returning `items.length` instead
		// would leave the tail of the previous frame in the list and draw it again, and writing
		// past the end when a node becomes visible again would be an out-of-bounds store.
		while ((items.length as int32) > at) { items.pop(); }
		return at;
	}
}

// Fills the renderer's light block from the visible light nodes: ambient first, then the one
// directional slot, then the point slots. `out` is the caller's LIGHT_UNIFORM_LENGTH floats.
// A second visible directional, or a fifth visible point light, is an error rather than a
// silent drop: the block cannot express it, and a shader quietly lighting less is the failure
// this port refuses (fwd.LightSystem sorts by priority and keeps its top N without a word).
// Syncs first, so a light moved this frame is read at its new place whatever called this.
export function collectLights(ref scene: Scene, out: Span<float32>): Result<int32, LightError> {
	const _synced: int32 = syncWorld(scene);
	for (let i = 0; i < (out.length as int32); i++) { out[i] = 0.0; }
	out[0] = scene.ambientLight.x;
	out[1] = scene.ambientLight.y;
	out[2] = scene.ambientLight.z;
	while ((scene.lightOrder.length as int32) > 0) { scene.lightOrder.pop(); }
	let seenDirectional: boolean = false;
	if (scene.root != NO_NODE) {
		let top: int32 = 0;
		scene.stack[top] = scene.root;
		top = top + 1;
		while (top > 0) {
			top = top - 1;
			const index: int32 = scene.stack[top];
			if (!scene.nodes[index].isVisible()) { continue; }
			if (scene.nodes[index].kind == NodeKind.Light) {
				const light: LightInstance = scene.lights[scene.nodes[index].payload];
				if (light.kind == LightKind.Directional) {
					if (seenDirectional) { return Result.err(LightError.TooManyDirectionalLights); }
					seenDirectional = true;
					// fwd.DirLight.emit reads absPos.front() normalized; the shader wants the
					// vector pointing at the light, which is the front vector negated.
					const forward: Vec3 = vec3(0.0, 0.0, 1.0);
					const front: Vec3 = transformDirection(forward, scene.nodes[index].world);
					const toward: Vec3 = front.scaled(-1.0).normalized();
					out[4] = toward.x;
					out[5] = toward.y;
					out[6] = toward.z;
					out[7] = light.power;
					out[8] = light.color.x;
					out[9] = light.color.y;
					out[10] = light.color.z;
				} else {
					scene.lightOrder.push(index);
				}
			}
			const count: int32 = scene.nodes[index].children.length as int32;
			for (let i = count - 1; i >= 0; i--) {
				scene.stack[top] = scene.nodes[index].children[i];
				top = top + 1;
			}
		}
	}
	// Highest priority first, ties keeping declaration order: fwd.LightSystem's sortLight.
	for (let i = 1; i < (scene.lightOrder.length as int32); i++) {
		const held: int32 = scene.lightOrder[i];
		const priority: int32 = scene.lights[scene.nodes[held].payload].priority;
		let j: int32 = i - 1;
		while (j >= 0) {
			const ahead: int32 = scene.lights[scene.nodes[scene.lightOrder[j]].payload].priority;
			if (ahead >= priority) { break; }
			scene.lightOrder[j + 1] = scene.lightOrder[j];
			j = j - 1;
		}
		scene.lightOrder[j + 1] = held;
	}
	const found: int32 = scene.lightOrder.length as int32;
	if (found > MAX_POINT_LIGHTS) { return Result.err(LightError.TooManyPointLights); }
	for (let i = 0; i < found; i++) {
		const index: int32 = scene.lightOrder[i];
		const light: LightInstance = scene.lights[scene.nodes[index].payload];
		const world: Mat4 = scene.nodes[index].world;
		// The block's arrays are sequential, not interleaved: all four pointLight[4], then all
		// four pointColor[4]. Each array is one vec4 per light — packoffset(c3)/packoffset(c7)
		// in the HLSL — so the stride within an array is four floats, not eight.
		const lightAt: int32 = 12 + i * 4;
		const colorAt: int32 = 12 + MAX_POINT_LIGHTS * 4 + i * 4;
		out[lightAt] = world.m41;
		out[lightAt + 1] = world.m42;
		out[lightAt + 2] = world.m43;
		out[lightAt + 3] = light.power;
		out[colorAt] = light.color.x;
		out[colorAt + 1] = light.color.y;
		out[colorAt + 2] = light.color.z;
		out[colorAt + 3] = light.radius;
	}
	out[3] = found as float32;
	return Result.ok(found);
}
