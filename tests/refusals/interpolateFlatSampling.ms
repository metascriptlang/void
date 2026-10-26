// expect: 9:2 @interpolate(flat) takes no sampling, as WGSL's
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, interpolate } from "../../src/shader/std";
struct A {
	position: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
	@interpolate(flat, centroid) tint: Vec4f;
}
function tintVs(input: A): V { return { clip: input.position, tint: input.position }; }
console.log(glsl(tintVs));
