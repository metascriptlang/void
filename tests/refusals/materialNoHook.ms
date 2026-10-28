// expect: 22:17 materialProgram 'biased': link: effect 'depthBias' works on phase 'Depth', which the base has no hook site for
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
struct Depth {
	z: float32;
}
function plainVs(input: In): Out { return { position: input.position }; }
function shadedFs(): Vec4f {
	const lit: Shaded = { color: vec4f(1.0, 0.5, 0.25, 1.0) };
	return hook(lit).color;
}
function depthBias(depth: Depth): Depth { return { z: depth.z + 0.5 }; }
materialProgram(biased, plainVs, shadedFs, [depthBias]);
