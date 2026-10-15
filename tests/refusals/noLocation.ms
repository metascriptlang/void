// expect: 12:1 fragment output 'second' has no @location(n)
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, location } from "../../src/shader/std";
struct In {
	@builtin(position) position: Vec4f;
}
struct Out {
	@location(0) first: Vec4f;
	second: Vec4f;
}

function outFs(input: In): Out {
	return { first: input.position, second: input.position };
}
console.log(glsl(outFs));
