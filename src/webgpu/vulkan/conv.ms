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
	FORMAT_COUNT,
	addressModeNative,
	blendFactorNative,
	blendOperationNative,
	compareNative,
	nativeAt,
	stencilOperationNative,
	textureFormatFacts,
	topologyNative,
	vertexFormatNative,
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

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

export function depthStencilNative(d24s8Features: uint32): int32 {
	return (d24s8Features & FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT) != 0
		? FORMAT_D24_UNORM_S8_UINT
		: FORMAT_D32_SFLOAT_S8_UINT;
}

export function d24s8Format(): int32 { return FORMAT_D24_UNORM_S8_UINT; }

const FORMATS: int32[] = [9, 16, 37, 43, 44, 50, 41, 42, 76, 83, 97, 95, 100, 103, 109, 107, 98, 64, 122, 124, 126, 0];

export function formatInfo(format: GPUTextureFormat, depthStencil: int32, member: string): FormatInfo {
	const facts = textureFormatFacts(format, member, "vulkan");
	if (facts.stencil) { return { native: depthStencil, texelBytes: 0, aspect: ASPECT_DEPTH | ASPECT_STENCIL, depth: true }; }
	const native = nativeAt(FORMATS, FORMAT_COUNT, facts.index, "vulkan", "VkFormat");
	return { native: native, texelBytes: facts.bytesPerPixel, aspect: facts.depth ? ASPECT_DEPTH : ASPECT_COLOR, depth: facts.depth };
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

const ADDRESS_MODES: int32[] = [2, 0, 1];

export function addressMode(mode: string, member: string): int32 { return addressModeNative(ADDRESS_MODES, mode, member, "vulkan"); }

const COMPARE_OPS: int32[] = [0, 1, 2, 3, 4, 5, 6, 7];

export function compareOp(compare: string, member: string): int32 {
	if (compare == "") { return -1; }
	return compareNative(COMPARE_OPS, compare, member, "vulkan");
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

const BLEND_ZERO: int32 = 0;
const BLEND_ONE: int32 = 1;

export function shaderStages(visibility: int32): uint32 {
	let stages: uint32 = 0;
	if (has(visibility, GPUShaderStage.VERTEX as int32)) { stages |= SHADER_STAGE_VERTEX; }
	if (has(visibility, GPUShaderStage.FRAGMENT as int32)) { stages |= SHADER_STAGE_FRAGMENT; }
	if (has(visibility, GPUShaderStage.COMPUTE as int32)) { stages |= SHADER_STAGE_COMPUTE; }
	return stages;
}

const TOPOLOGIES: int32[] = [0, 1, TOPOLOGY_LINE_STRIP as int32, 3, TOPOLOGY_TRIANGLE_STRIP as int32];

export function topology(value: GPUPrimitiveTopology): uint32 {
	return topologyNative(TOPOLOGIES, value, "primitive.topology", "vulkan") as uint32;
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
	return compareNative(COMPARE_OPS, compare, member, "vulkan") as uint32;
}

const STENCIL_OPS: int32[] = [0, 1, 2, 5, 3, 4, 6, 7];

export function stencilOp(op: GPUStencilOperation, member: string): uint32 {
	return stencilOperationNative(STENCIL_OPS, op, member, "vulkan") as uint32;
}

const BLEND_FACTORS: int32[] = [BLEND_ZERO, BLEND_ONE, 2, 3, 6, 7, 4, 5, 8, 9, 14, 10, 11];

export function sourceFactor(factor: GPUBlendFactor, member: string): uint32 {
	return blendFactorNative(BLEND_FACTORS, factor, member, "vulkan") as uint32;
}

export function destinationFactor(factor: GPUBlendFactor, member: string): uint32 {
	const value: string = factor;
	if (value == "") { return BLEND_ZERO as uint32; }
	return sourceFactor(factor, member);
}

const BLEND_OPS: int32[] = [0, 1, 2, 3, 4];

export function blendOp(operation: GPUBlendOperation, member: string): uint32 {
	return blendOperationNative(BLEND_OPS, operation, member, "vulkan") as uint32;
}

const VERTEX_FORMATS: int32[] = [
	20, 41, 21, 42, 16, 37, 17, 38,
	81, 95, 82, 96, 77, 91, 78, 92, 83, 97,
	100, 103, 106, 109, 98, 101, 104, 107, 99, 102, 105, 108,
];

export function vertexFormat(format: GPUVertexFormat, member: string): uint32 {
	return vertexFormatNative(VERTEX_FORMATS, format, member, "vulkan") as uint32;
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
