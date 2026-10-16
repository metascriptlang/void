// treeform/shady's tests/test_shady.nim, case by case, as Void stages: each one's GLSL is pinned
// and, where it computes something, run on the CPU. A case Void writes differently says why beside
// it.

import { glsl, glslLinked } from "../shader/emit";
import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Texture2dArray,
	Texture2dU32,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	clamp,
	discard,
	dot,
	dpdx,
	fract,
	fwidth,
	inverse,
	mix,
	normalize,
	sin,
	smoothstep,
	textureLoad,
	textureSample,
	vec2f,
	vec2i,
	vec3f,
	vec4f,
} from "../shader/std";

export struct Pixel {
	@builtin(position) position: Vec4f;
}

export struct Surface {
	uv: Vec2f;
	color: Vec4f;
	normal: Vec3f;
}

export struct SurfaceVertex {
	position: Vec3f;
	color: Vec4f;
	normal: Vec3f;
}

export struct SurfaceVaryings {
	uv: Vec2f;
	color: Vec4f;
	normal: Vec3f;
	@builtin(position) clip: Vec4f;
}

// "Using var, let and math operators": shady writes fragColor.x..w one by one; here the colour is
// returned.
export function mathVs(input: SurfaceVertex): SurfaceVaryings {
	return {
		uv: input.position.xy,
		color: input.color,
		normal: input.normal,
		clip: vec4f(input.position, 1.0),
	};
}

export function mathFs(input: Surface): Vec4f {
	const f = input.color.xyz * dot(input.normal, normalize(vec3f(1.0, 1.0, 1.0)));
	return vec4f(f.x, f.y, f.z, 1.0);
}

export struct Atlas {
	@binding(0) atlas: Texture2d;
	@binding(0) atlasSampler: Sampler;
}

// "Using textures."
export function textureFs(input: Pixel, b: Atlas): Vec4f {
	return textureSample(b.atlas, b.atlasSampler, vec2f(0.5, 0.5));
}

// "Ternary operator."
export function ternaryFs(input: Surface): Vec4f {
	const up: float32 = input.normal.y > 0.5 ? 1.0 : 0.0;
	const side: float32 = input.normal.x < 0.0 ? 1.0 : 0.5;
	return vec4f(up, side, 0.0, 1.0);
}

// "Loops (For and While)": shady's `inc` and `dec` are ++ and --.
export function loopsFs(input: Pixel): Vec4f {
	let sum: float32 = 0.0;
	for (let i = 0; i < 10; i++) {
		sum += 0.1;
	}
	let j = 0;
	while (j < 5) {
		sum += 0.01;
		j++;
	}
	j += 2;
	let k = 10;
	while (k > 0) {
		sum += 0.001;
		k--;
	}
	return vec4f(sum, 0.0, 0.0, 1.0);
}

// "Switch/Case statement": the scrutinee is the pixel's column.
export function switchFs(input: Pixel): Vec4f {
	const i = vec2i(input.position.xy).x;
	switch (i) {
		case 0:
			return vec4f(1.0, 0.0, 0.0, 1.0);
		case 1:
			return vec4f(0.0, 1.0, 0.0, 1.0);
		default:
			return vec4f(0.0, 0.0, 1.0, 1.0);
	}
}

export struct MatrixParams {
	m: Mat4x4f;
	v: Vec4f;
}

export struct MatrixBindings {
	@binding(0) matrixParams: MatrixParams;
}

// "Matrix inverse and swizzles."
export function matrixFs(input: Pixel, b: MatrixBindings): Vec4f {
	return inverse(b.matrixParams.m) * b.matrixParams.v.zyxw;
}

export struct Tile {
	@builtin(position) position: Vec4f;
	someInt: int32;
}

export struct TileVertex {
	position: Vec3f;
	someInt: int32;
}

export struct TileVaryings {
	someInt: int32;
	@builtin(position) clip: Vec4f;
}

