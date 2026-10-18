// expect: 13:24 the fragment input does not declare varying 'uv' of the vertex output
import { glslLinked } from "../../src/shader/emit";
import { Vec2f, Vec4f, builtin, vec2f, vec4f } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
	uv: Vec2f;
}
function unreadVs(input: In): Out { return { position: input.position, uv: vec2f(0.0, 0.0) }; }
function unreadFs(): Vec4f { return vec4f(1.0, 1.0, 1.0, 1.0); }
console.log(glslLinked(unreadFs, unreadVs));
