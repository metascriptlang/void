// expect: 14:25 writeUniform<Tint>: the buffer is a name or a field path, bound before the call
import { writeUniform } from "../../src/shader/uniform";
import { Vec4f } from "../../src/shader/std";

struct Tint {
	color: Vec4f;
}

function pool(): Vec<float32> {
	return [0, 0, 0, 0];
}

function run(tint: Tint): void {
	writeUniform<Tint>(pool(), 0, tint);
}
