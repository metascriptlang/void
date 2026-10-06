// expect: void3d: drawItem with a material whose block is not the one it was added with
import { Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, ProgramKey } from "../../src/void3d/gpu3d";
import { RenderState } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT } from "../../src/gpu/target";
import { identity } from "../../src/math/math3d";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	addMesh,
	addMaterial,
	reserveUniforms,
	releaseUniforms,
	drawItem,
} from "../../src/void3d/draw";

const NO_GLOBALS: Vec<UniformBlock> = [];

function blockOf(context: DrawContext): UniformBlock {
	const made: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!made.ok) { unreachable; }
	return made.value;
}

let context: DrawContext = DrawContext.withUniformCapacity(3 * MATERIAL_UNIFORM_LENGTH);
const mesh = addMesh(context, GpuMesh.fullscreen(0, 3));
const lit: Material = {
	...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
	uniforms: blockOf(context),
};
const material = addMaterial(context, lit);
if (!mesh.ok || !material.ok) { unreachable; }
const gone: UniformBlock = blockOf(context);
if (!releaseUniforms(context, gone).ok) { unreachable; }
context.materials[material.value.index].uniforms = gone;
const item: DrawItem = { mesh: mesh.value, material: material.value, world: identity() };
drawItem(context, item, ProgramKey.of(Program.Lit), SWAPCHAIN_LAYOUT, NO_GLOBALS);
console.log("the call returned");
