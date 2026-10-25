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
export struct GPUQuerySet { id: uint32; }

export const GPU_MAX_COLOR_ATTACHMENTS: int32 = 4;
export const GPU_MAX_VERTEX_BUFFERS: int32 = 2;
export const GPU_MAX_VERTEX_ATTRIBUTES: int32 = 16;
export const GPU_MAX_BIND_GROUP_ENTRIES: int32 = 16;
export const GPU_MAX_UNIFORM_BLOCKS: int32 = 8;
export const GPU_MAX_SHADER_BINDINGS: int32 = 24;
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
	QUERY_RESOLVE = 0x200,
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

export enum GPUShaderStage {
	VERTEX = 0x1,
	FRAGMENT = 0x2,
	COMPUTE = 0x4,
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
	| "rgba32uint"
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
export type GPUQueryType = "occlusion" | "timestamp";
export type GPUFeatureName =
	| "timestamp-query"
	| "texture-compression-bc"
	| "texture-compression-etc2"
	| "texture-compression-astc"
	| "depth32float-stencil8"
	| "depth-clip-control"
	| "float32-filterable"
	| "float32-blendable"
	| "rg11b10ufloat-renderable"
	| "bgra8unorm-storage"
	| "indirect-first-instance"
	| "shader-f16"
	| "dual-source-blending";
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

export struct GPUColor { r: float64; g: float64; b: float64; a: float64; }
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
	lodMinClamp: float32;
	lodMaxClamp: float32;
	compare: GPUCompareFunction;
	maxAnisotropy: int32;
}

// A shader module carries one stage's source per entry, compiled for the backend this build
// targets, and the reflection that maps a WebGPU binding to the backend's register or name.
export type GPUShaderBindingKind = "uniform" | "texture" | "sampler" | "storage-buffer" | "storage-texture";
export type GPUBufferBindingType = "uniform" | "storage" | "read-only-storage";
export type GPUStorageTextureAccess = "write-only" | "read-only" | "read-write";

export const DUMMY_SAMPLER_BINDING: int32 = -1;

export struct GPUShaderBinding {
	group: int32;
	binding: int32;
	kind: GPUShaderBindingKind;
	visibility: int32;
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
	// A stage's precompiled bytes in the backend's native format (DXBC on d3d11), used instead of
	// compiling that stage's code; empty is none. A backend that compiles text stops on a non-empty one.
	vertexBytecode: Vec<uint8>;
	fragmentBytecode: Vec<uint8>;
	computeBytecode: Vec<uint8>;
	// WGSL instance_index and MSL instance_id include firstInstance but HLSL and GLSL count from 0: a draw with
	// firstInstance != 0 on a vertex stage that reads it stops instead of differing per backend.
	readsInstanceIndex: boolean;
	workgroupSize: int32[3];
	bindings: GPUShaderBinding[GPU_MAX_SHADER_BINDINGS];
	attributes: GPUShaderAttribute[GPU_MAX_VERTEX_ATTRIBUTES];
}

export struct GPUVertexAttribute {
	format: GPUVertexFormat;
	offset: int32;
	shaderLocation: int32;
}

export struct GPUVertexBufferLayout {
	arrayStride: int32;
	stepMode: GPUVertexStepMode;
	attributes: GPUVertexAttribute[GPU_MAX_VERTEX_ATTRIBUTES];
}

