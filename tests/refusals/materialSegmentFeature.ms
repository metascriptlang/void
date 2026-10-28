// expect: 14:2 materialProgram builds one program, so 'glow' cannot be @feature; a program family is a row of src/void3d/programKeys.txt
import { materialProgram } from "../../src/shader/program";
import { Vec4f, builtin, feature, hook, vec4f } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct Shaded {
	color: Vec4f;
}
struct GlowKey {
	@feature(GLOW) glow: boolean;
}
function plainVs(input: In): Out { return { position: input.position }; }
function shadedFs(): Vec4f {
	const lit: Shaded = { color: vec4f(1.0, 0.5, 0.25, 1.0) };
	return hook(lit).color;
}
function glowing(shaded: Shaded, key: GlowKey): Shaded {
	if (key.glow) { return { color: shaded.color * 2.0 }; }
	return shaded;
}
materialProgram(glowed, plainVs, shadedFs, [glowing]);
