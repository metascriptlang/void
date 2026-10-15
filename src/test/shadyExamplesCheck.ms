// treeform/shady's shader-toy examples (examples/{circle,colors,flare,mandelbrot}.nim) written as
// Void fragment entries: each runs on the CPU and its GLSL is pinned. The pixel is measured from
// the target's centre, as shady's `uv` is; toy.x is the time, toy.yz half the target size.

import { glsl } from "../shader/emit";
import {
	Vec2f,
	Vec3f,
	Vec4f,
	abs,
	binding,
	builtin,
	cos,
	floor,
	length,
	mat2x2f,
	mat3x3f,
	pow,
	sin,
	vec2f,
	vec3f,
	vec4f,
} from "../shader/std";

export struct ToyInput {
	@builtin(position) position: Vec4f;
}

export struct ToyParams {
	toy: Vec4f;
}

export struct ToyBindings {
	@binding(0) toyParams: ToyParams;
}

const PI: float32 = 3.14159265;

function uvOf(input: ToyInput, b: ToyBindings): Vec2f {
	return input.position.xy - b.toyParams.toy.yz;
}

export function circleFs(input: ToyInput, b: ToyBindings): Vec4f {
	const radius = 300.0 + 100.0 * sin(b.toyParams.toy.x);
	if (length(uvOf(input, b)) < radius) {
		return vec4f(1.0, 1.0, 1.0, 1.0);
	}
	return vec4f(0.0, 0.0, 0.0, 1.0);
}

export function circleSmoothFs(input: ToyInput, b: ToyBindings): Vec4f {
	const uv = uvOf(input, b);
	const radius = 300.0 + 100.0 * sin(b.toyParams.toy.x);
	let a: float32 = 0.0;
	for (let x = 0; x < 8; x++) {
		for (let y = 0; y < 8; y++) {
			const offset = vec2f((x as float32) - 4.0, (y as float32) - 4.0) / 8.0;
			if (length(uv + offset) < radius) {
				a += 1.0;
			}
		}
	}
	a = a / 64.0;
	return vec4f(a, a, a, 1.0);
}

function toRgb(ycbcr: Vec3f): Vec3f {
	const c709 = mat3x3f(
		1.0, 1.0, 1.0,
		0.0, -0.1873242729, 1.8556,
		1.5748, -0.4681242729, 0.0,
	);
	return c709 * ycbcr;
}

