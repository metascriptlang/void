// Void's WebGPU-shaped API: names and fields as WebGPU spells them, docs/GPU.md.
// A handle is a pool id with sokol's encoding (slot index + generation); 0 is invalid.
// A fixed array field holds up to the limit Void uses; trailing entries stay zero and are unused.

export struct GPUBuffer { id: uint32; }
export struct GPUTexture { id: uint32; }
export struct GPUTextureView { id: uint32; }
export struct GPUSampler { id: uint32; }
export struct GPUShaderModule { id: uint32; }
export struct GPURenderPipeline { id: uint32; }
export struct GPUBindGroupLayout { id: uint32; }
export struct GPUBindGroup { id: uint32; }
export struct GPUQueue { id: uint32; }
export struct GPUDevice { id: uint32; queue: GPUQueue; }
export struct GPUCommandEncoder { id: uint32; }
export struct GPUCommandBuffer { id: uint32; }
export struct GPURenderPassEncoder { id: uint32; }

export const GPU_MAX_COLOR_ATTACHMENTS = 4;
export const GPU_MAX_VERTEX_BUFFERS = 2;
export const GPU_MAX_VERTEX_ATTRIBUTES = 16;
export const GPU_MAX_BIND_GROUP_ENTRIES = 8;
export const GPU_MAX_UNIFORM_BLOCKS = 8;
export const GPU_UNIFORM_GROUP = 0;
export const GPU_RESOURCE_GROUP = 1;

export enum GPUBufferUsage {
	MAP_READ = 0x1,
	MAP_WRITE = 0x2,
	COPY_SRC = 0x4,
	COPY_DST = 0x8,
	INDEX = 0x10,
	VERTEX = 0x20,
	UNIFORM = 0x40,
}

export enum GPUTextureUsage {
	COPY_SRC = 0x1,
	COPY_DST = 0x2,
	TEXTURE_BINDING = 0x4,
	RENDER_ATTACHMENT = 0x10,
}

export enum GPUColorWrite {
	RED = 0x1,
	GREEN = 0x2,
	BLUE = 0x4,
	ALPHA = 0x8,
	ALL = 0xF,
}

export type GPUTextureFormat =
	| "r8unorm"
	| "rgba8unorm"
	| "bgra8unorm"
	| "rgba16float"
	| "depth32float"
	| "depth24plus-stencil8";
export type GPUTextureSampleType = "float" | "unfilterable-float";
export type GPUSamplerBindingType = "filtering" | "non-filtering";
export type GPULoadOp = "load" | "clear";
export type GPUStoreOp = "store" | "discard";
export type GPUCompareFunction =
	| "never"
	| "less"
	| "equal"
	| "less-equal"
	| "greater"
	| "not-equal"
	| "greater-equal"
	| "always";
export type GPUCullMode = "none" | "front" | "back";
export type GPUFrontFace = "ccw" | "cw";
export type GPUPrimitiveTopology = "triangle-list";
export type GPUIndexFormat = "uint16" | "uint32";
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
	| "src-alpha-saturated";
export type GPUBlendOperation = "add" | "subtract" | "reverse-subtract" | "min" | "max";
export type GPUVertexFormat = "float32" | "float32x2" | "float32x3" | "float32x4" | "unorm8x4";
export type GPUVertexStepMode = "vertex" | "instance";
export type GPUFilterMode = "nearest" | "linear";
export type GPUAddressMode = "clamp-to-edge" | "repeat" | "mirror-repeat";
export type GPUBackend = "d3d11" | "metal" | "glcore" | "gles3" | "webgpu";

export struct GPUColor { r: number; g: number; b: number; a: number; }
export struct GPUExtent3D { width: int32; height: int32; depthOrArrayLayers: int32; }

export struct GPUBufferDescriptor {
	label: string | null;
	size: int64;
	usage: int32;
}

export struct GPUTextureDescriptor {
	label: string | null;
	size: GPUExtent3D;
	format: GPUTextureFormat;
	usage: int32;
	sampleCount: int32;
}

export struct GPUTextureViewDescriptor { label: string | null; }

export struct GPUSamplerDescriptor {
	label: string | null;
	addressModeU: GPUAddressMode;
	addressModeV: GPUAddressMode;
	magFilter: GPUFilterMode;
	minFilter: GPUFilterMode;
}

