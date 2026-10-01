// expect: void3d: tallyMeshPin through a context that did not issue the mesh
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MeshUploadError,
	addMesh,
	tallyMeshPin,
} from "../../src/void3d/draw";

let made: DrawContext = DrawContext.withUniformCapacity(0);
let other: DrawContext = DrawContext.withUniformCapacity(0);
const mesh: Result<MeshId, MeshUploadError> = addMesh(made, GpuMesh.fullscreen(0, 3));
if (!mesh.ok) { unreachable; }
const _covered: boolean = tallyMeshPin(other, mesh.value);
console.log("the call returned");
