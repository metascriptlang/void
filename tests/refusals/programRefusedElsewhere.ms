// expect: 14:15 shaderProgram 'scaledProgram': on glsl300es: printGlsl: Ldexp is not in GLSL ES 3.00
import { shaderProgram } from "../../src/shader/program";
import { Vec4f, builtin, ldexp } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
function scaledVs(input: In): Out { return { position: input.position }; }
function scaledFs(input: Out): Vec4f {
	return { x: ldexp(input.position.x, 2), y: 0.0, z: 0.0, w: 1.0 };
}
shaderProgram(scaledProgram, scaledVs, scaledFs);
