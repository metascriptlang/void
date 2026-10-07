// expect: void3d: Core Billboard has no dissolve variant
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
const made: ProgramKey = ProgramKey.of(Program.Billboard).withDissolve();
console.log(`a dissolve key of an untextured program was made: ${made.describe()}`);
