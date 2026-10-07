// expect: so a block of 8 is not its own; only a shadow caster takes a head
import { DrawContext, applyBlockHead } from "../../src/void3d/draw";
import { UniformBlock } from "../../src/void3d/material";
import { Program, ProgramKey, MATERIAL_UNIFORM_SLOT } from "../../src/void3d/gpu3d";

let context: DrawContext = DrawContext.withUniformCapacity(64);
const long: UniformBlock = {
	store: context.uniforms.serial, slot: MATERIAL_UNIFORM_SLOT, offset: 0,
	length: 8, generation: 1,
};
context.applyBlockHead(long, ProgramKey.of(Program.Lit), 4);
console.log("a long block was applied to a colour pass");
