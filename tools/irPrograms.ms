// Writes the GPUShaderModuleDescriptor modules from the shader IR: one function per program, each
// target's source under the `when` that builds it. The stages are lowered while this tool compiles
// (glslIr); the programs are the rows of src/void3d/programKeys.txt, VOID2D_PROGRAMS and
// GPU_COPY_PROGRAMS. Beside the modules it writes each source's stages as GLSL 450 in sokol-shdc's
// dialect (void3d.glsl, pixelArt3d.glsl, shader2d.glsl, gpuCopy.glsl), which tools/shaderSlots.ms
// reads and scripts/regen-shaders.sh --oracle-shdc hands to sokol-shdc.
// Usage: msc run tools/irPrograms.ms -- <out dir> <dxbc cache dir> [--fxc <fxc path>]
//   [--reflection-only]
// --reflection-only writes a target whose printer refuses the program as its reflection with empty
// sources and the refusal above the function; without it a refusal stops the tool.
// Every printed stage lands in out/irPrograms/ for validateHlsl.sh, validateWgsl.sh and the rest.
// Each HLSL stage's DXBC is <dxbc cache dir>/<key>.dxbc, else fxc compiles it into <out dir>/dxbc/,
// else the stage has none; <out dir>/dxbc.used lists the keys the modules use. Each Metal stage's
// metallib is the same through xcrun into <metallib cache dir>/<key>.metallib, with metallib.used.

import { Buffer } from "std/core/buffer";
import { sha256 } from "std/crypto/sha256";
import { exists, mkdir, readFile, writeFile } from "std/fs";
import { argv, execFileResult, exit } from "std/process";
import { glslIr, glslLinkedIr } from "../src/shader/emit";
import {
	ProgramSource,
	descriptorSource,
	isComputeSource,
	programModule,
	programSource,
} from "../src/shader/descriptor";
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
	for (const stage of STAGES) {
		if (stage[0] == source && stage[1] == name) { return stage[2]; }
	}
	fail("no " + source + " stage '" + name + "'");
}

class Program {
	name: string = "";
	source: string = "";
	vertex: string = "";
	fragment: string = "";
	features: string[] = [];
	layout: string = "";
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
		if (columns.length != 7) {
			fail("programKeys.txt: row " + columns[0] + " is not seven columns");
		}
		let program = new Program();
		program.name = columns[0];
		program.source = columns[2] == "PIXEL_ART" ? "PIXEL_ART" : "CORE";
		program.features = columns[3] == "-" ? [] : columns[3].split(":");
		program.vertex = columns[4];
		program.fragment = columns[5];
		program.layout = columns[6];
		out.push(program);
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
		let program = new Program();
		program.name = row[0];
		program.source = source;
		program.vertex = row[1];
		program.fragment = row[2];
		return program;
	});
}

function parsed(text: string, what: string): ShaderModule {
	const result = irFromText(text);
	if (!result.ok) { fail(what + ": " + result.error); }
	return result.value;
}

function shdcText(source: string, programs: Program[]): string {
	let out = "";
	for (const stage of STAGES) {
		if (stage[0] != source) { continue; }
		const shaderModule = parsed(stage[2], source + " " + stage[1]);
		const kind = shaderModule.entries[0].stage == ShaderStage.Vertex ? "@vs " : "@fs ";
		out += kind + stage[1] + "\n" + printGlsl450(shaderModule) + "@end\n\n";
	}
	for (const program of programs) {
		out += "@program " + program.name + " " + program.vertex + " " + program.fragment + "\n";
	}
	return out;
}

function linkedModule(program: Program): ShaderModule {
	const result = programModule(
		stageText(program.source, program.vertex),
		stageText(program.source, program.fragment),
		program.features,
	);
	if (!result.ok) { fail(program.name + ": " + result.error); }
	return result.value;
}

