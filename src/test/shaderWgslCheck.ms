// Hand-built IR modules print as WGSL, one module per entry. Each printed module is written to
// out/wgslProbe/, which scripts/validateWgsl.sh hands to naga.

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
	exprOf,
	featureOn,
	intrinsicOf,
	irErrors,
	literal,
	matrixType,
	samplerType,
	stmtOf,
} from "../shader/ir";
import { BindingSlot, ShaderTarget, bindingSlots } from "../shader/layout";
import { printWgsl } from "../shader/printWgsl";
import { specialize } from "../shader/specialize";
import {
	BOOL,
	I32,
	IVEC2,
	MAT4,
	TEXTURE,
	VEC2,
	VEC4,
	blurModule,
	column,
	comparisonSampler,
	computeBuiltinsModule,
	depthCompare,
	depthModule,
	depthTexture,
	everyModule,
	io,
	model,
	resource,
	shaderFunction,
	tiny,
} from "./shaderProbeModules";

function slotsOf(m: ShaderModule, entries: int32[]): BindingSlot[] {
	const slots = bindingSlots(m, entries, ShaderTarget.Wgsl);
	if (!slots.ok) { return [] }
	return slots.value;
}

function writeProbe(name: string, text: string): boolean {
	const _out = mkdir("out");
	const _probe = mkdir("out/wgslProbe");
	return writeFile("out/wgslProbe/" + name + ".wgsl", text).ok;
}

function wgslOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printWgsl(m, index, slots);
	if (printed.ok) { return printed.value; }
	return printed.error;
}

function refusalOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printWgsl(m, index, slots);
	if (printed.ok) { return "printed"; }
	return printed.error;
}

// The interface lines of the WGSL committed in src/void2d/shader2dModules.ms (webgpu
// blurShaderModule).
const COMMITTED_BLUR_VS = "struct main_out {\n  @location(0)\n  uv_1 : vec2f,\n" +
	"  @builtin(position)\n  gl_Position : vec4f,\n}\n\n@vertex\n" +
	"fn main(@location(1) uv0_param : vec2f, @location(0) pos_param : vec2f) -> main_out {\n";
const COMMITTED_BLUR_FS = "@binding(0) @group(0) var<uniform> x_13 : blur_params;\n\n" +
	"@binding(0) @group(1) var srcTex : texture_2d<f32>;\n\n" +
	"@binding(32) @group(1) var srcSmp : sampler;\n\n" +
	"struct main_out {\n  @location(0)\n  fragColor_1 : vec4f,\n}\n\n@fragment\n" +
	"fn main(@location(0) uv_param : vec2f) -> main_out {\n";

function withoutName(item: string): string {
	const parts = item.trim().split(" : ");
	let words = parts[0].split(" ");
	words.pop();
	return words.join(" ") + " : " + parts[1];
}

function sorted(items: string[]): string[] {
	let out = items.map((s) => s);
	out.sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
	return out;
}

function interfaceOf(text: string): string {
	let facts: string[] = [];
	const lines = text.split("\n");
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (line.startsWith("@binding(")) {
			const item = withoutName(line.substring(0, line.length - 1));
			facts.push(line.includes("<uniform>") ? item.split(" : ")[0] : item);
		}
		if (line == "@vertex" || line == "@fragment") { facts.push(line); }
		if (line.startsWith("fn main(")) {
			const inside = line.substring(8, line.lastIndexOf(")"));
			facts.push("in " + sorted(inside.split(", ").map((x) => withoutName(x))).join(", "));
		}
		if (line == "struct main_out {") {
			let members = "";
			for (let k = i + 1; k < lines.length && lines[k] != "}"; k++) {
				members += " " + lines[k].trim();
			}
			const items = members.split(",").filter((x) => x.trim() != "");
			facts.push("out " + sorted(items.map((x) => withoutName(x))).join(", "));
		}
	}
	return facts.join("\n");
}

