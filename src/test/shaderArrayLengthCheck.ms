// The length of a runtime-sized storage array (WGSL's arrayLength, spelled `.length`): the entry
// runs on the CPU, is pinned as GLSL and printed into out/<target>Probe/ for
// scripts/validateWgsl.sh,
// scripts/validateHlsl.sh and spirv-val. MSL is a refusal. A fragment entry reaches it through
// shaderModule.

import { mkdir, writeFile } from "std/fs";
import { computeModule } from "../shader/descriptor";
import { glslCompute, glslComputeIr, glslIr, glslLinkedIr } from "../shader/emit";
import { ResourceKind, ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { shaderModule } from "../shader/program";
import { fragmentText, printedProbe, printedSpirv } from "./shaderProbePrint";
import {
	Vec2f,
	Vec3u,
	Vec4f,
	access,
	binding,
	builtin,
	vec2i,
	vec4f,
} from "../shader/std";

export struct Ids {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct Row {
	value: float32;
}

export struct Rows {
	@binding(0) @access(read_write) rows: Row[];
	@binding(1) seeds: Row[];
}

export function lengthCs(input: Ids, b: Rows): void {
	const at = vec2i(input.id.xy).x;
	if (at < b.seeds.length) {
		b.rows[at].value = b.seeds[at].value + (b.rows.length as float32);
	}
}

test "arrayLength is the element count of the CPU array" {
	const b: Rows = { rows: [{ value: 0.0 }, { value: 0.0 }, { value: 0.0 }],
		seeds: [{ value: 5.0 }, { value: 6.0 }] };
	assert b.seeds.length == 2 && b.rows.length == 3;
	lengthCs({ id: { x: 1, y: 0, z: 0 } }, b);
	lengthCs({ id: { x: 2, y: 0, z: 0 } }, b);
	assert b.rows[1].value == 9.0 && b.rows[2].value == 0.0;
}

export struct Weighted {
	@binding(0) weights: Row[];
}

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
}

export struct Pixel {
	@builtin(position) position: Vec4f;
}

function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

function weightedFs(input: Pixel, b: Weighted): Vec4f {
	const n = b.weights.length;
	return vec4f(b.weights[n - 1].value, n as float32, 0.0, 1.0);
}

shaderModule(weighted, plainVs, weightedFs);

test "shaderModule prints arrayLength while the macro prints the program" {
	const code = fragmentText(weightedModule, glslIr(plainVs), glslLinkedIr(weightedFs, plainVs));
	assert code.length > 0 && !code.includes("null");
}

function computeOf(): ShaderModule {
	const m = computeModule(glslComputeIr(lengthCs, [64, 1, 1]), []);
	if (!m.ok) { throw new Error("computeOf: " + m.error); }
	return m.value;
}

test "GLSL 450 asks the block member for its length" {
	const text = glslCompute(lengthCs, [64, 1, 1]);
	const _out = mkdir("out");
	const _folder = mkdir("out/glslProbe");
	const _written = writeFile("out/glslProbe/rowsLength.450.comp", "#version 450\n" + text);
	assert text ==
		"layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
" +
		"struct Row {
" +
		"    float value;
" +
		"};
" +
		"layout(binding=0) buffer rowsBuffer {
" +
		"    Row rows[];
" +
		"};
" +
		"layout(binding=1) readonly buffer seedsBuffer {
" +
		"    Row seeds[];
" +
		"};
" +
		"void main() {
" +
		"    int at = ivec2(gl_GlobalInvocationID.xy).x;
" +
		"    if (at < seeds.length()) {
" +
		"        rows[at].value = seeds[at].value + float(rows.length());
" +
		"    }
" +
		"}
";
}

test "every target spells the length" {
	const m = computeOf();
	assert irErrors(m).length == 0;
	for (const t of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430]) {
		const text = printedProbe(m, 0, t, "rowsLength", "comp");
		assert text.length > 0 && !text.startsWith("print");
	}
	assert printedSpirv(m, 0, "rowsLength") == "";
}

test "MSL refuses the length until the host fills a sizes buffer" {
	const text = printedProbe(computeOf(), 0, ShaderTarget.Msl, "rowsLength", "comp");
	assert text.startsWith(
		"printMsl: ArrayLength of storage buffer 'seeds': MSL reads no buffer length");
}

test "the length of a buffer that is not a storage buffer is an error of the module" {
	let m = computeOf();
	m.resources[1].kind = ResourceKind.UniformBlock;
	assert irErrors(m).includes("function 'lengthCs': ArrayLength takes one storage buffer, " +
		"as WGSL's takes a runtime-sized array");
}
