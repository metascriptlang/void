// expect: void3d: Core LitTextured uv-transform has no pbr variant
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
const made: ProgramKey = ProgramKey.of(Program.LitTextured).withUvTransform().withPbr();
console.log(`a moving key with the pbr block was made: ${made.describe()}`);
