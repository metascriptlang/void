import { RenderState, Face } from "../gpu/state";
import { PassState, passState } from "../gpu/door";
import {
	GltfData, GltfMaterial, GltfAlphaMode, validateGltfGraph, DEFAULT_MATERIAL, NO_TEXTURE_INDEX,
	GltfTextureTransform, IDENTITY_TEXTURE_TRANSFORM,
} from "./gltf";
import {
	DrawContext,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	addMaterial,
	addMeshData,
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
	declares,
	emissiveBase,
	movingBase,
	withEmissive,
	withNormalMap,
	withUvTransform,
} from "./gpu3d";
import { Material, MaterialKind, UniformBlock, passFor } from "./material";
import { vec3, linearToSrgb } from "../math/math3d";
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
}

export struct GltfMeshBinding {
	mesh: MeshId;
	material: MaterialId;
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
	const key: ProgramKey = Material.ofKind(lit, kindOf(source.alphaMode)).program;
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

function madeMaterial(
	context: DrawContext,
	setup: GltfMaterialSetup,
	source: GltfMaterial,
	texture: TextureId,
	emissive: TextureId,
	normal: TextureId,
): Result<MaterialId, GltfSceneError> {
	const program: ProgramKey = gltfProgramOf(source);
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
		texture: texture,
		emissiveTexture: emissive,
		normalTexture: normal,
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
	return MATERIAL_UNIFORM_LENGTH + (program.emissive ? EMISSIVE_LENGTH : 0);
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
	for (const material of data.materials) {
		const key: ProgramKey = gltfProgramOf(material);
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
		const texture: TextureId = material.texture == NO_TEXTURE_INDEX
			? NO_TEXTURE
			: assets.textures[material.texture];
		const emissive: TextureId = material.emissiveTexture == NO_TEXTURE_INDEX
			? NO_TEXTURE
			: assets.textures[material.emissiveTexture];
		const normal: TextureId = material.normalTexture == NO_TEXTURE_INDEX
			? NO_TEXTURE
			: assets.textures[material.normalTexture];
		const made: Result<MaterialId, GltfSceneError> =
			madeMaterial(context, setup, material, texture, emissive, normal);
		if (!made.ok) { return undone(context, assets, made.error); }
		assets.materials.push(made.value);
	}
	const defaultIndex: int32 = assets.materials.length as int32;
	if (usesDefaultMaterial(data)) {
		const made: Result<MaterialId, GltfSceneError> =
			madeMaterial(context, setup, DEFAULT_SOURCE, NO_TEXTURE, NO_TEXTURE, NO_TEXTURE);
		if (!made.ok) { return undone(context, assets, made.error); }
		assets.materials.push(made.value);
	}
	for (let i = 0; i < (data.meshes.length as int32); i++) {
		const added: Result<MeshId, MeshUploadError> = addMeshData(context, data.meshes[i]);
		if (!added.ok) { return undone(context, assets, GltfSceneError.MeshRefused); }
		assets.meshes.push(added.value);
		const material: int32 = data.meshMaterials[i];
		const index: int32 = material == DEFAULT_MATERIAL ? defaultIndex : material;
		assets.bindings.push({ mesh: added.value, material: assets.materials[index] });
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
	const _under: int32 = scene.liveRow(parent, "addGltfNodes");
	const context: DrawContext = scene.context;
	context.requireOpen("addGltfNodes");
	if ((bindings.length as int32) != (data.meshes.length as int32)) {
		return Result.err(GltfSceneError.BadMeshBinding);
	}
	for (const binding of bindings) {
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
	let nodes: Vec<int32> = [];
	let parents: Vec<NodeId3D> = [];
	for (let i = (data.sceneRoots.length as int32) - 1; i >= 0; i--) {
		nodes.push(data.sceneRoots[i]);
		parents.push(parent);
	}
	let count: int32 = 0;
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
		} else {
			const added: Result<NodeId3D, SceneError> = addMeshNode(
				scene, under, transformOf(data, index),
				bindings[mesh].mesh, bindings[mesh].material,
			);
			if (!added.ok) { return Result.err(GltfSceneError.SceneRefused); }
			id = added.value;
		}
		setName(scene, id, data.nodes[index].name);
		count = count + 1;
		const childCount: int32 = data.nodes[index].children.length as int32;
		for (let i = childCount - 1; i >= 0; i--) {
			nodes.push(data.nodes[index].children[i]);
			parents.push(id);
		}
	}
	return Result.ok(count);
}
