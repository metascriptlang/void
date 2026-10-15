// expect: 12:29 a matrix's columns are read one at a time, as m.columns[i]
import { glsl } from "../../src/shader/emit";
import { Vec3f, Vec4f, builtin, mat3x3f, vec4f } from "../../src/shader/std";

export struct Pixel {
	@builtin(position) position: Vec4f;
}

export function columnsFs(input: Pixel): Vec4f {
	const p = input.position;
	const frame = mat3x3f(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, p.x, p.y, 1.0);
	const all: Vec3f[3] = frame.columns;
	return vec4f(all[0], 1.0);
}

console.log(glsl(columnsFs));
