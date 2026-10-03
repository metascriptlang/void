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
//   - a row is addressed by index plus a generation (slots.ms). A silently reused node id in a
//     scene graph is unfindable from the symptom it produces.
import {
	Vec3, vec3, transformDirection, normalized, Quat, identityQuat, Mat4, identity,
	composeTransform, multiplyAffine,
} from "../math/math3d";
import { MAX_POINT_LIGHTS } from "./gpu3d";
import { PassState, passState } from "../gpu/door";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	HandleError,
	pinMesh,
	unpinMesh,
	pinMaterial,
	unpinMaterial,
	tallyMeshPin,
	clearMeshTally,
	tallyMaterialPin,
	clearMaterialTally,
} from "./draw";
import { Slots, LAST_GENERATION, claim, vacate } from "./slots";

export enum NodeFlag {
	Visible,
	PosChanged,
	Culled,
	Pickable,
}

export const NO_NODE_3D: int32 = -1;

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
	NodeNotFound,
	StaleMesh,
	StaleMaterial,
	ForeignMesh,
	ForeignMaterial,
	NotPinned,
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

// A node id is a plain value: its scene's serial, the index, and the generation the slot had when
// it was handed out, so a stale id is caught rather than silently addressing whatever now lives
// in that slot.
export struct NodeId3D {
	scene: int32;
	index: int32;
	generation: int32;
}

export const NO_NODE_ID: NodeId3D = { scene: 0, index: NO_NODE_3D, generation: 0 };

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

// The Mesh side table: what h3d.scene.Mesh carries beyond an Object. Both are ids into the
// DrawContext, so a draw item built from one is a plain value, and the node pins both
// (draw.ms pinMesh) from addMeshNode until remove, as h3d.scene.Mesh increfs its primitive.
export struct MeshInstance {
	mesh: MeshId;
	material: MaterialId;
}

export interface Scene3D {
	serial: int32;
	context: DrawContext;
	nodes: Vec<Object3D>;
	slots: Slots;
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
	closed: boolean;
}

// Bevy's `Transform::IDENTITY` and `Transform::from_translation`.
export function identity(this typeof Transform3D): Transform3D {
	return { position: vec3(0.0, 0.0, 0.0), rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0) };
}

