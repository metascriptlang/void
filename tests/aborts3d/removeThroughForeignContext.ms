// expect: void3d: remove through a context that did not issue the mesh or material of node 1
import { Program } from "../../src/void3d/gpu3d";
import { RenderState } from "../../src/gpu/state";
import { Material, Phase } from "../../src/void3d/material";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	addMesh,
	addMaterial,
} from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addMeshNode,
	remove,
} from "../../src/void3d/scene";

let made: DrawContext = DrawContext.withUniformCapacity(0);
let other: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const mesh: Result<MeshId, MeshUploadError> = addMesh(made, GpuMesh.fullscreen(0, 3));
const material: Result<MaterialId, MaterialError> =
	addMaterial(made, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
if (!mesh.ok || !material.ok) { unreachable; }
const node: Result<NodeId3D, SceneError> =
	addMeshNode(
		scene, made, scene.rootId(), Transform3D.identity(), mesh.value, material.value,
	);
if (!node.ok) { unreachable; }
const _removed: Result<int32, SceneError> = remove(scene, other, node.value);
console.log("the call returned");
