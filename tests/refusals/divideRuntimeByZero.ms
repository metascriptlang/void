// expect: ok
import { glsl } from "../../src/shader/emit";
import { Vec4f, binding, builtin, mat3x3f, vec4f } from "../../src/shader/std";
struct Pixel {
	@builtin(position) position: Vec4f;
}
struct Counts {
	total: uint32;
}
struct Bindings {
	@binding(0) counts: Counts;
}
function splitFs(input: Pixel, b: Bindings): Vec4f {
	const none = 0 as uint32;
	const share = b.counts.total / none;
	return vec4f(share as float32, 0.0, 0.0, 1.0);
}
console.log(glsl(splitFs));
