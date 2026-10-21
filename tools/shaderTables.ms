// Turns sokol-shdc's `-f bare_yaml` output into a MetaScript module of GPUShaderModuleDescriptor
// functions, one per program, each backend's sources under the `when` that builds it (docs/GPU.md).
// Usage: msc run tools/shaderTables.ms -- <reflection.yaml> <output.ms> <types import path>

import { readFile, writeFile } from "std/fs";
import { argv, exit } from "std/process";

class Yaml {
	scalars: Map<string, string> = new Map();
	maps: Map<string, Yaml> = new Map();
	lists: Map<string, Yaml[]> = new Map();
}

function indentOf(line: string): int32 {
	let n = 0;
	while (n < line.length && line[n] == " ") { n++; }
	return n;
}

class Parser {
	lines: string[];
	at: int32 = 0;
	constructor(lines: string[]) { this.lines = lines; }

	map(indent: int32): Yaml {
		const node = new Yaml();
		while (this.at < this.lines.length && indentOf(this.lines[this.at]) == indent) {
			const text = this.lines[this.at].trim();
			if (text == "-") { break; }
			const colon = text.indexOf(":");
			if (colon < 0) { fail("no key in yaml line '" + text + "'"); }
			const key = text.substring(0, colon);
			const value = text.substring(colon + 1).trim();
			this.at++;
			if (value != "") {
				node.scalars.set(key, value);
				continue;
			}
			if (this.at < this.lines.length && this.lines[this.at].trim() == "-") {
				const items: Yaml[] = [];
				const dash = indentOf(this.lines[this.at]);
				while (this.at < this.lines.length && indentOf(this.lines[this.at]) == dash &&
					this.lines[this.at].trim() == "-") {
					this.at++;
					items.push(this.map(indentOf(this.lines[this.at])));
				}
				node.lists.set(key, items);
			} else {
				node.maps.set(key, this.map(indentOf(this.lines[this.at])));
			}
		}
		return node;
	}
}

function fail(message: string): never {
	console.error("shaderTables: " + message);
	exit(1);
}

function scalar(node: Yaml, key: string): string {
	const value = node.scalars.get(key);
	if (value == null) { fail("missing '" + key + "'"); }
	return value;
}

function scalarOr(node: Yaml, key: string, fallback: string): string {
	return node.scalars.get(key) ?? fallback;
}

function child(node: Yaml, key: string): Yaml {
	const value = node.maps.get(key);
	if (value == null) { fail("missing map '" + key + "'"); }
	return value;
}

function list(node: Yaml, key: string): Yaml[] {
	return node.lists.get(key) ?? [];
}

function quoted(text: string): string {
	let out = "\"";
	for (let i = 0; i < text.length; i++) {
		const c = text[i];
		if (c == "\\") { out += "\\\\"; }
		else if (c == "\"") { out += "\\\""; }
		else if (c == "\n") { out += "\\n"; }
		else if (c == "\t") { out += "\\t"; }
		else if (c != "\r") { out += c; }
	}
	return out + "\"";
}

function source(stage: Yaml): string {
	const path = scalar(stage, "path");
	const text = readFile(path);
	if (!text.ok) { fail("cannot read " + path); }
	return quoted(text.value);
}

function nativeSlot(node: Yaml, keys: string[]): string {
	for (const key of keys) {
		const value = node.scalars.get(key);
		if (value != null) { return value; }
	}
	return "-1";
}

function bindingEntry(group: string, binding: string, kind: string, stage: string, size: string,
	sampleType: string, samplerType: string, slot: string, name: string, textureBinding: string): string {
	return "{ group: " + group + ", binding: " + binding + ", kind: \"" + kind + "\", stage: \"" + stage +
		"\", size: " + size +
		(sampleType != "" ? ", sampleType: \"" + sampleType + "\"" : "") +
		(samplerType != "" ? ", samplerType: \"" + samplerType + "\"" : "") +
		", nativeSlot: " + slot + (name != "null" ? ", nativeName: " + name : "") +
		", textureBinding: " + textureBinding + " }";
}

const UNIFORM_SLOTS = ["hlsl_register_b_n", "msl_buffer_n"];
const TEXTURE_SLOTS = ["hlsl_register_t_n", "msl_texture_n"];
const SAMPLER_SLOTS = ["hlsl_register_s_n", "msl_sampler_n"];

function sampleTypeOf(texture: Yaml): string {
	const t = scalar(texture, "sample_type");
	if (t == "float") { return "float"; }
	if (t == "unfilterable_float") { return "unfilterable-float"; }
	fail("sample_type '" + t + "' has no WebGPU texture sample type here");
}

function samplerTypeOf(sampler: Yaml): string {
	const t = scalar(sampler, "sampler_type");
	if (t == "filtering") { return "filtering"; }
	if (t == "nonfiltering") { return "non-filtering"; }
	fail("sampler_type '" + t + "' has no WebGPU sampler binding type here");
}

