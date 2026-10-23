// Writes the GPUShaderModuleDescriptor modules from the shader IR: one function per program, each
// target's source under the `when` that builds it. The stages are lowered while this tool compiles
// (glslIr); the programs are the rows of src/void3d/programKeys.txt, VOID2D_PROGRAMS and
// GPU_COPY_PROGRAMS. Beside the modules it writes each source's stages as GLSL 450 in sokol-shdc's
// dialect (void3d.glsl, pixelArt3d.glsl, shader2d.glsl, gpuCopy.glsl), which tools/shaderSlots.ms
// reads and scripts/regen-shaders.sh --oracle-shdc hands to sokol-shdc.
// Usage: msc run tools/irPrograms.ms -- <out dir> [--reflection-only]
// --reflection-only writes a target whose printer refuses the program as its reflection with empty
// sources and the refusal above the function; without it a refusal stops the tool.
// Every printed stage lands in out/irPrograms/ for validateHlsl.sh, validateWgsl.sh and the rest.

import { mkdir, readFile, writeFile } from "std/fs";
import { argv, exit } from "std/process";
import { glslIr, glslLinkedIr } from "../src/shader/emit";
import { ProgramSource, descriptorSource, programModule, programSource } from "../src/shader/descriptor";
import { irFromText } from "../src/shader/irText";
import { ResourceKind, ShaderModule, ShaderStage } from "../src/shader/ir";
import { ShaderTarget, uniformBlockLayout } from "../src/shader/layout";
import { printGlsl450 } from "../src/shader/printGlsl450";
import {
	billboardFs,
	billboardVs,
	copyFs,
	litFs,
	litTexturedFs,
	litTexturedVs,
	litVs,
	particleFs,
	particleVs,
	particleVisualPixelArtVs,
	particleVisualVs,
	shadowLitFs,
	shadowLitTexturedFs,
	shadowUnlitTexturedFs,
	unlitTexturedFs,
	unlitTexturedVs,
} from "../src/void3d/shader3d";
import {
	bloomDownsampleFirstFs,
	bloomDownsampleFs,
	bloomUpsampleFs,
	fullscreenVs,
	outlineMaskFs,
	outlineMixFs,
	outlineWidthFs,
	toneMapFs,
} from "../src/void3d/post3d";
import {
	blitFs,
	pixelArtBillboardFs,
	pixelArtBillboardVs,
	pixelArtLitFs,
	pixelArtLitTexturedFs,
	pixelArtLitTexturedVs,
	pixelArtLitVs,
	pixelArtParticleFs,
	pixelArtParticleVs,
	pixelArtUnlitTexturedFs,
	pixelArtUnlitTexturedVs,
	postFs,
} from "../src/void3d/pixelArt3d";
import {
	blurFs,
	blurVs,
	fs,
	spriteFs,
	spriteVs,
	uiFs,
	uiVs,
	vs,
} from "../src/void2d/shader2d";
import { gpuCopyFs } from "../tests/integration/gpuCopyShader";

