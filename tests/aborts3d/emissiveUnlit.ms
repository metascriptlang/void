// expect: void3d: Core UnlitTextured has no emissive variant
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
const made: ProgramKey = ProgramKey.of(Program.UnlitTextured).withEmissive();
console.log(`an emissive key of an unlit program was made: ${made.describe()}`);
