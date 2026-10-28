// Prints one entry of a lowered module for a target and writes the text where the validators read:
// out/<target>Probe/ for scripts/validateWgsl.sh, scripts/validateHlsl.sh, naga and spirv-val.

import { Buffer } from "std/core/buffer";
import { mkdir, writeFile } from "std/fs";
import { stageSource, stageWords, wordsBase64 } from "../shader/descriptor";
import { ShaderModule } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";

function probePath(target: ShaderTarget, name: string, stage: string): string {
	const hlsl = stage == "comp" ? "cs" : stage == "frag" ? "ps" : "vs";
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + "." + hlsl + ".hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430." + stage,
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es." + stage,
		ShaderTarget.Msl => "out/mslProbe/" + name + ".metal",
		ShaderTarget.Spirv => { throw new Error("probePath: SPIR-V is words, see printedSpirv"); },
	};
}

// The text of entry `entry` for `target`, or the printer's refusal; `stage` is comp, frag or vert.
export function printedProbe(
	m: ShaderModule,
	entry: int32,
	target: ShaderTarget,
	name: string,
	stage: string,
): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { return text.error; }
	const path = probePath(target, name, stage);
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

// The words of entry `entry` as SPIR-V, written to out/spirvProbe/<name>.spv, or the printer's
// refusal as a message.
export function printedSpirv(m: ShaderModule, entry: int32, name: string): string {
	const words = stageWords(m, entry);
	if (!words.ok) { return words.error; }
	const _out = mkdir("out");
	const _folder = mkdir("out/spirvProbe");
	const _written = writeFile("out/spirvProbe/" + name + ".spv",
		Buffer.fromString(wordsBase64(words.value), "base64"));
	return "";
}
