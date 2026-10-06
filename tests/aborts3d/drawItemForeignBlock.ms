// expect: void3d: drawItem with a block at slot 0 its context does not hold
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
import { RenderState } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT } from "../../src/gpu/target";
import { identity } from "../../src/math/math3d";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	addMesh,
	addMaterial,
	reserveUniforms,
	drawItem,
} from "../../src/void3d/draw";

let drawing: DrawContext = DrawContext.withUniformCapacity(8);
let other: DrawContext = DrawContext.withUniformCapacity(64);
const mesh: Result<MeshId, MeshUploadError> = addMesh(drawing, GpuMesh.fullscreen(0, 3));
const material: Result<MaterialId, MaterialError> =
	addMaterial(drawing, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
const padding: Result<UniformBlock, UniformError> = reserveUniforms(other, 0, 32);
const block: Result<UniformBlock, UniformError> = reserveUniforms(other, 0, 24);
if (!mesh.ok || !material.ok || !padding.ok || !block.ok) { unreachable; }
const item: DrawItem = { mesh: mesh.value, material: material.value, world: identity() };
const globals: Vec<UniformBlock> = [block.value];
drawItem(drawing, item, ProgramKey.of(Program.Lit), SWAPCHAIN_LAYOUT, globals);
console.log("the call returned");
