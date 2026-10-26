// Hand-built IR modules printed as HLSL SM5: the blur keeps the committed interface, every
// intrinsic and statement kind has a spelling, and each refusal names its case. The printed files
// land in out/hlslProbe/ for scripts/validateHlsl.sh.

import { mkdir, writeFile } from "std/fs";
import {
	AssignOp,
	BinaryOp,
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	SamplerType,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	StmtKind,
	TextureShape,
	arrayType,
	assignOf,
	exprOf,
	featureOn,
	irErrors,
	literal,
	stmtOf,
	structType,
} from "../shader/ir";
import { ShaderTarget, bindingSlots } from "../shader/layout";
import { printHlsl } from "../shader/printHlsl";
import { blurShaderModule } from "../void2d/shader2dModules";
import {
	BOOL,
	F32,
	MAT4,
	U32,
	UVEC3,
	VEC3,
	binary,
	blurModule,
	caseOf,
	computeModule,
	construct,
	depthModule,
	everyModule,
	f32,
	fragmentModule,
	i32,
	io,
	layeredBlurModule,
	local,
	prepend,
	shaderFunction,
	single,
	update,
	vertexModule,
} from "./shaderProbeModules";

function printed(m: ShaderModule, entryIndex: int32, program: int32[]): string {
	const slots = bindingSlots(m, program, ShaderTarget.Hlsl5);
	if (!slots.ok) { return slots.error; }
	const text = printHlsl(m, entryIndex, slots.value);
	if (!text.ok) { return text.error; }
	return text.value;
}

// Each line that binds a register, a packoffset or a semantic, with the declared name left out,
// since the committed names (`gl_Position`, `_13_dir`) are SPIR-V ids.
function interfaceLines(text: string): string[] {
	let out: string[] = [];
	for (const line of text.split("\n")) {
		const bound = line.includes(" : register(") || line.includes(" : packoffset(") ||
			line.includes(" : TEXCOORD") || line.includes(" : SV_");
		if (!bound) { continue; }
		const words = line.trim().split(" ");
		out.push(words.slice(0, words.length - 3).join(" ") + " " +
			words.slice(words.length - 2).join(" "));
	}
	return out;
}

test "blur prints the interface of the committed HLSL" {
	const m = blurModule();
	assert irErrors(m).length == 0;
	const vs = printed(m, 0, [0, 1]);
	const fs = printed(m, 1, [0, 1]);
	assert interfaceLines(fs).join("\n") == [
		"cbuffer : register(b0)",
		"float4 : packoffset(c0);",
		"Texture2D<float4> : register(t0);",
		"SamplerState : register(s0);",
		"float2 : TEXCOORD0;",
		"float4 : SV_Target0;",
	].join("\n");
	assert interfaceLines(vs).join("\n") == [
		"float2 : TEXCOORD0;",
		"float2 : TEXCOORD1;",
		"float2 : TEXCOORD0;",
		"float4 : SV_Position;",
	].join("\n");
	assert fs.includes("cbuffer blur_params : register(b0)\n{\n    float4 _2_dir : packoffset(c0);\n};\n");
	assert fs.includes("fragColor = srcTex.Sample(srcSmp, uv) * _2_dir;\n");
	assert vs.includes("clip_1 = float4(pos, 0.0, 1.0);\n");
	assert !fs.includes("struct BlurParams");
	assert vs.includes("StageOutput main(StageInput stage_input)\n");
	when (windows) {
		const committed = blurShaderModule();
		assert committed.fragmentCode == "" && committed.fragmentBytecode.length > 0;
		assert committed.vertexCode == "" && committed.vertexBytecode.length > 0;
	}
}

