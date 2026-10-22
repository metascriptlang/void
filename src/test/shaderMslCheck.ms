// Hand-built IR modules print as MSL, one module per entry. Each printed module is written to
// out/mslProbe/ for `xcrun metal -c` on a Mac; no Metal compiler runs on the other hosts.

import { mkdir, writeFile } from "std/fs";
import {
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	ResourceKind,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	StmtKind,
	TextureShape,
	assignOf,
	exprOf,
	featureOn,
	intrinsicOf,
	irErrors,
	literal,
	matrixType,
	samplerType,
	stmtOf,
	structType,
} from "../shader/ir";
import { BindingSlot, ShaderTarget, bindingSlots } from "../shader/layout";
import { printMsl } from "../shader/printMsl";
import { specialize } from "../shader/specialize";
import {
	F32,
	I32,
	MAT4,
	VEC2,
	VEC3,
	VEC4,
	block,
	blurModule,
	column,
	comparisonSampler,
	computeModule,
	depthCompare,
	depthModule,
	depthTexture,
	everyModule,
	field,
	io,
	ioOf,
	memberOf,
	model,
	resource,
	shaderFunction,
	tiny,
} from "./shaderIrModules";

function slotsOf(m: ShaderModule, entries: int32[]): BindingSlot[] {
	const slots = bindingSlots(m, entries, ShaderTarget.Msl);
	if (!slots.ok) { return []; }
	return slots.value;
}

function writeProbe(name: string, text: string): boolean {
	const _out = mkdir("out");
	const _probe = mkdir("out/mslProbe");
	return writeFile("out/mslProbe/" + name + ".metal", text).ok;
}

function mslOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printMsl(m, index, slots);
	if (printed.ok) { return printed.value; }
	return printed.error;
}

function refusalOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printMsl(m, index, slots);
	if (printed.ok) { return "printed"; }
	return printed.error;
}

function refused(m: ShaderModule): string { return refusalOf(m, 0, slotsOf(m, [0])); }

// The interface of the metal_macos blurShaderModule committed in src/void2d/shader2dModules.ms.
const COMMITTED_BLUR_VS = "struct main0_out\n{\n    float2 uv [[user(locn0)]];\n" +
	"    float4 gl_Position [[position]];\n};\n\nstruct main0_in\n{\n" +
	"    float2 pos [[attribute(0)]];\n    float2 uv0 [[attribute(1)]];\n};\n\n" +
	"vertex main0_out main0(main0_in in [[stage_in]])\n";
const COMMITTED_BLUR_FS = "struct main0_out\n{\n    float4 fragColor [[color(0)]];\n};\n\n" +
	"struct main0_in\n{\n    float2 uv [[user(locn0)]];\n};\n\n" +
	"fragment main0_out main0(main0_in in [[stage_in]], constant blur_params& _13 [[buffer(0)]], " +
	"texture2d<float> srcTex [[texture(0)]], sampler srcSmp [[sampler(0)]])\n";

function sorted(items: string[]): string[] {
	let out = items.map((s) => s);
	out.sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
	return out;
}

function withoutName(item: string): string {
	const at = item.indexOf(" [[");
	let words = item.substring(0, at).trim().split(" ");
	words.pop();
	if (words[0] == "constant") { words = ["constant"]; }
	return words.join(" ") + item.substring(at);
}

function interfaceOf(text: string): string {
	let facts: string[] = [];
	let members: string[] = [];
	const lines = text.split("\n");
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (line.startsWith("struct main0_in") || line.startsWith("struct main0_out")) {
			const side = line.startsWith("struct main0_in") ? "in " : "out ";
			for (let k = i + 1; k < lines.length && lines[k] != "};"; k++) {
				const member = lines[k].trim();
				if (member != "{" && !member.endsWith("{")) {
					members.push(side + withoutName(member.substring(0, member.length - 1)));
				}
			}
		}
		const open = line.indexOf(" main0(");
		if (open > 0) {
			facts.push(line.substring(0, open + 6));
			const inside = line.substring(open + 7, line.lastIndexOf(")"));
			const params = inside.split("]], ").map((x) => x.endsWith("]]") ? x : x + "]]");
			facts.push(sorted(params.map((x) => withoutName(x))).join(", "));
		}
	}
	return sorted(members).concat(facts).join("\n");
}