function rot(uv: Vec2f, r: float32): Vec2f {
	const s = sin(r);
	const c = cos(r);
	return vec2f(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

function vsphere(x: float32): Vec2f {
	return vec2f(sin(x * PI), cos(x * PI));
}

export function colorsFs(input: ToyInput, b: ToyBindings): Vec4f {
	const time = b.toyParams.toy.x;
	let pos = uvOf(input, b) / 300.0;
	pos = rot(pos, time * PI * 0.5);
	const inv = 1.0 / length(pos);
	pos = pos * inv;
	const cbcr = vsphere(pos.x + time) * sin(time * 0.5) * 0.5;
	const col = toRgb(vec3f(inv * 0.3, cbcr.x, cbcr.y)) * inv * 0.5;
	return vec4f(col.x, col.y, col.z, 1.0);
}

// shady's `mod` is GLSL's floored one: x - floor(x).
export function flareFs(input: ToyInput, b: ToyBindings): Vec4f {
	const uv = uvOf(input, b);
	let c = vec3f(0.0);
	let l: float32 = 0.0;
	let z = b.toyParams.toy.x;
	for (let i = 0; i < 3; i++) {
		const p = uv / 500.0;
		let pos = p;
		z += 0.07;
		l = length(p);
		pos = pos + p / l * (sin(z) + 1.0) * abs(sin(l * 9.0 - z * 2.0));
		const glow = 0.01 / length(abs(pos - floor(pos)) - 0.5);
		if (i == 0) {
			c.x = glow;
		} else if (i == 1) {
			c.y = glow;
		} else {
			c.z = glow;
		}
	}
	const v = c / l;
	return vec4f(v.x, v.y, v.z, b.toyParams.toy.x);
}

function mandelbrotInner(zoom: Vec2f): Vec2f {
	let o = vec2f(0.0, 0.0);
	let w: float32 = 0.0;
	while (w < 98.0) {
		w += 1.0;
		const v = 0.55 - mat2x2f(-o.y, o.x, o.x, o.y) * vec2f(o.y, o.x) + zoom;
		o.x = v.x;
		o.y = v.y;
	}
	return o;
}

export function mandelbrotFs(input: ToyInput, b: ToyBindings): Vec4f {
	const uv = uvOf(input, b);
	let a = vec2f(0.0, 0.0);
	for (let x = 0; x < 8; x++) {
		for (let y = 0; y < 8; y++) {
			const pos = uv + vec2f(x as float32, y as float32) / 8.0;
			const zoom = (pos / 700.0 - 0.2) * (2.0 / pow(2.0, b.toyParams.toy.x));
			a = a + mandelbrotInner(zoom);
		}
	}
	a = a / 64.0;
	let shade: float32 = 0.0;
	if (a.x < 0.0 && a.y < 0.0) {
		shade = -a.x - a.y;
	}
	return vec4f(a.x + 1.0, a.y, shade, 1.0);
}

function at(x: float32, y: float32): ToyInput {
	return { position: vec4f(x, y, 0.5, 1.0) };
}

function bindings(time: float32): ToyBindings {
	return { toyParams: { toy: vec4f(time, 400.0, 300.0, 0.0) } };
}

function finite(v: Vec4f): boolean {
	return v.x == v.x && v.y == v.y && v.z == v.z && Math.abs(v.x) < 1e30 && Math.abs(v.y) < 1e30;
}

test "circle is white inside its radius and black beyond it" {
	assert circleFs(at(400.5, 300.5), bindings(0.0)).x == 1.0;
	assert circleFs(at(0.5, 0.5), bindings(0.0)).x == 0.0;
	const edge = circleSmoothFs(at(700.0, 300.0), bindings(0.0)).x;
	assert edge > 0.0 && edge < 1.0;
}

test "colors, flare and mandelbrot give a finite colour where shady's own test samples" {
	assert finite(colorsFs(at(500.0, 400.0), bindings(0.0)));
	assert finite(flareFs(at(500.0, 400.0), bindings(0.0)));
	assert finite(mandelbrotFs(at(500.0, 400.0), bindings(0.0)));
}

test "circle" {
	assert glsl(circleFs) ==
		"layout(binding=0) uniform toyParams {\n" +
		"    vec4 toy;\n" +
		"};\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"vec2 uvOf() {\n" +
		"    return gl_FragCoord.xy - toy.yz;\n" +
		"}\n" +
		"void main() {\n" +
		"    float radius = 300.0 + (100.0 * sin(toy.x));\n" +
		"    if (length(uvOf()) < radius) {\n" +
		"        fragColor = vec4(1.0, 1.0, 1.0, 1.0);\n" +
		"        return;\n" +
		"    }\n" +
		"    fragColor = vec4(0.0, 0.0, 0.0, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "circleSmooth" {
	assert glsl(circleSmoothFs) ==
		"layout(binding=0) uniform toyParams {\n" +
		"    vec4 toy;\n" +
		"};\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"vec2 uvOf() {\n" +
		"    return gl_FragCoord.xy - toy.yz;\n" +
		"}\n" +
		"void main() {\n" +
		"    vec2 uv = uvOf();\n" +
		"    float radius = 300.0 + (100.0 * sin(toy.x));\n" +
		"    float a = 0.0;\n" +
		"    for (int x = 0; x < 8; x++) {\n" +
		"        for (int y = 0; y < 8; y++) {\n" +
		"            vec2 offset = vec2((float(x) - 4.0), (float(y) - 4.0)) / 8.0;\n" +
		"            if (length((uv + offset)) < radius) {\n" +
		"                a += 1.0;\n" +
		"            }\n" +
		"        }\n" +
		"    }\n" +
		"    a = a / 64.0;\n" +
		"    fragColor = vec4(a, a, a, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "colors" {
	assert glsl(colorsFs) ==
		"layout(binding=0) uniform toyParams {\n" +
		"    vec4 toy;\n" +
		"};\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"vec2 uvOf() {\n" +
		"    return gl_FragCoord.xy - toy.yz;\n" +
		"}\n" +
		"vec2 rot(vec2 uv, float r) {\n" +
		"    float s = sin(r);\n" +
		"    float c = cos(r);\n" +
		"    return vec2(((uv.x * c) - (uv.y * s)), ((uv.x * s) + (uv.y * c)));\n" +
		"}\n" +
		"const float PI = 3.14159265;\n" +
		"vec2 vsphere(float x) {\n" +
		"    return vec2(sin((x * PI)), cos((x * PI)));\n" +
		"}\n" +
		"vec3 toRgb(vec3 ycbcr) {\n" +
		"    mat3 c709 = mat3(1.0, 1.0, 1.0, 0.0, -0.1873242729, 1.8556, 1.5748, -0.4681242729, 0.0);\n" +
		"    return c709 * ycbcr;\n" +
		"}\n" +
		"void main() {\n" +
		"    float time = toy.x;\n" +
		"    vec2 pos = uvOf() / 300.0;\n" +
		"    pos = rot(pos, ((time * PI) * 0.5));\n" +
		"    float inv = 1.0 / length(pos);\n" +
		"    pos = pos * inv;\n" +
		"    vec2 cbcr = (vsphere((pos.x + time)) * sin((time * 0.5))) * 0.5;\n" +
		"    vec3 col = (toRgb(vec3((inv * 0.3), cbcr.x, cbcr.y)) * inv) * 0.5;\n" +
		"    fragColor = vec4(col.x, col.y, col.z, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "flare" {
	assert glsl(flareFs) ==
		"layout(binding=0) uniform toyParams {\n" +
		"    vec4 toy;\n" +
		"};\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"vec2 uvOf() {\n" +
		"    return gl_FragCoord.xy - toy.yz;\n" +
		"}\n" +
		"void main() {\n" +
		"    vec2 uv = uvOf();\n" +
		"    vec3 c = vec3(0.0);\n" +
		"    float l = 0.0;\n" +
		"    float z = toy.x;\n" +
		"    for (int i = 0; i < 3; i++) {\n" +
		"        vec2 p = uv / 500.0;\n" +
		"        vec2 pos = p;\n" +
		"        z += 0.07;\n" +
		"        l = length(p);\n" +
		"        pos = pos + (((p / l) * (sin(z) + 1.0)) * abs(sin(((l * 9.0) - (z * 2.0)))));\n" +
		"        float glow = 0.01 / length((abs((pos - floor(pos))) - 0.5));\n" +
		"        if (i == 0) {\n" +
		"            c.x = glow;\n" +
		"        } else if (i == 1) {\n" +
		"            c.y = glow;\n" +
		"        } else {\n" +
		"            c.z = glow;\n" +
		"        }\n" +
		"    }\n" +
		"    vec3 v = c / l;\n" +
		"    fragColor = vec4(v.x, v.y, v.z, toy.x);\n" +
		"    return;\n" +
		"}\n";
}

test "mandelbrot" {
	assert glsl(mandelbrotFs) ==
		"layout(binding=0) uniform toyParams {\n" +
		"    vec4 toy;\n" +
		"};\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"vec2 uvOf() {\n" +
		"    return gl_FragCoord.xy - toy.yz;\n" +
		"}\n" +
		"vec2 mandelbrotInner(vec2 zoom) {\n" +
		"    vec2 o = vec2(0.0, 0.0);\n" +
		"    float w = 0.0;\n" +
		"    while (w < 98.0) {\n" +
		"        w += 1.0;\n" +
		"        vec2 v = (0.55 - (mat2((-o.y), o.x, o.x, o.y) * vec2(o.y, o.x))) + zoom;\n" +
		"        o.x = v.x;\n" +
		"        o.y = v.y;\n" +
		"    }\n" +
		"    return o;\n" +
		"}\n" +
		"void main() {\n" +
		"    vec2 uv = uvOf();\n" +
		"    vec2 a = vec2(0.0, 0.0);\n" +
		"    for (int x = 0; x < 8; x++) {\n" +
		"        for (int y = 0; y < 8; y++) {\n" +
		"            vec2 pos = uv + (vec2(float(x), float(y)) / 8.0);\n" +
		"            vec2 zoom = ((pos / 700.0) - 0.2) * (2.0 / pow(2.0, toy.x));\n" +
		"            a = a + mandelbrotInner(zoom);\n" +
		"        }\n" +
		"    }\n" +
		"    a = a / 64.0;\n" +
		"    float shade = 0.0;\n" +
		"    if ((a.x < 0.0) && (a.y < 0.0)) {\n" +
		"        shade = (-a.x) - a.y;\n" +
		"    }\n" +
		"    fragColor = vec4((a.x + 1.0), a.y, shade, 1.0);\n" +
		"    return;\n" +
		"}\n";
}