test "blur prints the bindings and entry interface of the committed WGSL" {
	const m = blurModule();
	const slots = slotsOf(m, [0, 1]);
	const vs = wgslOf(m, 0, slots);
	const fs = wgslOf(m, 1, slots);
	assert writeProbe("blurVs", vs);
	assert writeProbe("blurFs", fs);
	assert interfaceOf(vs) == interfaceOf(COMMITTED_BLUR_VS);
	assert interfaceOf(fs) == interfaceOf(COMMITTED_BLUR_FS);
	assert interfaceOf(fs) == [
		"@binding(0) @group(0) var<uniform>",
		"@binding(0) @group(1) var : texture_2d<f32>",
		"@binding(32) @group(1) var : sampler",
		"out @location(0) : vec4f",
		"@fragment",
		"in @location(0) : vec2f",
	].join("\n");
	assert vs.includes("fn main(@location(0) pos_param : vec2f, @location(1) uv0_param : vec2f)" +
		" -> main_out {\n  pos = pos_param;\n  uv0 = uv0_param;\n  blurVs();\n" +
		"  return main_out(clip, uv);\n}\n");
	assert !vs.includes("diagnostic") && fs.startsWith("diagnostic(off, derivative_uniformity);\n");
	assert fs.includes("  fragColor = (textureSample(srcTex, srcSmp, uv) * blur_params.dir);\n");
}


test "compute prints storage resources, builtins and its workgroup size" {
	const m = computeBuiltinsModule();
	assert irErrors(m).length == 0;
	const cs = wgslOf(m, 0, slotsOf(m, [0]));
	assert writeProbe("total", cs);
	assert cs.includes("@binding(0) @group(1) var<storage, read> commands : array<Command>;\n");
	assert cs.includes("@binding(1) @group(1) var<storage, read_write> results : array<Total>;\n");
	assert cs.includes("@binding(2) @group(1) var image : texture_storage_2d<rgba8unorm, write>;\n");
	assert cs.includes("@binding(3) @group(1) var lut : texture_2d<f32>;\n");
	assert cs.includes("@binding(32) @group(1) var lutSmp : sampler;\n");
	assert cs.includes("@compute @workgroup_size(32, 1, 1)\nfn main(@builtin(global_invocation_id)" +
		" id_param : vec3u, @builtin(local_invocation_id) local_param : vec3u, " +
		"@builtin(local_invocation_index) index_param : u32, @builtin(workgroup_id) group_param :" +
		" vec3u, @builtin(num_workgroups) groups_param : vec3u) {\n");
	assert cs.includes("  textureStore(image, vec2i(local.xy), (textureLoad(lut, vec2i(local.xy)," +
		" 0i) * commands[id.x].value));\n");
	assert cs.includes("results[(group.x + (index + groups.y))].sum = ");
}


