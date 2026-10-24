import {
	Scene3D, SceneError, Transform3D, addGroup, addSkinMeshNode, rootId, closeScene,
	refreshChecked, setLocal, setPickable, remove, setMaterialOf, SceneSyncError,
} from "../void3d/scene";
import { SkinGeometry, SkinGeometryError, bind, spatialReady } from "../void3d/skinGeometry";
import { SkinPose, bind as bindPose } from "../void3d/skinPose";
import { SkinPalette, create } from "../void3d/skinPalette";
import { MeshData, addVertex, addSkinAttributes } from "../void3d/meshData";
import { MeshId, MaterialId, DrawItem, validSkin, addMaterial } from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { Program, ProgramKey, VertexLayout, withSkin } from "../void3d/gpu3d";
import { PickError, pickNearest } from "../void3d/pick";
import { Ray } from "../void3d/ray";
import { identity, vec3 } from "../math/math3d";
import { Face, RenderState } from "../gpu/state";
import { contextOf, meshAt, materialAt } from "./drawHelpers";

interface SkinSceneFixture {
	scene: Scene3D;
	geometry: SkinGeometry;
	mesh: MeshId;
	material: MaterialId;
}

function fixture(two: boolean = false): SkinSceneFixture {
	const context = contextOf(1, 1);
	let data = MeshData.empty();
	let joints: Vec<int32> = [];
	let weights: Vec<float32> = [];
	const triangles: int32 = two ? 2 : 1;
	for (let triangle: int32 = 0; triangle < triangles; triangle++) {
		for (let corner: int32 = 0; corner < 3; corner++) {
			const x: float32 = (triangle * 4 + (corner == 1 ? 1 : 0)) as float32;
			const y: float32 = corner == 2 ? 1.0 : 0.0;
			const added = addVertex(data, vec3(x, y, 0), vec3(0, 0, 1),
				{ red: 1, green: 1, blue: 1, alpha: 1 });
			if (!added.ok) { unreachable; }
			for (let slot: int32 = 0; slot < 4; slot++) {
				joints.push(0); weights.push(slot == 0 ? 1.0 : 0.0);
			}
		}
	}
	const packed = addSkinAttributes(data, joints, weights);
	if (!packed.ok) { unreachable; }
	context.meshData[0] = { ...data };
	context.meshes[0].layout = VertexLayout.SkinLit;
	context.meshes[0].vertexCount = triangles * 3;
	context.materials[0].program = ProgramKey.of(Program.Lit).withSkin();
	context.materials[0].pass.culling = Face.None;
	const scene = Scene3D.create(context);
	const bone = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const palette = SkinPalette.create([0]);
	if (!palette.ok) { unreachable; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	if (!pose.ok) { unreachable; }
	const geometry = SkinGeometry.bind(data, { joints: joints, weights: weights }, pose.value);
	if (!geometry.ok) { unreachable; }
	return { scene: scene, geometry: geometry.value,
		mesh: context.meshAt(0), material: context.materialAt(0) };
}

test "retained skin publishes shared pose once and emits independent geometries without model" {
	const f = fixture();
	defer closeScene(f.scene);
	const second = SkinGeometry.bind(f.geometry.source, f.geometry.influences, f.geometry.pose);
	assert second.ok;
	if (!second.ok) { return; }
	const a = addSkinMeshNode(f.scene, f.scene.rootId(),
		{ ...Transform3D.identity(), position: vec3(1000, 0, 0) },
		f.mesh, f.material, f.geometry, 0, null);
	const b = addSkinMeshNode(f.scene, f.scene.rootId(),
		{ ...Transform3D.identity(), position: vec3(2000, 0, 0) },
		f.mesh, f.material, second.value, 0, null);
	assert a.ok && b.ok;
	let items: Vec<DrawItem> = [];
	const refreshed = refreshChecked(f.scene, items);
	assert refreshed.ok;
	if (refreshed.ok) { assert refreshed.value == 2; }
	assert f.geometry.pose.revision == 1;
	assert f.geometry.spatialReady() && second.value.spatialReady();
	assert f.geometry.mesh.bounds.min.x == 10 && second.value.mesh.bounds.max.x == 11;
	for (const item of items) {
		assert item.skin === null && item.skinGeometry !== null;
		assert item.validSkin(f.scene.context.materials[0].program);
	}
	setLocal(f.scene, f.geometry.pose.joints[0], {
		...Transform3D.identity(), position: vec3(20, 0, 0),
	});
	assert refreshChecked(f.scene, items).ok;
	assert f.geometry.pose.revision == 2;
	assert f.geometry.mesh.bounds.min.x == 20 && second.value.mesh.bounds.max.x == 21;
}

test "retained picking refreshes joints and respects skin range in world space" {
	const f = fixture(true);
	defer closeScene(f.scene);
	const made = addSkinMeshNode(f.scene, f.scene.rootId(),
		{ ...Transform3D.identity(), position: vec3(1000, 0, 0) },
		f.mesh, f.material, f.geometry, 0, { base: 3, count: 3 });
	assert made.ok;
	if (!made.ok) { return; }
	setPickable(f.scene, made.value, true);
	const near: Ray = { origin: vec3(10.25, 0.25, 2), direction: vec3(0, 0, -1) };
	const excluded = pickNearest(f.scene, near);
	assert !excluded.ok;
	if (!excluded.ok) { assert excluded.error == PickError.NothingHit; }
	setLocal(f.scene, f.geometry.pose.joints[0], {
		...Transform3D.identity(), position: vec3(20, 0, 0),
	});
	const far: Ray = { origin: vec3(24.25, 0.25, 2), direction: vec3(0, 0, -2) };
	const hit = pickNearest(f.scene, far);
	assert hit.ok;
	if (hit.ok) {
		assert hit.value.distance == 2 && hit.value.point.x == 24.25;
		assert hit.value.mesh.index == made.value.index;
	}
}

test "retained skin refuses foreign pose bad palette layout and element declaration before pins" {
	const f = fixture();
	defer closeScene(f.scene);
	const other = Scene3D.create(f.scene.context);
	defer closeScene(other);
	const foreign = addSkinMeshNode(other, other.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 0, null);
	assert !foreign.ok;
	if (!foreign.ok) { assert foreign.error == SceneError.ForeignSkin; }
	const palette = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 1, null);
	assert !palette.ok;
	if (!palette.ok) { assert palette.error == SceneError.SkinPalette; }
	const range = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 0, { base: 1, count: 3 });
	assert !range.ok;
	if (!range.ok) { assert range.error == SceneError.DrawRange; }
	f.scene.context.materials[0].program = ProgramKey.of(Program.Lit);
	const layout = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 0, null);
	assert !layout.ok;
	if (!layout.ok) { assert layout.error == SceneError.SkinMesh; }
	assert f.scene.meshes.length == 0;
	assert f.scene.context.meshPins[0] == 0 && f.scene.context.materialPins[0] == 0;
}

