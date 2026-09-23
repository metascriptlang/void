import { Vec3, vec3, eulerQuat, translation, scaling, identity } from "../math/math3d";
import { Bounds } from "../void3d/bounds";
import { MeshData, Rgba, addBox, addPlane, addVertex, addTriangle } from "../void3d/meshData";
import { Material, Phase } from "../void3d/material";
import { RenderState, Face } from "../void3d/pass";
import { Program } from "../void3d/gpu3d";
import { Ray } from "../void3d/ray";
import {
	Scene,
	NodeId,
	Transform3D,
	NO_NODE,
	identityTransform,
	transformAt,
	addGroup,
	addMeshNode,
	setName,
	setLocal,
	setVisible,
	setPickable,
} from "../void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	update,
	bindMeshFrames,
	syncMeshFrame,
} from "../void3d/animation";
import { PickHit, PickError, pickNearest } from "../void3d/pick";
import { OrthoCamera, CameraView, CameraBasis } from "../void3d/camera";
import { LowResView, lowResView } from "../void3d/blit";
import { approx } from "./helpers";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const UNCULLED: int32 = 0;
const BACK_CULLED: int32 = 1;
const NO_ID: NodeId = { index: NO_NODE, generation: 0 };
const NO_HIT: PickHit = {
	owner: NO_ID,
	mesh: NO_ID,
	distance: -1.0,
	point: { x: 0.0, y: 0.0, z: 0.0 },
};

// Typed defaults for `try … catch`: a struct literal there fails in clang
// (~/metascript/.inbox/compiler/2026-09-23-catch-struct-literal-clang.md).
const NO_LOW_RES: LowResView = { width: 0, height: 0, scale: 0, offsetX: 0.0, offsetY: 0.0 };
const NO_BASIS: CameraBasis = {
	right: vec3(0.0, 0.0, 0.0),
	up: vec3(0.0, 0.0, 0.0),
	forward: vec3(0.0, 0.0, 0.0),
};
const NO_VIEW: CameraView = {
	eye: vec3(0.0, 0.0, 0.0),
	basis: NO_BASIS,
	viewProj: identity(),
	remainderX: 0.0,
	remainderY: 0.0,
	texelWidth: 0,
	texelHeight: 0,
	worldPerTexel: 0.0,
};

function nearVec(a: Vec3, b: Vec3): boolean {
	return approx(a.x, b.x) && approx(a.y, b.y) && approx(a.z, b.z);
}

function down(x: float32, z: float32): Ray {
	return { origin: vec3(x, 10.0, z), direction: vec3(0.0, -1.0, 0.0) };
}

function materials(): Vec<Material> {
	const state: RenderState = RenderState.defaults();
	return [
		Material.plain(Program.Lit, state.withCulling(Face.None), Phase.Opaque),
		Material.plain(Program.Lit, state.withCulling(Face.Back), Phase.Opaque),
		Material.plain(Program.Lit, state.withCulling(Face.Front), Phase.Opaque),
	];
}

