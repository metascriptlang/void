import { Vec3, vec3, eulerQuat, translation, scaling, identity } from "../math/math3d";
import { Bounds3D } from "../void3d/bounds";
import { MeshData, Rgba, addBox, addPlane, addVertex, addTriangle } from "../void3d/meshData";
import { Material, Phase } from "../void3d/material";
import { RenderState, Face } from "../gpu/state";
import { Program } from "../void3d/gpu3d";
import { Ray } from "../void3d/ray";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	NO_NODE_3D,
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
import { Camera3D, ProjectionKind, CameraView, CameraBasis } from "../void3d/camera";
import { LowResView, lowResView } from "../void3d/blit";
import { approx } from "./helpers";
import { contextOf } from "./drawHelpers";
import { DrawContext, MeshId, MaterialId } from "../void3d/draw";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const UNCULLED: int32 = 0;
const BACK_CULLED: int32 = 1;
const FRONT_CULLED: int32 = 2;
const NO_ID: NodeId3D = { index: NO_NODE_3D, generation: 0 };
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
	inverseViewProj: identity(),
	remainderX: 0.0,
	remainderY: 0.0,
	texelWidth: 0,
	texelHeight: 0,
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

function meshNode(
	ref scene: Scene3D,
	ref context: DrawContext,
	parent: NodeId3D,
	at: Transform3D,
	mesh: int32,
): NodeId3D {
	const material: MaterialId = context.materialAt(UNCULLED);
	return try addMeshNode(scene, context, parent, at, context.meshAt(mesh), material) catch NO_ID;
}

function pickable(ref scene: Scene3D, id: NodeId3D): NodeId3D {
	setPickable(scene, id, true);
	return id;
}

function pickOf(ref scene: Scene3D, meshes: Span<MeshData>, ray: Ray): PickHit {
	const table: Vec<Material> = materials();
	return try pickNearest(scene, meshes, table, ray) catch NO_HIT;
}

function sameId(a: NodeId3D, b: NodeId3D): boolean {
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
	const box: Bounds3D = Bounds3D.fromValues(-1.0, -1.0, -1.0, 2.0, 2.0, 2.0);
	const ray: Ray = { origin: vec3(0.5, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(box.rayIntersection(ray), 4.0);
	const beside: Ray = { ...ray, origin: vec3(3.0, 0.0, 5.0) };
	assert box.rayIntersection(beside) == -1.0;
}

test "a box behind the ray or around its origin answers a negative entry, as in Heaps" {
	const box: Bounds3D = Bounds3D.fromValues(-1.0, -1.0, -1.0, 2.0, 2.0, 2.0);
	const away: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, 1.0) };
	assert approx(box.rayIntersection(away), -6.0);
	const inside: Ray = { origin: vec3(0.0, 0.0, 0.5), direction: vec3(0.0, 0.0, -1.0) };
	assert approx(box.rayIntersection(inside), -0.5);
	assert box.contains(inside.origin);
	assert !box.contains(away.origin);
}

test "a ray along a face's plane misses a box it passes beside and hits one it crosses" {
	const box: Bounds3D = Bounds3D.fromValues(-1.0, -1.0, -1.0, 2.0, 2.0, 2.0);
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
	const entered: Vec<float32> = [4.0, 4.5, 4.5, 4.5, 4.5];
	const leftBy: Vec<float32> = [-1.0, 5.5, 5.5, 5.5, 5.5];
	for (let i = 0; i < 5; i++) {
		assert approx(box.rayIntersection(toward[i], Face.Back), entered[i]);
		assert approx(box.rayIntersection(toward[i], Face.Front), leftBy[i]);
	}
	let ground: MeshData = MeshData.empty();
	const _plane: int32 = try addPlane(ground, 2.0, WHITE) catch -1;
	assert approx(ground.rayIntersection(down(0.5, 0.5), Face.Back), 10.0);
	assert ground.rayIntersection(down(0.5, 0.5), Face.Front) == -1.0;
}