function blockMembers(program: Program, block: string): string[] {
	const shaderModule = linkedModule(program);
	const resources = shaderModule.resources;
	for (let resourceIndex = 0; resourceIndex < resources.length; resourceIndex++) {
		const resource = resources[resourceIndex];
		if (resource.kind != ResourceKind.UniformBlock || resource.name != block) { continue; }
		const layout = uniformBlockLayout(shaderModule, resourceIndex);
		if (!layout.ok) { fail(program.name + ": " + layout.error); }
		const members = shaderModule.structs[resource.type.structIndex].members;
		let out: string[] = [];
		for (let i = 0; i < members.length; i++) {
			out.push(members[i].name + "@" + String(layout.value.offsets[i]));
		}
		return out;
	}
	fail(program.name + " has no uniform block " + block);
}

function checkFeaturesRead(program: Program): void {
	const vertexText = stageText(program.source, program.vertex);
	const fragmentText = stageText(program.source, program.fragment);
	const lines = (printGlsl450(parsed(vertexText, program.vertex)) +
		printGlsl450(parsed(fragmentText, program.fragment))).split("\n");
	for (const feature of program.features) {
		const read = lines.some((line) => line == "#ifdef " + feature ||
			(line.startsWith("#if ") && line.includes("defined(" + feature + ")")));
		if (!read) {
			fail("programKeys.txt: row " + program.name + " asks for " + feature + ", which " +
				program.vertex + " and " + program.fragment + " never read");
		}
	}
}

