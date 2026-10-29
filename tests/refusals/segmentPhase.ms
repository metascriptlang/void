// expect: 7:1 segment 'shadeUv' returns Vec4f, and a segment returns its phase struct UvStage or, reading no carrier, the carrier struct it writes
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec2f, Vec4f, vec4f } from "../../src/shader/std";
struct UvStage {
	uv: Vec2f;
}
function shadeUv(stage: UvStage): Vec4f {
	return vec4f(stage.uv.x, stage.uv.y, 0.0, 1.0);
}
console.log(glslSegmentIr(shadeUv));
