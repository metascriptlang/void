// expect: void3d: no program declared for PixelArt Copy (src/void3d/programKeys.txt)
import { Program, ProgramKey, Preset, doorProgram } from "../../src/void3d/gpu3d";
const id: int32 = doorProgram(ProgramKey.of(Program.Copy).withPreset(Preset.PixelArt));
console.log(`an undeclared key reached the door as ${id}`);
