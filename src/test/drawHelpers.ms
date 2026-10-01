import { Program } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { Material, Phase } from "../void3d/material";
import { MeshData } from "../void3d/meshData";
import {
	DrawContext,
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
	return { index: index, generation: context.meshSlots.generations[index] };
}

export function materialAt(this context: DrawContext, index: int32): MaterialId {
	return { index: index, generation: context.materialSlots.generations[index] };
}

export function lastMaterial(this context: DrawContext): MaterialId {
	return context.materialAt((context.materials.length as int32) - 1);
}