export struct GPUVertexState {
	module: GPUShaderModule;
	buffers: GPUVertexBufferLayout[GPU_MAX_VERTEX_BUFFERS];
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
	targets: GPUColorTargetState[GPU_MAX_COLOR_ATTACHMENTS];
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
	depthBiasSlopeScale: float32;
	depthBiasClamp: float32;
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

export const GPU_NO_QUERY_INDEX = -1;

// `querySet` 0 means no timestamps; an index of GPU_NO_QUERY_INDEX skips that end of the pass.
export struct GPUPassTimestampWrites {
	querySet: GPUQuerySet;
	beginningOfPassWriteIndex: int32;
	endOfPassWriteIndex: int32;
}

export struct GPUComputePassDescriptor {
	label: string | null;
	timestampWrites: GPUPassTimestampWrites;
}

export struct GPUQuerySetDescriptor {
	label: string | null;
	type: GPUQueryType;
	count: int32;
}

export struct GPUSupportedLimits {
	maxTextureDimension1D: int32;
	maxTextureDimension2D: int32;
	maxTextureDimension3D: int32;
	maxTextureArrayLayers: int32;
	maxBindGroups: int32;
	maxSampledTexturesPerShaderStage: int32;
	maxSamplersPerShaderStage: int32;
	maxStorageBuffersPerShaderStage: int32;
	maxStorageTexturesPerShaderStage: int32;
	maxUniformBuffersPerShaderStage: int32;
	maxUniformBufferBindingSize: int64;
	maxStorageBufferBindingSize: int64;
	maxVertexBuffers: int32;
	maxVertexAttributes: int32;
	maxColorAttachments: int32;
	maxComputeWorkgroupSizeX: int32;
	maxComputeWorkgroupSizeY: int32;
	maxComputeWorkgroupSizeZ: int32;
	maxComputeInvocationsPerWorkgroup: int32;
	maxComputeWorkgroupsPerDimension: int32;
	minUniformBufferOffsetAlignment: int32;
	minStorageBufferOffsetAlignment: int32;
}

export struct GPUSupportedFeatures { bits: uint32; }

export function featureBit(name: GPUFeatureName): uint32 {
	return match (name) {
		"timestamp-query" => 0x1,
		"texture-compression-bc" => 0x2,
		"texture-compression-etc2" => 0x4,
		"texture-compression-astc" => 0x8,
		"depth32float-stencil8" => 0x10,
		"depth-clip-control" => 0x20,
		"float32-filterable" => 0x40,
		"float32-blendable" => 0x80,
		"rg11b10ufloat-renderable" => 0x100,
		"bgra8unorm-storage" => 0x200,
		"indirect-first-instance" => 0x400,
		"shader-f16" => 0x800,
		"dual-source-blending" => 0x1000,
	};
}

export enum BindingKind {
	Uniform,
	Texture,
	Sampler,
	StorageBuffer,
	StorageTexture,
}

@noinline function stopOnMember(backend: string, member: string, value: string): int32 {
	console.log(`webgpu ${backend}: ${member} '${value}' is not supported`);
	unreachable;
}

export function bindingKind(kind: string, backend: string): BindingKind {
	return match (kind) {
		"uniform" => BindingKind.Uniform,
		"texture" => BindingKind.Texture,
		"sampler" => BindingKind.Sampler,
		"storage-buffer" => BindingKind.StorageBuffer,
		"storage-texture" => BindingKind.StorageTexture,
		_ => stopOnMember(backend, "GPUShaderBinding.kind", kind) as BindingKind,
	};
}

export function linearFilter(filter: string, member: string, backend: string): boolean {
	const value = match (filter) {
		"" | "nearest" => 0,
		"linear" => 1,
		_ => stopOnMember(backend, member, filter),
	};
	return value == 1;
}

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
	entries: GPUBindGroupEntry[GPU_MAX_BIND_GROUP_ENTRIES];
}

export struct GPURenderPassColorAttachment {
	view: GPUTextureView;
	resolveTarget: GPUTextureView;
	clearValue: GPUColor;
	loadOp: GPULoadOp;
	storeOp: GPUStoreOp;
	depthSlice: int32;
}

export struct GPURenderPassDepthStencilAttachment {
	view: GPUTextureView;
	depthClearValue: float32;
	depthLoadOp: GPULoadOp;
	depthStoreOp: GPUStoreOp;
}

export struct GPURenderPassDescriptor {
	label: string | null;
	colorAttachments: GPURenderPassColorAttachment[GPU_MAX_COLOR_ATTACHMENTS];
	depthStencilAttachment: GPURenderPassDepthStencilAttachment;
	timestampWrites: GPUPassTimestampWrites;
	occlusionQuerySet: GPUQuerySet;
}

