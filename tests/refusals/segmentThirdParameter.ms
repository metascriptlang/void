// expect: 13:1 segment 'tinted' takes its phase struct and its bindings struct, and 'scale' is a third parameter
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec4f } from "../../src/shader/std";
struct Shaded {
	color: Vec4f;
}
struct Tint {
	tint: Vec4f;
}
struct TintBindings {
	tintParams: Tint;
}
function tinted(shaded: Shaded, b: TintBindings, scale: float32): Shaded {
	return { color: shaded.color + b.tintParams.tint * scale };
}
console.log(glslSegmentIr(tinted));
