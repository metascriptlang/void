import {
	Scene3D, MorphNodeError, SceneSyncError, SceneMorph, NodeId3D, Transform3D, addGroup,
	addMorphMeshNode, addSkinMorphMeshNode, bindSceneMorph, setMorphWeights, rootId, closeScene,
	refreshChecked, setLocal, setPickable, remove,
} from "../void3d/scene";
import { SkinGeometry } from "../void3d/skinGeometry";
import { SkinPose, bind as bindPose } from "../void3d/skinPose";
import { SkinPalette, create } from "../void3d/skinPalette";
import { MorphData, MorphGeometryError, MorphPrimitiveInput, rebased } from "../void3d/morphGeometry";
import { MeshData, addVertex, addTriangle, addSkinAttributes, stride } from "../void3d/meshData";
import { DrawItem, MeshId, VertexStorage, validSkin } from "../void3d/draw";
import { Program, ProgramKey, VertexLayout, withSkin } from "../void3d/gpu3d";
import { loadGltf } from "../void3d/gltf";
import { GltfMeshBinding, GltfSceneError, addGltfBoundNodes } from "../void3d/gltfScene";
import { pickNearest } from "../void3d/pick";
import { identity, vec3 } from "../math/math3d";
import { Face } from "../gpu/state";
import { contextOf, meshAt, materialAt } from "./drawHelpers";

const STRIDE: int32 = skinnedTriangle().stride();

function plainTriangle(): MeshData {
	let mesh = MeshData.empty();
	for (const point of [vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0)]) {
		const added = addVertex(mesh, point, vec3(0, 0, 1), { red: 1, green: 1, blue: 1, alpha: 1 });
		if (!added.ok) { unreachable; }
	}
	return move mesh;
}

function skinnedTriangle(): MeshData {
	let mesh = plainTriangle();
	const packed = addSkinAttributes(mesh,
		[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]);
	if (!packed.ok) { unreachable; }
	return move mesh;
}

// Target 0 lifts every vertex by 5 in y, target 1 moves it by 1 in x.
function morphInput(base: MeshData): MorphPrimitiveInput {
	return {
		base: base, sourceVertexCount: 3, sourceVertices: [0, 1, 2],
		targets: [
			{ positions: [0, 5, 0, 0, 5, 0, 0, 5, 0], normals: [], tangents: [] },
			{ positions: [1, 0, 0, 1, 0, 0, 1, 0, 0], normals: [], tangents: [] },
		],
	};
}

function morphOf(base: MeshData): Readonly<MorphData> {
	const made = MorphData.create([morphInput(base)], 2);
	if (!made.ok) { unreachable; }
	return made.value;
}

function skinMorph(weights: Vec<float32>): SceneMorph {
	const data = morphOf(plainTriangle()).rebased([skinnedTriangle()]);
	if (!data.ok) { unreachable; }
	const bound = bindSceneMorph(data.value, weights);
	if (!bound.ok) { unreachable; }
	return bound.value;
}

interface Fixture {
	scene: Scene3D;
	geometry: SkinGeometry;
}

// Mesh `i` is a private skin-layout dynamic mesh with no GPU buffer; the bone stands at x=10
// and doubles y, so the order morph then skin differs from skin then morph.
function fixture(meshes: int32 = 1): Fixture {
	const context = contextOf(meshes, 1);
	for (let i = 0; i < meshes; i++) {
		context.meshData[i] = skinnedTriangle();
		context.meshStorage[i] = VertexStorage.Pending;
		context.meshes[i].layout = VertexLayout.SkinLit;
		context.meshes[i].vertexCount = 3;
	}
	context.materials[0].program = ProgramKey.of(Program.Lit).withSkin();
	context.materials[0].pass.culling = Face.None;
	const scene = Scene3D.create(context);
	const bone = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0), scale: vec3(2, 2, 2),
	});
	const palette = SkinPalette.create([0]);
	if (!palette.ok) { unreachable; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	if (!pose.ok) { unreachable; }
	const source = skinnedTriangle();
	let joints: Vec<int32> = [];
	let weights: Vec<float32> = [];
	for (let vertex = 0; vertex < 3; vertex++) {
		for (let slot = 0; slot < 4; slot++) { joints.push(0); weights.push(slot == 0 ? 1.0 : 0.0); }
	}
	const geometry = SkinGeometry.bind(source, { joints: joints, weights: weights }, pose.value);
	if (!geometry.ok) { unreachable; }
	return { scene: scene, geometry: geometry.value };
}

