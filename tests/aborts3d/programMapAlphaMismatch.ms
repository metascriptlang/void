// expect: void3d: ProgramMap draws UnlitTexturedPremultiplied as UnlitTextured
import { ProgramMap } from "../../src/void3d/programMap";
import { Program } from "../../src/void3d/gpu3d";
const map: ProgramMap =
	ProgramMap.empty().drawing(Program.UnlitTexturedPremultiplied, Program.UnlitTextured);
console.log(`a premultiplied program drawn straight was accepted: ${map.drawnHigh}`);