// ---- h3d.scene.Interactive and Scene.rayCastEventTargets -------------------------------------

test "only meshes under a pickable node are hit, and the others do not stand in front" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const upper: NodeId3D = meshNode(
		scene,
		context,
		scene.rootId(),
		Transform3D.fromTranslation(vec3(0.0, 3.0, 0.0)),
		0,
	);
	const lower: NodeId3D = pickable(
		scene,
		meshNode(scene, context, scene.rootId(), Transform3D.identity(), 0),
	);
	const hit: PickHit = pickOf(scene, meshes, down(0.0, 0.0));
	assert sameId(hit.owner, lower);
	assert sameId(hit.mesh, lower);
	assert approx(hit.distance, 9.0);
	assert nearVec(hit.point, vec3(0.0, 1.0, 0.0));
	const _both: NodeId3D = pickable(scene, upper);
	const top: PickHit = pickOf(scene, meshes, down(0.0, 0.0));
	assert sameId(top.owner, upper);
	assert approx(top.distance, 6.0);
}

test "a hit on a mesh belongs to its nearest pickable ancestor" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const outer: NodeId3D = pickable(
		scene,
		addGroup(scene, scene.rootId(), Transform3D.identity()),
	);
	const inner: NodeId3D = pickable(
		scene,
		addGroup(scene, outer, Transform3D.fromTranslation(vec3(5.0, 0.0, 0.0))),
	);
	const body: NodeId3D = meshNode(scene, context, outer, Transform3D.identity(), 0);
	const arm: NodeId3D = meshNode(scene, context, inner, Transform3D.identity(), 0);
	const onBody: PickHit = pickOf(scene, meshes, down(0.0, 0.0));
	assert sameId(onBody.owner, outer);
	assert sameId(onBody.mesh, body);
	const onArm: PickHit = pickOf(scene, meshes, down(5.0, 0.0));
	assert sameId(onArm.owner, inner);
	assert sameId(onArm.mesh, arm);
}

test "a mesh under a hidden node is not picked" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const _box: NodeId3D =
		pickable(scene, meshNode(scene, context, group, Transform3D.identity(), 0));
	setVisible(scene, group, false);
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !missed.ok;
	if (!missed.ok) { assert missed.error == PickError.NothingHit; }
}

test "a turned, scaled and moved node is picked where it is drawn, in world units" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const placed: Transform3D = {
		position: vec3(4.0, 1.0, -2.0),
		rotation: eulerQuat(0.0, 0.7, 0.0),
		scale: vec3(2.0, 3.0, 2.0),
	};
	const box: NodeId3D = pickable(scene, meshNode(scene, context, scene.rootId(), placed, 0));
	const hit: PickHit = pickOf(scene, meshes, down(4.0, -2.0));
	assert sameId(hit.owner, box);
	assert approx(hit.distance, 6.0);
	assert nearVec(hit.point, vec3(4.0, 4.0, -2.0));
	setLocal(scene, box, { ...placed, position: vec3(0.0, 0.0, 0.0) });
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(4.0, -2.0));
	assert !missed.ok;
}

test "a node scaled to nothing and a mesh with no CPU geometry are never hit" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox(), MeshData.empty()];
	const flat: Transform3D = { ...Transform3D.identity(), scale: vec3(0.0, 0.0, 0.0) };
	const _gone: NodeId3D = pickable(scene, meshNode(scene, context, scene.rootId(), flat, 0));
	const _external: NodeId3D =
		pickable(scene, meshNode(scene, context, scene.rootId(), Transform3D.identity(), 1));
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !missed.ok;
	if (!missed.ok) { assert missed.error == PickError.NothingHit; }
}

