// expect: 14:42 'tangent' is declared only under @feature(NORMAL_MAP), and this call reads it outside it
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, feature } from "../../src/shader/std";
struct A {
	position: Vec4f;
	@feature(NORMAL_MAP) tangent: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
}
struct K { @feature(NORMAL_MAP) normalMap: boolean; @feature(SKIN) skin: boolean; }
function tangentOf(input: A): Vec4f { return input.tangent; }
function helperVs(input: A, key: K): V {
	if (key.skin) { return { clip: tangentOf(input) }; }
	return { clip: input.position };
}
console.log(glsl(helperVs));
