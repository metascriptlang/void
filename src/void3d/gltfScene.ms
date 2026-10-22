import { RenderState, Face } from "../gpu/state";
import { PassState, passState } from "../gpu/door";
import {
	GltfData, GltfMaterial, GltfAlphaMode, validateGltfGraph, DEFAULT_MATERIAL, NO_TEXTURE_INDEX,
	GltfTextureTransform, IDENTITY_TEXTURE_TRANSFORM,
} from "./gltf";
import { GltfWeightTrack, sampleWeights } from "./gltfCurve";
import {
	DrawContext,
	MeshId,
	DrawRange,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	addMaterial,
	addMeshData,
	addDynamicMeshData,
	addTexture,
	releaseMaterial,
	releaseMesh,
	releaseTexture,
	releaseUniforms,
	reserveUniforms,
	writeUniforms,
} from "./draw";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	MATERIAL_DOUBLE_SIDED,
	MATERIAL_ALPHA_KILL,
	ProgramKey,
	EMISSIVE_COLOR,
	EMISSIVE_STRENGTH,
	EMISSIVE_LENGTH,
	MOVING_LENGTH,
	MOVING_UV_MATRIX,
	MOVING_UV_OFFSET,
	MOVING_BACK_UV_MATRIX,
	PBR_VALUES,
	PBR_OCCLUSION_STRENGTH,
	PBR_MATERIAL_UNIFORM_LENGTH,
	declares,
	emissiveBase,
	movingBase,
	withEmissive,
	withNormalMap,
	withPbr,
	withPbrMaps,
	withUvTransform,
	withSkin,
} from "./gpu3d";
import { Material, MaterialKind, UniformBlock, passFor, pbrBlock } from "./material";
import { PbrProperties } from "./pbrResponse";
import { vec3, identityQuat, linearToSrgb } from "../math/math3d";
import { SkinPose, bind as bindSkinPose } from "./skinPose";
import { SkinGeometry, bind as bindSkinGeometry } from "./skinGeometry";
import { SkinPalette } from "./skinPalette";
import { MeshData } from "./meshData";
import { sinf, cosf } from "../math/mat4";
import { TextureId, TextureUploadError, NO_TEXTURE } from "./texture";
import { UniformError } from "./uniformPool";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	addMeshNode,
	addSkinMeshNode,
	addMorphMeshNode,
	MorphNodeError,
	bindSceneMorph,
	setMorphWeights,
	SceneMorph,
	isLive,
	remove,
	setName,
	NO_NODE_ID,
} from "./scene";

export enum GltfSceneError {
	InvalidData,
	BadMeshBinding,
	ForeignMeshBinding,
	SceneRefused,
	BadSetup,
	TextureRefused,
	UniformsFull,
	MaterialRefused,
	MeshRefused,
	UndeclaredProgram,
	MorphWithSkin,
	MorphRefused,
	PbrFeatureRefused,
	PbrValueRefused,
}

export struct GltfMeshBinding {
	skinMesh: MeshId | null;
	skinMaterial: MaterialId | null;
	mesh: MeshId;
	material: MaterialId;
}

// `morphs[i]` is glTF node i's shared morph state when its mesh has morph targets, else null.
export struct GltfNodeBinding {
	nodes: Vec<NodeId3D>;
	count: int32;
	morphs: Vec<SceneMorph | null>;
}

// `block` is the lit block every material starts from, a preset's floats included (RAMP_LEVELS);
// `pass` gives culling, depth test and colour mask, the material's kind its blend and depth write.
export struct GltfMaterialSetup {
	pass: RenderState;
	block: Vec<float32>;
}

// Every id is held once, until closeGltfAssets.
export interface GltfAssets {
	readonly context: DrawContext;
	bindings: Vec<GltfMeshBinding>;
	meshes: Vec<MeshId>;
	materials: Vec<MaterialId>;
	textures: Vec<TextureId>;
	closed: boolean;
}

function usesDefaultMaterial(data: GltfData): boolean {
	for (const material of data.meshMaterials) {
		if (material == DEFAULT_MATERIAL) { return true; }
	}
	return false;
}

function isTexturedAt(data: GltfData, mesh: int32): boolean {
	const material: int32 = data.meshMaterials[mesh];
	return material != DEFAULT_MATERIAL && data.materials[material].texture != NO_TEXTURE_INDEX;
}

