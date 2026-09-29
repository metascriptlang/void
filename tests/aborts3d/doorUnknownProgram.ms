// expect: gpu door: unregistered program id
import { programLayout } from "../../src/gpu/door";
let layout: int32 = programLayout(-1);
console.log(`unknown program returned layout ${layout}`);
