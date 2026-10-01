// expect: void3d: setMeshOf through a context that did not issue the mesh or material of node 1
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
	setMeshOf,
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
const shown: Result<MeshId, MeshUploadError> = addMesh(other, GpuMesh.fullscreen(0, 3));
if (!shown.ok) { unreachable; }
const _set: Result<int32, SceneError> =
	setMeshOf(scene, other, node.value, shown.value);
console.log("the call returned");
