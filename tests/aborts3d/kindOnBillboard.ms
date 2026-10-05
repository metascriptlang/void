// expect: void3d: MaterialKind.AlphaKill for Billboard, which already cuts at a fixed alpha
import { Material, MaterialKind } from "../../src/void3d/material";
import { Program } from "../../src/void3d/gpu3d";
const made: Material = Material.ofKind(Program.Billboard, MaterialKind.AlphaKill);
console.log(`an AlphaKill billboard was made: ${made.program.toString()}`);