// [source, stage name as the program lines give it, lowered stage]; the names are those of
// genShaders.ms, genShadersPixelArt.ms, genShaders2d.ms and genShadersGpuCopy.ms.
const STAGES: string[][] = [
	["CORE", "fullscreenVs", glslIr(fullscreenVs)],
	["CORE", "copyFs", glslIr(copyFs)],
	["CORE", "toneMapFs", glslIr(toneMapFs)],
	["CORE", "bloomDownsampleFirstFs", glslIr(bloomDownsampleFirstFs)],
	["CORE", "bloomDownsampleFs", glslIr(bloomDownsampleFs)],
	["CORE", "bloomUpsampleFs", glslIr(bloomUpsampleFs)],
	["CORE", "outlineMaskFs", glslIr(outlineMaskFs)],
	["CORE", "outlineMixFs", glslIr(outlineMixFs)],
	["CORE", "outlineWidthFs", glslIr(outlineWidthFs)],
	["CORE", "particleVisualVs", glslIr(particleVisualVs)],
	["CORE", "particleVs", glslIr(particleVs)],
	["CORE", "particleFs", glslLinkedIr(particleFs, particleVs)],
	["CORE", "billboardVs", glslIr(billboardVs)],
	["CORE", "billboardFs", glslLinkedIr(billboardFs, billboardVs)],
	["CORE", "litVs", glslIr(litVs)],
	["CORE", "litFs", glslLinkedIr(litFs, litVs)],
	["CORE", "shadowLitFs", glslLinkedIr(shadowLitFs, litVs)],
	["CORE", "litTexturedVs", glslIr(litTexturedVs)],
	["CORE", "litTexturedFs", glslLinkedIr(litTexturedFs, litTexturedVs)],
	["CORE", "shadowLitTexturedFs", glslLinkedIr(shadowLitTexturedFs, litTexturedVs)],
	["CORE", "unlitTexturedVs", glslIr(unlitTexturedVs)],
	["CORE", "unlitTexturedFs", glslLinkedIr(unlitTexturedFs, unlitTexturedVs)],
	["CORE", "shadowUnlitTexturedFs", glslLinkedIr(shadowUnlitTexturedFs, unlitTexturedVs)],
	["PIXEL_ART", "fullscreenVs", glslIr(fullscreenVs)],
	["PIXEL_ART", "postFs", glslIr(postFs)],
	["PIXEL_ART", "blitFs", glslIr(blitFs)],
	["PIXEL_ART", "particleVisualPixelArtVs", glslIr(particleVisualPixelArtVs)],
	["PIXEL_ART", "billboardVs", glslIr(pixelArtBillboardVs)],
	["PIXEL_ART", "billboardFs", glslLinkedIr(pixelArtBillboardFs, pixelArtBillboardVs)],
	["PIXEL_ART", "particleVs", glslIr(pixelArtParticleVs)],
	["PIXEL_ART", "particleFs", glslLinkedIr(pixelArtParticleFs, pixelArtParticleVs)],
	["PIXEL_ART", "litVs", glslIr(pixelArtLitVs)],
	["PIXEL_ART", "litFs", glslLinkedIr(pixelArtLitFs, pixelArtLitVs)],
	["PIXEL_ART", "litTexturedVs", glslIr(pixelArtLitTexturedVs)],
	["PIXEL_ART", "litTexturedFs", glslLinkedIr(pixelArtLitTexturedFs, pixelArtLitTexturedVs)],
	["PIXEL_ART", "unlitTexturedVs", glslIr(pixelArtUnlitTexturedVs)],
	["PIXEL_ART", "unlitTexturedFs", glslLinkedIr(pixelArtUnlitTexturedFs,
		pixelArtUnlitTexturedVs)],
	["VOID2D", "vs", glslIr(vs)],
	["VOID2D", "fs", glslLinkedIr(fs, vs)],
	["VOID2D", "spriteVs", glslIr(spriteVs)],
	["VOID2D", "spriteFs", glslLinkedIr(spriteFs, spriteVs)],
	["VOID2D", "uiVs", glslIr(uiVs)],
	["VOID2D", "uiFs", glslLinkedIr(uiFs, uiVs)],
	["VOID2D", "blurVs", glslIr(blurVs)],
	["VOID2D", "blurFs", glslLinkedIr(blurFs, blurVs)],
	["GPU_COPY", "gpuCopyVs", glslIr(fullscreenVs)],
	["GPU_COPY", "gpuCopyFs", glslIr(gpuCopyFs)],
];

// Each shdc language, the `when` that compiles it and the IR target that prints it, in
// tools/shaderTables.ms's order.
const LANGUAGES: string[][] = [
	["wgsl", "webgpu"],
	["glsl300es", "webgl2 || android"],
	["metal_ios", "ios"],
	["metal_macos", "macos"],
	["glsl430", "voidGlCore || linux"],
	["hlsl5", "windows"],
];

function targetOf(language: string): ShaderTarget {
	return match (language) {
		"wgsl" => ShaderTarget.Wgsl,
		"glsl300es" => ShaderTarget.Glsl300es,
		"glsl430" => ShaderTarget.Glsl430,
		"hlsl5" => ShaderTarget.Hlsl5,
		_ => ShaderTarget.Msl,
	};
}

// The file suffixes of a language's vertex and fragment stage, as the validators read them.
function stageFiles(language: string): string[] {
	return match (language) {
		"wgsl" => [".vs.wgsl", ".fs.wgsl"],
		"glsl300es" => [".es.vert", ".es.frag"],
		"glsl430" => [".430.vert", ".430.frag"],
		"hlsl5" => [".vs.hlsl", ".ps.hlsl"],
		_ => ["." + language + ".vs.metal", "." + language + ".fs.metal"],
	};
}

function fail(message: string): never {
	console.error("irPrograms: " + message);
	exit(1);
}

function stageText(source: string, name: string): string {
	for (const s of STAGES) {
		if (s[0] == source && s[1] == name) { return s[2]; }
	}
	fail("no " + source + " stage '" + name + "'");
}

class Program {
	name: string = "";
	source: string = "";
	vertex: string = "";
	fragment: string = "";
	features: string[] = [];
}

