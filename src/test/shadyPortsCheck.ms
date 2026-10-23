// Every shady port (shadyExamplesCheck.ms, shadyTestsCheck.ms, compute1 in shaderComputeCheck.ms)
// lowered as descriptor.ms lowers a program and printed for every target into out/shadyPrograms/,
// which scripts/validateHlsl.sh, scripts/validateWgsl.sh and naga's GLSL front end read.

import { mkdir, writeFile } from "std/fs";
import { computeModule, programModule, stageSource, targetName } from "../shader/descriptor";
import { glslComputeIr, glslIr, glslLinkedIr } from "../shader/emit";
import { ShaderModule } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { Vec2f, Vec4f, builtin, textureSample, vec4f } from "../shader/std";
import { commandsToImage } from "./shaderComputeCheck";
import { circleFs, circleSmoothFs, colorsFs, flareFs, mandelbrotFs } from "./shadyExamplesCheck";
import {
	Atlas,
	complexFs,
	conversionFs,
	discardFs,
	loopsFs,
	mathBuiltinFs,
	mathExtraFs,
	mathFs,
	mathVs,
	matrixFs,
	quadVs,
	switchFs,
	ternaryFs,
	textureFs,
	tileFs,
	tileVs,
	uniformParamFs,
} from "./shadyTestsCheck";

export struct Corner {
	@builtin(vertexIndex) index: uint32;
}

export struct Covering {
	@builtin(position) clip: Vec4f;
}

// The fullscreen triangle a fragment-only port draws through.
export function coverVs(input: Corner): Covering {
	const x = ((input.index & 1) * 4) as float32 - 1.0;
	const y = ((input.index & 2) * 2) as float32 - 1.0;
	return { clip: vec4f(x, y, 0.0, 1.0) };
}

export struct QuadPixel {
	fragmentUv: Vec2f;
}

// silkyVertTest's quad drawn: the atlas sampled at the corner's coordinates.
export function quadFs(input: QuadPixel, b: Atlas): Vec4f {
	return textureSample(b.atlas, b.atlasSampler, input.fragmentUv);
}

// [name, vertex stage, fragment stage]
const PROGRAMS: string[][] = [
	["circle", glslIr(coverVs), glslIr(circleFs)],
	["circleSmooth", glslIr(coverVs), glslIr(circleSmoothFs)],
	["colors", glslIr(coverVs), glslIr(colorsFs)],
	["flare", glslIr(coverVs), glslIr(flareFs)],
	["mandelbrot", glslIr(coverVs), glslIr(mandelbrotFs)],
	["math", glslIr(mathVs), glslLinkedIr(mathFs, mathVs)],
	["texture", glslIr(coverVs), glslIr(textureFs)],
	["ternary", glslIr(mathVs), glslLinkedIr(ternaryFs, mathVs)],
	["loops", glslIr(coverVs), glslIr(loopsFs)],
	["switch", glslIr(coverVs), glslIr(switchFs)],
	["matrix", glslIr(coverVs), glslIr(matrixFs)],
	["complex", glslIr(tileVs), glslLinkedIr(complexFs, tileVs)],
	["conversion", glslIr(tileVs), glslLinkedIr(conversionFs, tileVs)],
	["mathExtra", glslIr(mathVs), glslLinkedIr(mathExtraFs, mathVs)],
	["discard", glslIr(mathVs), glslLinkedIr(discardFs, mathVs)],
	["mathBuiltin", glslIr(mathVs), glslLinkedIr(mathBuiltinFs, mathVs)],
	["quad", glslIr(quadVs), glslLinkedIr(quadFs, quadVs)],
	["tile", glslIr(coverVs), glslIr(tileFs)],
	["uniformParam", glslIr(mathVs), glslLinkedIr(uniformParamFs, mathVs)],
];

const TARGETS: ShaderTarget[] = [ShaderTarget.Wgsl, ShaderTarget.Glsl300es, ShaderTarget.Glsl430,
	ShaderTarget.Hlsl5, ShaderTarget.Msl];

// stage is "vert", "frag" or "comp"; each validator finds its files by extension.
function probePath(name: string, target: ShaderTarget, stage: string): string {
	const base = "out/shadyPrograms/" + name;
	return match (target) {
		ShaderTarget.Wgsl => base + "." + stage + ".wgsl",
		ShaderTarget.Hlsl5 => base + "." + (stage == "vert" ? "vs" : stage == "frag" ? "ps" : "cs") +
			".hlsl",
		ShaderTarget.Glsl430 => base + ".430." + stage,
		ShaderTarget.Glsl300es => base + ".es." + stage,
		ShaderTarget.Msl => base + "." + stage + ".metal",
	};
}

// The printed text, written to its probe path; a refusal comes back prefixed so a caller tells
// the two apart.
function printed(m: ShaderModule, entry: int32, name: string, target: ShaderTarget,
	stage: string): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { return "refused: " + text.error; }
	const _out = mkdir("out");
	const _folder = mkdir("out/shadyPrograms");
	const _written = writeFile(probePath(name, target, stage), text.value);
	return text.value;
}

test "every shady program prints on every target" {
	let refusals: string[] = [];
	for (const p of PROGRAMS) {
		const m = programModule(p[1], p[2], []);
		if (!m.ok) {
			refusals.push(p[0] + ": " + m.error);
			continue;
		}
		for (const target of TARGETS) {
			for (let entry: int32 = 0; entry < 2; entry++) {
				const stage = entry == 0 ? "vert" : "frag";
				const text = printed(m.value, entry, p[0], target, stage);
				if (text.startsWith("refused: ")) {
					refusals.push(p[0] + " " + targetName(target) + " " + stage + ": " + text);
				}
			}
		}
	}
	console.log(refusals.join("\n"));
	assert refusals.length == 0;
}

test "GL names a varying apart from the attribute it copies, alike in both stages" {
	const m = programModule(glslIr(mathVs), glslLinkedIr(mathFs, mathVs), []);
	assert m.ok;
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		const vertex = printed(m.value, 0, "mathNames", target, "vert");
		const fragment = printed(m.value, 1, "mathNames", target, "frag");
		assert vertex.includes("layout(location = 1) in vec4 color;\n");
		assert vertex.includes("out vec4 color_1;\n");
		assert fragment.includes(" vec4 color_1;\n") && !fragment.includes(" color;\n");
	}
}

test "compute1 prints on every target but GLSL ES 3.00, which has no storage resources" {
	const m = computeModule(glslComputeIr(commandsToImage, [32, 1, 1]), []);
	assert m.ok;
	for (const target of TARGETS) {
		const text = printed(m.value, 0, "compute1", target, "comp");
		if (target == ShaderTarget.Glsl300es) {
			assert text == "refused: resource 'image': GLSL ES 3.0 has no storage resources";
		} else {
			assert !text.startsWith("refused: ");
		}
	}
}
