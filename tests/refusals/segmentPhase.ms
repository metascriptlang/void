// expect: 10:1 segment 'shadeUv' returns Shaded, and a segment returns its phase struct UvStage
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec2f, Vec4f, vec4f } from "../../src/shader/std";
struct UvStage {
	uv: Vec2f;
}
struct Shaded {
	color: Vec4f;
}
function shadeUv(stage: UvStage): Shaded {
	return { color: vec4f(stage.uv.x, stage.uv.y, 0.0, 1.0) };
}
console.log(glslSegmentIr(shadeUv));
