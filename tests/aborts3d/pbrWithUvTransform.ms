// expect: void3d: Core LitTextured pbr has no uv transform variant
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
const made: ProgramKey = ProgramKey.of(Program.LitTextured).withPbr().withUvTransform();
console.log(`a pbr key with the moving block was made: ${made.describe()}`);
