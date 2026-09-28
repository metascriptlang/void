import { Program } from "../void3d/gpu3d";
import { RenderState } from "../void3d/pass";
import { MeshData } from "../void3d/meshData";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "../void3d/material";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	addMesh,
	addMeshData,
	addMaterial,
	retainMesh,
	releaseMesh,
	retainMaterial,
	releaseMaterial,
	reserveUniforms,
	releaseUniforms,
} from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import {
	Scene,
	NodeId,
	SceneError,
	NO_NODE,
	identityTransform,
	addGroup,
	addMeshNode,
	remove,
	setMeshOf,
} from "../void3d/scene";

const NO_ID: NodeId = { index: NO_NODE, generation: 0 };

function quad(): GpuMesh {
	return GpuMesh.billboards(0, 0);
}

function plainMaterial(ref context: DrawContext): MaterialId {
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, plain);
	if (!added.ok) { unreachable; }
	return added.value;
}

function holders(result: Result<int32, HandleError>): int32 {
	return result.ok ? result.value : -1;
}

function handleError(result: Result<int32, HandleError>): HandleError {
	return result.ok ? HandleError.StaleMaterial : result.error;
}

test "a mesh lives until its last holder lets go, and its id then names nothing" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const id: MeshId = addMesh(context, quad());
	assert context.meshHolders[id.index] == 1;
	assert holders(retainMesh(context, id)) == 2;
	assert holders(releaseMesh(context, id)) == 1;
	assert context.hasMesh(id);
	assert holders(releaseMesh(context, id)) == 0;
	assert !context.hasMesh(id) && context.liveMeshes() == 0;
	assert handleError(releaseMesh(context, id)) == HandleError.StaleMesh;
	assert handleError(retainMesh(context, id)) == HandleError.StaleMesh;
}

test "a freed slot comes back a generation later, and the old id stays stale" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const first: MeshId = addMesh(context, quad());
	assert holders(releaseMesh(context, first)) == 0;
	const next: MeshId = addMesh(context, quad());
	assert next.index == first.index && next.generation == first.generation + 1;
	assert !context.hasMesh(first) && context.hasMesh(next);
	assert (context.meshes.length as int32) == 1;
}

test "the buffers the context made for a freed mesh wait for a frame of their own context" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const stream: MeshId = addMesh(context, GpuMesh.streamMesh(4, 77, 5));
	const lit: MeshId = addMesh(
		context,
		{ ...MeshData.empty().meshFor(31, 0, 5), indexBuffer: 32 },
	);
	const external: MeshId = addMesh(context, GpuMesh.billboards(12, 1));
	const neverMade: MeshId = addMesh(context, GpuMesh.streamMesh(4, 0, 0));
	for (const id of [stream, lit, external, neverMade]) {
		assert holders(releaseMesh(context, id)) == 0;
	}
	assert (context.doomed.length as int32) == 3;
	assert context.doomedFor(5) == 3 && context.doomedFor(6) == 0;
	for (const doomed of context.doomed) {
		assert doomed.buffer == 77 || doomed.buffer == 31 || doomed.buffer == 32;
	}
	assert context.meshes[stream.index].instanceBuffer == 0;
}

test "an upload refused before the driver frees its slot" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const refused: Result<MeshId, MeshUploadError> = addMeshData(context, MeshData.empty());
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == MeshUploadError.EmptyMesh; }
	assert context.liveMeshes() == 0 && (context.doomed.length as int32) == 0;
	const next: MeshId = addMesh(context, quad());
	assert next.index == 0 && next.generation == 2;
}

test "a material takes its uniform range with it when its last holder lets go" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const block: UniformBlock = try reserveUniforms(context, 2, 4) catch NO_UNIFORMS;
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, uniforms: block });
	assert added.ok;
	if (!added.ok) { return; }
	const owned: Result<int32, UniformError> = releaseUniforms(context, block);
	assert !owned.ok;
	if (!owned.ok) { assert owned.error == UniformError.OwnedByMaterial; }
	assert holders(retainMaterial(context, added.value)) == 2;
	assert holders(releaseMaterial(context, added.value)) == 1;
	assert context.uniforms.holds(block);
	assert holders(releaseMaterial(context, added.value)) == 0;
	assert !context.hasMaterial(added.value) && context.liveMaterials() == 0;
	assert !context.uniforms.holds(block) && context.uniforms.freeRanges() == 1;
	const reused: UniformBlock = try reserveUniforms(context, 2, 4) catch NO_UNIFORMS;
	assert reused.offset == block.offset && reused.generation == block.generation + 1;
	assert handleError(releaseMaterial(context, added.value)) == HandleError.StaleMaterial;
}

