import { GPUBufferUsage, GPUTextureFormat, GPUTextureUsage } from "../types.ms";
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
export const ACCESS_DEPTH_STENCIL_ATTACHMENT_READ: uint32 = 0x200;
export const ACCESS_TRANSFER_WRITE: uint32 = 0x1000;
export const ACCESS_HOST_READ: uint32 = 0x2000;

export const LAYOUT_GENERAL: int32 = 1;
export const LAYOUT_COLOR_ATTACHMENT: int32 = 2;
export const LAYOUT_DEPTH_STENCIL_ATTACHMENT: int32 = 3;
export const LAYOUT_SHADER_READ_ONLY: int32 = 5;
export const LAYOUT_TRANSFER_DST: int32 = 7;

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

export function textureRest(usage: int32, depth: boolean): TextureRest {
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
	return { stages: stages, access: access, layout: layout };
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
