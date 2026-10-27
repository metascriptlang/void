// The integer and compute vocabulary past the basic forms, authored in MetaScript: each entry runs
// on the CPU, is pinned as GLSL, and is printed for every target into out/<target>Probe/ for
// scripts/validateWgsl.sh, scripts/validateHlsl.sh and naga's GLSL front end.

import { mkdir, writeFile } from "std/fs";
import { computeModule, stageSource } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import {
	Access,
	ExprKind,
	Intrinsic,
	ScalarKind,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	ShaderType,
	ShaderField,
	StmtKind,
	TextureShape,
	atomicType,
	exprOf,
	intrinsicOf,
	irErrors,
	literal,
	scalarType,
	stmtOf,
	vectorType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import {
	AtomicI32,
	AtomicU32,
	StorageTexture2d,
	StorageTexture2dArray,
	StorageTexture3d,
	Vec3u,
	access,
	atomicAdd,
	atomicAnd,
	atomicCompareExchangeWeak,
	atomicExchange,
	atomicLoad,
	atomicMax,
	atomicMin,
	atomicOr,
	atomicStore,
	atomicSub,
	atomicXor,
	binding,
	builtin,
	format,
	storageBarrier,
	textureDimensions,
	textureLoad,
	textureStore,
	vec2i,
	vec2u,
	vec3i,
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
		ShaderTarget.Spirv => "out/spirvProbe/" + name + ".spv",
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
		"layout(local_size_x=32, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32f) uniform writeonly image2D image;\n" +
		"void main() {\n" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);\n" +
		"    int x = at.x;\n" +
		"    int mixed = (((x | 4) ^ (x << 2)) ^ ((~x) >> 1)) ^ (x >> (uint(x & 7) & 31u));\n" +
		"    uvec2 u = uvec2(ivec2(x, 3));\n" +
		"    uvec2 v = (u << (uvec2(1, 3) & 31u)) | ((u >> (u & 31u)) ^ (u & uvec2(6, 6)));\n" +
		"    uint w = v.x ^ v.y;\n" +
		"    imageStore(image, at, vec4(((float(mixed) * 2.0) + float(w))));\n" +
		"}\n";
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

export struct Cell {
	hits: AtomicU32;
	low: AtomicI32;
}

export struct CountBindings {
	@binding(0) @access(read_write) cells: Cell[];
}

export function countCs(input: OpsInput, b: CountBindings): void {
	const i = input.id.x;
	const seen = atomicAdd(b.cells[i].hits, 2);
	atomicSub(b.cells[i].hits, 1);
	atomicMax(b.cells[i].low, -4);
	atomicMin(b.cells[i].low, 7);
	atomicAnd(b.cells[i].hits, 255);
	atomicOr(b.cells[i].hits, 256);
	atomicXor(b.cells[i].hits, 1);
	const swapped = atomicExchange(b.cells[i].low, 3);
	atomicStore(b.cells[i].low, swapped + 1);
	const exchange = atomicCompareExchangeWeak(b.cells[i].hits, seen, 9);
	if (!exchange.exchanged) {
		atomicStore(b.cells[i].hits, exchange.oldValue + 1);
	}
	const now = atomicLoad(b.cells[i].hits);
	atomicMax(b.cells[i].hits, now * 2);
}

test "an atomic is a read-modify-write that returns the old value on the CPU" {
	let b: CountBindings = { cells: [{ hits: { value: 0 }, low: { value: 0 } },
		{ hits: { value: 5 }, low: { value: 0 } }] };
	countCs({ id: { x: 1, y: 0, z: 0 } }, b);
	assert b.cells[1].hits.value == 528;
	assert b.cells[1].low.value == 1;
	assert b.cells[0].hits.value == 0;
}

test "every target spells each atomic on a storage buffer" {
	const m = computeOf(glslComputeIr(countCs, [64, 1, 1]));
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "atomics");
	assert wgsl.includes("struct Cell {\n  hits : atomic<u32>,\n  low : atomic<i32>,\n}\n");
	assert wgsl.includes("  var seen : u32 = atomicAdd(&cells[i].hits, 2u);\n" +
		"  _ = atomicSub(&cells[i].hits, 1u);\n");
	assert wgsl.includes("  var exchange = atomicCompareExchangeWeak(&cells[i].hits, seen, 9u);\n" +
		"  if ((!exchange.exchanged)) {\n" +
		"    atomicStore(&cells[i].hits, (exchange.old_value + 1u));\n  }\n" +
		"  var now : u32 = atomicLoad(&cells[i].hits);\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "atomics");
	assert hlsl.includes("struct Cell\n{\n    uint hits;\n    int low;\n};\n");
	assert hlsl.includes("    uint seen;\n    InterlockedAdd(cells[i].hits, 2u, seen);\n" +
		"    InterlockedAdd(cells[i].hits, -1u);\n");
	assert hlsl.includes("    int exchanged;\n" +
		"    InterlockedExchange(cells[i].low, swapped + 1, exchanged);\n" +
		"    uint compare = seen;\n    AtomicExchangeU32 exchange;\n" +
		"    InterlockedCompareExchange(cells[i].hits, compare, 9u, exchange.old_value);\n" +
		"    exchange.exchanged = exchange.old_value == compare;\n");
	assert hlsl.includes("    uint now;\n    InterlockedAdd(cells[i].hits, 0, now);\n");
	const gl = printedFor(m, ShaderTarget.Glsl430, "atomics");
	assert gl.includes("    atomicAdd(cells.data[i].hits, -1u);\n");
	assert gl.includes("    atomicExchange(cells.data[i].low, swapped + 1);\n" +
		"    uint compare = seen;\n    AtomicExchangeU32 exchange;\n" +
		"    exchange.old_value = atomicCompSwap(cells.data[i].hits, compare, 9u);\n" +
		"    exchange.exchanged = exchange.old_value == compare;\n");
	assert gl.includes("    uint now = atomicAdd(cells.data[i].hits, 0u);\n");
	const msl = printedFor(m, ShaderTarget.Msl, "atomics");
	assert msl.includes("struct Cell {\n  atomic_uint hits;\n  atomic_int low;\n};\n");
	assert msl.includes("  uint seen = atomic_fetch_add_explicit(&cells[i].hits, 2u, " +
		"memory_order_relaxed);\n");
	assert msl.includes("  AtomicExchangeU32 exchange = atomicCompareExchangeWeakU32(" +
		"&cells[i].hits, seen, 9u);\n");
	assert msl.includes("  bool exchanged = atomic_compare_exchange_weak_explicit(place, " +
		"&compare, value, memory_order_relaxed, memory_order_relaxed);\n");
	assert glslCompute(countCs, [64, 1, 1]) ==
		"layout(local_size_x=64, local_size_y=1, local_size_z=1) in;\n" +
		"struct Cell {\n" +
		"    uint hits;\n" +
		"    int low;\n" +
		"};\n" +
		"struct AtomicExchangeU32 {\n" +
		"    uint old_value;\n" +
		"    bool exchanged;\n" +
		"};\n" +
		"AtomicExchangeU32 atomicExchangeResultU32(uint compare, uint old) {\n" +
		"    return AtomicExchangeU32(old, old == compare);\n" +
		"}\n" +
		"layout(binding=0) buffer cellsBuffer {\n" +
		"    Cell cells[];\n" +
		"};\n" +
		"void main() {\n" +
		"    uint i = gl_GlobalInvocationID.x;\n" +
		"    uint seen = atomicAdd(cells[i].hits, 2);\n" +
		"    atomicAdd(cells[i].hits, -(1));\n" +
		"    atomicMax(cells[i].low, -4);\n" +
		"    atomicMin(cells[i].low, 7);\n" +
		"    atomicAnd(cells[i].hits, 255);\n" +
		"    atomicOr(cells[i].hits, 256);\n" +
		"    atomicXor(cells[i].hits, 1);\n" +
		"    int swapped = atomicExchange(cells[i].low, 3);\n" +
		"    atomicExchange(cells[i].low, (swapped + 1));\n" +
		"    AtomicExchangeU32 exchange = AtomicExchangeU32(seen, false);\n" +
		"    exchange = atomicExchangeResultU32(exchange.old_value, atomicCompSwap(cells[i].hits, exchange.old_value, 9));\n" +
		"    if (!exchange.exchanged) {\n" +
		"        atomicExchange(cells[i].hits, (exchange.old_value + 1));\n" +
		"    }\n" +
		"    uint now = atomicAdd(cells[i].hits, 0u);\n" +
		"    atomicMax(cells[i].hits, (now * 2));\n" +
		"}\n";
}

function atomicPlace(m: ShaderModule): ShaderExpr {
	const body = m.functions[m.entries[0].functionIndex].body;
	return body.filter((s) => s.kind == StmtKind.Let && s.expr.kind == ExprKind.Intrinsic)[0]
		.expr.operands[0];
}

test "workgroup atomics print on every target" {
	let m = computeOf(glslComputeIr(countCs, [64, 1, 1]));
	let total = new ShaderField();
	total.name = "total";
	total.type = atomicType(ScalarKind.U32);
	m.workgroups.push(total);
	const at = exprOf(ExprKind.Workgroup, total.type, m.workgroups.length - 1, []);
	prepend(m.functions[m.entries[0].functionIndex], stmtOf(StmtKind.Call,
		intrinsicOf(Intrinsic.AtomicAdd, scalarType(ScalarKind.U32),
			[at, literal(scalarType(ScalarKind.U32), 1.0)]), []));
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "workgroupAtomics");
	assert wgsl.includes("var<workgroup> total : atomic<u32>;\n");
	assert wgsl.includes("  _ = atomicAdd(&total, 1u);\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "workgroupAtomics");
	assert hlsl.includes("groupshared uint total;\n");
	assert hlsl.includes("    InterlockedAdd(total, 1u);\n");
	const gl = printedFor(m, ShaderTarget.Glsl430, "workgroupAtomics");
	assert gl.includes("shared uint total;\n");
	assert gl.includes("    atomicAdd(total, 1u);\n");
	const msl = printedFor(m, ShaderTarget.Msl, "workgroupAtomics");
	assert msl.includes("  threadgroup atomic_uint total;\n");
	assert msl.includes("  (void)atomic_fetch_add_explicit(&total, 1u, memory_order_relaxed);\n");
}

test "an atomic stays in a read_write buffer, and HLSL refuses one nested in an expression" {
	let readOnly = computeOf(glslComputeIr(countCs, [64, 1, 1]));
	readOnly.resources[0].access = Access.Read;
	assert irErrors(readOnly).includes(
		"resource 'cells': it holds atomics, so its access is read_write, as WGSL's");
	let nested = computeOf(glslComputeIr(countCs, [64, 1, 1]));
	const place = atomicPlace(nested);
	const u32 = scalarType(ScalarKind.U32);
	prepend(nested.functions[nested.entries[0].functionIndex], stmtOf(StmtKind.Call,
		intrinsicOf(Intrinsic.AtomicStore, new ShaderType(), [place, intrinsicOf(Intrinsic.AtomicAdd,
			u32, [place, literal(u32, 1.0)])]), []));
	assert irErrors(nested).length == 0;
	const refused = stageSource(nested, 0, ShaderTarget.Hlsl5);
	assert !refused.ok && refused.error.endsWith(": AtomicAdd inside an expression or a for " +
		"header: Interlocked* hands its result back through an out parameter, so an atomic is a " +
		"statement or a local's initializer");
}

export struct VolumeBindings {
	@binding(0) @format(r32float) @access(read_write) layers: StorageTexture2dArray;
	@binding(1) @format(r32float) @access(read_write) volume: StorageTexture3d;
	@binding(2) @format(r32float) @access(read) plane: StorageTexture2d;
}

export function volumeCs(input: OpsInput, b: VolumeBindings): void {
	const at = vec2i(input.id.xy);
	const size = textureDimensions(b.layers);
	const deep = textureDimensions(b.volume);
	const below = textureLoad(b.layers, at, 0);
	textureStore(b.layers, at, 1, vec4f(below.x + (size.x as float32)));
	const far = textureLoad(b.volume, vec3i(at.x, at.y, deep.z - 1));
	textureStore(b.volume, vec3i(at.x, at.y, 0), vec4f(far.x * 2.0));
	textureStore(b.layers, at, 0, textureLoad(b.plane, at));
}

function texelsOf(count: int32, start: float32): float32[] {
	let texels: float32[] = [];
	for (let i = 0; i < count * 4; i++) { texels.push(start + ((i / 4) as float32)); }
	return texels;
}

test "a storage texture is 2d, 2d array or 3d, a layer an operand of its own" {
	let b: VolumeBindings = {
		layers: { width: 2, height: 1, layers: 2, texels: texelsOf(4, 10.0) },
		volume: { width: 2, height: 1, depth: 3, texels: texelsOf(6, 20.0) },
		plane: { width: 2, height: 1, texels: texelsOf(2, 30.0) },
	};
	volumeCs({ id: { x: 1, y: 0, z: 0 } }, b);
	assert b.layers.texels[3 * 4] == 13.0;
	assert b.volume.texels[1 * 4] == 50.0;
	assert b.layers.texels[1 * 4] == 31.0;
}

test "every target spells a storage texture of each shape" {
	const m = computeOf(glslComputeIr(volumeCs, [32, 1, 1]));
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "volume");
	assert wgsl.includes("var layers : texture_storage_2d_array<r32float, read_write>;\n");
	assert wgsl.includes("var volume : texture_storage_3d<r32float, read_write>;\n");
	assert wgsl.includes("  var below : vec4f = textureLoad(layers, at, 0i);\n" +
		"  textureStore(layers, at, 1i, vec4f((below.x + f32(size.x))));\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "volume");
	assert hlsl.includes("RWTexture2DArray<float> layers : register(u0);\n" +
		"RWTexture3D<float> volume : register(u1);\n");
	assert hlsl.includes("    image.GetDimensions(width, height, depth);\n" +
		"    return uint3(width, height, depth);\n");
	assert hlsl.includes("    float4 below = float4(layers[uint3(at, 0)], 0.0, 0.0, 1.0);\n" +
		"    layers[uint3(at, 1)] = ((float4)(below.x + float(size.x))).x;\n");
	assert hlsl.includes("    volume[uint3(int3(at.x, at.y, 0))] = ((float4)(far.x * 2.0)).x;\n");
	const gl = printedFor(m, ShaderTarget.Glsl430, "volume");
	assert gl.includes("layout(binding = 0, r32f) uniform image2DArray layers;\n" +
		"layout(binding = 1, r32f) uniform image3D volume;\n");
	assert gl.includes("    ivec2 size = imageSize(layers).xy;\n    ivec3 deep = imageSize(volume);\n" +
		"    vec4 below = imageLoad(layers, ivec3(at, 0));\n" +
		"    imageStore(layers, ivec3(at, 1), vec4(below.x + float(size.x)));\n");
	const msl = printedFor(m, ShaderTarget.Msl, "volume");
	assert msl.includes("texture2d_array<float, access::read_write> layers, " +
		"texture3d<float, access::read_write> volume, texture2d<float, access::read> plane");
	assert msl.includes("  int3 deep = int3(volume.get_width(), volume.get_height(), " +
		"volume.get_depth());\n  float4 below = layers.read(uint2(at), uint(0));\n" +
		"  layers.write(float4((below.x + float(size.x))), uint2(at), uint(1));\n");
	let cube = computeOf(glslComputeIr(volumeCs, [32, 1, 1]));
	cube.resources[1].type.shape = TextureShape.Cube;
	assert irErrors(cube).includes("resource 'volume': a storage texture of shape Cube, where " +
		"WGSL's is 1d, 2d, 2d array or 3d");
	assert glslCompute(volumeCs, [32, 1, 1]) ==
		"layout(local_size_x=32, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32f) uniform image2DArray layers;\n" +
		"layout(binding=1, r32f) uniform image3D volume;\n" +
		"layout(binding=2, r32f) uniform readonly image2D plane;\n" +
		"void main() {\n" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);\n" +
		"    ivec2 size = imageSize(layers).xy;\n" +
		"    ivec3 deep = imageSize(volume);\n" +
		"    vec4 below = imageLoad(layers, ivec3(at, 0));\n" +
		"    imageStore(layers, ivec3(at, 1), vec4((below.x + float(size.x))));\n" +
		"    vec4 far = imageLoad(volume, ivec3(at.x, at.y, (deep.z - 1)));\n" +
		"    imageStore(volume, ivec3(at.x, at.y, 0), vec4((far.x * 2.0)));\n" +
		"    imageStore(layers, ivec3(at, 0), imageLoad(plane, at));\n" +
		"}\n";
}
