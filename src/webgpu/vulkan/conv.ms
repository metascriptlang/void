import {
	GPUBlendFactor,
	GPUBlendOperation,
	GPUBufferUsage,
	GPUCompareFunction,
	GPUCullMode,
	GPUFrontFace,
	GPUIndexFormat,
	GPULoadOp,
	GPUPrimitiveTopology,
	GPUShaderStage,
	GPUStencilOperation,
	GPUStoreOp,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUVertexFormat,
	GPUVertexStepMode,
} from "../types.ms";
import { MemoryKind } from "./memory";
import { ACCESS_TRANSFER_READ, BufferRest, STAGE_TRANSFER, TextureRest } from "./tracker";

export const STAGE_DRAW_INDIRECT: uint32 = 0x2;
export const STAGE_VERTEX_INPUT: uint32 = 0x4;
export const STAGE_VERTEX_SHADER: uint32 = 0x8;
export const STAGE_FRAGMENT_SHADER: uint32 = 0x80;
export const STAGE_EARLY_FRAGMENT_TESTS: uint32 = 0x100;
export const STAGE_LATE_FRAGMENT_TESTS: uint32 = 0x200;
export const STAGE_COLOR_ATTACHMENT_OUTPUT: uint32 = 0x400;
export const STAGE_COMPUTE_SHADER: uint32 = 0x800;
export const STAGE_HOST: uint32 = 0x4000;

export const ACCESS_INDIRECT_COMMAND_READ: uint32 = 0x1;
export const ACCESS_INDEX_READ: uint32 = 0x2;
export const ACCESS_VERTEX_ATTRIBUTE_READ: uint32 = 0x4;
export const ACCESS_UNIFORM_READ: uint32 = 0x8;
export const ACCESS_SHADER_READ: uint32 = 0x20;
export const ACCESS_COLOR_ATTACHMENT_READ: uint32 = 0x80;
export const ACCESS_COLOR_ATTACHMENT_WRITE: uint32 = 0x100;
export const ACCESS_DEPTH_STENCIL_ATTACHMENT_READ: uint32 = 0x200;
export const ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE: uint32 = 0x400;
export const ACCESS_TRANSFER_WRITE: uint32 = 0x1000;
export const ACCESS_HOST_READ: uint32 = 0x2000;

export const LAYOUT_GENERAL: int32 = 1;
export const LAYOUT_COLOR_ATTACHMENT: int32 = 2;
export const LAYOUT_DEPTH_STENCIL_ATTACHMENT: int32 = 3;
export const LAYOUT_DEPTH_STENCIL_READ_ONLY: int32 = 4;
export const LAYOUT_SHADER_READ_ONLY: int32 = 5;
export const LAYOUT_TRANSFER_DST: int32 = 7;
export const LAYOUT_PRESENT: int32 = 1000001002;

export const LOAD_OP_LOAD: uint32 = 0;
export const LOAD_OP_CLEAR: uint32 = 1;
export const LOAD_OP_DONT_CARE: uint32 = 2;
export const STORE_OP_STORE: uint32 = 0;
export const STORE_OP_DONT_CARE: uint32 = 1;

export const ASPECT_COLOR: uint32 = 0x1;
export const ASPECT_DEPTH: uint32 = 0x2;
export const ASPECT_STENCIL: uint32 = 0x4;

export const IMAGE_TYPE_2D: int32 = 1;
export const IMAGE_TYPE_3D: int32 = 2;
export const IMAGE_CREATE_CUBE_COMPATIBLE: uint32 = 0x10;

const FORMAT_D24_UNORM_S8_UINT: int32 = 129;
const FORMAT_D32_SFLOAT_S8_UINT: int32 = 130;
const FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT: uint32 = 0x200;

export struct FormatInfo {
	native: int32;
	texelBytes: int32;
	aspect: uint32;
	depth: boolean;
}

@noinline function refuse(member: string, value: string): int32 {
	console.log(`webgpu vulkan: ${member} '${value}' is not supported`);
	unreachable;
}