test "blur prints the bindings, stage_in attributes and entry of the committed MSL" {
	const m = blurModule();
	const slots = slotsOf(m, [0, 1]);
	const vs = mslOf(m, 0, slots);
	const fs = mslOf(m, 1, slots);
	assert writeProbe("blurVs", vs);
	assert writeProbe("blurFs", fs);
	assert interfaceOf(vs) == interfaceOf(COMMITTED_BLUR_VS);
	assert interfaceOf(fs) == interfaceOf(COMMITTED_BLUR_FS);
	assert interfaceOf(fs) == [
		"in float2 [[user(locn0)]]",
		"out float4 [[color(0)]]",
		"fragment main0_out main0",
		"constant [[buffer(0)]], main0_in [[stage_in]], sampler [[sampler(0)]], " +
			"texture2d<float> [[texture(0)]]",
	].join("\n");
	assert vs.startsWith("#include <metal_stdlib>\n\nusing namespace metal;\n\n");
	assert vs.includes("vertex main0_out main0(main0_in in [[stage_in]]) {\n" +
		"  main0_out out = {};\n  blurVs(in, out);\n  return out;\n}\n");
	assert vs.includes("  out.clip = float4(in.pos, 0.0, 1.0);\n");
	assert fs.includes("static inline void blurFs(thread main0_in& in, thread main0_out& out, " +
		"texture2d<float> srcTex, sampler srcSmp, constant BlurParams& blur_params) {\n" +
		"  out.fragColor = (srcTex.sample(srcSmp, in.uv) * blur_params.dir);\n");
	assert fs.includes("  blurFs(in, out, srcTex, srcSmp, blur_params);\n");
}

test "compute prints storage resources, builtins and no workgroup size" {
	const m = computeModule();
	assert irErrors(m).length == 0;
	const cs = mslOf(m, 0, slotsOf(m, [0]));
	assert writeProbe("total", cs);
	assert cs.includes("kernel void main0(uint3 id [[thread_position_in_grid]], uint3 local " +
		"[[thread_position_in_threadgroup]], uint index [[thread_index_in_threadgroup]], uint3 group " +
		"[[threadgroup_position_in_grid]], uint3 groups [[threadgroups_per_grid]], " +
		"const device Command* commands [[buffer(8)]], device Total* results [[buffer(9)]], " +
		"texture2d<float, access::write> image [[texture(0)]], texture2d<float> lut [[texture(1)]], " +
		"sampler lutSmp [[sampler(0)]]) {\n" +
		"  total(id, local, index, group, groups, commands, results, image, lut, lutSmp);\n}\n");
	assert cs.includes("struct Command {\n  float value;\n};\n");
	assert cs.includes("  image.write((lut.read(uint2(int2(local.xy)), uint(0)) * " +
		"commands[id.x].value), uint2(int2(local.xy)));\n");
	assert cs.includes("  results[(group.x + (index + groups.y))].sum = ");
	assert !cs.includes("32");
}