// A unit box standing on the origin: top at y = 1, sides at +-0.5.
function unitBox(): MeshData {
	let data: MeshData = MeshData.empty();
	const _box: int32 = try addBox(data, {
		base: vec3(0.0, 0.0, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.0,
		tilt: 0.0,
		color: WHITE,
	}) catch -1;
	return data;
}

// One triangle in the z = `depth` plane, counter-clockwise seen from +z.
function facingPlusZ(depth: float32): MeshData {
	let data: MeshData = MeshData.empty();
	const up: Vec3 = vec3(0.0, 0.0, 1.0);
	const a: int32 = try addVertex(data, vec3(-1.0, -1.0, depth), up, WHITE) catch 0;
	const b: int32 = try addVertex(data, vec3(1.0, -1.0, depth), up, WHITE) catch 0;
	const c: int32 = try addVertex(data, vec3(0.0, 1.0, depth), up, WHITE) catch 0;
	const _t: int32 = try addTriangle(data, a, b, c) catch 0;
	return data;
}

function meshNode(ref scene: Scene, parent: NodeId, at: Transform3D, mesh: int32): NodeId {
	return try addMeshNode(scene, parent, at, mesh, UNCULLED) catch NO_ID;
}

function pickable(ref scene: Scene, id: NodeId): NodeId {
	const _marked: int32 = try setPickable(scene, id, true) catch -1;
	return id;
}

function pickOf(ref scene: Scene, meshes: Span<MeshData>, ray: Ray): PickHit {
	const table: Vec<Material> = materials();
	return try pickNearest(scene, meshes, table, ray) catch NO_HIT;
}

function sameId(a: NodeId, b: NodeId): boolean {
	return a.index == b.index && a.generation == b.generation;
}

// ---- h3d.col.Ray ---------------------------------------------------------------------------

test "a ray from two points has a unit direction, and its point at a distance lies on it" {
	const ray: Ray = Ray.fromPoints(vec3(1.0, 2.0, 3.0), vec3(1.0, 2.0, -5.0));
	assert nearVec(ray.direction, vec3(0.0, 0.0, -1.0));
	assert nearVec(ray.pointAt(4.0), vec3(1.0, 2.0, -1.0));
}

test "a transformed ray moves its origin as a point and keeps a unit direction" {
	const ray: Ray = { origin: vec3(1.0, 0.0, 0.0), direction: vec3(1.0, 0.0, 0.0) };
	const moved: Ray = ray.transformed(scaling(4.0, 1.0, 1.0) * translation(0.0, 3.0, 0.0));
	assert nearVec(moved.origin, vec3(4.0, 3.0, 0.0));
	assert nearVec(moved.direction, vec3(1.0, 0.0, 0.0));
}

// ---- h3d.col.Bounds.rayIntersection ----------------------------------------------------------

test "a box ahead of the ray answers the distance the ray enters it" {
	const box: Bounds = Bounds.fromValues(-1.0, -1.0, -1.0, 2.0, 2.0, 2.0);
	const ray: Ray = { origin: vec3(0.5, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(box.rayIntersection(ray), 4.0);
	const beside: Ray = { ...ray, origin: vec3(3.0, 0.0, 5.0) };
	assert box.rayIntersection(beside) == -1.0;
}

test "a box behind the ray or around its origin answers a negative entry, as in Heaps" {
	const box: Bounds = Bounds.fromValues(-1.0, -1.0, -1.0, 2.0, 2.0, 2.0);
	const away: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, 1.0) };
	assert approx(box.rayIntersection(away), -6.0);
	const inside: Ray = { origin: vec3(0.0, 0.0, 0.5), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(box.rayIntersection(inside), -0.5);
	assert box.contains(inside.origin);
	assert !box.contains(away.origin);
}

test "a ray along a face's plane misses a box it passes beside and hits one it crosses" {
	const box: Bounds = Bounds.fromValues(-1.0, -1.0, -1.0, 2.0, 2.0, 2.0);
	const grazing: Ray = { origin: vec3(1.0, 5.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert box.rayIntersection(grazing) == -1.0;
	const crossing: Ray = { origin: vec3(1.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(box.rayIntersection(crossing), 4.0);
}

// ---- h3d.col.PolygonBuffer.rayIntersection ---------------------------------------------------

test "a triangle is hit from the side the material draws" {
	const data: MeshData = facingPlusZ(0.0);
	const front: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	const back: Ray = { origin: vec3(0.0, 0.0, -5.0), direction: vec3(0.0, 0.0, 1.0) };
	assert approx(data.rayIntersection(front, Face.Back), 5.0);
	assert data.rayIntersection(back, Face.Back) == -1.0;
	assert data.rayIntersection(front, Face.Front) == -1.0;
	assert approx(data.rayIntersection(back, Face.Front), 5.0);
	assert approx(data.rayIntersection(front, Face.None), 5.0);
	assert approx(data.rayIntersection(back, Face.None), 5.0);
}

test "a triangle beside the ray or behind its origin is missed" {
	const data: MeshData = facingPlusZ(0.0);
	const beside: Ray = { origin: vec3(0.9, 0.9, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert data.rayIntersection(beside, Face.None) == -1.0;
	const past: Ray = { origin: vec3(0.0, 0.0, -1.0), direction: vec3(0.0, 0.0, -1.0) };
	assert data.rayIntersection(past, Face.None) == -1.0;
}

test "the nearest triangle is the one answered, whatever the index order" {
	let data: MeshData = facingPlusZ(0.0);
	const up: Vec3 = vec3(0.0, 0.0, 1.0);
	const a: int32 = try addVertex(data, vec3(-1.0, -1.0, 2.0), up, WHITE) catch 0;
	const b: int32 = try addVertex(data, vec3(1.0, -1.0, 2.0), up, WHITE) catch 0;
	const c: int32 = try addVertex(data, vec3(0.0, 1.0, 2.0), up, WHITE) catch 0;
	const _t: int32 = try addTriangle(data, a, b, c) catch 0;
	const ray: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(data.rayIntersection(ray, Face.Back), 3.0);
}

test "every face addBox and addPlane build faces outward" {
	const box: MeshData = unitBox();
	const toward: Vec<Ray> = [
		{ origin: vec3(0.0, 5.0, 0.0), direction: vec3(0.0, -1.0, 0.0) },
		{ origin: vec3(5.0, 0.5, 0.0), direction: vec3(-1.0, 0.0, 0.0) },
		{ origin: vec3(-5.0, 0.5, 0.0), direction: vec3(1.0, 0.0, 0.0) },
		{ origin: vec3(0.0, 0.5, 5.0), direction: vec3(0.0, 0.0, -1.0) },
		{ origin: vec3(0.0, 0.5, -5.0), direction: vec3(0.0, 0.0, 1.0) },
	];
	for (const ray of toward) {
		const outside: float32 = box.rayIntersection(ray, Face.Back);
		assert approx(outside, 4.5) || approx(outside, 4.0);
		assert box.rayIntersection(ray, Face.Front) != outside;
	}
	let ground: MeshData = MeshData.empty();
	const _plane: int32 = try addPlane(ground, 2.0, WHITE) catch -1;
	assert approx(ground.rayIntersection(down(0.5, 0.5), Face.Back), 10.0);
	assert ground.rayIntersection(down(0.5, 0.5), Face.Front) == -1.0;
}

// ---- h3d.scene.Interactive and Scene.rayCastEventTargets -------------------------------------

test "only meshes under a pickable node are hit, and the others do not stand in front" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const upper: NodeId = meshNode(scene, scene.rootId(), transformAt(vec3(0.0, 3.0, 0.0)), 0);
	const lower: NodeId = pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 0));
	const hit: PickHit = pickOf(scene, meshes, down(0.0, 0.0));
	assert sameId(hit.owner, lower);
	assert sameId(hit.mesh, lower);
	assert approx(hit.distance, 9.0);
	assert nearVec(hit.point, vec3(0.0, 1.0, 0.0));
	const _both: NodeId = pickable(scene, upper);
	const top: PickHit = pickOf(scene, meshes, down(0.0, 0.0));
	assert sameId(top.owner, upper);
	assert approx(top.distance, 6.0);
}

test "a hit on a mesh belongs to its nearest pickable ancestor" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const outer: NodeId = pickable(
		scene,
		try addGroup(scene, scene.rootId(), identityTransform()) catch NO_ID,
	);
	const inner: NodeId = pickable(
		scene,
		try addGroup(scene, outer, transformAt(vec3(5.0, 0.0, 0.0))) catch NO_ID,
	);
	const body: NodeId = meshNode(scene, outer, identityTransform(), 0);
	const arm: NodeId = meshNode(scene, inner, identityTransform(), 0);
	const onBody: PickHit = pickOf(scene, meshes, down(0.0, 0.0));
	assert sameId(onBody.owner, outer);
	assert sameId(onBody.mesh, body);
	const onArm: PickHit = pickOf(scene, meshes, down(5.0, 0.0));
	assert sameId(onArm.owner, inner);
	assert sameId(onArm.mesh, arm);
}

test "a mesh under a hidden node is not picked" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const group: NodeId = try addGroup(scene, scene.rootId(), identityTransform()) catch NO_ID;
	const _box: NodeId = pickable(scene, meshNode(scene, group, identityTransform(), 0));
	const _hidden: int32 = try setVisible(scene, group, false) catch -1;
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !missed.ok;
	if (!missed.ok) { assert missed.error == PickError.NothingHit; }
}

test "a turned, scaled and moved node is picked where it is drawn, in world units" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const placed: Transform3D = {
		position: vec3(4.0, 1.0, -2.0),
		rotation: eulerQuat(0.0, 0.7, 0.0),
		scale: vec3(2.0, 3.0, 2.0),
	};
	const box: NodeId = pickable(scene, meshNode(scene, scene.rootId(), placed, 0));
	const hit: PickHit = pickOf(scene, meshes, down(4.0, -2.0));
	assert sameId(hit.owner, box);
	assert approx(hit.distance, 6.0);
	assert nearVec(hit.point, vec3(4.0, 4.0, -2.0));
	const _moved: int32 = try setLocal(scene, box, { ...placed, position: vec3(0.0, 0.0, 0.0) })
		catch -1;
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(4.0, -2.0));
	assert !missed.ok;
}

test "a node scaled to nothing and a mesh with no CPU geometry are never hit" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox(), MeshData.empty()];
	const flat: Transform3D = { ...identityTransform(), scale: vec3(0.0, 0.0, 0.0) };
	const _gone: NodeId = pickable(scene, meshNode(scene, scene.rootId(), flat, 0));
	const _external: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 1));
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !missed.ok;
	if (!missed.ok) { assert missed.error == PickError.NothingHit; }
}

