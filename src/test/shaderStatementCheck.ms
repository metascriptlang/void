// The statements and value types glsl emits beyond the basic forms: switch and match, writes to a
// local's field or element, the author's structs, uint32 '%' and integer varyings, each pinned as
// GLSL text and run on the CPU.

import { glsl, glslLinked } from "../shader/emit";
import { Vec2i, Vec3f, Vec4f, builtin, dot, max, vec2i, vec3f, vec4f } from "../shader/std";

struct ProbeInput {
	@builtin(position) position: Vec4f;
}

function at(x: float32, y: float32): ProbeInput {
	return { position: { x, y, z: 0.5, w: 1.0 } };
}

function switchFs(input: ProbeInput): float32 {
	const column = input.position.x as int32;
	let shade: float32 = 0.0;
	switch (column) {
		case 0:
			shade = 0.25;
			break;
		case 2:
			if (input.position.x > 2.5) {
				break;
			}
			shade = 0.5;
			break;
		case -1:
			return 2.0;
		default:
			shade = 1.0;
	}
	return shade;
}

function matchFs(input: ProbeInput): float32 {
	const column = input.position.x as int32;
	let shade: float32 = 0.0;
	for (let i = 0; i < 2; i++) {
		match (column + i) {
			0 => { shade += 0.25; },
			1 | 2 => {
				shade += 0.5;
				continue;
			},
			_ => { shade += 1.0; },
		}
		shade *= 2.0;
	}
	return shade;
}

struct Light {
	direction: Vec3f;
	intensity: float32;
}

struct Rig {
	key: Light;
	fill: Light;
	weights: float32[2];
}

struct Tap {
	sample: float32;
	offset: Vec2i;
}

function lit(light: Light, normal: Vec3f): float32 {
	return max(dot(light.direction, normal), 0.0) * light.intensity;
}

function keyLight(intensity: float32): Light {
	return { direction: vec3f(0.0, 0.0, 1.0), intensity };
}

function structFs(input: ProbeInput): float32 {
	let rig: Rig = {
		key: keyLight(input.position.x),
		fill: { direction: vec3f(0.0, 1.0, 0.0), intensity: 0.5 },
		weights: [1.0, 0.5],
	};
	rig.fill.intensity += 0.25;
	rig.weights[1] = 0.5 * rig.weights[1];
	let normal = vec3f(0.0, 0.0, 1.0);
	normal.y = 1.0;
	const pair: Light[2] = [rig.key, rig.fill];
	let tap: Tap = { sample: 1.0, offset: vec2i(0, 0) };
	tap.offset.x = 2;
	return lit(pair[0], normal) * rig.weights[0] + lit(pair[1], normal) * rig.weights[1] +
		tap.sample * (tap.offset.x as float32);
}

struct CellAttributes {
	position: Vec4f;
	id: uint32;
}

struct CellVaryings {
	@builtin(position) clip: Vec4f;
	cell: uint32;
	band: Vec2i;
	tint: Vec4f;
}

function cellVs(input: CellAttributes): CellVaryings {
	return { clip: input.position, cell: input.id, band: vec2i(1, 2), tint: vec4f(1.0) };
}

function cellFs(input: CellVaryings): float32 {
	let rest = input.cell % 4;
	rest %= 3;
	switch (rest) {
		case 0:
			return input.tint.x;
		case 2:
			return 2.0;
		default:
			return input.band.y as float32;
	}
}

function cellAt(cell: uint32): CellVaryings {
	return { clip: vec4f(0.0), cell, band: vec2i(1, 3), tint: vec4f(0.5) };
}

test "switch ends every case in a break, and a break inside a case leaves the switch" {
	assert glsl(switchFs) ==
		"layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    int column = int(gl_FragCoord.x);\n" +
		"    float shade = 0.0;\n" +
		"    switch (column) {\n" +
		"        case 0: {\n" +
		"            shade = 0.25;\n" +
		"            break;\n" +
		"        }\n" +
		"        case 2: {\n" +
		"            if (gl_FragCoord.x > 2.5) {\n" +
		"                break;\n" +
		"            }\n" +
		"            shade = 0.5;\n" +
		"            break;\n" +
		"        }\n" +
		"        case -1: {\n" +
		"            fragColor = 2.0;\n" +
		"            return;\n" +
		"        }\n" +
		"        default: {\n" +
		"            shade = 1.0;\n" +
		"            break;\n" +
		"        }\n" +
		"    }\n" +
		"    fragColor = shade;\n" +
		"    return;\n" +
		"}\n";
	assert switchFs(at(0.5, 0.0)) == 0.25 && switchFs(at(2.2, 0.0)) == 0.5;
	assert switchFs(at(2.7, 0.0)) == 0.0 && switchFs(at(-1.5, 0.0)) == 2.0;
	assert switchFs(at(5.5, 0.0)) == 1.0;
}

