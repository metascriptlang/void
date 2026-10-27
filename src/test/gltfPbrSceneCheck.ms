// Imported pbr materials in the scene: the key and block gltfScene.ms makes of GltfMaterial.pbr,
// and the combinations the build has no pbr program for, refused by name before anything is made.

import { FilterMode, Wrap, RenderState } from "../gpu/state";
import { vec3 } from "../math/math3d";
import {
	loadGltf,
	GltfData,
	GltfMaterial,
	GltfAlphaMode,
	GltfTextureTransform,
	GltfPbrMaps,
	IDENTITY_TEXTURE_TRANSFORM,
} from "../void3d/gltf";
import {
	addGltfAssets,
	GltfAssets,
	GltfMaterialSetup,
	GltfSceneError,
	gltfProgramOf,
	gltfBlockOf,
	gltfTextureRoles,
} from "../void3d/gltfScene";
import { DrawContext } from "../void3d/draw";
import { TextureData, TextureId } from "../void3d/texture";
import {
	Program,
	ProgramKey,
	MATERIAL_UNIFORM_LENGTH,
	MATERIAL_DOUBLE_SIDED,
	MATERIAL_ALPHA_KILL,
	PBR_METALNESS,
	PBR_ROUGHNESS,
	PBR_OCCLUSION,
	PBR_MATERIAL_UNIFORM_LENGTH,
	PBR_OCCLUSION_STRENGTH,
	PBR_UV_MATRIX,
	PBR_UV_OFFSET,
	PBR_UV_SCROLL,
	EMISSIVE_COLOR,
	EMISSIVE_LENGTH,
	EMISSIVE_STRENGTH,
	MATERIAL_UNIFORM_SLOT,
	declares,
	emissiveBase,
	uniformBlockLength,
	withPbr,
	withShadowed,
	withCutout,
	withSkin,
} from "../void3d/gpu3d";

function setupOf(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [3.0, -1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0] };
}

function pbrMaterial(
	metallic: float32,
	roughness: float32,
	texture: int32 = -1,
	alphaMode: GltfAlphaMode = GltfAlphaMode.Opaque,
): GltfMaterial {
	return {
		texture: texture, doubleSided: true, alphaMode: alphaMode,
		alphaKill: alphaMode == GltfAlphaMode.Mask ? 0.5 : 0.0,
		emissiveTexture: -1, emissive: vec3(0.0, 0.0, 0.0), emissiveStrength: 1.0,
		normalTexture: -1, uvTransform: IDENTITY_TEXTURE_TRANSFORM,
		pbr: { metallic: metallic, roughness: roughness },
	};
}

function materialsOnly(materials: Readonly<Span<GltfMaterial>>, withTexture: boolean): GltfData {
	let list: Vec<GltfMaterial> = [];
	for (const material of materials) { list.push(material); }
	let textures: Vec<TextureData> = [];
	if (withTexture) {
		textures.push({
			pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Linear, wrap: Wrap.Clamp,
		});
	}
	return {
		meshes: [], meshMaterials: [], materials: list, textures: textures, nodes: [], sceneRoots: [],
	};
}

function refusalOf(material: GltfMaterial): GltfSceneError {
	let context: DrawContext = DrawContext.withUniformCapacity(256);
	const refused: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, materialsOnly([material], true), setupOf());
	if (refused.ok) { unreachable; }
	return refused.error;
}

test "a pbr material draws with the pbr key of its alpha mode and base texture" {
	const lit: ProgramKey = ProgramKey.of(Program.Lit).withShadowed().withPbr();
	assert gltfProgramOf(pbrMaterial(0.5, 0.5)) == lit;
	assert gltfProgramOf(pbrMaterial(0.5, 0.5, -1, GltfAlphaMode.Blend)) == lit;
	assert gltfProgramOf(pbrMaterial(0.5, 0.5, -1, GltfAlphaMode.Mask)) == lit.withCutout();
	const textured: ProgramKey = ProgramKey.of(Program.LitTextured).withShadowed().withPbr();
	assert gltfProgramOf(pbrMaterial(0.5, 0.5, 0)) == textured;
	assert gltfProgramOf(pbrMaterial(0.5, 0.5, 0, GltfAlphaMode.Mask)) == textured.withCutout();
	for (const key of [lit, lit.withCutout(), textured, textured.withCutout()]) {
		assert key.pbr && declares(key) && declares({ ...key, shadowed: false });
	}
}

test "a pbr material with a normal map has declared programs, shadowed or not, cut or not" {
	let mapped: GltfMaterial = pbrMaterial(0.5, 0.5, 0);
	mapped.normalTexture = 0;
	const key: ProgramKey = gltfProgramOf(mapped);
	assert key.pbr && key.normalMap && key.program == Program.LitTextured;
	assert declares(key) && declares({ ...key, shadowed: false });
	assert declares(key.withCutout()) && declares({ ...key.withCutout(), shadowed: false });
}

