import { loadGltf, GltfError, validateGltfGraph } from "../void3d/gltf";
import { approx } from "./helpers";
import { contextOf, meshAt, materialAt } from "./drawHelpers";
import { vec3 } from "../math/math3d";
import { Face } from "../gpu/state";
import {
	DrawItem, EXTERNAL_GENERATION, meshFor, closeContext, releaseMesh, releaseMaterial,
} from "../void3d/draw";
import { Program, ProgramKey, withSkin } from "../void3d/gpu3d";
import { indexAt, indexCount, vertexCount } from "../void3d/meshData";
import { GltfMeshBinding, GltfSceneError, addGltfBoundNodes } from "../void3d/gltfScene";
import {
	Scene3D, Transform3D, fromTranslation, rootId, nodeIdAt, closeScene, refreshChecked,
	setLocal, setPickable,
} from "../void3d/scene";
import { pickNearest } from "../void3d/pick";

function push32(ref bytes: Vec<uint8>, bits: uint32): void {
	for (let shift = 0; shift < 32; shift += 8) {
		bytes.push(((bits >> (shift as uint32)) & 255) as uint8);
	}
}

function payload(
	wide: boolean, asymmetric: boolean = false, index32: boolean = false,
): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const bits of [
		0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32,
		0 as uint32, 0x3f800000 as uint32, 0 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
	]) { push32(bytes, bits); }
	if (index32) {
		for (const index of [0, 1, 2]) { push32(bytes, index as uint32); }
	} else {
		for (const value of [0, 0, 1, 0, 2, 0, 0, 0]) { bytes.push(value as uint8); }
	}
	for (const joint of [0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0]) {
		bytes.push(joint as uint8);
		if (wide) { bytes.push(0); }
	}
	for (const bits of [
		0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32,
		0x3e800000 as uint32, 0x3f400000 as uint32, 0 as uint32, 0 as uint32,
	]) { push32(bytes, bits); }
	for (let joint = 0; joint < 2; joint++) {
		for (let cell = 0; cell < 16; cell++) {
			let bits: uint32 = cell % 5 == 0 ? 0x3f800000 as uint32 : 0 as uint32;
			if (asymmetric && cell == 12) { bits = 0xbf800000 as uint32; }
			if (asymmetric && joint == 1 && cell == 13) { bits = 0xc0000000 as uint32; }
			push32(bytes, bits);
		}
	}
	return move bytes;
}