test "a mesh or material index outside the tables is an error, not a miss" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const _beyond: NodeId3D =
		pickable(scene, meshNode(scene, context, scene.rootId(), Transform3D.identity(), 7));
	const noMesh: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !noMesh.ok;
	if (!noMesh.ok) { assert noMesh.error == PickError.MeshOutOfRange; }
	let other: Scene3D = Scene3D.create();
	const odd: NodeId3D = try addMeshNode(
		other,
		context,
		other.rootId(),
		Transform3D.identity(),
		context.meshAt(0),
		context.materialAt(9),
	) catch NO_ID;
	const _marked: NodeId3D = pickable(other, odd);
	const noMaterial: Result<PickHit, PickError> =
		pickNearest(other, meshes, materials(), down(0.0, 0.0));
	assert !noMaterial.ok;
	if (!noMaterial.ok) { assert noMaterial.error == PickError.MaterialOutOfRange; }
}

test "the pick keeps the faces the material draws, turned over by a mirroring node" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [facingPlusZ(0.0)];
	const front: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	const plain: NodeId3D =
		try addMeshNode(
			scene,
			context,
			scene.rootId(),
			Transform3D.identity(),
			context.meshAt(0),
			context.materialAt(BACK_CULLED),
		) catch NO_ID;
	const _marked: NodeId3D = pickable(scene, plain);
	assert sameId(pickOf(scene, meshes, front).owner, plain);
	const mirrored: Transform3D = { ...Transform3D.identity(), scale: vec3(-1.0, 1.0, 1.0) };
	setLocal(scene, plain, mirrored);
	const missed: Result<PickHit, PickError> = pickNearest(scene, meshes, materials(), front);
	assert !missed.ok;
	const behind: Ray = { origin: vec3(0.0, 0.0, -5.0), direction: vec3(0.0, 0.0, 1.0) };
	assert sameId(pickOf(scene, meshes, behind).owner, plain);
}

test "a mirroring parent turns a child's faces over, and a second mirror turns them back" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [facingPlusZ(0.0)];
	const front: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
	const behind: Ray = { origin: vec3(0.0, 0.0, -5.0), direction: vec3(0.0, 0.0, 1.0) };
	const mirror: Transform3D = { ...Transform3D.identity(), scale: vec3(-1.0, 1.0, 1.0) };
	const parent: NodeId3D = addGroup(scene, scene.rootId(), mirror);
	const child: NodeId3D =
		try addMeshNode(
			scene,
			context,
			parent,
			Transform3D.identity(),
			context.meshAt(0),
			context.materialAt(FRONT_CULLED),
		) catch NO_ID;
	const _marked: NodeId3D = pickable(scene, child);
	const drawnFromFront: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), front);
	assert drawnFromFront.ok;
	const culledFromBehind: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), behind);
	assert !culledFromBehind.ok;
	setLocal(scene, child, mirror);
	assert !pickNearest(scene, meshes, materials(), front).ok;
	assert pickNearest(scene, meshes, materials(), behind).ok;
}

// Heaps never sets checkInside on a getCollider() shape, so it misses this ray.
test "a ray starting inside a mesh's bounds still reaches its triangles" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const box: NodeId3D =
		pickable(scene, meshNode(scene, context, scene.rootId(), Transform3D.identity(), 0));
	const up: Ray = { origin: vec3(0.0, 0.5, 0.0), direction: vec3(0.0, 1.0, 0.0) };
	const inside: PickHit = pickOf(scene, meshes, up);
	assert sameId(inside.owner, box);
	assert approx(inside.distance, 0.5);
}

// Heaps sorts by distance from camera.pos. This camera's eye is its target, mid depth range,
// so the farther mesh here would be the closer one to the eye.
test "the nearest hit is measured from the ray's origin, not from the camera's eye" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [facingPlusZ(0.5), facingPlusZ(-0.3)];
	const nearer: NodeId3D =
		pickable(scene, meshNode(scene, context, scene.rootId(), Transform3D.identity(), 0));
	const _farther: NodeId3D =
		pickable(scene, meshNode(scene, context, scene.rootId(), Transform3D.identity(), 1));
	const ray: Ray = { origin: vec3(0.0, 0.0, 50.0), direction: vec3(0.0, 0.0, -1.0) };
	const hit: PickHit = pickOf(scene, meshes, ray);
	assert sameId(hit.owner, nearer);
	assert approx(hit.distance, 49.5);
}

