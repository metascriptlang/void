// expect: 9:29 '%' by a constant zero: an integer remainder of const-expressions by zero is a shader-creation error in WGSL
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct Pixel {
	@builtin(position) position: Vec4f;
}
function splitFs(input: Pixel): Vec4f {
	const none = 0 as uint32;
	const left = (5 as uint32) % none;
	return vec4f(left as float32, 0.0, 0.0, 1.0);
}
console.log(glsl(splitFs));
