// expect: gpu door: unregistered layout id
import { layoutFloats } from "../../src/gpu/door";
let floats: int32 = layoutFloats(8, 0);
console.log(`unknown layout returned ${floats} floats`);