function lines(path: string): string[] {
	const text = readFile(path);
	if (!text.ok) { fail("cannot read " + path); }
	return text.value.replaceAll("\r", "").split("\n");
}

function keyedPrograms(): Program[] {
	let out: Program[] = [];
	for (const line of lines("src/void3d/programKeys.txt")) {
		const columns = line.trim().split(" ").filter((c) => c != "");
		if (columns.length == 0 || columns[0].startsWith("#")) { continue; }
		if (columns.length != 7) { fail("programKeys.txt: row " + columns[0] + " is not seven columns"); }
		let p = new Program();
		p.name = columns[0];
		p.source = columns[2] == "PIXEL_ART" ? "PIXEL_ART" : "CORE";
		p.features = columns[3] == "-" ? [] : columns[3].split(":");
		p.vertex = columns[4];
		p.fragment = columns[5];
		out.push(p);
	}
	return out;
}

// [program, vertex stage, fragment stage], in name order, as sokol-shdc kept its programs.
const VOID2D_PROGRAMS: string[][] = [
	["blur", "blurVs", "blurFs"],
	["sprite", "spriteVs", "spriteFs"],
	["ui", "uiVs", "uiFs"],
	["void2d", "vs", "fs"],
];
const GPU_COPY_PROGRAMS: string[][] = [["gpuCopy", "gpuCopyVs", "gpuCopyFs"]];

function listedPrograms(rows: string[][], source: string): Program[] {
	return rows.map((row) => {
		let p = new Program();
		p.name = row[0];
		p.source = source;
		p.vertex = row[1];
		p.fragment = row[2];
		return p;
	});
}

function parsed(text: string, what: string): ShaderModule {
	const m = irFromText(text);
	if (!m.ok) { fail(what + ": " + m.error); }
	return m.value;
}

function shdcText(source: string, programs: Program[]): string {
	let out = "";
	for (const s of STAGES) {
		if (s[0] != source) { continue; }
		const m = parsed(s[2], source + " " + s[1]);
		const kind = m.entries[0].stage == ShaderStage.Vertex ? "@vs " : "@fs ";
		out += kind + s[1] + "\n" + printGlsl450(m) + "@end\n\n";
	}
	for (const p of programs) {
		out += "@program " + p.name + " " + p.vertex + " " + p.fragment + "\n";
	}
	return out;
}

function blockMembers(p: Program, block: string): string[] {
	const m = programModule(stageText(p.source, p.vertex), stageText(p.source, p.fragment),
		p.features);
	if (!m.ok) { fail(p.name + ": " + m.error); }
	for (let r = 0; r < m.value.resources.length; r++) {
		const resource = m.value.resources[r];
		if (resource.kind != ResourceKind.UniformBlock || resource.name != block) { continue; }
		const layout = uniformBlockLayout(m.value, r);
		if (!layout.ok) { fail(p.name + ": " + layout.error); }
		const members = m.value.structs[resource.type.structIndex].members;
		let out: string[] = [];
		for (let i = 0; i < members.length; i++) {
			out.push(members[i].name + "@" + String(layout.value.offsets[i]));
		}
		return out;
	}
	fail(p.name + " has no uniform block " + block);
}


function checkFeaturesRead(p: Program): void {
	const text = printGlsl450(parsed(stageText(p.source, p.vertex), p.vertex)) +
		printGlsl450(parsed(stageText(p.source, p.fragment), p.fragment));
	for (const f of p.features) {
		if (!text.split("\n").includes("#ifdef " + f)) {
			fail("programKeys.txt: row " + p.name + " asks for " + f + ", which " + p.vertex + " and " +
				p.fragment + " never read");
		}
	}
}
function programNamed(programs: Program[], name: string): Program {
	for (const p of programs) {
		if (p.name == name) { return p; }
	}
	fail("programKeys.txt has no row " + name);
}

// A dissolve caster writes the head of an emissive dissolve's block (src/void3d/draw.ms
// applyBlockHead), so that block is the caster's, member for member, and then emissive.
function checkBlockHead(programs: Program[]): void {
	const caster = blockMembers(programNamed(programs, "shadowLitTexturedDissolve"),
		"movingMaterialParams");
	const emissive = blockMembers(programNamed(programs, "litTexturedDissolveEmissive"),
		"movingEmissiveMaterialParams");
	const head = caster.length > 0 ? Number(caster[caster.length - 1].split("@")[1]) + 16 : 0;
	const expected = caster.concat(["emissive@" + String(head)]);
	if (emissive.join(" ") != expected.join(" ")) {
		fail("movingEmissiveMaterialParams (" + emissive.join(" ") +
			") must be movingMaterialParams (" + caster.join(" ") + ") and then emissive");
	}
}