@noinline function refuseFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu vulkan: ${member} '${value}' is not supported`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

function color(native: int32, texelBytes: int32): FormatInfo {
	return { native: native, texelBytes: texelBytes, aspect: ASPECT_COLOR, depth: false };
}

function depthFormat(native: int32, texelBytes: int32, aspect: uint32): FormatInfo {
	return { native: native, texelBytes: texelBytes, aspect: aspect, depth: true };
}

export function depthStencilNative(d24s8Features: uint32): int32 {
	return (d24s8Features & FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT) != 0
		? FORMAT_D24_UNORM_S8_UINT
		: FORMAT_D32_SFLOAT_S8_UINT;
}

export function d24s8Format(): int32 { return FORMAT_D24_UNORM_S8_UINT; }

export function formatInfo(format: GPUTextureFormat, depthStencil: int32, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => color(9, 1),
		"rg8unorm" => color(16, 2),
		"rgba8unorm" => color(37, 4),
		"rgba8unorm-srgb" => color(43, 4),
		"bgra8unorm" => color(44, 4),
		"bgra8unorm-srgb" => color(50, 4),
		"rgba8uint" => color(41, 4),
		"rgba8sint" => color(42, 4),
		"r16float" => color(76, 2),
		"rg16float" => color(83, 4),
		"rgba16float" => color(97, 8),
		"rgba16uint" => color(95, 8),
		"r32float" => color(100, 4),
		"rg32float" => color(103, 8),
		"rgba32float" => color(109, 16),
		"rgba32uint" => color(107, 16),
		"r32uint" => color(98, 4),
		"rgb10a2unorm" => color(64, 4),
		"rg11b10ufloat" => color(122, 4),
		"depth16unorm" => depthFormat(124, 2, ASPECT_DEPTH),
		"depth32float" => depthFormat(126, 4, ASPECT_DEPTH),
		"depth24plus-stencil8" => depthFormat(depthStencil, 0, ASPECT_DEPTH | ASPECT_STENCIL),
		_ => refuseFormat(member, value),
	};
}

export function bufferUsageFlags(usage: int32): uint32 {
	let flags: uint32 = 0;
	if (has(usage, GPUBufferUsage.COPY_SRC as int32)) { flags |= 0x1; }
	if (has(usage, GPUBufferUsage.COPY_DST as int32) || has(usage, GPUBufferUsage.QUERY_RESOLVE as int32)) { flags |= 0x2; }
	if (has(usage, GPUBufferUsage.UNIFORM as int32)) { flags |= 0x10; }
	if (has(usage, GPUBufferUsage.STORAGE as int32)) { flags |= 0x20; }
	if (has(usage, GPUBufferUsage.INDEX as int32)) { flags |= 0x40; }
	if (has(usage, GPUBufferUsage.VERTEX as int32)) { flags |= 0x80; }
	if (has(usage, GPUBufferUsage.INDIRECT as int32)) { flags |= 0x100; }
	return flags;
}

export function imageUsageFlags(usage: int32, depth: boolean): uint32 {
	let flags: uint32 = 0;
	if (has(usage, GPUTextureUsage.COPY_SRC as int32)) { flags |= 0x1; }
	if (has(usage, GPUTextureUsage.COPY_DST as int32)) { flags |= 0x2; }
	if (has(usage, GPUTextureUsage.TEXTURE_BINDING as int32)) { flags |= 0x4; }
	if (has(usage, GPUTextureUsage.STORAGE_BINDING as int32)) { flags |= 0x8; }
	if (has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32)) { flags |= (depth ? 0x20 : 0x10) as uint32; }
	return flags;
}

export function bufferMemoryKind(usage: int32): MemoryKind {
	if (has(usage, GPUBufferUsage.MAP_READ as int32)) { return MemoryKind.ReadMappable; }
	if (has(usage, GPUBufferUsage.MAP_WRITE as int32)) { return MemoryKind.WriteMappable; }
	return MemoryKind.DeviceLocal;
}

export function bufferRest(usage: int32): BufferRest {
	const shader = has(usage, GPUBufferUsage.UNIFORM as int32) || has(usage, GPUBufferUsage.STORAGE as int32);
	let stages: uint32 = 0;
	let access: uint32 = 0;
	if (has(usage, GPUBufferUsage.INDIRECT as int32)) {
		stages |= STAGE_DRAW_INDIRECT;
		access |= ACCESS_INDIRECT_COMMAND_READ;
	}
	if (has(usage, GPUBufferUsage.INDEX as int32) || has(usage, GPUBufferUsage.VERTEX as int32)) {
		stages |= STAGE_VERTEX_INPUT;
	}
	if (has(usage, GPUBufferUsage.INDEX as int32)) { access |= ACCESS_INDEX_READ; }
	if (has(usage, GPUBufferUsage.VERTEX as int32)) { access |= ACCESS_VERTEX_ATTRIBUTE_READ; }
	if (shader) { stages |= STAGE_VERTEX_SHADER | STAGE_FRAGMENT_SHADER | STAGE_COMPUTE_SHADER; }
	if (has(usage, GPUBufferUsage.UNIFORM as int32)) { access |= ACCESS_UNIFORM_READ; }
	if (has(usage, GPUBufferUsage.STORAGE as int32)) { access |= ACCESS_SHADER_READ; }
	if (has(usage, GPUBufferUsage.MAP_READ as int32)) {
		stages |= STAGE_HOST;
		access |= ACCESS_HOST_READ;
	}
	if (has(usage, GPUBufferUsage.COPY_SRC as int32) || has(usage, GPUBufferUsage.COPY_DST as int32)) {
		stages |= STAGE_TRANSFER;
	}
	if (has(usage, GPUBufferUsage.COPY_SRC as int32)) { access |= ACCESS_TRANSFER_READ; }
	return { stages: stages, access: access };
}

export function textureRest(usage: int32, aspect: uint32): TextureRest {
	const depth = aspect != ASPECT_COLOR;
	const shader = has(usage, GPUTextureUsage.TEXTURE_BINDING as int32) || has(usage, GPUTextureUsage.STORAGE_BINDING as int32);
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	let stages: uint32 = 0;
	let access: uint32 = 0;
	if (shader) {
		stages |= STAGE_VERTEX_SHADER | STAGE_FRAGMENT_SHADER | STAGE_COMPUTE_SHADER;
		access |= ACCESS_SHADER_READ;
	}
	if (attachment && depth) {
		stages |= STAGE_EARLY_FRAGMENT_TESTS | STAGE_LATE_FRAGMENT_TESTS;
		access |= ACCESS_DEPTH_STENCIL_ATTACHMENT_READ;
	}
	if (attachment && !depth) {
		stages |= STAGE_COLOR_ATTACHMENT_OUTPUT;
		access |= ACCESS_COLOR_ATTACHMENT_READ;
	}
	if (has(usage, GPUTextureUsage.COPY_SRC as int32) || has(usage, GPUTextureUsage.COPY_DST as int32)) {
		stages |= STAGE_TRANSFER;
	}
	if (has(usage, GPUTextureUsage.COPY_SRC as int32)) { access |= ACCESS_TRANSFER_READ; }
	let layout = LAYOUT_GENERAL;
	if (has(usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
		layout = LAYOUT_SHADER_READ_ONLY;
	} else if (attachment) {
		layout = depth ? LAYOUT_DEPTH_STENCIL_ATTACHMENT : LAYOUT_COLOR_ATTACHMENT;
	}
	return { stages: stages, access: access, layout: layout, aspect: aspect };
}

export function swapchainRest(): TextureRest {
	return { stages: STAGE_COLOR_ATTACHMENT_OUTPUT, access: 0, layout: LAYOUT_PRESENT, aspect: ASPECT_COLOR };
}

export function loadOp(op: GPULoadOp, member: string): uint32 {
	const value: string = op;
	const code = match (value) {
		"load" => LOAD_OP_LOAD as int32,
		"clear" => LOAD_OP_CLEAR as int32,
		_ => refuse(member, value),
	};
	return code as uint32;
}

export function storeOp(op: GPUStoreOp, member: string): uint32 {
	const value: string = op;
	const code = match (value) {
		"store" => STORE_OP_STORE as int32,
		"discard" => STORE_OP_DONT_CARE as int32,
		_ => refuse(member, value),
	};
	return code as uint32;
}

export function cubeCompatible(volume: boolean, width: int32, height: int32, layers: int32, samples: int32): boolean {
	return !volume && width == height && layers >= 6 && samples == 1;
}

export function viewType(dimension: string): int32 {
	return match (dimension) {
		"2d" => 1,
		"3d" => 2,
		"cube" => 3,
		"2d-array" => 5,
		"cube-array" => 6,
		_ => refuse("GPUTextureViewDescriptor.dimension", dimension),
	};
}

export function filter(mode: string, member: string): int32 {
	return match (mode) {
		"" | "nearest" => 0,
		"linear" => 1,
		_ => refuse(member, mode),
	};
}

export function addressMode(mode: string, member: string): int32 {
	return match (mode) {
		"repeat" => 0,
		"mirror-repeat" => 1,
		"" | "clamp-to-edge" => 2,
		_ => refuse(member, mode),
	};
}

export function compareOp(compare: string, member: string): int32 {
	return match (compare) {
		"" => -1,
		"never" => 0,
		"less" => 1,
		"equal" => 2,
		"less-equal" => 3,
		"greater" => 4,
		"not-equal" => 5,
		"greater-equal" => 6,
		"always" => 7,
		_ => refuse(member, compare),
	};
}

export function rowLength(bytesPerRow: int32, texelBytes: int32): uint32 {
	return (bytesPerRow / texelBytes) as uint32;
}

export const ACCESS_SHADER_WRITE: uint32 = 0x40;

export const SHADER_STAGE_VERTEX: uint32 = 0x1;
export const SHADER_STAGE_FRAGMENT: uint32 = 0x10;
export const SHADER_STAGE_COMPUTE: uint32 = 0x20;

export const DESCRIPTOR_SAMPLER: uint32 = 0;
export const DESCRIPTOR_SAMPLED_IMAGE: uint32 = 2;
export const DESCRIPTOR_STORAGE_IMAGE: uint32 = 3;
export const DESCRIPTOR_STORAGE_BUFFER: uint32 = 7;
export const DESCRIPTOR_UNIFORM_BUFFER_DYNAMIC: uint32 = 8;

export const INPUT_RATE_VERTEX: uint32 = 0;
export const INPUT_RATE_INSTANCE: uint32 = 1;

export const TOPOLOGY_LINE_STRIP: uint32 = 2;
export const TOPOLOGY_TRIANGLE_STRIP: uint32 = 4;

const COMPARE_ALWAYS: int32 = 7;
const BLEND_ZERO: int32 = 0;
const BLEND_ONE: int32 = 1;

export function shaderStages(visibility: int32): uint32 {
	let stages: uint32 = 0;
	if (has(visibility, GPUShaderStage.VERTEX as int32)) { stages |= SHADER_STAGE_VERTEX; }
	if (has(visibility, GPUShaderStage.FRAGMENT as int32)) { stages |= SHADER_STAGE_FRAGMENT; }
	if (has(visibility, GPUShaderStage.COMPUTE as int32)) { stages |= SHADER_STAGE_COMPUTE; }
	return stages;
}

export function topology(value: GPUPrimitiveTopology): uint32 {
	const name: string = value;
	const code = match (name) {
		"point-list" => 0,
		"line-list" => 1,
		"line-strip" => 2,
		"" | "triangle-list" => 3,
		"triangle-strip" => 4,
		_ => refuse("primitive.topology", name),
	};
	return code as uint32;
}

export function indexType(format: GPUIndexFormat, member: string): int32 {
	const name: string = format;
	return match (name) {
		"uint16" => 0,
		"uint32" => 1,
		_ => refuse(member, name),
	};
}

export function cullMode(cull: GPUCullMode): uint32 {
	const name: string = cull;
	const code = match (name) {
		"" | "none" => 0,
		"front" => 1,
		"back" => 2,
		_ => refuse("primitive.cullMode", name),
	};
	return code as uint32;
}

export function frontFace(face: GPUFrontFace): uint32 {
	const name: string = face;
	const code = match (name) {
		"" | "ccw" => 0,
		"cw" => 1,
		_ => refuse("primitive.frontFace", name),
	};
	return code as uint32;
}

export function pipelineCompare(compare: GPUCompareFunction, member: string): uint32 {
	const name: string = compare;
	if (name == "") { return COMPARE_ALWAYS as uint32; }
	return compareOp(name, member) as uint32;
}

export function stencilOp(op: GPUStencilOperation, member: string): uint32 {
	const name: string = op;
	const code = match (name) {
		"" | "keep" => 0,
		"zero" => 1,
		"replace" => 2,
		"increment-clamp" => 3,
		"decrement-clamp" => 4,
		"invert" => 5,
		"increment-wrap" => 6,
		"decrement-wrap" => 7,
		_ => refuse(member, name),
	};
	return code as uint32;
}

function blendFactorCode(factor: string, fallback: int32, member: string): uint32 {
	const code = match (factor) {
		"" => fallback,
		"zero" => BLEND_ZERO,
		"one" => BLEND_ONE,
		"src" => 2,
		"one-minus-src" => 3,
		"dst" => 4,
		"one-minus-dst" => 5,
		"src-alpha" => 6,
		"one-minus-src-alpha" => 7,
		"dst-alpha" => 8,
		"one-minus-dst-alpha" => 9,
		"constant" => 10,
		"one-minus-constant" => 11,
		"src-alpha-saturated" => 14,
		_ => refuse(member, factor),
	};
	return code as uint32;
}

export function sourceFactor(factor: GPUBlendFactor, member: string): uint32 {
	return blendFactorCode(factor, BLEND_ONE, member);
}

export function destinationFactor(factor: GPUBlendFactor, member: string): uint32 {
	return blendFactorCode(factor, BLEND_ZERO, member);
}

export function blendOp(operation: GPUBlendOperation, member: string): uint32 {
	const name: string = operation;
	const code = match (name) {
		"" | "add" => 0,
		"subtract" => 1,
		"reverse-subtract" => 2,
		"min" => 3,
		"max" => 4,
		_ => refuse(member, name),
	};
	return code as uint32;
}

export function vertexFormat(format: GPUVertexFormat, member: string): uint32 {
	const name: string = format;
	const code = match (name) {
		"unorm8x2" => 16,
		"snorm8x2" => 17,
		"uint8x2" => 20,
		"sint8x2" => 21,
		"unorm8x4" => 37,
		"snorm8x4" => 38,
		"uint8x4" => 41,
		"sint8x4" => 42,
		"unorm16x2" => 77,
		"snorm16x2" => 78,
		"uint16x2" => 81,
		"sint16x2" => 82,
		"float16x2" => 83,
		"unorm16x4" => 91,
		"snorm16x4" => 92,
		"uint16x4" => 95,
		"sint16x4" => 96,
		"float16x4" => 97,
		"uint32" => 98,
		"sint32" => 99,
		"float32" => 100,
		"uint32x2" => 101,
		"sint32x2" => 102,
		"float32x2" => 103,
		"uint32x3" => 104,
		"sint32x3" => 105,
		"float32x3" => 106,
		"uint32x4" => 107,
		"sint32x4" => 108,
		"float32x4" => 109,
		_ => refuse(member, name),
	};
	return code as uint32;
}

export function inputRate(stepMode: GPUVertexStepMode, member: string): uint32 {
	const name: string = stepMode;
	const code = match (name) {
		"" | "vertex" => INPUT_RATE_VERTEX as int32,
		"instance" => INPUT_RATE_INSTANCE as int32,
		_ => refuse(member, name),
	};
	return code as uint32;
}