test "a pbr block is the setup's block, the flags written over it, then the factors" {
	const material: GltfMaterial = pbrMaterial(0.25, 0.75);
	const key: ProgramKey = gltfProgramOf(material);
	const block: Vec<float32> = gltfBlockOf(setupOf(), material, key);
	assert (block.length as int32) == PBR_MATERIAL_UNIFORM_LENGTH;
	assert block[0] == 3.0 && block[1] == -1.0;
	assert block[MATERIAL_DOUBLE_SIDED] == 1.0 && block[MATERIAL_ALPHA_KILL] == 0.0;
	assert block[PBR_METALNESS] == 0.25 && block[PBR_ROUGHNESS] == 0.75;
	assert block[PBR_OCCLUSION] == 1.0;
	const cut: GltfMaterial = pbrMaterial(1.0, 1.0, -1, GltfAlphaMode.Mask);
	assert gltfBlockOf(setupOf(), cut, gltfProgramOf(cut))[MATERIAL_ALPHA_KILL] == 0.5;
}

test "addGltfAssets reserves a pbr block per material and writes its factors" {
	let context: DrawContext = DrawContext.withUniformCapacity(256);
	const made: Result<GltfAssets, GltfSceneError> = addGltfAssets(
		context, materialsOnly([pbrMaterial(0.25, 0.75), pbrMaterial(1.0, 0.5)], false), setupOf());
	assert made.ok;
	if (!made.ok) { return; }
	assert context.liveMaterials() == 2;
	const first = context.materials[made.value.materials[0].index];
	const second = context.materials[made.value.materials[1].index];
	assert first.program.pbr && second.program.pbr;
	assert first.uniforms.length == PBR_MATERIAL_UNIFORM_LENGTH;
	const values: Vec<float32> = context.uniforms.values;
	assert values[first.uniforms.offset + PBR_METALNESS] == 0.25;
	assert values[first.uniforms.offset + PBR_ROUGHNESS] == 0.75;
	assert values[second.uniforms.offset + PBR_METALNESS] == 1.0;
	assert values[second.uniforms.offset + PBR_ROUGHNESS] == 0.5;
	assert MATERIAL_UNIFORM_LENGTH < PBR_MATERIAL_UNIFORM_LENGTH;
}

function emittingMaterial(): GltfMaterial {
	let emitting: GltfMaterial = pbrMaterial(0.25, 0.75, 0);
	emitting.emissiveTexture = 0;
	emitting.emissive = vec3(0.5, 0.0, 1.0);
	emitting.emissiveStrength = 3.0;
	return emitting;
}

test "a pbr material with an emissive map keeps the emissive vec4 after the pbr one" {
	const material: GltfMaterial = emittingMaterial();
	const key: ProgramKey = gltfProgramOf(material);
	assert key.pbr && key.emissive && key.program == Program.LitTextured;
	assert declares(key) && declares({ ...key, shadowed: false });
	assert declares(key.withCutout()) && declares({ ...key.withCutout(), shadowed: false });
	const block: Vec<float32> = gltfBlockOf(setupOf(), material, key);
	const at: int32 = emissiveBase(key);
	assert at == PBR_MATERIAL_UNIFORM_LENGTH;
	assert (block.length as int32) == at + EMISSIVE_LENGTH;
	assert (block.length as int32) == uniformBlockLength(key, MATERIAL_UNIFORM_SLOT);
	assert block[PBR_METALNESS] == 0.25 && block[PBR_ROUGHNESS] == 0.75;
	assert block[at + EMISSIVE_COLOR] > 0.7 && block[at + EMISSIVE_COLOR + 1] == 0.0;
	assert block[at + EMISSIVE_COLOR + 2] > 0.999 && block[at + EMISSIVE_STRENGTH] == 3.0;
	let mapped: GltfMaterial = emittingMaterial();
	mapped.normalTexture = 0;
	mapped.pbrMaps = { metalRough: 0, occlusion: 0, occlusionStrength: 0.4 };
	const both: ProgramKey = gltfProgramOf(mapped);
	assert both.pbr && both.pbrMaps && both.emissive && both.normalMap && declares(both);
	const full: Vec<float32> = gltfBlockOf(setupOf(), mapped, both);
	assert (full.length as int32) == uniformBlockLength(both, MATERIAL_UNIFORM_SLOT);
	assert full[PBR_OCCLUSION_STRENGTH] == 0.4;
	assert full[emissiveBase(both) + EMISSIVE_STRENGTH] == 3.0;
}