export struct GPUOrigin3D { x: int32; y: int32; z: int32; }
export struct GPUTexelCopyTextureInfo { texture: GPUTexture; mipLevel: int32; origin: GPUOrigin3D; }
export struct GPUTexelCopyBufferLayout { offset: int64; bytesPerRow: int32; rowsPerImage: int32; }
export struct GPUTexelCopyBufferInfo { buffer: GPUBuffer; offset: int64; bytesPerRow: int32; rowsPerImage: int32; }

@noinline function stop(message: string): void {
	console.log(`webgpu: ${message}`);
	unreachable;
}

@noinline function stopOnUnported(backend: string, what: string): void {
	console.log(`webgpu ${backend}: ${what} is not ported to ${backend} yet`);
	unreachable;
}

export function firstInstanceRefusal(call: string, pipeline: string, firstInstance: int32): string {
	return `${call} with firstInstance ${firstInstance} on pipeline ${pipeline}: firstInstance must be 0 because the vertex stage reads instance_index`;
}

// A backend that has not ported a descriptor member calls the helper for its descriptor: a member
// at WebGPU's default passes, any other value stops naming the member, the value and the backend.
@noinline export function stopOnUnportedShaderBindings(backend: string, descriptor: GPUShaderModuleDescriptor): void {
	for (let i = 0; i < GPU_MAX_SHADER_BINDINGS; i++) {
		const b = descriptor.bindings[i];
		const sampleType: string = b.sampleType;
		if (sampleType != "" && sampleType != "float" && sampleType != "unfilterable-float" && sampleType != "uint" && sampleType != "sint") {
			stopOnUnported(backend, `GPUShaderBinding.sampleType '${sampleType}'`);
		}
		const samplerType: string = b.samplerType;
		if (samplerType == "comparison") { stopOnUnported(backend, `GPUShaderBinding.samplerType 'comparison'`); }
		if (b.multisampled) { stopOnUnported(backend, `GPUShaderBinding.multisampled`); }
	}
}

// A uint or sint texture cannot be filtered (WebGPU's bind group layout rule, sokol's
// VALIDATE_SHADERDESC_NONFILTERING_SAMPLER_REQUIRED), so a sampler paired with one must be non-filtering.
@noinline export function checkedIntegerTexturePairs(descriptor: GPUShaderModuleDescriptor): void {
	for (let i = 0; i < GPU_MAX_SHADER_BINDINGS; i++) {
		const sampler = descriptor.bindings[i];
		const kind: string = sampler.kind;
		const samplerType: string = sampler.samplerType;
		if (kind != "sampler" || sampler.textureBinding < 0 || samplerType == "non-filtering") { continue; }
		for (let j = 0; j < GPU_MAX_SHADER_BINDINGS; j++) {
			const texture = descriptor.bindings[j];
			const textureKind: string = texture.kind;
			const sampleType: string = texture.sampleType;
			if (textureKind == "texture" && texture.binding == sampler.textureBinding && (sampleType == "uint" || sampleType == "sint")) {
				stop(`sampler binding ${sampler.binding} is '${samplerType == "" ? "filtering" : samplerType}' but pairs with the ${sampleType} texture binding ${texture.binding}; an integer texture needs a non-filtering sampler`);
			}
		}
	}
}

@noinline export function checkedVisibility(binding: GPUShaderBinding, compute: boolean): void {
	const render = (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);
	const allowed = compute ? GPUShaderStage.COMPUTE as int32 : render;
	if (binding.visibility == 0 || (binding.visibility & ~allowed) != 0) {
		stop(`shader binding ${binding.binding} has visibility ${binding.visibility}, but a ${compute ? "compute" : "vertex and fragment"} module allows only ${allowed}`);
	}
}

@noinline export function stopOnUnportedShaderBytecode(backend: string, descriptor: GPUShaderModuleDescriptor): void {
	if (descriptor.vertexBytecode.length > 0) { stopOnUnported(backend, `GPUShaderModuleDescriptor.vertexBytecode`); }
	if (descriptor.fragmentBytecode.length > 0) { stopOnUnported(backend, `GPUShaderModuleDescriptor.fragmentBytecode`); }
	if (descriptor.computeBytecode.length > 0) { stopOnUnported(backend, `GPUShaderModuleDescriptor.computeBytecode`); }
}

