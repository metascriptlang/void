// expect: 14:36 writeUniform<Tint>: the value is a name or a field path, bound before the call
import { writeUniform } from "../../src/shader/uniform";
import { Vec4f } from "../../src/shader/std";

struct Tint {
	color: Vec4f;
}

function made(): Tint {
	return { color: { x: 1, y: 2, z: 3, w: 4 } };
}

function run(values: Vec<float32>): void {
	writeUniform<Tint>(values, 0, made());
}