// WebGPU binding numbers are shdc's WGSL ones: uniform block slot n is group 0 binding n, view
// slot n is group 1 binding n, sampler slot n is group 1 binding 32 + n.
function program(p: Yaml, gl: boolean): string {
	const bindings: string[] = [];
	for (const block of list(p, "uniform_blocks")) {
		const uniforms = list(block, "glsl_uniforms");
		const name = gl && uniforms.length > 0 ? quoted(scalar(uniforms[0], "glsl_name")) : "null";
		bindings.push(bindingEntry("0", scalar(block, "slot"), "uniform", scalar(block, "stage"),
			scalar(block, "size"), "", "", nativeSlot(block, UNIFORM_SLOTS), name, "-1"));
	}
	for (const view of list(p, "views")) {
		const texture = child(view, "texture");
		bindings.push(bindingEntry("1", scalar(texture, "slot"), "texture", scalar(texture, "stage"), "0",
			sampleTypeOf(texture), "", nativeSlot(texture, TEXTURE_SLOTS), "null", "-1"));
	}
	const samplers = list(p, "samplers");
	if (gl) {
		for (const pair of list(p, "texture_sampler_pairs")) {
			const slot = scalar(pair, "sampler_slot");
			let samplerType = "filtering";
			for (const s of samplers) {
				if (scalar(s, "slot") == slot) { samplerType = samplerTypeOf(s); }
			}
			bindings.push(bindingEntry("1", String(32 + Number(slot)), "sampler", scalar(pair, "stage"), "0",
				"", samplerType, "-1", quoted(scalar(pair, "glsl_name")), scalar(pair, "view_slot")));
		}
	} else {
		for (const s of samplers) {
			bindings.push(bindingEntry("1", String(32 + Number(scalar(s, "slot"))), "sampler", scalar(s, "stage"),
				"0", "", samplerTypeOf(s), nativeSlot(s, SAMPLER_SLOTS), "null", "-1"));
		}
	}
	if (bindings.length > 24) { fail("program '" + scalar(p, "name") + "' has more than 24 bindings"); }
	const attributes: string[] = [];
	for (const a of list(p, "attrs")) {
		const name = gl ? ", nativeName: " + quoted(scalar(a, "glsl_name")) : "";
		attributes.push("{ location: " + scalar(a, "slot") + name + ", semanticIndex: " +
			scalarOr(a, "hlsl_sem_index", "0") + " }");
	}
	const vertex = child(p, "vertex_func");
	const fragment = child(p, "fragment_func");
	return "\texport function " + scalar(p, "name") + "ShaderModule(): GPUShaderModuleDescriptor {\n" +
		"\t\treturn {\n" +
		"\t\t\tlabel: " + quoted(scalar(p, "name")) + ",\n" +
		"\t\t\tvertexCode: " + source(vertex) + ",\n" +
		"\t\t\tvertexEntryPoint: " + quoted(scalar(vertex, "entry_point")) + ",\n" +
		"\t\t\tfragmentCode: " + source(fragment) + ",\n" +
		"\t\t\tfragmentEntryPoint: " + quoted(scalar(fragment, "entry_point")) + ",\n" +
		"\t\t\tbindings: [\n\t\t\t\t" + bindings.join(",\n\t\t\t\t") + ",\n\t\t\t],\n" +
		"\t\t\tattributes: [\n\t\t\t\t" + attributes.join(",\n\t\t\t\t") + ",\n\t\t\t],\n" +
		"\t\t};\n\t}\n";
}

// Each shdc language and the `when` that compiles it; the first that holds wins, in this order.
const TARGETS: string[][] = [
	["wgsl", "webgpu"],
	["glsl300es", "webgl2 || android"],
	["metal_ios", "ios"],
	["metal_macos", "macos"],
	["glsl430", "voidGlCore || linux"],
	["hlsl5", "windows"],
];

function main(): void {
	if (argv.length < 4) { fail("usage: shaderTables <reflection.yaml> <output.ms> <types import path>"); }
	const input = argv[argv.length - 3];
	const output = argv[argv.length - 2];
	const typesPath = argv[argv.length - 1];
	const text = readFile(input);
	if (!text.ok) { fail("cannot read " + input); }
	const parser = new Parser(text.value.replaceAll("\r", "").split("\n").filter((l) => l.trim() != ""));
	const root = parser.map(0);
	let out = "// Generated by tools/shaderTables.ms from sokol-shdc output; do not edit.\n\n" +
		"import { GPUShaderModuleDescriptor } from " + quoted(typesPath) + ";\n";
	let opened = 0;
	for (const target of TARGETS) {
		for (const shader of list(root, "shaders")) {
			if (scalar(shader, "slang") != target[0]) { continue; }
			out += (opened == 0 ? "\nwhen (" : " else when (") + target[1] + ") {\n";
			const programs = list(shader, "programs");
			for (let i = 0; i < programs.length; i++) {
				out += (i > 0 ? "\n" : "") + program(programs[i], target[0].startsWith("glsl"));
			}
			out += "}";
			opened++;
		}
	}
	if (opened == 0) { fail("no known shdc language in " + input); }
	const written = writeFile(output, out + "\n");
	if (!written.ok) { fail("cannot write " + output); }
}

main();