test "a pbr material that moves its UV keeps its key and writes the transform in its own block" {
	const shifted: GltfTextureTransform =
		{ ...IDENTITY_TEXTURE_TRANSFORM, offsetU: 0.5, scaleV: 2.0 };
	let moved: GltfMaterial = pbrMaterial(0.5, 0.5, 0);
	moved.uvTransform = shifted;
	const key: ProgramKey = gltfProgramOf(moved);
	assert key == gltfProgramOf(pbrMaterial(0.5, 0.5, 0)) && !key.uvTransform && declares(key);
	const block: Vec<float32> = gltfBlockOf(setupOf(), moved, key);
	assert (block.length as int32) == uniformBlockLength(key, MATERIAL_UNIFORM_SLOT);
	assert block[PBR_UV_MATRIX] == 1.0 && block[PBR_UV_MATRIX + 3] == 2.0;
	assert block[PBR_UV_OFFSET] == 0.5 && block[PBR_UV_SCROLL] == 0.0;
	const still: Vec<float32> = gltfBlockOf(setupOf(), pbrMaterial(0.5, 0.5, 0), key);
	assert still[PBR_UV_MATRIX] == 1.0 && still[PBR_UV_MATRIX + 3] == 1.0;
	assert still[PBR_UV_OFFSET] == 0.0;
	let both: GltfMaterial = emittingMaterial();
	both.uvTransform = shifted;
	const emitting: ProgramKey = gltfProgramOf(both);
	const lit: Vec<float32> = gltfBlockOf(setupOf(), both, emitting);
	assert (lit.length as int32) == uniformBlockLength(emitting, MATERIAL_UNIFORM_SLOT);
	assert lit[PBR_UV_OFFSET] == 0.5 && lit[emissiveBase(emitting) + EMISSIVE_STRENGTH] == 3.0;
}

function pushBits(ref bytes: Vec<uint8>, bits: uint32): void {
	for (let shift = 0; shift < 32; shift += 8) {
		bytes.push(((bits >> (shift as uint32)) & 255) as uint8);
	}
}

// One skinned triangle on two joints, as gltfSkinCheck.ms writes it, byte joints.
function skinPayload(): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const bits of [
		0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32,
		0 as uint32, 0x3f800000 as uint32, 0 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
	]) { pushBits(bytes, bits); }
	for (const value of [0, 0, 1, 0, 2, 0, 0, 0]) { bytes.push(value as uint8); }
	for (const joint of [0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0]) { bytes.push(joint as uint8); }
	for (const bits of [
		0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32,
		0x3e800000 as uint32, 0x3f400000 as uint32, 0 as uint32, 0 as uint32,
	]) { pushBits(bytes, bits); }
	for (let joint = 0; joint < 2; joint++) {
		for (let cell = 0; cell < 16; cell++) {
			pushBits(bytes, cell % 5 == 0 ? 0x3f800000 as uint32 : 0 as uint32);
		}
	}
	return move bytes;
}