test "a mesh node holds its mesh and material from addMeshNode until remove" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = addMesh(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene = Scene.create();
	const node: NodeId =
		try addMeshNode(scene, context, scene.rootId(), identityTransform(), mesh, material)
		catch NO_ID;
	assert context.meshHolders[mesh.index] == 2 && context.materialHolders[material.index] == 2;
	assert holders(releaseMesh(context, mesh)) == 1;
	assert holders(releaseMaterial(context, material)) == 1;
	assert context.hasMesh(mesh) && context.hasMaterial(material);
	assert remove(scene, context, node).ok;
	assert !context.hasMesh(mesh) && !context.hasMaterial(material);
}

test "removing a group lets go once for every mesh node under it" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = addMesh(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene = Scene.create();
	const group: NodeId = try addGroup(scene, scene.rootId(), identityTransform()) catch NO_ID;
	for (let i = 0; i < 3; i++) {
		const _node: NodeId =
			try addMeshNode(scene, context, group, identityTransform(), mesh, material) catch NO_ID;
	}
	assert context.meshHolders[mesh.index] == 4;
	assert remove(scene, context, group).ok;
	assert context.meshHolders[mesh.index] == 1 && context.materialHolders[material.index] == 1;
}

test "setMeshOf holds the new mesh before it lets go of the one shown, even when they are one" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const shown: MeshId = addMesh(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene = Scene.create();
	const node: NodeId =
		try addMeshNode(scene, context, scene.rootId(), identityTransform(), shown, material)
		catch NO_ID;
	assert holders(releaseMesh(context, shown)) == 1;
	assert setMeshOf(scene, context, node, shown).ok;
	assert context.hasMesh(shown) && context.meshHolders[shown.index] == 1;
	const next: MeshId = addMesh(context, quad());
	assert setMeshOf(scene, context, node, next).ok;
	assert !context.hasMesh(shown) && context.meshHolders[next.index] == 2;
}

test "a node refuses a released mesh or material, and holds nothing then" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = addMesh(context, quad());
	const material: MaterialId = plainMaterial(context);
	const goneMesh: MeshId = addMesh(context, quad());
	const goneMaterial: MaterialId = plainMaterial(context);
	assert holders(releaseMesh(context, goneMesh)) == 0;
	assert holders(releaseMaterial(context, goneMaterial)) == 0;
	let scene: Scene = Scene.create();
	const noMesh: Result<NodeId, SceneError> =
		addMeshNode(scene, context, scene.rootId(), identityTransform(), goneMesh, material);
	assert !noMesh.ok;
	if (!noMesh.ok) { assert noMesh.error == SceneError.StaleMesh; }
	const noMaterial: Result<NodeId, SceneError> =
		addMeshNode(scene, context, scene.rootId(), identityTransform(), mesh, goneMaterial);
	assert !noMaterial.ok;
	if (!noMaterial.ok) { assert noMaterial.error == SceneError.StaleMaterial; }
	assert context.meshHolders[mesh.index] == 1 && context.materialHolders[material.index] == 1;
	assert scene.nodeCount() == 1;
	const node: NodeId =
		try addMeshNode(scene, context, scene.rootId(), identityTransform(), mesh, material)
		catch NO_ID;
	const swapped: Result<int32, SceneError> = setMeshOf(scene, context, node, goneMesh);
	assert !swapped.ok;
	if (!swapped.ok) { assert swapped.error == SceneError.StaleMesh; }
	assert context.meshHolders[mesh.index] == 2;
}

function loadRocks(
	ref scene: Scene,
	ref context: DrawContext,
	under: NodeId,
): Result<int32, SceneError> {
	const rock: MeshId = addMesh(context, quad());
	defer releaseMesh(context, rock);
	const stone: MaterialId = plainMaterial(context);
	defer releaseMaterial(context, stone);
	const _first: NodeId = try addMeshNode(scene, context, under, identityTransform(), rock, stone);
	const _second: NodeId = try addMeshNode(
		scene,
		context,
		under,
		identityTransform(),
		rock,
		stone,
	);
	return Result.ok(2);
}

test "a loader that lets go of its own with defer leaves its meshes to the nodes, or to no one" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene = Scene.create();
	const level: NodeId = try addGroup(scene, scene.rootId(), identityTransform()) catch NO_ID;
	const loaded: Result<int32, SceneError> = loadRocks(scene, context, level);
	assert loaded.ok;
	assert context.liveMeshes() == 1 && context.liveMaterials() == 1;
	assert context.meshHolders[0] == 2;
	assert remove(scene, context, level).ok;
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
	const refused: Result<int32, SceneError> = loadRocks(scene, context, level);
	assert !refused.ok;
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
}
