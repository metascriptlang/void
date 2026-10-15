// expect: 21:15 'tint' is declared only under @feature(TINT), and this read runs outside it
import { glslLinked } from "../../src/shader/emit";
import { Vec4f, builtin, feature } from "../../src/shader/std";
struct A {
	position: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
	shade: Vec4f;
	@feature(TINT) tint: Vec4f;
}
struct F {
	shade: Vec4f;
	@feature(TINT) tint: Vec4f;
}
struct K { @feature(TINT) tinted: boolean; }
function tintVs(input: A, key: K): V {
	return { clip: input.position, shade: input.position, tint: input.position };
}
function tintFs(input: F, key: K): Vec4f {
	let c = input.tint;
	if (key.tinted) { c = c * input.shade; }
	return c;
}
console.log(glslLinked(tintFs, tintVs));
