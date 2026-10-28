// expect: 14:32 writeUniform<Tint>: the value is not a Tint
import { writeUniform } from "../../src/shader/uniform";
import { Vec4f } from "../../src/shader/std";

struct Tint {
	color: Vec4f;
}

struct Glow {
	color: Vec4f;
}

function run(values: Vec<float32>, glow: Glow): void {
	writeUniform<Tint>(values, 0, glow);
}
