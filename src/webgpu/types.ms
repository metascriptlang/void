// Void's WebGPU-shaped API: names and fields as WebGPU spells them, docs/GPU.md.
// A handle is a pool id with sokol's encoding (slot index + generation); 0 is invalid.
// A fixed array field holds up to the limit Void uses; trailing entries stay zero and are unused.

export struct GPUBuffer { id: uint32; }
export struct GPUTexture { id: uint32; }
export struct GPUTextureView { id: uint32; }
export struct GPUSampler { id: uint32; }
export struct GPUShaderModule { id: uint32; }
export struct GPURenderPipeline { id: uint32; }
export struct GPUComputePipeline { id: uint32; }
export struct GPUBindGroupLayout { id: uint32; }
export struct GPUBindGroup { id: uint32; }
export struct GPUQueue { id: uint32; }
export struct GPUDevice { id: uint32; queue: GPUQueue; }
export struct GPUCommandEncoder { id: uint32; }
export struct GPUCommandBuffer { id: uint32; }
export struct GPURenderPassEncoder { id: uint32; }
export struct GPUComputePassEncoder { id: uint32; }

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
	STORAGE = 0x80,
	INDIRECT = 0x100,
}

export enum GPUMapMode {
	READ = 0x1,
	WRITE = 0x2,
}

export enum GPUTextureUsage {
	COPY_SRC = 0x1,
	COPY_DST = 0x2,
	TEXTURE_BINDING = 0x4,
	STORAGE_BINDING = 0x8,
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
	| "rg8unorm"
	| "rgba8unorm"
	| "rgba8unorm-srgb"
	| "bgra8unorm"
	| "bgra8unorm-srgb"
	| "rgba8uint"
	| "rgba8sint"
	| "r16float"
	| "rg16float"
	| "rgba16float"
	| "rgba16uint"
	| "r32float"
	| "rg32float"
	| "rgba32float"
	| "r32uint"
	| "rgb10a2unorm"
	| "rg11b10ufloat"
	| "depth16unorm"
	| "depth32float"
	| "depth24plus-stencil8";
export type GPUTextureSampleType = "float" | "unfilterable-float" | "depth" | "sint" | "uint";
export type GPUSamplerBindingType = "filtering" | "non-filtering" | "comparison";
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
export type GPUPrimitiveTopology = "point-list" | "line-list" | "line-strip" | "triangle-list" | "triangle-strip";
export type GPUStencilOperation =
	| "keep"
	| "zero"
	| "replace"
	| "invert"
	| "increment-clamp"
	| "decrement-clamp"
	| "increment-wrap"
	| "decrement-wrap";
export type GPUTextureDimension = "2d" | "3d";
export type GPUTextureViewDimension = "2d" | "2d-array" | "cube" | "cube-array" | "3d";
export type GPUMipmapFilterMode = "nearest" | "linear";
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
	| "src-alpha-saturated"
	| "constant"
	| "one-minus-constant";
export type GPUBlendOperation = "add" | "subtract" | "reverse-subtract" | "min" | "max";
export type GPUVertexFormat =
	| "uint8x2"
	| "uint8x4"
	| "sint8x2"
	| "sint8x4"
	| "unorm8x2"
	| "unorm8x4"
	| "snorm8x2"
	| "snorm8x4"
	| "uint16x2"
	| "uint16x4"
	| "sint16x2"
	| "sint16x4"
	| "unorm16x2"
	| "unorm16x4"
	| "snorm16x2"
	| "snorm16x4"
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
export type GPUVertexStepMode = "vertex" | "instance";
export type GPUFilterMode = "nearest" | "linear";
export type GPUAddressMode = "clamp-to-edge" | "repeat" | "mirror-repeat";
export type GPUBackend = "d3d11" | "metal" | "glcore" | "gles3" | "webgpu";

export function vertexFormatSize(format: GPUVertexFormat): int32 {
	return match (format) {
		"uint8x2" | "sint8x2" | "unorm8x2" | "snorm8x2" => 2,
		"uint8x4" | "sint8x4" | "unorm8x4" | "snorm8x4" => 4,
		"uint16x2" | "sint16x2" | "unorm16x2" | "snorm16x2" | "float16x2" => 4,
		"uint16x4" | "sint16x4" | "unorm16x4" | "snorm16x4" | "float16x4" => 8,
		"float32" | "uint32" | "sint32" => 4,
		"float32x2" | "uint32x2" | "sint32x2" => 8,
		"float32x3" | "uint32x3" | "sint32x3" => 12,
		"float32x4" | "uint32x4" | "sint32x4" => 16,
	};
}

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
	dimension: GPUTextureDimension;
	mipLevelCount: int32;
}

