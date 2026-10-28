// The CPU meaning of ./shader/std where its GLSL spelling or meaning parts from WGSL's
// (docs/VOCABULARY.md, "A name brings its meaning"), and the GLSL the glsl macro spells for it.

import { Wrap } from "../gpu/state";
import { glsl } from "../shader/emit";
import {
	Mat4x4f,
	Sampler,
	Texture2d,
	TextureCube,
	Vec3f,
	Vec4f,
	abs,
	acos,
	asin,
	atan,
	atan2,
	binding,
	builtin,
	ceil,
	clamp,
	cos,
	cosh,
	cross,
	degrees,
	determinant,
	distance,
	dot,
	dpdx,
	dpdy,
	exp,
	exp2,
	faceForward,
	floor,
	fma,
	fract,
	fwidth,
	inverse,
	inverseSqrt,
	length,
	log,
	log2,
	mat2x2f,
	mat3x3f,
	mat4x4f,
	max,
	min,
	mix,
	normalize,
	pow,
	radians,
	reflect,
	refract,
	round,
	saturate,
	select,
	sign,
	sin,
	sinh,
	smoothstep,
	sqrt,
	step,
	tan,
	tanh,
	textureDimensions,
	textureLoad,
	textureSample,
	textureSampleLevel,
	transpose,
	trunc,
	upperLeft3x3,
	vec2f,
	vec2i,
	vec2u,
	vec3f,
	vec3i,
	vec3u,
	vec4f,
	vec4i,
	vec4u,
} from "../shader/std";

export struct ProbeInput {
	@builtin(position) position: Vec4f;
}

export struct ProbeBindings {
	@binding(0) shadowMap: Texture2d;
}

export function probeFs(input: ProbeInput, b: ProbeBindings): Vec4f {
	const p = input.position;
	const model = mat4x4f(p, p, p, vec4f(0.0, 0.0, 0.0, 1.0));
	const world = model * model * vec4f(p.xyz, 1.0);
	const n = normalize(upperLeft3x3(model) * world.xyz);
	const basis = mat3x3f(n, vec3f(0.0, 1.0, 0.0), vec3f(1.0));
	const uv = p.xy * vec2f(textureDimensions(b.shadowMap, 0));
	const up = basis * vec3f(0.0, 1.0, 0.0);
	const lambert = max(dot(n, up), 0.0) * p.w / length(n);
	const light = pow(max(n * 0.5 + 0.5, vec3f(0.0)), vec3f(2.4)) - 1.0;
	const bright = 2.0 * light / n;
	const curved = mix(clamp(light, vec3f(0.0), vec3f(1.0)), bright, min(lambert, 1.0));
	const facing = select(n, light - n, p.z > 0.5);
	const shade = select(1.0, clamp(uv.x, 0.0, 1.0), uv.y > 1.0);
	const texel = textureLoad(b.shadowMap, vec2i(uv), 0);
	return vec4f(curved * facing * shade + texel.rgb * texel.r, texel.a);
}

test "glsl spells every std name in its GLSL form" {
	const expected =
		"#extension GL_EXT_samplerless_texture_functions : require\n" +
		"layout(binding=0) uniform texture2D shadowMap;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 p = gl_FragCoord;\n" +
		"    mat4 model = mat4(p, p, p, vec4(0.0, 0.0, 0.0, 1.0));\n" +
		"    vec4 world = (model * model) * vec4(p.xyz, 1.0);\n" +
		"    vec3 n = normalize((mat3(model) * world.xyz));\n" +
		"    mat3 basis = mat3(n, vec3(0.0, 1.0, 0.0), vec3(1.0));\n" +
		"    vec2 uv = p.xy * vec2(textureSize(shadowMap, 0));\n" +
		"    vec3 up = basis * vec3(0.0, 1.0, 0.0);\n" +
		"    float lambert = (max(dot(n, up), 0.0) * p.w) / length(n);\n" +
		"    vec3 light = pow(max(((n * 0.5) + 0.5), vec3(0.0)), vec3(2.4)) - 1.0;\n" +
		"    vec3 bright = (2.0 * light) / n;\n" +
		"    vec3 curved = mix(clamp(light, vec3(0.0), vec3(1.0)), bright, min(lambert, 1.0));\n" +
		"    vec3 facing = ((p.z > 0.5) ? (light - n) : n);\n" +
		"    float shade = ((uv.y > 1.0) ? clamp(uv.x, 0.0, 1.0) : 1.0);\n" +
		"    vec4 texel = texelFetch(shadowMap, ivec2(uv), 0);\n" +
		"    fragColor = vec4((((curved * facing) * shade) + (texel.rgb * texel.r)), texel.a);\n" +
		"    return;\n" +
		"}\n";
	assert glsl(probeFs) == expected;
}

