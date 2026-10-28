// expect: 10:22 '/' by a constant zero: an integer division of const-expressions by zero is a shader-creation error in WGSL
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct Pixel {
	@builtin(position) position: Vec4f;
}
const WIDTH = 8 as uint32;
const NONE = 0 as uint32;
function splitFs(input: Pixel): Vec4f {
	const share = WIDTH / NONE;
	return vec4f(share as float32, 0.0, 0.0, 1.0);
}
console.log(glsl(splitFs));
