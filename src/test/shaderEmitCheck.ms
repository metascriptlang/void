// The GLSL the glsl macro emits for each statement and expression form, and the same probe run on
// the CPU, so the text and the oracle are held by one function.

import { glsl } from "../shader/emit";
import { Vec4f, builtin } from "../shader/std";

struct ProbeInput {
	@builtin(position) position: Vec4f;
}

function at(x: float32, y: float32): ProbeInput {
	return { position: { x, y, z: 0.5, w: 1.0 } };
}

function branchFs(input: ProbeInput): float32 {
	const x = input.position.x;
	const inside = x >= 0.0 && x < 2.0;
	if (!inside || false) {
		return -x;
	} else if (x <= 1.0) {
		return 1.0;
	} else {
		return x;
	}
}

function loopFs(input: ProbeInput): float32 {
	let sum: float32 = 0.0;
	for (let i = 0; i < 8; i++) {
		if (i == 1) {
			continue;
		}
		if (i == 5) {
			break;
		}
		sum += input.position.x;
	}
	let scale: float32 = 1.0;
	while (scale < sum) {
		scale *= 2.0;
	}
	scale -= 0.5;
	scale /= 2.0;
	sum = sum + scale;
	return sum;
}

function convertFs(input: ProbeInput): float32 {
	const weights: float32[3] = [0.25, 0.5, 1.0];
	const column = input.position.x as int32;
	const nearest = column > 2 ? 2 : column;
	const lower: float32 = input.position.y > 1.0 ? 1.0 : 0.0;
	return weights[nearest] * (nearest as float32) + lower;
}

test "if, else if and else return the colour from every branch" {
	assert glsl(branchFs) == "layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    float x = gl_FragCoord.x;\n" +
		"    bool inside = (x >= 0.0) && (x < 2.0);\n" +
		"    if ((!inside) || false) {\n" +
		"        fragColor = -x;\n" +
		"        return;\n" +
		"    } else if (x <= 1.0) {\n" +
		"        fragColor = 1.0;\n" +
		"        return;\n" +
		"    } else {\n" +
		"        fragColor = x;\n" +
		"        return;\n" +
		"    }\n" +
		"}\n";
	assert branchFs(at(-0.5, 0.0)) == 0.5 && branchFs(at(3.0, 0.0)) == -3.0;
	assert branchFs(at(0.5, 0.0)) == 1.0 && branchFs(at(1.5, 0.0)) == 1.5;
}

test "for, while, break, continue and assignment to locals" {
	assert glsl(loopFs) == "layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    float sum = 0.0;\n" +
		"    for (int i = 0; i < 8; i++) {\n" +
		"        if (i == 1) {\n" +
		"            continue;\n" +
		"        }\n" +
		"        if (i == 5) {\n" +
		"            break;\n" +
		"        }\n" +
		"        sum += gl_FragCoord.x;\n" +
		"    }\n" +
		"    float scale = 1.0;\n" +
		"    while (scale < sum) {\n" +
		"        scale *= 2.0;\n" +
		"    }\n" +
		"    scale -= 0.5;\n" +
		"    scale /= 2.0;\n" +
		"    sum = sum + scale;\n" +
		"    fragColor = sum;\n" +
		"    return;\n" +
		"}\n";
	assert loopFs(at(1.5, 0.0)) == 9.75 && loopFs(at(0.25, 0.0)) == 1.25;
}

test "conversions, the conditional and an index into a local array" {
	assert glsl(convertFs) == "layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    float[3] weights = float[3](0.25, 0.5, 1.0);\n" +
		"    int column = int(gl_FragCoord.x);\n" +
		"    int nearest = (column > 2) ? 2 : column;\n" +
		"    float lower = (gl_FragCoord.y > 1.0) ? 1.0 : 0.0;\n" +
		"    fragColor = (weights[nearest] * float(nearest)) + lower;\n" +
		"    return;\n" +
		"}\n";
	assert convertFs(at(0.5, 0.5)) == 0.0 && convertFs(at(1.5, 1.5)) == 1.5;
	assert convertFs(at(7.5, 0.5)) == 2.0;
}
