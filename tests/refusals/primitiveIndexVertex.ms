// expect: 6:2 input field 'primitive': @builtin(primitiveIndex) is read in a fragment entry, as WGSL's is
import { glsl } from "../../src/shader/emit";
import { Vec2f, Vec4f, builtin, vec4f } from "../../src/shader/std";
struct Corner {
	position: Vec2f;
	@builtin(primitiveIndex) primitive: uint32;
}
struct Placed {
	@builtin(position) clip: Vec4f;
}
function facetVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}
console.log(glsl(facetVs));
