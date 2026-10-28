// expect: 8:2 segment binding 'frame' carries @binding(n): the linker numbers a segment's bindings
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec2f, binding, vec2f } from "../../src/shader/std";
struct Frame {
	time: float32;
}
struct ScrollBindings {
	@binding(0) frame: Frame;
}
struct UvStage {
	uv: Vec2f;
}
function scroll(stage: UvStage, b: ScrollBindings): UvStage {
	return { uv: stage.uv + vec2f(b.frame.time, 0.0) };
}
console.log(glslSegmentIr(scroll));
