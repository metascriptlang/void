// A shader calls the author's functions and reads module constants: glsl defines each one above
// main(), once, after what it reads, under a name GLSL does not already hold.

import { glsl } from "../shader/emit";
import { Vec2f, Vec2i, Vec4f, builtin, vec2i } from "../shader/std";
import { GAIN, scale as scaleFar } from "./shaderCalleeHelpers";

struct ProbeInput {
	@builtin(position) position: Vec4f;
}

function at(x: float32, y: float32): ProbeInput {
	return { position: { x, y, z: 0.5, w: 1.0 } };
}

function twice(x: float32): float32 { return x + x; }

function quad(x: float32): float32 { return twice(twice(x)); }

function probeDeepFs(input: ProbeInput): float32 { return quad(input.position.x); }

test "a helper two deep is defined after the helper it calls, the shared one once" {
	assert glsl(probeDeepFs) ==
		"layout(location=0) out float fragColor;\n" +
		"float twice(float x) {\n" +
		"    return x + x;\n" +
		"}\n" +
		"float quad(float x) {\n" +
		"    return twice(twice(x));\n" +
		"}\n" +
		"void main() {\n" +
		"    fragColor = quad(gl_FragCoord.x);\n" +
		"    return;\n" +
		"}\n";
	assert probeDeepFs(at(1.5, 0.5)) == 6.0;
}

const BIAS: float32 = 0.5;

function scale(x: float32): float32 { return x * BIAS; }

function probeModuleFs(input: ProbeInput): float32 {
	return scaleFar(input.position.x) + scale(GAIN);
}

test "a helper and a constant of another module, a same-named helper under its own name" {
	assert glsl(probeModuleFs) ==
		"layout(location=0) out float fragColor;\n" +
		"const float GAIN = 2.0;\n" +
		"float scale(float x) {\n" +
		"    return x * GAIN;\n" +
		"}\n" +
		"const float BIAS = 0.5;\n" +
		"float scale_1(float x) {\n" +
		"    return x * BIAS;\n" +
		"}\n" +
		"void main() {\n" +
		"    fragColor = scale(gl_FragCoord.x) + scale_1(GAIN);\n" +
		"    return;\n" +
		"}\n";
	assert probeModuleFs(at(1.5, 0.5)) == 4.0;
}

const ONE = vec2i(1, 1);

function texel(at: Vec2f): Vec2i { return vec2i(at); }

function texel(at: Vec2i): Vec2i { return at - ONE; }

function probeOverloadFs(input: ProbeInput): int32 {
	const p = texel(texel(input.position.xy));
	return p.x + p.y;
}

test "an overload pair stays two GLSL overloads, each call on the declaration it resolved to" {
	assert glsl(probeOverloadFs) ==
		"layout(location=0) out int fragColor;\n" +
		"const ivec2 ONE = ivec2(1, 1);\n" +
		"ivec2 texel(ivec2 at) {\n" +
		"    return at - ONE;\n" +
		"}\n" +
		"ivec2 texel(vec2 at) {\n" +
		"    return ivec2(at);\n" +
		"}\n" +
		"void main() {\n" +
		"    ivec2 p = texel(texel(gl_FragCoord.xy));\n" +
		"    fragColor = p.x + p.y;\n" +
		"    return;\n" +
		"}\n";
	assert probeOverloadFs(at(5.5, 7.5)) == 10;
}

function weigh(sample: float32, texture: float32): float32 {
	const output = sample * texture;
	return output;
}

function probeNamesFs(input: ProbeInput): float32 {
	const mix = input.position.x;
	const BIAS = weigh(mix, 0.25);
	return scale(BIAS);
}

test "a name GLSL holds or a constant the shader defines is renamed with a suffix" {
	assert glsl(probeNamesFs) ==
		"layout(location=0) out float fragColor;\n" +
		"float weigh(float sample_1, float texture_1) {\n" +
		"    float output_1 = sample_1 * texture_1;\n" +
		"    return output_1;\n" +
		"}\n" +
		"const float BIAS = 0.5;\n" +
		"float scale(float x) {\n" +
		"    return x * BIAS;\n" +
		"}\n" +
		"void main() {\n" +
		"    float mix_1 = gl_FragCoord.x;\n" +
		"    float BIAS_1 = weigh(mix_1, 0.25);\n" +
		"    fragColor = scale(BIAS_1);\n" +
		"    return;\n" +
		"}\n";
	assert probeNamesFs(at(2.0, 0.5)) == 0.25;
}