export function fromTranslation(this typeof Transform3D, position: Vec3): Transform3D {
	return { ...Transform3D.identity(), position: position };
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

export function nodeCount(this scene: Scene3D): int32 {
	if (scene.closed) { return 0; }
	return scene.slots.liveCount();
}

// True when `id` still names the node it was handed out for.
export function isLive(this scene: Scene3D, id: NodeId3D): boolean {
	if (scene.closed || id.scene != scene.serial) { return false; }
	return scene.slots.isCurrent(id.index, id.generation);
}

// The id of the node now at `index`.
export function nodeIdAt(this scene: Scene3D, index: int32): NodeId3D {
	return { scene: scene.serial, index: index, generation: scene.slots.generations[index] };
}

export function liveRow(this scene: Scene3D, id: NodeId3D, call: string): int32 {
	if (scene.isLive(id)) { return id.index; }
	return scene.stopOnDeadId(id, call);
}

function stopOnDeadId(this scene: Scene3D, id: NodeId3D, call: string): int32 {
	if (scene.closed) { stopOnClosed(call); }
	const rows: int32 = scene.slots.generations.length as int32;
	if (id.index < 0 || id.index >= rows) {
		console.log(`void3d: ${call} on node id ${id.index}, which names no node of this scene`);
		unreachable;
	}
	if (id.scene != scene.serial) {
		console.log(`void3d: ${call} on node ${id.index} of another scene`);
		unreachable;
	}
	console.log(
		`void3d: ${call} on stale node ${id.index}: the handle has generation ` +
		`${id.generation}, the row ${scene.slots.generations[id.index]}`,
	);
	unreachable;
}

function kindRow(this scene: Scene3D, id: NodeId3D, kind: NodeKind, call: string): int32 {
	const row: int32 = scene.liveRow(id, call);
	if (scene.nodes[row].kind == kind) { return row; }
	return scene.stopOnWrongKind(row, kind, call);
}

function meshError(context: DrawContext, mesh: MeshId): SceneError {
	return context.issuedMesh(mesh) ? SceneError.StaleMesh : SceneError.ForeignMesh;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a scene that was closed`);
	unreachable;
}

function stopOnWrongKind(this scene: Scene3D, row: int32, kind: NodeKind, call: string): int32 {
	console.log(
		`void3d: ${call} asked of a ${scene.nodes[row].kind.toString()} node ${row}; ` +
		`only a ${kind.toString()} node has it`,
	);
	unreachable;
}

function newSlot(scene: Scene3D, node: Object3D): NodeId3D {
	const index: int32 = claim(scene.slots);
	if (index == (scene.nodes.length as int32)) {
		scene.nodes.push(node);
		scene.stack.push(NO_NODE_3D);
	} else {
		scene.nodes[index] = node;
	}
	return scene.nodeIdAt(index);
}

let sceneSerials: int32 = 0;

export function create(this typeof Scene3D, context: DrawContext): Scene3D {
	context.requireOpen("Scene3D.create");
	if (sceneSerials == LAST_GENERATION) {
		console.log("void3d: Scene3D.create has no serial left for a new scene");
		unreachable;
	}
	sceneSerials = sceneSerials + 1;
	let scene: Scene3D = {
		serial: sceneSerials,
		context: context,
		nodes: [],
		slots: Slots.empty(),
		meshes: [],
		lights: [],
		meshOwners: [],
		lightOwners: [],
		lightOrder: [],
		ambientLight: vec3(0.5, 0.5, 0.5),
		stack: [],
		root: NO_NODE_3D,
		structureChanged: true,
		closed: false,
	};
	const root: NodeId3D = newSlot(scene, {
		kind: NodeKind.Group,
		flags: freshFlags(),
		parent: NO_NODE_3D,
		payload: NO_NODE_3D,
		name: "",
		local: Transform3D.identity(),
		world: identity(),
		children: [],
	});
	scene.root = root.index;
	return scene;
}

export function rootId(this scene: Scene3D): NodeId3D {
	return scene.nodeIdAt(scene.root);
}

// Adds an empty group under `parent`. Structure changed, so the draw list is rebuilt next collect.
export function addGroup(scene: Scene3D, parent: NodeId3D, local: Transform3D): NodeId3D {
	const under: int32 = scene.liveRow(parent, "addGroup");
	const id: NodeId3D = newSlot(scene, {
		kind: NodeKind.Group,
		flags: freshFlags(),
		parent: under,
		payload: NO_NODE_3D,
		name: "",
		local: local,
		world: identity(),
		children: [],
	});
	scene.nodes[under].children.push(id.index);
	scene.structureChanged = true;
	return id;
}

// h3d.scene.Mesh: an object that carries a primitive and a material, and holds both.
//
// Named `addMeshNode` rather than Heaps' `Mesh`, because `draw.ms` already exports
// `addMesh(context: DrawContext, ...)` and two free functions with one name collide: with a `ref`
// first parameter on both the call ran the wrong one silently, with a value one it is refused
// (`out/tmp/overload`, `out/tmp/overload/value`). The compiler card
// `2026-09-20-ref-receiver-not-an-extension.md` lists this as a site to rename back.
// PENDING3D: mesh-node-name-collision
export function addMeshNode(
	scene: Scene3D,
	parent: NodeId3D,
	local: Transform3D,
	mesh: MeshId,
	material: MaterialId,
): Result<NodeId3D, SceneError> {
	const under: int32 = scene.liveRow(parent, "addMeshNode");
	const context: DrawContext = scene.context;
	if (!context.hasMesh(mesh)) { return Result.err(meshError(context, mesh)); }
	if (!context.hasMaterial(material)) {
		const issued: boolean = context.issuedMaterial(material);
		return Result.err(issued ? SceneError.StaleMaterial : SceneError.ForeignMaterial);
	}
	const pinnedMesh: Result<int32, HandleError> = pinMesh(context, mesh);
	const pinnedMaterial: Result<int32, HandleError> = pinMaterial(context, material);
	if (!pinnedMesh.ok || !pinnedMaterial.ok) { unreachable; }
	const payload: int32 = scene.meshes.length as int32;
	scene.meshes.push({ mesh: mesh, material: material });
	const id: NodeId3D = newSlot(scene, {
		kind: NodeKind.Mesh,
		flags: freshFlags(),
		parent: under,
		payload: payload,
		name: "",
		local: local,
		world: identity(),
		children: [],
	});
	scene.meshOwners.push(id.index);
	scene.nodes[under].children.push(id.index);
	scene.structureChanged = true;
	return Result.ok(id);
}

// h3d.scene.Light: an object whose payload is a light rather than a drawable. Named with the
// Node suffix for the same reason as `addMeshNode` (the compiler card above).
export function addLightNode(
	scene: Scene3D,
	parent: NodeId3D,
	local: Transform3D,
	light: LightInstance,
): NodeId3D {
	const under: int32 = scene.liveRow(parent, "addLightNode");
	const payload: int32 = scene.lights.length as int32;
	scene.lights.push(light);
	const id: NodeId3D = newSlot(scene, {
		kind: NodeKind.Light,
		flags: freshFlags(),
		parent: under,
		payload: payload,
		name: "",
		local: local,
		world: identity(),
		children: [],
	});
	scene.lightOwners.push(id.index);
	scene.nodes[under].children.push(id.index);
	scene.structureChanged = true;
	return id;
}

function detach(scene: Scene3D, index: int32): void {
	const parent: int32 = scene.nodes[index].parent;
	if (parent == NO_NODE_3D) { return; }
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

// A mesh node unpins its mesh and material; remove checked the pins first (checkPins). A freed id
// holds no pin: whoever freed it took the node's.
function releasePayload(scene: Scene3D, index: int32): void {
	const context: DrawContext = scene.context;
	const row: int32 = scene.nodes[index].payload;
	match (scene.nodes[index].kind) {
		NodeKind.Mesh => {
			const instance: MeshInstance = scene.meshes[row];
			if (context.hasMesh(instance.mesh) && !unpinMesh(context, instance.mesh).ok) {
				unreachable;
			}
			const material: MaterialId = instance.material;
			if (context.hasMaterial(material) && !unpinMaterial(context, material).ok) {
				unreachable;
			}
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
	scene.nodes[index].payload = NO_NODE_3D;
}

// `index` and every node under it into scene.stack, parents before children; answers how many.
function collectSubtree(scene: Scene3D, index: int32): int32 {
	scene.stack[0] = index;
	let read: int32 = 0;
	let written: int32 = 1;
	while (read < written) {
		const at: int32 = scene.stack[read];
		read = read + 1;
		for (const child of scene.nodes[at].children) {
			scene.stack[written] = child;
			written = written + 1;
		}
	}
	return written;
}

// Every live mesh and material of the mesh nodes among the first `count` in scene.stack has a pin
// for each node about to let one go.
function checkPins(scene: Scene3D, count: int32): Result<int32, SceneError> {
	const context: DrawContext = scene.context;
	let covered: boolean = true;
	for (let k = 0; k < count; k++) {
		const node: int32 = scene.stack[k];
		if (scene.nodes[node].kind != NodeKind.Mesh) { continue; }
		const instance: MeshInstance = scene.meshes[scene.nodes[node].payload];
		if (!tallyMeshPin(context, instance.mesh)) { covered = false; }
		if (!tallyMaterialPin(context, instance.material)) { covered = false; }
	}
	for (let k = 0; k < count; k++) {
		const node: int32 = scene.stack[k];
		if (scene.nodes[node].kind != NodeKind.Mesh) { continue; }
		const instance: MeshInstance = scene.meshes[scene.nodes[node].payload];
		clearMeshTally(context, instance.mesh);
		clearMaterialTally(context, instance.material);
	}
	if (!covered) { return Result.err(SceneError.NotPinned); }
	return Result.ok(count);
}

// Frees `id` and everything under it; their ids go stale (slots.ms), and each mesh node unpins its
// mesh and material. Nothing changes when a pin is gone (checkPins).
export function remove(scene: Scene3D, id: NodeId3D): Result<int32, SceneError> {
	const row: int32 = scene.liveRow(id, "remove");
	if (row == scene.root) {
		console.log("void3d: remove asked of the scene root; removeChildren empties it");
		unreachable;
	}
	const count: int32 = collectSubtree(scene, row);
	const _checked: int32 = try checkPins(scene, count);
	detach(scene, id.index);
	for (let k = 0; k < count; k++) {
		const index: int32 = scene.stack[k];
		scene.nodes[index].children = [];
		scene.nodes[index].parent = NO_NODE_3D;
		releasePayload(scene, index);
		vacate(scene.slots, index);
	}
	scene.structureChanged = true;
	return Result.ok(count);
}

// h3d.scene.Object.removeChildren: every node under `id` goes, and `id` stays.
export function removeChildren(scene: Scene3D, id: NodeId3D): Result<int32, SceneError> {
	const row: int32 = scene.liveRow(id, "removeChildren");
	let removed: int32 = 0;
	while ((scene.nodes[row].children.length as int32) > 0) {
		const child: NodeId3D = scene.nodeIdAt(scene.nodes[row].children[0]);
		removed = removed + (try remove(scene, child));
	}
	return Result.ok(removed);
}

// Heaps' `posChanged`: writing a transform marks only this node, and the descent propagates it.
export function setLocal(scene: Scene3D, id: NodeId3D, local: Transform3D): void {
	const row: int32 = scene.liveRow(id, "setLocal");
	scene.nodes[row].local = local;
	scene.nodes[row].flags = scene.nodes[row].flags.incl(NodeFlag.PosChanged);
}

export function setVisible(scene: Scene3D, id: NodeId3D, visible: boolean): void {
	const row: int32 = scene.liveRow(id, "setVisible");
	const flags: BitSet<NodeFlag> = scene.nodes[row].flags;
	scene.nodes[row].flags = visible ?
		flags.incl(NodeFlag.Visible) :
		flags.excl(NodeFlag.Visible);
	// Visibility does not move anything, so the world matrices stay valid; only the draw list
	// changes, and `collect` reads the flag as it walks.
	scene.structureChanged = true;
}

// h3d.scene.Interactive cut to a flag: a pickable node owns every hit on the meshes under it.
export function setPickable(scene: Scene3D, id: NodeId3D, pickable: boolean): void {
	const row: int32 = scene.liveRow(id, "setPickable");
	const flags: BitSet<NodeFlag> = scene.nodes[row].flags;
	scene.nodes[row].flags = pickable ?
		flags.incl(NodeFlag.Pickable) :
		flags.excl(NodeFlag.Pickable);
}

// The node pins `mesh` and unpins the one it showed, unless that one was freed already; pinning
// first keeps a mesh swapped for itself alive.
export function setMeshOf(scene: Scene3D, id: NodeId3D, mesh: MeshId): Result<int32, SceneError> {
	const node: int32 = scene.kindRow(id, NodeKind.Mesh, "setMeshOf");
	const context: DrawContext = scene.context;
	const row: int32 = scene.nodes[node].payload;
	const shown: MeshId = scene.meshes[row].mesh;
	const holds: boolean = context.hasMesh(shown);
	if (holds && context.meshPinned(shown) < 1) { return Result.err(SceneError.NotPinned); }
	if (!pinMesh(context, mesh).ok) { return Result.err(meshError(context, mesh)); }
	if (holds && !unpinMesh(context, shown).ok) { unreachable; }
	scene.meshes[row].mesh = mesh;
	return Result.ok(node);
}

// The flicker path: power moves every few frames, and `collectLights` re-reads it, so nothing
// else needs to hear about the change.
export function setLightPower(scene: Scene3D, id: NodeId3D, power: float32): void {
	const node: int32 = scene.kindRow(id, NodeKind.Light, "setLightPower");
	scene.lights[scene.nodes[node].payload].power = power;
}

export function setAmbient(scene: Scene3D, ambient: Vec3): void {
	if (scene.closed) { stopOnClosed("setAmbient"); }
	scene.ambientLight = ambient;
}

export function setName(scene: Scene3D, id: NodeId3D, name: string): void {
	const row: int32 = scene.liveRow(id, "setName");
	scene.nodes[row].name = name;
}

export function nameOf(this scene: Scene3D, id: NodeId3D): Result<string, SceneError> {
	if (!scene.isLive(id)) { return Result.err(SceneError.StaleNode); }
	return Result.ok(scene.nodes[id.index].name);
}

// h3d.scene.Object.getObjectByName: self first, then children in order, depth-first. A miss is
// an error rather than a null id, so a caller cannot quietly address the root by accident.
export function findByName(
	this scene: Scene3D,
	from: NodeId3D,
	name: string,
): Result<NodeId3D, SceneError> {
	if (!scene.isLive(from)) { return Result.err(SceneError.StaleNode); }
	const stack: Vec<int32> = [from.index];
	while ((stack.length as int32) > 0) {
		const last: int32 = (stack.length as int32) - 1;
		const index: int32 = stack[last];
		stack.pop();
		if (scene.nodes[index].name == name) {
			return Result.ok(scene.nodeIdAt(index));
		}
		const count: int32 = scene.nodes[index].children.length as int32;
		for (let i = count - 1; i >= 0; i--) {
			stack.push(scene.nodes[index].children[i]);
		}
	}
	return Result.err(SceneError.NodeNotFound);
}

export function worldOf(this scene: Scene3D, id: NodeId3D): Result<Mat4, SceneError> {
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
export function syncWorld(scene: Scene3D): int32 {
	if (scene.closed) { stopOnClosed("syncWorld"); }
	if (scene.root == NO_NODE_3D) { return 0; }
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
			const parentWorld: Mat4 = parent == NO_NODE_3D ? identity() : scene.nodes[parent].world;
			scene.nodes[index].world =
				parent == NO_NODE_3D ? local : local.multiplyAffine(parentWorld);
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
export function collectDrawList(scene: Scene3D, ref items: Vec<DrawItem>): int32 {
	if (scene.closed) { stopOnClosed("collectDrawList"); }
	// Emptied by popping rather than by `items = []`, which would hand back a fresh array and
	// drop the capacity this list already has. Collect runs only on a structural change, but
	// keeping it allocation-free means the claim does not depend on how often that is.
	while ((items.length as int32) > 0) { items.pop(); }
	if (scene.root == NO_NODE_3D) { return 0; }
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
export function refresh(scene: Scene3D, ref items: Vec<DrawItem>): int32 {
	if (scene.closed) { stopOnClosed("refresh"); }
	if (scene.root == NO_NODE_3D) { return 0; }
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
export function collectLights(scene: Scene3D, out: Span<float32>): Result<int32, LightError> {
	if (scene.closed) { stopOnClosed("collectLights"); }
	const _synced: int32 = syncWorld(scene);
	for (let i = 0; i < (out.length as int32); i++) { out[i] = 0.0; }
	out[0] = scene.ambientLight.x;
	out[1] = scene.ambientLight.y;
	out[2] = scene.ambientLight.z;
	while ((scene.lightOrder.length as int32) > 0) { scene.lightOrder.pop(); }
	let seenDirectional: boolean = false;
	if (scene.root != NO_NODE_3D) {
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

export function closeScene(scene: Scene3D): void {
	if (scene.closed) { stopOnClosed("closeScene"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeScene with a pass open; endPass ends it");
		unreachable;
	}
	const removed: Result<int32, SceneError> = removeChildren(scene, scene.rootId());
	if (!removed.ok) {
		const error: string = removed.error.toString();
		console.log(`void3d: closeScene found a node's mesh or material ${error}`);
		unreachable;
	}
	scene.closed = true;
	scene.structureChanged = true;
}

export function isClosed(this scene: Scene3D): boolean {
	return scene.closed;
}

export function requireOpen(this scene: Scene3D, call: string): void {
	if (scene.closed) { stopOnClosed(call); }
}
