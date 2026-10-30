// expect: 13:22 textureSample takes a constant offset: a vec2i of integer literals, or a const of one (a let, or a const of runtime values, is not a const-expression), as WGSL's
import { glsl } from "../../src/shader/emit";
import { Sampler, Texture2d, Vec2f, Vec4f, binding, builtin, textureSample, vec2f, vec2i, vec4f } from "../../src/shader/std";
struct Pixel {
	@builtin(position) position: Vec4f;
}
struct Atlas {
	@binding(0) atlas: Texture2d;
	@binding(0) atlasSampler: Sampler;
}
function nudgedFs(input: Pixel, b: Atlas): Vec4f {
	let shift = vec2i(1, 0);
	return textureSample(b.atlas, b.atlasSampler, vec2f(0.5, 0.5), shift);
}
console.log(glsl(nudgedFs));
