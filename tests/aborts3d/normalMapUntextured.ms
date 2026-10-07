// expect: void3d: Core Lit has no normal map variant
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
const made: ProgramKey = ProgramKey.of(Program.Lit).withNormalMap();
console.log(`a normal-mapped key of an untextured program was made: ${made.describe()}`);
