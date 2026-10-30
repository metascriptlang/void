// expect: 5:2 @interpolate sits on a varying, not a vertex attribute, as WGSL's
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, interpolate } from "../../src/shader/std";
struct A {
	@interpolate(linear) position: Vec4f;
}
struct V {
	@builtin(position) clip: Vec4f;
}
function attributeVs(input: A): V { return { clip: input.position }; }
console.log(glsl(attributeVs));