export struct TexturedProbeBindings {
	@binding(0) baseTexture: Texture2d;
	@binding(0) baseSampler: Sampler;
}

export function texturedProbeFs(input: ProbeInput, b: TexturedProbeBindings): Vec4f {
	const p = input.position;
	const uv = mat2x2f(p.xy, p.zw) * p.xy + p.zw * 0.5;
	const texel = textureSample(b.baseTexture, b.baseSampler, uv);
	const n = cross(texel.xyz, p.xyz);
	return texel.a > 0.5 ? vec4f(n, 1.0) : vec4f(0.0);
}

test "glsl spells the textured family's std names in their GLSL form" {
	const expected =
		"layout(binding=0) uniform texture2D baseTexture;\n" +
		"layout(binding=0) uniform sampler baseSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 p = gl_FragCoord;\n" +
		"    vec2 uv = (mat2(p.xy, p.zw) * p.xy) + (p.zw * 0.5);\n" +
		"    vec4 texel = texture(sampler2D(baseTexture, baseSampler), uv);\n" +
		"    vec3 n = cross(texel.xyz, p.xyz);\n" +
		"    fragColor = (texel.a > 0.5) ? vec4(n, 1.0) : vec4(0.0);\n" +
		"    return;\n" +
		"}\n";
	assert glsl(texturedProbeFs) == expected;
}

// Four texels in a row, the red channel of each its index.
function ramp(): Texture2d {
	return {
		width: 4,
		height: 1,
		texels: [0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 2.0, 0.0, 0.0, 1.0, 3.0, 0.0, 0.0, 1.0],
	};
}

function sampledAt(x: float32, nearest: boolean, wrap: Wrap): float32 {
	return textureSample(ramp(), { nearest, wrap }, vec2f(x, 0.5)).r;
}

test "textureSample's nearest filter takes the texel holding the coordinate, an edge the next one" {
	assert textureSample(ramp(), { nearest: true }, vec2f(0.375, 0.5)) == vec4f(1.0, 0.0, 0.0, 1.0);
	assert sampledAt(0.5, true, Wrap.Clamp) == 2.0 && sampledAt(0.999, true, Wrap.Clamp) == 3.0;
}

test "textureSample's linear filter weighs the two texels whose centres surround it" {
	assert sampledAt(0.375, false, Wrap.Clamp) == 1.0;
	assert sampledAt(0.25, false, Wrap.Clamp) == 0.5 && sampledAt(0.5, false, Wrap.Clamp) == 1.5;
	assert textureSample(ramp(), { nearest: false }, vec2f(0.625, 0.25)).a == 1.0;
}

test "textureSample wraps a texel index past the edge as the sampler's wrap says" {
	assert sampledAt(1.25, true, Wrap.Clamp) == 3.0 && sampledAt(-0.375, true, Wrap.Clamp) == 0.0;
	assert sampledAt(1.25, true, Wrap.Repeat) == 1.0 && sampledAt(-0.375, true, Wrap.Repeat) == 2.0;
	assert sampledAt(1.25, true, Wrap.Mirror) == 2.0 && sampledAt(-0.375, true, Wrap.Mirror) == 1.0;
	assert sampledAt(-0.125, true, Wrap.Mirror) == 0.0 && sampledAt(1.0, true, Wrap.Mirror) == 3.0;
	assert sampledAt(0.0, false, Wrap.Clamp) == 0.0 && sampledAt(0.0, false, Wrap.Repeat) == 1.5;
	assert sampledAt(0.0, false, Wrap.Mirror) == 0.0 && sampledAt(1.0, false, Wrap.Repeat) == 1.5;
}

export struct CubeProbeInput {
	@builtin(position) position: Vec4f;
}

export struct CubeProbeBindings {
	@binding(0) environment: TextureCube;
	@binding(0) environmentSampler: Sampler;
}

