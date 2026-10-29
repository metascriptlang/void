// expect: 13:1 segment 'tinted' takes its phase struct, its bindings struct, a key and the carrier struct it reads, and 'scale' is none of them
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
