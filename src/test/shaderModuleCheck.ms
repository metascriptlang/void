import { shaderModule } from "../shader/program";
import { GPUShaderStage } from "../webgpu/types.ms";
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
	assert pictureModule.vertexCode.length > 0 && pictureModule.fragmentCode.length > 0;
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

test "shaderModule spells a componentwise comparison while the macro prints it" {
	const code = belowModule.fragmentCode;
	assert code.includes("<") || code.includes("lessThan(");
	assert !code.includes("null");
}

test "shaderModule folds a function's const of constants into the offset while the macro prints it" {
	const code = nudgedModule.fragmentCode;
	assert code.includes("vec2i(1i, (-1i))") || code.includes("int2(1, -1))") || code.includes("int2(1, (-1)))") ||
		code.includes("ivec2(1, -1))"), code;
}
