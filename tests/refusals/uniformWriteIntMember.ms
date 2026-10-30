// expect: 9:23 writeUniform<Counted>: uniform block 'Counted': member 'count'
import { writeUniform } from "../../src/shader/uniform";

struct Counted {
	count: int32;
}

function run(values: Vec<float32>, counted: Counted): void {
	writeUniform<Counted>(values, 0, counted);
}