function document(
	wide: boolean, skinned: boolean, matrices: boolean,
	joints: string = "[2,3]", matrixCount: int32 = 2, index32: boolean = false,
): string {
	const jointBytes: int32 = wide ? 24 : 12;
	const jointOffset: int32 = index32 ? 84 : 80;
	const weights: int32 = jointOffset + jointBytes;
	const inverseBind: int32 = weights + 48;
	const component: int32 = wide ? 5123 : 5121;
	const skin: string = skinned ? ',"skin":0' : "";
	const ibm: string = matrices ? ',"inverseBindMatrices":5' : "";
	return `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
		+ `"buffers":[{"byteLength":${inverseBind + 128}}],"bufferViews":[`
		+ `{"buffer":0,"byteLength":36},`
		+ `{"buffer":0,"byteOffset":36,"byteLength":36},`
		+ `{"buffer":0,"byteOffset":72,"byteLength":${index32 ? 12 : 6}},`
		+ `{"buffer":0,"byteOffset":${jointOffset},"byteLength":${jointBytes}},`
		+ `{"buffer":0,"byteOffset":${weights},"byteLength":48},`
		+ `{"buffer":0,"byteOffset":${inverseBind},"byteLength":128}],"accessors":[`
		+ `{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",`
		+ `"min":[0,0,0],"max":[1,1,0]},`
		+ `{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},`
		+ `{"bufferView":2,"componentType":${index32 ? 5125 : 5123},`
		+ `"count":3,"type":"SCALAR"},`
		+ `{"bufferView":3,"componentType":${component},"count":3,"type":"VEC4"},`
		+ `{"bufferView":4,"componentType":5126,"count":3,"type":"VEC4"},`
		+ `{"bufferView":5,"componentType":5126,"count":${matrixCount},"type":"MAT4"}],`
		+ `"meshes":[{"primitives":[{"attributes":{`
		+ `"POSITION":0,"NORMAL":1,"JOINTS_0":3,"WEIGHTS_0":4},"indices":2}]}],`
		+ `"nodes":[{"translation":[3,0,0],"children":[1,2]},`
		+ `{"mesh":0,"translation":[100,0,0]${skin}},`
		+ `{"translation":[1,0,0],"children":[3]},{"translation":[0,2,0]}],`
		+ `"skins":[{"joints":${joints},"skeleton":2${ibm}}]}`;
}

test "glTF nonindexed skin keeps implicit corner source ids through palette partitioning" {
	for (const wide of [false, true]) {
		const json = document(wide, true, true).replace(`,"indices":2`, "");
		const loaded = loadGltf(json, payload(wide));
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		assert loaded.value.meshes[0].indexCount() == 0;
		const skin = loaded.value.skinMeshes[0];
		assert skin !== null;
		if (skin === null) { continue; }
		assert skin.mesh.hasSkin && skin.mesh.indexCount() == 3;
		assert skin.partition.parts.length == 1 && skin.vertexSources.length == 3;
		for (let i = 0; i < 3; i++) {
			assert skin.vertexSources[skin.mesh.indexAt(i) as int32] == i;
		}
		assert skin.influences.joints[4] == 1;
		assert skin.influences.weights[8] == 0.25 && skin.influences.weights[9] == 0.75;
	}
}

test "glTF skin without NORMAL keeps each duplicated corner's joints and weights" {
	for (const wide of [false, true]) {
		const json = document(wide, true, true).replace(`"NORMAL":1,`, "")
			.replace(`"attributes":`, `"mode":6,"attributes":`);
		const loaded = loadGltf(json, payload(wide));
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		assert loaded.value.meshes[0].vertexCount() == 3;
		assert loaded.value.meshes[0].indexCount() == 0;
		const skin = loaded.value.skinMeshes[0];
		assert skin !== null;
		if (skin === null) { continue; }
		assert skin.vertexSources.length == 3;
		assert skin.vertexSources[0] == 1 && skin.vertexSources[1] == 2;
		assert skin.vertexSources[2] == 0;
		assert skin.influences.joints[0] == 1 && skin.influences.joints[4] == 0;
		assert skin.influences.weights[4] == 0.25 && skin.influences.weights[5] == 0.75;
	}
}

test "glTF fans preserve canonical skin corners for explicit and implicit sources" {
	const expected: Vec<int32> = [1, 2, 0];
	for (const wide of [false, true]) {
		for (const index32 of [false, true]) {
			for (const indexed of [false, true]) {
				const json = document(wide, true, true, "[2,3]", 2, index32)
					.replace(`"attributes":`, `"mode":6,"attributes":`);
				const loaded = loadGltf(indexed ? json : json.replace(`,"indices":2`, ""),
					payload(wide, false, index32));
				assert loaded.ok;
				if (!loaded.ok) { continue; }
				assert loaded.value.meshes[0].indexCount() == 3;
				const skin = loaded.value.skinMeshes[0];
				assert skin !== null;
				if (skin === null) { continue; }
				assert skin.mesh.hasSkin && skin.mesh.indexCount() == 3;
				assert (skin.mesh.wideIndices !== null) == (indexed && index32);
				assert skin.partition.parts.length == 1 && skin.vertexSources.length == 3;
				for (let i = 0; i < 3; i++) {
					assert skin.vertexSources[skin.mesh.indexAt(i) as int32] == expected[i];
				}
				assert skin.influences.joints[4] == 1;
				assert skin.influences.weights[8] == 0.25 && skin.influences.weights[9] == 0.75;
			}
		}
	}
}

test "glTF skin attributes keep a rigid node a valid passing neighbour" {
	for (const wide of [false, true]) {
		const loaded = loadGltf(document(wide, false, wide), payload(wide, wide));
		assert loaded.ok;
		if (!loaded.ok) { return; }
		assert loaded.value.skinMeshes.length == 1;
		const skin = loaded.value.skinMeshes[0];
		assert skin !== null;
		if (skin === null) { return; }
		assert !loaded.value.meshes[0].hasSkin && skin.mesh.hasSkin;
		assert skin.influences.joints[4] == 1;
		assert skin.influences.weights[8] == 0.25 && skin.influences.weights[9] == 0.75;
		assert skin.partition.parts.length == 1;
		assert skin.vertexSources.length == 3 && skin.vertexSources[2] == 2;
		assert loaded.value.skins.length == 1;
		assert loaded.value.skins[0].joints[0] == 2 && loaded.value.skins[0].joints[1] == 3;
		assert loaded.value.skins[0].inverseBindMatrices.length == 2;
		const inverse = loaded.value.skins[0].inverseBindMatrices[1];
		assert inverse.m44 == 1.0 && inverse.m14 == 0.0;
		assert inverse.m41 == (wide ? -1.0 : 0.0);
		assert inverse.m42 == (wide ? -2.0 : 0.0);
	}
}

test "glTF skin tables refuse duplicate out of range or insufficient source slots" {
	for (const joints of ["[2,2]", "[2,4]"]) {
		const loaded = loadGltf(document(false, false, false, joints), payload(false));
		assert !loaded.ok && loaded.error == GltfError.BadNode;
	}
	const short = loadGltf(document(false, false, true, "[2,3]", 1), payload(false));
	assert !short.ok && short.error == GltfError.Unsupported;
}

test "glTF inverse binds refuse nonfinite and nonaffine matrix values" {
	for (const affine of [false, true]) {
		let bytes = payload(false);
		const at: int32 = 140 + (affine ? 12 : 0);
		const bits: uint32 = affine ? 0x3f800000 as uint32 : 0x7fc00000 as uint32;
		for (let byte = 0; byte < 4; byte++) {
			bytes[at + byte] = ((bits >> ((byte * 8) as uint32)) & 255) as uint8;
		}
		const loaded = loadGltf(document(false, false, true), bytes);
		assert !loaded.ok && loaded.error == GltfError.Unsupported;
	}
}

test "glTF skin graph requires mapped joint ancestry before Scene attachment" {
	const loaded = loadGltf(document(false, false, false), payload(false));
	assert loaded.ok;
	if (!loaded.ok) { return; }
	let data = loaded.value;
	data.nodes[1].skin = 0;
	data.nodes[1].skinMeshes = [0];
	data.nodes[1].mesh = -1;
	assert validateGltfGraph(data).ok;
	data.skins[0].skeleton = 1;
	assert !validateGltfGraph(data).ok;
	data.skins[0].skeleton = 2;
	data.nodes[0].children = [1];
	assert !validateGltfGraph(data).ok;
}

test "glTF two joint skin accepts byte and short joint tables with omitted identity IBM" {
	for (const wide of [false, true]) {
		const loaded = loadGltf(document(wide, true, false), payload(wide));
		assert loaded.ok;
	}
}

test "glTF skin accepts an explicit affine MAT4 inverse bind table" {
	for (const wide of [false, true]) {
		const loaded = loadGltf(document(wide, true, true), payload(wide));
		assert loaded.ok;
	}
}

test "glTF UINT32 skin indices keep explicit width for byte and short joint accessors" {
	for (const wide of [false, true]) {
		const loaded = loadGltf(
			document(wide, true, true, "[2,3]", 2, true), payload(wide, true, true),
		);
		assert loaded.ok;
		if (!loaded.ok) { return; }
		const source = loaded.value.skinMeshes[0];
		assert source !== null;
		if (source === null) { return; }
		assert source.mesh.wideIndices !== null && source.mesh.indices.length == 0;
		assert source.mesh.indexCount() == 3 && source.mesh.indexAt(2) == 2;
		assert source.influences.joints[4] == 1 && source.vertexSources[2] == 2;
		assert source.partition.parts.length == 1;
	}
}

test "imported skin Scene rolls back missing bindings and keeps independent world poses" {
	for (const index32 of [false, true]) {
		for (let variant = 0; variant < 4; variant++) {
			const wide: boolean = variant % 2 != 0;
			let json = document(wide, true, true, "[2,3]", 2, index32);
			if (variant >= 2) {
				json = json.replaceAll('"translation":[3,0,0]',
					'"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,3,0,0,1]');
				json = json.replaceAll('"translation":[1,0,0]',
					'"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,1,0,0,1]');
				json = json.replaceAll('"translation":[0,2,0]',
					'"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,2,0,1]');
			}
			const loaded = loadGltf(json, payload(wide, true, index32));
			assert loaded.ok;
			if (!loaded.ok) { return; }
			const source = loaded.value.skinMeshes[0];
			assert source !== null;
			if (source === null) { return; }
			const context = contextOf(1, 1);
			defer closeContext(context);
			defer releaseMesh(context, context.meshAt(0));
			defer releaseMaterial(context, context.materialAt(0));
			context.meshData[0] = source.mesh;
			context.meshes[0] = source.mesh.meshFor(0, 1, EXTERNAL_GENERATION);
			context.materials[0].program = ProgramKey.of(Program.Lit).withSkin();
			context.materials[0].pass.culling = Face.None;
			assert context.meshes[0].index32 == index32;
			const scene = Scene3D.create(context);
			defer closeScene(scene);
			const missing: Vec<GltfMeshBinding> = [
				{ mesh: context.meshAt(0), material: context.materialAt(0) },
			];
			const refused = addGltfBoundNodes(scene, scene.rootId(), loaded.value, missing);
			assert !refused.ok;
			if (!refused.ok) { assert refused.error == GltfSceneError.BadMeshBinding; }
			assert scene.nodes[scene.rootId().index].children.length == 0;
			assert context.meshPins[0] == 0 && context.materialPins[0] == 0;
			const bindings: Vec<GltfMeshBinding> = [
				{ mesh: context.meshAt(0), material: context.materialAt(0),
					skinMesh: context.meshAt(0), skinMaterial: context.materialAt(0) },
			];
			const actorA = addGltfBoundNodes(scene, scene.rootId(), loaded.value, bindings);
			const actorB = addGltfBoundNodes(scene, scene.rootId(), loaded.value, bindings);
			assert actorA.ok && actorB.ok;
			if (!actorA.ok || !actorB.ok) { return; }
			assert actorA.value.count == 5 && actorA.value.nodes.length == 4;
			assert actorA.value.nodes[2] != actorB.value.nodes[2];
			const geometryA = scene.meshes[0].skinGeometry;
			const geometryB = scene.meshes[1].skinGeometry;
			assert geometryA !== null && geometryB !== null;
			if (geometryA === null || geometryB === null) { return; }
			assert geometryA.pose !== geometryB.pose;
			assert geometryA.pose.joints[0] == actorA.value.nodes[2];
			let items: Vec<DrawItem> = [];
			assert refreshChecked(scene, items).ok && items.length == 2;
			assert geometryA.pose.revision == 1 && geometryB.pose.revision == 1;
			assert approx(geometryA.mesh.vertices[0], 3.0);
			assert geometryA.mesh.bounds.max.x < 5.0;
			const accepted = geometryA.pose.blocks[0][3];
			setLocal(scene, actorA.value.nodes[2], Transform3D.fromTranslation(vec3(2, 0, 0)));
			assert geometryA.pose.revision == 1 && geometryA.pose.blocks[0][3] == accepted;
			assert refreshChecked(scene, items).ok;
			assert geometryA.pose.revision == 2 && geometryB.pose.revision == 2;
			assert approx(geometryA.mesh.vertices[0], 4.0);
			assert approx(geometryB.mesh.vertices[0], 3.0);
			assert (geometryA.mesh.wideIndices !== null) == index32;
			const target = scene.nodeIdAt(scene.nodes[actorA.value.nodes[1].index].children[0]);
			setPickable(scene, target, true);
			const hit = pickNearest(scene, {
				origin: vec3(4.25, 0.25, 2), direction: vec3(0, 0, -1),
			});
			assert hit.ok;
			if (hit.ok) {
				assert hit.value.mesh == target && approx(hit.value.distance, 2.0);
			}
		}
	}
}

test "imported skin late binding refusal rolls back earlier mesh pins and permits retry" {
	for (const index32 of [false, true]) {
		const loaded = loadGltf(
			document(true, true, true, "[2,3]", 2, index32), payload(true, true, index32),
		);
		assert loaded.ok;
		if (!loaded.ok) { return; }
		let data = loaded.value;
		const source = data.skinMeshes[0];
		assert source !== null;
		if (source === null) { return; }
		data.meshes.push(data.meshes[0]);
		data.meshMaterials.push(data.meshMaterials[0]);
		data.skinMeshes.push(data.skinMeshes[0]);
		data.nodes[1].skinMeshes = [0, 1];
		const context = contextOf(2, 2);
		defer closeContext(context);
		defer releaseMesh(context, context.meshAt(0));
		defer releaseMesh(context, context.meshAt(1));
		defer releaseMaterial(context, context.materialAt(0));
		defer releaseMaterial(context, context.materialAt(1));
		for (let mesh = 0; mesh < 2; mesh++) {
			context.meshData[mesh] = source.mesh;
			context.meshes[mesh] = source.mesh.meshFor(0, 1, EXTERNAL_GENERATION);
		}
		context.materials[1].program = ProgramKey.of(Program.Lit).withSkin();
		const bindings: Vec<GltfMeshBinding> = [
			{ mesh: context.meshAt(0), material: context.materialAt(1),
				skinMesh: context.meshAt(0), skinMaterial: context.materialAt(1) },
			{ mesh: context.meshAt(1), material: context.materialAt(0),
				skinMesh: context.meshAt(1), skinMaterial: context.materialAt(0) },
		];
		const scene = Scene3D.create(context);
		defer closeScene(scene);
		const refused = addGltfBoundNodes(scene, scene.rootId(), data, bindings);
		assert !refused.ok;
		if (!refused.ok) { assert refused.error == GltfSceneError.SceneRefused; }
		assert scene.nodes[scene.rootId().index].children.length == 0;
		for (let slot = 0; slot < 2; slot++) {
			assert context.meshPins[slot] == 0 && context.materialPins[slot] == 0;
			assert context.meshHolders[slot] == 1 && context.materialHolders[slot] == 1;
		}
		context.materials[0].program = ProgramKey.of(Program.Lit).withSkin();
		const retried = addGltfBoundNodes(scene, scene.rootId(), data, bindings);
		assert retried.ok;
		if (!retried.ok) { return; }
		let items: Vec<DrawItem> = [];
		assert refreshChecked(scene, items).ok && items.length == 2;
		assert items[0].skinGeometry !== null && items[1].skinGeometry !== null;
		for (let slot = 0; slot < 2; slot++) {
			assert context.meshPins[slot] == 1 && context.materialPins[slot] == 1;
		}
	}
}
