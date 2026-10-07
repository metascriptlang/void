// expect: void3d: movingDefaults for Core LitTextured, which does not move
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
import { movingDefaults } from "../../src/void3d/material";
const values: Vec<float32> = movingDefaults(ProgramKey.of(Program.LitTextured));
console.log(`a still key got a moving block of ${values.length} floats`);
