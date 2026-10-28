// @interpolate(kind[, sampling]) on stage io, as WGSL's: printed in every target's spelling, and
// the
// IR refuses a vertex output and a fragment input that disagree.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glslIr, glslLinked, glslLinkedIr } from "../shader/emit";
import { Interpolation, Sampling, ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { Vec2f, Vec4f, builtin, interpolate, vec2f, vec4f } from "../shader/std";

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
	@interpolate(linear) screen: Vec2f;
	@interpolate(perspective, centroid) tint: Vec4f;
	@interpolate(linear, sample) detail: Vec2f;
	@interpolate(flat) id: uint32;
	@interpolate(perspective, center) plain: float32;
}

export struct Lanes {
	@builtin(position) position: Vec4f;
	@interpolate(linear) screen: Vec2f;
	@interpolate(perspective, centroid) tint: Vec4f;
	@interpolate(linear, sample) detail: Vec2f;
	@interpolate(flat) id: uint32;
	@interpolate(perspective, center) plain: float32;
}

export struct Skewed {
	@builtin(position) position: Vec4f;
	screen: Vec2f;
	@interpolate(perspective, centroid) tint: Vec4f;
	@interpolate(linear, sample) detail: Vec2f;
	@interpolate(flat) id: uint32;
	@interpolate(perspective, center) plain: float32;
}

export function interpolateVs(input: Corner): Placed {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		screen: input.position,
		tint: vec4f(1.0, 0.5, 0.25, 1.0),
		detail: vec2f(0.5, 0.5),
		id: 7,
		plain: 1.0,
	};
}

export function interpolateFs(input: Lanes): Vec4f {
	return vec4f(input.screen.x + input.detail.x + input.plain, input.tint.y, input.tint.z,
		(input.id as float32));
}

export function skewedFs(input: Skewed): Vec4f {
	return vec4f(input.screen.x, input.tint.y, input.detail.x, (input.id as float32) + input.plain);
}

function programOf(): ShaderModule {
	const m = programModule(glslIr(interpolateVs), glslLinkedIr(interpolateFs, interpolateVs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

function printedFor(m: ShaderModule, entry: int32, target: ShaderTarget, name: string,
	path: string): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { return text.error; }
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

test "the decorator sets the IR's interpolation and sampling on both sides" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const ios = m.ios.filter((io) => io.name == "screen" || io.name == "tint" ||
		io.name == "detail" || io.name == "id" || io.name == "plain");
	assert ios.length == 10;
	for (const io of ios) {
		if (io.name == "screen") {
			assert io.interpolation == Interpolation.Linear && io.sampling == Sampling.Center;
		}
		if (io.name == "tint") {
			assert io.interpolation == Interpolation.Perspective &&
				io.sampling == Sampling.Centroid;
		}
		if (io.name == "detail") {
			assert io.interpolation == Interpolation.Linear && io.sampling == Sampling.Sample;
		}
		if (io.name == "id") {
			assert io.interpolation == Interpolation.Flat && io.sampling == Sampling.Center;
		}
		if (io.name == "plain") {
			assert io.interpolation == Interpolation.Perspective && io.sampling == Sampling.Center;
		}
	}
}

test "GLSL 450 writes noperspective, centroid and sample before in and out" {
	assert glslLinked(interpolateFs, interpolateVs).startsWith(
		"noperspective in vec2 screen;\n" +
		"centroid in vec4 tint;\n" +
		"noperspective sample in vec2 detail;\n" +
		"flat in uint id;\n" +
		"in float plain;\n");
}

test "WGSL spells @interpolate on the vertex output and the fragment input" {
	const m = programOf();
	const vs = printedFor(m, 0, ShaderTarget.Wgsl, "interpolate",
		"out/wgslProbe/interpolateVs.wgsl");
	const fs = printedFor(m, 1, ShaderTarget.Wgsl, "interpolate",
		"out/wgslProbe/interpolateFs.wgsl");
	for (const text of [vs, fs]) {
		assert text.includes("@interpolate(linear) screen") &&
			text.includes("@interpolate(perspective, centroid) tint");
		assert text.includes("@interpolate(linear, sample) detail") &&
			text.includes("@interpolate(flat) id");
	}
	assert !fs.includes("@interpolate(perspective, center)");
}

test "GLSL 430 and HLSL spell it, MSL as attributes" {
	const m = programOf();
	const glsl = printedFor(m, 1, ShaderTarget.Glsl430, "interpolate",
		"out/glslProbe/interpolate.430.frag");
	assert glsl.includes("noperspective in vec2 screen;") &&
		glsl.includes("centroid in vec4 tint;");
	assert glsl.includes("noperspective sample in vec2 detail;") &&
		glsl.includes("flat in uint id;");
	const vs = printedFor(m, 0, ShaderTarget.Hlsl5, "interpolate",
		"out/hlslProbe/interpolate.vs.hlsl");
	const fs = printedFor(m, 1, ShaderTarget.Hlsl5, "interpolate",
		"out/hlslProbe/interpolate.ps.hlsl");
	for (const text of [vs, fs]) {
		assert text.includes("noperspective float2 screen") &&
			text.includes("centroid float4 tint");
		assert text.includes("noperspective sample float2 detail") &&
			text.includes("nointerpolation uint id");
	}
	const msl = printedFor(m, 1, ShaderTarget.Msl, "interpolate",
		"out/mslProbe/interpolateFs.metal");
	assert msl.includes("[[user(locn0), center_no_perspective]]") &&
		msl.includes("[[user(locn1), centroid_perspective]]");
	assert msl.includes("[[user(locn2), sample_no_perspective]]") &&
		msl.includes("[[user(locn3), flat]]");
}

test "GLSL ES 3.00 refuses linear and per-sample, naming the varying" {
	const es = printedFor(programOf(), 1, ShaderTarget.Glsl300es, "interpolate",
		"out/glslProbe/interpolate.es.frag");
	assert es.includes("io 'screen' is linear, which GLSL ES 3.00 has not");
}

test "a fragment input that interpolates otherwise than the vertex output is refused" {
	const skewed = programModule(glslIr(interpolateVs), glslLinkedIr(skewedFs, interpolateVs), []);
	assert !skewed.ok && skewed.error.includes(
		"varying 0 is interpolated differently by the vertex output and the fragment input");
	let m = programOf();
	for (const io of m.ios) {
		if (io.name == "id" && io.stage == m.entries[1].stage) { io.sampling = Sampling.Sample; }
	}
	assert irErrors(m).includes("io 'id': a flat varying takes no sampling, as WGSL's");
}
