import { SkinGeometry, SkinGeometryError, bind, syncGeometry, deformPublished, spatialReady, rayIntersection as intersectSkin } from "../void3d/skinGeometry";
import { SkinPose, bind as bindPose, syncSkinPose } from "../void3d/skinPose";
import { SkinPalette, create } from "../void3d/skinPalette";
import { MeshData, addVertex, addTriangle, rayIntersection } from "../void3d/meshData";
import { SkinInfluences } from "../void3d/skinInfluences";
import { DrawContext, DrawItem, NO_MESH, NO_MATERIAL, validSkin } from "../void3d/draw";
import { Program, ProgramKey, withSkin } from "../void3d/gpu3d";
import { PassList, forPhase, filterFrustum, sortBackToFront } from "../void3d/passList";
import { Phase } from "../void3d/material";
import { Frustum3D, fromMatrix } from "../void3d/frustum";
import { Scene3D, Transform3D, addGroup, rootId, setLocal, remove } from "../void3d/scene";
import { identity, vec3, translation } from "../math/math3d";
import { Face } from "../gpu/state";
import { Ray } from "../void3d/ray";

function triangle(): MeshData {
	let mesh = MeshData.empty();
	for (const point of [vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0)]) {
		const _vertex = addVertex(mesh, point, vec3(0, 0, 1), { red: 1, green: 1, blue: 1, alpha: 1 });
	}
	const _triangle = addTriangle(mesh, 0, 1, 2);
	return move mesh;
}

function influences(): SkinInfluences {
	return { joints: [0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0],
		weights: [0.25, 0.75, 0, 0, 0.25, 0.75, 0, 0, 0.25, 0.75, 0, 0] };
}

test "posed bounds and triangle picking use canonical joints, not GPU palette slots or mesh world" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const second = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(20, 0, 0),
	});
	const palette = SkinPalette.create([1, 0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0, 1], [first, second], [identity(), identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	const geometry = SkinGeometry.bind(triangle(), influences(), pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.ready;
	assert geometry.value.mesh.bounds.min.x == 17.5;
	assert geometry.value.mesh.bounds.max.x == 18.5;
	const ray: Ray = { origin: vec3(17.75, 0.25, 2), direction: vec3(0, 0, -1) };
	assert geometry.value.mesh.rayIntersection(ray, Face.None).distance == 2;
	assert geometry.value.source.bounds.min.x == 0;
	setLocal(scene, second, { ...Transform3D.identity(), position: vec3(40, 0, 0) });
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.mesh.bounds.min.x == 32.5;
	assert geometry.value.mesh.rayIntersection(ray, Face.None).distance < 0;
}

test "late nonfinite deformation preserves published vertices and invalidates spatial queries" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let source = triangle();
	source.vertices[20] = 3.0e38;
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(source, values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.spatialReady();
	setLocal(scene, bone, { ...Transform3D.identity(), position: vec3(2, 0, 0), scale: vec3(10, 1, 1) });
	const failed = geometry.value.syncGeometry();
	assert !failed.ok && failed.error == SkinGeometryError.NonFinite;
	assert !geometry.value.spatialReady();
	assert geometry.value.mesh.vertices[0] == 0;
	const ray: Ray = { origin: vec3(0, 0, 2), direction: vec3(0, 0, -1) };
	assert !intersectSkin(geometry.value, ray, Face.None).ok;
}

test "published pose revisions and recycled joints invalidate cached geometry" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.spatialReady();
	assert pose.value.syncSkinPose().ok;
	assert !geometry.value.spatialReady();
	assert geometry.value.deformPublished().ok;
	assert geometry.value.spatialReady();
	const _removed = remove(scene, bone);
	const _replacement = addGroup(scene, scene.rootId(), Transform3D.identity());
	assert !geometry.value.spatialReady();
	assert !geometry.value.deformPublished().ok;
}

test "skin draw validation and frustum filtering consume published world bounds without mesh model" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	let item: DrawItem = {
		mesh: { ...NO_MESH, index: 0 }, material: NO_MATERIAL,
		world: translation(1000, 0, 0), order: 0, skin: null,
		skinGeometry: geometry.value, skinPalette: 0, range: null,
	};
	const program = ProgramKey.of(Program.Lit).withSkin();
	assert !item.validSkin(program);
	assert geometry.value.syncGeometry().ok;
	assert item.validSkin(program);
	let list = PassList.forPhase(Phase.Opaque);
	list.indices = [0]; list.layers = [0]; list.orders = [0]; list.count = 1;
	assert filterFrustum(list, [item], [triangle()], Frustum3D.fromMatrix(identity())) == 0;
	assert list.count == 1;
	item.skin = pose.value;
	assert !item.validSkin(program);
	item.skin = null;
	setLocal(scene, bone, { ...Transform3D.identity(), position: vec3(0, 0, 10) });
	assert geometry.value.syncGeometry().ok;
	item.world = translation(1000, 0, -1000);
	const other: DrawItem = { ...item, skinGeometry: null, world: translation(0, 0, 3) };
	list.indices = [0, 1]; list.depths = [0, 0]; list.layers = [0, 0]; list.orders = [0, 0]; list.count = 2;
	const camera: Vec<float32> = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
	sortBackToFront(list, [item, other], camera);
	assert list.indices[0] == 0 && list.depths[0] == 10;
}

test "two geometries consume one pose publication and never share pending vertex buffers" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const first = SkinGeometry.bind(triangle(), values, pose.value);
	const second = SkinGeometry.bind(triangle(), values, pose.value);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	assert pose.value.syncSkinPose().ok;
	assert first.value.deformPublished().ok && second.value.deformPublished().ok;
	assert first.value.spatialReady() && second.value.spatialReady();
	first.value.pending.vertices[0] = 99;
	assert second.value.pending.vertices[0] == 0;
	pose.value.revision = 0xffffffffffffffff as uint64;
	assert !pose.value.syncSkinPose().ok;
	assert !first.value.spatialReady() && !second.value.spatialReady();
}

test "skin geometry owns canonical inputs and refuses invalid influence shapes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	assert !SkinGeometry.bind(triangle(), values, pose.value).ok;
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	values.weights[0] = -1;
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.influences.weights[0] == 0.25;
	values.weights.pop();
	const short = SkinGeometry.bind(triangle(), values, pose.value);
	assert !short.ok && short.error == SkinGeometryError.Shape;
}