// `width` and `height` are the texture's mip 0; the validator derives the destination mip's size.
@noinline export function checkedTexelWritePitch(
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

@noinline export function checkedBufferCopy(
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
@noinline export function checkedMapRange(member: string, id: uint32, bufferSize: int64, offset: int64, size: int64): int64 {
	if (offset < 0 || offset % 8 != 0) { stop(`${member} offset ${offset} of GPUBuffer ${id} is not a non-negative multiple of 8`); }
	const length = size == 0 ? bufferSize - offset : size;
	if (length <= 0 || length % 4 != 0) { stop(`${member} size ${length} of GPUBuffer ${id} is not a positive multiple of 4`); }
	if (offset + length > bufferSize) { stop(`${member} of ${length} bytes at ${offset} overruns GPUBuffer ${id} of ${bufferSize}`); }
	return length;
}

// `width`/`height` are mip 0; `arrayLayers` is the layer count of a 2d texture and the depth of a 3d one.
@noinline export function checkedTexelCopyRegion(
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

// WebGPU copies a depth aspect only whole and only for depth16unorm (both ways) and depth32float
// (out); a combined depth-stencil format needs an aspect, which GPUTexelCopyTextureInfo does not carry.
@noinline export function checkedDepthTexelCopy(
	member: string,
	id: uint32,
	format: GPUTextureFormat,
	stencil: boolean,
	writes: boolean,
	width: int32,
	height: int32,
	mipLevel: int32,
	size: GPUExtent3D,
): void {
	const name: string = format;
	if (stencil) { stop(`${member}: ${name} GPUTexture ${id} has no single copyable aspect, and GPUTexelCopyTextureInfo names none`); }
	if (writes && name == "depth32float") { stop(`${member}: depth32float GPUTexture ${id} is not a valid copy destination in WebGPU`); }
	if (size.width != Math.max(1, width >> mipLevel) || size.height != Math.max(1, height >> mipLevel)) {
		stop(`${member}: a depth GPUTexture ${id} is copied as a whole subresource in WebGPU`);
	}
}

// The buffer side of a texture<->buffer copy; returns the effective bytesPerRow.
@noinline export function checkedTexelBufferLayout(
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

// WebGPU lets a mappable buffer carry only the one copy usage that matches its map direction.
@noinline export function checkedBufferUsage(usage: int32): void {
	const mapRead = GPUBufferUsage.MAP_READ as int32;
	const mapWrite = GPUBufferUsage.MAP_WRITE as int32;
	if ((usage & mapRead) != 0 && usage != (mapRead | (GPUBufferUsage.COPY_DST as int32))) {
		stop("GPUBufferUsage MAP_READ combines only with COPY_DST");
	}
	if ((usage & mapWrite) != 0 && usage != (mapWrite | (GPUBufferUsage.COPY_SRC as int32))) {
		stop("GPUBufferUsage MAP_WRITE combines only with COPY_SRC");
	}
}

// The mip count a descriptor asks for (0 means 1), checked against the chain its largest side allows.
@noinline export function checkedMipLevelCount(descriptor: GPUTextureDescriptor, volume: boolean, layers: int32): int32 {
	const requested = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	let largest = Math.max(descriptor.size.width, descriptor.size.height);
	if (volume) { largest = Math.max(largest, layers); }
	let possible = 1;
	while ((largest >> possible) > 0) { possible += 1; }
	if (requested < 1 || requested > possible) {
		stop(`GPUTextureDescriptor.mipLevelCount ${requested} is outside 1..${possible} for a ${descriptor.size.width}x${descriptor.size.height} texture`);
	}
	return requested;
}

// `sampleCount` is already resolved (0 means 1); more than one sample is a 2d, single-mip, single-layer attachment.
@noinline export function checkedMultisample(sampleCount: int32, volume: boolean, layers: int32, mipLevels: int32, attachment: boolean): void {
	if (sampleCount > 1 && (volume || layers > 1 || mipLevels > 1)) {
		stop("WebGPU allows a multisampled texture only as a 2d texture with one mip level and one array layer");
	}
	if (sampleCount > 1 && !attachment) { stop("a multisampled texture must be a RENDER_ATTACHMENT"); }
}

// `from*` describe the source texture at mip 0; the regions are already bounds-checked by checkedTexelCopyRegion.
@noinline export function checkedTextureToTextureCopy(
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyTextureInfo,
	size: GPUExtent3D,
	fromFormat: GPUTextureFormat,
	toFormat: GPUTextureFormat,
	fromVolume: boolean,
	toVolume: boolean,
	fromDepth: boolean,
	fromWidth: int32,
	fromHeight: int32,
): void {
	const fromName: string = fromFormat;
	const toName: string = toFormat;
	if (fromName != toName) { stop(`copyTextureToTexture between formats '${fromName}' and '${toName}'`); }
	if (fromVolume != toVolume) { stop("copyTextureToTexture between a 3d and a 2d GPUTexture"); }
	const mipWidth = Math.max(1, fromWidth >> source.mipLevel);
	const mipHeight = Math.max(1, fromHeight >> source.mipLevel);
	if (fromDepth && (size.width != mipWidth || size.height != mipHeight)) {
		stop(`copyTextureToTexture of depth GPUTexture ${source.texture.id} copies a whole subresource in WebGPU`);
	}
	if (
		source.texture.id == destination.texture.id && source.mipLevel == destination.mipLevel
			&& source.origin.z < destination.origin.z + size.depthOrArrayLayers && destination.origin.z < source.origin.z + size.depthOrArrayLayers
			&& source.origin.x < destination.origin.x + size.width && destination.origin.x < source.origin.x + size.width
			&& source.origin.y < destination.origin.y + size.height && destination.origin.y < source.origin.y + size.height
	) {
		stop(`copyTextureToTexture regions overlap inside mip ${source.mipLevel} of GPUTexture ${source.texture.id}`);
	}
}

// `mapMode` is the buffer's current map (0 when unmapped); returns the byte length mapped.
@noinline export function checkedMapAsync(id: uint32, usage: int32, mapMode: int32, bufferSize: int64, mode: int32, offset: int64, size: int64): int64 {
	const read = mode == (GPUMapMode.READ as int32);
	if (!read && mode != (GPUMapMode.WRITE as int32)) { stop(`mapAsync mode ${mode} is not GPUMapMode READ or WRITE`); }
	const need = read ? GPUBufferUsage.MAP_READ as int32 : GPUBufferUsage.MAP_WRITE as int32;
	if ((usage & need) == 0) { stop(`mapAsync ${read ? "READ" : "WRITE"} on GPUBuffer ${id}, created without ${read ? "MAP_READ" : "MAP_WRITE"}`); }
	if (mapMode != 0) { stop(`mapAsync on GPUBuffer ${id}, which is already mapped`); }
	return checkedMapRange("mapAsync", id, bufferSize, offset, size);
}

// A size of 0 means the rest of the mapped range; returns the byte length.
@noinline export function checkedMappedRange(
	member: string,
	id: uint32,
	bufferSize: int64,
	currentMode: int32,
	mapOffset: int64,
	mapSize: int64,
	mode: int32,
	offset: int64,
	size: int64,
): int64 {
	if (currentMode != mode) { stop(`${member} on GPUBuffer ${id}, which is not mapped for ${mode == 1 ? "READ" : "WRITE"}`); }
	const length = checkedMapRange(member, id, bufferSize, offset, size == 0 ? mapOffset + mapSize - offset : size);
	if (offset < mapOffset || offset + length > mapOffset + mapSize) {
		stop(`${member} of ${length} bytes at ${offset} leaves the mapped range ${mapOffset}..${mapOffset + mapSize} of GPUBuffer ${id}`);
	}
	return length;
}

@noinline export function checkedUnmap(id: uint32, mapMode: int32): void {
	if (mapMode == 0) { stop(`unmap on GPUBuffer ${id}, which is not mapped`); }
}

@noinline export function checkedWriteBuffer(id: uint32, bufferSize: int64, offset: int64, bytes: int64): void {
	if (offset < 0 || offset + bytes > bufferSize) {
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${id} of ${bufferSize}`);
	}
	if ((offset & 3) != 0) { stop(`writeBuffer offset ${offset} is not a multiple of 4`); }
}

@noinline export function checkedViewMips(id: uint32, mipLevels: int32, baseMip: int32, mipCount: int32): void {
	if (baseMip < 0 || mipCount < 1 || baseMip + mipCount > mipLevels) {
		stop(`view mips ${baseMip}+${mipCount} overrun GPUTexture ${id}, which has ${mipLevels} mips`);
	}
}

// A 3d view spans the whole volume slice stack, so it names no layer range.
@noinline export function checkedView3d(baseLayer: int32, layerCount: int32): void {
	if (baseLayer != 0 || layerCount > 1) { stop("a 3d view takes no baseArrayLayer or arrayLayerCount"); }
}

// `layerCount` is resolved (a 0 count already means the rest of the layers).
@noinline export function checkedViewLayers(id: uint32, layers: int32, baseLayer: int32, layerCount: int32): void {
	if (baseLayer < 0 || layerCount < 1 || baseLayer + layerCount > layers) {
		stop(`view layers ${baseLayer}+${layerCount} overrun GPUTexture ${id}, which has ${layers} layers`);
	}
}

// `cubeCapable` is the texture's own square, TEXTURE_BINDING, multiple-of-6 test made at creation.
@noinline export function checkedCubeView(id: uint32, cubeCapable: boolean, baseLayer: int32, layerCount: int32): void {
	if (!cubeCapable) {
		stop(`a cube view needs GPUTexture ${id} created square, with TEXTURE_BINDING and a depthOrArrayLayers multiple of 6`);
	}
	if (layerCount % 6 != 0 || baseLayer % 6 != 0) { stop("a cube view takes whole cubes: baseArrayLayer and arrayLayerCount multiples of 6"); }
}

@noinline export function checkedViewport(width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	if (width < 0 || height < 0 || minDepth < 0 || maxDepth > 1 || minDepth > maxDepth) {
		stop(`setViewport ${width}x${height} depth ${minDepth}..${maxDepth} is outside WebGPU's valid range`);
	}
}

@noinline export function checkedDispatch(x: int32, y: int32, z: int32, limit: int32): void {
	if (x < 0 || y < 0 || z < 0 || x > limit || y > limit || z > limit) {
		stop(`dispatchWorkgroups ${x},${y},${z} is outside 0..${limit}`);
	}
}

// `groupBase` is the depth the open pass (or none) started at: a pass cannot pop a group it did not push.
@noinline export function checkedPopDebugGroup(groupDepth: int32, groupBase: int32): void {
	if (groupDepth <= groupBase) { stop("popDebugGroup without a matching pushDebugGroup"); }
}

// `slices` is the depth of the 3d view's mip.
@noinline export function checkedDepthSlice(attachment: int32, slice: int32, slices: int32, baseMip: int32, textureId: uint32): void {
	if (slice < 0 || slice >= slices) {
		stop(`colorAttachments[${attachment}].depthSlice ${slice} is outside the ${slices} slices of mip ${baseMip} of GPUTexture ${textureId}`);
	}
}

@noinline export function checkedNoDepthSlice(attachment: int32, slice: int32): void {
	if (slice != 0) { stop(`colorAttachments[${attachment}].depthSlice ${slice} needs a 3d view`); }
}

// A pass width of 0 means no attachment has set the extent yet.
@noinline export function checkedPassExtent(passWidth: int32, passHeight: int32, width: int32, height: int32): void {
	if (passWidth != 0 && (passWidth != width || passHeight != height)) { stop("render pass attachments differ in size"); }
}

// `member` is the attachment's field, such as `colorAttachments[0].view`.
@noinline export function checkedSingleSubresource(member: string, attachable: boolean): void {
	if (!attachable) { stop(`${member} spans several mips or layers: a render attachment is one mip of one layer`); }
}

// The sizes are the color view's and the resolve view's own mip.
@noinline export function checkedResolveTarget(
	attachment: int32,
	colorSamples: int32,
	colorWidth: int32,
	colorHeight: int32,
	resolveWidth: int32,
	resolveHeight: int32,
): void {
	if (colorSamples == 1) { stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`); }
	if (resolveWidth != colorWidth || resolveHeight != colorHeight) {
		stop(`colorAttachments[${attachment}].resolveTarget differs in size from its multisampled view`);
	}
}

@noinline export function checkedSamplerAnisotropy(maxAnisotropy: int32, allLinear: boolean): void {
	if (maxAnisotropy > 1 && !allLinear) {
		stop("GPUSamplerDescriptor.maxAnisotropy above 1 needs linear magFilter, minFilter and mipmapFilter");
	}
}

// A lodMaxClamp of 0 means WebGPU's default of 32; returns the effective maximum.
@noinline export function checkedSamplerLod(lodMinClamp: float32, lodMaxClamp: float32): float32 {
	const maxLod: float32 = lodMaxClamp == 0 ? 32.0 : lodMaxClamp;
	if (maxLod < lodMinClamp) { stop(`GPUSamplerDescriptor.lodMaxClamp ${maxLod} is below lodMinClamp ${lodMinClamp}`); }
	return maxLod;
}

@noinline export function checkedDispatchIndirect(id: uint32, usage: int32, bufferSize: int64, offset: int64): void {
	if ((usage & (GPUBufferUsage.INDIRECT as int32)) == 0) { stop(`dispatchWorkgroupsIndirect: GPUBuffer ${id} was created without INDIRECT`); }
	if (offset < 0 || offset % 4 != 0 || offset + 12 > bufferSize) {
		stop(`dispatchWorkgroupsIndirect offset ${offset} is not a multiple of 4 with 12 bytes inside GPUBuffer ${id} of ${bufferSize}`);
	}
}

@noinline export function checkedQuerySetCount(count: int32): void {
	if (count < 1 || count > 4096) { stop(`GPUQuerySetDescriptor.count ${count} is outside 1..4096`); }
}

// `count` is the query set's size; an occlusion set cannot take timestamp writes.
@noinline export function checkedTimestampWrites(member: string, writes: GPUPassTimestampWrites, timestamp: boolean, count: int32): void {
	if (!timestamp) { stop(`${member}.querySet is an occlusion set: a timestamp set is required`); }
	const begin = writes.beginningOfPassWriteIndex;
	const end = writes.endOfPassWriteIndex;
	if (begin == end) {
		stop(`${member} writes index ${begin} at both ends: give each end its own index, or -1 (GPU_NO_QUERY_INDEX) to skip one`);
	}
	if (begin < -1 || begin >= count || end < -1 || end >= count) {
		stop(`${member} indices ${begin} and ${end} are outside the query set of ${count}`);
	}
}

// Each query resolves to 8 bytes; returns that byte length.
@noinline export function checkedResolveQuerySet(
	setCount: int32,
	firstQuery: int32,
	queryCount: int32,
	destinationId: uint32,
	destinationUsage: int32,
	destinationSize: int64,
	destinationOffset: int64,
): int64 {
	if (firstQuery < 0 || queryCount < 0 || firstQuery + queryCount > setCount) {
		stop(`resolveQuerySet ${firstQuery}+${queryCount} overruns the query set of ${setCount}`);
	}
	if ((destinationUsage & (GPUBufferUsage.QUERY_RESOLVE as int32)) == 0) {
		stop(`resolveQuerySet: GPUBuffer ${destinationId} was created without QUERY_RESOLVE`);
	}
	if (destinationOffset < 0 || destinationOffset % 256 != 0) {
		stop(`resolveQuerySet destinationOffset ${destinationOffset} is not a multiple of 256`);
	}
	const bytes = (queryCount as int64) * 8;
	if (destinationOffset + bytes > destinationSize) {
		stop(`resolveQuerySet of ${bytes} bytes at ${destinationOffset} overruns GPUBuffer ${destinationId} of ${destinationSize}`);
	}
	return bytes;
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
