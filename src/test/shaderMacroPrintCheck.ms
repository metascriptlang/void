// The printers also run inside the compile-time VM: shaderBuild prints an app's program for the
// build's one target while msc compiles. Here a macro prints every target of a stage while msc
// compiles this file, the test prints it again at run time, and the two digests must agree per
// target and stage, so a printer that misbehaves only in the VM fails on its own target.

import { Node, NodeKind, stringValue } from "std/meta";
import {
	computeModule,
	programModule,
	stageSource,
	stageWords,
	targetName,
	wordsBase64,
} from "../shader/descriptor";
import { glslComputeIr, glslIr, glslLinkedIr } from "../shader/emit";
import { ShaderModule } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { litTexturedFs, litTexturedVs, shadowLitTexturedFs } from "../void3d/shader3d";
import { boolFs, boolVs } from "./shaderBoolVectorCheck";
import { cellsCs, shapeVs, twosFs } from "./shaderMatrixShapeCheck";
import { frexpFs, modfFs, partsVs } from "./shaderModfCheck";
import { liftedVs, offsetFs } from "./shaderSampleOffsetCheck";
import { signedCs, swizzledCs } from "./shaderStorageFormatCheck";
import { swapCs } from "./shaderTextureBarrierCheck";
import { loadCs } from "./shaderWorkgroupLoadCheck";

function digest(text: string): string {
	let a = 1;
	let b = 0;
	for (let i = 0; i < text.length; i++) {
		a = (a + text.charCodeAt(i)) % 65521;
		b = (b + a) % 65521;
	}
	return text.length + " " + b + " " + a;
}

function printedTarget(m: ShaderModule, target: ShaderTarget): string {
	let lines = "";
	for (let e = 0; e < m.entries.length; e++) {
		let line = "";
		if (target == ShaderTarget.Spirv) {
			const words = stageWords(m, e);
			line = words.ok ? digest(wordsBase64(words.value)) : "refused " + words.error;
		} else {
			const text = stageSource(m, e, target);
			line = text.ok ? digest(text.value) : "refused " + text.error;
		}
		lines = lines + targetName(target) + " " + e + " " + line + "\n";
	}
	return lines;
}

function printedEveryTarget(m: ShaderModule): string {
	let out = "";
	for (let i = 0; i < 6; i++) {
		let target: ShaderTarget = ShaderTarget.Wgsl;
		if (i == 1) { target = ShaderTarget.Glsl300es; }
		if (i == 2) { target = ShaderTarget.Glsl430; }
		if (i == 3) { target = ShaderTarget.Hlsl5; }
		if (i == 4) { target = ShaderTarget.Msl; }
		if (i == 5) { target = ShaderTarget.Spirv; }
		out = out + printedTarget(m, target);
	}
	return out;
}

function printedProgram(vertex: string, fragment: string, features: string): string {
	const m = programModule(vertex, fragment, features == "" ? [] : features.split(":"));
	return m.ok ? printedEveryTarget(m.value) : "module refused " + m.error + "\n";
}

function printedCompute(text: string): string {
	const m = computeModule(text, []);
	return m.ok ? printedEveryTarget(m.value) : "module refused " + m.error + "\n";
}

macro printedProgramAtCompileTime(vertex: Node, fragment: Node, features: Node): Node {
	return {
		kind: NodeKind.StringLiteral,
		line: vertex.line,
		column: vertex.column,
		value: printedProgram(stringValue(vertex), stringValue(fragment), stringValue(features)),
	};
}

macro printedComputeAtCompileTime(text: Node): Node {
	return {
		kind: NodeKind.StringLiteral,
		line: text.line,
		column: text.column,
		value: printedCompute(stringValue(text)),
	};
}

function lineAt(text: string, i: int32): string {
	const lines = text.split("\n");
	return i < lines.length ? lines[i] : "";
}

function firstDifference(atCompileTime: string, atRunTime: string): string {
	const count = Math.max(atCompileTime.split("\n").length, atRunTime.split("\n").length);
	for (let i = 0; i < count; i++) {
		const a = lineAt(atCompileTime, i);
		const b = lineAt(atRunTime, i);
		if (a != b) { return "macro: " + a + " | run time: " + b; }
	}
	return "";
}

function agree(atCompileTime: string, atRunTime: string): boolean {
	const difference = firstDifference(atCompileTime, atRunTime);
	if (difference != "") { console.log("shaderMacroPrintCheck: " + difference); }
	return difference == "";
}

