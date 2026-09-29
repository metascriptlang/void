// expect: gpu door: the program registry is full (16)
import { invalidProgramCount } from "../integration/gpuRegistrationFixture";
let refused: int32 = invalidProgramCount(2147483647);
console.log(`overflowing program count returned ${refused}`);
