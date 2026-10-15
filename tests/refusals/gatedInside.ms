// expect: ok
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, feature } from "../../src/shader/std";
struct A {
	position: Vec4f;
	@feature(NORMAL_MAP) tangent: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
	@feature(NORMAL_MAP) bent: Vec4f;
}
struct K { @feature(NORMAL_MAP) normalMap: boolean; @feature(SKIN) skin: boolean; }
function tangentOf(input: A): Vec4f { return input.tangent; }
function shifted(input: A): Vec4f { return tangentOf(input) + input.position; }
function insideVs(input: A, key: K): V {
	if (key.skin && key.normalMap) { return { clip: shifted(input), bent: input.tangent }; }
	if ((key.skin || !key.skin) && key.normalMap) { return { clip: tangentOf(input), bent: input.tangent }; }
	if (key.normalMap) {
		if (key.skin) { return { clip: input.tangent, bent: input.tangent }; }
	}
	return { clip: input.position, bent: input.tangent };
}
console.log(glsl(insideVs));
