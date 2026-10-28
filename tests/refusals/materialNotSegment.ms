// expect: 18:1 segment 'brighten': its first parameter 'c' is the phase struct it reads and returns, and Vec4f is no author struct
import { materialProgram } from "../../src/shader/program";
import { Vec4f, builtin, hook, vec4f } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct Shaded {
	color: Vec4f;
}
function plainVs(input: In): Out { return { position: input.position }; }
function shadedFs(): Vec4f {
	const lit: Shaded = { color: vec4f(1.0, 0.5, 0.25, 1.0) };
	return hook(lit).color;
}
function brighten(c: Vec4f): Vec4f { return c * c; }
materialProgram(bright, plainVs, shadedFs, [brighten]);
