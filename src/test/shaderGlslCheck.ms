// The probe modules printed as GLSL 430 and GLSL ES 3.00: the blur keeps the committed interface
// of both, every intrinsic and statement kind has a spelling, and each refusal names its case.
// The printed files land in out/glslProbe/ for naga.

import { mkdir, readFile, writeFile } from "std/fs";
import {
	AssignOp,
	Builtin,
	ExprKind,
	Interpolation,
	Intrinsic,
	IoDirection,
	ResourceKind,
	ScalarKind,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	StmtKind,
	arrayType,
	assignOf,
	exprOf,
	featureOn,
	intrinsicOf,
	irErrors,
	literal,
	samplerType,
	stmtOf,
	structType,
	vectorType,
} from "../shader/ir";
import { ShaderTarget, bindingSlots } from "../shader/layout";
import { GlslTarget, printGlsl } from "../shader/printGlsl";
import {
	BOOL,
	F32,
	IVEC2,
	MAT4,
	TEXTURE,
	U32,
	VEC3,
	VEC4,
	blurModule,
	caseOf,
	computeModule,
	construct,
	entry,
	f32,
	fragmentModule,
	i32,
	io,
	ioRead,
	local,
	prepend,
	resource,
	ret,
	shaderFunction,
	single,
	update,
	vertexModule,
} from "./shaderProbeModules";

const TARGETS = [GlslTarget.Glsl430, GlslTarget.Glsl300es];

function layoutTarget(target: GlslTarget): ShaderTarget {
	return target == GlslTarget.Glsl430 ? ShaderTarget.Glsl430 : ShaderTarget.Glsl300es;
}

function printed(m: ShaderModule, entryIndex: int32, program: int32[], target: GlslTarget): string {
	const slots = bindingSlots(m, program, layoutTarget(target));
	if (!slots.ok) { return slots.error; }
	const text = printGlsl(m, entryIndex, slots.value, target);
	if (!text.ok) { return text.error; }
	return text.value;
}

function refusal(m: ShaderModule, entryIndex: int32, target: GlslTarget): string {
	const slots = bindingSlots(m, [entryIndex], layoutTarget(target));
	const text = printGlsl(m, entryIndex, slots.ok ? slots.value : [], target);
	return text.ok ? "printed" : text.error;
}

function interfaceLines(text: string): string[] {
	let out: string[] = [];
	for (const line of text.split("\n")) {
		const declared = ["uniform ", "layout(location", "layout(binding", "in ", "out ", "flat ",
			"centroid "].some((start) => line.startsWith(start));
		if (declared) { out.push(line); }
	}
	out.sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
	return out;
}

// The blur strings of the GL rows of src/void2d/shader2dModules.ms, which only a GL build
// compiles, read from the source.
function committed(version: string, stage: string): string {
	const source = readFile("src/void2d/shader2dModules.ms");
	if (!source.ok) { return "unread"; }
	const start = stage + "Code: \"" + version;
	const at = source.value.indexOf(start);
	if (at < 0) { return "absent"; }
	const from = at + start.length - version.length;
	const end = source.value.indexOf("\",", from);
	return source.value.substring(from, end).split("\\n").join("\n");
}

test "blur prints the interface of the committed GLSL 430 and GLSL ES 3.00" {
	const m = blurModule();
	assert irErrors(m).length == 0;
	for (const target of TARGETS) {
		const version = target == GlslTarget.Glsl430 ? "#version 430\\n" : "#version 300 es\\n";
		const vs = printed(m, 0, [0, 1], target);
		const fs = printed(m, 1, [0, 1], target);
		assert interfaceLines(vs).join("\n") ==
			interfaceLines(committed(version, "vertex")).join("\n");
		assert interfaceLines(fs).join("\n") ==
			interfaceLines(committed(version, "fragment")).join("\n");
		assert interfaceLines(fs).length == 4;
		assert vs.includes("    gl_Position = vec4(pos, 0.0, 1.0);\n");
		assert fs.includes("    fragColor = texture(srcTex_srcSmp, uv) * blur_params[0];\n");
	}
	assert printed(m, 1, [0, 1], GlslTarget.Glsl300es).startsWith("#version 300 es\n" +
		"precision mediump float;\nprecision highp int;\n");
	assert !printed(m, 0, [0, 1], GlslTarget.Glsl300es).includes("precision");
}

function perspective(m: ShaderModule): ShaderModule {
	m.ios[7].interpolation = Interpolation.Perspective;
	return m;
}