// A shader module carries one stage's source per entry, compiled for the backend this build
// targets, and the reflection that maps a WebGPU binding to the backend's register or name.
export type GPUShaderBindingKind = "uniform" | "texture" | "sampler";
export type GPUShaderStage = "vertex" | "fragment";

export struct GPUShaderBinding {
	group: int32;
	binding: int32;
	kind: GPUShaderBindingKind;
	stage: GPUShaderStage;
	size: int32;
	sampleType: GPUTextureSampleType;
	samplerType: GPUSamplerBindingType;
	nativeSlot: int32;
	nativeName: string | null;
	textureBinding: int32;
}

export struct GPUShaderAttribute {
	location: int32;
	nativeName: string | null;
	semanticIndex: int32;
}

export struct GPUShaderModuleDescriptor {
	label: string | null;
	vertexCode: string;
	vertexEntryPoint: string;
	fragmentCode: string;
	fragmentEntryPoint: string;
	bindings: GPUShaderBinding[24];
	attributes: GPUShaderAttribute[16];
}

export struct GPUVertexAttribute {
	format: GPUVertexFormat;
	offset: int32;
	shaderLocation: int32;
}

export struct GPUVertexBufferLayout {
	arrayStride: int32;
	stepMode: GPUVertexStepMode;
	attributes: GPUVertexAttribute[16];
}

export struct GPUVertexState {
	module: GPUShaderModule;
	buffers: GPUVertexBufferLayout[2];
}

export struct GPUBlendComponent {
	operation: GPUBlendOperation;
	srcFactor: GPUBlendFactor;
	dstFactor: GPUBlendFactor;
}

export struct GPUBlendState {
	color: GPUBlendComponent;
	alpha: GPUBlendComponent;
}

// `blend` absent is WebGPU's "no blending"; Void marks it with `blendEnabled`, since a
// nullable struct field is a heap carrier.
export struct GPUColorTargetState {
	format: GPUTextureFormat;
	blendEnabled: boolean;
	blend: GPUBlendState;
	writeMask: int32;
}

export struct GPUFragmentState {
	module: GPUShaderModule;
	targets: GPUColorTargetState[4];
}

export struct GPUPrimitiveState {
	topology: GPUPrimitiveTopology;
	frontFace: GPUFrontFace;
	cullMode: GPUCullMode;
}

export struct GPUDepthStencilState {
	format: GPUTextureFormat;
	depthWriteEnabled: boolean;
	depthCompare: GPUCompareFunction;
}

export struct GPUMultisampleState { count: int32; }

// `depthStencil.format` "" means no depth attachment; `fragment.targets` with no format means
// a depth-only pipeline.
export struct GPURenderPipelineDescriptor {
	label: string | null;
	vertex: GPUVertexState;
	primitive: GPUPrimitiveState;
	depthStencil: GPUDepthStencilState;
	multisample: GPUMultisampleState;
	fragment: GPUFragmentState;
}

export struct GPUBindGroupEntry {
	binding: int32;
	buffer: GPUBuffer;
	size: int64;
	textureView: GPUTextureView;
	sampler: GPUSampler;
}

export struct GPUBindGroupDescriptor {
	label: string | null;
	layout: GPUBindGroupLayout;
	entries: GPUBindGroupEntry[8];
}

export struct GPURenderPassColorAttachment {
	view: GPUTextureView;
	resolveTarget: GPUTextureView;
	clearValue: GPUColor;
	loadOp: GPULoadOp;
	storeOp: GPUStoreOp;
}

export struct GPURenderPassDepthStencilAttachment {
	view: GPUTextureView;
	depthClearValue: number;
	depthLoadOp: GPULoadOp;
	depthStoreOp: GPUStoreOp;
}

export struct GPURenderPassDescriptor {
	label: string | null;
	colorAttachments: GPURenderPassColorAttachment[4];
	depthStencilAttachment: GPURenderPassDepthStencilAttachment;
}

export struct GPUTexelCopyTextureInfo { texture: GPUTexture; }
export struct GPUTexelCopyBufferLayout { offset: int64; bytesPerRow: int32; rowsPerImage: int32; }

// What sokol's sg_query_features/limits/stats answered for Void (inventory E).
export struct GPUAdapterInfo {
	backend: GPUBackend;
	originTopLeft: boolean;
	depthZeroToOne: boolean;
}
