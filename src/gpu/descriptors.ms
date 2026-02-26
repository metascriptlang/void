// WebGPU Descriptor Interfaces — matching @webgpu/types spec
// Flattened (no extends) to work with MetaScript C codegen.
// Reference: ~/projects/webgpu-types/dist/index.d.ts

import {
	GPUTextureFormat, GPUPrimitiveTopology, GPUFrontFace, GPUCullMode,
	GPULoadOp, GPUStoreOp, GPUColorWriteFlags,
	GPUSize32, GPUSampleMask, GPUColorDict,
	GPUCanvasAlphaMode, GPUTextureUsageFlags
} from "./types"

// --- Shader ---

export interface GPUShaderModuleDescriptor {
	label?: string;
	code: string;
}

// --- Buffer ---

export interface GPUBufferDescriptor {
	label?: string;
	size: uint64;
	usage: uint32;
	mappedAtCreation: int32;
}

// --- Vertex Layout ---

export interface GPUVertexAttribute {
	format: uint32;
	offset: uint64;
	shaderLocation: uint32;
}

export interface GPUVertexBufferLayout {
	arrayStride: uint64;
	stepMode?: string;
	attributes: Array<GPUVertexAttribute>;
}

// --- Pipeline ---

export interface GPUVertexState {
	module: unknown;
	entryPoint: string;
	buffers: Array<GPUVertexBufferLayout>;
}

export interface GPUFragmentState {
	module: unknown;
	entryPoint: string;
	targets: Array<GPUColorTargetState>;
}

export interface GPUColorTargetState {
	format: GPUTextureFormat;
	writeMask?: GPUColorWriteFlags;
}

export interface GPUPrimitiveState {
	topology: string;
	frontFace?: string;
	cullMode?: string;
}

export interface GPUMultisampleState {
	count?: GPUSize32;
	mask?: GPUSampleMask;
}

export interface GPURenderPipelineDescriptor {
	label?: string;
	layout: string;
	vertex: GPUVertexState;
	primitive?: GPUPrimitiveState;
	multisample?: GPUMultisampleState;
	fragment?: GPUFragmentState;
}

// --- Render Pass ---

export interface GPURenderPassColorAttachment {
	view: unknown;
	clearR: float64;
	clearG: float64;
	clearB: float64;
	clearA: float64;
	loadOp: string;
	storeOp: string;
}

export interface GPURenderPassDescriptor {
	label?: string;
	colorAttachments: Array<GPURenderPassColorAttachment>;
}

// --- Bind Group ---

export interface GPUBindGroupLayoutEntry {
	binding: uint32;
	visibility: uint32;
	bufferType: uint32;
	bufferMinBindingSize: uint64;
}

export interface GPUBindGroupEntry {
	binding: uint32;
	buffer: unknown;
	offset: uint64;
	size: uint64;
}

// --- Depth Stencil ---

export interface GPUDepthStencilState {
	format: uint32;
	depthWriteEnabled: int32;
	depthCompare: uint32;
}

export interface GPURenderPassDepthStencilAttachment {
	view: unknown;
	depthClearValue: float32;
	depthLoadOp: string;
	depthStoreOp: string;
}

// --- Canvas ---

export interface GPUCanvasConfiguration {
	device: unknown;
	format: string;
	width: uint32;
	height: uint32;
	usage?: GPUTextureUsageFlags;
	alphaMode?: GPUCanvasAlphaMode;
}