export function cubeProbeFs(input: CubeProbeInput, b: CubeProbeBindings): Vec4f {
	const dir = input.position.xyz;
	const sharp = textureSample(b.environment, b.environmentSampler, dir);
	const rough = textureSampleLevel(b.environment, b.environmentSampler, dir, input.position.w);
	return sharp + rough;
}

test "glsl spells a cube texture and textureSampleLevel in their GLSL form" {
	assert glsl(cubeProbeFs) ==
		"layout(binding=0) uniform textureCube environment;\n" +
		"layout(binding=0) uniform sampler environmentSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec3 dir = gl_FragCoord.xyz;\n" +
		"    vec4 sharp = texture(samplerCube(environment, environmentSampler), dir);\n" +
		"    vec4 rough = textureLod(samplerCube(environment, environmentSampler), dir, " +
		"gl_FragCoord.w);\n" +
		"    fragColor = sharp + rough;\n" +
		"    return;\n" +
		"}\n";
}

// One texel per face, the red channel of each its face index.
function faces(): TextureCube {
	let texels: float32[] = [];
	for (let face = 0; face < 6; face++) { texels.push(face as float32); texels.push(0.0); texels.push(0.0); texels.push(1.0); }
	return { size: 1, texels };
}

function faceAt(dir: Vec3f): float32 {
	return textureSample(faces(), { nearest: true }, dir).r;
}

test "a cube is read on the face of the direction's major axis, a tie going to x, then y" {
	assert faceAt(vec3f(1.0, 0.2, -0.3)) == 0.0 && faceAt(vec3f(-1.0, 0.2, 0.3)) == 1.0;
	assert faceAt(vec3f(0.2, 1.0, -0.3)) == 2.0 && faceAt(vec3f(0.2, -1.0, 0.3)) == 3.0;
	assert faceAt(vec3f(0.2, 0.3, 1.0)) == 4.0 && faceAt(vec3f(0.2, -0.3, -1.0)) == 5.0;
	assert faceAt(vec3f(1.0, 1.0, 1.0)) == 0.0 && faceAt(vec3f(0.5, -1.0, 1.0)) == 3.0;
	assert textureSampleLevel(faces(), { nearest: false }, vec3f(0.0, 0.0, -2.0), 3.0).r == 5.0;
}

test "select returns its second operand when the condition holds, as WGSL orders them" {
	assert select(1.0, 2.0, true) == 2.0 && select(1.0, 2.0, false) == 1.0;
	assert select(vec3f(1.0), vec3f(2.0), true) == vec3f(2.0);
}

function counting(): Mat4x4f {
	return mat4x4f(
		vec4f(1.0, 2.0, 3.0, 4.0),
		vec4f(5.0, 6.0, 7.0, 8.0),
		vec4f(9.0, 10.0, 11.0, 12.0),
		vec4f(13.0, 14.0, 15.0, 16.0),
	);
}

test "a matrix is its columns: m * v weighs column i by component i" {
	const v = counting() * vec4f(1.0, 2.0, 3.0, 4.0);
	assert v == vec4f(90.0, 100.0, 110.0, 120.0);
	const scaleThenMove = mat4x4f(
		vec4f(2.0, 0.0, 0.0, 0.0),
		vec4f(0.0, 3.0, 0.0, 0.0),
		vec4f(0.0, 0.0, 4.0, 0.0),
		vec4f(1.0, 1.0, 1.0, 1.0),
	);
	const p = vec4f(1.0, 1.0, 1.0, 1.0);
	assert (counting() * scaleThenMove) * p == counting() * (scaleThenMove * p);
}

test "a 2x2 matrix is its columns too, and cross follows the right-hand rule" {
	assert mat2x2f(vec2f(1.0, 2.0), vec2f(3.0, 4.0)) * vec2f(5.0, 6.0) == vec2f(23.0, 34.0);
	assert cross(vec3f(1.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0)) == vec3f(0.0, 0.0, 1.0);
	assert cross(vec3f(1.0, 2.0, 3.0), vec3f(4.0, 5.0, 6.0)) == vec3f(-3.0, 6.0, -3.0);
}

test "upperLeft3x3 keeps the first three rows of the first three columns, as GLSL mat3(m)" {
	const m = upperLeft3x3(counting());
	assert m == mat3x3f(vec3f(1.0, 2.0, 3.0), vec3f(5.0, 6.0, 7.0), vec3f(9.0, 10.0, 11.0));
	assert m * vec3f(1.0, 2.0, 3.0) == vec3f(38.0, 44.0, 50.0);
}