function place(
	f: Fixture, morph: SceneMorph, mesh: int32 = 0,
): Result<NodeId3D, MorphNodeError> {
	return addSkinMorphMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		f.scene.context.meshAt(mesh), f.scene.context.materialAt(0), f.geometry, 0, null, morph, 0);
}

test "a skinned morph node poses the morphed vertices and bounds, picks and draws agree" {
	const f = fixture();
	defer closeScene(f.scene);
	const context = f.scene.context;
	const morph = skinMorph([1, 0]);
	const node = place(f, morph);
	assert node.ok;
	if (!node.ok) { return; }
	setPickable(f.scene, node.value, true);
	let items: Vec<DrawItem> = [];
	assert refreshChecked(f.scene, items).ok && items.length == 1;
	assert f.geometry.spatialReady();
	assert items[0].skinGeometry === f.geometry && items[0].mesh == context.meshAt(0);
	assert items[0].validSkin(context.materials[0].program);
	const posed = f.geometry.mesh;
	assert posed.vertices[0] == 10 && posed.vertices[1] == 10 && posed.vertices[2] == 0;
	assert posed.vertices[STRIDE] == 12 && posed.vertices[STRIDE + 1] == 10;
	assert posed.vertices[2 * STRIDE] == 10 && posed.vertices[2 * STRIDE + 1] == 12;
	assert posed.bounds.min.x == 10 && posed.bounds.min.y == 10;
	assert posed.bounds.max.x == 12 && posed.bounds.max.y == 12;
	assert context.meshData[0].vertices[1] == 5 && context.meshData[0].bounds.max.y == 6;
	assert context.meshStorage[0] == VertexStorage.Pending;
	const morphed = pickNearest(f.scene, { origin: vec3(10.5, 10.25, 2), direction: vec3(0, 0, -1) });
	assert morphed.ok;
	if (morphed.ok) { assert morphed.value.mesh.index == node.value.index && morphed.value.distance == 2; }
	assert !pickNearest(f.scene, { origin: vec3(10.5, 0.25, 2), direction: vec3(0, 0, -1) }).ok;
	assert !pickNearest(f.scene, { origin: vec3(10.5, 5.25, 2), direction: vec3(0, 0, -1) }).ok;
	assert setMorphWeights(morph, [0, 1]).ok;
	setLocal(f.scene, f.geometry.pose.joints[0], {
		...Transform3D.identity(), position: vec3(20, 0, 0), scale: vec3(2, 2, 2),
	});
	assert refreshChecked(f.scene, items).ok;
	assert f.geometry.mesh.bounds.min.x == 22 && f.geometry.mesh.bounds.max.x == 24;
	assert f.geometry.mesh.bounds.min.y == 0 && f.geometry.mesh.bounds.max.y == 2;
	const moved = pickNearest(f.scene, { origin: vec3(22.5, 0.25, 2), direction: vec3(0, 0, -1) });
	assert moved.ok;
}

test "a skinned morph node keeps the joint and weight attributes of the mesh untouched" {
	const f = fixture();
	defer closeScene(f.scene);
	const node = place(f, skinMorph([1, 1]));
	assert node.ok;
	let items: Vec<DrawItem> = [];
	assert refreshChecked(f.scene, items).ok;
	const base = skinnedTriangle();
	const shown = f.scene.context.meshData[0];
	for (let vertex = 0; vertex < 3; vertex++) {
		for (let field = STRIDE - 8; field < STRIDE; field++) {
			assert shown.vertices[vertex * STRIDE + field] == base.vertices[vertex * STRIDE + field];
		}
	}
	assert shown.vertices[0] == 1 && shown.vertices[1] == 5;
}