test "the vertex probe reads its block through the flattened vec4 array" {
	const m = vertexModule();
	assert irErrors(m).length == 0;
	const desktop = printed(m, 0, [0], GlslTarget.Glsl430);
	const es = printed(perspective(vertexModule()), 0, [0], GlslTarget.Glsl300es);
	for (const text of [desktop, es]) {
		for (const piece of [
			"uniform vec4 camera[12];\n",
			"gl_Position = mat4(camera[0], camera[1], camera[2], camera[3]) * vec4(position, 1.0);\n",
			"shade = (color * camera[5].w) + (vec4(mat3(camera[7].xyz, camera[8].xyz, " +
				"camera[9].xyz) * camera[5].xyz, 0.0) + camera[11]);\n",
			"id = uint(gl_VertexID) + uint(gl_InstanceID);\n",
			"uvL = camera[6].xy + camera[4].xy;\n",
			"layout(location = 0) in vec3 position;\n",
			"layout(location = 1) in vec4 color;\n",
		]) {
			if (!text.includes(piece)) { console.log("missing: " + piece); }
			assert text.includes(piece);
		}
	}
	assert desktop.includes("layout(location = 0) out vec4 shade;\n" +
		"layout(location = 1) flat out uint id;\nlayout(location = 2) noperspective centroid out " +
		"vec2 uvL;\n");
	assert es.includes("out vec4 shade;\nflat out uint id;\ncentroid out vec2 uvL;\n");
}

test "the fragment probe spells every intrinsic and statement on both targets" {
	const m = fragmentModule();
	assert irErrors(m).length == 0;
	const desktop = printed(m, 0, [0], GlslTarget.Glsl430);
	const es = printed(m, 0, [0], GlslTarget.Glsl300es);
	for (const text of [desktop, es]) {
		for (const piece of [
			"float[3](0.25, 0.5, 0.25);\n", "float arr[3] = float[3](f, f, 2.0);\n",
			"Sample s = Sample(f, v2);\n", "ivec2 size = textureSize(albedo_albedoSmp, 0);\n",
			"bvec3 b3 = lessThanEqual(v3, v3);\n", "f = inversesqrt(f);\n", "v3 = sign(v3);\n",
			"v3 = roundEven(v3);\n", "v3 = fract(v3);\n", "v3 = mix(v3, v3, f);\n",
			"v3 = faceforward(v3, v3, v3);\n", "v3 = mix(v3, v3, b3);\n", "f = (b ? 1.0 : f);\n",
			"f = atan(f, f);\n", "v4 = clamp(v4, 0.0, 1.0);\n", "m4 = inverse(m4);\n",
			"m3 = inverse(m3);\n", "m2 = inverse(m2);\n", "m3 = mat3(m4);\n", "v2 = dFdx(v2);\n",
			"v2 = fwidth(v2);\n", "f = dFdy(f);\n", "i = sign(i);\n",
			"v4 = texelFetch(albedo_albedoSmp, i2, 0);\n", "v4 *= m4;\n",
			"f = f - 2.0 * trunc(f / 2.0);\n", "u = u % 4u;\n", "v4.zw = v2;\n", "shade_1(v3, f);\n",
			"if (f < 0.0)\n    {\n        discard;\n    }\n    else\n",
			"int k = 0; k < 3; k++)\n", "f += weights[k];\n",
			"int j = 3;\n        for (; k < j; k++, j--)\n",
			"        case 0:\n        case 1:\n        {\n            f += 1.0;\n            break;\n",
			"        default:\n", "b = v3 == v3;\n", "b = v3 != v3;\n", "i = i / 2;\n",
			"f = s.weight + v3[i];\n", "v2 = s.offset - gl_FragCoord.xy;\n", "v4 = m4[1];\n",
			"v4 = mat4(material[1], material[2], material[3], material[4]) * (v4 * material[0]);\n",
			"f = b ? f : 1.0;\n", "f = f + float(u + 2891336453u);\n", "bool b = gl_FrontFacing;\n",
			"gl_FragDepth = f;\n", "color = v4;\n", "void main()\n",
		]) {
			if (!text.includes(piece)) { console.log("missing: " + piece); }
			assert text.includes(piece);
		}
	}
	for (const piece of [
		"#version 430\n\n", "const float weights[3]", "vec3 shade_1(vec3 x, float k)\n{\n" +
			"    return x * k;\n}\n",
		"uniform vec4 material[5];\nlayout(binding = 0) uniform sampler2D albedo_albedoSmp;\n",
		"layout(location = 0) in vec4 shade;\nlayout(location = 1) flat in uint id;\n" +
			"layout(location = 0) out vec4 color;\nlayout(location = 1) out vec4 extra;\n",
		"f = fma(f, f, f);\n",
	]) {
		if (!desktop.includes(piece)) { console.log("missing: " + piece); }
		assert desktop.includes(piece);
	}
	for (const piece of [
		"const highp float weights[3]", "highp vec3 shade_1(highp vec3 x, highp float k)\n",
		"uniform highp vec4 material[5];\nuniform highp sampler2D albedo_albedoSmp;\n",
		"in highp vec4 shade;\nflat in highp uint id;\n" +
			"layout(location = 0) out highp vec4 color;\nlayout(location = 1) out highp vec4 extra;\n",
		"highp float arr[3]", "f = (f * f + f);\n",
	]) {
		if (!es.includes(piece)) { console.log("missing: " + piece); }
		assert es.includes(piece);
	}
}

