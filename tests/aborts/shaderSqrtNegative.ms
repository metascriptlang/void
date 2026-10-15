// expect: sqrt: the GPU result is undefined below 0
import { sqrt } from "../../src/shader/std";

const below: float32 = -1.0;
console.log(`sqrt of a negative was ${sqrt(below)}`);