test "every intrinsic and statement prints" {
	const m = everyModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	const vs = wgslOf(m, 0, slots);
	const fs = wgslOf(m, 1, slots);
	assert writeProbe("everyVs", vs);
	assert writeProbe("everyFs", fs);
	assert !vs.includes("diagnostic") && fs.startsWith("diagnostic(off, derivative_uniformity);\n");
	assert vs.includes("@binding(33) @group(1) var heightSampler : sampler;\n");
	assert vs.includes("textureSampleLevel(heightMap, heightSampler, position, 0.0f)");
	assert vs.includes("  @builtin(position) clip : vec4f,\n" +
		"  @location(0) @interpolate(perspective, sample) uv : vec2f,\n" +
		"  @location(1) @interpolate(linear, centroid) tint : vec4f,\n" +
		"  @location(2) @interpolate(flat) id : u32,\n}\n");
	assert vs.includes("fn main(@location(0) position_param : vec2f, @builtin(vertex_index) " +
		"vertexIndex_param : u32, @builtin(instance_index) instance_param : u32) -> main_out {\n");
	assert fs.includes("fn main(@location(0) @interpolate(perspective, sample) uv_param : vec2f, " +
		"@location(1) @interpolate(linear, centroid) tint_param : vec4f, @location(2) " +
		"@interpolate(flat) id_param : u32, @builtin(position) coord_param : vec4f, " +
		"@builtin(front_facing) facing_param : bool) -> main_out {\n");
	assert fs.includes("  @builtin(frag_depth) depth : f32,\n");
	for (const fragment of [
		"const loop_1 : i32 = 3i;\n",
		"fn shade(light : Light, gain_in : f32) -> vec3f {\n  var gain : f32 = gain_in;\n",
		"fn upperLeft3x3(m : mat4x4f) -> mat3x3f {\n",
		"  var select_1 : vec3<bool> = (v3 <= vec3f(0.5f));\n",
		"  var ofUpperLeft3x3 : mat3x3f = upperLeft3x3(m4);\n",
		"fn inverse2x2(m : mat2x2f) -> mat2x2f {\n  let k = 1.0f / determinant(m);\n",
		"fn inverse3x3(m : mat3x3f) -> mat3x3f {\n",
		"fn inverse4x4(m : mat4x4f) -> mat4x4f {\n  let a = m[0].xyz;\n",
		"  var ofInverse : mat4x4f = inverse4x4(m4);\n",
		"  var ofInverse3 : mat3x3f = inverse3x3(ofUpperLeft3x3);\n",
		"  var ofInverse2 : mat2x2f = inverse2x2(mat2x2f(uv, uv));\n",
		"  var ofSelect : vec3f = select(v3, vec3f(1f), select_1);\n",
		"  var ofTextureSampleLayer : vec4f = textureSample(layers, albedoSampler, uv, i);\n",
		"  var ofTextureLoadLayer : vec4f = textureLoad(layers, vec2i(uv), i, 0i);\n",
		"  var ofTextureDimensions : vec2i = vec2i(textureDimensions(texel, 0i));\n",
		"  var least : i32 = (-2147483647i - 1i);\n",
		"  var same : bool = all(v3 == v3);\n",
		"  var differ : bool = any(v4 != v4);\n",
		"  var chosen : f32 = select(0f, 1f, b);\n",
		"  var ints : i32 = (((i + 1i) - loop_1) / 2i);\n",
		"  var negated : f32 = (-(-0.5f));\n",
		"  i %= 3i;\n  i++;\n  i--;\n  u = ((~u) & 255u);\n",
		"  {\n    let swizzled = v3;\n    v4.x = swizzled.x;\n    v4.y = swizzled.y;\n" +
			"    v4.z = swizzled.z;\n  }\n",
		"    v4.y += swizzled_1.x;\n    v4.x += swizzled_1.y;\n",
		"  } else {\n    discard;\n  }\n",
		"  for (var k : i32 = 0i; (k < 4i); k++) {\n    if ((k == 2i)) {\n      continue;\n",
		"    loop {\n      if (!(j < 2i)) { break; }\n      switch (j) {\n" +
			"        case 0i, 1i: {\n",
		"        case 3i, default: {\n          break;\n        }\n",
		"      continuing {\n        j++;\n        f += 0f;\n      }\n",
		"    case 5u: {\n      f -= 1f;\n    }\n    default: {}\n",
		"  shade(light, f);\n  _ = dpdx(f);\n  {\n    var scratch : f32;\n",
		"  while ((f > 1f)) {\n",
		"  depth = (coord.z * f32(id));\n",
	]) {
		assert fs.includes(fragment);
	}
}


function refused(m: ShaderModule): string { return refusalOf(m, 0, slotsOf(m, [0])); }