test "the compute probe declares std430 buffers and images on GLSL 430" {
	const m = computeModule();
	assert irErrors(m).length == 0;
	const text = printed(m, 0, [0], GlslTarget.Glsl430);
	for (const piece of [
		"#version 430\n\nlayout(local_size_x = 8, local_size_y = 4, local_size_z = 1) in;\n",
		"struct Particle\n{\n    vec3 position;\n    float mass;\n    vec2 velocity;\n};\n",
		"struct Spring\n{\n    float rest;\n    vec3 axis;\n};\n",
		"layout(std430, binding = 0) buffer particles_buffer\n{\n    Particle data[];\n} particles;\n",
		"layout(std430, binding = 1) readonly buffer springs_buffer\n{\n    Spring data[];\n} " +
			"springs;\n",
		"layout(binding = 0, r32f) uniform image2D heat;\n",
		"layout(binding = 1, rgba8) uniform writeonly image2D image;\n",
		"ivec2 size = imageSize(image);\n",
		"particles.data[gl_GlobalInvocationID.x].mass = springs.data[gl_LocalInvocationIndex].rest" +
			" + float(gl_WorkGroupID.x);\n",
		"imageStore(heat, ivec2(gl_LocalInvocationID.xy), vec4(springs.data[gl_LocalInvocationIndex]" +
			".axis, imageLoad(heat, ivec2(gl_LocalInvocationID.xy)).x));\n",
		"imageStore(image, size.yx - ivec2(gl_LocalInvocationID.xy), vec4(",
	]) {
		if (!text.includes(piece)) { console.log("missing: " + piece); }
		assert text.includes(piece);
	}
}

