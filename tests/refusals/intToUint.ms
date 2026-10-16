// expect: 11:19 'as' converts float32 and int32 both ways, uint32 to float32 and a non-negative literal to uint32
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin } from "../../src/shader/std";

export struct Pixel {
	@builtin(position) position: Vec4f;
}

export function bitsFs(input: Pixel): float32 {
	const column = input.position.x as int32;
	const n = column as uint32;
	return n as float32;
}

console.log(glsl(bitsFs));
