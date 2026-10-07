// expect: reads 28 floats of slot 3 and its material's block holds 4
import { DrawContext, applyBlockHead } from "../../src/void3d/draw";
import { UniformBlock } from "../../src/void3d/material";
import { Program, ProgramKey, Preset, MATERIAL_UNIFORM_SLOT } from "../../src/void3d/gpu3d";

let context: DrawContext = DrawContext.withUniformCapacity(64);
const short: UniformBlock = {
	store: context.uniforms.serial, slot: MATERIAL_UNIFORM_SLOT, offset: 0,
	length: 4, generation: 1,
};
const caster: ProgramKey =
	ProgramKey.of(Program.LitTextured).withDissolve().withPreset(Preset.Shadow);
context.applyBlockHead(short, caster, 28);
console.log("a short block was applied");
