// expect: 8:13 hook: a segment is no base; an entry calls hook
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec4f, hook } from "../../src/shader/std";
struct Shaded {
	color: Vec4f;
}
function hooked(shaded: Shaded): Shaded {
	return hook(shaded);
}
console.log(glslSegmentIr(hooked));
