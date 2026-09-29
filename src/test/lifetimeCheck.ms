import { Program } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
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
	buryDoomed,
} from "../void3d/draw";
import { added } from "./drawHelpers";
import { UniformError } from "../void3d/uniformPool";
import {
	Transform3D,
	Scene3D,
	NodeId3D,
	SceneError,
	NO_NODE_3D,
	addGroup,
	addMeshNode,
	remove,
	removeChildren,
	setMeshOf,
	setName,
} from "../void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	bindMeshFrames,
	releaseMeshFrames,
	syncMeshFrame,
	update,
} from "../void3d/animation";

const NO_ID: NodeId3D = { index: NO_NODE_3D, generation: 0 };
const NO_MATERIAL: MaterialId = { index: -1, generation: 0 };

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
	const id: MeshId = added(context, quad());
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
	const first: MeshId = added(context, quad());
	assert holders(releaseMesh(context, first)) == 0;
	const next: MeshId = added(context, quad());
	assert next.index == first.index && next.generation == first.generation + 1;
	assert !context.hasMesh(first) && context.hasMesh(next);
	assert (context.meshes.length as int32) == 1;
}

test "the buffers the context made for a freed mesh are doomed, a caller's never" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const stream: MeshId = added(context, GpuMesh.streamMesh(4, 77, 5));
	const external: MeshId = added(context, GpuMesh.billboards(12, 1));
	const neverMade: MeshId = added(context, GpuMesh.streamMesh(4, 0, 0));
	for (const id of [stream, external, neverMade]) {
		assert holders(releaseMesh(context, id)) == 0;
	}
	assert (context.doomed.length as int32) == 1;
	assert context.doomed[0].buffer == 77 && context.doomed[0].generation == 5;
	assert context.meshes[stream.index].instanceBuffer == 0;
}

test "a doomed buffer of an older GPU context is dropped, not destroyed" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	for (const buffer of [31, 32, 77]) {
		const id: MeshId = added(context, GpuMesh.streamMesh(4, buffer as uint32, 5));
		assert holders(releaseMesh(context, id)) == 0;
	}
	assert (context.doomed.length as int32) == 3;
	assert buryDoomed(context, 6) == 0;
	assert (context.doomed.length as int32) == 0;
}

test "addMesh refuses a mesh made in a context that it could not remake" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const lit: Result<MeshId, MeshUploadError> =
		addMesh(context, { ...MeshData.empty().meshFor(31, 0, 5), indexBuffer: 32 });
	assert !lit.ok;
	if (!lit.ok) { assert lit.error == MeshUploadError.Unrebuildable; }
	assert context.liveMeshes() == 0;
	assert addMesh(context, GpuMesh.streamMesh(4, 77, 5)).ok;
	assert !addMesh(context, MeshData.empty().meshFor(0, 0, 0)).ok;
	assert !addMesh(context, { ...GpuMesh.billboards(12, 4), generation: 0 }).ok;
	assert !addMesh(context, GpuMesh.streamMesh(16, 9, 0)).ok;
	assert addMesh(context, GpuMesh.fullscreen(9, 3)).ok;
}

test "an upload refused before the driver frees its slot" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const refused: Result<MeshId, MeshUploadError> = addMeshData(context, MeshData.empty());
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == MeshUploadError.EmptyMesh; }
	assert context.liveMeshes() == 0 && (context.doomed.length as int32) == 0;
	const next: MeshId = added(context, quad());
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
	if (!owned.ok) { assert owned.error == UniformError.Owned; }
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
	const mesh: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), mesh, material)
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
	const mesh: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	for (let i = 0; i < 3; i++) {
		const _node: NodeId3D =
			try addMeshNode(scene, context, group, Transform3D.identity(), mesh, material)
			catch NO_ID;
	}
	assert context.meshHolders[mesh.index] == 4;
	assert remove(scene, context, group).ok;
	assert context.meshHolders[mesh.index] == 1 && context.materialHolders[material.index] == 1;
}

test "setMeshOf holds the new mesh before it lets go of the one shown, even when they are one" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const shown: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), shown, material)
		catch NO_ID;
	assert holders(releaseMesh(context, shown)) == 1;
	assert setMeshOf(scene, context, node, shown).ok;
	assert context.hasMesh(shown) && context.meshHolders[shown.index] == 1;
	const next: MeshId = added(context, quad());
	assert setMeshOf(scene, context, node, next).ok;
	assert !context.hasMesh(shown) && context.meshHolders[next.index] == 2;
}

