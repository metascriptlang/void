import { RenderState, Face } from "../gpu/state";
import { GltfData, validateGltfGraph, DEFAULT_MATERIAL, NO_TEXTURE_INDEX } from "./gltf";
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
} from "./gpu3d";
import { Material, Phase, UniformBlock } from "./material";
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
	NO_NODE_3D,
} from "./scene";

export enum GltfSceneError {
	InvalidData,
	BadMeshBinding,
	SceneRefused,
	BadSetup,
	TextureRefused,
	UniformsFull,
	MaterialRefused,
	MeshRefused,
}

export struct GltfMeshBinding {
	mesh: MeshId;
	material: MaterialId;
}

// `block` is the lit block every material starts from, a preset's floats included (RAMP_LEVELS).
export struct GltfMaterialSetup {
	pass: RenderState;
	block: Vec<float32>;
}

// Every id is held once, until releaseGltfAssets.
export struct GltfAssets {
	bindings: Vec<GltfMeshBinding>;
	meshes: Vec<MeshId>;
	materials: Vec<MaterialId>;
	textures: Vec<TextureId>;
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

function isConsistent(data: GltfData): boolean {
	const meshCount: int32 = data.meshes.length as int32;
	const materialCount: int32 = data.materials.length as int32;
	const textureCount: int32 = data.textures.length as int32;
	if ((data.meshMaterials.length as int32) != meshCount) { return false; }
	for (const material of data.materials) {
		if (material.texture < NO_TEXTURE_INDEX || material.texture >= textureCount) {
			return false;
		}
	}
	for (let i = 0; i < meshCount; i++) {
		const material: int32 = data.meshMaterials[i];
		if (material < DEFAULT_MATERIAL || material >= materialCount) { return false; }
		if (isTexturedAt(data, i) != data.meshes[i].hasUvs) { return false; }
	}
	return true;
}

function madeMaterial(
	ref context: DrawContext,
	setup: GltfMaterialSetup,
	doubleSided: boolean,
	texture: TextureId,
): Result<MaterialId, GltfSceneError> {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { return Result.err(GltfSceneError.UniformsFull); }
	let values: Vec<float32> = [];
	for (const value of setup.block) { values.push(value); }
	values[MATERIAL_DOUBLE_SIDED] = doubleSided ? 1.0 : 0.0;
	const written: Result<int32, UniformError> = writeUniforms(context, reserved.value, values);
	if (!written.ok) { unreachable; }
	const pass: RenderState = doubleSided ? { ...setup.pass, culling: Face.None } : setup.pass;
	const program: Program = texture.isTexture() ? Program.LitTextured : Program.Lit;
	const material: Material = {
		...Material.plain(program, pass, Phase.Opaque),
		texture: texture,
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

function undone(
	ref context: DrawContext,
	assets: GltfAssets,
	error: GltfSceneError,
): Result<GltfAssets, GltfSceneError> {
	const released: Result<void, HandleError> = releaseGltfAssets(context, assets);
	if (!released.ok) { unreachable; }
	return Result.err(error);
}

export function addGltfAssets(
	ref context: DrawContext,
	data: GltfData,
	setup: GltfMaterialSetup,
): Result<GltfAssets, GltfSceneError> {
	if ((setup.block.length as int32) != MATERIAL_UNIFORM_LENGTH
		|| setup.block[MATERIAL_DOUBLE_SIDED] != 0.0) {
		return Result.err(GltfSceneError.BadSetup);
	}
	if (!isConsistent(data)) { return Result.err(GltfSceneError.InvalidData); }
	let assets: GltfAssets = { bindings: [], meshes: [], materials: [], textures: [] };
	for (const texture of data.textures) {
		const added: Result<TextureId, TextureUploadError> = addTexture(context, texture);
		if (!added.ok) { return undone(context, assets, GltfSceneError.TextureRefused); }
		assets.textures.push(added.value);
	}
	for (const material of data.materials) {
		const texture: TextureId = material.texture == NO_TEXTURE_INDEX
			? NO_TEXTURE
			: assets.textures[material.texture];
		const made: Result<MaterialId, GltfSceneError> =
			madeMaterial(context, setup, material.doubleSided, texture);
		if (!made.ok) { return undone(context, assets, made.error); }
		assets.materials.push(made.value);
	}
	const defaultIndex: int32 = assets.materials.length as int32;
	if (usesDefaultMaterial(data)) {
		const made: Result<MaterialId, GltfSceneError> =
			madeMaterial(context, setup, false, NO_TEXTURE);
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

export function releaseGltfAssets(
	ref context: DrawContext,
	assets: GltfAssets,
): Result<void, HandleError> {
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

function transformOf(data: GltfData, index: int32): Transform3D {
	return {
		position: data.nodes[index].local.position,
		rotation: data.nodes[index].local.rotation,
		scale: data.nodes[index].local.scale,
	};
}

export function addGltfNodes(
	ref scene: Scene3D,
	ref context: DrawContext,
	parent: NodeId3D,
	data: GltfData,
	bindings: Span<GltfMeshBinding>,
): Result<int32, GltfSceneError> {
	const _under: int32 = scene.liveRow(parent, "addGltfNodes");
	if ((bindings.length as int32) != (data.meshes.length as int32)) {
		return Result.err(GltfSceneError.BadMeshBinding);
	}
	for (const binding of bindings) {
		if (!context.hasMesh(binding.mesh) || !context.hasMaterial(binding.material)) {
			return Result.err(GltfSceneError.BadMeshBinding);
		}
	}
	const valid = validateGltfGraph(data);
	if (!valid.ok) { return Result.err(GltfSceneError.InvalidData); }
	const nodes: Vec<int32> = [];
	const parents: Vec<NodeId3D> = [];
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
		let id: NodeId3D = { index: NO_NODE_3D, generation: 0 };
		const mesh: int32 = data.nodes[index].mesh;
		if (mesh < 0) {
			id = addGroup(scene, under, transformOf(data, index));
		} else {
			const added: Result<NodeId3D, SceneError> = addMeshNode(
				scene, context, under, transformOf(data, index),
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
