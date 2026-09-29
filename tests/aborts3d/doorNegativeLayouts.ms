// expect: gpu door: registerLayouts count is negative
import { invalidLayoutCount } from "../integration/gpuRegistrationFixture";
let refused: int32 = invalidLayoutCount(-1);
console.log(`negative layout count returned ${refused}`);
