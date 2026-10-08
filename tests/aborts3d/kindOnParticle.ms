// expect: void3d: MaterialKind.AlphaKill for Particle, which already cuts at a fixed alpha
import { Material, MaterialKind } from "../../src/void3d/material";
import { Program } from "../../src/void3d/gpu3d";
const made: Material = Material.ofKind(Program.Particle, MaterialKind.AlphaKill);
console.log(`an AlphaKill particle was made: ${made.program.toString()}`);