test "a skinned morph node refuses the shapes it cannot deform and leaves no pin behind" {
	const f = fixture(5);
	defer closeScene(f.scene);
	const context = f.scene.context;
	const morph = skinMorph([0, 0]);
	context.meshStorage[1] = VertexStorage.Immutable;
	context.meshHolders[2] = 2;
	context.meshData[3].vertices[0] = 9;
	context.meshData[4].indices.push(0);
	const stat = place(f, morph, 1);
	assert !stat.ok;
	if (!stat.ok) { assert stat.error == MorphNodeError.Mesh; }
	const shared = place(f, morph, 2);
	assert !shared.ok;
	if (!shared.ok) { assert shared.error == MorphNodeError.Mesh; }
	const drifted = place(f, morph, 3);
	assert !drifted.ok;
	if (!drifted.ok) { assert drifted.error == MorphNodeError.SkinMesh; }
	const indexed = place(f, morph, 4);
	assert !indexed.ok;
	const plain = bindSceneMorph(morphOf(plainTriangle()), [0, 0]);
	assert plain.ok;
	if (!plain.ok) { return; }
	const wrongLayout = place(f, plain.value);
	assert !wrongLayout.ok;
	if (!wrongLayout.ok) { assert wrongLayout.error == MorphNodeError.Skin; }
	const plainNode = addMorphMeshNode(f.scene, f.scene.rootId(), Transform3D.identity(),
		context.meshAt(0), context.materialAt(0), morph, 0);
	assert !plainNode.ok;
	if (!plainNode.ok) { assert plainNode.error == MorphNodeError.Skin; }
	context.materials[0].program = ProgramKey.of(Program.Lit);
	const flat = place(f, morph);
	assert !flat.ok;
	if (!flat.ok) { assert flat.error == MorphNodeError.SkinMesh; }
	assert f.scene.morphNodes == 0 && f.scene.skinNodes == 0 && f.scene.meshes.length == 0;
	for (let i = 0; i < 5; i++) { assert context.meshPins[i] == 0; }
	assert context.materialPins[0] == 0;
}

test "a plain morph node refuses a mesh whose indices differ from the morph base" {
	const context = contextOf(1, 1);
	let mesh = plainTriangle();
	assert addTriangle(mesh, 0, 2, 1).ok;
	context.meshData[0] = {...mesh};
	context.meshStorage[0] = VertexStorage.Pending;
	let base = plainTriangle();
	assert addTriangle(base, 0, 1, 2).ok;
	const bound = bindSceneMorph(morphOf(base), [0, 0]);
	assert bound.ok;
	if (!bound.ok) { return; }
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const refused = addMorphMeshNode(scene, scene.rootId(), Transform3D.identity(),
		context.meshAt(0), context.materialAt(0), bound.value, 0);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == MorphNodeError.Mesh; }
	assert scene.morphNodes == 0 && context.meshPins[0] == 0;
}

test "a skinned morph node gives back its mesh and counts at remove" {
	const f = fixture();
	defer closeScene(f.scene);
	const context = f.scene.context;
	const node = place(f, skinMorph([0, 0]));
	assert node.ok;
	if (!node.ok) { return; }
	assert f.scene.morphNodes == 1 && f.scene.skinNodes == 1;
	assert context.meshPins[0] == 1 && context.meshHolders[0] == 2;
	const held: MeshId = context.meshAt(0);
	assert remove(f.scene, node.value) == 1;
	assert f.scene.morphNodes == 0 && f.scene.skinNodes == 0;
	assert !context.hasMesh(held);
}

test "a lost joint after a morph publish is the skin error, not the previous shape" {
	const f = fixture();
	defer closeScene(f.scene);
	const node = place(f, skinMorph([1, 0]));
	assert node.ok;
	let items: Vec<DrawItem> = [];
	assert refreshChecked(f.scene, items).ok;
	assert remove(f.scene, f.geometry.pose.joints[0]) == 1;
	const failed = refreshChecked(f.scene, items);
	assert !failed.ok;
	if (!failed.ok) { assert failed.error == SceneSyncError.Skin; }
}

test "rebased keeps the offsets and refuses a base that is not the same vertices" {
	const data = morphOf(plainTriangle());
	const same = data.rebased([skinnedTriangle()]);
	assert same.ok;
	if (same.ok) {
		assert same.value.primitives[0].base.hasSkin;
		assert same.value.primitives[0].targetVertexXyz.length == data.primitives[0].targetVertexXyz.length;
	}
	const none = data.rebased([]);
	assert !none.ok;
	if (!none.ok) { assert none.error == MorphGeometryError.Shape; }
	let moved = skinnedTriangle();
	moved.vertices[0] = 3;
	const drift = data.rebased([moved]);
	assert !drift.ok;
	if (!drift.ok) { assert drift.error == MorphGeometryError.Shape; }
	let longer = plainTriangle();
	assert addVertex(longer, vec3(0, 0, 1), vec3(0, 0, 1), { red: 1, green: 1, blue: 1, alpha: 1 }).ok;
	const count = data.rebased([longer]);
	assert !count.ok;
}