test "a statement match is a switch whose or-pattern shares one case, a continue passes through" {
	assert glsl(matchFs) ==
		"layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    int column = int(gl_FragCoord.x);\n" +
		"    float shade = 0.0;\n" +
		"    for (int i = 0; i < 2; i++) {\n" +
		"        switch (column + i) {\n" +
		"            case 0: {\n" +
		"                shade += 0.25;\n" +
		"                break;\n" +
		"            }\n" +
		"            case 1: case 2: {\n" +
		"                shade += 0.5;\n" +
		"                continue;\n" +
		"            }\n" +
		"            default: {\n" +
		"                shade += 1.0;\n" +
		"                break;\n" +
		"            }\n" +
		"        }\n" +
		"        shade *= 2.0;\n" +
		"    }\n" +
		"    fragColor = shade;\n" +
		"    return;\n" +
		"}\n";
	assert matchFs(at(0.5, 0.0)) == 1.0 && matchFs(at(1.5, 0.0)) == 1.0;
	assert matchFs(at(5.5, 0.0)) == 6.0;
}

test "an author struct is declared before its first reader and built in field order" {
	assert glsl(structFs) ==
		"struct Light {\n" +
		"    vec3 direction;\n" +
		"    float intensity;\n" +
		"};\n" +
		"struct Rig {\n" +
		"    Light key;\n" +
		"    Light fill;\n" +
		"    float[2] weights;\n" +
		"};\n" +
		"struct Tap {\n" +
		"    float sample_1;\n" +
		"    ivec2 offset;\n" +
		"};\n" +
		"layout(location=0) out float fragColor;\n" +
		"Light keyLight(float intensity) {\n" +
		"    return Light(vec3(0.0, 0.0, 1.0), intensity);\n" +
		"}\n" +
		"float lit(Light light, vec3 normal) {\n" +
		"    return max(dot(light.direction, normal), 0.0) * light.intensity;\n" +
		"}\n" +
		"void main() {\n" +
		"    Rig rig = Rig(keyLight(gl_FragCoord.x), Light(vec3(0.0, 1.0, 0.0), 0.5), float[2](1.0, 0.5));\n" +
		"    rig.fill.intensity += 0.25;\n" +
		"    rig.weights[1] = 0.5 * rig.weights[1];\n" +
		"    vec3 normal = vec3(0.0, 0.0, 1.0);\n" +
		"    normal.y = 1.0;\n" +
		"    Light[2] pair = Light[2](rig.key, rig.fill);\n" +
		"    Tap tap = Tap(1.0, ivec2(0, 0));\n" +
		"    tap.offset.x = 2;\n" +
		"    fragColor = ((lit(pair[0], normal) * rig.weights[0]) + (lit(pair[1], normal) * rig.weights[1])) + (tap.sample_1 * float(tap.offset.x));\n" +
		"    return;\n" +
		"}\n";
	assert structFs(at(2.0, 0.0)) == 4.1875;
}

struct Vec2f {
	x: float32;
	y: float32;
}

function twinFs(input: ProbeInput): float32 {
	const t: Vec2f = { x: input.position.x, y: 2.0 };
	return t.x * t.y;
}

test "a struct named like a ./std type is the author's, told apart by its module" {
	assert glsl(twinFs) ==
		"struct Vec2f {\n" +
		"    float x;\n" +
		"    float y;\n" +
		"};\n" +
		"layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    Vec2f t = Vec2f(gl_FragCoord.x, 2.0);\n" +
		"    fragColor = t.x * t.y;\n" +
		"    return;\n" +
		"}\n";
	assert twinFs(at(3.0, 0.0)) == 6.0;
}

test "integer varyings are flat on both sides, and uint32 takes '%' and '%='" {
	assert glsl(cellVs) ==
		"in vec4 position;\n" +
		"in uint id;\n" +
		"flat out uint cell;\n" +
		"flat out ivec2 band;\n" +
		"out vec4 tint;\n" +
		"void main() {\n" +
		"    gl_Position = position;\n" +
		"    cell = id;\n" +
		"    band = ivec2(1, 2);\n" +
		"    tint = vec4(1.0);\n" +
		"    return;\n" +
		"}\n";
	assert glslLinked(cellFs, cellVs) ==
		"flat in uint cell;\n" +
		"flat in ivec2 band;\n" +
		"in vec4 tint;\n" +
		"layout(location=0) out float fragColor;\n" +
		"void main() {\n" +
		"    uint rest = cell % 4;\n" +
		"    rest %= 3;\n" +
		"    switch (rest) {\n" +
		"        case 0: {\n" +
		"            fragColor = tint.x;\n" +
		"            return;\n" +
		"        }\n" +
		"        case 2: {\n" +
		"            fragColor = 2.0;\n" +
		"            return;\n" +
		"        }\n" +
		"        default: {\n" +
		"            fragColor = float(band.y);\n" +
		"            return;\n" +
		"        }\n" +
		"    }\n" +
		"}\n";
	assert cellFs(cellAt(7)) == 0.5 && cellFs(cellAt(6)) == 2.0 && cellFs(cellAt(5)) == 3.0;
	assert cellFs(cellAt(4294967295)) == 0.5;
}