test "every intrinsic and statement prints" {
	const m = everyModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	const vs = mslOf(m, 0, slots);
	const fs = mslOf(m, 1, slots);
	assert writeProbe("everyVs", vs);
	assert writeProbe("everyFs", fs);
	assert vs.includes("vertex main0_out main0(main0_in in [[stage_in]], uint vertexIndex " +
		"[[vertex_id]], uint instance [[instance_id]], texture2d<float> heightMap [[texture(0)]], " +
		"sampler heightSampler [[sampler(1)]]) {\n");
	assert vs.includes("heightMap.sample(heightSampler, in.position, level(0.0)).x");
	assert vs.includes("struct main0_out {\n  float4 clip [[position]];\n" +
		"  float2 uv [[user(locn0)]];\n  float4 tint [[user(locn1)]];\n  uint id [[user(locn2)]];\n};\n");
	assert vs.includes("static inline void everyVs(thread main0_in& in, thread main0_out& out, " +
		"thread uint& vertexIndex, thread uint& instance, texture2d<float> heightMap, " +
		"sampler heightSampler) {\n");
	assert fs.includes("struct main0_in {\n  float2 uv [[user(locn0), sample_perspective]];\n" +
		"  float4 tint [[user(locn1), centroid_no_perspective]];\n" +
		"  uint id [[user(locn2), flat]];\n};\n");
	assert fs.includes("struct main0_out {\n  float4 colour [[color(0)]];\n" +
		"  float4 extra [[color(1)]];\n  float depth [[depth(any)]];\n};\n");
	assert fs.includes("fragment main0_out main0(main0_in in [[stage_in]], float4 coord " +
		"[[position]], bool facing [[front_facing]], constant Params& params [[buffer(0)]], " +
		"texture2d<float> albedo [[texture(0)]], texture2d<float> texel [[texture(1)]], " +
		"texture2d_array<float> layers [[texture(2)]], sampler albedoSampler [[sampler(0)]]) {\n");
	for (const fragment of [
		"struct Params {\n  float4 tint;\n  float4x4 model;\n  float4 rows[2];\n};\n",
		"constant float SCALE = 2.0;\n",
		"constant int loop = 3;\n",
		"static inline float3 shade(Light light, float gain) {\n  gain *= SCALE;\n",
		"static inline float3x3 upperLeft3x3(float4x4 m) {\n",
		"static inline float2x2 inverse2x2(float2x2 m) {\n  float k = 1.0 / determinant(m);\n",
		"static inline float3x3 inverse3x3(float3x3 m) {\n",
		"static inline float4x4 inverse4x4(float4x4 m) {\n  float3 a = m[0].xyz;\n",
		"static inline void everyFs(thread main0_in& in, thread main0_out& out, thread float4& " +
			"coord, thread bool& facing, constant Params& params, texture2d<float> albedo, sampler " +
			"albedoSampler, texture2d<float> texel, texture2d_array<float> layers) {\n",
		"  bool3 select_1 = (v3 <= float3(0.5));\n",
		"  Light light = Light{v3, f};\n",
		"  float3 ofRound = rint(v3);\n",
		"  float3 ofInverseSqrt = rsqrt(v3);\n",
		"  float3 ofDegrees = (v3 * 57.295779513082323);\n",
		"  float3 ofDpdy = dfdy(v3);\n",
		"  float3 ofFaceForward = faceforward(v3, v3, v3);\n",
		"  float4x4 ofInverse = inverse4x4(m4);\n",
		"  float3x3 ofInverse3 = inverse3x3(ofUpperLeft3x3);\n",
		"  float2x2 ofInverse2 = inverse2x2(float2x2(in.uv, in.uv));\n",
		"  float3 ofSelect = select(v3, float3(1.0), select_1);\n",
		"  float4 ofTextureSample = albedo.sample(albedoSampler, in.uv);\n",
		"  float4 ofTextureSampleLayer = layers.sample(albedoSampler, in.uv, uint(i));\n",
		"  float4 ofTextureLoad = texel.read(uint2(int2(in.uv)), uint(0));\n",
		"  float4 ofTextureLoadLayer = layers.read(uint2(int2(in.uv)), uint(i), uint(0));\n",
		"  int2 ofTextureDimensions = int2(texel.get_width(uint(0)), texel.get_height(uint(0)));\n",
		"  int least = (-2147483647 - 1);\n",
		"  bool same = all(v3 == v3);\n",
		"  bool differ = any(v4 != v4);\n",
		"  float chosen = (b ? 1.0 : 0.0);\n",
		"  int ints = (((i + 1) - loop) / 2);\n",
		"  f = fmod(f, 7.0);\n  i %= 3;\n  i++;\n  i--;\n  u = ((~u) & 255u);\n",
		"  v4.xyz = v3;\n  v4.yx += float2(1.0);\n  v4.w = f;\n",
		"  } else {\n    discard_fragment();\n  }\n",
		"  for (int k = 0; (k < 4); k++) {\n    if ((k == 2)) {\n      continue;\n",
		"  {\n    int j = 0;\n    f = f;\n    for (; (j < 2); j++, f += 0.0) {\n" +
			"      switch (j) {\n        case 0: case 1: {\n          f += 1.0;\n          break;\n",
		"        case 3: default: {\n          break;\n          break;\n        }\n",
		"    case 5u: {\n      f -= 1.0;\n      break;\n    }\n  }\n",
		"  shade(light, f);\n  (void)dfdx(f);\n  {\n    float scratch = {};\n",
		"  while ((f > 1.0)) {\n",
		"  out.extra = float4(shade(light, f), 1.0);\n",
		"  out.depth = (coord.z * float(in.id));\n",
		"  everyFs(in, out, coord, facing, params, albedo, albedoSampler, texel, layers);\n",
	]) {
		assert fs.includes(fragment);
	}
}

