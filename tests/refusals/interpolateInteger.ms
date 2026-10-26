// expect: 9:2 an integer varying is @interpolate(flat), as WGSL's
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, interpolate } from "../../src/shader/std";
struct A {
	position: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
	@interpolate(linear) id: uint32;
}
function idVs(input: A): V { return { clip: input.position, id: 1 }; }
console.log(glsl(idVs));