test "a hidden mesh under a visible pickable node is not picked" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const model: NodeId3D = pickable(
		scene,
		addGroup(scene, scene.rootId(), Transform3D.identity()),
	);
	const part: NodeId3D = meshNode(scene, context, model, Transform3D.identity(), 0);
	assert sameId(pickOf(scene, meshes, down(0.0, 0.0)).owner, model);
	setVisible(scene, part, false);
	const missed: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !missed.ok;
}

test "a baked frame swapped in by its animation is the geometry picked" {
	let context: DrawContext = contextOf(16, 16);
	let scene: Scene3D = Scene3D.create();
	let moved: MeshData = MeshData.empty();
	const _shifted: int32 = try addBox(moved, {
		base: vec3(5.0, 0.0, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.0,
		tilt: 0.0,
		color: WHITE,
	}) catch -1;
	const meshes: Vec<MeshData> = [unitBox(), moved];
	const pet: NodeId3D = pickable(
		scene,
		meshNode(scene, context, scene.rootId(), Transform3D.identity(), 0),
	);
	setName(scene, pet, "body");
	const frames: Vec<MeshId> = [context.meshAt(0), context.meshAt(1)];
	const clock: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(2, 1.0, Interpolation.Step);
	assert clock.ok;
	if (!clock.ok) { return; }
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(context, clock.value, "body", frames);
	assert made.ok;
	if (!made.ok) { return; }
	let animation: MeshFrameAnimation = made.value;
	const _bound: int32 = try bindMeshFrames(animation, scene, scene.rootId()) catch -1;
	const _first: int32 = try syncMeshFrame(animation, scene, context) catch -1;
	assert sameId(pickOf(scene, meshes, down(0.0, 0.0)).owner, pet);
	const _stepped: boolean = try update(animation.clock, 1.0) catch false;
	const _second: int32 = try syncMeshFrame(animation, scene, context) catch -1;
	const old: Result<PickHit, PickError> =
		pickNearest(scene, meshes, materials(), down(0.0, 0.0));
	assert !old.ok;
	assert sameId(pickOf(scene, meshes, down(5.0, 0.0)).owner, pet);
}

// ---- tap to object, end to end through the camera and the blit ---------------------------

test "a framebuffer pixel a box is drawn at picks that box and not its neighbour" {
	let context: DrawContext = contextOf(16, 16);
	const blit: LowResView = try lowResView(1280, 720, 360, 1, 1) catch NO_LOW_RES;
	const texel: float32 = 20.0 / 360.0;
	let camera: Camera3D = {
		position: vec3(0.3, 0.0, 0.2),
		yaw: 0.785398,
		pitch: 0.6,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: texel, snap: true },
		nearPlane: -50.0,
		farPlane: 50.0,
	};
	const resolved: CameraView = try camera.resolve(blit.width, blit.height) catch NO_VIEW;
	const shifted: LowResView = blit.withRemainder(resolved.remainderX, resolved.remainderY, true);
	let scene: Scene3D = Scene3D.create();
	const meshes: Vec<MeshData> = [unitBox()];
	const left: NodeId3D =
		pickable(
			scene,
			meshNode(
				scene,
				context,
				scene.rootId(),
				Transform3D.fromTranslation(vec3(-3.0, 0.0, 0.0)),
				0,
			),
		);
	const right: NodeId3D =
		pickable(
			scene,
			meshNode(
				scene, context, scene.rootId(), Transform3D.fromTranslation(vec3(3.0, 0.0, 1.0)), 0,
			),
		);
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