test "the vertex probe reads matrices through mul and blocks through packoffset" {
	const m = vertexModule();
	assert irErrors(m).length == 0;
	const text = printed(m, 0, [0]);
	assert text.includes("cbuffer camera : register(b1)\n{\n" +
		"    row_major float4x4 _0_viewProj : packoffset(c0);\n" +
		"    float4 _0_offset : packoffset(c4);\n" +
		"    float3 _0_tint : packoffset(c5);\n" +
		"    float _0_scale : packoffset(c5.w);\n" +
		"    float2 _0_shift : packoffset(c6);\n" +
		"    row_major float3x3 _0_normalMatrix : packoffset(c7);\n" +
		"    float4 _0_lights[2] : packoffset(c10);\n};\n");
	assert text.includes("clip_1 = mul(float4(position, 1.0), _0_viewProj);\n");
	assert text.includes("mul(_0_tint, _0_normalMatrix)");
	assert text.includes("    uint vertexIndex : SV_VertexID;\n    uint instanceIndex : SV_InstanceID;\n");
	assert text.includes("struct StageOutput\n{\n    float4 shade : TEXCOORD0;\n" +
		"    nointerpolation uint id : TEXCOORD1;\n    noperspective centroid float2 uvL : TEXCOORD2;\n" +
		"    float4 clip_1 : SV_Position;\n};\n");
}

test "the fragment probe spells every intrinsic and statement" {
	const m = fragmentModule();
	assert irErrors(m).length == 0;
	const text = printed(m, 0, [0]);
	for (const piece of [
		"static const float weights[3] = { 0.25, 0.5, 0.25 };\n",
		"float3 shade_1(float3 x, float k)\n{\n    return x * k;\n}\n",
		"float arr[3] = { f, f, 2.0 };\n",
		"Sample s = makeSample(f, v2);\n",
		"int2 size = int2(textureSize(albedo, uint(0)));\n",
		"bool3 b3 = v3 <= v3;\n",
		"f = rsqrt(f);\n", "f = mad(f, f, f);\n", "v3 = float3(sign(v3));\n", "v3 = frac(v3);\n",
		"v3 = lerp(v3, v3, f);\n", "v3 = faceforward(v3, v3, v3);\n", "v3 = (b3 ? v3 : v3);\n",
		"f = (b ? 1.0 : f);\n", "m4 = inverse(m4);\n", "m3 = ((float3x3)m4);\n",
		"v2 = ddx(v2);\n", "f = ddy(f);\n", "i = sign(i);\n", "v4 = albedo.Load(int3(i2, 0));\n",
		"v4 = mul(m4, v4);\n", "f = fmod(f, 2.0);\n", "u = u % 4u;\n", "v4.zw = v2;\n",
		"shade_1(v3, f);\n", "static bool demoted = false;\n",
		"if (f < 0.0)\n    {\n        demoted = true;\n    }\n    else\n",
		"if (demoted)\n    {\n        discard;\n    }\n    return;\n}\n",
		"for (int k = 0; k < 3; k++)\n", "f += weights[k];\n",
		"    {\n        int k = 0;\n        int j = 3;\n        for (; k < j; k++, j--)\n",
		"        case 0:\n        case 1:\n        {\n            f += 1.0;\n            break;\n",
		"        default:\n", "b = all(v3 == v3);\n", "b = any(v3 != v3);\n", "i = i / 2;\n",
		"f = s.weight + v3[i];\n", "v2 = s.offset - frag.xy;\n", "v4 = m4[1];\n",
		"v4 = mul(v4 * _0_tint, _0_model);\n", "f = b ? f : 1.0;\n", "f = f + float(u + 2891336453u);\n",
		"    frag.w = 1.0 / frag.w;\n", "    nointerpolation uint id : TEXCOORD1;\n",
		"    float4 frag : SV_Position;\n    bool facing : SV_IsFrontFace;\n",
		"    float4 extra : SV_Target1;\n    float depth : SV_Depth;\n",
	]) {
		if (!text.includes(piece)) { console.log("missing: " + piece); }
		assert text.includes(piece);
	}
}