function isNormalMappedAt(data: GltfData, mesh: int32): boolean {
	const material: int32 = data.meshMaterials[mesh];
	return material != DEFAULT_MATERIAL
		&& data.materials[material].normalTexture != NO_TEXTURE_INDEX;
}

function hasTextureOrNone(texture: int32, textureCount: int32): boolean {
	return texture >= NO_TEXTURE_INDEX && texture < textureCount;
}

function isConsistent(data: GltfData): boolean {
	const meshCount: int32 = data.meshes.length as int32;
	const materialCount: int32 = data.materials.length as int32;
	const textureCount: int32 = data.textures.length as int32;
	if ((data.meshMaterials.length as int32) != meshCount) { return false; }
	for (const material of data.materials) {
		if (!hasTextureOrNone(material.texture, textureCount)
			|| !hasTextureOrNone(material.emissiveTexture, textureCount)) {
			return false;
		}
		if (!hasTextureOrNone(material.normalTexture, textureCount)) { return false; }
		const maps: boolean = material.emissiveTexture != NO_TEXTURE_INDEX
			|| material.normalTexture != NO_TEXTURE_INDEX;
		if (maps && material.texture == NO_TEXTURE_INDEX) { return false; }
		const packed = material.pbrMaps;
		if (packed !== null) {
			if (material.pbr === null || material.texture == NO_TEXTURE_INDEX) { return false; }
			if (packed.metalRough == NO_TEXTURE_INDEX || packed.occlusion == NO_TEXTURE_INDEX
				|| !hasTextureOrNone(packed.metalRough, textureCount)
				|| !hasTextureOrNone(packed.occlusion, textureCount)) {
				return false;
			}
		}
	}
	for (let i = 0; i < meshCount; i++) {
		const material: int32 = data.meshMaterials[i];
		if (material < DEFAULT_MATERIAL || material >= materialCount) { return false; }
		if (isTexturedAt(data, i) != data.meshes[i].hasUvs) { return false; }
		if (isNormalMappedAt(data, i) != data.meshes[i].hasTangents) { return false; }
	}
	return true;
}

const DEFAULT_SOURCE: GltfMaterial = {
	texture: NO_TEXTURE_INDEX, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0,
	emissiveTexture: NO_TEXTURE_INDEX, emissive: vec3(0.0, 0.0, 0.0), emissiveStrength: 1.0,
	normalTexture: NO_TEXTURE_INDEX, uvTransform: IDENTITY_TEXTURE_TRANSFORM,
};

function kindOf(mode: GltfAlphaMode): MaterialKind {
	return match (mode) {
		GltfAlphaMode.Opaque => MaterialKind.Opaque,
		GltfAlphaMode.Mask => MaterialKind.AlphaKill,
		GltfAlphaMode.Blend => MaterialKind.Alpha,
	};
}

// The key a material draws with: a textured one when it names a base texture, and M37's emissive
// and normal-map keys when it emits or has a normal map. A kind or feature pair the build
// declares no program for is refused by addGltfAssets before anything is made
// (UndeclaredProgram).
export function gltfProgramOf(source: GltfMaterial): ProgramKey {
	const lit: Program =
		source.texture != NO_TEXTURE_INDEX ? Program.LitTextured : Program.Lit;
	const plain: ProgramKey = Material.ofKind(lit, kindOf(source.alphaMode)).program;
	const pbrKey: ProgramKey = source.pbr !== null ? plain.withPbr() : plain;
	const key: ProgramKey = source.pbr !== null && source.pbrMaps !== null && lit == Program.LitTextured
		? pbrKey.withPbrMaps() : pbrKey;
	const emitting: ProgramKey =
		source.emissiveTexture != NO_TEXTURE_INDEX ? key.withEmissive() : key;
	const mapped: ProgramKey =
		source.normalTexture != NO_TEXTURE_INDEX ? emitting.withNormalMap() : emitting;
	return source.uvTransform != IDENTITY_TEXTURE_TRANSFORM ? mapped.withUvTransform() : mapped;
}

