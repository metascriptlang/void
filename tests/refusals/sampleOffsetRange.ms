// expect: 12:22 textureSample takes a constant offset in [-8, 7], as WGSL's, not 8
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
	return textureSample(b.atlas, b.atlasSampler, vec2f(0.5, 0.5), vec2i(8, 0));
}
console.log(glsl(nudgedFs));
