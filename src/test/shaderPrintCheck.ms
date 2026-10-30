// Each entry is lowered to the shader IR, checked against its invariants and printed as GLSL 450:
// a textured vertex and fragment pair with a program key feature, and compute1.

import { glsl, glslCompute, glslLinked } from "../shader/emit";
import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	feature,
	textureSample,
	vec4f,
} from "../shader/std";
import { commandsToImage } from "./shaderComputeCheck";

struct PrintAttributes {
	position: Vec3f;
	uv: Vec2f;
	@feature(TINT) tint: Vec4f;
}

struct PrintVaryings {
	@builtin(position) clip: Vec4f;
	uv: Vec2f;
	@feature(TINT) tint: Vec4f;
}

struct PrintFragment {
	uv: Vec2f;
	@feature(TINT) tint: Vec4f;
}

struct PrintKey {
	@feature(TINT) tinted: boolean;
}

struct PrintUniforms {
	mvp: Mat4x4f;
}

struct PrintVertexBindings {
	@binding(0) params: PrintUniforms;
}

struct PrintFragmentBindings {
	@binding(0) colour: Texture2d;
	@binding(0) colourSampler: Sampler;
}

function tinted(colour: Vec4f, tint: Vec4f): Vec4f {
	return colour * tint;
}

function printVs(input: PrintAttributes, b: PrintVertexBindings, key: PrintKey): PrintVaryings {
	return { clip: b.params.mvp * vec4f(input.position, 1.0), uv: input.uv, tint: input.tint };
}

function printFs(input: PrintFragment, b: PrintFragmentBindings, key: PrintKey): Vec4f {
	let colour = textureSample(b.colour, b.colourSampler, input.uv);
	if (key.tinted) { colour = tinted(colour, input.tint); }
	return colour;
}

test "a textured pair with a feature prints its gated interface and helper" {
	assert glsl(printVs) ==
		"layout(binding=0) uniform params {\n" +
		"    mat4 mvp;\n" +
		"};\n" +
		"in vec3 position;\n" +
		"in vec2 uv;\n" +
		"#ifdef TINT\n" +
		"in vec4 tint;\n" +
		"#endif\n" +
		"out vec2 uv_1;\n" +
		"#ifdef TINT\n" +
		"out vec4 tint_1;\n" +
		"#endif\n" +
		"void main() {\n" +
		"    gl_Position = (mvp * vec4(position, 1.0));\n" +
		"    uv_1 = uv;\n" +
		"#ifdef TINT\n" +
		"    tint_1 = tint;\n" +
		"#endif\n" +
		"    return;\n" +
		"}\n";
	assert glslLinked(printFs, printVs) ==
		"layout(binding=0) uniform texture2D colour;\n" +
		"layout(binding=0) uniform sampler colourSampler;\n" +
		"in vec2 uv_1;\n" +
		"#ifdef TINT\n" +
		"in vec4 tint_1;\n" +
		"#endif\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"#ifdef TINT\n" +
		"vec4 tinted(vec4 colour_1, vec4 tint) {\n" +
		"    return colour_1 * tint;\n" +
		"}\n" +
		"#endif\n" +
		"void main() {\n" +
		"    vec4 colour_1 = texture(sampler2D(colour, colourSampler), uv_1);\n" +
		"#ifdef TINT\n" +
		"    colour_1 = tinted(colour_1, tint_1);\n" +
		"#endif\n" +
		"    fragColor = colour_1;\n" +
		"    return;\n" +
		"}\n";
}

test "compute1 prints its storage buffer, storage texture and workgroup size" {
	assert glslCompute(commandsToImage, [32, 1, 1]) ==
		"layout(local_size_x=32, local_size_y=1, local_size_z=1) in;\n" +
		"struct Command {\n" +
		"    float value;\n" +
		"};\n" +
		"layout(binding=0) readonly buffer commandsBuffer {\n" +
		"    Command commands[];\n" +
		"};\n" +
		"layout(binding=1, rgba8) uniform writeonly image2D image;\n" +
		"void main() {\n" +
		"    ivec2 size = imageSize(image);\n" +
		"    int y = ivec2(gl_GlobalInvocationID.xy).y;\n" +
		"    for (int x = 0; x < size.x; x++) {\n" +
		"        float value = commands[x].value;\n" +
		"        imageStore(image, ivec2(x, y), vec4(0.5, 0.0, (value / 255.0), 1.0));\n" +
		"    }\n" +
		"}\n";
}
