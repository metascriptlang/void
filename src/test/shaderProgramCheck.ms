import { shaderProgram } from "../shader/program";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	textureSample,
	vec4f,
} from "../shader/std";
import {
	layoutFloats,
	programLayout,
	samplerSlotMask,
	textureSlotMask,
	uniformBlockBytes,
} from "../gpu/door";

struct TintedInput {
	position: Vec2f;
	color: Vec4f;
	@builtin(vertexIndex) index: uint32;
	uv: Vec2f;
}

struct TintedVarying {
	@builtin(position) position: Vec4f;
	color: Vec4f;
	uv: Vec2f;
}

struct TintedFragment {
	color: Vec4f;
	uv: Vec2f;
}

struct Tint {
	tint: Vec4f;
}

struct TintedBindings {
	@binding(1) tintParams: Tint;
	@binding(0) picture: Texture2d;
	@binding(0) smoothing: Sampler;
}

function tintedVs(input: TintedInput): TintedVarying {
	return {
		position: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		color: input.color,
		uv: input.uv,
	};
}

function tintedFs(input: TintedFragment, b: TintedBindings): Vec4f {
	return textureSample(b.picture, b.smoothing, input.uv) * input.color * b.tintParams.tint;
}

shaderProgram(tinted, tintedVs, tintedFs);

struct SolidVarying {
	@builtin(position) position: Vec4f;
}

function solidVs(input: TintedInput): SolidVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

function solidFs(): Vec4f {
	return vec4f(1.0, 0.5, 0.25, 1.0);
}

shaderProgram(solid, solidVs, solidFs);

test "shaderProgram registers the program it declares, with its attributes and bindings" {
	assert layoutFloats(programLayout(tinted), 0) == 2 + 4 + 2;
	assert uniformBlockBytes(tinted, 1) == 16;
	assert uniformBlockBytes(tinted, 0) == 0;
	assert textureSlotMask(tinted) == 1;
	assert samplerSlotMask(tinted) == 1;
}

test "a fragment that reads no varyings pairs with a vertex entry that writes none" {
	assert solid != tinted;
	assert layoutFloats(programLayout(solid), 0) == 2 + 4 + 2;
	assert uniformBlockBytes(solid, 1) == 0;
	assert textureSlotMask(solid) == 0;
}