export struct GPUTextureViewDescriptor {
	label: string | null;
	dimension: GPUTextureViewDimension;
	baseMipLevel: int32;
	mipLevelCount: int32;
	baseArrayLayer: int32;
	arrayLayerCount: int32;
}

export struct GPUSamplerDescriptor {
	label: string | null;
	addressModeU: GPUAddressMode;
	addressModeV: GPUAddressMode;
	addressModeW: GPUAddressMode;
	magFilter: GPUFilterMode;
	minFilter: GPUFilterMode;
	mipmapFilter: GPUMipmapFilterMode;
	lodMinClamp: number;
	lodMaxClamp: number;
	compare: GPUCompareFunction;
	maxAnisotropy: int32;
}

// A shader module carries one stage's source per entry, compiled for the backend this build
// targets, and the reflection that maps a WebGPU binding to the backend's register or name.
export type GPUShaderBindingKind = "uniform" | "texture" | "sampler" | "storage-buffer" | "storage-texture";
export type GPUShaderStage = "vertex" | "fragment" | "compute";
export type GPUBufferBindingType = "uniform" | "storage" | "read-only-storage";
export type GPUStorageTextureAccess = "write-only" | "read-only" | "read-write";

export struct GPUShaderBinding {
	group: int32;
	binding: int32;
	kind: GPUShaderBindingKind;
	stage: GPUShaderStage;
	size: int32;
	sampleType: GPUTextureSampleType;
	samplerType: GPUSamplerBindingType;
	bufferType: GPUBufferBindingType;
	viewDimension: GPUTextureViewDimension;
	multisampled: boolean;
	storageAccess: GPUStorageTextureAccess;
	storageFormat: GPUTextureFormat;
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
	computeCode: string;
	computeEntryPoint: string;
	workgroupSize: int32[3];
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
	stripIndexFormat: GPUIndexFormat;
	frontFace: GPUFrontFace;
	cullMode: GPUCullMode;
}

export struct GPUStencilFaceState {
	compare: GPUCompareFunction;
	failOp: GPUStencilOperation;
	depthFailOp: GPUStencilOperation;
	passOp: GPUStencilOperation;
}