test "what WGSL cannot say is refused by name" {
	const fragment = ShaderStage.Fragment;
	assert refused(tiny(fragment, column(model()))) == "printed";
	assert refused(tiny(fragment, column(intrinsicOf(Intrinsic.Inverse, matrixType(4, 3),
		[model()])))) == "printWgsl: inverse of a Matrix that is no square matrix";
	assert refused(tiny(ShaderStage.Vertex, intrinsicOf(Intrinsic.Dpdx, VEC4,
		[literal(VEC4, 1.0)]))) == "printWgsl: dpdx outside a fragment entry";
	assert refused(tiny(fragment, column(literal(MAT4, 1.0)))) ==
		"printWgsl: a literal of a Matrix";
	assert refused(tiny(fragment, literal(VEC4, 1.0 / 0.0))) ==
		"printWgsl: a literal that is not finite";
	assert refusalOf(tiny(fragment, column(model())), 0, []) ==
		"printWgsl: resource 'params' has no binding slot";
	assert refusalOf(tiny(fragment, column(model())), 1, []) == "printWgsl: entry 1 is out of range";

	let called = tiny(fragment, exprOf(ExprKind.Conditional, VEC4, -1,
		[literal(BOOL, 1.0), exprOf(ExprKind.Call, VEC4, 1, []), literal(VEC4, 0.0)]));
	let helper = shaderFunction("helper", [], [stmtOf(StmtKind.Return, literal(VEC4, 1.0), [])]);
	helper.result = VEC4;
	called.functions.push(helper);
	assert refused(called) == "printWgsl: a conditional whose branch calls a function";

	let unlevelled = tiny(fragment, intrinsicOf(Intrinsic.TextureLoad, VEC4, [
		exprOf(ExprKind.Resource, TEXTURE, 1, []),
		exprOf(ExprKind.Resource, samplerType(), 2, []),
		literal(IVEC2, 0.0),
	]));
	unlevelled.resources.push(resource(ResourceKind.Texture, "lut", 0, TEXTURE));
	unlevelled.resources.push(resource(ResourceKind.Sampler, "lutSmp", 0, samplerType()));
	assert refused(unlevelled) == "printWgsl: textureLoad of a sampled texture takes a level";

	let signed = tiny(ShaderStage.Vertex, literal(VEC4, 0.0));
	signed.ios.push(io("vertexIndex", ShaderStage.Vertex, IoDirection.In, I32,
		Builtin.VertexIndex));
	assert refused(signed) == "printWgsl: io 'vertexIndex' is i32; @builtin(vertex_index) is u32";

	let unspellable = tiny(fragment, literal(VEC4, 0.0));
	unspellable.functions[0].name = "__entry";
	assert refused(unspellable) == "printWgsl: '__entry' is no WGSL identifier";
}

test "a feature branch prints only after specialize decides it" {
	let m = tiny(ShaderStage.Fragment, literal(VEC4, 0.0));
	m.features = ["CUTOUT"];
	let branch = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), [stmtOf(StmtKind.Discard,
		new ShaderExpr(), [])]);
	branch.condition = featureOn("CUTOUT");
	m.functions[0].body.splice(1, 0, branch);
	assert refused(m) ==
		"printWgsl: a feature branch is still undecided: specialize the module first";
	const on = specialize(m, ["CUTOUT"]);
	const off = specialize(m, []);
	assert on.ok && off.ok;
	if (on.ok && off.ok) {
		const cut = wgslOf(on.value, 0, slotsOf(on.value, [0]));
		const kept = wgslOf(off.value, 0, slotsOf(off.value, [0]));
		assert cut.includes("  discard;\n") && !kept.includes("discard");
		assert writeProbe("cutout", cut) && writeProbe("kept", kept);
	}
}

test "depth comparison prints on every depth shape" {
	const m = depthModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	const vs = wgslOf(m, 0, slots);
	const fs = wgslOf(m, 1, slots);
	assert writeProbe("depthVs", vs);
	assert writeProbe("depthFs", fs);
	assert vs.includes("@binding(33) @group(1) var heightSmp : sampler_comparison;
");
	assert vs.includes("textureSampleCompareLevel(heightMap, heightSmp, vec2f(0.5f), 0.5f)");
	assert vs.includes("f32(vec2i(textureDimensions(heightMap)).x)");
	for (const fragment of [
		"textureSampleCompare(shadowMap, shadowSmp, uv, 0.5f)",
		"textureSampleCompare(shadowLayers, shadowSmp, vec3f(uv, 1f).xy, i32(vec3f(uv, 1f).z), 0.5f)",
		"textureSampleCompare(shadowCube, shadowSmp, vec3f(uv, 1f), 0.5f)",
		"textureSampleCompareLevel(shadowLayers, shadowSmp, vec3f(uv, 1f).xy, " +
			"i32(vec3f(uv, 1f).z), 0.5f)",
		"textureLoad(shadowMap, vec2i(1i), 0i)",
		"textureDimensions(lut, 0i)",
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
		"printWgsl: TextureSampleCompare outside a fragment entry";
	assert refused(compared(ShaderStage.Fragment, LEVEL, D2, false)) ==
		"printWgsl: TextureSampleCompareLevel through a sampler that is no comparison sampler binding";
	assert refused(compared(ShaderStage.Fragment, COMPARE, TextureShape.D2, true)) ==
		"printWgsl: TextureSampleCompare of a D2 texture, which holds no depth";
}