test "a mesh or material index outside the tables is an error, not a miss" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const _beyond: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 7));
	const noMesh: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !noMesh.ok;
	if (!noMesh.ok) { assert noMesh.error == PickError.MeshOutOfRange; }
	let other: Scene = Scene.create();
	const odd: NodeId = try addMeshNode(other, other.rootId(), identityTransform(), 0, 9)
		catch NO_ID;
	const _marked: NodeId = pickable(other, odd);
	const noMaterial: Result<PickHit, PickError> =
		pickNearest(other, meshes, materials(), down(0.0, 0.0));
	assert !noMaterial.ok;
	if (!noMaterial.ok) { assert noMaterial.error == PickError.MaterialOutOfRange; }
}

test "the pick keeps the faces the material draws, turned over by a mirroring node" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [facingPlusZ(0.0)];
	const front: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	const plain: NodeId =
		try addMeshNode(scene, scene.rootId(), identityTransform(), 0, BACK_CULLED) catch NO_ID;
	const _marked: NodeId = pickable(scene, plain);
	assert sameId(pickOf(scene, meshes, front).owner, plain);
	const mirrored: Transform3D = { ...identityTransform(), scale: vec3(-1.0, 1.0, 1.0) };
	const _flipped: int32 = try setLocal(scene, plain, mirrored) catch -1;
	const missed: Result<PickHit, PickError> = pickNearest(scene, meshes, materials(), front);
	assert !missed.ok;
	const behind: Ray = { origin: vec3(0.0, 0.0, -5.0), direction: vec3(0.0, 0.0, 1.0) };
	assert sameId(pickOf(scene, meshes, behind).owner, plain);
}

