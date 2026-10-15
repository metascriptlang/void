// expect: 12:2 'tint' names two things in one stage
import { glsl } from "../../src/shader/emit";
import { Sampler, Texture2d, Vec4f, binding, builtin, textureSample } from "../../src/shader/std";
struct In {
	@builtin(position) position: Vec4f;
}
struct Params {
	tint: Vec4f;
}
struct Both {
	@binding(0) params: Params;
	@binding(1) tint: Texture2d;
	@binding(2) smp: Sampler;
}
function dupFs(input: In, b: Both): Vec4f {
	return b.params.tint * textureSample(b.tint, b.smp, input.position.xy);
}
console.log(glsl(dupFs));
