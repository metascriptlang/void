import { Mat4, vec3, identity, scaling, translation } from "../math/math3d";
import { Camera3D, CameraView, CameraError, ProjectionKind, CAMERA_BLOCK_LENGTH,
	CAMERA_PROJECTION_X, CAMERA_PROJECTION_Y, CAMERA_EYE, CAMERA_NEAR } from "../void3d/camera";
import {
	MeshLod, MeshLodRange, MeshLodRanges, MeshLodPick, MeshLodError, pickFor,
} from "../void3d/meshLod";
import { Bounds3D } from "../void3d/bounds";
import { Frustum3D } from "../void3d/frustum";
import {
	DrawContext, DrawItem, GpuMesh, MeshId, MaterialId, addMaterial, addMesh, reserveUniforms,
} from "../void3d/draw";
import { Material, Phase, ShadowCasting } from "../void3d/material";
import { RenderState } from "../gpu/state";
import {
	Program, VERTEX_UNIFORM_LENGTH, MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, pickMeshLods } from "../void3d/renderer";
import {
	Scene3D, NodeId3D, SceneError, Transform3D, addMeshNode, addLodMeshNode, setForcedLod,
	setMeshOf, refresh,
} from "../void3d/scene";
import { PassList, collect, collectCasters, filterFrustum } from "../void3d/passList";
import { added, litShape } from "./drawHelpers";
import { approx } from "./helpers";

function twoLevels(): MeshLod {
	const made = MeshLod.create(2, [0.5], 0.1);
	if (!made.ok) { unreachable; }
	return made.value;
}

function nineElements(lodCount: int32, elementCount: int64): MeshLodRanges {
	const made = MeshLodRanges.fromElementRanges(lodCount, 1, elementCount,
		[{ base: 0, count: 6 }, { base: 6, count: 3 }]);
	if (!made.ok) { unreachable; }
	return made.value;
}

function pickOf(forcedLod: int32): MeshLodPick {
	return {
		config: twoLevels(), ranges: nineElements(2, 9), material: 0, localOriginRadius: 1.0,
		forcedLod: forcedLod,
	};
}

function pickedAt(pick: MeshLodPick, world: Mat4): Result<MeshLodRange | null, MeshLodError> {
	return pick.pickFor(world, vec3(0.0, 0.0, 0.0), 1.0, 1.0, 0.1, 1.0);
}

function rangeAt(forcedLod: int32, world: Mat4): MeshLodRange | null {
	const picked = pickedAt(pickOf(forcedLod), world);
	if (!picked.ok) { unreachable; }
	return picked.value;
}

test "a pick chooses the level by screen ratio, scaled by the world, and culls below the floor" {
	const near = rangeAt(-1, translation(0.0, 0.0, -1.0));
	assert near !== null && near.base == 0 && near.count == 6;
	const far = rangeAt(-1, translation(0.0, 0.0, -3.0));
	assert far !== null && far.base == 6 && far.count == 3;
	const scaled = rangeAt(-1, { ...scaling(2.0, 2.0, 2.0), m43: -3.0 });
	assert scaled !== null && scaled.base == 0;
	assert rangeAt(-1, translation(0.0, 0.0, -20.0)) === null;
}

test "a forced level overrides the distance and a level past the count hides the mesh" {
	const forced = rangeAt(1, translation(0.0, 0.0, -1.0));
	assert forced !== null && forced.base == 6;
	assert rangeAt(2, translation(0.0, 0.0, -1.0)) === null;
}

test "a mirrored world is refused by the pick" {
	const pick = pickOf(-1);
	const picked = pickedAt(pick, scaling(-1.0, 1.0, 1.0));
	assert !picked.ok && picked.error == MeshLodError.MirroredWorld;
}

function perspective(): Camera3D {
	return {
		position: vec3(1.0, 2.0, 3.0), yaw: 0.0, pitch: 0.0, nearPlane: 0.5, farPlane: 11.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.5707963267948966 },
	};
}

function viewOf(camera: Camera3D): CameraView {
	const view: Result<CameraView, CameraError> = camera.resolve(800, 400);
	if (!view.ok) { unreachable; }
	return view.value;
}

test "the camera block carries the projection diagonal, the eye and the near plane" {
	const view = viewOf(perspective());
	assert approx(view.projectionX, 0.5) && approx(view.projectionY, 1.0);
	let block: Vec<float32> = new Array(CAMERA_BLOCK_LENGTH);
	view.writeCameraBlock(block);
	assert approx(block[CAMERA_PROJECTION_X], 0.5) && approx(block[CAMERA_PROJECTION_Y], 1.0);
	assert block[CAMERA_NEAR] == 0.5;
	assert block[CAMERA_EYE] == 1.0 && block[CAMERA_EYE + 1] == 2.0 && block[CAMERA_EYE + 2] == 3.0;
}

function shadowedContext(): DrawContext {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const mesh: MeshId = added(context, GpuMesh.fullscreen(0, 9));
	context.meshData[mesh.index] = {
		...context.meshData[mesh.index],
		bounds: Bounds3D.fromPoints(vec3(-1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)),
	};
	const _short: MeshId = added(context, GpuMesh.fullscreen(0, 3));
	const casting: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque)
		.withShadows(ShadowCasting.On, false);
	const _material = addMaterial(context, casting);
	return context;
}

function lodNode(scene: Scene3D, depth: float32): NodeId3D {
	const node = addLodMeshNode(scene, scene.rootId(), Transform3D.fromTranslation(
		vec3(0.0, 0.0, depth)), scene.context.meshAt(0), scene.context.materialAt(0),
		twoLevels(), nineElements(2, 9), 0);
	if (!node.ok) { unreachable; }
	return node.value;
}