// Heaps never sets checkInside on a getCollider() shape, so it misses this ray.
test "a ray starting inside a mesh's bounds still reaches its triangles" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const box: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 0));
	const up: Ray = { origin: vec3(0.0, 0.5, 0.0), direction: vec3(0.0, 1.0, 0.0) };
	const inside: PickHit = pickOf(scene, meshes, up);
	assert sameId(inside.owner, box);
	assert approx(inside.distance, 0.5);
}

// Heaps sorts by distance from camera.pos. This camera's eye is its target, mid depth range,
// so the farther mesh here would be the closer one to the eye.
test "the nearest hit is measured from the ray's origin, not from the camera's eye" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [facingPlusZ(0.5), facingPlusZ(-0.3)];
	const nearer: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 0));
	const _farther: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 1));
	const ray: Ray = { origin: vec3(0.0, 0.0, 50.0), direction: vec3(0.0, 0.0, -1.0) };
	const hit: PickHit = pickOf(scene, meshes, ray);
	assert sameId(hit.owner, nearer);
	assert approx(hit.distance, 49.5);
}

test "a hidden mesh under a visible pickable node is not picked" {
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const model: NodeId = pickable(
		scene,
		try addGroup(scene, scene.rootId(), identityTransform()) catch NO_ID,
	);
	const part: NodeId = meshNode(scene, model, identityTransform(), 0);
	assert sameId(pickOf(scene, meshes, down(0.0, 0.0)).owner, model);
	const _hidden: int32 = try setVisible(scene, part, false) catch -1;
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !missed.ok;
}

