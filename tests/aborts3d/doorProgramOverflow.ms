// expect: gpu door: 2147483647 more program ids overflow int32
import { invalidProgramCount } from "../integration/gpuRegistrationFixture";
let refused: int32 = invalidProgramCount(2147483647);
console.log(`overflowing program count returned ${refused}`);
