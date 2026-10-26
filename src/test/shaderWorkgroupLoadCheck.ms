// workgroupUniformLoad(v): the entry runs on the CPU, is pinned as GLSL and printed into
// out/<target>Probe/ for scripts/validateWgsl.sh, scripts/validateHlsl.sh, naga and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { computeModule } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import { ShaderModule, StmtKind, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { printedProbe, printedSpirv } from "./shaderProbePrint";
import {
	Vec3u,
	access,
	binding,
	builtin,
	workgroupBarrier,
	workgroupUniformLoad,
} from "../shader/std";

export struct Ids {
	@builtin(globalInvocationId) id: Vec3u;
	@builtin(localInvocationIndex) local: uint32;
}

export struct Slot {
	value: float32;
}

export struct Slots {
	@binding(0) @access(read_write) slots: Slot[];
}

let flag: uint32;
let gain: float32;

export function loadCs(input: Ids, b: Slots): void {
	if (input.local == 0) {
		flag = 3;
		gain = 2.5;
	}
	workgroupBarrier();
	const n = workgroupUniformLoad(flag);
	const g = workgroupUniformLoad(gain);
	if (n > 2) {
		workgroupBarrier();
	}
	b.slots[input.id.x].value = g * (n as float32);
}

test "the uniform load is the read of workgroup memory on the CPU" {
	const b: Slots = { slots: [{ value: 0.0 }] };
	loadCs({ id: { x: 0, y: 0, z: 0 }, local: 0 }, b);
	assert b.slots[0].value == 7.5;
}

function computeOf(): ShaderModule {
	const m = computeModule(glslComputeIr(loadCs, [64, 1, 1]), []);
	if (!m.ok) { throw new Error("computeOf: " + m.error); }
	return m.value;
}

test "GLSL 450 brackets the load with two barriers" {
	const text = glslCompute(loadCs, [64, 1, 1]);
	const _out = mkdir("out");
	const _folder = mkdir("out/glslProbe");
	const _written = writeFile("out/glslProbe/uniformLoad.450.comp", "#version 450\n" + text);
	assert text ==
		"layout(local_size_x=64, local_size_y=1, local_size_z=1) in;\n" +
		"struct Slot {\n" +
		"    float value;\n" +
		"};\n" +
		"layout(binding=0) buffer slotsBuffer {\n" +
		"    Slot slots[];\n" +
		"};\n" +
		"shared uint flag;\n" +
		"shared float gain;\n" +
		"void main() {\n" +
		"    if (gl_LocalInvocationIndex == 0) {\n" +
		"        flag = 0;\n" +
		"        gain = 0.0;\n" +
		"    }\n" +
		"    barrier();\n" +
		"    if (gl_LocalInvocationIndex == 0) {\n" +
		"        flag = 3;\n" +
		"        gain = 2.5;\n" +
		"    }\n" +
		"    barrier();\n" +
		"    barrier();\n" +
		"    uint n = flag;\n" +
		"    barrier();\n" +
		"    barrier();\n" +
		"    float g = gain;\n" +
		"    barrier();\n" +
		"    if (n > 2) {\n" +
		"        barrier();\n" +
		"    }\n" +
		"    slots[gl_GlobalInvocationID.x].value = g * float(n);\n" +
		"}\n";
}

test "a uniform load outside a const or let of its own is an error of the module" {
	let m = computeOf();
	const entry = m.entries[0].functionIndex;
	const at = m.functions[entry].body.findIndex((s) => s.kind == StmtKind.Let);
	m.functions[entry].body[at].kind = StmtKind.Call;
	assert irErrors(m).includes("function 'loadCs': a WorkgroupUniformLoad is the initializer of a " +
		"const or let of its own, because the barriers around it sit between two statements");
}

test "every target spells the load" {
	const m = computeOf();
	assert irErrors(m).length == 0;
	for (const t of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430, ShaderTarget.Msl]) {
		const text = printedProbe(m, 0, t, "uniformLoad", "comp");
		assert text.length > 0 && !text.startsWith("print");
	}
	assert printedSpirv(m, 0, "uniformLoad") == "";
}
