// expect: void3d: ProgramMap draws LitCutout as Lit; a cutout program is drawn only as a cutout one
import { ProgramMap } from "../../src/void3d/programMap";
import { Program } from "../../src/void3d/gpu3d";
const map: ProgramMap = ProgramMap.empty().drawing(Program.LitCutout, Program.Lit);
console.log(`a cutout program drawn whole was accepted: ${map.drawnHigh}`);
