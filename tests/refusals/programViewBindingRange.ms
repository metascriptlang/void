// expect: 18:15 shaderProgram 'farViewProgram': resource 'far': @binding(15) is outside 0..14
import { shaderProgram } from "../../src/shader/program";
import { Texture2d, Vec2i, Vec4f, binding, builtin, textureLoad } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct FarBindings {
	@binding(15) far: Texture2d;
}
function farVs(input: In): Out { return { position: input.position }; }
function farFs(b: FarBindings): Vec4f {
	const at: Vec2i = { x: 0, y: 0 };
	return textureLoad(b.far, at, 0);
}
shaderProgram(farViewProgram, farVs, farFs);