test "the compute probe pads std430 elements and binds t and u registers" {
	const m = computeModule();
	assert irErrors(m).length == 0;
	const text = printed(m, 0, [0]);
	for (const piece of [
		"struct Particle\n{\n    float3 position;\n    float mass;\n    float2 velocity;\n" +
			"    uint _pad;\n    uint _pad_1;\n};\n",
		"struct Spring\n{\n    float rest;\n    uint _pad;\n    uint _pad_1;\n    uint _pad_2;\n" +
			"    float3 axis;\n    uint _pad_3;\n};\n",
		"RWStructuredBuffer<Particle> particles : register(u0);\n",
		"StructuredBuffer<Spring> springs : register(t0);\n",
		"RWTexture2D<float> heat : register(u1);\n",
		"RWTexture2D<unorm float4> image : register(u2);\n",
		"int2 size = int2(imageSize(image));\n",
		"heat[uint2(int2(local.xy))] = float4(springs[flat].axis, heat[uint2(int2(local.xy))]).x;\n",
		"[numthreads(8, 4, 1)]\nvoid main(StageInput stage_input)\n",
		"    uint3 global : SV_DispatchThreadID;\n    uint3 local : SV_GroupThreadID;\n" +
			"    uint flat : SV_GroupIndex;\n    uint3 group : SV_GroupID;\n",
	]) {
		if (!text.includes(piece)) { console.log("missing: " + piece); }
		assert text.includes(piece);
	}
}

test "depth comparison samples each depth shape and fetches with no sampler" {
	const m = depthModule();
	assert irErrors(m).length == 0;
	const ps = printed(m, 1, [0, 1]);
	const vs = printed(m, 0, [0, 1]);
	for (const piece of [
		"Texture2D<float> shadowMap : register(t0);\n",
		"Texture2DArray<float> shadowLayers : register(t1);\n",
		"TextureCube<float> shadowCube : register(t2);\n",
		"SamplerComparisonState shadowSmp : register(s0);\n",
		"shadowMap.SampleCmp(shadowSmp, uv, 0.5)",
		"shadowLayers.SampleCmp(shadowSmp, float3(uv, float(1)), 0.5)",
		"shadowCube.SampleCmp(shadowSmp, float3(uv, 1.0), 0.5)",
		"shadowMap.SampleCmpLevelZero(shadowSmp, uv, 0.5)",
		"shadowLayers.SampleCmpLevelZero(shadowSmp, float3(uv, float(1)), 0.5)",
		"shadowCube.SampleCmpLevelZero(shadowSmp, float3(uv, 1.0), 0.5)",
		"shadowMap.Load(int3(((int2)1), 0))",
		"lut.Load(int3(((int2)1), 0))",
	]) {
		if (!ps.includes(piece)) { console.log("missing: " + piece + "\n" + ps); }
		assert ps.includes(piece);
	}
	for (const piece of [
		"SamplerComparisonState heightSmp : register(s1);\n",
		"heightMap.SampleCmpLevelZero(heightSmp, ((float2)0.5), 0.5)",
	]) {
		if (!vs.includes(piece)) { console.log("missing: " + piece + "\n" + vs); }
		assert vs.includes(piece);
	}
}

function refusal(m: ShaderModule, entryIndex: int32): string {
	const slots = bindingSlots(m, [entryIndex], ShaderTarget.Hlsl5);
	const text = printHlsl(m, entryIndex, slots.ok ? slots.value : []);
	return text.ok ? "printed" : text.error;
}