// KHR_texture_transform as the UV transform key's matrix and offset: translation, rotation, scale,
// with the rotation negated as Bevy's texture_transform_to_affine2 (bevy_gltf
// loader/gltf_ext/texture.rs:59-65) and three.js' Texture.rotation apply it.
function writeUvTransform(
	ref values: Vec<float32>,
	at: int32,
	transform: GltfTextureTransform,
): void {
	const c: float32 = cosf(transform.rotation);
	const s: float32 = sinf(transform.rotation);
	values[at + MOVING_UV_MATRIX] = transform.scaleU * c;
	values[at + MOVING_UV_MATRIX + 1] = -transform.scaleU * s;
	values[at + MOVING_UV_MATRIX + 2] = transform.scaleV * s;
	values[at + MOVING_UV_MATRIX + 3] = transform.scaleV * c;
	values[at + MOVING_UV_OFFSET] = transform.offsetU;
	values[at + MOVING_UV_OFFSET + 1] = transform.offsetV;
	values[at + MOVING_BACK_UV_MATRIX] = 1.0;
	values[at + MOVING_BACK_UV_MATRIX + 3] = 1.0;
}

function pbrValuesOf(
	source: GltfMaterial,
	program: ProgramKey,
): Result<Vec<float32>, GltfSceneError> {
	const pbr = source.pbr;
	if (pbr === null) { return Result.err(GltfSceneError.PbrValueRefused); }
	const properties = PbrProperties.gltfMap(pbr.metallic, pbr.roughness);
	if (!properties.ok) { return Result.err(GltfSceneError.PbrValueRefused); }
	const block = pbrBlock(program, properties.value);
	if (!block.ok) { return Result.err(GltfSceneError.PbrValueRefused); }
	return Result.ok(block.value);
}

function declaresPbr(key: ProgramKey): boolean {
	return declares(key) && declares({ ...key, shadowed: false });
}

// The material's block: the setup's floats with the double-sided flag and alpha kill written
// over them, and an emissive key's colour and strength after them at emissiveBase.
export function gltfBlockOf(
	setup: GltfMaterialSetup,
	source: GltfMaterial,
	program: ProgramKey,
): Vec<float32> {
	let values: Vec<float32> = [];
	for (const value of setup.block) { values.push(value); }
	values[MATERIAL_DOUBLE_SIDED] = source.doubleSided ? 1.0 : 0.0;
	values[MATERIAL_ALPHA_KILL] = source.alphaKill;
	if (program.pbr) {
		if (program.uvTransform || program.emissive) { unreachable; }
		const held = pbrValuesOf(source, program);
		if (!held.ok) { unreachable; }
		if (held.ok) {
			for (let i = PBR_VALUES; i < PBR_MATERIAL_UNIFORM_LENGTH; i++) {
				values.push(held.value[i]);
			}
			const maps = source.pbrMaps;
			if (program.pbrMaps && maps !== null) {
				values[PBR_OCCLUSION_STRENGTH] = maps.occlusionStrength;
			}
		}
		return values;
	}
	if (program.uvTransform) {
		if ((values.length as int32) != movingBase(program)) { unreachable; }
		for (let i = 0; i < MOVING_LENGTH; i++) { values.push(0.0); }
		writeUvTransform(values, movingBase(program), source.uvTransform);
	}
	if (program.emissive) {
		if ((values.length as int32) != emissiveBase(program)) { unreachable; }
		for (let i = 0; i < EMISSIVE_LENGTH; i++) { values.push(0.0); }
		const at: int32 = emissiveBase(program) + EMISSIVE_COLOR;
		values[at] = linearToSrgb(source.emissive.x);
		values[at + 1] = linearToSrgb(source.emissive.y);
		values[at + 2] = linearToSrgb(source.emissive.z);
		values[emissiveBase(program) + EMISSIVE_STRENGTH] = source.emissiveStrength;
	}
	return values;
}

export struct GltfTextureRoles {
	texture: TextureId;
	emissive: TextureId;
	normal: TextureId;
	metalRough: TextureId;
	occlusion: TextureId;
}

const NO_ROLES: GltfTextureRoles = {
	texture: NO_TEXTURE, emissive: NO_TEXTURE, normal: NO_TEXTURE,
	metalRough: NO_TEXTURE, occlusion: NO_TEXTURE,
};

function textureAt(textures: Readonly<Span<TextureId>>, index: int32): TextureId {
	return index == NO_TEXTURE_INDEX ? NO_TEXTURE : textures[index];
}