function pickerOf(context: DrawContext): Renderer {
	const made = Renderer.create(context);
	if (!made.ok) { unreachable; }
	return made.value;
}

function pickedFrom(renderer: Renderer, items: Span<DrawItem>): Result<void, RendererError> {
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	viewOf({ ...perspective(), position: vec3(0.0, 0.0, 0.0) }).writeCameraBlock(camera);
	return pickMeshLods(renderer, items, camera);
}

test "a LOD node's item draws level zero until a frame picks its level" {
	const scene = Scene3D.create(shadowedContext());
	const _node = lodNode(scene, -3.0);
	let items: Vec<DrawItem> = [];
	const _count = refresh(scene, items);
	assert items.length == 1;
	const before = items[0].range;
	assert before !== null && before.base == 0 && before.count == 6;
	assert pickedFrom(pickerOf(scene.context), items).ok;
	const after = items[0].range;
	assert after !== null && after.base == 6 && after.count == 3 && !items[0].lodCulled;
	const pick = items[0].lod;
	assert pick !== null && approx(pick.localOriginRadius as float32, 1.0);
}

test "a LOD node refuses a table that does not fit its mesh" {
	const scene = Scene3D.create(shadowedContext());
	const at: Transform3D = Transform3D.identity();
	const mesh: MeshId = scene.context.meshAt(0);
	const material: MaterialId = scene.context.materialAt(0);
	const threeLevels = MeshLod.create(3, [0.5, 0.2], 0.1);
	assert threeLevels.ok;
	const counts = addLodMeshNode(scene, scene.rootId(), at, mesh, material,
		threeLevels.value, nineElements(2, 9), 0);
	assert !counts.ok && counts.error == SceneError.MeshLod;
	const elements = addLodMeshNode(scene, scene.rootId(), at, mesh, material,
		twoLevels(), nineElements(2, 12), 0);
	assert !elements.ok && elements.error == SceneError.MeshLod;
	const slot = addLodMeshNode(scene, scene.rootId(), at, mesh, material,
		twoLevels(), nineElements(2, 9), 1);
	assert !slot.ok && slot.error == SceneError.MeshLod;
	const node = lodNode(scene, -3.0);
	const shorter = setMeshOf(scene, node, scene.context.meshAt(1));
	assert !shorter.ok && shorter.error == SceneError.MeshLod;
}

test "a forced level is refused on a plain node and below minus one" {
	const scene = Scene3D.create(shadowedContext());
	const plain = addMeshNode(scene, scene.rootId(), Transform3D.identity(),
		scene.context.meshAt(0), scene.context.materialAt(0));
	assert plain.ok;
	const unpicked = setForcedLod(scene, plain.value, 0);
	assert !unpicked.ok && unpicked.error == SceneError.MeshLod;
	const node = lodNode(scene, -3.0);
	const below = setForcedLod(scene, node, -2);
	assert !below.ok && below.error == SceneError.MeshLod;
	assert setForcedLod(scene, node, 1).ok;
}

function excludedBy(list: PassList, items: Vec<DrawItem>, context: DrawContext): int32 {
	let kept: PassList = list;
	const frustum = Frustum3D.fromMatrix(viewOf({ ...perspective(), position: vec3(0.0, 0.0, 0.0) })
		.viewProj);
	return filterFrustum(kept, items, context.meshData, frustum);
}

test "a culled pick leaves both the colour and the shadow pass lists" {
	const scene = Scene3D.create(shadowedContext());
	const node = lodNode(scene, -3.0);
	let items: Vec<DrawItem> = [];
	const _count = refresh(scene, items);
	const renderer: Renderer = pickerOf(scene.context);
	for (const level of [-1, 2]) {
		assert setForcedLod(scene, node, level).ok;
		assert pickedFrom(renderer, items).ok;
		assert items[0].lodCulled == (level == 2);
		let colour: PassList = PassList.forPhase(Phase.Opaque);
		collect(colour, items, scene.context.materials);
		let casters: PassList = PassList.forPhase(Phase.Opaque);
		collectCasters(casters, items, scene.context.materials);
		assert colour.count == 1 && casters.count == 1;
		const expected: int32 = level == 2 ? 1 : 0;
		assert excludedBy(colour, items, scene.context) == expected;
		assert excludedBy(casters, items, scene.context) == expected;
	}
}

struct LitFrame {
	began: Result<void, RendererError>;
	published: boolean;
}

function litFrame(world: Mat4): LitFrame {
	let context: DrawContext =
		DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH);
	const made = Renderer.create(context);
	if (!made.ok) { unreachable; }
	const renderer: Renderer = made.value;
	const mesh = addMesh(context, litShape());
	const block = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	const material = addMaterial(context, {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque), uniforms: block.value,
	});
	if (!mesh.ok || !material.ok) { unreachable; }
	const ranges = MeshLodRanges.fromElementRanges(2, 1, 0,
		[{ base: 0, count: 0 }, { base: 0, count: 0 }]);
	if (!ranges.ok) { unreachable; }
	const pick: MeshLodPick = {
		config: twoLevels(), ranges: ranges.value, material: 0, localOriginRadius: 1.0,
		forcedLod: -1,
	};
	const item: DrawItem = { mesh: mesh.value, material: material.value, world: world, lod: pick };
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	viewOf(perspective()).writeCameraBlock(camera);
	const before: int32 = renderer.generation;
	let items: Vec<DrawItem> = [item];
	const began = pickMeshLods(renderer, items, camera);
	return { began: began, published: renderer.generation != before };
}

test "a frame with a mirrored LOD item is refused before it is published" {
	const mirrored = litFrame(scaling(-1.0, 1.0, 1.0));
	assert !mirrored.began.ok && mirrored.began.error == RendererError.MeshLod;
	assert !mirrored.published;
}
