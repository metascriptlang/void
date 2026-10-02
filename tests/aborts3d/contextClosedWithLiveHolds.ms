// expect: void3d: closeContext with holds still live: meshes 1, materials 0, textures 0,
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MeshUploadError,
	addMesh,
	reserveUniforms,
	closeContext,
} from "../../src/void3d/draw";
import { UniformBlock } from "../../src/void3d/material";
import { UniformError } from "../../src/void3d/uniformPool";

let context: DrawContext = DrawContext.withUniformCapacity(4);
const mesh: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
const range: Result<UniformBlock, UniformError> = reserveUniforms(context, 2, 4);
if (!mesh.ok || !range.ok) { unreachable; }
closeContext(context);
console.log("a context closed with a mesh and a range held returned");
