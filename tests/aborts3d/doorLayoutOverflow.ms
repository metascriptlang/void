// expect: gpu door: the vertex layout registry is full (8)
import { invalidLayoutCount } from "../integration/gpuRegistrationFixture";
let refused: int32 = invalidLayoutCount(2147483647);
console.log(`overflowing layout count returned ${refused}`);
