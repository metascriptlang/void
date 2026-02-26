// WebGPU Type Definitions — matching @webgpu/types spec
// Reference: ~/projects/webgpu-types/dist/index.d.ts

// --- Numeric aliases ---

export type GPUSize32 = uint32;
export type GPUSize64 = uint64;
export type GPUIndex32 = uint32;
export type GPUFlagsConstant = uint32;
export type GPUIntegerCoordinate = uint32;
export type GPUSignedOffset32 = int32;
export type GPUStencilValue = uint32;
export type GPUSampleMask = uint32;
export type GPUDepthBias = int32;
export type GPUBufferDynamicOffset = uint32;
export type GPUColorWriteFlags = uint32;
export type GPUBufferUsageFlags = uint32;
export type GPUTextureUsageFlags = uint32;
export type GPUMapModeFlags = uint32;
export type GPUShaderStageFlags = uint32;
export type GPUPipelineConstantValue = float64;

// --- String literal union types (enums) ---

export type GPUTextureFormat =
	| "r8unorm"
	| "r8snorm"
	| "r8uint"
	| "r8sint"
	| "r16uint"
	| "r16sint"
	| "r16float"
	| "rg8unorm"
	| "rg8snorm"
	| "rg8uint"
	| "rg8sint"
	| "r32uint"
	| "r32sint"
	| "r32float"
	| "rg16uint"
	| "rg16sint"
	| "rg16float"
	| "rgba8unorm"
	| "rgba8unorm-srgb"
	| "rgba8snorm"
	| "rgba8uint"
	| "rgba8sint"
	| "bgra8unorm"
	| "bgra8unorm-srgb"
	| "rgb9e5ufloat"
	| "rgb10a2uint"
	| "rgb10a2unorm"
	| "rg11b10ufloat"
	| "rg32uint"
	| "rg32sint"
	| "rg32float"
	| "rgba16uint"
	| "rgba16sint"
	| "rgba16float"
	| "rgba32uint"
	| "rgba32sint"
	| "rgba32float"
	| "stencil8"
	| "depth16unorm"
	| "depth24plus"
	| "depth24plus-stencil8"
	| "depth32float"
	| "depth32float-stencil8";

export type GPUPrimitiveTopology =
	| "point-list"
	| "line-list"
	| "line-strip"
	| "triangle-list"
	| "triangle-strip";

export type GPUFrontFace =
	| "ccw"
	| "cw";

export type GPUCullMode =
	| "none"
	| "front"
	| "back";

export type GPULoadOp =
	| "load"
	| "clear";

export type GPUStoreOp =
	| "store"
	| "discard";

export type GPUIndexFormat =
	| "uint16"
	| "uint32";

export type GPUBlendFactor =
	| "zero"
	| "one"
	| "src"
	| "one-minus-src"
	| "src-alpha"
	| "one-minus-src-alpha"
	| "dst"
	| "one-minus-dst"
	| "dst-alpha"
	| "one-minus-dst-alpha"
	| "src-alpha-saturated"
	| "constant"
	| "one-minus-constant";

export type GPUBlendOperation =
	| "add"
	| "subtract"
	| "reverse-subtract"
	| "min"
	| "max";

export type GPUCompareFunction =
	| "never"
	| "less"
	| "equal"
	| "less-equal"
	| "greater"
	| "not-equal"
	| "greater-equal"
	| "always";

export type GPUTextureDimension =
	| "1d"
	| "2d"
	| "3d";

export type GPUTextureViewDimension =
	| "1d"
	| "2d"
	| "2d-array"
	| "cube"
	| "cube-array"
	| "3d";

export type GPUTextureAspect =
	| "all"
	| "stencil-only"
	| "depth-only";

export type GPUTextureSampleType =
	| "float"
	| "unfilterable-float"
	| "depth"
	| "sint"
	| "uint";

export type GPUAddressMode =
	| "clamp-to-edge"
	| "repeat"
	| "mirror-repeat";

export type GPUFilterMode =
	| "nearest"
	| "linear";

export type GPUMipmapFilterMode =
	| "nearest"
	| "linear";

export type GPUVertexFormat =
	| "uint8"
	| "uint8x2"
	| "uint8x4"
	| "sint8"
	| "sint8x2"
	| "sint8x4"
	| "unorm8"
	| "unorm8x2"
	| "unorm8x4"
	| "snorm8"
	| "snorm8x2"
	| "snorm8x4"
	| "uint16"
	| "uint16x2"
	| "uint16x4"
	| "sint16"
	| "sint16x2"
	| "sint16x4"
	| "unorm16"
	| "unorm16x2"
	| "unorm16x4"
	| "snorm16"
	| "snorm16x2"
	| "snorm16x4"
	| "float16"
	| "float16x2"
	| "float16x4"
	| "float32"
	| "float32x2"
	| "float32x3"
	| "float32x4"
	| "uint32"
	| "uint32x2"
	| "uint32x3"
	| "uint32x4"
	| "sint32"
	| "sint32x2"
	| "sint32x3"
	| "sint32x4";

export type GPUVertexStepMode =
	| "vertex"
	| "instance";

export type GPUStencilOperation =
	| "keep"
	| "zero"
	| "replace"
	| "invert"
	| "increment-clamp"
	| "decrement-clamp"
	| "increment-wrap"
	| "decrement-wrap";

export type GPUBufferBindingType =
	| "uniform"
	| "storage"
	| "read-only-storage";

export type GPUBufferMapState =
	| "unmapped"
	| "pending"
	| "mapped";

export type GPUSamplerBindingType =
	| "filtering"
	| "non-filtering"
	| "comparison";

export type GPUStorageTextureAccess =
	| "write-only"
	| "read-only"
	| "read-write";

export type GPUAutoLayoutMode = "auto";

export type GPUPowerPreference =
	| "low-power"
	| "high-performance";

export type GPUCanvasAlphaMode =
	| "opaque"
	| "premultiplied";

export type GPUErrorFilter =
	| "validation"
	| "out-of-memory"
	| "internal";

export type GPUDeviceLostReason =
	| "unknown"
	| "destroyed";

export type GPUQueryType =
	| "occlusion"
	| "timestamp";

// --- Composite types ---

export interface GPUColorDict {
	r: float64;
	g: float64;
	b: float64;
	a: float64;
}

export type GPUColor = GPUColorDict;

export interface GPUOrigin2DDict {
	x?: GPUIntegerCoordinate;
	y?: GPUIntegerCoordinate;
}

export interface GPUOrigin3DDict {
	x?: GPUIntegerCoordinate;
	y?: GPUIntegerCoordinate;
	z?: GPUIntegerCoordinate;
}

export interface GPUExtent3DDict {
	width: GPUIntegerCoordinate;
	height?: GPUIntegerCoordinate;
	depthOrArrayLayers?: GPUIntegerCoordinate;
}

export type GPUOrigin2D = GPUOrigin2DDict;
export type GPUOrigin3D = GPUOrigin3DDict;
export type GPUExtent3D = GPUExtent3DDict;
