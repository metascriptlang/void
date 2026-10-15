// expect: 13:55 'tangent' is declared only under @feature(NORMAL_MAP), and this read runs outside it
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
function orVs(input: A, key: K): V {
	if (key.skin || key.normalMap) { return { clip: input.tangent }; }
	return { clip: input.position };
}
console.log(glsl(orVs));
