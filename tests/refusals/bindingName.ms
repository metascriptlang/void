// expect: 8:2 @binding takes a number
import { glsl } from "../../src/shader/emit";
import { Vec4f, binding, builtin } from "../../src/shader/std";
struct In {
	@builtin(position) position: Vec4f;
}
struct Bad {
	@binding(n) tint: Vec4f;
}
function bindFs(input: In, b: Bad): Vec4f { return b.tint; }
console.log(glsl(bindFs));
