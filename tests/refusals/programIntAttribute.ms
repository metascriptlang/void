// expect: 13:23 shaderProgram: an int32 or integer vector vertex attribute has no door vertex format
import { shaderProgram } from "../../src/shader/program";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct In {
	position: Vec4f;
	tag: int32;
}
struct Out {
	@builtin(position) position: Vec4f;
}
function intVs(input: In): Out { return { position: input.position }; }
function intFs(): Vec4f { return vec4f(1.0, 1.0, 1.0, 1.0); }
shaderProgram(tagged, intVs, intFs);