test "a node refuses a released mesh or material, and holds nothing then" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	const goneMesh: MeshId = added(context, quad());
	const goneMaterial: MaterialId = plainMaterial(context);
	assert holders(releaseMesh(context, goneMesh)) == 0;
	assert holders(releaseMaterial(context, goneMaterial)) == 0;
	let scene: Scene3D = Scene3D.create();
	const noMesh: Result<NodeId3D, SceneError> =
		addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), goneMesh, material);
	assert !noMesh.ok;
	if (!noMesh.ok) { assert noMesh.error == SceneError.StaleMesh; }
	const noMaterial: Result<NodeId3D, SceneError> =
		addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), mesh, goneMaterial);
	assert !noMaterial.ok;
	if (!noMaterial.ok) { assert noMaterial.error == SceneError.StaleMaterial; }
	assert context.meshHolders[mesh.index] == 1 && context.materialHolders[material.index] == 1;
	assert scene.nodeCount() == 1;
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), mesh, material)
		catch NO_ID;
	const swapped: Result<int32, SceneError> = setMeshOf(scene, context, node, goneMesh);
	assert !swapped.ok;
	if (!swapped.ok) { assert swapped.error == SceneError.StaleMesh; }
	assert context.meshHolders[mesh.index] == 2;
}

function loadRocks(
	ref scene: Scene3D,
	ref context: DrawContext,
	under: NodeId3D,
): Result<int32, SceneError> {
	const rock: MeshId = added(context, quad());
	defer releaseMesh(context, rock);
	const stone: MaterialId = plainMaterial(context);
	defer releaseMaterial(context, stone);
	if (!scene.isLive(under)) { return Result.err(SceneError.StaleNode); }
	const _first: NodeId3D =
		try addMeshNode(scene, context, under, Transform3D.identity(), rock, stone);
	const _second: NodeId3D = try addMeshNode(
		scene,
		context,
		under,
		Transform3D.identity(),
		rock,
		stone,
	);
	return Result.ok(2);
}

test "a loader that lets go of its own with defer leaves its meshes to the nodes, or to no one" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create();
	const level: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
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

test "a caller that would take a mesh node's hold is refused, and the mesh stays" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), mesh, material)
		catch NO_ID;
	assert holders(releaseMesh(context, mesh)) == 1;
	assert handleError(releaseMesh(context, mesh)) == HandleError.OnlyPinned;
	assert holders(releaseMaterial(context, material)) == 1;
	assert handleError(releaseMaterial(context, material)) == HandleError.OnlyPinned;
	assert context.hasMesh(mesh) && context.hasMaterial(material);
	assert holders(retainMesh(context, mesh)) == 2;
	assert holders(releaseMesh(context, mesh)) == 1;
	assert remove(scene, context, node).ok;
	assert !context.hasMesh(mesh) && !context.hasMaterial(material);
}

test "removeChildren lets go of everything under a node and keeps the node" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const level: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const _first: NodeId3D =
		try addMeshNode(scene, context, level, Transform3D.identity(), mesh, material) catch NO_ID;
	const _second: NodeId3D = try addMeshNode(
		scene,
		context,
		scene.rootId(),
		Transform3D.identity(),
		mesh,
		material,
	) catch NO_ID;
	assert holders(releaseMesh(context, mesh)) == 2;
	assert holders(releaseMaterial(context, material)) == 2;
	const removed: Result<int32, SceneError> = removeChildren(scene, context, scene.rootId());
	assert removed.ok;
	if (removed.ok) { assert removed.value == 3; }
	assert scene.nodeCount() == 1 && scene.isLive(scene.rootId());
	assert !context.hasMesh(mesh) && !context.hasMaterial(material);
}

test "a frame swap on a node whose pin a copy of the scene took answers NotPinned" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const shown: MeshId = added(context, quad());
	const first: MeshId = added(context, quad());
	const second: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), shown, material)
		catch NO_ID;
	setName(scene, node, "pet");
	const clock: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(2, 1.0, Interpolation.Step);
	assert clock.ok;
	if (!clock.ok) { return; }
	const frames: Vec<MeshId> = [first, second];
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(context, clock.value, "pet", frames);
	assert made.ok;
	if (!made.ok) { return; }
	let animation: MeshFrameAnimation = made.value;
	const _bound: int32 = try bindMeshFrames(animation, scene, scene.rootId()) catch -1;
	let copy: Scene3D = scene;
	assert remove(copy, context, node).ok;
	assert context.hasMesh(shown) && context.meshPinned(shown) == 0;
	const swapped: Result<int32, AnimationError> = syncMeshFrame(animation, scene, context);
	assert !swapped.ok;
	if (!swapped.ok) { assert swapped.error == AnimationError.NotPinned; }
}

