// WebGPU Flag Constants — matching @webgpu/types spec
// Reference: ~/projects/webgpu-types/dist/index.d.ts

import { GPUFlagsConstant } from "./types"

// --- GPUBufferUsage ---

export const GPUBufferUsage = {
	MAP_READ:      0x0001 as GPUFlagsConstant,
	MAP_WRITE:     0x0002 as GPUFlagsConstant,
	COPY_SRC:      0x0004 as GPUFlagsConstant,
	COPY_DST:      0x0008 as GPUFlagsConstant,
	INDEX:         0x0010 as GPUFlagsConstant,
	VERTEX:        0x0020 as GPUFlagsConstant,
	UNIFORM:       0x0040 as GPUFlagsConstant,
	STORAGE:       0x0080 as GPUFlagsConstant,
	INDIRECT:      0x0100 as GPUFlagsConstant,
	QUERY_RESOLVE: 0x0200 as GPUFlagsConstant,
};

// --- GPUTextureUsage ---

export const GPUTextureUsage = {
	COPY_SRC:             0x01 as GPUFlagsConstant,
	COPY_DST:             0x02 as GPUFlagsConstant,
	TEXTURE_BINDING:      0x04 as GPUFlagsConstant,
	STORAGE_BINDING:      0x08 as GPUFlagsConstant,
	RENDER_ATTACHMENT:    0x10 as GPUFlagsConstant,
	TRANSIENT_ATTACHMENT: 0x20 as GPUFlagsConstant,
};

// --- GPUColorWrite ---

export const GPUColorWrite = {
	RED:   0x1 as GPUFlagsConstant,
	GREEN: 0x2 as GPUFlagsConstant,
	BLUE:  0x4 as GPUFlagsConstant,
	ALPHA: 0x8 as GPUFlagsConstant,
	ALL:   0xF as GPUFlagsConstant,
};

// --- GPUShaderStage ---

export const GPUShaderStage = {
	VERTEX:   0x1 as GPUFlagsConstant,
	FRAGMENT: 0x2 as GPUFlagsConstant,
	COMPUTE:  0x4 as GPUFlagsConstant,
};

// --- GPUVertexFormat (Dawn WGPUVertexFormat enum values) ---

export const VertexFormat = {
	FLOAT32:   0x1C as GPUFlagsConstant,
	FLOAT32X2: 0x1D as GPUFlagsConstant,
	FLOAT32X3: 0x1E as GPUFlagsConstant,
	FLOAT32X4: 0x1F as GPUFlagsConstant,
	UINT32:    0x20 as GPUFlagsConstant,
	UINT32X2:  0x21 as GPUFlagsConstant,
	UINT32X3:  0x22 as GPUFlagsConstant,
	UINT32X4:  0x23 as GPUFlagsConstant,
	SINT32:    0x24 as GPUFlagsConstant,
	SINT32X2:  0x25 as GPUFlagsConstant,
	SINT32X3:  0x26 as GPUFlagsConstant,
	SINT32X4:  0x27 as GPUFlagsConstant,
};

// --- GPUIndexFormat (Dawn WGPUIndexFormat enum values) ---

export const IndexFormat = {
	UINT16: 1 as GPUFlagsConstant,  // WGPUIndexFormat_Uint16
	UINT32: 2 as GPUFlagsConstant,  // WGPUIndexFormat_Uint32
};

// --- GPUCompareFunction (Dawn WGPUCompareFunction enum values) ---

export const CompareFunction = {
	NEVER:         1 as GPUFlagsConstant,
	LESS:          2 as GPUFlagsConstant,
	EQUAL:         3 as GPUFlagsConstant,
	LESS_EQUAL:    4 as GPUFlagsConstant,
	GREATER:       5 as GPUFlagsConstant,
	NOT_EQUAL:     6 as GPUFlagsConstant,
	GREATER_EQUAL: 7 as GPUFlagsConstant,
	ALWAYS:        8 as GPUFlagsConstant,
};

// --- GPUTextureFormat (Dawn WGPUTextureFormat enum values, subset) ---

export const TextureFormat = {
	RGBA8_UNORM:      0x12 as GPUFlagsConstant,  // WGPUTextureFormat_RGBA8Unorm
	RGBA8_UNORM_SRGB: 0x13 as GPUFlagsConstant,  // WGPUTextureFormat_RGBA8UnormSrgb
	BGRA8_UNORM:      0x17 as GPUFlagsConstant,  // WGPUTextureFormat_BGRA8Unorm
	DEPTH24_PLUS:     0x28 as GPUFlagsConstant,  // WGPUTextureFormat_Depth24Plus
};

// --- GPUCullMode (Dawn WGPUCullMode enum values) ---

export const CullMode = {
	NONE:  1 as GPUFlagsConstant,  // WGPUCullMode_None
	FRONT: 2 as GPUFlagsConstant,  // WGPUCullMode_Front
	BACK:  3 as GPUFlagsConstant,  // WGPUCullMode_Back
};

// --- GPUAddressMode (Dawn WGPUAddressMode enum values) ---

export const AddressMode = {
	CLAMP_TO_EDGE: 1 as GPUFlagsConstant,  // WGPUAddressMode_ClampToEdge
	REPEAT:        2 as GPUFlagsConstant,   // WGPUAddressMode_Repeat
	MIRROR_REPEAT: 3 as GPUFlagsConstant,   // WGPUAddressMode_MirrorRepeat
};

// --- GPUFilterMode (Dawn WGPUFilterMode enum values) ---

export const FilterMode = {
	NEAREST: 1 as GPUFlagsConstant,  // WGPUFilterMode_Nearest
	LINEAR:  2 as GPUFlagsConstant,  // WGPUFilterMode_Linear
};

// --- GPUBlendFactor (Dawn WGPUBlendFactor enum values) ---

export const BlendFactor = {
	ZERO:                 1 as GPUFlagsConstant,
	ONE:                  2 as GPUFlagsConstant,
	SRC:                  3 as GPUFlagsConstant,
	ONE_MINUS_SRC:        4 as GPUFlagsConstant,
	SRC_ALPHA:            5 as GPUFlagsConstant,
	ONE_MINUS_SRC_ALPHA:  6 as GPUFlagsConstant,
	DST:                  7 as GPUFlagsConstant,
	ONE_MINUS_DST:        8 as GPUFlagsConstant,
	DST_ALPHA:            9 as GPUFlagsConstant,
	ONE_MINUS_DST_ALPHA: 10 as GPUFlagsConstant,
};

// --- GPUBlendOperation (Dawn WGPUBlendOperation enum values) ---

export const BlendOperation = {
	ADD:              1 as GPUFlagsConstant,
	SUBTRACT:         2 as GPUFlagsConstant,
	REVERSE_SUBTRACT: 3 as GPUFlagsConstant,
	MIN:              4 as GPUFlagsConstant,
	MAX:              5 as GPUFlagsConstant,
};

// --- GPUMapMode ---

export const GPUMapMode = {
	READ:  0x1 as GPUFlagsConstant,
	WRITE: 0x2 as GPUFlagsConstant,
};
