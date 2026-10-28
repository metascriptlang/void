import { byteAt, byteLength } from "std/core/string/bytes";
import { readFile } from "std/fs";
import { programModule, programSource } from "../shader/descriptor";
import { glslIr, glslLinkedIr } from "../shader/emit";
import { ShaderTarget } from "../shader/layout";
import { shaderModule, stageBlob } from "../shader/program";
import { GPUShaderModuleDescriptor, GPUShaderStage } from "../webgpu/types.ms";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	lt,
	select,
	textureSample,
	vec2i,
	vec4f,
} from "../shader/std";

struct PictureInput {
	position: Vec2f;
	uv: Vec2f;
}

struct PictureVarying {
	@builtin(position) position: Vec4f;
	uv: Vec2f;
}

struct PictureFragment {
	uv: Vec2f;
}

struct PictureTint {
	tint: Vec4f;
}

struct PictureBindings {
	@binding(1) tintParams: PictureTint;
	@binding(0) picture: Texture2d;
	@binding(0) smoothing: Sampler;
}

function pictureVs(input: PictureInput): PictureVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0), uv: input.uv };
}

function pictureFs(input: PictureFragment, b: PictureBindings): Vec4f {
	return textureSample(b.picture, b.smoothing, input.uv) * b.tintParams.tint;
}

shaderModule(picture, pictureVs, pictureFs);

struct BelowBindings {
	@binding(0) tintParams: PictureTint;
}

function belowFs(input: PictureFragment, b: BelowBindings): Vec4f {
	return select(vec4f(0.0, 0.0, 0.0, 0.0), b.tintParams.tint, lt(b.tintParams.tint, vec4f(0.5, 0.5, 0.5, 0.5)));
}

shaderModule(below, pictureVs, belowFs);

function nudgedFs(input: PictureFragment, b: PictureBindings): Vec4f {
	const shift = vec2i(1, -1);
	return textureSample(b.picture, b.smoothing, input.uv, shift);
}

shaderModule(nudged, pictureVs, nudgedFs);

test "shaderModule declares the program's WebGPU shader module for this build's backend" {
	assert (pictureModule.label ?? "") == "picture";
	assert pictureModule.vertexCode.length + pictureModule.vertexBytecode.length > 0;
	assert pictureModule.fragmentCode.length + pictureModule.fragmentBytecode.length > 0;
	assert pictureModule.vertexEntryPoint != "" && pictureModule.fragmentEntryPoint != "";
	const kind: string = pictureModule.bindings[3].kind;
	assert kind == "";
	assert pictureModule.attributes[0].location == 0 && pictureModule.attributes[1].location == 1;
}

test "shaderModule numbers bindings on the WGSL slots: blocks group 0, views group 1, samplers from 32" {
	const tint = pictureModule.bindings[0];
	assert tint.group == 0 && tint.binding == 1 && tint.kind == "uniform" && tint.visibility == (GPUShaderStage.FRAGMENT as int32);
	assert tint.size == 16;
	const texture = pictureModule.bindings[1];
	assert texture.group == 1 && texture.binding == 0 && texture.kind == "texture";
	assert texture.sampleType == "float";
	const sampler = pictureModule.bindings[2];
	assert sampler.group == 1 && sampler.binding == 32 && sampler.kind == "sampler";
	assert sampler.samplerType == "filtering";
}

// On a host with fxc the descriptor carries DXBC and no text: the text is then the one this binary
// prints, and "" unless the descriptor's blob is the cache file that text keys.
function fragmentText(module: GPUShaderModuleDescriptor, vs: string, fs: string): string {
	if (module.fragmentCode != "") { return module.fragmentCode; }
	const m = programModule(vs, fs, []);
	if (!m.ok) { return ""; }
	const source = programSource(m.value, ShaderTarget.Hlsl5);
	if (!source.ok) { return ""; }
	const s = source.value;
	const file = readFile(stageBlob("hlsl5", "fragment", s.fragmentCode, s.entryPoint, "").path);
	if (!file.ok || file.value.byteLength() != module.fragmentBytecode.length) { return ""; }
	for (let i = 0; i < module.fragmentBytecode.length; i++) {
		if (module.fragmentBytecode[i] as int32 != file.value.byteAt(i) as int32) { return ""; }
	}
	return s.fragmentCode;
}

test "shaderModule spells a componentwise comparison while the macro prints it" {
	const code = fragmentText(belowModule, glslIr(pictureVs), glslLinkedIr(belowFs, pictureVs));
	assert code.includes("<") || code.includes("lessThan(");
	assert !code.includes("null");
}

test "shaderModule folds a function's const of constants into the offset while the macro prints it" {
	const code = fragmentText(nudgedModule, glslIr(pictureVs), glslLinkedIr(nudgedFs, pictureVs));
	assert code.includes("vec2i(1i, (-1i))") || code.includes("int2(1, -1))") || code.includes("int2(1, (-1)))") ||
		code.includes("ivec2(1, -1))"), code;
}
