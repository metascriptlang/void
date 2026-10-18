// expect: 18:15 shaderProgram 'farProgram': sokol-shdc exited 10
import { shaderProgram } from "../../src/shader/program";
import { Vec4f, binding, builtin } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct Far {
	tint: Vec4f;
}
struct FarBindings {
	@binding(9) far: Far;
}
function farVs(input: In): Out { return { position: input.position }; }
function farFs(b: FarBindings): Vec4f { return b.far.tint; }
shaderProgram(farProgram, farVs, farFs);
