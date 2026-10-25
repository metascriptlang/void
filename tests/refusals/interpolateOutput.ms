// expect: 8:15 @interpolate sits on a varying, not a fragment output, as WGSL's
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, interpolate, location } from "../../src/shader/std";
struct A {
	@builtin(position) position: Vec4f;
}
struct O {
	@location(0) @interpolate(linear) color: Vec4f;
}
function outputFs(input: A): O { return { color: input.position }; }
console.log(glsl(outputFs));