const SKIN_DOCUMENT: string = `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
	+ `"buffers":[{"byteLength":268}],"bufferViews":[`
	+ `{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},`
	+ `{"buffer":0,"byteOffset":72,"byteLength":6},{"buffer":0,"byteOffset":80,"byteLength":12},`
	+ `{"buffer":0,"byteOffset":92,"byteLength":48},{"buffer":0,"byteOffset":140,"byteLength":128}],`
	+ `"accessors":[`
	+ `{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},`
	+ `{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},`
	+ `{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"},`
	+ `{"bufferView":3,"componentType":5121,"count":3,"type":"VEC4"},`
	+ `{"bufferView":4,"componentType":5126,"count":3,"type":"VEC4"},`
	+ `{"bufferView":5,"componentType":5126,"count":2,"type":"MAT4"}],`
	+ `"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"JOINTS_0":3,"WEIGHTS_0":4},`
	+ `"indices":2}]}],`
	+ `"nodes":[{"translation":[3,0,0],"children":[1,2]},`
	+ `{"mesh":0,"translation":[100,0,0],"skin":0},`
	+ `{"translation":[1,0,0],"children":[3]},{"translation":[0,2,0]}],`
	+ `"skins":[{"joints":[2,3],"skeleton":2,"inverseBindMatrices":5}]}`;

function skinnedRefusalOf(material: GltfMaterial): GltfSceneError {
	const loaded = loadGltf(SKIN_DOCUMENT, skinPayload());
	if (!loaded.ok) { unreachable; }
	let data: GltfData = loaded.value;
	if (data.skinMeshes.length != 1 || data.skinMeshes[0] === null) { unreachable; }
	data.materials.push(material);
	data.meshMaterials[0] = 0;
	data.textures.push({
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Linear, wrap: Wrap.Clamp,
	});
	data.meshes[0].hasUvs = true;
	let context: DrawContext = DrawContext.withUniformCapacity(256);
	const refused: Result<GltfAssets, GltfSceneError> = addGltfAssets(context, data, setupOf());
	if (refused.ok) { unreachable; }
	if (context.liveMaterials() != 0 || context.liveTextures() != 0) { unreachable; }
	return refused.error;
}

test "a skinned pbr material has declared skinned programs, shadowed or not, cut or not" {
	for (const alpha of [GltfAlphaMode.Opaque, GltfAlphaMode.Mask]) {
		for (const texture of [-1, 0]) {
			const key: ProgramKey = gltfProgramOf(pbrMaterial(0.5, 0.5, texture, alpha)).withSkin();
			assert key.pbr && key.skinned && declares(key) && declares({ ...key, shadowed: false });
		}
	}
	let mapped: GltfMaterial = mappedMaterial({ metalRough: 1, occlusion: 0, occlusionStrength: 1.0 });
	mapped.normalTexture = 0;
	const key: ProgramKey = gltfProgramOf(mapped).withSkin();
	assert key.pbrMaps && key.normalMap && declares(key) && declares({ ...key, shadowed: false });
}

test "a skinned pbr material that also emits is refused by name, before anything is made" {
	assert !declares(gltfProgramOf(emittingMaterial()).withSkin());
	assert skinnedRefusalOf(emittingMaterial()) == GltfSceneError.PbrFeatureRefused;
	let moved: GltfMaterial = pbrMaterial(0.5, 0.5, 0);
	moved.uvTransform = { ...IDENTITY_TEXTURE_TRANSFORM, offsetU: 0.5 };
	const skinned: ProgramKey = gltfProgramOf(moved).withSkin();
	assert declares(skinned) && declares({ ...skinned, shadowed: false });
	assert skinnedRefusalOf(pbrMaterial(0.5, 0.0, 0)) == GltfSceneError.PbrValueRefused;
}

test "a pbr value the BRDF has no response for is refused by name, before anything is made" {
	assert refusalOf(pbrMaterial(0.5, 0.0)) == GltfSceneError.PbrValueRefused;
	assert refusalOf(pbrMaterial(1.5, 0.5)) == GltfSceneError.PbrValueRefused;
	assert refusalOf(pbrMaterial(0.5, 1.5)) == GltfSceneError.PbrValueRefused;
}

test "a pbr key is not a legacy material: without GltfMaterial.pbr nothing changes" {
	let legacy: GltfMaterial = pbrMaterial(0.5, 0.5);
	legacy.pbr = null;
	assert !gltfProgramOf(legacy).pbr;
	assert (gltfBlockOf(setupOf(), legacy, gltfProgramOf(legacy)).length as int32)
		== MATERIAL_UNIFORM_LENGTH;
}

function mappedMaterial(maps: GltfPbrMaps): GltfMaterial {
	return { ...pbrMaterial(0.5, 0.5, 0), pbrMaps: maps };
}

test "a pbr material with maps draws with a declared pbr-maps key and carries the strength" {
	const material = mappedMaterial({ metalRough: 1, occlusion: 0, occlusionStrength: 0.4 });
	const key: ProgramKey = gltfProgramOf(material);
	assert key.pbr && key.pbrMaps && key.program == Program.LitTextured;
	assert declares(key) && declares({ ...key, shadowed: false });
	assert declares(key.withCutout()) && declares({ ...key.withCutout(), shadowed: false });
	const block: Vec<float32> = gltfBlockOf(setupOf(), material, key);
	assert (block.length as int32) == PBR_MATERIAL_UNIFORM_LENGTH;
	assert block[PBR_OCCLUSION_STRENGTH] == 0.4 && block[PBR_METALNESS] == 0.5;
	assert !gltfProgramOf(pbrMaterial(0.5, 0.5, 0)).pbrMaps;
}

test "texture roles follow the material's indices, one texture may fill both maps" {
	const a: TextureId = { store: 1, index: 4, generation: 1 };
	const b: TextureId = { store: 1, index: 9, generation: 2 };
	const split = gltfTextureRoles(
		mappedMaterial({ metalRough: 1, occlusion: 0, occlusionStrength: 1.0 }), [a, b]);
	assert split.texture == a && split.metalRough == b && split.occlusion == a;
	const same = gltfTextureRoles(
		mappedMaterial({ metalRough: 1, occlusion: 1, occlusionStrength: 1.0 }), [a, b]);
	assert same.metalRough == b && same.occlusion == b;
	const plain = gltfTextureRoles(pbrMaterial(0.5, 0.5, 0), [a, b]);
	assert plain.metalRough.index == 0 && plain.occlusion.index == 0 && plain.texture == a;
}
