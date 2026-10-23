// The integer and compute vocabulary past the basic forms, authored in MetaScript: each entry runs
// on the CPU, is pinned as GLSL, and is printed for every target into out/<target>Probe/ for
// scripts/validateWgsl.sh, scripts/validateHlsl.sh and naga's GLSL front end.

import { mkdir, writeFile } from "std/fs";
import { computeModule, stageSource } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import { ShaderModule } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import {
	StorageTexture2d,
	Vec3u,
	access,
	binding,
	builtin,
	format,
	textureStore,
	vec2i,
	vec2u,
	vec4f,
} from "../shader/std";

const TARGETS = [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430, ShaderTarget.Msl];

function computeOf(text: string): ShaderModule {
	const m = computeModule(text, []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

function probePath(target: ShaderTarget, name: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + ".cs.hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430.comp",
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es.comp",
		ShaderTarget.Msl => "out/mslProbe/" + name + ".metal",
	};
}

// The compute entry of a lowered module as a target prints it, written where its validator reads,
// or the printer's refusal.
function printedFor(m: ShaderModule, target: ShaderTarget, name: string): string {
	const text = stageSource(m, 0, target);
	if (!text.ok) { return text.error; }
	const path = probePath(target, name);
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

export struct OpsInput {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct OpsBindings {
	@binding(0) @format(r32float) @access(write) image: StorageTexture2d;
}

function blankImage(): StorageTexture2d {
	let texels: float32[] = [];
	for (let i = 0; i < 4 * 8; i++) { texels.push(0.0); }
	return { width: 8, height: 1, texels };
}

export function bitsCs(input: OpsInput, b: OpsBindings): void {
	const at = vec2i(input.id.xy);
	const x = at.x;
	const mixed = (x | 4) ^ (x << 2) ^ (~x >> 1) ^ (x >> (x & 7));
	const u = vec2u(vec2i(x, 3));
	const v = (u << vec2u(1, 3)) | (u >> u) ^ (u & vec2u(6, 6));
	const w: uint32 = v.x ^ v.y;
	textureStore(b.image, at, vec4f((mixed as float32) * 2.0 + (w as float32)));
}

test "integer '|', '^', '<<', '>>' and '~' keep their bits, scalar and per component" {
	const b: OpsBindings = { image: blankImage() };
	bitsCs({ id: { x: 5, y: 0, z: 0 } }, b);
	assert b.image.texels[5 * 4] == -20.0;
	assert glslCompute(bitsCs, [32, 1, 1]) ==
		"layout(local_size_x=32, local_size_y=1, local_size_z=1) in;
" +
		"layout(binding=0, r32f) uniform writeonly image2D image;
" +
		"void main() {
" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);
" +
		"    int x = at.x;
" +
		"    int mixed = (((x | 4) ^ (x << 2)) ^ ((~x) >> 1)) ^ (x >> (uint(x & 7) & 31u));
" +
		"    uvec2 u = uvec2(ivec2(x, 3));
" +
		"    uvec2 v = (u << (uvec2(1, 3) & 31u)) | ((u >> (u & 31u)) ^ (u & uvec2(6, 6)));
" +
		"    uint w = v.x ^ v.y;
" +
		"    imageStore(image, at, vec4(((float(mixed) * 2.0) + float(w))));
" +
		"}
";
}

test "every target spells the bit operators, a shift amount as a masked uint" {
	const m = computeOf(glslComputeIr(bitsCs, [32, 1, 1]));
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "bits");
	assert wgsl.includes("((((x | 4i) ^ (x << 2u)) ^ ((~x) >> 1u)) ^ (x >> u32((x & 7i))))");
	assert wgsl.includes("((u << vec2u(1u, 3u)) | ((u >> u) ^ (u & vec2u(6u, 6u))))");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "bits");
	assert hlsl.includes("(((x | 4) ^ (x << 2u)) ^ ((~x) >> 1u)) ^ (x >> uint(x & 7))");
	assert hlsl.includes("(u << uint2(1u, 3u)) | ((u >> u) ^ (u & uint2(6u, 6u)))");
	const gl = printedFor(m, ShaderTarget.Glsl430, "bits");
	assert gl.includes("(((x | 4) ^ (x << 2u)) ^ ((~x) >> 1u)) ^ (x >> (uint(x & 7) & 31u))");
	assert gl.includes("(u << (uvec2(1u, 3u) & 31u)) | ((u >> (u & 31u)) ^ (u & uvec2(6u, 6u)))");
	const msl = printedFor(m, ShaderTarget.Msl, "bits");
	assert msl.includes("((((x | 4) ^ (x << 2u)) ^ ((~x) >> 1u)) ^ (x >> (uint((x & 7)) & 31u)))");
	assert msl.includes("((u << (uint2(1u, 3u) & 31u)) | ((u >> (u & 31u)) ^ (u & uint2(6u, 6u))))");
}
