// expect: 16:15 shaderProgram 'farSamplerProgram': resource 'far': @binding(8) is outside 0..7
import { shaderProgram } from "../../src/shader/program";
import { Sampler, Texture2d, Vec4f, binding, builtin, textureSample, vec2f } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct FarBindings {
	@binding(0) near: Texture2d;
	@binding(8) far: Sampler;
}
function farVs(input: In): Out { return { position: input.position }; }
function farFs(b: FarBindings): Vec4f { return textureSample(b.near, b.far, vec2f(0.5, 0.5)); }
shaderProgram(farSamplerProgram, farVs, farFs);