test "what MSL cannot say is refused by name" {
	const fragment = ShaderStage.Fragment;
	assert refused(tiny(fragment, column(model()))) == "printed";
	assert refused(tiny(fragment, column(intrinsicOf(Intrinsic.Inverse, MAT4, [model()])))) ==
		"printed";
	assert refused(tiny(fragment, column(intrinsicOf(Intrinsic.Inverse, matrixType(4, 3),
		[model()])))) == "printMsl: Inverse of a Matrix that is no square matrix";
	assert refused(tiny(ShaderStage.Vertex, intrinsicOf(Intrinsic.Dpdx, VEC4,
		[literal(VEC4, 1.0)]))) == "printMsl: dfdx outside a fragment entry";
	assert refused(tiny(fragment, column(literal(MAT4, 1.0)))) == "printMsl: a literal of a Matrix";
	assert refused(tiny(fragment, literal(VEC4, 1.0 / 0.0))) ==
		"printMsl: a literal that is not finite";
	assert refusalOf(tiny(fragment, column(model())), 0, []) ==
		"printMsl: resource 'params' has no MSL slot";
	assert refusalOf(tiny(fragment, column(model())), 1, []) == "printMsl: entry 1 is out of range";

	let vertexDiscard = tiny(ShaderStage.Vertex, literal(VEC4, 0.0));
	vertexDiscard.functions[0].body.splice(0, 0, stmtOf(StmtKind.Discard, new ShaderExpr(), []));
	assert refused(vertexDiscard) == "printMsl: discard outside a fragment entry";

	let signed = tiny(ShaderStage.Vertex, literal(VEC4, 0.0));
	signed.ios.push(io("vertexIndex", ShaderStage.Vertex, IoDirection.In, I32,
		Builtin.VertexIndex));
	assert refused(signed) == "printMsl: io 'vertexIndex' is int; [[vertex_id]] is uint";

	let unspellable = tiny(fragment, literal(VEC4, 0.0));
	unspellable.functions[0].name = "__entry";
	assert refused(unspellable) == "printMsl: '__entry' is no MSL identifier";

	let recursive = tiny(fragment, exprOf(ExprKind.Call, VEC4, 1, []));
	let helper = shaderFunction("helper", [stmtOf(StmtKind.Return, exprOf(ExprKind.Call, VEC4, 1,
		[]), [])]);
	helper.result = VEC4;
	recursive.functions.push(helper);
	assert refused(recursive) == "printMsl: function 'helper' is recursive";

	let packed = tiny(fragment, literal(VEC4, 0.0));
	packed.structs.push(block("Light", [field("colour", VEC3), field("power", F32)]));
	packed.resources.push(resource(ResourceKind.UniformBlock, "light", 1, structType(1)));
	packed.functions[0].body.splice(0, 0, assignOf(ioOf(packed, 0),
		exprOf(ExprKind.Construct, VEC4, -1, [memberOf(packed, 1, 0), memberOf(packed, 1, 1)])));
	assert refused(packed) == "printMsl: uniform block 'light': member 'power' sits at byte 12 " +
		"in the host layout and 16 in MSL";
}

