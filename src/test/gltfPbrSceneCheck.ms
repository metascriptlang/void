// Imported pbr materials in the scene: the key and block gltfScene.ms makes of GltfMaterial.pbr,
// and the combinations the build has no pbr program or block layout for, refused by name before
// anything is made.

import { FilterMode, Wrap, RenderState } from "../gpu/state";
import { vec3 } from "../math/math3d";
import {
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
	declares,
	withPbr,
	withShadowed,
	withCutout,
} from "../void3d/gpu3d";

function setupOf(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [3.0, -1.0, 0.0, 0.0] };
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

test "a pbr material that also emits or moves its UV has no block layout and is refused by name" {
	let emitting: GltfMaterial = pbrMaterial(0.5, 0.5, 0);
	emitting.emissiveTexture = 0;
	assert !declares(gltfProgramOf(emitting));
	assert refusalOf(emitting) == GltfSceneError.PbrFeatureRefused;
	const shifted: GltfTextureTransform = { ...IDENTITY_TEXTURE_TRANSFORM, offsetU: 0.5 };
	let moved: GltfMaterial = pbrMaterial(0.5, 0.5, 0);
	moved.uvTransform = shifted;
	assert refusalOf(moved) == GltfSceneError.PbrFeatureRefused;
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
