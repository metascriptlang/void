// expect: 7:1 two stage input structs: 'other'
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin } from "../../src/shader/std";
struct In {
	@builtin(position) position: Vec4f;
}
function twoFs(input: In, other: In): Vec4f { return input.position; }
console.log(glsl(twoFs));
