// The integer and compute vocabulary past the basic forms, authored in MetaScript: each entry runs
// on the CPU, is pinned as GLSL, and is printed for every target into out/<target>Probe/ for
// scripts/validateWgsl.sh, scripts/validateHlsl.sh and naga's GLSL front end.

import { mkdir, writeFile } from "std/fs";
import { computeModule, stageSource } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import {
	ExprKind,
	Intrinsic,
	ScalarKind,
	ShaderModule,
	ShaderStage,
	ShaderType,
	StmtKind,
	exprOf,
	intrinsicOf,
	literal,
	scalarType,
	stmtOf,
	vectorType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import {
	StorageTexture2d,
	Vec3u,
	access,
	binding,
	builtin,
	format,
	storageBarrier,
	textureStore,
	vec2i,
	vec2u,
	vec4f,
	workgroupBarrier,
} from "../shader/std";
import { prepend, tiny } from "./shaderProbeModules";

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

export function barrierCs(input: OpsInput, b: OpsBindings): void {
	const at = vec2i(input.id.xy);
	workgroupBarrier();
	storageBarrier();
	textureStore(b.image, at, vec4f(1.0));
}

test "a barrier waits for no one on the CPU, and GLSL 450 spells a workgroup one barrier()" {
	const b: OpsBindings = { image: blankImage() };
	barrierCs({ id: { x: 2, y: 0, z: 0 } }, b);
	assert b.image.texels[2 * 4] == 1.0;
	assert glslCompute(barrierCs, [32, 1, 1]) ==
		"layout(local_size_x=32, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32f) uniform writeonly image2D image;\n" +
		"void main() {\n" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);\n" +
		"    barrier();\n" +
		"    memoryBarrierBuffer(); barrier();\n" +
		"    imageStore(image, at, vec4(1.0));\n" +
		"}\n";
}

test "every target spells both barriers, and refuses one outside a compute entry" {
	const m = computeOf(glslComputeIr(barrierCs, [32, 1, 1]));
	assert printedFor(m, ShaderTarget.Wgsl, "barriers").includes(
		"  workgroupBarrier();\n  storageBarrier();\n");
	assert printedFor(m, ShaderTarget.Hlsl5, "barriers").includes(
		"    GroupMemoryBarrierWithGroupSync();\n    DeviceMemoryBarrierWithGroupSync();\n");
	assert printedFor(m, ShaderTarget.Glsl430, "barriers").includes(
		"    memoryBarrierShared(); barrier();\n    memoryBarrierBuffer(); barrier();\n");
	assert printedFor(m, ShaderTarget.Msl, "barriers").includes(
		"  threadgroup_barrier(mem_flags::mem_threadgroup);\n" +
		"  threadgroup_barrier(mem_flags::mem_device);\n");
	let fragment = tiny(ShaderStage.Fragment, exprOf(ExprKind.Construct,
		vectorType(ScalarKind.F32, 4), -1, [literal(scalarType(ScalarKind.F32), 1.0)]));
	prepend(fragment.functions[0], stmtOf(StmtKind.Call,
		intrinsicOf(Intrinsic.WorkgroupBarrier, new ShaderType(), []), []));
	for (const target of TARGETS) {
		const refused = stageSource(fragment, 0, target);
		assert !refused.ok && refused.error.endsWith(": WorkgroupBarrier outside a compute entry");
	}
}

export struct TileInput {
	@builtin(globalInvocationId) id: Vec3u;
	@builtin(localInvocationIndex) local: uint32;
}

let tile: float32[64];
let scale: float32;

function mirrored(i: uint32): float32 {
	return tile[63 - i] * scale;
}

export function tileCs(input: TileInput, b: OpsBindings): void {
	const i = input.local;
	tile[i] = i as float32;
	if (i == 0) {
		scale = 2.0;
	}
	workgroupBarrier();
	textureStore(b.image, vec2i(input.id.xy), vec4f(mirrored(i)));
}

test "a module let a compute entry reads is workgroup memory that starts at zero" {
	const b: OpsBindings = { image: blankImage() };
	tileCs({ id: { x: 1, y: 0, z: 0 }, local: 63 }, b);
	assert b.image.texels[4] == 0.0;
	tileCs({ id: { x: 0, y: 0, z: 0 }, local: 0 }, b);
	assert b.image.texels[0] == 126.0;
	assert glslCompute(tileCs, [64, 1, 1]) ==
		"layout(local_size_x=64, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32f) uniform writeonly image2D image;\n" +
		"shared float[64] tile;\n" +
		"shared float scale;\n" +
		"float mirrored(uint i) {\n" +
		"    return tile[63 - i] * scale;\n" +
		"}\n" +
		"void main() {\n" +
		"    if (gl_LocalInvocationIndex == 0) {\n" +
		"        for (uint zeroAt = 0; zeroAt < 64; zeroAt++) {\n" +
		"            tile[zeroAt] = 0.0;\n" +
		"        }\n" +
		"        scale = 0.0;\n" +
		"    }\n" +
		"    barrier();\n" +
		"    uint i = gl_LocalInvocationIndex;\n" +
		"    tile[i] = float(i);\n" +
		"    if (i == 0) {\n" +
		"        scale = 2.0;\n" +
		"    }\n" +
		"    barrier();\n" +
		"    imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(mirrored(i)));\n" +
		"}\n";
}

test "every target declares workgroup memory, zeroed by one invocation behind a barrier" {
	const m = computeOf(glslComputeIr(tileCs, [64, 1, 1]));
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "tile");
	assert wgsl.includes("var<workgroup> tile : array<f32, 64>;\n");
	assert wgsl.includes("var<workgroup> scale : f32;\n");
	assert wgsl.includes("  if ((local == 0u)) {\n" +
		"    for (var zeroAt : u32 = 0u; (zeroAt < 64u); zeroAt++) {\n" +
		"      tile[zeroAt] = 0f;\n    }\n    scale = 0f;\n  }\n  workgroupBarrier();\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "tile");
	assert hlsl.includes("groupshared float tile[64];\ngroupshared float scale;\n");
	assert hlsl.includes("    uint local : SV_GroupIndex;\n");
	const gl = printedFor(m, ShaderTarget.Glsl430, "tile");
	assert gl.includes("shared float tile[64];\nshared float scale;\n");
	assert gl.includes("    if (gl_LocalInvocationIndex == 0u)\n");
	const msl = printedFor(m, ShaderTarget.Msl, "tile");
	assert msl.includes("static inline float mirrored(uint i, threadgroup float (&tile)[64], " +
		"threadgroup float& scale) {\n");
	assert msl.includes("  threadgroup float tile[64];\n  threadgroup float scale;\n" +
		"  tileCs(id, local, image, tile, scale);\n");
	let fragment = tiny(ShaderStage.Fragment, exprOf(ExprKind.Construct,
		vectorType(ScalarKind.F32, 4), -1, [exprOf(ExprKind.Workgroup, m.workgroups[1].type, 0, [])]));
	fragment.workgroups = [m.workgroups[1]];
	for (const target of TARGETS) {
		const refused = stageSource(fragment, 0, target);
		assert !refused.ok &&
			refused.error.endsWith(": workgroup variable 'scale' is read outside a compute entry");
	}
}