test "constructors splat, extend and convert" {
	assert vec3f(2.0) == vec3f(2.0, 2.0, 2.0);
	assert vec4f(2.0) == vec4f(2.0, 2.0, 2.0, 2.0);
	assert vec4f(vec3f(1.0, 2.0, 3.0), 4.0) == vec4f(1.0, 2.0, 3.0, 4.0);
	assert vec2f(vec2i(-3, 2)) == vec2f(-3.0, 2.0);
}

test "swizzles read the components they name" {
	const c = vec4f(1.0, 2.0, 3.0, 4.0);
	assert c.rgb == vec3f(1.0, 2.0, 3.0) && c.xyz == c.rgb && c.xy == vec2f(1.0, 2.0);
	assert c.zw == vec2f(3.0, 4.0);
	assert c.r == 1.0 && c.g == 2.0 && c.b == 3.0 && c.a == 4.0;
	const v = c.xyz;
	assert v.r == 1.0 && v.g == 2.0 && v.b == 3.0 && v.xy == vec2f(1.0, 2.0);
}

test "vector arithmetic is componentwise, a scalar operand applies to every component" {
	const v = vec3f(1.0, 2.0, 4.0);
	assert v + v == vec3f(2.0, 4.0, 8.0) && v - vec3f(1.0) == vec3f(0.0, 1.0, 3.0);
	assert v * v == vec3f(1.0, 4.0, 16.0) && v / vec3f(1.0, 2.0, 4.0) == vec3f(1.0);
	assert v + 1.0 == vec3f(2.0, 3.0, 5.0) && v - 1.0 == vec3f(0.0, 1.0, 3.0);
	assert v * 2.0 == 2.0 * v && v / 2.0 == vec3f(0.5, 1.0, 2.0);
	assert -v == vec3f(-1.0, -2.0, -4.0);
	assert vec2f(2.0, 3.0) * vec2f(4.0, 5.0) == vec2f(8.0, 15.0);
	assert vec2f(2.0, 3.0) + vec2f(4.0, 5.0) == vec2f(6.0, 8.0);
	assert vec2f(2.0, 3.0) * 2.0 == vec2f(4.0, 6.0);
	let sum = v;
	sum += v;
	assert sum == v * 2.0;
}

test "numeric builtins compute WGSL's definitions" {
	assert max(1.0, 2.0) == 2.0 && min(1.0, 2.0) == 1.0;
	assert max(vec3f(1.0, 5.0, 0.0), vec3f(2.0)) == vec3f(2.0, 5.0, 2.0);
	assert min(vec3f(1.0, 5.0, 0.0), vec3f(2.0)) == vec3f(1.0, 2.0, 0.0);
	assert clamp(1.5, 0.0, 1.0) == 1.0 && clamp(-1.0, 0.0, 1.0) == 0.0;
	assert clamp(vec3f(-1.0, 0.5, 2.0), vec3f(0.0), vec3f(1.0)) == vec3f(0.0, 0.5, 1.0);
	assert mix(2.0, 4.0, 0.25) == 2.5 && mix(vec3f(2.0), vec3f(4.0), 0.25) == vec3f(2.5);
	assert pow(4.0, 0.5) == 2.0 && pow(0.0, 2.4) == 0.0;
	assert pow(vec3f(4.0, 9.0, 0.0), vec3f(0.5)) == vec3f(2.0, 3.0, 0.0);
	assert dot(vec3f(1.0, 2.0, 3.0), vec3f(4.0, 5.0, 6.0)) == 32.0;
	assert length(vec3f(2.0, 3.0, 6.0)) == 7.0;
	assert normalize(vec3f(0.0, 0.0, -2.0)) == vec3f(0.0, 0.0, -1.0);
}