export function tileVs(input: TileVertex): TileVaryings {
	return { someInt: input.someInt, clip: vec4f(input.position, 1.0) };
}

// "gl_FragCoord and flat int attributes."
export function complexFs(input: Tile): Vec4f {
	if (input.someInt == 0) {
		return input.position;
	}
	return vec4f(1.0, 1.0, 1.0, 1.0);
}

// "Type conversions and unary minus."
export function conversionFs(input: Tile): Vec4f {
	const f = input.position.x;
	const f2 = input.someInt as float32;
	const i2 = f as int32;
	return vec4f(f2, i2 as float32, -f, 1.0);
}

// "Derivatives, fract and mod": shady's fmod is GLSL's floored mod, x - y * floor(x / y).
export function mathExtraFs(input: Surface): Vec4f {
	const v = input.uv;
	const mo = v.y - 2.0 * (v.y / 2.0 - fract(v.y / 2.0));
	return vec4f(dpdx(v.x), fwidth(v.y), fract(v.x), v.y - mo);
}

// "discardFragment and break."
export function discardFs(input: Surface): Vec4f {
	if (input.uv.x < 0.0) {
		discard();
	}
	let sum: float32 = 0.0;
	for (let i = 0; i < 10; i++) {
		if (i > 5) {
			break;
		}
		sum += 1.0;
	}
	return vec4f(sum / 10.0, 0.0, 0.0, 1.0);
}

// "Built-in math (mix, smoothstep, clamp)."
export function mathBuiltinFs(input: Surface): Vec4f {
	const t = input.uv.x;
	return vec4f(mix(input.uv.y, input.normal.x, t), smoothstep(0.0, 1.0, t), clamp(t, 0.0, 1.0),
		1.0);
}

export struct Quad {
	@builtin(vertexIndex) index: uint32;
	position: Vec2f;
}

export struct QuadVaryings {
	fragmentUv: Vec2f;
	@builtin(position) clip: Vec4f;
}

export struct QuadParams {
	mvp: Mat4x4f;
	atlasSize: Vec4f;
}

export struct QuadBindings {
	@binding(0) quadParams: QuadParams;
}

// silkyVertTest and es3VertShader: a quad corner from the vertex index, by uint % and /.
export function quadVs(input: Quad, b: QuadBindings): QuadVaryings {
	const cornerX = (input.index % 2) as float32;
	const cornerY = (input.index / 2) as float32;
	const dx = input.position.x + cornerX * 10.0;
	const dy = input.position.y + cornerY * 10.0;
	return {
		fragmentUv: vec2f(dx, dy) / b.quadParams.atlasSize.xy,
		clip: b.quadParams.mvp * vec4f(dx, dy, 0.0, 1.0),
	};
}

export struct TileBindings {
	@binding(0) tileData: Texture2dU32;
	@binding(1) tileAtlas: Texture2dArray;
	@binding(0) tileSampler: Sampler;
}

// es3SamplerFrag and desktopSamplerFrag: a uint texel fetched, and a layer of an array sampled.
export function tileFs(input: Pixel, b: TileBindings): Vec4f {
	const tile = textureLoad(b.tileData, b.tileSampler, vec2i(0, 0), 0);
	const layer = textureSample(b.tileAtlas, b.tileSampler, vec2f(0.5, 0.5), 1);
	return vec4f(tile.x as float32, layer.y, 0.0, 1.0);
}

export struct TimeParams {
	time: Vec4f;
}

export struct TimeBindings {
	@binding(0) timeParams: TimeParams;
}

// uniformParamFrag: a uniform read beside the varyings.
export function uniformParamFs(input: Surface, b: TimeBindings): Vec4f {
	return vec4f(input.uv.x, input.uv.y, sin(b.timeParams.time.x), 1.0);
}

test "mathFrag gives shady's colour" {
	const red = vec4f(1.0, 0.0, 0.0, 1.0);
	const c = mathFs({ uv: vec2f(0.0, 0.0), color: red, normal: vec3f(0.0, 1.0, 0.0) });
	assert Math.abs(c.x - 0.5773502588272095) < 1e-6 && c.y == 0.0 && c.w == 1.0;
}

