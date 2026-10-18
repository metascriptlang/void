// expect: 6:2 shaderProgram builds one program, so 'tangent' cannot be @feature
import { shaderProgram } from "../../src/shader/program";
import { Vec4f, builtin, feature, vec4f } from "../../src/shader/std";
struct In {
	position: Vec4f;
	@feature(NORMAL_MAP) tangent: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
function featureVs(input: In): Out { return { position: input.position }; }
function featureFs(): Vec4f { return vec4f(1.0, 1.0, 1.0, 1.0); }
shaderProgram(featured, featureVs, featureFs);