export function mathProbeFs(input: ProbeInput): Vec4f {
	const p = input.position;
	const wave = sin(p.x) + cos(p.y) + tan(p.z) + asin(p.w);
	const arc = acos(p.x) + atan(p.y) + atan2(p.y, p.x);
	const hyper = sinh(p.x) + cosh(p.y) + tanh(p.z);
	const grow = exp(p.x) + exp2(p.y) + log(p.z) + log2(p.w);
	const root = sqrt(p.x) + inverseSqrt(p.y);
	const whole = abs(p.xy) + sign(p.zw) + floor(p.yx);
	const edge = ceil(p.wz) + round(p.xy) + trunc(p.zw);
	const parts = fract(p.xyz) + p.xyz % 2.0;
	const ramp = saturate(p.zyx) + step(p.xyz, p.zxy);
	const eased = smoothstep(0.0, 1.0, p.x) + fma(p.x, p.y, p.z);
	const angle = degrees(p.w) + radians(vec3f(wave + arc, hyper + grow, root));
	const rest = whole.x % edge.y;
	return vec4f(parts + ramp * eased + angle, rest);
}

test "glsl spells the numeric builtins in their GLSL form, % as WGSL's truncated remainder" {
	const expected =
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 p = gl_FragCoord;\n" +
		"    float wave = ((sin(p.x) + cos(p.y)) + tan(p.z)) + asin(p.w);\n" +
		"    float arc = (acos(p.x) + atan(p.y)) + atan(p.y, p.x);\n" +
		"    float hyper = (sinh(p.x) + cosh(p.y)) + tanh(p.z);\n" +
		"    float grow = ((exp(p.x) + exp2(p.y)) + log(p.z)) + log2(p.w);\n" +
		"    float root = sqrt(p.x) + inversesqrt(p.y);\n" +
		"    vec2 whole = (abs(p.xy) + sign(p.zw)) + floor(p.yx);\n" +
		"    vec2 edge = (ceil(p.wz) + roundEven(p.xy)) + trunc(p.zw);\n" +
		"    vec3 parts = fract(p.xyz) + (p.xyz - 2.0 * trunc(p.xyz / 2.0));\n" +
		"    vec3 ramp = clamp(p.zyx, 0.0, 1.0) + step(p.xyz, p.zxy);\n" +
		"    float eased = smoothstep(0.0, 1.0, p.x) + fma(p.x, p.y, p.z);\n" +
		"    vec3 angle = degrees(p.w) + radians(vec3((wave + arc), (hyper + grow), root));\n" +
		"    float rest = whole.x - edge.y * trunc(whole.x / edge.y);\n" +
		"    fragColor = vec4(((parts + (ramp * eased)) + angle), rest);\n" +
		"    return;\n" +
		"}\n";
	assert glsl(mathProbeFs) == expected;
}

export function shapeProbeFs(input: ProbeInput): Vec4f {
	const p = input.position;
	const n = normalize(p.xyz);
	const bounced = reflect(n, p.zyx) + refract(n, p.zyx, 0.5);
	const facing = faceForward(n, p.yzx, p.xyz);
	const spread = distance(p.xy, p.yx) + dpdx(p.x) + dpdy(p.y) + fwidth(p.z);
	const turn = mat2x2f(p.x, p.y, p.z, p.w);
	const frame = mat3x3f(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, p.x, p.y, 1.0);
	const lens = inverse(frame) * transpose(frame * frame) * (bounced + facing);
	const plane = 1.0 - turn * turn * p.xy / determinant(turn) + 0.5;
	const cell = vec3u(vec3i(p.xyz));
	const texel = -vec2i(p.zw) * 2 - vec2i(1, 1);
	const back = vec4f(vec4i(vec4u(vec4i(p)))) + vec4f(vec4u(vec4i(p.wzyx)));
	const turned = inverse(mat4x4f(p, p.yzwx, p.zwxy, p.wxyz)) * back;
	const grid = vec4f(vec3f(cell), vec2f(texel).y);
	return vec4f(lens * spread, plane.x) + grid + turned.zyxw;
}