function push32(ref bytes: Vec<uint8>, bits: uint32): void {
	for (let shift = 0; shift < 32; shift += 8) {
		bytes.push(((bits >> (shift as uint32)) & 255) as uint8);
	}
}

function payload(): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const bits of [
		0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32,
		0 as uint32, 0x3f800000 as uint32, 0 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
	]) { push32(bytes, bits); }
	for (const value of [0, 0, 1, 0, 2, 0, 0, 0]) { bytes.push(value as uint8); }
	for (let i = 0; i < 12; i++) { bytes.push(0); }
	for (let vertex = 0; vertex < 3; vertex++) {
		for (const bits of [0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32]) {
			push32(bytes, bits);
		}
	}
	for (let vertex = 0; vertex < 3; vertex++) {
		for (const bits of [0 as uint32, 0x40a00000 as uint32, 0 as uint32]) { push32(bytes, bits); }
	}
	return move bytes;
}

const GLTF: string = `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
	+ `"buffers":[{"byteLength":176}],"bufferViews":[`
	+ `{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},`
	+ `{"buffer":0,"byteOffset":72,"byteLength":6},{"buffer":0,"byteOffset":80,"byteLength":12},`
	+ `{"buffer":0,"byteOffset":92,"byteLength":48},{"buffer":0,"byteOffset":140,"byteLength":36}],`
	+ `"accessors":[`
	+ `{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},`
	+ `{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},`
	+ `{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"},`
	+ `{"bufferView":3,"componentType":5121,"count":3,"type":"VEC4"},`
	+ `{"bufferView":4,"componentType":5126,"count":3,"type":"VEC4"},`
	+ `{"bufferView":5,"componentType":5126,"count":3,"type":"VEC3"}],`
	+ `"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"JOINTS_0":3,"WEIGHTS_0":4},`
	+ `"indices":2,"targets":[{"POSITION":5}]}],"weights":[1]}],`
	+ `"nodes":[{"children":[1,2]},{"mesh":0,"skin":0},{"translation":[1,0,0]}],`
	+ `"skins":[{"joints":[2],"skeleton":2}]}`;

test "an imported skin and morph primitive rebases onto its skin mesh and refuses a drifted one" {
	const loaded = loadGltf(GLTF, payload());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const data = loaded.value;
	assert data.nodes[1].skin !== null && data.nodes[1].morph !== null;
	const source = data.skinMeshes[0];
	assert source !== null;
	if (source === null) { return; }
	const rebasedData = data.morphs[0].data.rebased([source.mesh]);
	assert rebasedData.ok;
	if (rebasedData.ok) {
		const base = rebasedData.value.primitives[0].base;
		assert base.hasSkin && base.vertexCount() == 3 && base.indexCount() == 3;
		assert base.vertices[1] == source.mesh.vertices[1];
	}
	const context = contextOf(1, 1);
	context.meshData[0] = {...source.mesh};
	context.meshes[0].layout = VertexLayout.SkinLit;
	context.materials[0].program = ProgramKey.of(Program.Lit).withSkin();
	const bindings: Vec<GltfMeshBinding> = [
		{ mesh: context.meshAt(0), material: context.materialAt(0),
			skinMesh: context.meshAt(0), skinMaterial: context.materialAt(0) },
	];
	const scene = Scene3D.create(context);
	defer closeScene(scene);
	const again = loadGltf(GLTF, payload());
	assert again.ok;
	if (!again.ok) { return; }
	let drifted = again.value;
	let shifted = plainTriangle();
	shifted.vertices[0] = 7;
	drifted.morphs[0].data = morphOf(shifted);
	const refused = addGltfBoundNodes(scene, scene.rootId(), drifted, bindings);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == GltfSceneError.MorphRefused; }
	const third = loadGltf(GLTF, payload());
	assert third.ok;
	if (!third.ok) { return; }
	let uncovered = third.value;
	uncovered.nodes[1].skinMeshes.push(0);
	const invalid = addGltfBoundNodes(scene, scene.rootId(), uncovered, bindings);
	assert !invalid.ok;
	if (!invalid.ok) { assert invalid.error == GltfSceneError.InvalidData; }
	assert scene.nodes[scene.rootId().index].children.length == 0;
	assert context.meshPins[0] == 0 && context.materialPins[0] == 0;
}
