// expect: gpu door: 2147483647 more vertex layout ids overflow int32
import { invalidLayoutCount } from "../integration/gpuRegistrationFixture";
let refused: int32 = invalidLayoutCount(2147483647);
console.log(`overflowing layout count returned ${refused}`);