test "what HLSL cannot carry is refused by name" {
	let feature = fragmentModule();
	feature.features = ["CUTOUT"];
	let branch = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), [single(StmtKind.Discard)]);
	branch.condition = featureOn("CUTOUT");
	prepend(feature.functions[0], branch);
	assert refusal(feature, 0) == "printHlsl: a feature branch is still undecided: specialize " +
		"the module first";

	let signed = fragmentModule();
	prepend(signed.functions[0], update(local(7), AssignOp.Mod, i32(2.0)));
	assert refusal(signed, 0) ==
		"printHlsl: '%' of I32: HLSL leaves a negative operand undefined";

	let groups = computeModule();
	groups.ios.push(io("groups", ShaderStage.Compute, IoDirection.In, UVEC3,
		Builtin.NumWorkgroups));
	assert refusal(groups, 0) == "printHlsl: NumWorkgroups has no HLSL system value";

	let leaving = fragmentModule();
	let choose = stmtOf(StmtKind.Switch, local(7), []);
	choose.cases = [caseOf([], true, [single(StmtKind.Break)])];
	prepend(leaving.functions[0], choose);
	assert refusal(leaving, 0) == "printHlsl: a break inside a switch case, which HLSL reads " +
		"as leaving the switch";

	let diagonal = fragmentModule();
	prepend(diagonal.functions[0], assignOf(local(6), construct(MAT4, [f32(1.0)])));
	assert refusal(diagonal, 0) == "printHlsl: a matrix built from one scalar";

	let effect = computeModule();
	let writer = shaderFunction("bump", [], [
		assignOf(exprOf(ExprKind.Field, F32, 1, [exprOf(ExprKind.Index, structType(0), -1,
			[exprOf(ExprKind.Resource, arrayType(structType(0), -1), 0, []), literal(U32, 0.0)])]),
			f32(1.0)),
		stmtOf(StmtKind.Return, literal(BOOL, 1.0), []),
	]);
	writer.result = BOOL;
	effect.functions.push(writer);
	prepend(effect.functions[0], stmtOf(StmtKind.If, binary(BinaryOp.LogicalAnd, BOOL,
		literal(BOOL, 0.0), exprOf(ExprKind.Call, BOOL, 1, [])), []));
	assert refusal(effect, 0) == "printHlsl: '&&' evaluates every operand in HLSL, and one of " +
		"them has an effect";

	let recursive = fragmentModule();
	prepend(recursive.functions[1], stmtOf(StmtKind.Call,
		exprOf(ExprKind.Call, VEC3, 1, [exprOf(ExprKind.Param, VEC3, 0, []),
			exprOf(ExprKind.Param, F32, 1, [])]), []));
	assert refusal(recursive, 0) == "printHlsl: function 'shade' is recursive";
}

test "a depth comparison HLSL cannot spell is refused by name" {
	let vertex = depthModule();
	vertex.functions[0].body[1].expr.operands[2].operands[0].intrinsic =
		Intrinsic.TextureSampleCompare;
	assert refusal(vertex, 0) == "printHlsl: entry 'depthVs': TextureSampleCompare outside a fragment entry";

	let filtering = depthModule();
	filtering.resources[6].samplerType = SamplerType.Filtering;
	assert refusal(filtering, 0) == "printHlsl: TextureSampleCompareLevel through a sampler " +
		"that is no comparison sampler binding";

	let colour = depthModule();
	colour.functions[0].body[1].expr.operands[2].operands[0].operands[0].type.shape =
		TextureShape.D2;
	assert refusal(colour, 0) == "printHlsl: TextureSampleCompareLevel of a D2 texture, which " +
		"holds no depth";
}

const PROBE_DIR = "out/hlslProbe";

function probe(name: string, text: string): boolean {
	const _made = mkdir(PROBE_DIR);
	return writeFile(PROBE_DIR + "/" + name + ".hlsl", text).ok;
}

test "printed modules are written for fxc" {
	const blur = blurModule();
	assert probe("blur.vs", printed(blur, 0, [0, 1]));
	assert probe("blur.ps", printed(blur, 1, [0, 1]));
	assert probe("vertex.vs", printed(vertexModule(), 0, [0]));
	assert probe("fragment.ps", printed(fragmentModule(), 0, [0]));
	assert probe("compute.cs", printed(computeModule(), 0, [0]));
	assert probe("depth.vs", printed(depthModule(), 0, [0, 1]));
	assert probe("depth.ps", printed(depthModule(), 1, [0, 1]));
}

test "an array texture samples with its layer packed into the coordinates" {
	const m = layeredBlurModule();
	assert irErrors(m).length == 0;
	assert printed(m, 1, [0, 1]).includes("srcTex.Sample(srcSmp, float3(uv, float(2)))");
}

test "a plain sample outside a fragment entry reads level 0, as WGSL and MSL do" {
	const m = everyModule();
	assert irErrors(m).length == 0;
	assert printed(m, 0, [0, 1]).includes("heightMap.SampleLevel(heightSampler, position, 0.0)");
}
