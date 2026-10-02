// expect: void3d: addMesh on a draw context that was closed
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MeshUploadError,
	addMesh,
	closeContext,
} from "../../src/void3d/draw";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let alias: DrawContext = context;
closeContext(context);
const _mesh: Result<MeshId, MeshUploadError> = addMesh(alias, GpuMesh.fullscreen(0, 3));
console.log("a closed context took a mesh");