function refusals(report: string): int32 {
	return report.split("\n").filter((line) => line.indexOf(" refused ") >= 0 ||
		line.startsWith("module refused")).length as int32;
}

test "a digest is the same in the macro VM and at run time" {
	assert printedCompute("") == printedComputeAtCompileTime("");
}

test "a lit textured program with PBR maps, a normal map and shadows prints alike" {
	const features = "PBR:PBR_MAPS:EMISSIVE:NORMAL_MAP:SHADOWED";
	const run = printedProgram(glslIr(litTexturedVs), glslLinkedIr(litTexturedFs, litTexturedVs),
		features);
	const macro = printedProgramAtCompileTime(glslIr(litTexturedVs),
		glslLinkedIr(litTexturedFs, litTexturedVs), "PBR:PBR_MAPS:EMISSIVE:NORMAL_MAP:SHADOWED");
	assert agree(macro, run);
	assert refusals(run) == 0 && run.split("\n").length == 13;
}

test "a shadow caster with a dissolve and a cutout prints alike" {
	const run = printedProgram(glslIr(litTexturedVs),
		glslLinkedIr(shadowLitTexturedFs, litTexturedVs), "DISSOLVE:CUTOUT");
	const macro = printedProgramAtCompileTime(glslIr(litTexturedVs),
		glslLinkedIr(shadowLitTexturedFs, litTexturedVs), "DISSOLVE:CUTOUT");
	assert agree(macro, run);
	assert refusals(run) == 0;
}

test "bool vectors, componentwise compare and select print alike" {
	const run = printedProgram(glslIr(boolVs), glslLinkedIr(boolFs, boolVs), "");
	const macro = printedProgramAtCompileTime(glslIr(boolVs), glslLinkedIr(boolFs, boolVs), "");
	assert agree(macro, run);
	assert refusals(run) == 0;
}

test "modf and frexp print alike" {
	const modf = printedProgram(glslIr(partsVs), glslLinkedIr(modfFs, partsVs), "");
	const frexp = printedProgram(glslIr(partsVs), glslLinkedIr(frexpFs, partsVs), "");
	const macroModf = printedProgramAtCompileTime(glslIr(partsVs),
		glslLinkedIr(modfFs, partsVs), "");
	const macroFrexp = printedProgramAtCompileTime(glslIr(partsVs),
		glslLinkedIr(frexpFs, partsVs), "");
	assert agree(macroModf, modf);
	assert agree(macroFrexp, frexp);
	assert refusals(modf) == 0 && refusals(frexp) == 1;
}

test "a two-row matrix in a uniform block prints alike" {
	const run = printedProgram(glslIr(shapeVs), glslLinkedIr(twosFs, shapeVs), "");
	const macro = printedProgramAtCompileTime(glslIr(shapeVs), glslLinkedIr(twosFs, shapeVs), "");
	assert agree(macro, run);
	assert refusals(run) == 0;
}

test "an offset sample prints alike" {
	const run = printedProgram(glslIr(liftedVs), glslIr(offsetFs), "");
	const macro = printedProgramAtCompileTime(glslIr(liftedVs), glslIr(offsetFs), "");
	assert agree(macro, run);
	assert refusals(run) == 0;
}

// card: no card yet; countCs of shaderComputeOpsCheck (atomics) stops irFromText in the macro VM
// with "value 19228 not in range 0 .. 3", so it has no pin here.

test "a compute stage with workgroup memory and a barrier prints alike" {
	const run = printedCompute(glslComputeIr(loadCs, [64, 1, 1])) +
		printedCompute(glslComputeIr(swapCs, [2, 1, 1]));
	const macro = printedComputeAtCompileTime(glslComputeIr(loadCs, [64, 1, 1])) +
		printedComputeAtCompileTime(glslComputeIr(swapCs, [2, 1, 1]));
	assert agree(macro, run);
	assert refusals(run) >= 1;
}

test "storage textures with texel formats and a matrix compute print alike" {
	const run = printedCompute(glslComputeIr(signedCs, [8, 1, 1])) +
		printedCompute(glslComputeIr(swizzledCs, [8, 1, 1])) +
		printedCompute(glslComputeIr(cellsCs, [4, 1, 1]));
	const macro = printedComputeAtCompileTime(glslComputeIr(signedCs, [8, 1, 1])) +
		printedComputeAtCompileTime(glslComputeIr(swizzledCs, [8, 1, 1])) +
		printedComputeAtCompileTime(glslComputeIr(cellsCs, [4, 1, 1]));
	assert agree(macro, run);
	assert refusals(run) >= 1;
}
