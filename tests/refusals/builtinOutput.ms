// expect: 9:2 output field 'size': only a vertex @builtin(position) yet
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin } from "../../src/shader/std";
struct A {
	position: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
	@builtin(pointSize) size: float32;
}
function sizeVs(input: A): V { return { clip: input.position, size: 2.0 }; }
console.log(glsl(sizeVs));
