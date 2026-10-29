import { Program } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { Texture } from "../gpu/texture";
import { Material, Phase, ShadowCasting } from "../void3d/material";
import { TextureData, TextureId, TextureAlpha } from "../void3d/texture";
import { claim } from "../void3d/slots";
import { contextGeneration } from "../gpu/door";
import { MeshData } from "../void3d/meshData";
import { PassList } from "../void3d/passList";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	EXTERNAL_GENERATION,
	addMesh,
	addMaterial,
} from "../void3d/draw";

// `meshes` meshes and `materials` materials that draw nothing and make no GPU object, each held
// once, at the index of its position, so a scene test tells its nodes apart by the mesh they draw.
export function contextOf(meshes: int32, materials: int32): DrawContext {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	for (let i = 0; i < meshes; i++) {
		const _mesh: MeshId = added(context, GpuMesh.fullscreen(0, 3));
	}
	for (let i = 0; i < materials; i++) {
		const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
		const _material: Result<MaterialId, MaterialError> = addMaterial(context, plain);
	}
	return context;
}

// A Lit mesh with nothing to draw, marked the caller's so that addMesh takes it.
export function litShape(): GpuMesh {
	return { ...MeshData.empty().meshFor(0, 0, 0), generation: EXTERNAL_GENERATION };
}

// A mesh addMesh takes: the caller's, or a stream.
export function added(context: DrawContext, mesh: GpuMesh): MeshId {
	const result: Result<MeshId, MeshUploadError> = addMesh(context, mesh);
	if (!result.ok) { unreachable; }
	return result.value;
}

export function meshAt(this context: DrawContext, index: int32): MeshId {
	return {
		store: context.serial,
		index: index,
		generation: context.meshSlots.generations[index],
	};
}

export function materialAt(this context: DrawContext, index: int32): MaterialId {
	return {
		store: context.serial,
		index: index,
		generation: context.materialSlots.generations[index],
	};
}

export function lastMaterial(this context: DrawContext): MaterialId {
	return context.materialAt((context.materials.length as int32) - 1);
}

export function writeTables(
	context: DrawContext,
	meshData: Readonly<Span<MeshData>>,
	materials: Readonly<Span<Material>>,
): void {
	for (let i = 0; i < (meshData.length as int32); i++) {
		context.meshData[i] = meshData[i].copy();
	}
	for (let i = 0; i < (materials.length as int32); i++) {
		context.materials[i].pass = { ...materials[i].pass };
	}
}

export function textureViewAt(context: DrawContext, index: int32): uint32 {
	const owner: Texture | null = context.textures[index].texture;
	return owner !== null ? owner.view : 0;
}

// What a lost context leaves of the texture at `index`: its image and its sampler of an older
// generation, the way beginFrame's new-context branch finds them.
export function loseTextureAt(context: DrawContext, index: int32): void {
	const owner: Texture | null = context.textures[index].texture;
	if (owner !== null) { owner.generation = 0; }
	context.textures[index].samplerGeneration = 0;
}

export function textureGenerationAt(context: DrawContext, index: int32): int32 {
	const owner: Texture | null = context.textures[index].texture;
	return owner !== null ? owner.generation : 0;
}

// A texture slot, held once, whose owner is `owner`, for a context with no texture slot yet.
export function addedOwner(context: DrawContext, owner: Texture): TextureId {
	const index: int32 = claim(context.textureSlots);
	if (index != (context.textures.length as int32)) { unreachable; }
	context.textures.push({
		texture: owner,
		sampler: 1,
		samplerGeneration: contextGeneration(),
	});
	context.textureData.push(TextureData.empty());
	context.textureHolders.push(1);
	context.texturePins.push(0);
	context.textureTargets.push(null);
	context.textureAlphas.push(TextureAlpha.Straight);
	return {
		store: context.serial,
		index: index,
		generation: context.textureSlots.generations[index],
	};
}

// One phase's list as beginFrame filled it before collectVisible, the oracle its pins compare to.
export function collect(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	materials: Readonly<Span<Material>>,
): void {
	while ((list.indices.length as int32) < (items.length as int32)) {
		list.indices.push(0);
		list.depths.push(0.0);
		list.layers.push(0);
		list.orders.push(0);
	}
	let count: int32 = 0;
	for (let i = 0; i < (items.length as int32); i++) {
		const material: int32 = items[i].material.index;
		if (materials[material].phase == list.phase &&
			materials[material].castShadows != ShadowCasting.Only) {
			list.indices[count] = i;
			list.layers[count] = materials[material].layer;
			list.orders[count] = items[i].order;
			count = count + 1;
		}
	}
	list.count = count;
}