class Counts {
	programs: int32 = 0;
	refused: int32 = 0;
	printed: int32 = 0;
}

function keep(path: string, text: string): void {
	if (!writeFile(path, text).ok) { fail("cannot write " + path); }
}

function moduleText(programs: Program[], typesPath: string, dispatcher: string,
	reflectionOnly: boolean, counts: Counts): string {
	let sources: ProgramSource[][] = [];
	for (const p of programs) {
		const m = programModule(stageText(p.source, p.vertex), stageText(p.source, p.fragment),
			p.features);
		if (!m.ok) { fail(p.name + ": " + m.error); }
		counts.programs++;
		let row: ProgramSource[] = [];
		for (const language of LANGUAGES) {
			const s = programSource(m.value, targetOf(language[0]));
			if (!s.ok) { fail(p.name + " " + language[0] + ": " + s.error); }
			if (s.value.refusal != "") {
				if (!reflectionOnly) { fail(p.name + " " + language[0] + ": " + s.value.refusal); }
				counts.refused++;
				console.log("refused " + p.name + " " + language[0] + ": " + s.value.refusal);
			} else {
				const files = stageFiles(language[0]);
				keep("out/irPrograms/" + p.name + files[0], s.value.vertexCode);
				keep("out/irPrograms/" + p.name + files[1], s.value.fragmentCode);
				counts.printed += 2;
			}
			row.push(s.value);
		}
		sources.push(row);
	}
	let text = "// Generated by tools/irPrograms.ms from the shader IR; do not edit.\n\n" +
		"import { GPUShaderModuleDescriptor } from \"" + typesPath + "\";\n";
	for (let t = 0; t < LANGUAGES.length; t++) {
		let functions: string[] = [];
		for (let i = 0; i < programs.length; i++) {
			functions.push(descriptorSource(programs[i].name, sources[i][t]));
		}
		text += (t == 0 ? "\nwhen (" : " else when (") + LANGUAGES[t][1] + ") {\n" +
			functions.join("\n") + "}";
	}
	if (dispatcher != "") {
		let arms = "";
		for (let i = 0; i < programs.length - 1; i++) {
			arms += "\t\t" + String(i) + " => " + programs[i].name + "ShaderModule(),\n";
		}
		arms += "\t\t_ => " + programs[programs.length - 1].name + "ShaderModule(),\n";
		text += "\n\nexport function " + dispatcher + "(index: int32): GPUShaderModuleDescriptor {\n" +
			"\tif (index < 0 || index >= " + String(programs.length) + ") {\n" +
			"\t\tconsole.error(\"" + dispatcher + ": no program at index \" + String(index));\n" +
			"\t\tunreachable;\n\t}\n" +
			"\treturn match (index) {\n" + arms + "\t};\n}";
	}
	return text + "\n";
}

function main(): void {
	const reflectionOnly = argv.includes("--reflection-only");
	const dirs = argv.slice(1).filter((a) => a != "--reflection-only" && a != "--");
	if (dirs.length != 1) { fail("usage: irPrograms <out dir> [--reflection-only]"); }
	const out = dirs[0];
	const _out = mkdir("out");
	const _probes = mkdir("out/irPrograms");
	const _dir = mkdir(out);
	let counts = new Counts();
	const keyed = keyedPrograms();
	const void2d = listedPrograms(VOID2D_PROGRAMS, "VOID2D");
	const gpuCopy = listedPrograms(GPU_COPY_PROGRAMS, "GPU_COPY");
	for (const p of keyed) { checkFeaturesRead(p); }
	checkBlockHead(keyed);
	keep(out + "/programModules.ms", moduleText(keyed, "../webgpu/types.ms",
		"gpu3dShaderModule", reflectionOnly, counts));
	keep(out + "/shader2dModules.ms", moduleText(void2d, "../webgpu/types.ms", "", reflectionOnly,
		counts));
	keep(out + "/gpuCopyModules.ms", moduleText(gpuCopy, "../../src/webgpu/types.ms", "",
		reflectionOnly, counts));
	keep(out + "/void3d.glsl", shdcText("CORE", []));
	keep(out + "/pixelArt3d.glsl", shdcText("PIXEL_ART", []));
	keep(out + "/shader2d.glsl", shdcText("VOID2D", void2d));
	keep(out + "/gpuCopy.glsl", shdcText("GPU_COPY", gpuCopy));
	console.log("irPrograms: " + String(counts.programs) + " programs, " + String(counts.printed) +
		" stages printed, " + String(counts.refused) + " target sources refused");
}

main();
