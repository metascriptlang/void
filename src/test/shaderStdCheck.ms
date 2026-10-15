// The CPU meaning of ./shader/std where its GLSL spelling or meaning parts from WGSL's
// (docs/VOCABULARY.md, "A name brings its meaning"), and the GLSL the glsl macro spells for it.

import { glsl } from "../shader/emit";
import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec4f,
	binding,
	builtin,
	clamp,
	cross,
	dot,
	length,
	mat2x2f,
	mat3x3f,
	mat4x4f,
	max,
	min,
	mix,
	normalize,
	pow,
	select,
	textureDimensions,
	textureLoad,
	upperLeft3x3,
	vec2f,
	vec2i,
	vec3f,
	vec4f,
} from "../shader/std";

export struct ProbeInput {
	@builtin(position) position: Vec4f;
}

export struct ProbeBindings {
	@binding(0) shadowMap: Texture2d;
	@binding(0) shadowSampler: Sampler;
}

export function probeFs(input: ProbeInput, b: ProbeBindings): Vec4f {
	const p = input.position;
	const model = mat4x4f(p, p, p, vec4f(0.0, 0.0, 0.0, 1.0));
	const world = model * model * vec4f(p.xyz, 1.0);
	const n = normalize(upperLeft3x3(model) * world.xyz);
	const basis = mat3x3f(n, vec3f(0.0, 1.0, 0.0), vec3f(1.0));
	const uv = p.xy * vec2f(textureDimensions(b.shadowMap, b.shadowSampler, 0));
	const up = basis * vec3f(0.0, 1.0, 0.0);
	const lambert = max(dot(n, up), 0.0) * p.w / length(n);
	const light = pow(max(n * 0.5 + 0.5, vec3f(0.0)), vec3f(2.4)) - 1.0;
	const bright = 2.0 * light / n;
	const curved = mix(clamp(light, vec3f(0.0), vec3f(1.0)), bright, min(lambert, 1.0));
	const facing = select(n, light - n, p.z > 0.5);
	const shade = select(1.0, clamp(uv.x, 0.0, 1.0), uv.y > 1.0);
	const texel = textureLoad(b.shadowMap, b.shadowSampler, vec2i(uv), 0);
	return vec4f(curved * facing * shade + texel.rgb * texel.r, texel.a);
}

test "glsl spells every std name in its GLSL form" {
	const expected =
		"layout(binding=0) uniform texture2D shadowMap;\n" +
		"layout(binding=0) uniform sampler shadowSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 p = gl_FragCoord;\n" +
		"    mat4 model = mat4(p, p, p, vec4(0.0, 0.0, 0.0, 1.0));\n" +
		"    vec4 world = (model * model) * vec4(p.xyz, 1.0);\n" +
		"    vec3 n = normalize((mat3(model) * world.xyz));\n" +
		"    mat3 basis = mat3(n, vec3(0.0, 1.0, 0.0), vec3(1.0));\n" +
		"    vec2 uv = p.xy * vec2(textureSize(sampler2D(shadowMap, shadowSampler), 0));\n" +
		"    vec3 up = basis * vec3(0.0, 1.0, 0.0);\n" +
		"    float lambert = (max(dot(n, up), 0.0) * p.w) / length(n);\n" +
		"    vec3 light = pow(max(((n * 0.5) + 0.5), vec3(0.0)), vec3(2.4)) - 1.0;\n" +
		"    vec3 bright = (2.0 * light) / n;\n" +
		"    vec3 curved = mix(clamp(light, vec3(0.0), vec3(1.0)), bright, min(lambert, 1.0));\n" +
		"    vec3 facing = ((p.z > 0.5) ? (light - n) : n);\n" +
		"    float shade = ((uv.y > 1.0) ? clamp(uv.x, 0.0, 1.0) : 1.0);\n" +
		"    vec4 texel = texelFetch(sampler2D(shadowMap, shadowSampler), ivec2(uv), 0);\n" +
		"    fragColor = vec4((((curved * facing) * shade) + (texel.rgb * texel.r)), texel.a);\n" +
		"    return;\n" +
		"}\n";
	assert glsl(probeFs) == expected;
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
