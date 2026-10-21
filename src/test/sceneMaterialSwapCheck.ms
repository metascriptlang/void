import {
	Scene3D, SceneError, NodeId3D, Transform3D,
	addMeshNode, setMaterialOf, collectDrawList, refreshChecked, closeScene,
} from "../void3d/scene";
import {
	DrawContext, DrawItem, MaterialId, addMaterial, hasMaterial, releaseMaterial,
} from "../void3d/draw";
import { contextOf, meshAt, materialAt } from "./drawHelpers";

function node(scene: Scene3D, parent: NodeId3D | null, material: MaterialId): NodeId3D {
	const result = addMeshNode(scene, parent, Transform3D.identity(),
		scene.context.meshAt(0), material);
	if (!result.ok) { unreachable; }
	return result.value;
}

function shown(scene: Scene3D, id: NodeId3D, expected: MaterialId): boolean {
	const result = scene.getMaterials(id, false);
	if (!result.ok || result.value.length != 1) { return false; }
	const current = result.value[0];
	return current.store == expected.store && current.index == expected.index &&
		current.generation == expected.generation;
}

test "material swap transfers one pin and refreshes a retained draw item" {
	const context = contextOf(1, 2);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const first = context.materialAt(0);
	const second = context.materialAt(1);
	const id = node(scene, scene.rootId(), first);
	let items: Vec<DrawItem> = [];
	assert collectDrawList(scene, items) == 1;
	assert items[0].material.index == first.index;
	assert !scene.structureChanged;
	const changed = setMaterialOf(scene, id, second);
	assert changed.ok;
	if (changed.ok) { assert changed.value == id.index; }
	assert context.materialPins[first.index] == 0 && context.materialHolders[first.index] == 1;
	assert context.materialPins[second.index] == 1 && context.materialHolders[second.index] == 2;
	assert shown(scene, id, second);
	assert !scene.structureChanged;
	const refreshed = refreshChecked(scene, items);
	assert refreshed.ok;
	if (refreshed.ok) { assert refreshed.value == 1; }
	assert items[0].material.store == second.store;
	assert items[0].material.index == second.index;
	assert items[0].material.generation == second.generation;
}

test "self material swap keeps a material alive when only its node pins it" {
	const context = contextOf(1, 1);
	const scene = Scene3D.create(context);
	const material = context.materialAt(0);
	const id = node(scene, scene.rootId(), material);
	const released = releaseMaterial(context, material);
	assert released.ok;
	if (released.ok) { assert released.value == 1; }
	assert setMaterialOf(scene, id, material).ok;
	assert context.hasMaterial(material);
	assert context.materialPins[material.index] == 1;
	assert context.materialHolders[material.index] == 1;
	assert shown(scene, id, material);
	const replacement = addMaterial(context, { ...context.materials[material.index] });
	assert replacement.ok;
	if (!replacement.ok) { closeScene(scene); return; }
	assert setMaterialOf(scene, id, replacement.value).ok;
	assert !context.hasMaterial(material);
	assert context.materialPins[replacement.value.index] == 1;
	assert context.materialHolders[replacement.value.index] == 2;
	assert releaseMaterial(context, replacement.value).ok;
	closeScene(scene);
	assert !context.hasMaterial(replacement.value);
}

test "material swap rejects foreign and stale generations before changing either ownership" {
	const context = contextOf(1, 2);
	const foreign = contextOf(1, 1);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const first = context.materialAt(0);
	const stale = context.materialAt(1);
	const id = node(scene, scene.rootId(), first);
	const wrongStore = setMaterialOf(scene, id, foreign.materialAt(0));
	assert !wrongStore.ok;
	if (!wrongStore.ok) { assert wrongStore.error == SceneError.ForeignMaterial; }
	assert shown(scene, id, first);
	assert context.materialPins[first.index] == 1 && context.materialHolders[first.index] == 2;
	assert foreign.materialPins[0] == 0 && foreign.materialHolders[0] == 1;
	assert releaseMaterial(context, stale).ok;
	const replacement = addMaterial(context, { ...context.materials[first.index] });
	assert replacement.ok;
	if (!replacement.ok) { return; }
	assert replacement.value.index == stale.index;
	assert replacement.value.generation != stale.generation;
	const oldGeneration = setMaterialOf(scene, id, stale);
	assert !oldGeneration.ok;
	if (!oldGeneration.ok) { assert oldGeneration.error == SceneError.StaleMaterial; }
	assert shown(scene, id, first);
	assert context.materialPins[first.index] == 1 && context.materialHolders[first.index] == 2;
	assert context.materialPins[stale.index] == 0 && context.materialHolders[stale.index] == 1;
	assert setMaterialOf(scene, id, replacement.value).ok;
	assert shown(scene, id, replacement.value);
}

test "material swap changes only selected node not its children or shared material peers" {
	const context = contextOf(1, 2);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const first = context.materialAt(0);
	const second = context.materialAt(1);
	const parent = node(scene, scene.rootId(), first);
	const child = node(scene, parent, first);
	const peer = node(scene, scene.rootId(), first);
	assert context.materialPins[first.index] == 3;
	assert setMaterialOf(scene, parent, second).ok;
	assert shown(scene, parent, second);
	assert shown(scene, child, first);
	assert shown(scene, peer, first);
	assert context.materialPins[first.index] == 2 && context.materialPins[second.index] == 1;
}

test "material swap works on live detached nodes without attaching them" {
	const context = contextOf(1, 2);
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const id = node(scene, null, context.materialAt(0));
	const second = context.materialAt(1);
	assert setMaterialOf(scene, id, second).ok;
	assert shown(scene, id, second);
	let items: Vec<DrawItem> = [];
	assert collectDrawList(scene, items) == 0;
}
