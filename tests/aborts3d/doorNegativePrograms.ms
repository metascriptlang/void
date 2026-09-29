// expect: gpu door: registerPrograms count is negative
import { invalidProgramCount } from "../integration/gpuRegistrationFixture";
let refused: int32 = invalidProgramCount(-1);
console.log(`negative program count returned ${refused}`);