test "a skinned node takes only a skinned material through setMaterialOf" {
	const f = fixture();
	defer closeScene(f.scene);
	const context = f.scene.context;
	const made = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 0, null);
	assert made.ok;
	if (!made.ok) { return; }
	const flat = addMaterial(context, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
	const skinned = addMaterial(context, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
	assert flat.ok && skinned.ok;
	if (!flat.ok || !skinned.ok) { return; }
	context.materials[skinned.value.index].program = ProgramKey.of(Program.Lit).withSkin();
	const refused = setMaterialOf(f.scene, made.value, flat.value);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == SceneError.SkinMesh; }
	assert context.materialPins[f.material.index] == 1 && context.materialPins[flat.value.index] == 0;
	assert setMaterialOf(f.scene, made.value, skinned.value).ok;
	assert context.materialPins[f.material.index] == 0 && context.materialPins[skinned.value.index] == 1;
}

test "retained skin rejects stale joints rather than bind fallback and close drops attachment" {
	const f = fixture();
	const made = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 0, null);
	assert made.ok;
	if (!made.ok) { closeScene(f.scene); return; }
	setPickable(f.scene, made.value, true);
	let items: Vec<DrawItem> = [];
	assert refreshChecked(f.scene, items).ok;
	const removed = remove(f.scene, f.geometry.pose.joints[0]);
	assert removed == 1;
	const failed = refreshChecked(f.scene, items);
	assert !failed.ok;
	if (!failed.ok) { assert failed.error == SceneSyncError.Skin; }
	assert !f.geometry.spatialReady();
	const hit = pickNearest(f.scene,
		{ origin: vec3(10.25, 0.25, 2), direction: vec3(0, 0, -1) });
	assert !hit.ok;
	if (!hit.ok) { assert hit.error == PickError.SkinGeometry; }
	closeScene(f.scene);
	assert f.scene.meshes.length == 0;
	assert f.scene.context.meshPins[0] == 0 && f.scene.context.materialPins[0] == 0;
}

test "retained actors share mesh and material but keep pose bounds and attachment independent" {
	const f = fixture();
	defer closeScene(f.scene);
	const bone = addGroup(f.scene, f.scene.rootId(), {
		...Transform3D.identity(), position: vec3(-10, 0, 0),
	});
	const pose = SkinPose.bindPose(f.scene, [0], [bone], [identity()], f.geometry.pose.palettes);
	assert pose.ok;
	if (!pose.ok) { return; }
	const geometry = SkinGeometry.bind(f.geometry.source, f.geometry.influences, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	const first = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, f.geometry, 0, null);
	const second = addSkinMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.mesh, f.material, geometry.value, 0, null);
	assert first.ok && second.ok;
	if (!first.ok) { return; }
	if (!second.ok) { return; }
	let items: Vec<DrawItem> = [];
	assert refreshChecked(f.scene, items).ok;
	assert f.geometry.mesh.bounds.min.x == 10 && geometry.value.mesh.bounds.min.x == -10;
	assert f.scene.context.meshPins[0] == 2 && f.scene.context.materialPins[0] == 2;
	setLocal(f.scene, f.geometry.pose.joints[0], {
		...Transform3D.identity(), position: vec3(20, 0, 0),
	});
	assert refreshChecked(f.scene, items).ok;
	assert f.geometry.mesh.bounds.min.x == 20 && geometry.value.mesh.bounds.min.x == -10;
	assert remove(f.scene, first.value) == 1;
	assert remove(f.scene, f.geometry.pose.joints[0]) == 1;
	assert refreshChecked(f.scene, items).ok;
	assert items.length == 1 && items[0].skinGeometry === geometry.value;
	assert geometry.value.spatialReady() && geometry.value.mesh.bounds.min.x == -10;
	assert f.scene.context.meshPins[0] == 1 && f.scene.context.materialPins[0] == 1;
}
