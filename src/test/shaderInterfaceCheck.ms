// The stage interface glsl reads from a signature: attributes, varyings, bindings, a program key
// and several outputs, each declaration gated by the features that read it.

import { glsl, glslLinked } from "../shader/emit";
import {
	Sampler, Texture2d, Vec2f, Vec4f, binding, builtin, feature, location, sampleType, samplerType,
	textureSample, discard,
} from "../shader/std";

struct Attributes {
	position: Vec4f;
	texcoord: Vec2f;
}

struct Varyings {
	@builtin(position) clip: Vec4f;
	uv: Vec2f;
	tint: Vec4f;
}

struct ViewParams {
	scale: Vec4f;
	lights: Vec4f[4];
}

struct ShadowParams {
	shadow: Vec4f;
}

struct ProbeBindings {
	@binding(0) viewParams: ViewParams;
	@binding(5) shadowParams: ShadowParams;
	@binding(4) @sampleType(unfilterable_float) shadowMap: Texture2d;
	@binding(2) @samplerType(nonfiltering) shadowSampler: Sampler;
}

struct ProbeKey {
	@feature(SHADOWED) shadowed: boolean;
	@feature(NORMAL_MRT) normalMrt: boolean;
}

struct ProbeOutput {
	@location(0) color: Vec4f;
	@location(1) @feature(NORMAL_MRT) normal: Vec4f;
}

function probeVs(input: Attributes, b: ProbeBindings): Varyings {
	return { clip: input.position, uv: input.texcoord, tint: b.viewParams.scale };
}

function probeFs(input: Varyings, b: ProbeBindings, key: ProbeKey): ProbeOutput {
	const shade = input.tint;
	if (key.shadowed) {
		const s = textureSample(b.shadowMap, b.shadowSampler, input.uv);
		return { color: s, normal: b.shadowParams.shadow };
	}
	return { color: shade, normal: input.tint };
}


struct CutoutBindings {
	@binding(3) materialParams: ShadowParams;
}

struct CutoutKey {
	@feature(CUTOUT) cutout: boolean;
}

function cutoutFs(input: Varyings, b: CutoutBindings, key: CutoutKey): void {
	if (key.cutout) {
		if (input.tint.w < b.materialParams.shadow.w) {
			discard();
		}
	}
}

test "a vertex entry declares its attributes, its varyings and the blocks it reads" {
	assert glsl(probeVs) ==
		"layout(binding=0) uniform viewParams {\n" +
		"    vec4 scale;\n" +
		"    vec4 lights[4];\n" +
		"};\n" +
		"in vec4 position;\n" +
		"in vec2 texcoord;\n" +
		"out vec2 uv;\n" +
		"out vec4 tint;\n" +
		"void main() {\n" +
		"    gl_Position = position;\n" +
		"    uv = texcoord;\n" +
		"    tint = scale;\n" +
		"    return;\n" +
		"}\n";
}

test "a fragment entry declares each binding and output under the features that read it" {
	assert glslLinked(probeFs, probeVs) ==
		"#if defined(SHADOWED) && defined(NORMAL_MRT)\n" +
		"layout(binding=5) uniform shadowParams {\n" +
		"    vec4 shadow;\n" +
		"};\n" +
		"#endif\n" +
		"#ifdef SHADOWED\n" +
		"@image_sample_type shadowMap unfilterable_float\n" +
		"layout(binding=4) uniform texture2D shadowMap;\n" +
		"#endif\n" +
		"#ifdef SHADOWED\n" +
		"@sampler_type shadowSampler nonfiltering\n" +
		"layout(binding=2) uniform sampler shadowSampler;\n" +
		"#endif\n" +
		"in vec2 uv;\n" +
		"in vec4 tint;\n" +
		"layout(location=0) out vec4 color;\n" +
		"#ifdef NORMAL_MRT\n" +
		"layout(location=1) out vec4 normal;\n" +
		"#endif\n" +
		"void main() {\n" +
		"    vec4 shade = tint;\n" +
		"#ifdef SHADOWED\n" +
		"    vec4 s = texture(sampler2D(shadowMap, shadowSampler), uv);\n" +
		"    color = s;\n" +
		"#ifdef NORMAL_MRT\n" +
		"    normal = shadow;\n" +
		"#endif\n" +
		"    return;\n" +
		"#endif\n" +
		"    color = shade;\n" +
		"#ifdef NORMAL_MRT\n" +
		"    normal = tint;\n" +
		"#endif\n" +
		"    return;\n" +
		"}\n";
}

test "a fragment entry without outputs discards under its feature" {
	assert glslLinked(cutoutFs, probeVs) ==
		"#ifdef CUTOUT\n" +
		"layout(binding=3) uniform materialParams {\n" +
		"    vec4 shadow;\n" +
		"};\n" +
		"#endif\n" +
		"in vec2 uv;\n" +
		"in vec4 tint;\n" +
		"void main() {\n" +
		"#ifdef CUTOUT\n" +
		"    if (tint.w < shadow.w) {\n" +
		"        discard;\n" +
		"    }\n" +
		"#endif\n" +
		"}\n";
}

struct MaterialParams {
	material: Vec4f;
}

struct BranchBindings {
	@binding(0) viewParams: ViewParams;
	@binding(5) shadowParams: ShadowParams;
	@binding(3) materialParams: MaterialParams;
}

function branchFs(input: Varyings, b: BranchBindings, key: ProbeKey): Vec4f {
	let color = input.tint;
	if (key.shadowed) {
		color = b.viewParams.scale;
		if (key.normalMrt) {
			color = b.shadowParams.shadow;
		} else {
			color = color + b.shadowParams.shadow;
		}
	} else {
		color = b.viewParams.scale + b.materialParams.material;
		if (key.normalMrt) {
			color = b.materialParams.material;
		}
	}
	return color;
}

test "a read under a feature and its negation, or under an absorbed term, gates simply" {
	const source: string = glslLinked(branchFs, probeVs);
	assert source.startsWith("layout(binding=0) uniform viewParams {\n");
	assert source.includes("#ifdef SHADOWED\nlayout(binding=5) uniform shadowParams {\n");
	assert source.includes("#ifndef SHADOWED\nlayout(binding=3) uniform materialParams {\n");
	assert !source.includes("|| !defined(SHADOWED)") && !source.includes("NORMAL_MRT) ||");
}