// A fragment whose only texture read is a TextureLoad with no sampler operand.
function loneLoadModule(paired: boolean): ShaderModule {
	let m = new ShaderModule();
	m.resources = [
		resource(ResourceKind.Texture, "tex", 0, TEXTURE),
		resource(ResourceKind.Sampler, "smp", 0, samplerType()),
	];
	let color = io("color", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	color.location = 0;
	m.ios = [color];
	const texture = exprOf(ExprKind.Resource, TEXTURE, 0, []);
	const sampler = exprOf(ExprKind.Resource, samplerType(), 1, []);
	let body = [assignOf(ioRead(0, VEC4), intrinsicOf(Intrinsic.TextureLoad, VEC4,
		[texture, construct(IVEC2, [i32(1.0)]), i32(0.0)]))];
	if (paired) {
		body.push(assignOf(ioRead(0, VEC4), intrinsicOf(Intrinsic.TextureSample, VEC4,
			[texture, sampler, construct(vectorType(ScalarKind.F32, 2), [f32(0.5)])])));
	}
	body.push(ret());
	m.functions = [shaderFunction("loadFs", [], body)];
	m.entries = [entry("loadFs", ShaderStage.Fragment, 0)];
	return m;
}

test "a TextureLoad without a sampler reads through the pair the slots chose" {
	const paired = loneLoadModule(true);
	assert irErrors(paired).length == 0;
	assert printed(paired, 0, [0], GlslTarget.Glsl430)
		.includes("color = texelFetch(tex_smp, ivec2(1), 0);\n");
	assert refusal(loneLoadModule(false), 0, GlslTarget.Glsl430) ==
		"printGlsl: texture 'tex' has no combined sampler in this stage's binding slots";
}

test "what GLSL cannot carry is refused by name" {
	assert refusal(computeModule(), 0, GlslTarget.Glsl300es) ==
		"printGlsl: entry 'simulate' is compute, which GLSL ES 3.00 has not";
	assert refusal(vertexModule(), 0, GlslTarget.Glsl300es) ==
		"printGlsl: io 'uvL' is linear, which GLSL ES 3.00 has not";

	let feature = fragmentModule();
	feature.features = ["CUTOUT"];
	let branch = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), [single(StmtKind.Discard)]);
	branch.condition = featureOn("CUTOUT");
	prepend(feature.functions[0], branch);
	assert refusal(feature, 0, GlslTarget.Glsl430) == "printGlsl: a feature branch is still " +
		"undecided: specialize the module first";

	let signed = fragmentModule();
	prepend(signed.functions[0], update(local(7), AssignOp.Mod, i32(2.0)));
	assert refusal(signed, 0, GlslTarget.Glsl430) ==
		"printGlsl: '%' of I32: GLSL leaves a negative operand undefined";

	let sampleIndex = fragmentModule();
	sampleIndex.ios.push(io("sampleIndex", ShaderStage.Fragment, IoDirection.In, U32,
		Builtin.SampleIndex));
	prepend(sampleIndex.functions[0], assignOf(local(8), ioRead(7, U32)));
	assert refusal(sampleIndex, 0, GlslTarget.Glsl300es) ==
		"printGlsl: SampleIndex: GLSL ES 3.00 has no gl_SampleID";
	assert printed(sampleIndex, 0, [0], GlslTarget.Glsl430).includes("u = uint(gl_SampleID);\n");

	let leaving = fragmentModule();
	let choose = stmtOf(StmtKind.Switch, local(7), []);
	choose.cases = [caseOf([], true, [single(StmtKind.Break)])];
	prepend(leaving.functions[0], choose);
	assert refusal(leaving, 0, GlslTarget.Glsl430) == "printGlsl: a break inside a switch case, " +
		"which GLSL reads as leaving the switch";

	let diagonal = fragmentModule();
	prepend(diagonal.functions[0], assignOf(local(6), construct(MAT4, [f32(1.0)])));
	assert refusal(diagonal, 0, GlslTarget.Glsl430) == "printGlsl: a matrix built from one scalar";

	let integers = fragmentModule();
	prepend(integers.functions[0], assignOf(local(12), intrinsicOf(Intrinsic.Select, IVEC2,
		[local(12), local(12), construct(vectorType(ScalarKind.Bool, 2), [literal(BOOL, 1.0)])])));
	assert refusal(integers, 0, GlslTarget.Glsl430) == "printGlsl: Select of I32 by a bool " +
		"vector: GLSL mixes float vectors only";

	let effect = computeModule();
	let writer = shaderFunction("bump", [], [
		assignOf(exprOf(ExprKind.Field, F32, 1, [exprOf(ExprKind.Index, structType(0), -1,
			[exprOf(ExprKind.Resource, arrayType(structType(0), -1), 0, []), literal(U32, 0.0)])]),
			f32(1.0)),
		stmtOf(StmtKind.Return, f32(1.0), []),
	]);
	writer.result = F32;
	effect.functions.push(writer);
	prepend(effect.functions[0], stmtOf(StmtKind.Call, intrinsicOf(Intrinsic.Select, F32,
		[f32(0.0), exprOf(ExprKind.Call, F32, 1, []), literal(BOOL, 0.0)]), []));
	assert refusal(effect, 0, GlslTarget.Glsl430) == "printGlsl: 'select' prints an operand " +
		"more or fewer times than the IR evaluates it in GLSL, and one of them has an effect";

	let input = fragmentModule();
	prepend(input.functions[0], assignOf(ioRead(0, VEC4), ioRead(0, VEC4)));
	assert refusal(input, 0, GlslTarget.Glsl430) ==
		"printGlsl: io 'shade' is a stage input, which GLSL only reads";

	let reserved = blurModule();
	reserved.ios[0].name = "sample";
	assert refusal(reserved, 0, GlslTarget.Glsl430) == "printGlsl: io 'sample' is a word GLSL " +
		"holds or another name takes, and GL binds it by that name";

	let recursive = fragmentModule();
	prepend(recursive.functions[1], stmtOf(StmtKind.Call,
		exprOf(ExprKind.Call, VEC3, 1, [exprOf(ExprKind.Param, VEC3, 0, []),
			exprOf(ExprKind.Param, F32, 1, [])]), []));
	assert refusal(recursive, 0, GlslTarget.Glsl430) == "printGlsl: function 'shade' is recursive";
}

const PROBE_DIR = "out/glslProbe";

function probe(name: string, text: string): boolean {
	const _made = mkdir(PROBE_DIR);
	return writeFile(PROBE_DIR + "/" + name, text).ok;
}

test "printed modules are written for a GLSL front end" {
	const blur = blurModule();
	for (const target of TARGETS) {
		const tag = target == GlslTarget.Glsl430 ? "430" : "es";
		assert probe("blur." + tag + ".vert", printed(blur, 0, [0, 1], target));
		assert probe("blur." + tag + ".frag", printed(blur, 1, [0, 1], target));
		assert probe("vertex." + tag + ".vert", printed(perspective(vertexModule()), 0, [0], target));
		assert probe("fragment." + tag + ".frag", printed(fragmentModule(), 0, [0], target));
	}
	assert probe("vertex.430linear.vert", printed(vertexModule(), 0, [0], GlslTarget.Glsl430));
	assert probe("compute.430.comp", printed(computeModule(), 0, [0], GlslTarget.Glsl430));
}