test "a baked frame swapped in by its animation is the geometry picked" {
	let scene: Scene = Scene.create();
	let moved: MeshData = MeshData.empty();
	const _shifted: int32 = try addBox(moved, {
		base: vec3(5.0, 0.0, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.0,
		tilt: 0.0,
		color: WHITE,
	}) catch -1;
	const meshes: Vec<MeshData> = [unitBox(), moved];
	const pet: NodeId = pickable(scene, meshNode(scene, scene.rootId(), identityTransform(), 0));
	const _named: int32 = try setName(scene, pet, "body") catch -1;
	const frames: Vec<int32> = [0, 1];
	const clock: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(2, 1.0, Interpolation.Step);
	assert clock.ok;
	if (!clock.ok) { return; }
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(clock.value, "body", frames);
	assert made.ok;
	if (!made.ok) { return; }
	let animation: MeshFrameAnimation = made.value;
	const _bound: int32 = try bindMeshFrames(animation, scene, scene.rootId()) catch -1;
	const _first: int32 = try syncMeshFrame(animation, scene) catch -1;
	assert sameId(pickOf(scene, meshes, down(0.0, 0.0)).owner, pet);
	const _stepped: boolean = try update(animation.clock, 1.0) catch false;
	const _second: int32 = try syncMeshFrame(animation, scene) catch -1;
	const old: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !old.ok;
	assert sameId(pickOf(scene, meshes, down(5.0, 0.0)).owner, pet);
}

// ---- tap to object, end to end through the camera and the blit ---------------------------

test "a framebuffer pixel a box is drawn at picks that box and not its neighbour" {
	const blit: LowResView = try lowResView(1280, 720, 360, 1, 1) catch NO_LOW_RES;
	const texel: float32 = 20.0 / 360.0;
	const camera: OrthoCamera = {
		target: vec3(0.3, 0.0, 0.2),
		yaw: 0.785398,
		pitch: 0.6,
		worldPerTexel: texel,
		nearPlane: -50.0,
		farPlane: 50.0,
		snap: true,
	};
	const resolved: CameraView = try camera.resolve(blit.width, blit.height) catch NO_VIEW;
	const shifted: LowResView = blit.withRemainder(resolved.remainderX, resolved.remainderY, true);
	let scene: Scene = Scene.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const left: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), transformAt(vec3(-3.0, 0.0, 0.0)), 0));
	const right: NodeId =
		pickable(scene, meshNode(scene, scene.rootId(), transformAt(vec3(3.0, 0.0, 1.0)), 0));
	const onLeft: Vec3 = resolved.project(vec3(-3.0, 1.0, 0.0), shifted, true);
	const onRight: Vec3 = resolved.project(vec3(3.0, 1.0, 1.0), shifted, true);
	const tapLeft: Ray = resolved.rayFromScreen(onLeft.x, onLeft.y, shifted, true);
	const tapRight: Ray = resolved.rayFromScreen(onRight.x, onRight.y, shifted, true);
	const hitLeft: PickHit = pickOf(scene, meshes, tapLeft);
	const hitRight: PickHit = pickOf(scene, meshes, tapRight);
	assert sameId(hitLeft.owner, left);
	assert sameId(hitRight.owner, right);
	assert nearVec(hitLeft.point, vec3(-3.0, 1.0, 0.0));
	const between: Vec3 = resolved.project(vec3(0.0, 0.0, 0.0), shifted, true);
	const tapBetween: Ray = resolved.rayFromScreen(between.x, between.y, shifted, true);
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), tapBetween);
	assert !missed.ok;
}
