import { materialModule, materialProgram, shaderProgram } from "../shader/program";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	hook,
	textureSample,
	vec2f,
	vec4f,
} from "../shader/std";
import {
	layoutFloats,
	programLayout,
	samplerSlotMask,
	textureSlotMask,
	uniformBlockBytes,
	uniformSlotMask,
} from "../gpu/door";

struct CrateInput {
	position: Vec2f;
	uv: Vec2f;
}

struct CrateVarying {
	@builtin(position) position: Vec4f;
	uv: Vec2f;
}

struct CrateFragment {
	uv: Vec2f;
}

struct CrateFrame {
	time: float32;
}

struct CrateBindings {
	@binding(0) frame: CrateFrame;
}

struct CrateShaded {
	color: Vec4f;
}

function crateVs(input: CrateInput): CrateVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0), uv: input.uv };
}

function crateFs(input: CrateFragment, b: CrateBindings): Vec4f {
	const lit: CrateShaded = { color: vec4f(input.uv.x, input.uv.y, b.frame.time, 1.0) };
	return hook(lit).color;
}

struct CrateTint {
	tint: Vec4f;
}

struct ColourBindings {
	tintParams: CrateTint;
}

function colourAdd(shaded: CrateShaded, b: ColourBindings): CrateShaded {
	return { color: shaded.color + b.tintParams.tint };
}

struct DetailBindings {
	detail: Texture2d;
	detailSampler: Sampler;
}

function detailMul(shaded: CrateShaded, b: DetailBindings): CrateShaded {
	return { color: shaded.color * textureSample(b.detail, b.detailSampler, vec2f(0.25, 0.5)) };
}

shaderProgram(plainCrate, crateVs, crateFs);
materialProgram(bareCrate, crateVs, crateFs, []);
materialProgram(detailedCrate, crateVs, crateFs, [colourAdd, detailMul]);
materialModule(detailed, crateVs, crateFs, [colourAdd, detailMul]);
materialModule(swapped, crateVs, crateFs, [detailMul, colourAdd]);

test "a material with no effects registers what shaderProgram registers for its stages" {
	assert bareCrate != plainCrate, "the two programs are registered apart";
	assert layoutFloats(programLayout(bareCrate), 0) == layoutFloats(programLayout(plainCrate), 0),
		"block 0 floats";
	assert uniformSlotMask(bareCrate) == uniformSlotMask(plainCrate), "uniform slots";
	assert uniformBlockBytes(bareCrate, 0) == uniformBlockBytes(plainCrate, 0), "block 0 bytes";
	assert textureSlotMask(bareCrate) == textureSlotMask(plainCrate), "texture slots";
	assert samplerSlotMask(bareCrate) == samplerSlotMask(plainCrate), "sampler slots";
	assert uniformSlotMask(plainCrate) == 1 && textureSlotMask(plainCrate) == 0,
		"the base has one block and no texture";
}

test "each effect adds its block, view and sampler past the base's bindings" {
	assert layoutFloats(programLayout(detailedCrate), 0) == 2 + 2, "block 0 floats";
	assert uniformSlotMask(detailedCrate) == 3, "the tint block takes slot 1";
	assert uniformBlockBytes(detailedCrate, 0) == 16 && uniformBlockBytes(detailedCrate, 1) == 16,
		"block bytes";
	assert textureSlotMask(detailedCrate) == 1, "the detail view takes texture slot 0";
	assert samplerSlotMask(detailedCrate) == 1, "the detail sampler takes sampler slot 0";
}

test "the effects chain at the hook site in the author's order" {
	assert detailedModule.fragmentCode.includes("detailMul(colourAdd(phase))"),
		"colourAdd runs first";
	assert swappedModule.fragmentCode.includes("colourAdd(detailMul(phase))"),
		"detailMul runs first";
	assert detailedModule.fragmentCode != swappedModule.fragmentCode,
		"the order reaches the printed text";
}