test "loops sum as shady's do, and break stops at six" {
	assert Math.abs(loopsFs({ position: vec4f(0.0, 0.0, 0.0, 1.0) }).x - 1.06) < 1e-5;
	const d = discardFs({ uv: vec2f(1.0, 0.0), color: vec4f(0.0), normal: vec3f(0.0) });
	assert Math.abs(d.x - 0.6) < 1e-6;
}

test "switch picks by the pixel's column" {
	assert switchFs({ position: vec4f(1.5, 0.5, 0.0, 1.0) }).y == 1.0;
	assert switchFs({ position: vec4f(7.5, 0.5, 0.0, 1.0) }).z == 1.0;
}

test "mathFrag" {
	assert glslLinked(mathFs, mathVs) ==
		"in vec2 uv;\n" +
		"in vec4 color_1;\n" +
		"in vec3 normal_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec3 f = color_1.xyz * dot(normal_1, normalize(vec3(1.0, 1.0, 1.0)));\n" +
		"    fragColor = vec4(f.x, f.y, f.z, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "textureFrag" {
	assert glsl(textureFs) ==
		"layout(binding=0) uniform texture2D atlas;\n" +
		"layout(binding=0) uniform sampler atlasSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    fragColor = texture(sampler2D(atlas, atlasSampler), vec2(0.5, 0.5));\n" +
		"    return;\n" +
		"}\n";
}

test "ternaryOperator" {
	assert glslLinked(ternaryFs, mathVs) ==
		"in vec2 uv;\n" +
		"in vec4 color_1;\n" +
		"in vec3 normal_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    float up = (normal_1.y > 0.5) ? 1.0 : 0.0;\n" +
		"    float side = (normal_1.x < 0.0) ? 1.0 : 0.5;\n" +
		"    fragColor = vec4(up, side, 0.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "loops" {
	assert glsl(loopsFs) ==
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    float sum = 0.0;\n" +
		"    for (int i = 0; i < 10; i++) {\n" +
		"        sum += 0.1;\n" +
		"    }\n" +
		"    int j = 0;\n" +
		"    while (j < 5) {\n" +
		"        sum += 0.01;\n" +
		"        j++;\n" +
		"    }\n" +
		"    j += 2;\n" +
		"    int k = 10;\n" +
		"    while (k > 0) {\n" +
		"        sum += 0.001;\n" +
		"        k--;\n" +
		"    }\n" +
		"    fragColor = vec4(sum, 0.0, 0.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "switchCase" {
	assert glsl(switchFs) ==
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    int i = ivec2(gl_FragCoord.xy).x;\n" +
		"    switch (i) {\n" +
		"        case 0: {\n" +
		"            fragColor = vec4(1.0, 0.0, 0.0, 1.0);\n" +
		"            return;\n" +
		"        }\n" +
		"        case 1: {\n" +
		"            fragColor = vec4(0.0, 1.0, 0.0, 1.0);\n" +
		"            return;\n" +
		"        }\n" +
		"        default: {\n" +
		"            fragColor = vec4(0.0, 0.0, 1.0, 1.0);\n" +
		"            return;\n" +
		"        }\n" +
		"    }\n" +
		"}\n";
}

test "matrixShader" {
	assert glsl(matrixFs) ==
		"layout(binding=0) uniform matrixParams {\n" +
		"    mat4 m;\n" +
		"    vec4 v;\n" +
		"};\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    fragColor = inverse(m) * v.zyxw;\n" +
		"    return;\n" +
		"}\n";
}

