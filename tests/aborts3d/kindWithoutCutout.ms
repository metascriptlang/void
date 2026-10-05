// expect: void3d: MaterialKind.AlphaKill for Copy, which has no cutout
import { Material, MaterialKind } from "../../src/void3d/material";
import { Program } from "../../src/void3d/gpu3d";
const made: Material = Material.ofKind(Program.Copy, MaterialKind.AlphaKill);
console.log(`a cutout of a program without one was made: ${made.program.toString()}`);