export struct GPUDepthStencilState {
	format: GPUTextureFormat;
	depthWriteEnabled: boolean;
	depthCompare: GPUCompareFunction;
	stencilFront: GPUStencilFaceState;
	stencilBack: GPUStencilFaceState;
	stencilReadMask: uint32;
	stencilWriteMask: uint32;
	depthBias: int32;
	depthBiasSlopeScale: number;
	depthBiasClamp: number;
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

export struct GPUProgrammableStage {
	module: GPUShaderModule;
	entryPoint: string;
}

export struct GPUComputePipelineDescriptor {
	label: string | null;
	compute: GPUProgrammableStage;
}

export struct GPUComputePassDescriptor { label: string | null; }

export struct GPUBindGroupEntry {
	binding: int32;
	buffer: GPUBuffer;
	offset: int64;
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

export struct GPUOrigin3D { x: int32; y: int32; z: int32; }
export struct GPUTexelCopyTextureInfo { texture: GPUTexture; mipLevel: int32; origin: GPUOrigin3D; }
export struct GPUTexelCopyBufferLayout { offset: int64; bytesPerRow: int32; rowsPerImage: int32; }
export struct GPUTexelCopyBufferInfo { buffer: GPUBuffer; offset: int64; bytesPerRow: int32; rowsPerImage: int32; }

function stop(message: string): void {
	console.log(`webgpu: ${message}`);
	unreachable;
}

function stopOn(backend: string, message: string): void {
	console.log(`webgpu ${backend}: ${message}`);
	unreachable;
}

export function stopOnUnportedShaderModule(backend: string, descriptor: GPUShaderModuleDescriptor): void {
	if (descriptor.computeCode != "") { stopOn(backend, `GPUShaderModuleDescriptor.computeCode is not ported to ${backend} yet`); }
	for (let i = 0; i < 24; i++) {
		const kind: string = descriptor.bindings[i].kind;
		if (kind == "storage-buffer" || kind == "storage-texture") {
			stopOn(backend, `GPUShaderBinding.kind '${kind}' is not ported to ${backend} yet`);
		}
		const stage: string = descriptor.bindings[i].stage;
		if (stage == "compute") { stopOn(backend, `GPUShaderBinding.stage 'compute' is not ported to ${backend} yet`); }
	}
	stopOnUnportedShaderBindings(backend, descriptor);
	if (backend == "gl") { return; }
	for (let i = 0; i < 24; i++) {
		const viewDimension: string = descriptor.bindings[i].viewDimension;
		if (viewDimension != "" && viewDimension != "2d") {
			stopOn(backend, `GPUShaderBinding.viewDimension '${viewDimension}' is not ported to ${backend} yet`);
		}
	}
}

export function stopOnUnportedShaderBindings(backend: string, descriptor: GPUShaderModuleDescriptor): void {
	for (let i = 0; i < 24; i++) {
		const b = descriptor.bindings[i];
		const sampleType: string = b.sampleType;
		if (sampleType != "" && sampleType != "float" && sampleType != "unfilterable-float") {
			stopOn(backend, `GPUShaderBinding.sampleType '${sampleType}' is not ported to ${backend} yet`);
		}
		const samplerType: string = b.samplerType;
		if (samplerType == "comparison") { stopOn(backend, `GPUShaderBinding.samplerType 'comparison' is not ported to ${backend} yet`); }
		if (b.multisampled) { stopOn(backend, `GPUShaderBinding.multisampled is not ported to ${backend} yet`); }
	}
}

const STENCIL_MASK_ALL: uint32 = 0xFFFFFFFF;

// A backend that has not ported a descriptor member calls the helper for its descriptor: a member
// at WebGPU's default passes, any other value stops naming the member, the value and the backend.
export function stopOnUnportedTexture(backend: string, descriptor: GPUTextureDescriptor): void {
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d") { stopOn(backend, `GPUTextureDescriptor.dimension '${dimension}' is not ported to ${backend} yet`); }
	if (descriptor.size.depthOrArrayLayers > 1) {
		stopOn(backend, `GPUTextureDescriptor.size.depthOrArrayLayers ${descriptor.size.depthOrArrayLayers} is not ported to ${backend} yet`);
	}
	if (descriptor.mipLevelCount > 1) {
		stopOn(backend, `GPUTextureDescriptor.mipLevelCount ${descriptor.mipLevelCount} is not ported to ${backend} yet`);
	}
}

export function stopOnUnportedView(backend: string, descriptor: GPUTextureViewDescriptor): void {
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d") { stopOn(backend, `GPUTextureViewDescriptor.dimension '${dimension}' is not ported to ${backend} yet`); }
	if (descriptor.baseMipLevel != 0) { stopOn(backend, `GPUTextureViewDescriptor.baseMipLevel ${descriptor.baseMipLevel} is not ported to ${backend} yet`); }
	if (descriptor.mipLevelCount > 1) { stopOn(backend, `GPUTextureViewDescriptor.mipLevelCount ${descriptor.mipLevelCount} is not ported to ${backend} yet`); }
	if (descriptor.baseArrayLayer != 0) { stopOn(backend, `GPUTextureViewDescriptor.baseArrayLayer ${descriptor.baseArrayLayer} is not ported to ${backend} yet`); }
	if (descriptor.arrayLayerCount > 1) { stopOn(backend, `GPUTextureViewDescriptor.arrayLayerCount ${descriptor.arrayLayerCount} is not ported to ${backend} yet`); }
}

export function stopOnUnportedSampler(backend: string, descriptor: GPUSamplerDescriptor): void {
	const addressModeW: string = descriptor.addressModeW;
	if (addressModeW != "" && addressModeW != "clamp-to-edge") {
		stopOn(backend, `GPUSamplerDescriptor.addressModeW '${addressModeW}' is not ported to ${backend} yet`);
	}
	const mipmapFilter: string = descriptor.mipmapFilter;
	if (mipmapFilter != "" && mipmapFilter != "nearest") {
		stopOn(backend, `GPUSamplerDescriptor.mipmapFilter '${mipmapFilter}' is not ported to ${backend} yet`);
	}
	if (descriptor.lodMinClamp != 0) { stopOn(backend, `GPUSamplerDescriptor.lodMinClamp ${descriptor.lodMinClamp} is not ported to ${backend} yet`); }
	if (descriptor.lodMaxClamp != 0 && descriptor.lodMaxClamp != 32) {
		stopOn(backend, `GPUSamplerDescriptor.lodMaxClamp ${descriptor.lodMaxClamp} is not ported to ${backend} yet`);
	}
	const compare: string = descriptor.compare;
	if (compare != "") { stopOn(backend, `GPUSamplerDescriptor.compare '${compare}' is not ported to ${backend} yet`); }
	if (descriptor.maxAnisotropy > 1) {
		stopOn(backend, `GPUSamplerDescriptor.maxAnisotropy ${descriptor.maxAnisotropy} is not ported to ${backend} yet`);
	}
}

function stopOnUnportedStencilFace(backend: string, member: string, face: GPUStencilFaceState): void {
	const compare: string = face.compare;
	if (compare != "" && compare != "always") { stopOn(backend, `${member}.compare '${compare}' is not ported to ${backend} yet`); }
	const failOp: string = face.failOp;
	if (failOp != "" && failOp != "keep") { stopOn(backend, `${member}.failOp '${failOp}' is not ported to ${backend} yet`); }
	const depthFailOp: string = face.depthFailOp;
	if (depthFailOp != "" && depthFailOp != "keep") { stopOn(backend, `${member}.depthFailOp '${depthFailOp}' is not ported to ${backend} yet`); }
	const passOp: string = face.passOp;
	if (passOp != "" && passOp != "keep") { stopOn(backend, `${member}.passOp '${passOp}' is not ported to ${backend} yet`); }
}

export function stopOnUnportedDepthStencil(backend: string, state: GPUDepthStencilState): void {
	stopOnUnportedStencilFace(backend, "depthStencil.stencilFront", state.stencilFront);
	stopOnUnportedStencilFace(backend, "depthStencil.stencilBack", state.stencilBack);
	if (state.stencilReadMask != 0 && state.stencilReadMask != STENCIL_MASK_ALL) {
		stopOn(backend, `depthStencil.stencilReadMask ${state.stencilReadMask} is not ported to ${backend} yet`);
	}
	if (state.stencilWriteMask != 0 && state.stencilWriteMask != STENCIL_MASK_ALL) {
		stopOn(backend, `depthStencil.stencilWriteMask ${state.stencilWriteMask} is not ported to ${backend} yet`);
	}
	if (state.depthBias != 0) { stopOn(backend, `depthStencil.depthBias ${state.depthBias} is not ported to ${backend} yet`); }
	if (state.depthBiasSlopeScale != 0) {
		stopOn(backend, `depthStencil.depthBiasSlopeScale ${state.depthBiasSlopeScale} is not ported to ${backend} yet`);
	}
	if (state.depthBiasClamp != 0) { stopOn(backend, `depthStencil.depthBiasClamp ${state.depthBiasClamp} is not ported to ${backend} yet`); }
}

export function stopOnUnportedPrimitive(backend: string, state: GPUPrimitiveState): void {
	const topology: string = state.topology;
	if (topology != "" && topology != "triangle-list") { stopOn(backend, `primitive.topology '${topology}' is not ported to ${backend} yet`); }
	const stripIndexFormat: string = state.stripIndexFormat;
	if (stripIndexFormat != "") { stopOn(backend, `primitive.stripIndexFormat '${stripIndexFormat}' is not ported to ${backend} yet`); }
}

export function stopOnUnportedBindEntry(backend: string, entry: GPUBindGroupEntry): void {
	if (entry.offset != 0) { stopOn(backend, `bind group entry ${entry.binding} offset ${entry.offset} is not ported to ${backend} yet`); }
}

export function stopOnUnportedTexelWrite(backend: string, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	if (destination.mipLevel != 0) {
		stopOn(backend, `writeTexture destination.mipLevel ${destination.mipLevel} is not ported to ${backend} yet`);
	}
	if (destination.origin.z != 0 || size.depthOrArrayLayers != 1) {
		stopOn(backend, `writeTexture origin.z ${destination.origin.z} / size.depthOrArrayLayers ${size.depthOrArrayLayers} is not ported to ${backend} yet`);
	}
}

// `width` and `height` are the texture's mip 0; the validator derives the destination mip's size.
export function checkedTexelWritePitch(
	width: int32,
	height: int32,
	mipLevelCount: int32,
	arrayLayers: int32,
	bytesPerPixel: int32,
	dataBytes: int64,
	destination: GPUTexelCopyTextureInfo,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): int32 {
	const id = destination.texture.id;
	const origin = destination.origin;
	const mip = destination.mipLevel;
	if (mip < 0 || mip >= mipLevelCount) { stop(`writeTexture destination.mipLevel ${mip} of GPUTexture ${id}, which has ${mipLevelCount} mips`); }
	const mipWidth = Math.max(1, width >> mip);
	const mipHeight = Math.max(1, height >> mip);
	if (origin.z < 0 || size.depthOrArrayLayers <= 0 || origin.z + size.depthOrArrayLayers > arrayLayers) {
		stop(`writeTexture origin.z ${origin.z} / size.depthOrArrayLayers ${size.depthOrArrayLayers} overruns GPUTexture ${id}, which has ${arrayLayers} layers`);
	}
	if (size.width <= 0 || size.height <= 0) { stop(`writeTexture size ${size.width}x${size.height} needs a positive width and height`); }
	if (origin.x < 0 || origin.y < 0 || origin.x + size.width > mipWidth || origin.y + size.height > mipHeight) {
		stop(`writeTexture of ${size.width}x${size.height} at origin ${origin.x},${origin.y} overruns mip ${mip} of GPUTexture ${id}, ${mipWidth}x${mipHeight}`);
	}
	const rowBytes = size.width * bytesPerPixel;
	const bytesPerRow = layout.bytesPerRow == 0 ? rowBytes : layout.bytesPerRow;
	if (bytesPerRow < rowBytes) { stop(`writeTexture bytesPerRow ${bytesPerRow} is below a row of ${rowBytes}`); }
	if (bytesPerRow % bytesPerPixel != 0) {
		stop(`writeTexture bytesPerRow ${bytesPerRow} is not a whole number of ${bytesPerPixel}-byte texels`);
	}
	if (size.depthOrArrayLayers > 1 && layout.rowsPerImage < size.height) {
		stop(`writeTexture rowsPerImage ${layout.rowsPerImage} is below the copy height ${size.height} of ${size.depthOrArrayLayers} images`);
	}
	const imageBytes = (bytesPerRow as int64) * (layout.rowsPerImage as int64);
	const needed = layout.offset + imageBytes * ((size.depthOrArrayLayers - 1) as int64)
		+ (bytesPerRow as int64) * ((size.height - 1) as int64) + (rowBytes as int64);
	if (layout.offset < 0 || needed > dataBytes) {
		stop(`writeTexture needs ${needed} bytes of data and was given ${dataBytes}`);
	}
	return bytesPerRow;
}

export function checkedBufferCopy(
	sourceId: uint32,
	sourceSize: int64,
	sourceOffset: int64,
	destinationId: uint32,
	destinationSize: int64,
	destinationOffset: int64,
	size: int64,
): void {
	if (size < 0 || size % 4 != 0) { stop(`copyBufferToBuffer size ${size} is not a non-negative multiple of 4`); }
	if (sourceOffset < 0 || sourceOffset % 4 != 0) { stop(`copyBufferToBuffer sourceOffset ${sourceOffset} is not a non-negative multiple of 4`); }
	if (destinationOffset < 0 || destinationOffset % 4 != 0) {
		stop(`copyBufferToBuffer destinationOffset ${destinationOffset} is not a non-negative multiple of 4`);
	}
	if (sourceOffset + size > sourceSize) {
		stop(`copyBufferToBuffer of ${size} bytes at sourceOffset ${sourceOffset} overruns GPUBuffer ${sourceId} of ${sourceSize}`);
	}
	if (destinationOffset + size > destinationSize) {
		stop(`copyBufferToBuffer of ${size} bytes at destinationOffset ${destinationOffset} overruns GPUBuffer ${destinationId} of ${destinationSize}`);
	}
	if (sourceId == destinationId && sourceOffset < destinationOffset + size && destinationOffset < sourceOffset + size) {
		stop(`copyBufferToBuffer ranges overlap inside GPUBuffer ${sourceId}`);
	}
}

// A size of 0 means the rest of the buffer, as WebGPU's omitted size does.
export function checkedMapRange(member: string, id: uint32, bufferSize: int64, offset: int64, size: int64): int64 {
	if (offset < 0 || offset % 8 != 0) { stop(`${member} offset ${offset} of GPUBuffer ${id} is not a non-negative multiple of 8`); }
	const length = size == 0 ? bufferSize - offset : size;
	if (length <= 0 || length % 4 != 0) { stop(`${member} size ${length} of GPUBuffer ${id} is not a positive multiple of 4`); }
	if (offset + length > bufferSize) { stop(`${member} of ${length} bytes at ${offset} overruns GPUBuffer ${id} of ${bufferSize}`); }
	return length;
}

// `width`/`height` are mip 0; `arrayLayers` is the layer count of a 2d texture and the depth of a 3d one.
export function checkedTexelCopyRegion(
	member: string,
	id: uint32,
	width: int32,
	height: int32,
	mipLevelCount: int32,
	arrayLayers: int32,
	volume: boolean,
	info: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
): void {
	const origin = info.origin;
	const mip = info.mipLevel;
	if (mip < 0 || mip >= mipLevelCount) { stop(`${member}.mipLevel ${mip} of GPUTexture ${id}, which has ${mipLevelCount} mips`); }
	const mipWidth = Math.max(1, width >> mip);
	const mipHeight = Math.max(1, height >> mip);
	const depth = volume ? Math.max(1, arrayLayers >> mip) : arrayLayers;
	if (origin.z < 0 || size.depthOrArrayLayers <= 0 || origin.z + size.depthOrArrayLayers > depth) {
		stop(`${member} origin.z ${origin.z} / size.depthOrArrayLayers ${size.depthOrArrayLayers} overruns GPUTexture ${id}, which has ${depth} layers at mip ${mip}`);
	}
	if (size.width <= 0 || size.height <= 0) { stop(`${member} size ${size.width}x${size.height} needs a positive width and height`); }
	if (origin.x < 0 || origin.y < 0 || origin.x + size.width > mipWidth || origin.y + size.height > mipHeight) {
		stop(`${member} of ${size.width}x${size.height} at origin ${origin.x},${origin.y} overruns mip ${mip} of GPUTexture ${id}, ${mipWidth}x${mipHeight}`);
	}
}

// The buffer side of a texture<->buffer copy; returns the effective bytesPerRow.
export function checkedTexelBufferLayout(
	member: string,
	bytesPerPixel: int32,
	bufferSize: int64,
	info: GPUTexelCopyBufferInfo,
	size: GPUExtent3D,
): int32 {
	const id = info.buffer.id;
	const rowBytes = size.width * bytesPerPixel;
	if (info.bytesPerRow != 0 && info.bytesPerRow % 256 != 0) {
		stop(`${member}.bytesPerRow ${info.bytesPerRow} is not a multiple of 256`);
	}
	if ((size.height > 1 || size.depthOrArrayLayers > 1) && info.bytesPerRow == 0) {
		stop(`${member}.bytesPerRow is required when the copy spans more than one row`);
	}
	const bytesPerRow = info.bytesPerRow == 0 ? rowBytes : info.bytesPerRow;
	if (bytesPerRow < rowBytes) { stop(`${member}.bytesPerRow ${bytesPerRow} is below a row of ${rowBytes}`); }
	if (info.offset < 0 || info.offset % bytesPerPixel != 0) {
		stop(`${member}.offset ${info.offset} is not a non-negative multiple of the ${bytesPerPixel}-byte texel`);
	}
	if (info.rowsPerImage != 0 && info.rowsPerImage < size.height) {
		stop(`${member}.rowsPerImage ${info.rowsPerImage} is below the copy height ${size.height}`);
	}
	if (size.depthOrArrayLayers > 1 && info.rowsPerImage == 0) {
		stop(`${member}.rowsPerImage is required when the copy spans more than one image`);
	}
	const rowsPerImage = info.rowsPerImage == 0 ? size.height : info.rowsPerImage;
	const needed = info.offset + (bytesPerRow as int64) * (rowsPerImage as int64) * ((size.depthOrArrayLayers - 1) as int64)
		+ (bytesPerRow as int64) * ((size.height - 1) as int64) + (rowBytes as int64);
	if (needed > bufferSize) { stop(`${member} needs ${needed} bytes and GPUBuffer ${id} has ${bufferSize}`); }
	return bytesPerRow;
}

// What sokol's sg_query_features/limits/stats answered for Void (inventory E).
export struct GPUAdapterInfo {
	backend: GPUBackend;
	originTopLeft: boolean;
	depthZeroToOne: boolean;
}

// The swapchain the platform hands over at setup: WebGPU's canvas configuration, with the depth
// attachment and sample count Void's window adds (sokol's sg_environment defaults).
export struct GPUCanvasConfiguration {
	format: GPUTextureFormat;
	depthFormat: GPUTextureFormat;
	sampleCount: int32;
}

// Void's own queries, answered from the pools as sokol's sg_query_*_state and sg_query_stats do.
export struct GPULiveCounts {
	buffers: int32;
	textures: int32;
	views: int32;
	samplers: int32;
	shaderModules: int32;
	pipelines: int32;
}
