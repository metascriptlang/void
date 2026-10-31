// expect: 18:15 shaderProgram 'wideProgram': the fragment stage reads 225 uniform vec4s; GLSL ES 3.0 guarantees 224
import { shaderProgram } from "../../../src/shader/program";
import { Vec4f, binding, builtin } from "../../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct Wide {
	items: Vec4f[225];
}
struct WideBindings {
	@binding(0) wide: Wide;
}
function wideVs(input: In): Out { return { position: input.position }; }
function wideFs(b: WideBindings): Vec4f { return b.wide.items[0]; }
shaderProgram(wideProgram, wideVs, wideFs);