export function gltfTextureRoles(
	source: GltfMaterial,
	textures: Readonly<Span<TextureId>>,
): GltfTextureRoles {
	const maps = source.pbrMaps;
	return {
		texture: textureAt(textures, source.texture),
		emissive: textureAt(textures, source.emissiveTexture),
		normal: textureAt(textures, source.normalTexture),
		metalRough: maps === null ? NO_TEXTURE : textureAt(textures, maps.metalRough),
		occlusion: maps === null ? NO_TEXTURE : textureAt(textures, maps.occlusion),
	};
}

function madeMaterial(
	context: DrawContext,
	setup: GltfMaterialSetup,
	source: GltfMaterial,
	roles: GltfTextureRoles,
	skinned: boolean = false,
): Result<MaterialId, GltfSceneError> {
	let program: ProgramKey = gltfProgramOf(source);
	if (skinned) { program = program.withSkin(); }
	const doubleSided: boolean = source.doubleSided;
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, blockLength(program));
	if (!reserved.ok) { return Result.err(GltfSceneError.UniformsFull); }
	const values: Vec<float32> = gltfBlockOf(setup, source, program);
	const written: Result<int32, UniformError> = writeUniforms(context, reserved.value, values);
	if (!written.ok) { unreachable; }
	const sided: RenderState = doubleSided ? { ...setup.pass, culling: Face.None } : setup.pass;
	const kind: MaterialKind = kindOf(source.alphaMode);
	const pass: RenderState = passFor(kind, sided);
	const material: Material = {
		...Material.ofKind(program.program, kind),
		program: program,
		pass: pass,
		texture: roles.texture,
		emissiveTexture: roles.emissive,
		normalTexture: roles.normal,
		metalRoughTexture: roles.metalRough,
		occlusionTexture: roles.occlusion,
		uniforms: reserved.value,
	};
	const added: Result<MaterialId, MaterialError> = addMaterial(context, material);
	if (!added.ok) {
		const released: Result<int32, UniformError> = releaseUniforms(context, reserved.value);
		if (!released.ok) { unreachable; }
		return Result.err(GltfSceneError.MaterialRefused);
	}
	return Result.ok(added.value);
}

function blockLength(program: ProgramKey): int32 {
	const pbr: int32 = program.pbr ? PBR_MATERIAL_UNIFORM_LENGTH - MATERIAL_UNIFORM_LENGTH : 0;
	return MATERIAL_UNIFORM_LENGTH + pbr + (program.emissive ? EMISSIVE_LENGTH : 0);
}

function undone(
	context: DrawContext,
	assets: GltfAssets,
	error: GltfSceneError,
): Result<GltfAssets, GltfSceneError> {
	const released: Result<void, HandleError> = releaseHolds(assets);
	if (!released.ok) { unreachable; }
	return Result.err(error);
}