test "glsl spells the geometric, matrix, derivative and integer vector names in their GLSL form" {
	const expected =
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 p = gl_FragCoord;\n" +
		"    vec3 n = normalize(p.xyz);\n" +
		"    vec3 bounced = reflect(n, p.zyx) + refract(n, p.zyx, 0.5);\n" +
		"    vec3 facing = faceforward(n, p.yzx, p.xyz);\n" +
		"    float spread = ((distance(p.xy, p.yx) + dFdx(p.x)) + dFdy(p.y)) + fwidth(p.z);\n" +
		"    mat2 turn = mat2(p.x, p.y, p.z, p.w);\n" +
		"    mat3 frame = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, p.x, p.y, 1.0);\n" +
		"    vec3 lens = (inverse(frame) * transpose((frame * frame))) * (bounced + facing);\n" +
		"    vec2 plane = (1.0 - (((turn * turn) * p.xy) / determinant(turn))) + 0.5;\n" +
		"    uvec3 cell = uvec3(ivec3(p.xyz));\n" +
		"    ivec2 texel = ((-ivec2(p.zw)) * 2) - ivec2(1, 1);\n" +
		"    vec4 back = vec4(ivec4(uvec4(ivec4(p)))) + vec4(uvec4(ivec4(p.wzyx)));\n" +
		"    vec4 turned = inverse(mat4(p, p.yzwx, p.zwxy, p.wxyz)) * back;\n" +
		"    vec4 grid = vec4(vec3(cell), vec2(texel).y);\n" +
		"    fragColor = (vec4((lens * spread), plane.x) + grid) + turned.zyxw;\n" +
		"    return;\n" +
		"}\n";
	assert glsl(shapeProbeFs) == expected;
}

export function columnProbeFs(input: ProbeInput): Vec4f {
	const p = input.position;
	let frame = mat3x3f(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, p.x, p.y, 1.0);
	frame.columns[1] = frame.columns[2] * 2.0;
	return vec4f(frame.columns[1] + frame.columns[0], 1.0);
}

test "a matrix column is m[i] in GLSL, read and written, as WGSL's m[i]" {
	assert glsl(columnProbeFs) ==
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 p = gl_FragCoord;\n" +
		"    mat3 frame = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, p.x, p.y, 1.0);\n" +
		"    frame[1] = frame[2] * 2.0;\n" +
		"    fragColor = vec4((frame[1] + frame[0]), 1.0);\n" +
		"    return;\n" +
		"}\n";
	assert columnProbeFs({ position: vec4f(3.0, 4.0, 0.0, 1.0) }) == vec4f(7.0, 8.0, 2.0, 1.0);
}

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 1.0e-5; }

function near(a: Vec4f, b: Vec4f): boolean {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z) && near(a.w, b.w);
}

test "% on floats truncates as WGSL's does, where GLSL's mod floors" {
	assert 5.5 % 2.0 == 1.5 && -0.5 % 1.0 == -0.5 && 0.5 % -1.0 == 0.5;
	assert vec2f(-0.5, 2.5) % vec2f(1.0) == vec2f(-0.5, 0.5);
	assert vec3f(-2.5, 2.5, 7.0) % 2.0 == vec3f(-0.5, 0.5, 1.0);
	assert 5.0 % vec4f(2.0, -2.0, 3.0, 5.0) == vec4f(1.0, 1.0, 2.0, 0.0);
}

test "round takes a tie to the even integer, as WGSL's does" {
	assert round(2.5) == 2.0 && round(-2.5) == -2.0 && round(1.5) == 2.0 && round(-0.5) == 0.0;
	assert round(0.4) == 0.0 && round(-0.6) == -1.0 && round(3.5) == 4.0;
	assert round(vec2f(0.5, 1.5)) == vec2f(0.0, 2.0);
}

test "sign is 0 at 0, and floor, ceil, trunc and fract part at a negative operand" {
	assert sign(0.0) == 0.0 && sign(-3.0) == -1.0 && sign(2.0) == 1.0;
	assert sign(0) == 0 && sign(-7) == -1 && abs(-7) == 7 && abs(-2.5) == 2.5;
	assert floor(-1.5) == -2.0 && ceil(-1.5) == -1.0 && trunc(-1.5) == -1.0;
	assert fract(-0.5) == 0.5 && fract(1.5) == 0.5 && fract(-1.25) == 0.75;
	assert sign(vec3f(-2.0, 0.0, 2.0)) == vec3f(-1.0, 0.0, 1.0);
}

test "abs of the least int32 is that value, as WGSL's, where negating it overflows" {
	const least: int32 = -2147483648;
	assert abs(least) == least && abs(least + 1) == 2147483647;
}

test "atan2 takes y first and answers in the quadrant of (x, y)" {
	assert near(atan2(1.0, -1.0), 2.3561945) && near(atan2(-1.0, -1.0), -2.3561945);
	assert near(atan2(1.0, 0.0), 1.5707964) && atan2(0.0, 1.0) == 0.0;
	assert near(atan(1.0), 0.7853982);
}

