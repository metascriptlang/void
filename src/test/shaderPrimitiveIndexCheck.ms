// @builtin(primitiveIndex) authored in MetaScript: the entry runs on the CPU, is pinned as GLSL
// and printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh, naga and spirv-val. A shaderModule prints it for the build's target.

import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { Builtin, ShaderModule, irErrors, scalarType, ScalarKind } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { shaderModule } from "../shader/program";
import { printedProbe, printedSpirv } from "./shaderProbePrint";
import { Vec2f, Vec4f, builtin, vec4f } from "../shader/std";

export struct Facet {
	@builtin(position) position: Vec4f;
	@builtin(primitiveIndex) primitive: uint32;
}

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
}

export function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function facetFs(input: Facet): Vec4f {
	return vec4f((input.primitive as float32) * 0.25, 0.0, 0.0, 1.0);
}

test "a fragment entry reads @builtin(primitiveIndex) as a uint32" {
	assert facetFs({ position: vec4f(0.0, 0.0, 0.0, 1.0), primitive: 2 }).x == 0.5;
	assert glsl(facetFs) ==
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    fragColor = vec4((float(uint(gl_PrimitiveID)) * 0.25), 0.0, 0.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

function facetOf(): ShaderModule {
	const m = programModule(glslIr(plainVs), glslIr(facetFs), []);
	if (!m.ok) { throw new Error("facetOf: " + m.error); }
	return m.value;
}

test "every target reads the primitive index" {
	const m = facetOf();
	assert irErrors(m).length == 0;
	const wgsl = printedProbe(m, 1, ShaderTarget.Wgsl, "facet", "frag");
	assert wgsl.startsWith("enable primitive_index;\n") &&
		wgsl.includes("@builtin(primitive_index) primitive_param : u32");
	assert printedProbe(m, 1, ShaderTarget.Hlsl5, "facet", "frag").includes("uint primitive : SV_PrimitiveID;\n");
	assert printedProbe(m, 1, ShaderTarget.Glsl430, "facet", "frag").includes("uint(gl_PrimitiveID)");
	assert printedProbe(m, 1, ShaderTarget.Msl, "facet", "frag").includes("uint primitive [[primitive_id]]");
	assert printedSpirv(m, 1, "facet") == "";
}

test "GLSL ES 3.00 has no primitive index" {
	const refused = stageSource(facetOf(), 1, ShaderTarget.Glsl300es);
	assert !refused.ok && refused.error.endsWith("PrimitiveIndex: GLSL ES 3.00 has no gl_PrimitiveID");
}

test "the primitive index is a u32 as WGSL's" {
	let m = facetOf();
	const at = m.ios.findIndex((io) => io.builtin == Builtin.PrimitiveIndex);
	m.ios[at].type = scalarType(ScalarKind.F32);
	const refused = stageSource(m, 1, ShaderTarget.Wgsl);
	assert !refused.ok && refused.error.endsWith("is f32; @builtin(primitive_index) is u32");
}

shaderModule(facet, plainVs, facetFs);

test "shaderModule prints the primitive index for the build's target" {
	assert facetModule.fragmentCode.length > 0 && !facetModule.fragmentCode.includes("null");
}
