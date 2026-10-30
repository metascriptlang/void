// expect: 13:23 shaderProgram: an int32 or uint32 vertex attribute has no GPUVertexFormat
import { shaderProgram } from "../../src/shader/program";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct In {
	position: Vec4f;
	tag: uint32;
}
struct Out {
	@builtin(position) position: Vec4f;
}
function intVs(input: In): Out { return { position: input.position }; }
function intFs(): Vec4f { return vec4f(1.0, 1.0, 1.0, 1.0); }
shaderProgram(tagged, intVs, intFs);