function programNamed(programs: Program[], name: string): Program {
	for (const program of programs) {
		if (program.name == name) { return program; }
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

class Agreement {
	layoutSlots: Map<string, string> = new Map();
	layoutOwner: Map<string, string> = new Map();
	blockShape: Map<string, string> = new Map();
	blockOwner: Map<string, string> = new Map();
}

// Every program of one vertex layout reads its attributes at the same slots, and a uniform block
// that programs share by name has one size and one slot, so one layout and one writer serve all.
function agree(
	agreement: Agreement,
	program: Program,
	shaderModule: ShaderModule,
	glsl430: ProgramSource,
): void {
	let attributes: string[] = [];
	for (const attribute of glsl430.reflection.attributes) {
		attributes.push((attribute.nativeName ?? "") + "@" + String(attribute.location));
	}
	attributes.sort();
	const slots = attributes.join(" ");
	const layoutSlots = agreement.layoutSlots.get(program.layout);
	if (layoutSlots === undefined) {
		agreement.layoutSlots.set(program.layout, slots);
		agreement.layoutOwner.set(program.layout, program.name);
	} else if (layoutSlots != slots) {
		fail(program.name + " reads layout " + program.layout + " as " + slots + ", " +
			(agreement.layoutOwner.get(program.layout) ?? "") + " as " + layoutSlots);
	}
	for (let resourceIndex = 0; resourceIndex < shaderModule.resources.length; resourceIndex++) {
		const resource = shaderModule.resources[resourceIndex];
		if (resource.kind != ResourceKind.UniformBlock) { continue; }
		const layout = uniformBlockLayout(shaderModule, resourceIndex);
		if (!layout.ok) { fail(program.name + ": " + layout.error); }
		const shape = String(layout.value.size) + " bytes at slot " + String(resource.binding);
		const held = agreement.blockShape.get(resource.name);
		if (held === undefined) {
			agreement.blockShape.set(resource.name, shape);
			agreement.blockOwner.set(resource.name, program.name);
		} else if (held != shape) {
			fail(program.name + " declares " + resource.name + " as " + shape + ", " +
				(agreement.blockOwner.get(resource.name) ?? "") + " as " + held);
		}
	}
}

// The flags src/webgpu/d3d11/d3d11.c passes D3DCompile, in fxc's spelling; keep them in step.
const FXC_FLAGS: string[] = ["-Zpc", "-O3"];

class Dxbc {
	cache: string = "";
	fresh: string = "";
	fxc: string = "";
	used: string[] = [];
	compiled: int32 = 0;
	missed: int32 = 0;
}

function bytecodeOf(
	dxbc: Dxbc,
	constants: Map<string, string>,
	code: string,
	profile: string,
	entry: string,
	what: string,
): string {
	const keyed = profile + " " + entry + " " + FXC_FLAGS.join(" ") + "\n" + code;
	const key = sha256(keyed.asBytes()).toHex();
	let path = dxbc.cache + "/" + key + ".dxbc";
	if (!exists(path)) {
		path = dxbc.fresh + "/" + key + ".dxbc";
		if (!exists(path)) {
			if (dxbc.fxc == "") {
				dxbc.missed++;
				console.log("dxbc miss " + what + " " + key + ": no fxc");
				return "[]";
			}
			const source = dxbc.fresh + "/" + key + ".hlsl";
			keep(source, code);
			const run = execFileResult(
				dxbc.fxc,
				["-nologo", "-T", profile, "-E", entry]
					.concat(FXC_FLAGS)
					.concat(["-Fo", path, source]),
			);
			if (!run.started || run.exitCode != 0) {
				fail("fxc " + profile + " refused " + what + " (" + source + "):\n" + run.output +
					run.errorOutput);
			}
			dxbc.compiled++;
		}
	}
	if (!dxbc.used.includes(key)) { dxbc.used.push(key); }
	if (!constants.has(key)) {
		const blob = readFile(path);
		if (!blob.ok) { fail("cannot read " + path); }
		constants.set(key, blob.value.toBase64());
	}
	return "shaderBytecodeFromBase64(DXBC_" + key + ")";
}

function stageBytecode(
	dxbc: Dxbc,
	constants: Map<string, string>,
	source: ProgramSource,
	name: string,
): string[] {
	if (source.refusal != "") { return isComputeSource(source) ? ["[]"] : ["[]", "[]"]; }
	const entry = source.entryPoint;
	if (isComputeSource(source)) {
		return [
			bytecodeOf(dxbc, constants, source.computeCode, "cs_5_0", entry, name + " compute"),
		];
	}
	return [
		bytecodeOf(dxbc, constants, source.vertexCode, "vs_5_0", entry, name + " vertex"),
		bytecodeOf(dxbc, constants, source.fragmentCode, "ps_5_0", entry, name + " fragment"),
	];
}

function moduleText(
	programs: Program[],
	typesPath: string,
	dispatcher: string,
	reflectionOnly: boolean,
	counts: Counts,
	dxbc: Dxbc,
): string {
	let sources: ProgramSource[][] = [];
	let agreement = new Agreement();
	for (const program of programs) {
		const shaderModule = linkedModule(program);
		counts.programs++;
		let row: ProgramSource[] = [];
		for (const language of LANGUAGES) {
			const printed = programSource(shaderModule, targetOf(language[0]));
			if (!printed.ok) { fail(program.name + " " + language[0] + ": " + printed.error); }
			if (printed.value.refusal != "") {
				const refusal = printed.value.refusal;
				if (!reflectionOnly) { fail(program.name + " " + language[0] + ": " + refusal); }
				counts.refused++;
				console.log("refused " + program.name + " " + language[0] + ": " + refusal);
			} else {
				const files = stageFiles(language[0]);
				keep("out/irPrograms/" + program.name + files[0], printed.value.vertexCode);
				keep("out/irPrograms/" + program.name + files[1], printed.value.fragmentCode);
				counts.printed += 2;
			}
			row.push(printed.value);
		}
		if (program.layout != "") {
			const glsl430 = LANGUAGES.findIndex((language) => language[0] == "glsl430");
			agree(agreement, program, shaderModule, row[glsl430]);
		}
		sources.push(row);
	}
	let text = "// Generated by tools/irPrograms.ms from the shader IR; do not edit.\n\n" +
		"import { GPUShaderModuleDescriptor } from \"" + typesPath + "\";\n" +
		"import { shaderBytecodeFromBase64 } from \"" +
		typesPath.replace("webgpu/types.ms", "shader/dxbc.ms") + "\";\n";
	for (let targetIndex = 0; targetIndex < LANGUAGES.length; targetIndex++) {
		let constants: Map<string, string> = new Map();
		let functions: string[] = [];
		for (let i = 0; i < programs.length; i++) {
			const stageSource = sources[i][targetIndex];
			const bytecode = LANGUAGES[targetIndex][0] == "hlsl5" ?
				stageBytecode(dxbc, constants, stageSource, programs[i].name) :
				isComputeSource(stageSource) ? ["[]"] : ["[]", "[]"];
			functions.push(descriptorSource(programs[i].name, stageSource, bytecode));
		}
		let blobs = "";
		for (const [key, base64] of constants) {
			blobs += "\tconst " + (LANGUAGES[t][0] == "hlsl5" ? "DXBC_" : "METALLIB_") + key + " = \"" + base64 + "\";\n";
		}
		text += (targetIndex == 0 ? "\nwhen (" : " else when (") + LANGUAGES[targetIndex][1] +
			") {\n" +
			(blobs != "" ? blobs + "\n" : "") + functions.join("\n") + "}";
	}
	if (dispatcher != "") {
		let arms = "";
		for (let i = 0; i < programs.length - 1; i++) {
			arms += "\t\t" + String(i) + " => " + programs[i].name + "ShaderModule(),\n";
		}
		arms += "\t\t_ => " + programs[programs.length - 1].name + "ShaderModule(),\n";
		text += "\n\nexport function " + dispatcher +
			"(index: int32): GPUShaderModuleDescriptor {\n" +
			"\tif (index < 0 || index >= " + String(programs.length) + ") {\n" +
			"\t\tconsole.error(\"" + dispatcher + ": no program at index \" + String(index));\n" +
			"\t\tunreachable;\n\t}\n" +
			"\treturn match (index) {\n" + arms + "\t};\n}";
	}
	return text + "\n";
}

function main(): void {
	const reflectionOnly = argv.includes("--reflection-only");
	let dirs: string[] = [];
	let dxbc = new Dxbc();
	let metallib = new Metallib();
	const args = argv.slice(1);
	for (let i = 0; i < args.length; i++) {
		if (args[i] == "--fxc" && i + 1 < args.length) {
			i++;
			dxbc.fxc = args[i];
		} else if (args[i] != "--reflection-only" && args[i] != "--") {
			dirs.push(args[i]);
		}
	}
	if (dirs.length != 3) {
		fail("usage: irPrograms <out dir> <dxbc cache dir> <metallib cache dir> [--fxc <fxc path>] [--reflection-only]");
	}
	const out = dirs[0];
	dxbc.cache = dirs[1];
	dxbc.fresh = out + "/dxbc";
	metallib.cache = dirs[2];
	metallib.fresh = out + "/metallib";
	const _out = mkdir("out");
	const _probes = mkdir("out/irPrograms");
	const _dir = mkdir(out);
	const _fresh = mkdir(dxbc.fresh);
	const _metalFresh = mkdir(metallib.fresh);
	let counts = new Counts();
	const keyed = keyedPrograms();
	const void2d = listedPrograms(VOID2D_PROGRAMS, "VOID2D");
	const gpuCopy = listedPrograms(GPU_COPY_PROGRAMS, "GPU_COPY");
	for (const program of keyed) { checkFeaturesRead(program); }
	checkBlockHead(keyed);
	keep(
		out + "/programModules.ms",
		moduleText(keyed, "../webgpu/types.ms", "gpu3dShaderModule", reflectionOnly, counts, dxbc),
	);
	keep(
		out + "/shader2dModules.ms",
		moduleText(void2d, "../webgpu/types.ms", "", reflectionOnly, counts, dxbc),
	);
	keep(
		out + "/gpuCopyModules.ms",
		moduleText(gpuCopy, "../../src/webgpu/types.ms", "", reflectionOnly, counts, dxbc),
	);
	keep(out + "/void3d.glsl", shdcText("CORE", []));
	keep(out + "/pixelArt3d.glsl", shdcText("PIXEL_ART", []));
	keep(out + "/shader2d.glsl", shdcText("VOID2D", void2d));
	keep(out + "/gpuCopy.glsl", shdcText("GPU_COPY", gpuCopy));
	keep(out + "/dxbc.used", dxbc.used.join("\n") + "\n");
	keep(out + "/metallib.used", metallib.used.join("\n") + "\n");
	console.log("irPrograms: " + String(counts.programs) + " programs, " + String(counts.printed) +
		" stages printed, " + String(counts.refused) + " target sources refused, " +
		String(dxbc.used.length) + " DXBC blobs used, " + String(dxbc.compiled) +
		" compiled by fxc, " + String(dxbc.missed) + " missed");
}

main();
