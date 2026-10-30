// @builtin(fragDepth) authored in MetaScript: the entry runs on the CPU, is pinned as GLSL and
// printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh and the GLSL validator.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { Vec2f, Vec4f, builtin, location, vec4f } from "../shader/std";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";

export struct Pixel {
	@builtin(position) position: Vec4f;
}

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
}

export struct DepthOut {
	@location(0) color: Vec4f;
	@builtin(fragDepth) depth: float32;
}

export function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function deepFs(input: Pixel): DepthOut {
	return { color: vec4f(1.0, 0.0, 0.0, 1.0), depth: input.position.z * 0.5 };
}

test "a fragment entry writes @builtin(fragDepth) next to its colour" {
	const out = deepFs({ position: vec4f(0.0, 0.0, 0.8, 1.0) });
	assert out.depth == 0.4 && out.color.x == 1.0;
	assert glsl(deepFs) ==
		"layout(location=0) out vec4 color;\n" +
		"void main() {\n" +
		"    color = vec4(1.0, 0.0, 0.0, 1.0);\n" +
		"    gl_FragDepth = (gl_FragCoord.z * 0.5);\n" +
		"    return;\n" +
		"}\n";
}

function deepOf(): ShaderModule {
	const m = programModule(glslIr(plainVs), glslIr(deepFs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "every target writes the fragment depth" {
	const m = deepOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "deep");
	assert wgsl.includes("@builtin(frag_depth) depth : f32,\n") &&
		wgsl.includes("  return main_out(color, depth);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "deep");
	assert hlsl.includes("float depth : SV_Depth;\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		assert printedFor(m, 1, target,
			"deep").includes("    gl_FragDepth = gl_FragCoord.z * 0.5;\n");
	}
	assert printedFor(m, 1, ShaderTarget.Msl, "deep").includes("float depth [[depth(any)]];\n");
}

function probePath(name: string, target: ShaderTarget, stage: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + stage + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + "." + (stage == "Vs" ? "vs" : "ps") +
		".hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430." +
		(stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es." +
		(stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Msl => "out/mslProbe/" + name + stage + ".metal",
		ShaderTarget.Spirv => "out/spirvProbe/" + name + stage + ".spv",
	};
}

function printedFor(m: ShaderModule, entry: int32, target: ShaderTarget, name: string): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { return text.error; }
	const path = probePath(name, target, entry == 0 ? "Vs" : "Fs");
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

test "SPIR-V writes the fragment depth through BuiltIn FragDepth with DepthReplacing" {
	const _vertex = spirvProbe(deepOf(), 0, "deep");
	const fs = spirvProbe(deepOf(), 1, "deep");
	assert fs.filter(i => opcodeOf(i) == 16 && i[2] == 12).length == 1;
	assert fs.filter(i => opcodeOf(i) == 71 && i[2] == 11 && i[3] == 22).length == 1;
}