test "complexShader" {
	assert glslLinked(complexFs, tileVs) ==
		"flat in int someInt_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    if (someInt_1 == 0) {\n" +
		"        fragColor = gl_FragCoord;\n" +
		"        return;\n" +
		"    }\n" +
		"    fragColor = vec4(1.0, 1.0, 1.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "conversionShader" {
	assert glslLinked(conversionFs, tileVs) ==
		"flat in int someInt_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    float f = gl_FragCoord.x;\n" +
		"    float f2 = float(someInt_1);\n" +
		"    int i2 = int(f);\n" +
		"    fragColor = vec4(f2, float(i2), (-f), 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "mathExtraShader" {
	assert glslLinked(mathExtraFs, mathVs) ==
		"in vec2 uv;\n" +
		"in vec4 color_1;\n" +
		"in vec3 normal_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec2 v = uv;\n" +
		"    float mo = v.y - (2.0 * ((v.y / 2.0) - fract((v.y / 2.0))));\n" +
		"    fragColor = vec4(dFdx(v.x), fwidth(v.y), fract(v.x), (v.y - mo));\n" +
		"    return;\n" +
		"}\n";
}

test "discardShader" {
	assert glslLinked(discardFs, mathVs) ==
		"in vec2 uv;\n" +
		"in vec4 color_1;\n" +
		"in vec3 normal_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    if (uv.x < 0.0) {\n" +
		"        discard;\n" +
		"    }\n" +
		"    float sum = 0.0;\n" +
		"    for (int i = 0; i < 10; i++) {\n" +
		"        if (i > 5) {\n" +
		"            break;\n" +
		"        }\n" +
		"        sum += 1.0;\n" +
		"    }\n" +
		"    fragColor = vec4((sum / 10.0), 0.0, 0.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "mathBuiltinShader" {
	assert glslLinked(mathBuiltinFs, mathVs) ==
		"in vec2 uv;\n" +
		"in vec4 color_1;\n" +
		"in vec3 normal_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    float t = uv.x;\n" +
		"    fragColor = vec4(mix(uv.y, normal_1.x, t), smoothstep(0.0, 1.0, t), clamp(t, 0.0, 1.0), 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "silkyVertTest" {
	assert glsl(quadVs) ==
		"layout(binding=0) uniform quadParams {\n" +
		"    mat4 mvp;\n" +
		"    vec4 atlasSize;\n" +
		"};\n" +
		"in vec2 position;\n" +
		"out vec2 fragmentUv;\n" +
		"void main() {\n" +
		"    float cornerX = float(uint(gl_VertexIndex) % 2);\n" +
		"    float cornerY = float(uint(gl_VertexIndex) / 2);\n" +
		"    float dx = position.x + (cornerX * 10.0);\n" +
		"    float dy = position.y + (cornerY * 10.0);\n" +
		"    fragmentUv = (vec2(dx, dy) / atlasSize.xy);\n" +
		"    gl_Position = (mvp * vec4(dx, dy, 0.0, 1.0));\n" +
		"    return;\n" +
		"}\n";
}

test "es3SamplerFrag" {
	assert glsl(tileFs) ==
		"@image_sample_type tileData uint\n" +
		"layout(binding=0) uniform utexture2D tileData;\n" +
		"layout(binding=1) uniform texture2DArray tileAtlas;\n" +
		"layout(binding=0) uniform sampler tileSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    uvec4 tile = texelFetch(usampler2D(tileData, tileSampler), ivec2(0, 0), 0);\n" +
		"    vec4 layer = texture(sampler2DArray(tileAtlas, tileSampler), vec3(vec2(0.5, 0.5), float(1)));\n" +
		"    fragColor = vec4(float(tile.x), layer.y, 0.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "uniformParamFrag" {
	assert glslLinked(uniformParamFs, mathVs) ==
		"layout(binding=0) uniform timeParams {\n" +
		"    vec4 time;\n" +
		"};\n" +
		"in vec2 uv;\n" +
		"in vec4 color_1;\n" +
		"in vec3 normal_1;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    fragColor = vec4(uv.x, uv.y, sin(time.x), 1.0);\n" +
		"    return;\n" +
		"}\n";
}
