// expect: 13:13 hook: the base already hooks phase struct 'Shaded'; one hook site per phase struct
import { glslIr } from "../../src/shader/emit";
import { Vec4f, builtin, hook } from "../../src/shader/std";
struct Shaded {
	color: Vec4f;
}
struct Pixel {
	@builtin(position) position: Vec4f;
}
function twiceFs(input: Pixel): Vec4f {
	const lit: Shaded = { color: input.position };
	const once = hook(lit);
	return hook(once).color;
}
console.log(glslIr(twiceFs));