export function addGltfAssets(
	context: DrawContext,
	data: GltfData,
	setup: GltfMaterialSetup,
): Result<GltfAssets, GltfSceneError> {
	context.requireOpen("addGltfAssets");
	if ((setup.block.length as int32) != MATERIAL_UNIFORM_LENGTH
		|| setup.block[MATERIAL_DOUBLE_SIDED] != 0.0
		|| setup.block[MATERIAL_ALPHA_KILL] != 0.0) {
		return Result.err(GltfSceneError.BadSetup);
	}
	if (!isConsistent(data)) { return Result.err(GltfSceneError.InvalidData); }
	let usage: Vec<int32> = [];
	for (let mesh = 0; mesh < data.meshes.length; mesh++) { usage.push(0); }
	let hasSkin: boolean = false;
	for (const node of data.nodes) {
		if (node.skin === null) {
			if (node.mesh >= 0 && node.mesh < usage.length) { usage[node.mesh] |= 1; }
			continue;
		}
		hasSkin = true;
		for (const mesh of node.skinMeshes) {
			if (mesh < 0 || mesh >= usage.length || mesh >= data.skinMeshes.length) {
				return Result.err(GltfSceneError.InvalidData);
			}
			if (data.skinMeshes[mesh] === null) { return Result.err(GltfSceneError.InvalidData); }
			usage[mesh] |= 2;
		}
	}
	if (hasSkin && !validateGltfGraph(data).ok) { return Result.err(GltfSceneError.InvalidData); }
	for (let mesh = 0; mesh < usage.length; mesh++) {
		if ((usage[mesh] & 2) == 0) { continue; }
		const material: int32 = data.meshMaterials[mesh];
		const source: GltfMaterial = material == DEFAULT_MATERIAL
			? DEFAULT_SOURCE : data.materials[material];
		if (source.pbr !== null) { return Result.err(GltfSceneError.PbrFeatureRefused); }
		if (!declares(gltfProgramOf(source).withSkin())) {
			return Result.err(GltfSceneError.UndeclaredProgram);
		}
	}
	for (const material of data.materials) {
		const key: ProgramKey = gltfProgramOf(material);
		if (key.pbr) {
			if (!declaresPbr(key)) { return Result.err(GltfSceneError.PbrFeatureRefused); }
			if (!pbrValuesOf(material, key).ok) {
				return Result.err(GltfSceneError.PbrValueRefused);
			}
			continue;
		}
		if (!declares(key)) { return Result.err(GltfSceneError.UndeclaredProgram); }
	}
	let assets: GltfAssets = {
		context: context,
		bindings: [],
		meshes: [],
		materials: [],
		textures: [],
		closed: false,
	};
	for (const texture of data.textures) {
		const added: Result<TextureId, TextureUploadError> = addTexture(context, texture);
		if (!added.ok) { return undone(context, assets, GltfSceneError.TextureRefused); }
		assets.textures.push(added.value);
	}
	for (const material of data.materials) {
		const made: Result<MaterialId, GltfSceneError> =
			madeMaterial(context, setup, material, gltfTextureRoles(material, assets.textures));
		if (!made.ok) { return undone(context, assets, made.error); }
		assets.materials.push(made.value);
	}
	const defaultIndex: int32 = assets.materials.length as int32;
	if (usesDefaultMaterial(data)) {
		const made: Result<MaterialId, GltfSceneError> =
			madeMaterial(context, setup, DEFAULT_SOURCE, NO_ROLES);
		if (!made.ok) { return undone(context, assets, made.error); }
		assets.materials.push(made.value);
	}
	let skinMaterials: Vec<MaterialId | null> = [];
	for (let material = 0; material < assets.materials.length; material++) {
		skinMaterials.push(null);
	}
	for (let i = 0; i < (data.meshes.length as int32); i++) {
		const material: int32 = data.meshMaterials[i];
		const index: int32 = material == DEFAULT_MATERIAL ? defaultIndex : material;
		let skinMaterial: MaterialId | null = null;
		let skinMesh: MeshId | null = null;
		if ((usage[i] & 2) != 0) {
			const cached = skinMaterials[index];
			if (cached !== null) {
				skinMaterial = cached;
			} else {
				const source: GltfMaterial = material == DEFAULT_MATERIAL
					? DEFAULT_SOURCE : data.materials[material];
				const base = context.materials[assets.materials[index].index];
				const roles: GltfTextureRoles = {
					texture: base.texture, emissive: base.emissiveTexture, normal: base.normalTexture,
					metalRough: base.metalRoughTexture, occlusion: base.occlusionTexture,
				};
				const made = madeMaterial(context, setup, source, roles, true);
				if (!made.ok) { return undone(context, assets, made.error); }
				skinMaterials[index] = made.value;
				assets.materials.push(made.value);
				skinMaterial = made.value;
			}
		}
		let primary: MeshData = data.meshes[i];
		let primaryMaterial: MaterialId = assets.materials[index];
		if (usage[i] == 2) {
			const source = data.skinMeshes[i];
			if (source === null || skinMaterial === null) {
				return undone(context, assets, GltfSceneError.InvalidData);
			}
			primary = source.mesh;
			primaryMaterial = skinMaterial;
		}
		const added: Result<MeshId, MeshUploadError> = addMeshData(context, primary);
		if (!added.ok) { return undone(context, assets, GltfSceneError.MeshRefused); }
		assets.meshes.push(added.value);
		if (usage[i] == 2) {
			skinMesh = added.value;
		} else if ((usage[i] & 2) != 0) {
			const source = data.skinMeshes[i];
			if (source === null) { return undone(context, assets, GltfSceneError.InvalidData); }
			const uploaded = addMeshData(context, source.mesh);
			if (!uploaded.ok) { return undone(context, assets, GltfSceneError.MeshRefused); }
			assets.meshes.push(uploaded.value);
			skinMesh = uploaded.value;
		}
		assets.bindings.push({
			mesh: added.value, material: primaryMaterial,
			skinMesh: skinMesh, skinMaterial: skinMaterial,
		});
	}
	return Result.ok(assets);
}