test "step is 1 at its edge, and smoothstep is 0 and 1 at its edges" {
	assert step(1.0, 1.0) == 1.0 && step(1.0, 0.5) == 0.0 && step(1.0, 2.0) == 1.0;
	assert smoothstep(0.0, 1.0, 0.0) == 0.0 && smoothstep(0.0, 1.0, 1.0) == 1.0;
	assert smoothstep(0.0, 1.0, -1.0) == 0.0 && smoothstep(0.0, 1.0, 2.0) == 1.0;
	assert smoothstep(0.0, 1.0, 0.5) == 0.5 && smoothstep(2.0, 4.0, 3.0) == 0.5;
	assert smoothstep(vec2f(0.0), vec2f(1.0, 2.0), vec2f(0.25, 1.0)) == vec2f(0.15625, 0.5);
	assert saturate(-1.0) == 0.0 && saturate(0.25) == 0.25 && saturate(vec2f(2.0)) == vec2f(1.0);
}

test "exponents, roots and angles compute WGSL's definitions" {
	assert exp2(3.0) == 8.0 && log2(8.0) == 3.0 && near(exp(1.0), 2.7182817) && log(1.0) == 0.0;
	assert sqrt(9.0) == 3.0 && inverseSqrt(4.0) == 0.5 && inverseSqrt(vec2f(4.0)) == vec2f(0.5);
	assert near(degrees(3.1415927), 180.0) && near(radians(180.0), 3.1415927);
	assert sin(0.0) == 0.0 && cos(0.0) == 1.0 && near(tan(0.7853982), 1.0);
	assert asin(1.0) == 1.5707964 && acos(1.0) == 0.0 && tanh(0.0) == 0.0;
	assert sinh(0.0) == 0.0 && cosh(0.0) == 1.0 && fma(2.0, 3.0, 4.0) == 10.0;
	assert mix(vec2f(0.0), vec2f(4.0), vec2f(0.25, 0.5)) == vec2f(1.0, 2.0);
	assert min(3, 2) == 2 && max(-3, 2) == 2 && clamp(9, 0, 4) == 4;
	assert clamp(9 as uint32, 1 as uint32, 4 as uint32) == 4 as uint32;
}

test "the geometric builtins compute WGSL's definitions" {
	const up = vec3f(0.0, 1.0, 0.0);
	assert distance(vec2f(1.0, 1.0), vec2f(4.0, 5.0)) == 5.0 && length(vec2f(3.0, 4.0)) == 5.0;
	assert dot(vec4f(1.0, 2.0, 3.0, 4.0), vec4f(1.0)) == 10.0;
	assert normalize(vec2f(0.0, -3.0)) == vec2f(0.0, -1.0);
	assert reflect(vec3f(1.0, -1.0, 0.0), up) == vec3f(1.0, 1.0, 0.0);
	assert refract(vec3f(0.0, -1.0, 0.0), up, 0.5) == vec3f(0.0, -1.0, 0.0);
	const grazing = normalize(vec3f(1.0, -0.1, 0.0));
	assert refract(grazing, up, 1.5) == vec3f(0.0);
	assert faceForward(up, vec3f(0.0, -1.0, 0.0), up) == up;
	assert faceForward(up, vec3f(1.0, 0.0, 0.0), up) == -up;
}

function skewed(): Mat4x4f {
	return mat4x4f(
		vec4f(2.0, 0.0, 1.0, 0.0),
		vec4f(1.0, 3.0, 0.0, 0.0),
		vec4f(0.0, 1.0, 4.0, 1.0),
		vec4f(1.0, 0.0, 0.0, 2.0),
	);
}