test "a feature branch prints only after specialize decides it" {
	let m = tiny(ShaderStage.Fragment, literal(VEC4, 0.0));
	m.features = ["CUTOUT"];
	let branch = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), [stmtOf(StmtKind.Discard,
		new ShaderExpr(), [])]);
	branch.condition = featureOn("CUTOUT");
	m.functions[0].body.splice(1, 0, branch);
	assert refused(m) ==
		"printMsl: a feature branch is still undecided: specialize the module first";
	const on = specialize(m, ["CUTOUT"]);
	const off = specialize(m, []);
	assert on.ok && off.ok;
	if (on.ok && off.ok) {
		const cut = mslOf(on.value, 0, slotsOf(on.value, [0]));
		const kept = mslOf(off.value, 0, slotsOf(off.value, [0]));
		assert cut.includes("  discard_fragment();\n") && !kept.includes("discard");
		assert writeProbe("cutout", cut) && writeProbe("kept", kept);
	}
}

test "depth comparison prints on every depth shape" {
	const m = depthModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	const vs = mslOf(m, 0, slots);
	const fs = mslOf(m, 1, slots);
	assert writeProbe("depthVs", vs);
	assert writeProbe("depthFs", fs);
	assert vs.includes("vertex main0_out main0(depth2d<float> heightMap [[texture(0)]], " +
		"sampler heightSmp [[sampler(1)]])");
	assert vs.includes("heightMap.sample_compare(heightSmp, float2(0.5), 0.5, level(0.0))");
	assert vs.includes("int2(heightMap.get_width(), heightMap.get_height())");
	for (const fragment of [
		"depthcube<float> shadowCube [[texture(2)]]",
		"shadowMap.sample_compare(shadowSmp, in.uv, 0.5)",
		"shadowLayers.sample_compare(shadowSmp, float3(in.uv, 1.0).xy, " +
			"uint(float3(in.uv, 1.0).z), 0.5)",
		"shadowCube.sample_compare(shadowSmp, float3(in.uv, 1.0), 0.5)",
		"shadowLayers.sample_compare(shadowSmp, float3(in.uv, 1.0).xy, " +
			"uint(float3(in.uv, 1.0).z), 0.5, level(0.0))",
		"shadowMap.read(uint2(int2(1)), uint(0))",
		"lut.get_width(uint(0))",
	]) {
		assert fs.includes(fragment);
	}
}

function compared(stage: ShaderStage, op: Intrinsic, shape: TextureShape,
	comparison: boolean): ShaderModule {
	let m = tiny(stage, exprOf(ExprKind.Construct, VEC4, -1,
		[depthCompare(op, 1, 2, shape, literal(VEC2, 0.5))]));
	m.resources.push(depthTexture("shadowMap", 0, shape));
	m.resources.push(comparison ? comparisonSampler("shadowSmp", 0) :
		resource(ResourceKind.Sampler, "shadowSmp", 0, samplerType()));
	return m;
}

test "depth comparison is refused by name where it cannot print" {
	const COMPARE = Intrinsic.TextureSampleCompare;
	const LEVEL = Intrinsic.TextureSampleCompareLevel;
	const D2 = TextureShape.Depth2d;
	assert refused(compared(ShaderStage.Vertex, LEVEL, D2, true)) == "printed";
	assert refused(compared(ShaderStage.Fragment, COMPARE, D2, true)) == "printed";
	assert refused(compared(ShaderStage.Vertex, COMPARE, D2, true)) ==
		"printMsl: TextureSampleCompare outside a fragment entry";
	assert refused(compared(ShaderStage.Fragment, LEVEL, D2, false)) ==
		"printMsl: TextureSampleCompareLevel through a sampler that is no comparison sampler binding";
	assert refused(compared(ShaderStage.Fragment, COMPARE, TextureShape.D2, true)) ==
		"printMsl: TextureSampleCompare of a D2 texture, which holds no depth";
}