function releaseHolds(assets: GltfAssets): Result<void, HandleError> {
	const context: DrawContext = assets.context;
	for (const mesh of assets.meshes) {
		const _meshLeft: int32 = try releaseMesh(context, mesh);
	}
	for (const material of assets.materials) {
		const _materialLeft: int32 = try releaseMaterial(context, material);
	}
	for (const texture of assets.textures) {
		const _textureLeft: int32 = try releaseTexture(context, texture);
	}
	return Result.ok(null);
}

export function closeGltfAssets(assets: GltfAssets): void {
	if (assets.closed) { stopOnClosed("closeGltfAssets"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeGltfAssets with a pass open; endPass ends it");
		unreachable;
	}
	const released: Result<void, HandleError> = releaseHolds(assets);
	if (!released.ok) {
		console.log(`void3d: closeGltfAssets found a hold ${released.error.toString()}`);
		unreachable;
	}
	while ((assets.bindings.length as int32) > 0) { assets.bindings.pop(); }
	while ((assets.meshes.length as int32) > 0) { assets.meshes.pop(); }
	while ((assets.materials.length as int32) > 0) { assets.materials.pop(); }
	while ((assets.textures.length as int32) > 0) { assets.textures.pop(); }
	assets.closed = true;
}

export function isClosed(this assets: GltfAssets): boolean {
	return assets.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on glTF assets that were closed`);
	unreachable;
}

function transformOf(data: GltfData, index: int32): Transform3D {
	return {
		position: data.nodes[index].local.position,
		rotation: data.nodes[index].local.rotation,
		scale: data.nodes[index].local.scale,
	};
}

export function addGltfNodes(
	scene: Scene3D,
	parent: NodeId3D,
	data: GltfData,
	bindings: Readonly<Span<GltfMeshBinding>>,
): Result<int32, GltfSceneError> {
	const added = try addGltfBoundNodes(scene, parent, data, bindings);
	return Result.ok(added.count);
}

function failedGltfNodes(
	scene: Scene3D,
	data: GltfData,
	mapped: GltfNodeBinding,
	error: GltfSceneError,
): Result<GltfNodeBinding, GltfSceneError> {
	for (const root of data.sceneRoots) {
		if (root >= 0 && root < mapped.nodes.length && isLive(scene, mapped.nodes[root])) {
			remove(scene, mapped.nodes[root]);
		}
	}
	return Result.err(error);
}

function attachGltfSkins(
	scene: Scene3D,
	data: GltfData,
	bindings: Readonly<Span<GltfMeshBinding>>,
	mapped: GltfNodeBinding,
): Result<int32, GltfSceneError> {
	let addedCount: int32 = 0;
	for (let node = 0; node < data.nodes.length; node++) {
		const skinIndex = data.nodes[node].skin;
		if (skinIndex === null || !isLive(scene, mapped.nodes[node])) { continue; }
		const sourceSkin = data.skins[skinIndex];
		let palettes: Vec<SkinPalette> = [];
		for (const mesh of data.nodes[node].skinMeshes) {
			const source = data.skinMeshes[mesh];
			if (source === null) { return Result.err(GltfSceneError.InvalidData); }
			for (const part of source.partition.parts) { palettes.push(part.palette); }
		}
		const pose = SkinPose.bindSkinPose(scene, sourceSkin.joints, mapped.nodes,
			sourceSkin.inverseBindMatrices, palettes);
		if (!pose.ok) { return Result.err(GltfSceneError.SceneRefused); }
		let palette: int32 = 0;
		for (const mesh of data.nodes[node].skinMeshes) {
			const source = data.skinMeshes[mesh];
			const skinMesh = bindings[mesh].skinMesh;
			const skinMaterial = bindings[mesh].skinMaterial;
			if (source === null || skinMesh === null || skinMaterial === null) {
				return Result.err(GltfSceneError.BadMeshBinding);
			}
			const geometry = SkinGeometry.bindSkinGeometry(
				source.mesh, source.influences, pose.value,
			);
			if (!geometry.ok) { return Result.err(GltfSceneError.SceneRefused); }
			let base: int32 = 0;
			for (const part of source.partition.parts) {
				const count: int32 = part.triangles.length as int32 * 3;
				const range: DrawRange = { base: base, count: count };
				const local: Transform3D = {
					position: vec3(0, 0, 0), rotation: identityQuat(), scale: vec3(1, 1, 1),
				};
				const added = addSkinMeshNode(scene, mapped.nodes[node], local,
					skinMesh, skinMaterial, geometry.value, palette, range);
				if (!added.ok) { return Result.err(GltfSceneError.SceneRefused); }
				addedCount++;
				palette++;
				base += count;
			}
		}
	}
	return Result.ok(addedCount);
}

export function addGltfBoundNodes(
	scene: Scene3D,
	parent: NodeId3D,
	data: GltfData,
	bindings: Readonly<Span<GltfMeshBinding>>,
): Result<GltfNodeBinding, GltfSceneError> {
	const _under: int32 = scene.liveRow(parent, "addGltfNodes");
	const context: DrawContext = scene.context;
	context.requireOpen("addGltfNodes");
	if ((bindings.length as int32) != (data.meshes.length as int32)) {
		return Result.err(GltfSceneError.BadMeshBinding);
	}
	for (const binding of bindings) {
		const skinMesh = binding.skinMesh;
		const skinMaterial = binding.skinMaterial;
		if ((skinMesh === null) != (skinMaterial === null)) {
			return Result.err(GltfSceneError.BadMeshBinding);
		}
		if (skinMesh !== null && skinMaterial !== null
			&& (!context.hasMesh(skinMesh) || !context.hasMaterial(skinMaterial))) {
			return Result.err(GltfSceneError.BadMeshBinding);
		}
		if (!context.hasMesh(binding.mesh) || !context.hasMaterial(binding.material)) {
			const issued: boolean =
				context.issuedMesh(binding.mesh) && context.issuedMaterial(binding.material);
			return Result.err(
				issued ? GltfSceneError.BadMeshBinding : GltfSceneError.ForeignMeshBinding,
			);
		}
	}
	const valid = validateGltfGraph(data);
	if (!valid.ok) { return Result.err(GltfSceneError.InvalidData); }
	let owners: Vec<int32> = [];
	let primitives: Vec<int32> = [];
	let morphs: Vec<SceneMorph | null> = [];
	for (let index = 0; index < data.nodes.length; index++) {
		owners.push(-1);
		primitives.push(0);
		morphs.push(null);
	}
	for (let index = 0; index < data.nodes.length; index++) {
		const morph = data.nodes[index].morph;
		if (morph === null) { continue; }
		if (data.nodes[index].skin !== null) { return Result.err(GltfSceneError.MorphWithSkin); }
		const first: int32 = data.morphs[morph].firstPrimitive;
		const count: int32 = data.morphs[morph].data.primitives.length as int32;
		if (first < 0 || count < 1 || first > (data.meshes.length as int32) - count) {
			return Result.err(GltfSceneError.InvalidData);
		}
		const bound = bindSceneMorph(data.morphs[morph].data, data.nodes[index].weights);
		if (!bound.ok) { return Result.err(GltfSceneError.MorphRefused); }
		morphs[index] = bound.value;
		const own: int32 = data.nodes[index].mesh;
		if (own >= 0) {
			if (own < first || own >= first + count) { return Result.err(GltfSceneError.InvalidData); }
			owners[index] = index;
			primitives[index] = own - first;
			continue;
		}
		for (const child of data.nodes[index].children) {
			const mesh: int32 = data.nodes[child].mesh;
			if (data.nodes[child].morph === null && mesh >= first && mesh < first + count) {
				owners[child] = index;
				primitives[child] = mesh - first;
			}
		}
	}
	let nodes: Vec<int32> = [];
	let parents: Vec<NodeId3D> = [];
	for (let i = (data.sceneRoots.length as int32) - 1; i >= 0; i--) {
		nodes.push(data.sceneRoots[i]);
		parents.push(parent);
	}
	let mapped: GltfNodeBinding = { nodes: [], count: 0, morphs: [] };
	for (let index = 0; index < data.nodes.length; index++) { mapped.nodes.push(NO_NODE_ID); }
	while ((nodes.length as int32) > 0) {
		const last: int32 = (nodes.length as int32) - 1;
		const index: int32 = nodes[last];
		const under: NodeId3D = parents[last];
		nodes.pop();
		parents.pop();
		let id: NodeId3D = NO_NODE_ID;
		const mesh: int32 = data.nodes[index].mesh;
		if (mesh < 0) {
			id = addGroup(scene, under, transformOf(data, index));
		} else if (owners[index] >= 0) {
			const owner = morphs[owners[index]];
			const dynamic = addDynamicMeshData(context, data.meshes[mesh]);
			if (owner === null || !dynamic.ok) {
				return failedGltfNodes(scene, data, mapped, GltfSceneError.MeshRefused);
			}
			const added: Result<NodeId3D, MorphNodeError> = addMorphMeshNode(
				scene, under, transformOf(data, index),
				dynamic.value, bindings[mesh].material, owner, primitives[index],
			);
			if (!added.ok) {
				if (!releaseMesh(context, dynamic.value).ok) { unreachable; }
				return failedGltfNodes(scene, data, mapped, GltfSceneError.SceneRefused);
			}
			id = added.value;
		} else {
			const added: Result<NodeId3D, SceneError> = addMeshNode(
				scene, under, transformOf(data, index),
				bindings[mesh].mesh, bindings[mesh].material,
			);
			if (!added.ok) {
				return failedGltfNodes(scene, data, mapped, GltfSceneError.SceneRefused);
			}
			id = added.value;
		}
		setName(scene, id, data.nodes[index].name);
		mapped.nodes[index] = id;
		mapped.count++;
		const childCount: int32 = data.nodes[index].children.length as int32;
		for (let i = childCount - 1; i >= 0; i--) {
			nodes.push(data.nodes[index].children[i]);
			parents.push(id);
		}
	}
	const attached = attachGltfSkins(scene, data, bindings, mapped);
	if (!attached.ok) { return failedGltfNodes(scene, data, mapped, attached.error); }
	mapped.count += attached.value;
	mapped.morphs = move morphs;
	return Result.ok(move mapped);
}

export enum GltfMorphPoseError {
	Target,
	DuplicateTrack,
	Curve,
	Publish,
}

// Weights tracks of one clip over the nodes `addGltfBoundNodes` made, the morph twin of
// gltfPose.ms' GltfPose: a sample publishes each track's node once, however many primitives it has.
export interface GltfMorphPose {
	morphs: Vec<SceneMorph | null>;
	tracks: Vec<GltfWeightTrack>;
}

export function bindMorphPose(
	this typeof GltfMorphPose,
	morphs: Readonly<Span<SceneMorph | null>>,
	tracks: Readonly<Span<GltfWeightTrack>>,
): Result<GltfMorphPose, GltfMorphPoseError> {
	let pose: GltfMorphPose = { morphs: [], tracks: [] };
	for (const morph of morphs) { pose.morphs.push(morph); }
	for (let i = 0; i < tracks.length; i++) {
		const source: int32 = tracks[i].sourceNode;
		if (source < 0 || source >= (morphs.length as int32)) {
			return Result.err(GltfMorphPoseError.Target);
		}
		const morph = morphs[source];
		if (morph === null || morph.geometry.data.targetCount != tracks[i].curve.targetCount) {
			return Result.err(GltfMorphPoseError.Target);
		}
		for (let previous = 0; previous < i; previous++) {
			if (tracks[previous].sourceNode == source) {
				return Result.err(GltfMorphPoseError.DuplicateTrack);
			}
		}
		pose.tracks.push({ sourceNode: source, curve: tracks[i].curve });
	}
	return Result.ok(pose);
}

export function sampleMorphPose(
	this pose: GltfMorphPose, seconds: float64,
): Result<int32, GltfMorphPoseError> {
	for (const track of pose.tracks) {
		const morph = pose.morphs[track.sourceNode];
		if (morph === null) { return Result.err(GltfMorphPoseError.Target); }
		const weights = track.curve.sampleWeights(seconds);
		if (!weights.ok) { return Result.err(GltfMorphPoseError.Curve); }
		if (!setMorphWeights(morph, weights.value).ok) {
			return Result.err(GltfMorphPoseError.Publish);
		}
	}
	return Result.ok(pose.tracks.length as int32);
}