test "transpose, determinant and inverse of each matrix size" {
	const m2 = mat2x2f(1.0, 2.0, 3.0, 4.0);
	assert m2 == mat2x2f(vec2f(1.0, 2.0), vec2f(3.0, 4.0));
	assert transpose(m2) == mat2x2f(1.0, 3.0, 2.0, 4.0) && determinant(m2) == -2.0;
	assert inverse(m2) * m2 == mat2x2f(1.0, 0.0, 0.0, 1.0);
	const m3 = mat3x3f(2.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 3.0, 4.0);
	assert transpose(m3) == mat3x3f(2.0, 1.0, 0.0, 0.0, 1.0, 3.0, 0.0, 0.0, 4.0);
	assert determinant(m3) == 8.0 && determinant(upperLeft3x3(counting())) == 0.0;
	assert inverse(m3) * m3 == mat3x3f(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
	assert transpose(transpose(counting())) == counting();
	assert transpose(counting()).columns[0] == vec4f(1.0, 5.0, 9.0, 13.0);
	assert determinant(counting()) == 0.0 && determinant(skewed()) == 53.0;
	const identity = inverse(skewed()) * skewed();
	assert near(identity.columns[0], vec4f(1.0, 0.0, 0.0, 0.0));
	assert near(identity.columns[1], vec4f(0.0, 1.0, 0.0, 0.0));
	assert near(identity.columns[2], vec4f(0.0, 0.0, 1.0, 0.0));
	assert near(identity.columns[3], vec4f(0.0, 0.0, 0.0, 1.0));
}

test "a float vector has every swizzle WGSL spells, rgba as xyzw; an integer one xy and xyz" {
	const c = vec4f(1.0, 2.0, 3.0, 4.0);
	assert c.zyxw == vec4f(3.0, 2.0, 1.0, 4.0) && c.wwxy == vec4f(4.0, 4.0, 1.0, 2.0);
	assert c.bgra == c.zyxw && c.ar == vec2f(4.0, 1.0) && c.xyz.zzx == vec3f(3.0, 3.0, 1.0);
	assert vec2f(1.0, 2.0).yx == vec2f(2.0, 1.0) && vec2f(1.0, 2.0).g == 2.0;
	assert vec3u(1 as uint32, 2 as uint32, 3 as uint32).xy == vec2u(1 as uint32, 2 as uint32);
	assert vec4i(5, 6, 7, 8).xyz == vec3i(5, 6, 7) && vec3i(5, 6, 7).xy == vec2i(5, 6);
}

test "integer vectors convert as WGSL converts: truncated from floats, bits kept between signs" {
	assert vec2i(vec2f(-1.5, 1.5)) == vec2i(-1, 1);
	assert vec3i(vec3f(2.9, -2.9, 0.0)) == vec3i(2, -2, 0);
	const wrapped = vec3u(vec3i(-1, 0, 2));
	assert wrapped.x == 4294967295 as uint32 && wrapped.z == 2 as uint32;
	assert vec3i(wrapped) == vec3i(-1, 0, 2) && vec4i(vec4u(vec4i(-2, 1, 0, 3))).x == -2;
	assert vec3f(vec3u(vec3i(1, 2, 3))) == vec3f(1.0, 2.0, 3.0);
	assert vec2f(vec2u(vec2i(7, 8))).y == 8.0;
	assert vec4f(vec4i(-1, 0, 1, 2)) == vec4f(-1.0, 0.0, 1.0, 2.0);
}

test "a scalar operand of a vector operator applies to every component, on either side" {
	assert 1.0 - vec2f(0.25, 0.5) == vec2f(0.75, 0.5);
	assert 2.0 / vec4f(1.0, 2.0, 4.0, 8.0).xy == vec2f(2.0, 1.0);
	assert vec4f(1.0) + 1.0 == vec4f(2.0) && 3.0 + vec3f(1.0) == vec3f(4.0);
	assert -vec4f(1.0) == vec4f(-1.0) && -vec2i(1, -1) == vec2i(-1, 1);
	assert vec2i(3, 4) * 2 - 1 == vec2i(5, 7) && 10 - vec2i(3, 4) == vec2i(7, 6);
	const quarter = mat2x2f(0.0, 1.0, -1.0, 0.0);
	assert quarter * quarter == mat2x2f(-1.0, 0.0, 0.0, -1.0);
	const frame = mat3x3f(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 2.0, 3.0, 1.0);
	assert (frame * frame) * vec3f(0.0, 0.0, 1.0) == vec3f(4.0, 6.0, 1.0);
}

test "the mandelbrot step and mathFrag colour compute on the CPU" {
	const o = vec2f(0.25, 0.5);
	const v = 0.55 - mat2x2f(-o.y, o.x, o.x, o.y) * vec2f(o.y, o.x) + vec2f(0.1, 0.2);
	assert near(v.x, 0.8375) && near(v.y, 0.5);
	const color = vec4f(1.0, 0.0, 0.0, 1.0);
	const f = color.xyz * dot(vec3f(0.0, 1.0, 0.0), normalize(vec3f(1.0, 1.0, 1.0)));
	assert near(f.x, 0.5773503) && f.y == 0.0;
}