test "a baked animation holds its frames, the ones off screen too, until it lets them go" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const first: MeshId = added(context, quad());
	const second: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), first, material)
		catch NO_ID;
	setName(scene, node, "pet");
	const clock: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(2, 1.0, Interpolation.Step);
	assert clock.ok;
	if (!clock.ok) { return; }
	const frames: Vec<MeshId> = [first, second];
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(context, clock.value, "pet", frames);
	assert made.ok;
	if (!made.ok) { return; }
	let animation: MeshFrameAnimation = made.value;
	assert holders(releaseMesh(context, first)) == 2;
	assert holders(releaseMesh(context, second)) == 1;
	assert context.hasMesh(second);
	const _bound: int32 = try bindMeshFrames(animation, scene, scene.rootId()) catch -1;
	const _stepped: boolean = try update(animation.clock, 1.0) catch false;
	assert syncMeshFrame(animation, scene, context).ok;
	const released: Result<int32, AnimationError> = releaseMeshFrames(animation, context);
	assert released.ok;
	assert !context.hasMesh(first) && context.hasMesh(second);
	assert context.meshHolders[second.index] == 1;
}

test "an over-release is refused while only pins hold a frame, and frames go all or none" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const shown: MeshId = added(context, quad());
	const offScreen: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const node: NodeId3D =
		try addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), shown, material)
		catch NO_ID;
	const clock: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(2, 1.0, Interpolation.Step);
	assert clock.ok;
	if (!clock.ok) { return; }
	const frames: Vec<MeshId> = [shown, offScreen];
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(context, clock.value, "pet", frames);
	assert made.ok;
	if (!made.ok) { return; }
	let animation: MeshFrameAnimation = made.value;
	assert holders(releaseMesh(context, shown)) == 2;
	assert handleError(releaseMesh(context, shown)) == HandleError.OnlyPinned;
	let copy: MeshFrameAnimation = animation;
	assert releaseMeshFrames(animation, context).ok;
	assert context.meshPinned(shown) == 1 && context.meshPinned(offScreen) == 0;
	const twice: Result<int32, AnimationError> = releaseMeshFrames(copy, context);
	assert !twice.ok;
	if (!twice.ok) { assert twice.error == AnimationError.NotPinned; }
	assert context.meshPinned(shown) == 1 && (copy.meshes.length as int32) == 2;
	assert holders(releaseMesh(context, offScreen)) == 0;
	assert releaseMeshFrames(copy, context).ok;
	assert !context.hasMesh(shown);
	assert remove(scene, context, node).ok;
	assert context.hasMaterial(material) && context.materialPins[material.index] == 0;
}

test "a copy of a scene that removed the same nodes is refused by name, and nothing changes" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh: MeshId = added(context, quad());
	const material: MaterialId = plainMaterial(context);
	let scene: Scene3D = Scene3D.create();
	const level: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	for (let i = 0; i < 2; i++) {
		const _node: NodeId3D =
			try addMeshNode(scene, context, level, Transform3D.identity(), mesh, material)
			catch NO_ID;
	}
	let copy: Scene3D = scene;
	assert remove(scene, context, level).ok;
	assert context.meshHolders[mesh.index] == 1;
	const again: Result<int32, SceneError> = remove(copy, context, level);
	assert !again.ok;
	if (!again.ok) { assert again.error == SceneError.NotPinned; }
	assert copy.nodeCount() == 4 && context.meshHolders[mesh.index] == 1;
}

test "a material frees the range it was added with, whatever its uniforms field says later" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const first: UniformBlock = try reserveUniforms(context, 2, 4) catch NO_UNIFORMS;
	const second: UniformBlock = try reserveUniforms(context, 2, 4) catch NO_UNIFORMS;
	const a: MaterialId =
		try addMaterial(context, { ...plain, uniforms: first }) catch NO_MATERIAL;
	const b: MaterialId =
		try addMaterial(context, { ...plain, uniforms: second }) catch NO_MATERIAL;
	context.materials[b.index].uniforms = first;
	assert !context.keepsItsUniforms(b) && context.keepsItsUniforms(a);
	assert holders(releaseMaterial(context, b)) == 0;
	assert context.uniforms.holds(first) && !context.uniforms.holds(second);
	assert holders(releaseMaterial(context, a)) == 0;
	assert !context.uniforms.holds(first);
}
