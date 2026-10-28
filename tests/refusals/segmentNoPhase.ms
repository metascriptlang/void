// expect: 7:1 segment 'blank' takes its phase struct as its first parameter
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec4f, vec4f } from "../../src/shader/std";
struct Shaded {
	color: Vec4f;
}
function blank(): Shaded {
	return { color: vec4f(0.0) };
}
console.log(glslSegmentIr(blank));
