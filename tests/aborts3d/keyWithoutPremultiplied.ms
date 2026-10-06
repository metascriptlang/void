// expect: void3d: Core Lit has no premultiplied variant
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
const made: ProgramKey = ProgramKey.of(Program.Lit).withPremultiplied();
console.log(`a premultiplied key of an untextured program was made: ${made.describe()}`);
