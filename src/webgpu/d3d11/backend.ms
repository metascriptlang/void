import "./removal";
import {
	GPU_MAX_ANISOTROPY,
	BindingKind,
	bindingKind,
	linearFilter,
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	GPUAdapterInfo,
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBindGroupLayout,
	GPUBlendComponent,
	GPUBuffer,
	GPUBufferDescriptor,
	GPUBufferUsage,
	GPUCanvasConfiguration,
	GPUCommandBuffer,
	GPUColor,
	GPUCommandEncoder,
	GPUComputePassDescriptor,
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUComputePipelineDescriptor,
	GPUDevice,
	GPUExtent3D,
	GPUIndexFormat,
	GPULiveCounts,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUPassTimestampWrites,
	GPUPrimitiveState,
	GPUQuerySet,
	GPUQuerySetDescriptor,
	GPUSamplerDescriptor,
	GPUStencilFaceState,
	GPUShaderAttribute,
	GPUShaderBinding,
	GPUShaderStage,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUSupportedFeatures,
	GPUSupportedLimits,
	GPUMapMode,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDescriptor,
	checkedBufferCopy,
	checkedDepthSlice,
	checkedDepthTexelCopy,
	checkedDispatchIndirect,
	checkedMapAsync,
	checkedMappedRange,
	checkedNoDepthSlice,
	checkedPassExtent,
	checkedResolveQuerySet,
	checkedResolveTarget,
	samplerMaxLod,
	checkedTexelBufferLayout,
	checkedTexelWritePitch,
	checkedTextureToTextureCopy,
	checkedTimestampWrites,
	checkedUnmap,
	checkedWriteBuffer,
	featureBit,
	firstInstanceRefusal,
	vertexOffsetRefusal,
	stopOnUnportedShaderBindings,
} from "../types.ms";
import {
	checkedCopyRegion,
	entryOf,
	checkedViewRange,
	cubeCapable,
	clampedAnisotropy,
	addressesBinding,
	checkedBindGroupIndex,
	checkedBindGroupSet,
	checkedComputeModule,
	checkedComputePipeline,
	checkedRenderPassPipeline,
	checkedOcclusionRange,
	checkedOcclusionReuse,
	checkedOcclusionSetKind,
	checkedRenderModule,
	checkedSampledView,
	checkedStorageEntry,
	checkedStorageView,
	checkedStripDraw,
	checkedUniformEntry,
	entryBytes,
	occlusionQueryIndex,
	occlusionSetId,
	passSerial,
} from "../validate.ms";
import { Pool, allocate, alive, live, liveIds, newPool, release, reset, slotIndex, store } from "../pool.ms";
import {
	D3dBlobImpl,
	D3dBlendStateImpl,
	D3dBufferImpl,
	D3dComputeShaderImpl,
	D3dContext1Impl,
	D3dContextImpl,
	D3dDepthStencilStateImpl,
	D3dDeviceImpl,
	D3dDsvImpl,
	D3dInputLayoutImpl,
	D3dPixelShaderImpl,
	D3dQueryImpl,
	D3dRasterizerStateImpl,
	D3dRtvImpl,
	D3dSamplerImpl,
	D3dSrvImpl,
	D3dTextureImpl,
	D3dUavImpl,
	D3dVertexShaderImpl,
	d3dBeginEvent,
	d3dClearDsv,
	d3dClearRtv,
	d3dClearState,
	d3dCompile,
	d3dBlobCopy,
	d3dBlobFree,
	d3dCompileLog,
	d3dConstantsDisagreement,
	d3dContextFrom,
	d3dCopyBuffer,
	d3dCopyBufferToTexture,
	d3dCopyBytes,
	d3dCopyTexture,
	d3dCopyTextureToBuffer,
	d3dCreateBlendState,
	d3dCreateBuffer,
	d3dCreateBufferSrv,
	d3dCreateBufferUav,
	d3dCreateComputeShader,
	d3dCreateTextureUav,
	d3dCsClearViews,
	d3dCsSetSampler,
	d3dCsSetShader,
	d3dCsSetShaderResource,
	d3dCsSetUnorderedAccessView,
	d3dDispatch,
	d3dDispatchIndirect,
	d3dCreateDepthStencilState,
	d3dCreateDsv,
	d3dCreateInputLayout,
	d3dCreatePixelShader,
	d3dCreateQuery,
	d3dCreateRasterizerState,
	d3dCreateRtv,
	d3dCreateRtv3d,
	d3dCreateSampler,
	d3dCreateSrv,
	d3dCreateTexture2D,
	d3dCreateTexture3D,
	d3dCreateVertexShader,
	d3dDeviceFrom,
	d3dEndEvent,
	d3dFormatCaps,
	d3dDraw,
	d3dDrawIndexed,
	d3dDrawIndexedInstanced,
	d3dDrawInstanced,
	d3dDsvFrom,
	d3dIaSetIndexBuffer,
	d3dIaSetInputLayout,
	d3dIaSetPrimitiveTopology,
	d3dIaSetVertexBuffer,
	d3dMapWrite,
	d3dOmSetBlendState,
	d3dOmSetDepthStencilState,
	d3dPsSetShader,
	d3dReadBuffer,
	d3dRelease,
	d3dQueryBegin,
	d3dQueryEnd,
	d3dQueryFrequency,
	d3dQuerySupported,
	d3dQueryTicks,
	d3dReleaseAnnotation,
	d3dResolveSubresource,
	d3dResolveViews,
	d3dRsSetState,
	d3dRtvFrom,
	d3dRtvTexture,
	d3dSetRenderTargets,
	d3dSetMarker,
	d3dSetName,
	d3dSetScissorRect,
	d3dSetViewport,
	d3dTextureNative,
	d3dUpdateBuffer,
	d3dUpdateIfChanged,
	d3dUpdateTexture,
	d3dUniformOffsetting,
	d3dSetConstantBuffer,
	d3dSetConstantBufferRange,
	d3dSetShaderResource,
	d3dSetSampler,
	d3dVsSetShader,
} from "./d3d11.h";

export struct NativeEnvironment {
	device: Ptr<void> | null;
	context: Ptr<void> | null;
	colorFormat: GPUTextureFormat;
	depthFormat: GPUTextureFormat;
	sampleCount: int32;
}
export struct NativeSwapchain {
	width: int32;
	height: int32;
	sampleCount: int32;
	renderView: Ptr<void> | null;
	resolveView: Ptr<void> | null;
	depthStencilView: Ptr<void> | null;
}

const UNIFORM_OFFSET_ALIGNMENT = 256;
const MAX_BLOCK_CONSTANTS = 4096;
const MAX_STAGE_CONSTANT_BUFFERS = 14;
const MAX_STAGE_SHADER_RESOURCES = 128;
const MAX_STAGE_SAMPLERS = 16;
const MAX_STAGE_UNORDERED_ACCESS_VIEWS = 8;
const INPUT_ELEMENT_INTS = 5;
const BLEND_TARGET_INTS = 9;
const MAX_DISPATCH_GROUPS = 65535;
const MAX_TEXTURE_DIMENSION_1D = 16384;
const MAX_TEXTURE_DIMENSION_2D = 16384;
const MAX_TEXTURE_DIMENSION_3D = 2048;
const MAX_TEXTURE_ARRAY_LAYERS = 2048;
const MAX_UNIFORM_BUFFER_BINDING_SIZE: int64 = 65536;
const MAX_STORAGE_BUFFER_BINDING_SIZE: int64 = 134217728;
const MAX_WORKGROUP_SIZE_X = 1024;
const MAX_WORKGROUP_SIZE_Y = 1024;
const MAX_WORKGROUP_SIZE_Z = 64;
const MAX_WORKGROUP_INVOCATIONS = 1024;
const BIND_GROUPS = GPU_RESOURCE_GROUP + 1;
const QUERY_OCCLUSION = 0;
const QUERY_TIMESTAMP = 1;
const QUERY_DISJOINT = 2;
const FORMAT_CAP_SAMPLE = 1;
const FORMAT_CAP_RENDER = 2;
const FORMAT_CAP_BLEND = 4;
const STORAGE_OFFSET_ALIGNMENT = 256;

const DXGI_UNKNOWN = 0;
const DXGI_R32G32B32A32_FLOAT = 2;
const DXGI_R32G32B32A32_UINT = 3;
const DXGI_R32G32B32A32_SINT = 4;
const DXGI_R32G32B32_FLOAT = 6;
const DXGI_R32G32B32_UINT = 7;
const DXGI_R32G32B32_SINT = 8;
const DXGI_R16G16B16A16_FLOAT = 10;
const DXGI_R16G16B16A16_UNORM = 11;
const DXGI_R16G16B16A16_UINT = 12;
const DXGI_R16G16B16A16_SNORM = 13;
const DXGI_R16G16B16A16_SINT = 14;
const DXGI_R32G32_FLOAT = 16;
const DXGI_R32G32_UINT = 17;
const DXGI_R32G32_SINT = 18;
const DXGI_R32G8X24_TYPELESS = 19;
const DXGI_D32_FLOAT_S8X24_UINT = 20;
const DXGI_R32_FLOAT_X8X24_TYPELESS = 21;
const DXGI_R10G10B10A2_UNORM = 24;
const DXGI_R11G11B10_FLOAT = 26;
const DXGI_R8G8B8A8_TYPELESS = 27;
const DXGI_R8G8B8A8_UNORM = 28;
const DXGI_R8G8B8A8_UNORM_SRGB = 29;
const DXGI_R8G8B8A8_UINT = 30;
const DXGI_R8G8B8A8_SNORM = 31;
const DXGI_R8G8B8A8_SINT = 32;
const DXGI_R16G16_FLOAT = 34;
const DXGI_R16G16_UNORM = 35;
const DXGI_R16G16_UINT = 36;
const DXGI_R16G16_SNORM = 37;
const DXGI_R16G16_SINT = 38;
const DXGI_R32_TYPELESS = 39;
const DXGI_D32_FLOAT = 40;
const DXGI_R32_FLOAT = 41;
const DXGI_R32_UINT = 42;
const DXGI_R32_SINT = 43;
const DXGI_R8G8_UNORM = 49;
const DXGI_R8G8_UINT = 50;
const DXGI_R8G8_SNORM = 51;
const DXGI_R8G8_SINT = 52;
const DXGI_R16_TYPELESS = 53;
const DXGI_R16_FLOAT = 54;
const DXGI_D16_UNORM = 55;
const DXGI_R16_UNORM = 56;
const DXGI_R16_UINT = 57;
const DXGI_R8_UNORM = 61;
const DXGI_B8G8R8A8_UNORM = 87;
const DXGI_B8G8R8A8_TYPELESS = 90;
const DXGI_B8G8R8A8_UNORM_SRGB = 91;

const USAGE_DEFAULT = 0;
const USAGE_DYNAMIC = 2;
const USAGE_STAGING = 3;
const BIND_VERTEX_BUFFER = 0x1;
const BIND_INDEX_BUFFER = 0x2;
const BIND_CONSTANT_BUFFER = 0x4;
const BIND_SHADER_RESOURCE = 0x8;
const BIND_RENDER_TARGET = 0x20;
const BIND_DEPTH_STENCIL = 0x40;
const BIND_UNORDERED_ACCESS = 0x80;
const MISC_DRAWINDIRECT_ARGS = 0x10;
const MISC_ALLOW_RAW_VIEWS = 0x20;
const CPU_ACCESS_WRITE = 0x10000;
const CPU_ACCESS_READ = 0x20000;
const MAP_WRITE = 2;
const MAP_WRITE_DISCARD = 4;
const MAP_WRITE_NO_OVERWRITE = 5;
const CLEAR_DEPTH = 0x1;
const CLEAR_STENCIL = 0x2;
const TOPOLOGY_POINT_LIST = 1;
const TOPOLOGY_LINE_LIST = 2;
const TOPOLOGY_LINE_STRIP = 3;
const TOPOLOGY_TRIANGLE_LIST = 4;
const TOPOLOGY_TRIANGLE_STRIP = 5;
const CULL_NONE = 1;
const CULL_FRONT = 2;
const CULL_BACK = 3;
const FILTER_MIP_LINEAR = 0x01;
const FILTER_MAG_LINEAR = 0x04;
const FILTER_MIN_LINEAR = 0x10;
const FILTER_COMPARISON = 0x80;
const FILTER_ANISOTROPIC = 0x55;
const COMPARISON_NEVER = 1;
const STENCIL_MASK_DEFAULT: uint32 = 0xFF;
const ADDRESS_WRAP = 1;
const ADDRESS_MIRROR = 2;
const ADDRESS_CLAMP = 3;
const BLEND_ZERO = 1;
const BLEND_ONE = 2;
const BLEND_SRC_COLOR = 3;
const BLEND_INV_SRC_COLOR = 4;
const BLEND_SRC_ALPHA = 5;
const BLEND_INV_SRC_ALPHA = 6;
const BLEND_DEST_ALPHA = 7;
const BLEND_INV_DEST_ALPHA = 8;
const BLEND_DEST_COLOR = 9;
const BLEND_INV_DEST_COLOR = 10;
const BLEND_SRC_ALPHA_SAT = 11;
const BLEND_BLEND_FACTOR = 14;
const BLEND_INV_BLEND_FACTOR = 15;
const VIEW_2D = 0;
const VIEW_2D_ARRAY = 1;
const VIEW_CUBE = 2;
const VIEW_CUBE_ARRAY = 3;
const VIEW_3D = 4;
const COLOR_WRITE_ALL = 0xF;

const NO_BUFFER = null as unknown as Ptr<D3dBufferImpl>;
const NO_TEXTURE = null as unknown as Ptr<D3dTextureImpl>;
const NO_SRV = null as unknown as Ptr<D3dSrvImpl>;
const NO_SAMPLER = null as unknown as Ptr<D3dSamplerImpl>;
const NO_RTV = null as unknown as Ptr<D3dRtvImpl>;
const NO_DSV = null as unknown as Ptr<D3dDsvImpl>;
const NO_UAV = null as unknown as Ptr<D3dUavImpl>;
const NO_QUERY = null as unknown as Ptr<D3dQueryImpl>;
const LABEL_MAX_UNITS = 255;
const LABEL_TOO_LONG = -2;

enum QueryState {
	Unwritten,
	Open,
	Written,
}

struct FormatInfo {
	texture: int32;
	shaderResource: int32;
	renderTarget: int32;
	depthStencil: int32;
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
}

struct BufferSlot {
	id: uint32;
	size: int64;
	usage: int32;
	uniform: boolean;
	storage: boolean;
	staging: boolean;
	updatable: boolean;
	mapMode: int32;
	mapOffset: int64;
	mapSize: int64;
	native: Ptr<D3dBufferImpl>;
	shadow: Vec<uint8>;
	writtenFrame: int64;
	writtenEnd: int64;
}

struct TextureSlot {
	id: uint32;
	width: int32;
	height: int32;
	format: GPUTextureFormat;
	usage: int32;
	sampleCount: int32;
	mipLevels: int32;
	layers: int32;
	volume: boolean;
	cube: boolean;
	native: Ptr<D3dTextureImpl>;
	info: FormatInfo;
	swapchainView: uint32;
}

struct ViewSlot {
	id: uint32;
	texture: uint32;
	shaderResource: Ptr<D3dSrvImpl>;
	renderTarget: Ptr<D3dRtvImpl>;
	depthStencil: Ptr<D3dDsvImpl>;
	unordered: Ptr<D3dUavImpl>;
	swapchainResolve: Ptr<D3dRtvImpl>;
	baseMip: int32;
	mipCount: int32;
	baseLayer: int32;
	volumeTarget: boolean;
	swapchain: boolean;
}

struct SamplerSlot {
	id: uint32;
	native: Ptr<D3dSamplerImpl>;
}

struct NativeBinding {
	binding: int32;
	kind: BindingKind;
	vertexStage: boolean;
	fragmentStage: boolean;
	computeStage: boolean;
	writable: boolean;
	nativeSlot: int32;
	size: int32;
}

struct ShaderSlot {
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	id: uint32;
	vertex: Ptr<D3dVertexShaderImpl>;
	fragment: Ptr<D3dPixelShaderImpl>;
	compute: Ptr<D3dComputeShaderImpl>;
	computeEntry: string;
	vertexBlob: Ptr<D3dBlobImpl>;
	uniforms: NativeBinding[GPU_MAX_UNIFORM_BLOCKS];
	uniformCount: int32;
	constantBuffers: Ptr<D3dBufferImpl>[GPU_MAX_UNIFORM_BLOCKS];
	blockCache: Vec<uint8>;
	cacheOffset: int32[GPU_MAX_UNIFORM_BLOCKS];
	cacheFresh: int32[GPU_MAX_UNIFORM_BLOCKS];
	resources: NativeBinding[GPU_MAX_BIND_GROUP_ENTRIES];
	resourceCount: int32;
	attributes: GPUShaderAttribute[GPU_MAX_VERTEX_ATTRIBUTES];
}

struct PipelineSlot {
	label: string | null;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
	id: uint32;
	shader: uint32;
	rasterizer: Ptr<D3dRasterizerStateImpl>;
	depthStencil: Ptr<D3dDepthStencilStateImpl>;
	blend: Ptr<D3dBlendStateImpl>;
	inputLayout: Ptr<D3dInputLayoutImpl>;
	strides: int32[GPU_MAX_VERTEX_BUFFERS];
	layouts: uint32[2];
	topology: int32;
	stripIndexFormat: int32;
	compute: boolean;
}

struct LayoutSlot {
	id: uint32;
	pipeline: uint32;
	group: int32;
}

struct BindGroupSlot {
	id: uint32;
	group: int32;
	entries: GPUBindGroupEntry[GPU_MAX_BIND_GROUP_ENTRIES];
	srv: Ptr<D3dSrvImpl>[GPU_MAX_BIND_GROUP_ENTRIES];
	uav: Ptr<D3dUavImpl>[GPU_MAX_BIND_GROUP_ENTRIES];
	entryCount: int32;
	dynamicIndex: int32[GPU_MAX_BIND_GROUP_ENTRIES];
	dynamicCount: int32;
}

struct QuerySetSlot {
	id: uint32;
	timestamp: boolean;
	count: int32;
	queries: Vec<Ptr<D3dQueryImpl>>;
	state: Vec<QueryState>;
	usedPass: Vec<int64>;
	disjoint: Ptr<D3dQueryImpl>;
	disjointOpen: boolean;
	frequency: uint64;
}

struct PassState {
	labeled: boolean;
	timestampSet: uint32;
	timestampEnd: int32;
	width: int32;
	height: int32;
	colorViews: uint32[GPU_MAX_COLOR_ATTACHMENTS];
	resolveViews: uint32[GPU_MAX_COLOR_ATTACHMENTS];
	sliceTargets: Ptr<D3dRtvImpl>[GPU_MAX_COLOR_ATTACHMENTS];
}

struct ComputeState {
	labeled: boolean;
	timestampSet: uint32;
	timestampEnd: int32;
	pipeline: uint32;
	bindGroup: uint32;
	dirty: boolean;
}

struct BoundState {
	pipeline: uint32;
	appliedPipeline: uint32;
	vertexBuffers: uint32[GPU_MAX_VERTEX_BUFFERS];
	vertexOffsets: int64[GPU_MAX_VERTEX_BUFFERS];
	indexBuffer: uint32;
	indexFormat: int32;
	indexOffset: int64;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[GPU_MAX_BIND_GROUP_ENTRIES];
	vertexDirty: boolean;
	indexDirty: boolean;
	resourcesDirty: boolean;
	uniformsDirty: boolean;
	uniformBuffer: uint32[GPU_MAX_UNIFORM_BLOCKS];
	uniformFirst: int64[GPU_MAX_UNIFORM_BLOCKS];
	blendConstant: GPUColor;
	stencilReference: uint32;
}

export struct BindStats {
	vertexBuffers: int64;
	indexBuffers: int64;
	shaderResources: int64;
	samplers: int64;
}

struct NativeBinds {
	vertexBuffer: Ptr<D3dBufferImpl>[GPU_MAX_VERTEX_BUFFERS];
	vertexStride: int32[GPU_MAX_VERTEX_BUFFERS];
	vertexOffset: int32[GPU_MAX_VERTEX_BUFFERS];
	indexBuffer: Ptr<D3dBufferImpl>;
	indexFormat: int32;
	indexOffset: int32;
	shaderResource: Ptr<D3dSrvImpl>[256];
	sampler: Ptr<D3dSamplerImpl>[32];
}

let device: Ptr<D3dDeviceImpl> = null as unknown as Ptr<D3dDeviceImpl>;
let context: Ptr<D3dContextImpl> = null as unknown as Ptr<D3dContextImpl>;
let context1: Ptr<D3dContext1Impl> = null as unknown as Ptr<D3dContext1Impl>;
let offsetUniforms = false;
let frame: int64 = 0;
let pass: PassState = { width: 0 };
let bound: BoundState = { pipeline: 0 };
let computeBound: ComputeState = { pipeline: 0 };
let nativeBinds: NativeBinds = { indexFormat: 0 };
let stats: BindStats = { vertexBuffers: 0 };
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "bgra8unorm", depthFormat: "depth32float", sampleCount: 1 };


let buffers: Pool<BufferSlot> = newPool<BufferSlot>("d3d11", "GPUBuffer", "buffer", { id: 0 });
let textures: Pool<TextureSlot> = newPool<TextureSlot>("d3d11", "GPUTexture", "texture", { id: 0 });
let views: Pool<ViewSlot> = newPool<ViewSlot>("d3d11", "GPUTextureView", "view", { id: 0 });
let samplers: Pool<SamplerSlot> = newPool<SamplerSlot>("d3d11", "GPUSampler", "sampler", { id: 0 });
let shaders: Pool<ShaderSlot> = newPool<ShaderSlot>("d3d11", "GPUShaderModule", "shader module", { id: 0 });
let pipelines: Pool<PipelineSlot> = newPool<PipelineSlot>("d3d11", "GPURenderPipeline", "render or compute pipeline", { id: 0 });
let layouts: Pool<LayoutSlot> = newPool<LayoutSlot>("d3d11", "GPUBindGroupLayout", "bind group layout", { id: 0 });
let querySets: Pool<QuerySetSlot> = newPool<QuerySetSlot>("d3d11", "GPUQuerySet", "query set", { id: 0 });
let bindGroups: Pool<BindGroupSlot> = newPool<BindGroupSlot>("d3d11", "GPUBindGroup", "bind group", { id: 0 });

@noinline function stop(message: string): never {
	console.log(`webgpu d3d11: ${message}`);
	unreachable;
}

@noinline function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu d3d11: ${member} '${value}' is not supported`);
	unreachable;
}

@noinline function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu d3d11: ${member} '${value}' is not supported`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

@inline function roundUp16(bytes: int64): int64 { return (bytes + 15) & ~(15 as int64); }

@inline function roundUp256(bytes: int64): int64 { return (bytes + 255) & ~(255 as int64); }

export function bindStats(): BindStats { return stats; }

function forgetAppliedUniforms(): void {
	for (let u = 0; u < GPU_MAX_UNIFORM_BLOCKS; u++) { bound.uniformBuffer[u] = 0; }
}

function colorInfo(format: int32, bytesPerPixel: int32): FormatInfo {
	return {
		texture: format,
		shaderResource: format,
		renderTarget: format,
		depthStencil: DXGI_UNKNOWN,
		bytesPerPixel: bytesPerPixel,
		depth: false,
		stencil: false,
	};
}

function srgbInfo(typeless: int32, format: int32): FormatInfo {
	return {
		texture: typeless,
		shaderResource: format,
		renderTarget: format,
		depthStencil: DXGI_UNKNOWN,
		bytesPerPixel: 4,
		depth: false,
		stencil: false,
	};
}

function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const value: string = format;
	return match (value) {
		"r8unorm" => colorInfo(DXGI_R8_UNORM, 1),
		"rg8unorm" => colorInfo(DXGI_R8G8_UNORM, 2),
		"rgba8unorm" => colorInfo(DXGI_R8G8B8A8_UNORM, 4),
		"rgba8unorm-srgb" => srgbInfo(DXGI_R8G8B8A8_TYPELESS, DXGI_R8G8B8A8_UNORM_SRGB),
		"bgra8unorm" => colorInfo(DXGI_B8G8R8A8_UNORM, 4),
		"bgra8unorm-srgb" => srgbInfo(DXGI_B8G8R8A8_TYPELESS, DXGI_B8G8R8A8_UNORM_SRGB),
		"rgba8uint" => colorInfo(DXGI_R8G8B8A8_UINT, 4),
		"rgba8sint" => colorInfo(DXGI_R8G8B8A8_SINT, 4),
		"r16float" => colorInfo(DXGI_R16_FLOAT, 2),
		"rg16float" => colorInfo(DXGI_R16G16_FLOAT, 4),
		"rgba16float" => colorInfo(DXGI_R16G16B16A16_FLOAT, 8),
		"rgba16uint" => colorInfo(DXGI_R16G16B16A16_UINT, 8),
		"r32float" => colorInfo(DXGI_R32_FLOAT, 4),
		"rg32float" => colorInfo(DXGI_R32G32_FLOAT, 8),
		"rgba32float" => colorInfo(DXGI_R32G32B32A32_FLOAT, 16),
		"rgba32uint" => colorInfo(DXGI_R32G32B32A32_UINT, 16),
		"r32uint" => colorInfo(DXGI_R32_UINT, 4),
		"rgb10a2unorm" => colorInfo(DXGI_R10G10B10A2_UNORM, 4),
		"rg11b10ufloat" => colorInfo(DXGI_R11G11B10_FLOAT, 4),
		"depth16unorm" => ({
			texture: DXGI_R16_TYPELESS,
			shaderResource: DXGI_R16_UNORM,
			renderTarget: DXGI_R16_UNORM,
			depthStencil: DXGI_D16_UNORM,
			bytesPerPixel: 2,
			depth: true,
			stencil: false,
		}),
		"depth32float" => ({
			texture: DXGI_R32_TYPELESS,
			shaderResource: DXGI_R32_FLOAT,
			renderTarget: DXGI_R32_FLOAT,
			depthStencil: DXGI_D32_FLOAT,
			bytesPerPixel: 4,
			depth: true,
			stencil: false,
		}),
		"depth24plus-stencil8" => ({
			texture: DXGI_R32G8X24_TYPELESS,
			shaderResource: DXGI_R32_FLOAT_X8X24_TYPELESS,
			renderTarget: DXGI_R32_FLOAT_X8X24_TYPELESS,
			depthStencil: DXGI_D32_FLOAT_S8X24_UINT,
			bytesPerPixel: 8,
			depth: true,
			stencil: true,
		}),
		_ => stopOnFormat(member, value),
	};
}

function compareFunction(compare: string, member: string): int32 {
	return match (compare) {
		"never" => 1,
		"less" => 2,
		"equal" => 3,
		"less-equal" => 4,
		"greater" => 5,
		"not-equal" => 6,
		"greater-equal" => 7,
		"" | "always" => 8,
		_ => stopOnMember(member, compare),
	};
}

function cullMode(cull: string): int32 {
	return match (cull) {
		"" | "none" => CULL_NONE,
		"front" => CULL_FRONT,
		"back" => CULL_BACK,
		_ => stopOnMember("primitive.cullMode", cull),
	};
}

function frontCounterClockwise(face: string): int32 {
	return match (face) {
		"" | "ccw" => 1,
		"cw" => 0,
		_ => stopOnMember("primitive.frontFace", face),
	};
}

function blendFactor(factor: string, alpha: boolean, member: string): int32 {
	return match (factor) {
		"zero" => BLEND_ZERO,
		"" | "one" => BLEND_ONE,
		"src" => alpha ? BLEND_SRC_ALPHA : BLEND_SRC_COLOR,
		"one-minus-src" => alpha ? BLEND_INV_SRC_ALPHA : BLEND_INV_SRC_COLOR,
		"src-alpha" => BLEND_SRC_ALPHA,
		"one-minus-src-alpha" => BLEND_INV_SRC_ALPHA,
		"dst" => alpha ? BLEND_DEST_ALPHA : BLEND_DEST_COLOR,
		"one-minus-dst" => alpha ? BLEND_INV_DEST_ALPHA : BLEND_INV_DEST_COLOR,
		"dst-alpha" => BLEND_DEST_ALPHA,
		"one-minus-dst-alpha" => BLEND_INV_DEST_ALPHA,
		"src-alpha-saturated" => BLEND_SRC_ALPHA_SAT,
		"constant" => BLEND_BLEND_FACTOR,
		"one-minus-constant" => BLEND_INV_BLEND_FACTOR,
		_ => stopOnMember(member, factor),
	};
}

function destinationFactor(factor: string, alpha: boolean, member: string): int32 {
	const value: string = factor;
	if (value == "") { return BLEND_ZERO; }
	return blendFactor(value, alpha, member);
}

function blendOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "add" => 1,
		"subtract" => 2,
		"reverse-subtract" => 3,
		"min" => 4,
		"max" => 5,
		_ => stopOnMember(member, operation),
	};
}

function vertexFormat(format: string): int32 {
	return match (format) {
		"float32" => DXGI_R32_FLOAT,
		"float32x2" => DXGI_R32G32_FLOAT,
		"float32x3" => DXGI_R32G32B32_FLOAT,
		"float32x4" => DXGI_R32G32B32A32_FLOAT,
		"uint32" => DXGI_R32_UINT,
		"uint32x2" => DXGI_R32G32_UINT,
		"uint32x3" => DXGI_R32G32B32_UINT,
		"uint32x4" => DXGI_R32G32B32A32_UINT,
		"sint32" => DXGI_R32_SINT,
		"sint32x2" => DXGI_R32G32_SINT,
		"sint32x3" => DXGI_R32G32B32_SINT,
		"sint32x4" => DXGI_R32G32B32A32_SINT,
		"uint8x2" => DXGI_R8G8_UINT,
		"sint8x2" => DXGI_R8G8_SINT,
		"unorm8x2" => DXGI_R8G8_UNORM,
		"snorm8x2" => DXGI_R8G8_SNORM,
		"uint8x4" => DXGI_R8G8B8A8_UINT,
		"sint8x4" => DXGI_R8G8B8A8_SINT,
		"unorm8x4" => DXGI_R8G8B8A8_UNORM,
		"snorm8x4" => DXGI_R8G8B8A8_SNORM,
		"uint16x2" => DXGI_R16G16_UINT,
		"sint16x2" => DXGI_R16G16_SINT,
		"unorm16x2" => DXGI_R16G16_UNORM,
		"snorm16x2" => DXGI_R16G16_SNORM,
		"float16x2" => DXGI_R16G16_FLOAT,
		"uint16x4" => DXGI_R16G16B16A16_UINT,
		"sint16x4" => DXGI_R16G16B16A16_SINT,
		"unorm16x4" => DXGI_R16G16B16A16_UNORM,
		"snorm16x4" => DXGI_R16G16B16A16_SNORM,
		"float16x4" => DXGI_R16G16B16A16_FLOAT,
		_ => stopOnMember("vertex attribute format", format),
	};
}

function primitiveTopology(topology: string): int32 {
	return match (topology) {
		"point-list" => TOPOLOGY_POINT_LIST,
		"line-list" => TOPOLOGY_LINE_LIST,
		"line-strip" => TOPOLOGY_LINE_STRIP,
		"" | "triangle-list" => TOPOLOGY_TRIANGLE_LIST,
		"triangle-strip" => TOPOLOGY_TRIANGLE_STRIP,
		_ => stopOnMember("primitive.topology", topology),
	};
}

function stencilOperation(operation: string, member: string): int32 {
	return match (operation) {
		"" | "keep" => 1,
		"zero" => 2,
		"replace" => 3,
		"increment-clamp" => 4,
		"decrement-clamp" => 5,
		"invert" => 6,
		"increment-wrap" => 7,
		"decrement-wrap" => 8,
		_ => stopOnMember(member, operation),
	};
}

function addressMode(mode: string, member: string): int32 {
	return match (mode) {
		"" | "clamp-to-edge" => ADDRESS_CLAMP,
		"repeat" => ADDRESS_WRAP,
		"mirror-repeat" => ADDRESS_MIRROR,
		_ => stopOnMember(member, mode),
	};
}

function indexFormat(format: GPUIndexFormat): int32 {
	const value: string = format;
	return match (value) {
		"uint16" => DXGI_R16_UINT,
		"uint32" => DXGI_R32_UINT,
		_ => stopOnMember("setIndexBuffer indexFormat", value),
	};
}

function readsStage(binding: NativeBinding, vertex: int32): boolean {
	return vertex == 1 ? binding.vertexStage : binding.fragmentStage;
}

function checkDriverConstants(): void {
	const values: int32[] = [
		MAX_BLOCK_CONSTANTS,
		MAX_STAGE_CONSTANT_BUFFERS,
		MAX_STAGE_SHADER_RESOURCES,
		MAX_STAGE_SAMPLERS,
		MAX_STAGE_UNORDERED_ACCESS_VIEWS,
		MAX_DISPATCH_GROUPS,
		MAX_TEXTURE_DIMENSION_1D,
		MAX_TEXTURE_DIMENSION_2D,
		MAX_TEXTURE_DIMENSION_3D,
		MAX_TEXTURE_ARRAY_LAYERS,
		MAX_WORKGROUP_SIZE_X,
		MAX_WORKGROUP_SIZE_Y,
		MAX_WORKGROUP_SIZE_Z,
		MAX_WORKGROUP_INVOCATIONS,
		GPU_MAX_ANISOTROPY,
		INPUT_ELEMENT_INTS,
		BLEND_TARGET_INTS,
		FORMAT_CAP_SAMPLE,
		FORMAT_CAP_RENDER,
		FORMAT_CAP_BLEND,
		VIEW_2D,
		VIEW_2D_ARRAY,
		VIEW_CUBE,
		VIEW_CUBE_ARRAY,
		VIEW_3D,
		QUERY_OCCLUSION,
		QUERY_TIMESTAMP,
		QUERY_DISJOINT,
		LABEL_MAX_UNITS,
		LABEL_TOO_LONG,
		DXGI_UNKNOWN,
		DXGI_R32G32B32A32_FLOAT,
		DXGI_R32G32B32A32_UINT,
		DXGI_R32G32B32A32_SINT,
		DXGI_R32G32B32_FLOAT,
		DXGI_R32G32B32_UINT,
		DXGI_R32G32B32_SINT,
		DXGI_R16G16B16A16_FLOAT,
		DXGI_R16G16B16A16_UNORM,
		DXGI_R16G16B16A16_UINT,
		DXGI_R16G16B16A16_SNORM,
		DXGI_R16G16B16A16_SINT,
		DXGI_R32G32_FLOAT,
		DXGI_R32G32_UINT,
		DXGI_R32G32_SINT,
		DXGI_R32G8X24_TYPELESS,
		DXGI_D32_FLOAT_S8X24_UINT,
		DXGI_R32_FLOAT_X8X24_TYPELESS,
		DXGI_R10G10B10A2_UNORM,
		DXGI_R11G11B10_FLOAT,
		DXGI_R8G8B8A8_TYPELESS,
		DXGI_R8G8B8A8_UNORM,
		DXGI_R8G8B8A8_UNORM_SRGB,
		DXGI_R8G8B8A8_UINT,
		DXGI_R8G8B8A8_SNORM,
		DXGI_R8G8B8A8_SINT,
		DXGI_R16G16_FLOAT,
		DXGI_R16G16_UNORM,
		DXGI_R16G16_UINT,
		DXGI_R16G16_SNORM,
		DXGI_R16G16_SINT,
		DXGI_R32_TYPELESS,
		DXGI_D32_FLOAT,
		DXGI_R32_FLOAT,
		DXGI_R32_UINT,
		DXGI_R32_SINT,
		DXGI_R8G8_UNORM,
		DXGI_R8G8_UINT,
		DXGI_R8G8_SNORM,
		DXGI_R8G8_SINT,
		DXGI_R16_TYPELESS,
		DXGI_R16_FLOAT,
		DXGI_D16_UNORM,
		DXGI_R16_UNORM,
		DXGI_R16_UINT,
		DXGI_R8_UNORM,
		DXGI_B8G8R8A8_UNORM,
		DXGI_B8G8R8A8_TYPELESS,
		DXGI_B8G8R8A8_UNORM_SRGB,
		USAGE_DEFAULT,
		USAGE_DYNAMIC,
		USAGE_STAGING,
		BIND_VERTEX_BUFFER,
		BIND_INDEX_BUFFER,
		BIND_CONSTANT_BUFFER,
		BIND_SHADER_RESOURCE,
		BIND_RENDER_TARGET,
		BIND_DEPTH_STENCIL,
		BIND_UNORDERED_ACCESS,
		MISC_DRAWINDIRECT_ARGS,
		MISC_ALLOW_RAW_VIEWS,
		CPU_ACCESS_WRITE,
		CPU_ACCESS_READ,
		MAP_WRITE,
		MAP_WRITE_DISCARD,
		MAP_WRITE_NO_OVERWRITE,
		CLEAR_DEPTH,
		CLEAR_STENCIL,
		TOPOLOGY_POINT_LIST,
		TOPOLOGY_LINE_LIST,
		TOPOLOGY_LINE_STRIP,
		TOPOLOGY_TRIANGLE_LIST,
		TOPOLOGY_TRIANGLE_STRIP,
		CULL_NONE,
		CULL_FRONT,
		CULL_BACK,
		FILTER_MIP_LINEAR,
		FILTER_MAG_LINEAR,
		FILTER_MIN_LINEAR,
		FILTER_COMPARISON,
		FILTER_ANISOTROPIC,
		ADDRESS_WRAP,
		ADDRESS_MIRROR,
		ADDRESS_CLAMP,
		BLEND_ZERO,
		BLEND_ONE,
		BLEND_SRC_COLOR,
		BLEND_INV_SRC_COLOR,
		BLEND_SRC_ALPHA,
		BLEND_INV_SRC_ALPHA,
		BLEND_DEST_ALPHA,
		BLEND_INV_DEST_ALPHA,
		BLEND_DEST_COLOR,
		BLEND_INV_DEST_COLOR,
		BLEND_SRC_ALPHA_SAT,
		BLEND_BLEND_FACTOR,
		BLEND_INV_BLEND_FACTOR,
		COLOR_WRITE_ALL,
		COMPARISON_NEVER,
		compareFunction("never", "x"),
		compareFunction("less", "x"),
		compareFunction("equal", "x"),
		compareFunction("less-equal", "x"),
		compareFunction("greater", "x"),
		compareFunction("not-equal", "x"),
		compareFunction("greater-equal", "x"),
		compareFunction("always", "x"),
		blendOperation("add", "x"),
		blendOperation("subtract", "x"),
		blendOperation("reverse-subtract", "x"),
		blendOperation("min", "x"),
		blendOperation("max", "x"),
		stencilOperation("keep", "x"),
		stencilOperation("zero", "x"),
		stencilOperation("replace", "x"),
		stencilOperation("increment-clamp", "x"),
		stencilOperation("decrement-clamp", "x"),
		stencilOperation("invert", "x"),
		stencilOperation("increment-wrap", "x"),
		stencilOperation("decrement-wrap", "x"),
	];
	const disagreement: string = d3dConstantsDisagreement(values[0], values.length as int32);
	if (disagreement != "") { stop(`a constant of backend.ms disagrees with d3d11.c or the driver, ${disagreement}`); }
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device === null || environment.context === null) {
		stop("requestDevice needs the native ID3D11Device and ID3D11DeviceContext");
	}
	checkDriverConstants();
	device = d3dDeviceFrom(environment.device);
	context = d3dContextFrom(environment.context);
	frame = 0;
	pass = { width: 0 };
	bound = { pipeline: 0 };
	computeBound = { pipeline: 0 };
	context1 = d3dUniformOffsetting(device, context);
	offsetUniforms = context1 != null;
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(querySets);
	reset(bindGroups);
	canvas = canvasOf(environment);
	swapchainColor = reserveSwapchainTexture(canvas.format);
	textures.slots[textures.slotIndex(swapchainColor)].usage |= GPUTextureUsage.COPY_SRC as int32;
	const depthFormat: string = canvas.depthFormat;
	swapchainDepth = depthFormat == "" ? 0 : reserveSwapchainTexture(canvas.depthFormat);
	return { id: 1, queue: { id: 1 } };
}

function canvasOf(environment: NativeEnvironment): GPUCanvasConfiguration {
	const colorFormat: string = environment.colorFormat;
	if (colorFormat == "") { stop("NativeEnvironment.colorFormat is required"); }
	if (formatInfo(environment.colorFormat, "NativeEnvironment.colorFormat").depth) {
		stopOnMember("NativeEnvironment.colorFormat", colorFormat);
	}
	const depthFormat: string = environment.depthFormat;
	if (depthFormat != "" && !formatInfo(environment.depthFormat, "NativeEnvironment.depthFormat").depth) {
		stopOnMember("NativeEnvironment.depthFormat", depthFormat);
	}
	return {
		format: environment.colorFormat,
		depthFormat: environment.depthFormat,
		sampleCount: environment.sampleCount == 0 ? 1 : environment.sampleCount,
	};
}

export function canvasConfiguration(): GPUCanvasConfiguration { return canvas; }

export function formatRenderable(format: GPUTextureFormat): boolean {
	formatInfo(format, "formatRenderable format");
	return true;
}

export function frameIndex(): uint32 { return (frame + 1) as uint32; }

export function liveCounts(): GPULiveCounts {
	let counts: GPULiveCounts = { buffers: buffers.live() };
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { counts.textures += 1; } }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { counts.views += 1; } }
	counts.samplers = samplers.live();
	counts.shaderModules = shaders.live();
	counts.pipelines = pipelines.live();
	return counts;
}

export function bufferAlive(buffer: GPUBuffer): boolean {
	return buffers.alive(buffer.id);
}

export function textureAlive(texture: GPUTexture): boolean {
	return textures.alive(texture.id);
}

export function viewAlive(view: GPUTextureView): boolean {
	return views.alive(view.id);
}

export function samplerAlive(sampler: GPUSampler): boolean {
	return samplers.alive(sampler.id);
}

function reserveSwapchainTexture(format: GPUTextureFormat): uint32 {
	const textureId = allocate(textures);
	const viewId = allocate(views);
	store(textures, {
		id: textureId,
		format: format,
		info: formatInfo(format, "swapchain format"),
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		mipLevels: 1,
		layers: 1,
		swapchainView: viewId,
	});
	store(views, { id: viewId, texture: textureId, swapchain: true });
	return textureId;
}

export function shutdown(): void {
	d3dClearState(context);
	d3dRelease(context1 as Ptr<void>);
	context1 = null as unknown as Ptr<D3dContext1Impl>;
	d3dReleaseAnnotation();
	for (const id of querySets.liveIds()) { destroyQuerySet({ id: id }); }
	for (const id of bindGroups.liveIds()) { destroyBindGroup({ id: id }); }
	for (const id of pipelines.liveIds()) { destroyRenderPipeline({ id: id }); }
	for (const id of shaders.liveIds()) { destroyShaderModule({ id: id }); }
	for (const id of samplers.liveIds()) { destroySampler({ id: id }); }
	for (const id of views.liveIds()) { if (!views.slots[views.slotIndex(id)].swapchain) { destroyView({ id: id }); } }
	for (const id of textures.liveIds()) { if (textures.slots[textures.slotIndex(id)].swapchainView == 0) { destroyTexture({ id: id }); } }
	for (const id of buffers.liveIds()) { destroyBuffer({ id: id }); }
	reset(buffers);
	reset(textures);
	reset(views);
	reset(samplers);
	reset(shaders);
	reset(pipelines);
	reset(layouts);
	reset(querySets);
	reset(bindGroups);
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "d3d11", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocate(buffers);
	const usage = descriptor.usage;
	const mapRead = has(usage, GPUBufferUsage.MAP_READ as int32);
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
	const vertexOrIndex = (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.INDEX as int32);
	const uniform = has(usage, GPUBufferUsage.UNIFORM as int32);
	const storage = has(usage, GPUBufferUsage.STORAGE as int32);
	const indirect = has(usage, GPUBufferUsage.INDIRECT as int32);
	if ((storage || indirect) && (uniform || has(usage, vertexOrIndex))) {
		stop("a STORAGE or INDIRECT buffer cannot also be UNIFORM, VERTEX or INDEX on D3D11");
	}
	const resolve = has(usage, GPUBufferUsage.QUERY_RESOLVE as int32);
	if (resolve && (uniform || has(usage, vertexOrIndex))) {
		stop("a QUERY_RESOLVE buffer cannot also be UNIFORM, VERTEX or INDEX on D3D11");
	}
	if (storage && descriptor.size > MAX_STORAGE_BUFFER_BINDING_SIZE) {
		stop(`a STORAGE buffer of ${descriptor.size} bytes is over the limit of ${MAX_STORAGE_BUFFER_BINDING_SIZE}`);
	}
	if (storage && descriptor.size % 4 != 0) { stop("a STORAGE buffer takes a size that is a multiple of 4 (raw ByteAddressBuffer views)"); }
	if (uniform && has(usage, vertexOrIndex)) {
		stop("a UNIFORM buffer is a CPU shadow on D3D11 and cannot also be VERTEX or INDEX");
	}
	let slot: BufferSlot = {
		id: id,
		size: descriptor.size,
		usage: usage,
		uniform: uniform,
		storage: storage,
		staging: mapRead || mapWrite,
		updatable: false,
		native: NO_BUFFER,
		writtenFrame: has(usage, GPUBufferUsage.COPY_DST as int32) ? -1 : -2,
		writtenEnd: 0,
	};
	if (slot.staging) {
		slot.native = d3dCreateBuffer(device, descriptor.size, USAGE_STAGING, 0, CPU_ACCESS_READ | CPU_ACCESS_WRITE, 0);
		if (slot.native == null) { stop(`CreateBuffer failed for ${labelOf(descriptor.label)}`); }
	} else if (uniform && offsetUniforms) {
		slot.native = d3dCreateBuffer(device, roundUp256(descriptor.size), USAGE_DYNAMIC, BIND_CONSTANT_BUFFER, CPU_ACCESS_WRITE, 0);
		if (slot.native == null) { stop(`CreateBuffer failed for ${labelOf(descriptor.label)}`); }
	} else if (uniform) {
		slot.shadow = new Array(roundUp16(descriptor.size));
	} else {
		let bindFlags = 0;
		if (has(usage, GPUBufferUsage.VERTEX as int32)) { bindFlags |= BIND_VERTEX_BUFFER; }
		if (has(usage, GPUBufferUsage.INDEX as int32)) { bindFlags |= BIND_INDEX_BUFFER; }
		let miscFlags = 0;
		if (storage) {
			bindFlags |= BIND_SHADER_RESOURCE | BIND_UNORDERED_ACCESS;
			miscFlags |= MISC_ALLOW_RAW_VIEWS;
		}
		if (indirect) { miscFlags |= MISC_DRAWINDIRECT_ARGS; }
		slot.updatable = (bindFlags == 0 || storage) && (has(usage, GPUBufferUsage.COPY_DST as int32) || resolve);
		const writable = has(usage, GPUBufferUsage.COPY_DST as int32) && !slot.updatable;
		slot.native = d3dCreateBuffer(
			device,
			descriptor.size,
			writable ? USAGE_DYNAMIC : USAGE_DEFAULT,
			bindFlags,
			writable ? CPU_ACCESS_WRITE : 0,
			miscFlags,
		);
		if (slot.native == null) { stop(`CreateBuffer failed for ${labelOf(descriptor.label)}`); }
	}
	setLabel(slot.native, descriptor.label);
	store(buffers, slot);
	return { id: id };
}

function labelOf(label: string | null): string {
	if (label === null) { return "an unlabeled resource"; }
	return `'${label}'`;
}

function setLabel<T>(object: Ptr<T>, label: string | null): void {
	if (label === null || object == null) { return; }
	d3dSetName(object as Ptr<void>, label);
}

export function limits(): GPUSupportedLimits {
	return {
		maxTextureDimension1D: MAX_TEXTURE_DIMENSION_1D,
		maxTextureDimension2D: MAX_TEXTURE_DIMENSION_2D,
		maxTextureDimension3D: MAX_TEXTURE_DIMENSION_3D,
		maxTextureArrayLayers: MAX_TEXTURE_ARRAY_LAYERS,
		maxBindGroups: GPU_RESOURCE_GROUP + 1,
		maxSampledTexturesPerShaderStage: Math.min(MAX_STAGE_SHADER_RESOURCES, GPU_MAX_BIND_GROUP_ENTRIES),
		maxSamplersPerShaderStage: Math.min(MAX_STAGE_SAMPLERS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageBuffersPerShaderStage: Math.min(MAX_STAGE_UNORDERED_ACCESS_VIEWS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageTexturesPerShaderStage: Math.min(MAX_STAGE_UNORDERED_ACCESS_VIEWS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxUniformBuffersPerShaderStage: Math.min(MAX_STAGE_CONSTANT_BUFFERS, GPU_MAX_UNIFORM_BLOCKS),
		maxUniformBufferBindingSize: MAX_UNIFORM_BUFFER_BINDING_SIZE,
		maxStorageBufferBindingSize: MAX_STORAGE_BUFFER_BINDING_SIZE,
		maxVertexBuffers: GPU_MAX_VERTEX_BUFFERS,
		maxVertexAttributes: GPU_MAX_VERTEX_ATTRIBUTES,
		maxColorAttachments: GPU_MAX_COLOR_ATTACHMENTS,
		maxComputeWorkgroupSizeX: MAX_WORKGROUP_SIZE_X,
		maxComputeWorkgroupSizeY: MAX_WORKGROUP_SIZE_Y,
		maxComputeWorkgroupSizeZ: MAX_WORKGROUP_SIZE_Z,
		maxComputeInvocationsPerWorkgroup: MAX_WORKGROUP_INVOCATIONS,
		maxComputeWorkgroupsPerDimension: MAX_DISPATCH_GROUPS,
		minUniformBufferOffsetAlignment: UNIFORM_OFFSET_ALIGNMENT,
		minStorageBufferOffsetAlignment: STORAGE_OFFSET_ALIGNMENT,
	};
}

function supportsTimestamps(): boolean {
	return d3dQuerySupported(device, QUERY_TIMESTAMP) != 0 && d3dQuerySupported(device, QUERY_DISJOINT) != 0;
}

function formatCaps(format: GPUTextureFormat): int32 {
	return d3dFormatCaps(device, formatInfo(format, "features format").shaderResource);
}

export function features(): GPUSupportedFeatures {
	let bits: uint32 = 0;
	if (supportsTimestamps()) { bits |= featureBit("timestamp-query"); }
	const float32 = formatCaps("r32float") & formatCaps("rg32float") & formatCaps("rgba32float");
	if ((float32 & FORMAT_CAP_SAMPLE) != 0) { bits |= featureBit("float32-filterable"); }
	if ((float32 & FORMAT_CAP_BLEND) != 0) { bits |= featureBit("float32-blendable"); }
	if ((formatCaps("rg11b10ufloat") & FORMAT_CAP_RENDER) != 0) { bits |= featureBit("rg11b10ufloat-renderable"); }
	return { bits: bits };
}

function ticksToNanoseconds(ticks: uint64, frequency: uint64): uint64 {
	return (ticks / frequency) * 1000000000 + (ticks % frequency) * 1000000000 / frequency;
}

function checkLabel(status: int32, label: string): void {
	if (status == LABEL_TOO_LONG) { stop(`debug label '${label}' is over ${LABEL_MAX_UNITS} characters in UTF-16`); }
}

export function pushDebugGroup(label: string): void {
	checkLabel(d3dBeginEvent(context, label), label);
}

export function popDebugGroup(): void {
	d3dEndEvent(context);
}

export function insertDebugMarker(label: string): void { checkLabel(d3dSetMarker(context, label), label); }

function labelPass(label: string | null): boolean {
	if (label === null) { return false; }
	checkLabel(d3dBeginEvent(context, label), label);
	return true;
}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	const timestamp = kind == "timestamp";
	if (timestamp && !supportsTimestamps()) { stop("this device has no timestamp queries: features().has('timestamp-query') is false"); }
	const id = allocate(querySets);
	let slot: QuerySetSlot = {
		id: id,
		timestamp: timestamp,
		count: descriptor.count,
		queries: [],
		state: new Array(descriptor.count),
		usedPass: new Array(descriptor.count),
		disjoint: NO_QUERY,
	};
	for (let i = 0; i < descriptor.count; i++) {
		const query = d3dCreateQuery(device, timestamp ? QUERY_TIMESTAMP : QUERY_OCCLUSION);
		if (query == null) { stop(`CreateQuery failed for ${labelOf(descriptor.label)}`); }
		setLabel(query, descriptor.label);
		slot.queries.push(query);
	}
	if (timestamp) {
		slot.disjoint = d3dCreateQuery(device, QUERY_DISJOINT);
		if (slot.disjoint == null) { stop(`CreateQuery failed for ${labelOf(descriptor.label)}`); }
		setLabel(slot.disjoint, descriptor.label);
	}
	store(querySets, slot);
	return { id: id };
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySets.slotIndex(querySet.id);
	for (let i = 0; i < querySets.slots[index].queries.length; i++) { d3dRelease(querySets.slots[index].queries[i] as Ptr<void>); }
	d3dRelease(querySets.slots[index].disjoint as Ptr<void>);
	querySets.slots[index] = { id: 0 };
	release(querySets, querySet.id);
}

function writeTimestamp(querySet: uint32, queryIndex: int32): void {
	const q = querySets.slotIndex(querySet);
	if (!querySets.slots[q].disjointOpen) {
		d3dQueryBegin(context, querySets.slots[q].disjoint);
		querySets.slots[q].disjointOpen = true;
	}
	d3dQueryEnd(context, querySets.slots[q].queries[queryIndex]);
	querySets.slots[q].state[queryIndex] = QueryState.Written;
}

@noinline function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySets.slotIndex(writes.querySet.id);
	checkedTimestampWrites(member, writes, querySets.slots[q].timestamp, querySets.slots[q].count);
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	const q = querySets.slotIndex(querySet.id);
	const b = buffers.slotIndex(destination.id);
	const bytes = checkedResolveQuerySet(
		querySets.slots[q].count,
		firstQuery,
		queryCount,
		destination.id,
		buffers.slots[b].usage,
		buffers.slots[b].size,
		destinationOffset,
	);
	if (queryCount == 0) { return; }
	for (let i = 0; i < queryCount; i++) {
		const state = querySets.slots[q].state[firstQuery + i];
		if (state == QueryState.Unwritten) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QueryState.Open) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	if (querySets.slots[q].disjointOpen) {
		d3dQueryEnd(context, querySets.slots[q].disjoint);
		querySets.slots[q].disjointOpen = false;
		let frequency: uint64 = 0;
		const status = d3dQueryFrequency(context, querySets.slots[q].disjoint, frequency);
		if (status == 0) { stop("the timestamp frequency never arrived from the GPU"); }
		if (status < 0) { stop("the GPU clock was disjoint while the timestamps were written: the values are unreliable"); }
		querySets.slots[q].frequency = frequency;
	}
	let values: Vec<uint64> = new Array(queryCount);
	for (let i = 0; i < queryCount; i++) {
		let ticks: uint64 = 0;
		if (d3dQueryTicks(context, querySets.slots[q].queries[firstQuery + i], ticks) == 0) {
			stop(`query ${firstQuery + i} never arrived from the GPU`);
		}
		values[i] = querySets.slots[q].timestamp ? ticksToNanoseconds(ticks, querySets.slots[q].frequency) : ticks;
	}
	d3dUpdateBuffer(context, buffers.slots[b].native, destinationOffset, values[0], bytes);
}

export function beginOcclusionQuery(queryIndex: int32): void {
	const q = querySets.slotIndex(occlusionSetId());
	checkedOcclusionRange(queryIndex, querySets.slots[q].count);
	checkedOcclusionReuse(queryIndex, querySets.slots[q].usedPass[queryIndex]);
	querySets.slots[q].usedPass[queryIndex] = passSerial();
	querySets.slots[q].state[queryIndex] = QueryState.Open;
	d3dQueryBegin(context, querySets.slots[q].queries[queryIndex]);
}

export function endOcclusionQuery(): void {
	const q = querySets.slotIndex(occlusionSetId());
	d3dQueryEnd(context, querySets.slots[q].queries[occlusionQueryIndex()]);
	querySets.slots[q].state[occlusionQueryIndex()] = QueryState.Written;
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	d3dRelease(buffers.slots[index].native as Ptr<void>);
	buffers.slots[index] = { id: 0 };
	release(buffers, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers.slots[buffers.slotIndex(buffer.id)].size; }

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = writableBuffer(buffer.id, offset, bytes);
	if (buffers.slots[index].staging) { stop(`writeBuffer on GPUBuffer ${buffer.id}, a MAP buffer: write it through mapAsync and writeMappedRange or a copy`); }
	if (buffers.slots[index].updatable) {
		d3dUpdateBuffer(context, buffers.slots[index].native, offset, data[0], bytes);
		return;
	}
	if (buffers.slots[index].writtenFrame == -2) {
		stop(`GPUBuffer ${buffer.id} was created without COPY_DST`);
	}
	const discard = buffers.slots[index].writtenFrame != frame;
	if (discard) {
		buffers.slots[index].writtenFrame = frame;
	} else if (offset < buffers.slots[index].writtenEnd) {
		stop(`writeBuffer at ${offset} on GPUBuffer ${buffer.id} rewrites bytes this frame already wrote, up to ${buffers.slots[index].writtenEnd}`);
	}
	buffers.slots[index].writtenEnd = offset + bytes;
	if (buffers.slots[index].uniform && !offsetUniforms) {
		d3dCopyBytes(buffers.slots[index].shadow[0], offset, data[0], bytes);
		bound.uniformsDirty = true;
		return;
	}
	const mapType = discard ? MAP_WRITE_DISCARD : MAP_WRITE_NO_OVERWRITE;
	if (d3dMapWrite(context, buffers.slots[index].native, mapType, offset, data[0], bytes) == 0) {
		stop(`Map for writeBuffer failed on GPUBuffer ${buffer.id}`);
	}
}

function writableBuffer(id: uint32, offset: int64, bytes: int64): int32 {
	const index = buffers.slotIndex(id);
	checkedWriteBuffer(id, buffers.slots[index].size, offset, bytes);
	return index;
}

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocate(textures);
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const mipLevels = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const copyDestination = has(usage, GPUTextureUsage.COPY_DST as int32);
	if (attachment && copyDestination) {
		stop("COPY_DST with RENDER_ATTACHMENT has no Void caller: a multisampled target takes no UpdateSubresource");
	}
	const cube = cubeCapable(volume, layers, width, height, usage, sampleCount);
	let bindFlags = BIND_SHADER_RESOURCE;
	if (attachment) { bindFlags |= info.depth ? BIND_DEPTH_STENCIL : BIND_RENDER_TARGET; }
	if (has(usage, GPUTextureUsage.STORAGE_BINDING as int32)) {
		if (info.depth || info.texture != info.renderTarget || sampleCount > 1) {
			stop("STORAGE_BINDING needs a single-sample color format that is not sRGB on d3d11");
		}
		bindFlags |= BIND_UNORDERED_ACCESS;
	}
	let native = NO_TEXTURE;
	if (volume) {
		native = d3dCreateTexture3D(device, width, height, layers, mipLevels, info.texture, USAGE_DEFAULT, bindFlags);
	} else {
		native = d3dCreateTexture2D(
			device,
			width,
			height,
			mipLevels,
			layers,
			cube ? 1 : 0,
			info.texture,
			USAGE_DEFAULT,
			bindFlags,
			0,
			sampleCount,
		);
	}
	if (native == null) { stop(`CreateTexture failed for ${labelOf(descriptor.label)}`); }
	setLabel(native, descriptor.label);
	const slot: TextureSlot = {
		id: id,
		width: width,
		height: height,
		format: descriptor.format,
		usage: usage,
		sampleCount: sampleCount,
		mipLevels: mipLevels,
		layers: layers,
		volume: volume,
		cube: cube,
		native: native,
		info: info,
		swapchainView: 0,
	};
	store(textures, slot);
	return { id: id };
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textures.slotIndex(texture.id);
	if (textures.slots[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	d3dRelease(textures.slots[index].native as Ptr<void>);
	textures.slots[index] = { id: 0 };
	release(textures, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures.slots[textures.slotIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat { return textures.slots[textures.slotIndex(texture.id)].format; }

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	return d3dTextureNative(textures.slots[textures.slotIndex(texture.id)].native);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textures.slotIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	if (!has(textures.slots[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textures.slots[index].id}, created without COPY_DST`);
	}
	const bytesPerPixel = textures.slots[index].info.bytesPerPixel;
	const mip = destination.mipLevel;
	const mips = textures.slots[index].mipLevels;
	const volume = textures.slots[index].volume;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textures.slots[index].layers >> mip) : textures.slots[index].layers;
	const rowPitch = checkedTexelWritePitch(
		textures.slots[index].width,
		textures.slots[index].height,
		mips,
		depth,
		bytesPerPixel,
		bytes,
		destination,
		layout,
		size,
	);
	const imageBytes = (rowPitch as int64) * (layout.rowsPerImage as int64);
	if (volume) {
		d3dUpdateTexture(
			context,
			textures.slots[index].native,
			data[0],
			layout.offset,
			rowPitch,
			rowPitch * layout.rowsPerImage,
			mip,
			destination.origin.x,
			destination.origin.y,
			destination.origin.z,
			size.width,
			size.height,
			size.depthOrArrayLayers,
		);
		return;
	}
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		d3dUpdateTexture(
			context,
			textures.slots[index].native,
			data[0],
			layout.offset + imageBytes * (i as int64),
			rowPitch,
			0,
			mip + (destination.origin.z + i) * mips,
			destination.origin.x,
			destination.origin.y,
			0,
			size.width,
			size.height,
			1,
		);
	}
}

function copyableBuffer(buffer: GPUBuffer, member: string, flag: int32, flagName: string): int32 {
	const index = buffers.slotIndex(buffer.id);
	if (!has(buffers.slots[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers.slots[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	if (buffers.slots[index].native == null) { stop(`${member}: GPUBuffer ${buffer.id} is a CPU shadow uniform block on d3d11 and cannot be copied`); }
	return index;
}

function copyDestinationBuffer(buffer: GPUBuffer, member: string): int32 {
	const index = copyableBuffer(buffer, member, GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	if (!buffers.slots[index].staging && !buffers.slots[index].updatable) {
		stop(`${member}: GPUBuffer ${buffer.id} is a DYNAMIC VERTEX or INDEX buffer written by writeBuffer and cannot take a GPU copy on d3d11 yet`);
	}
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	const index = textures.slotIndex(info.texture.id);
	if (!has(textures.slots[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures.slots[index].swapchainView != 0) {
		if (textures.slots[index].native == null) { stop(`${member}: the swapchain texture has no resolved back buffer to copy`); }
		return index;
	}
	if (textures.slots[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	return index;
}


function texelCopyBytes(index: int32, member: string, writes: boolean, copy: GPUTexelCopyTextureInfo, size: GPUExtent3D): int32 {
	const format = textures.slots[index].info;
	if (format.depth) {
		checkedDepthTexelCopy(member, textures.slots[index].id, textures.slots[index].format, format.stencil, writes, textures.slots[index].width, textures.slots[index].height, copy.mipLevel, size);
	}
	if (textures.slots[index].volume) { stop(`${member}: 3d GPUTexture ${textures.slots[index].id} is not ported to d3d11 yet`); }
	return format.bytesPerPixel;
}

export function copyBufferToBuffer(
	source: GPUBuffer,
	sourceOffset: int64,
	destination: GPUBuffer,
	destinationOffset: int64,
	size: int64,
): void {
	const from = copyableBuffer(source, "copyBufferToBuffer source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination, "copyBufferToBuffer destination");
	checkedBufferCopy(source.id, buffers.slots[from].size, sourceOffset, destination.id, buffers.slots[to].size, destinationOffset, size);
	if (size == 0) { return; }
	d3dCopyBuffer(context, buffers.slots[to].native, destinationOffset, buffers.slots[from].native, sourceOffset, size);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination.buffer, "copyTextureToBuffer destination");
	checkedCopyRegion("copyTextureToBuffer source", textures.slots[from], source, size);
	const bytesPerPixel = texelCopyBytes(from, "copyTextureToBuffer source", false, source, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", bytesPerPixel, buffers.slots[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const mips = textures.slots[from].mipLevels;
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		const copied = d3dCopyTextureToBuffer(
			device,
			context,
			textures.slots[from].native,
			source.mipLevel + (source.origin.z + i) * mips,
			source.origin.x,
			source.origin.y,
			size.width,
			size.height,
			buffers.slots[to].native,
			destination.offset + (bytesPerRow as int64) * (rowsPerImage as int64) * (i as int64),
			bytesPerRow,
			size.width * bytesPerPixel,
		);
		if (copied == 0) { stop(`copyTextureToBuffer failed on GPUTexture ${source.texture.id}`); }
	}
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableBuffer(source.buffer, "copyBufferToTexture source", GPUBufferUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyBufferToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	checkedCopyRegion("copyBufferToTexture destination", textures.slots[to], destination, size);
	const bytesPerPixel = texelCopyBytes(to, "copyBufferToTexture destination", true, destination, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", bytesPerPixel, buffers.slots[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const rowBytes = size.width * bytesPerPixel;
	let readable = buffers.slots[from].native;
	let offset = source.offset;
	const temporary = !buffers.slots[from].staging;
	if (temporary) {
		const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (bytesPerRow as int64) * ((size.height - 1) as int64) + (rowBytes as int64);
		readable = d3dCreateBuffer(device, span, USAGE_STAGING, 0, CPU_ACCESS_READ | CPU_ACCESS_WRITE, 0);
		if (readable == null) { stop(`CreateBuffer failed for the copy of GPUBuffer ${source.buffer.id}`); }
		d3dCopyBuffer(context, readable, 0, buffers.slots[from].native, offset, span);
		offset = 0;
	}
	const mips = textures.slots[to].mipLevels;
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		const copied = d3dCopyBufferToTexture(
			context,
			readable,
			offset + imageBytes * (i as int64),
			bytesPerRow,
			textures.slots[to].native,
			destination.mipLevel + (destination.origin.z + i) * mips,
			destination.origin.x,
			destination.origin.y,
			size.width,
			size.height,
		);
		if (copied == 0) { stop(`copyBufferToTexture failed on GPUTexture ${destination.texture.id}`); }
	}
	if (temporary) { d3dRelease(readable as Ptr<void>); }
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyTextureToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	checkedCopyRegion("copyTextureToTexture source", textures.slots[from], source, size);
	checkedCopyRegion("copyTextureToTexture destination", textures.slots[to], destination, size);
	checkedTextureToTextureCopy(
		source,
		destination,
		size,
		textures.slots[from].format,
		textures.slots[to].format,
		textures.slots[from].volume,
		textures.slots[to].volume,
		textures.slots[from].info.depth,
		textures.slots[from].width,
		textures.slots[from].height,
	);
	if (textures.slots[from].volume) {
		d3dCopyTexture(
			context,
			textures.slots[to].native,
			destination.mipLevel,
			destination.origin.x,
			destination.origin.y,
			destination.origin.z,
			textures.slots[from].native,
			source.mipLevel,
			source.origin.x,
			source.origin.y,
			source.origin.z,
			size.width,
			size.height,
			size.depthOrArrayLayers,
		);
		return;
	}
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		d3dCopyTexture(
			context,
			textures.slots[to].native,
			destination.mipLevel + (destination.origin.z + i) * textures.slots[to].mipLevels,
			destination.origin.x,
			destination.origin.y,
			0,
			textures.slots[from].native,
			source.mipLevel + (source.origin.z + i) * textures.slots[from].mipLevels,
			source.origin.x,
			source.origin.y,
			0,
			size.width,
			size.height,
			1,
		);
	}
}

// A MAP buffer is a STAGING resource: mapAsync marks the range, and the Map call that reads or
// writes it blocks until the GPU copies into it are done.
export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	const index = buffers.slotIndex(buffer.id);
	const length = checkedMapAsync(buffer.id, buffers.slots[index].usage, buffers.slots[index].mapMode, buffers.slots[index].size, mode, offset, size);
	buffers.slots[index].mapMode = mode;
	buffers.slots[index].mapOffset = offset;
	buffers.slots[index].mapSize = length;
}

function mappedRange(member: string, buffer: GPUBuffer, mode: int32, offset: int64, size: int64): int64 {
	const index = buffers.slotIndex(buffer.id);
	const slot = buffers.slots[index];
	return checkedMappedRange(member, buffer.id, slot.size, slot.mapMode, slot.mapOffset, slot.mapSize, mode, offset, size);
}

// A copy of the mapped bytes: WebGPU's ArrayBuffer view has no MetaScript counterpart on a native pointer.
export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const length = mappedRange("getMappedRange", buffer, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	if (d3dReadBuffer(context, buffers.slots[buffers.slotIndex(buffer.id)].native, offset, bytes[0], length) == 0) {
		stop(`Map for getMappedRange failed on GPUBuffer ${buffer.id}`);
	}
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	mappedRange("writeMappedRange", buffer, GPUMapMode.WRITE as int32, offset, bytes);
	if (d3dMapWrite(context, buffers.slots[buffers.slotIndex(buffer.id)].native, MAP_WRITE, offset, data[0], bytes) == 0) {
		stop(`Map for writeMappedRange failed on GPUBuffer ${buffer.id}`);
	}
}

export function unmap(buffer: GPUBuffer): void {
	const index = buffers.slotIndex(buffer.id);
	checkedUnmap(buffer.id, buffers.slots[index].mapMode);
	buffers.slots[index].mapMode = 0;
}

function viewDimensionOf(name: string): int32 {
	if (name == "2d") { return VIEW_2D; }
	if (name == "2d-array") { return VIEW_2D_ARRAY; }
	if (name == "cube") { return VIEW_CUBE; }
	if (name == "cube-array") { return VIEW_CUBE_ARRAY; }
	if (name == "3d") { return VIEW_3D; }
	return stopOnMember("GPUTextureViewDescriptor.dimension", name);
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textures.slotIndex(texture.id);
	if (textures.slots[t].swapchainView != 0) { return { id: textures.slots[t].swapchainView }; }
	const id = allocate(views);
	const info = textures.slots[t].info;
	const multisampled = textures.slots[t].sampleCount > 1 ? 1 : 0;
	const usage = textures.slots[t].usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const layers = textures.slots[t].layers;
	const range = checkedViewRange(descriptor, textures.slots[t].id, textures.slots[t].mipLevels, layers, textures.slots[t].volume, textures.slots[t].cube);
	const baseMip = range.baseMip;
	const mipCount = range.mipCount;
	const baseLayer = range.baseLayer;
	const layerCount = range.layerCount;
	let dimension = viewDimensionOf(range.dimension);
	if (dimension == VIEW_CUBE && baseLayer != 0) { dimension = VIEW_CUBE_ARRAY; }
	const volumeTarget = attachment && mipCount == 1 && dimension == VIEW_3D && !info.depth;
	const attachable = mipCount == 1 && layerCount == 1 && (dimension == VIEW_2D || dimension == VIEW_2D_ARRAY);
	const arrayed = layers > 1 ? 1 : 0;
	let slot: ViewSlot = {
		id: 0,
		texture: texture.id,
		shaderResource: NO_SRV,
		renderTarget: NO_RTV,
		depthStencil: NO_DSV,
		unordered: NO_UAV,
		swapchainResolve: NO_RTV,
		baseMip: baseMip,
		mipCount: mipCount,
		baseLayer: baseLayer,
		volumeTarget: volumeTarget,
		swapchain: false,
	};
	const native = textures.slots[t].native;
	if (has(usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
		if (dimension == VIEW_2D && baseLayer > 0) { dimension = VIEW_2D_ARRAY; }
		slot.shaderResource = d3dCreateSrv(device, native, info.shaderResource, multisampled, dimension, baseMip, mipCount, baseLayer, layerCount);
		if (slot.shaderResource == null) { stop(`CreateShaderResourceView failed for ${labelOf(descriptor.label)}`); }
	}
	if (has(usage, GPUTextureUsage.STORAGE_BINDING as int32) && mipCount == 1) {
		const uavDimension = textures.slots[t].volume ? VIEW_3D : (layers > 1 ? VIEW_2D_ARRAY : VIEW_2D);
		slot.unordered = d3dCreateTextureUav(device, native, info.renderTarget, uavDimension, baseMip, baseLayer, layerCount);
		if (slot.unordered == null) { stop(`CreateUnorderedAccessView failed for ${labelOf(descriptor.label)}`); }
	}
	if (attachment && attachable && !info.depth) {
		slot.renderTarget = d3dCreateRtv(device, native, info.renderTarget, multisampled, arrayed, baseMip, baseLayer);
		if (slot.renderTarget == null) { stop(`CreateRenderTargetView failed for ${labelOf(descriptor.label)}`); }
	}
	if (attachment && attachable && info.depth) {
		slot.depthStencil = d3dCreateDsv(device, native, info.depthStencil, multisampled, arrayed, baseMip, baseLayer);
		if (slot.depthStencil == null) { stop(`CreateDepthStencilView failed for ${labelOf(descriptor.label)}`); }
	}
	setLabel(slot.shaderResource, descriptor.label);
	setLabel(slot.unordered, descriptor.label);
	setLabel(slot.renderTarget, descriptor.label);
	setLabel(slot.depthStencil, descriptor.label);
	slot.id = id;
	store(views, slot);
	return { id: slot.id };
}

export function destroyView(view: GPUTextureView): void {
	const index = views.slotIndex(view.id);
	if (views.slots[index].swapchain) { return; }
	d3dRelease(views.slots[index].shaderResource as Ptr<void>);
	d3dRelease(views.slots[index].unordered as Ptr<void>);
	d3dRelease(views.slots[index].renderTarget as Ptr<void>);
	d3dRelease(views.slots[index].depthStencil as Ptr<void>);
	views.slots[index] = { id: 0 };
	release(views, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views.slots[views.slotIndex(view.id)].texture }; }

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = views.slotIndex(textures.slots[textures.slotIndex(swapchainColor)].swapchainView);
	views.slots[v].renderTarget = d3dRtvFrom(swapchain.renderView);
	views.slots[v].swapchainResolve = d3dRtvFrom(swapchain.resolveView);
	const resolved = swapchain.sampleCount > 1 ? views.slots[v].swapchainResolve : views.slots[v].renderTarget;
	textures.slots[textures.slotIndex(swapchainColor)].native = d3dRtvTexture(resolved);
	if (swapchainDepth != 0) {
		updateSwapchainTexture(swapchainDepth, swapchain);
		const d = views.slotIndex(textures.slots[textures.slotIndex(swapchainDepth)].swapchainView);
		views.slots[d].depthStencil = d3dDsvFrom(swapchain.depthStencilView);
	}
	return { id: swapchainColor };
}

export function swapchainDepthTexture(): GPUTexture { return { id: swapchainDepth }; }

function updateSwapchainTexture(id: uint32, swapchain: NativeSwapchain): void {
	const t = textures.slotIndex(id);
	textures.slots[t].width = swapchain.width;
	textures.slots[t].height = swapchain.height;
	textures.slots[t].sampleCount = swapchain.sampleCount == 0 ? 1 : swapchain.sampleCount;
}

export function createSampler(descriptor: GPUSamplerDescriptor): GPUSampler {
	const id = allocate(samplers);
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter", "d3d11");
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter", "d3d11");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter", "d3d11");
	const compare: string = descriptor.compare;
	const maxAnisotropy = clampedAnisotropy(descriptor.maxAnisotropy);
	let filter = 0;
	if (maxAnisotropy > 1) {
		filter = FILTER_ANISOTROPIC;
	} else {
		if (mipLinear) { filter |= FILTER_MIP_LINEAR; }
		if (magLinear) { filter |= FILTER_MAG_LINEAR; }
		if (minLinear) { filter |= FILTER_MIN_LINEAR; }
	}
	if (compare != "") { filter |= FILTER_COMPARISON; }
	const maxLod = samplerMaxLod(descriptor.lodMaxClamp);
	const native = d3dCreateSampler(
		device,
		filter,
		addressMode(descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU"),
		addressMode(descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV"),
		addressMode(descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW"),
		maxAnisotropy,
		compare == "" ? COMPARISON_NEVER : compareFunction(compare, "GPUSamplerDescriptor.compare"),
		descriptor.lodMinClamp,
		maxLod,
	);
	if (native == null) { stop(`CreateSamplerState failed for ${labelOf(descriptor.label)}`); }
	setLabel(native, descriptor.label);
	const slot: SamplerSlot = { id: id, native: native };
	store(samplers, slot);
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplers.slotIndex(sampler.id);
	d3dRelease(samplers.slots[index].native as Ptr<void>);
	samplers.slots[index] = { id: 0 };
	release(samplers, sampler.id);
}

// A stage's precompiled bytes become its blob and skip D3DCompile; no stage reaching it loads d3dcompiler_47.dll.
function stageBlob(code: string, bytecode: Readonly<Vec<uint8>>, entryPoint: string, target: string, label: string | null, field: string): Ptr<D3dBlobImpl> {
	if (bytecode.length == 0) { return compileStage(code, entryPoint, target, label); }
	const blob = d3dBlobCopy(bytecode[0], bytecode.length as int64);
	if (blob == null) { stop(`out of memory copying GPUShaderModuleDescriptor.${field} of ${labelOf(label)}`); }
	return blob;
}

function compileStage(code: string, entryPoint: string, target: string, label: string | null): Ptr<D3dBlobImpl> {
	const entry = entryPoint == "" ? "main" : entryPoint;
	const blob = d3dCompile(code, entry, target);
	if (blob == null) {
		const log: string = d3dCompileLog();
		stop(`D3DCompile ${target} failed for ${labelOf(label)}:\n${log}`);
	}
	return blob;
}

export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	stopOnUnportedShaderBindings("d3d11", descriptor);
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	const id = allocate(shaders);
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const visibility = descriptor.bindings[i].visibility;
		const native: NativeBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName, "d3d11"),
			vertexStage: (visibility & (GPUShaderStage.VERTEX as int32)) != 0,
			fragmentStage: (visibility & (GPUShaderStage.FRAGMENT as int32)) != 0,
			computeStage: compute,
			writable: bindingWritable(descriptor.bindings[i]),
			nativeSlot: descriptor.bindings[i].nativeSlot,
			size: descriptor.bindings[i].size,
		};
		checkBinding(native);
		if (native.kind == BindingKind.Uniform) {
			slot.uniforms[slot.uniformCount] = native;
			slot.uniformCount += 1;
		} else {
			slot.resources[slot.resourceCount] = native;
			slot.resourceCount += 1;
		}
	}
	slot.attributes = descriptor.attributes;
	if (compute) {
		slot.computeEntry = descriptor.computeEntryPoint == "" ? "main" : descriptor.computeEntryPoint;
		const computeBlob = stageBlob(descriptor.computeCode, descriptor.computeBytecode, slot.computeEntry, "cs_5_0", descriptor.label, "computeBytecode");
		slot.compute = d3dCreateComputeShader(device, computeBlob);
		d3dBlobFree(computeBlob);
		if (slot.compute == null) { stop(`CreateComputeShader failed for ${labelOf(descriptor.label)}${descriptor.computeBytecode.length > 0 ? ": the device rejected GPUShaderModuleDescriptor.computeBytecode" : ""}`); }
		setLabel(slot.compute, descriptor.label);
	} else {
		slot.vertexBlob = stageBlob(descriptor.vertexCode, descriptor.vertexBytecode, descriptor.vertexEntryPoint, "vs_5_0", descriptor.label, "vertexBytecode");
		const fragmentBlob = stageBlob(descriptor.fragmentCode, descriptor.fragmentBytecode, descriptor.fragmentEntryPoint, "ps_5_0", descriptor.label, "fragmentBytecode");
		slot.vertex = d3dCreateVertexShader(device, slot.vertexBlob);
		slot.fragment = d3dCreatePixelShader(device, fragmentBlob);
		d3dBlobFree(fragmentBlob);
		if (slot.vertex == null) { stop(`CreateVertexShader failed for ${labelOf(descriptor.label)}${descriptor.vertexBytecode.length > 0 ? ": the device rejected GPUShaderModuleDescriptor.vertexBytecode" : ""}`); }
		if (slot.fragment == null) { stop(`CreatePixelShader failed for ${labelOf(descriptor.label)}${descriptor.fragmentBytecode.length > 0 ? ": the device rejected GPUShaderModuleDescriptor.fragmentBytecode" : ""}`); }
		setLabel(slot.vertex, descriptor.label);
		setLabel(slot.fragment, descriptor.label);
	}
	let cacheBytes: int64 = 0;
	for (let u = 0; u < slot.uniformCount && !offsetUniforms; u++) {
		const bytes = roundUp16(slot.uniforms[u].size as int64);
		slot.cacheOffset[u] = cacheBytes as int32;
		cacheBytes += bytes;
		slot.cacheFresh[u] = 1;
		slot.constantBuffers[u] = d3dCreateBuffer(device, bytes, USAGE_DEFAULT, BIND_CONSTANT_BUFFER, 0, 0);
		if (slot.constantBuffers[u] == null) { stop(`CreateBuffer of a constant buffer failed for ${labelOf(descriptor.label)}`); }
	}
	if (cacheBytes > 0) { slot.blockCache = new Array(cacheBytes); }
	slot.id = id;
	slot.readsInstanceIndex = descriptor.readsInstanceIndex;
	slot.readsVertexIndex = descriptor.readsVertexIndex;
	store(shaders, slot);
	return { id: slot.id };
}

function bindingWritable(binding: GPUShaderBinding): boolean {
	const kind: string = binding.kind;
	if (kind == "storage-buffer") {
		const bufferType: string = binding.bufferType;
		if (bufferType == "storage") { return true; }
		if (bufferType == "read-only-storage") { return false; }
		return stopOnMember("GPUShaderBinding.bufferType", bufferType) == 0;
	}
	if (kind == "storage-texture") {
		const access: string = binding.storageAccess;
		if (access == "write-only" || access == "read-write") { return true; }
		return stopOnMember("GPUShaderBinding.storageAccess", access) == 0;
	}
	return false;
}

@noinline function checkBinding(native: NativeBinding): void {
	const limit = match (native.kind) {
		BindingKind.Uniform => MAX_STAGE_CONSTANT_BUFFERS,
		BindingKind.Texture => MAX_STAGE_SHADER_RESOURCES,
		BindingKind.Sampler => MAX_STAGE_SAMPLERS,
		BindingKind.StorageBuffer => native.writable ? MAX_STAGE_UNORDERED_ACCESS_VIEWS : MAX_STAGE_SHADER_RESOURCES,
		BindingKind.StorageTexture => MAX_STAGE_UNORDERED_ACCESS_VIEWS,
	};
	if (native.writable && !native.computeStage) {
		stop(`shader binding ${native.binding} is writable storage in a render stage, which D3D11 binds only through OMSetRenderTargetsAndUnorderedAccessViews: not ported`);
	}
	if (native.kind == BindingKind.Uniform && native.computeStage) {
		stop(`uniform binding ${native.binding} in a compute stage is not ported to d3d11 yet`);
	}
	if (native.nativeSlot < 0 || native.nativeSlot >= limit) {
		stop(`shader binding ${native.binding} has HLSL register ${native.nativeSlot}, outside 0..${limit - 1}`);
	}
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaders.slotIndex(module.id);
	d3dRelease(shaders.slots[index].vertex as Ptr<void>);
	d3dRelease(shaders.slots[index].fragment as Ptr<void>);
	d3dRelease(shaders.slots[index].compute as Ptr<void>);
	d3dBlobFree(shaders.slots[index].vertexBlob);
	for (let u = 0; u < shaders.slots[index].uniformCount; u++) { d3dRelease(shaders.slots[index].constantBuffers[u] as Ptr<void>); }
	shaders.slots[index] = { id: 0 };
	release(shaders, module.id);
}

function semanticIndexOf(shader: int32, location: int32): int32 {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		if (shaders.slots[shader].attributes[i].location == location) {
			return shaders.slots[shader].attributes[i].semanticIndex;
		}
	}
	return stopOnMember("vertex attribute shaderLocation (absent from the shader reflection)", `${location}`);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocate(pipelines);
	const s = shaders.slotIndex(descriptor.vertex.module.id);
	checkedRenderModule(shaders.slots[s].compute != null);
	let slot: PipelineSlot = { id: 0, shader: descriptor.vertex.module.id, label: descriptor.label, readsInstanceIndex: shaders.slots[s].readsInstanceIndex, readsVertexIndex: shaders.slots[s].readsVertexIndex };
	slot.topology = primitiveTopology(descriptor.primitive.topology);
	slot.stripIndexFormat = stripIndexFormatOf(descriptor.primitive);
	slot.inputLayout = createInputLayout(s, descriptor, slot);
	const sampleCount = descriptor.multisample.count == 0 ? 1 : descriptor.multisample.count;
	slot.rasterizer = d3dCreateRasterizerState(
		device,
		cullMode(descriptor.primitive.cullMode),
		frontCounterClockwise(descriptor.primitive.frontFace),
		sampleCount > 1 ? 1 : 0,
		descriptor.depthStencil.depthBias,
		descriptor.depthStencil.depthBiasSlopeScale,
		descriptor.depthStencil.depthBiasClamp,
	);
	const depthFormat: string = descriptor.depthStencil.format;
	let stencil = false;
	if (depthFormat != "") { stencil = formatInfo(descriptor.depthStencil.format, "depthStencil.format").stencil; }
	const front: GPUStencilFaceState = descriptor.depthStencil.stencilFront;
	const back: GPUStencilFaceState = descriptor.depthStencil.stencilBack;
	const readMask = descriptor.depthStencil.stencilReadMask;
	const writeMask = descriptor.depthStencil.stencilWriteMask;
	slot.depthStencil = d3dCreateDepthStencilState(
		device,
		depthFormat != "" && descriptor.depthStencil.depthWriteEnabled ? 1 : 0,
		depthFormat == "" ? 8 : compareFunction(descriptor.depthStencil.depthCompare, "depthStencil.depthCompare"),
		stencil ? 1 : 0,
		(readMask == 0 ? STENCIL_MASK_DEFAULT : readMask) as int32,
		(writeMask == 0 ? STENCIL_MASK_DEFAULT : writeMask) as int32,
		stencilOperation(front.failOp, "depthStencil.stencilFront.failOp"),
		stencilOperation(front.depthFailOp, "depthStencil.stencilFront.depthFailOp"),
		stencilOperation(front.passOp, "depthStencil.stencilFront.passOp"),
		compareFunction(front.compare, "depthStencil.stencilFront.compare"),
		stencilOperation(back.failOp, "depthStencil.stencilBack.failOp"),
		stencilOperation(back.depthFailOp, "depthStencil.stencilBack.depthFailOp"),
		stencilOperation(back.passOp, "depthStencil.stencilBack.passOp"),
		compareFunction(back.compare, "depthStencil.stencilBack.compare"),
	);
	slot.blend = createBlendState(descriptor);
	if (slot.rasterizer == null || slot.depthStencil == null || slot.blend == null) {
		stop(`a D3D11 state object failed for pipeline ${labelOf(descriptor.label)}`);
	}
	setLabel(slot.inputLayout, descriptor.label);
	setLabel(slot.rasterizer, descriptor.label);
	setLabel(slot.depthStencil, descriptor.label);
	setLabel(slot.blend, descriptor.label);
	slot.id = id;
	store(pipelines, slot);
	return { id: slot.id };
}

function stripIndexFormatOf(state: GPUPrimitiveState): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return 0; }
	return indexFormat(state.stripIndexFormat);
}

function createInputLayout(
	shader: int32,
	descriptor: GPURenderPipelineDescriptor,
	ref slot: PipelineSlot,
): Ptr<D3dInputLayoutImpl> {
	let count = 0;
	let elements: int32[INPUT_ELEMENT_INTS * GPU_MAX_VERTEX_ATTRIBUTES] = [];
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stepMode: string = descriptor.vertex.buffers[b].stepMode;
		if (stepMode != "" && stepMode != "vertex" && stepMode != "instance") {
			stopOnMember("vertex.buffers stepMode", stepMode);
		}
		const perInstance = stepMode == "instance" ? 1 : 0;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			if (count == GPU_MAX_VERTEX_ATTRIBUTES) { stop(`a pipeline has over ${GPU_MAX_VERTEX_ATTRIBUTES} vertex attributes`); }
			const location = descriptor.vertex.buffers[b].attributes[a].shaderLocation;
			elements[count * INPUT_ELEMENT_INTS] = semanticIndexOf(shader, location);
			elements[count * INPUT_ELEMENT_INTS + 1] = vertexFormat(format);
			elements[count * INPUT_ELEMENT_INTS + 2] = b;
			elements[count * INPUT_ELEMENT_INTS + 3] = descriptor.vertex.buffers[b].attributes[a].offset;
			elements[count * INPUT_ELEMENT_INTS + 4] = perInstance;
			count += 1;
			slot.strides[b] = descriptor.vertex.buffers[b].arrayStride;
		}
		if (slot.strides[b] == 0 && descriptor.vertex.buffers[b].arrayStride != 0) {
			slot.strides[b] = descriptor.vertex.buffers[b].arrayStride;
		}
	}
	if (count == 0) { return null as unknown as Ptr<D3dInputLayoutImpl>; }
	const layout = d3dCreateInputLayout(device, elements[0], count, shaders.slots[shader].vertexBlob);
	if (layout == null) { stop(`CreateInputLayout failed for pipeline ${labelOf(descriptor.label)}`); }
	return layout;
}

function createBlendState(descriptor: GPURenderPipelineDescriptor): Ptr<D3dBlendStateImpl> {
	let count = 0;
	let targets: int32[BLEND_TARGET_INTS * GPU_MAX_COLOR_ATTACHMENTS] = [];
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") { continue; }
		formatInfo(descriptor.fragment.targets[i].format, `fragment.targets[${i}].format`);
		const color: GPUBlendComponent = descriptor.fragment.targets[i].blend.color;
		const alpha: GPUBlendComponent = descriptor.fragment.targets[i].blend.alpha;
		const writeMask = descriptor.fragment.targets[i].writeMask;
		targets[count * BLEND_TARGET_INTS] = i;
		targets[count * BLEND_TARGET_INTS + 1] = descriptor.fragment.targets[i].blendEnabled ? 1 : 0;
		targets[count * BLEND_TARGET_INTS + 2] = blendFactor(color.srcFactor, false, "blend.color.srcFactor");
		targets[count * BLEND_TARGET_INTS + 3] = destinationFactor(color.dstFactor, false, "blend.color.dstFactor");
		targets[count * BLEND_TARGET_INTS + 4] = blendOperation(color.operation, "blend.color.operation");
		targets[count * BLEND_TARGET_INTS + 5] = blendFactor(alpha.srcFactor, true, "blend.alpha.srcFactor");
		targets[count * BLEND_TARGET_INTS + 6] = destinationFactor(alpha.dstFactor, true, "blend.alpha.dstFactor");
		targets[count * BLEND_TARGET_INTS + 7] = blendOperation(alpha.operation, "blend.alpha.operation");
		targets[count * BLEND_TARGET_INTS + 8] = writeMask == 0 ? COLOR_WRITE_ALL : writeMask;
		count += 1;
	}
	return d3dCreateBlendState(device, targets[0], count);
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	const index = pipelines.slotIndex(pipeline.id);
	d3dRelease(pipelines.slots[index].inputLayout as Ptr<void>);
	d3dRelease(pipelines.slots[index].rasterizer as Ptr<void>);
	d3dRelease(pipelines.slots[index].depthStencil as Ptr<void>);
	d3dRelease(pipelines.slots[index].blend as Ptr<void>);
	for (let g = 0; g < BIND_GROUPS; g++) {
		const layout = pipelines.slots[index].layouts[g];
		if (layout != 0) {
			layouts.slots[layouts.slotIndex(layout)] = { id: 0 };
			release(layouts, layout);
		}
	}
	pipelines.slots[index] = { id: 0 };
	release(pipelines, pipeline.id);
}

export function getBindGroupLayout(pipeline: GPURenderPipeline, index: int32): GPUBindGroupLayout {
	const p = pipelines.slotIndex(pipeline.id);
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) {
		stopOnMember("getBindGroupLayout index", `${index}`);
	}
	if (pipelines.slots[p].layouts[index] == 0) {
		const id = allocate(layouts);
		const slot: LayoutSlot = { id: id, pipeline: pipeline.id, group: index };
		store(layouts, slot);
		pipelines.slots[p].layouts[index] = id;
	}
	return { id: pipelines.slots[p].layouts[index] };
}

export function createBindGroup(descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	const id = allocate(bindGroups);
	const l = layouts.slotIndex(descriptor.layout.id);
	const group = layouts.slots[l].group;
	const shader = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(layouts.slots[l].pipeline)].shader);
	let slot: BindGroupSlot = { id: 0, group: group };
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) { continue; }
		checkEntry(shader, group, entry);
		if (entry.buffer.id != 0 && buffers.slots[buffers.slotIndex(entry.buffer.id)].storage) { storageViews(slot, shader, entry); }
		slot.entries[slot.entryCount] = entry;
		slot.entryCount += 1;
	}
	for (let i = 0; i < slot.entryCount; i++) {
		if (slot.entries[i].buffer.id == 0 || !buffers.slots[buffers.slotIndex(slot.entries[i].buffer.id)].uniform) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			if (slot.entries[j].buffer.id != 0 && buffers.slots[buffers.slotIndex(slot.entries[j].buffer.id)].uniform && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	slot.id = id;
	store(bindGroups, slot);
	return { id: slot.id };
}

function resourceOf(shader: int32, group: int32, binding: int32): int32 {
	for (let r = 0; r < shaders.slots[shader].resourceCount; r++) {
		const resource = shaders.slots[shader].resources[r];
		if (addressesBinding(group, binding, resource.binding, resource.kind)) { return r; }
	}
	return -1;
}

function storageViews(ref slot: BindGroupSlot, shader: int32, entry: GPUBindGroupEntry): void {
	const b = buffers.slotIndex(entry.buffer.id);
	const bytes = entryBytes(entry, buffers.slots[b].size);
	const binding = shaders.slots[shader].resources[resourceOf(shader, slot.group, entry.binding)];
	if (binding.writable) {
		slot.uav[slot.entryCount] = d3dCreateBufferUav(device, buffers.slots[b].native, entry.offset, bytes);
		if (slot.uav[slot.entryCount] == null) { stop(`CreateUnorderedAccessView failed for bind group entry ${entry.binding}`); }
	} else {
		slot.srv[slot.entryCount] = d3dCreateBufferSrv(device, buffers.slots[b].native, entry.offset, bytes);
		if (slot.srv[slot.entryCount] == null) { stop(`CreateShaderResourceView failed for bind group entry ${entry.binding}`); }
	}
}

@noinline function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = buffers.slotIndex(entry.buffer.id);
		for (let u = 0; u < shaders.slots[shader].uniformCount; u++) {
			const binding = shaders.slots[shader].uniforms[u];
			if (addressesBinding(group, entry.binding, binding.binding, BindingKind.Uniform)) {
				checkedUniformEntry(entry, buffers.slots[b].uniform, buffers.slots[b].size, binding.size, UNIFORM_OFFSET_ALIGNMENT as int64);
				return;
			}
		}
		const r = resourceOf(shader, group, entry.binding);
		if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.StorageBuffer) {
			checkedStorageEntry(entry, buffers.slots[b].storage, buffers.slots[b].size, STORAGE_OFFSET_ALIGNMENT, MAX_STORAGE_BUFFER_BINDING_SIZE);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	const r = resourceOf(shader, group, entry.binding);
	if (entry.textureView.id != 0) {
		const v = views.slotIndex(entry.textureView.id);
		if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.Texture) {
			checkedSampledView(entry.binding, views.slots[v].shaderResource != null);
			return;
		}
		if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.StorageTexture) {
			checkedStorageView(entry.binding, has(textures.slots[textures.slotIndex(views.slots[v].texture)].usage, GPUTextureUsage.STORAGE_BINDING as int32), views.slots[v].mipCount);
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplers.slotIndex(entry.sampler.id);
	if (r >= 0 && shaders.slots[shader].resources[r].kind == BindingKind.Sampler) { return; }
	stop(`bind group ${group} entry ${entry.binding} (sampler) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroups.slotIndex(bindGroup.id);
	for (let e = 0; e < bindGroups.slots[index].entryCount; e++) {
		d3dRelease(bindGroups.slots[index].srv[e] as Ptr<void>);
		d3dRelease(bindGroups.slots[index].uav[e] as Ptr<void>);
	}
	bindGroups.slots[index] = { id: 0 };
	release(bindGroups, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(commandBuffer: GPUCommandBuffer): void { frame += 1; }

export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	if (descriptor.occlusionQuerySet.id != 0) {
		checkedOcclusionSetKind(querySets.slots[querySets.slotIndex(descriptor.occlusionQuerySet.id)].timestamp);
	}
	pass = {
		timestampSet: descriptor.timestampWrites.querySet.id,
		timestampEnd: descriptor.timestampWrites.endOfPassWriteIndex,
	};
	pass.labeled = labelPass(descriptor.label);
	if (pass.timestampSet != 0 && descriptor.timestampWrites.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(pass.timestampSet, descriptor.timestampWrites.beginningOfPassWriteIndex);
	}
	let targets: Ptr<D3dRtvImpl>[4] = [NO_RTV, NO_RTV, NO_RTV, NO_RTV];
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = views.slotIndex(viewId);
		const slice = descriptor.colorAttachments[i].depthSlice;
		if (views.slots[v].volumeTarget) {
			const volume = textures.slotIndex(views.slots[v].texture);
			const slices = Math.max(1, textures.slots[volume].layers >> views.slots[v].baseMip);
			checkedDepthSlice(i, slice, slices, views.slots[v].baseMip, textures.slots[volume].id);
			const format = textures.slots[volume].info.renderTarget;
			pass.sliceTargets[i] = d3dCreateRtv3d(device, textures.slots[volume].native, format, views.slots[v].baseMip, slice);
			if (pass.sliceTargets[i] == null) { stop(`CreateRenderTargetView failed for slice ${slice} of GPUTexture ${textures.slots[volume].id}`); }
			targets[i] = pass.sliceTargets[i];
		} else {
			if (views.slots[v].renderTarget == null) { stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`); }
			checkedNoDepthSlice(i, slice);
			targets[i] = views.slots[v].renderTarget;
		}
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		pass.colorViews[i] = viewId;
		pass.resolveViews[i] = checkResolve(i, views.slots[v].texture, descriptor.colorAttachments[i].resolveTarget.id);
		checkStoreOp(descriptor.colorAttachments[i].storeOp, i, "storeOp");
	}
	let depth = NO_DSV;
	const depthView = descriptor.depthStencilAttachment.view.id;
	let depthStencil = false;
	if (depthView != 0) {
		const v = views.slotIndex(depthView);
		if (views.slots[v].depthStencil == null) { stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT"); }
		depth = views.slots[v].depthStencil;
		passExtent(views.slots[v].texture, views.slots[v].baseMip);
		depthStencil = textures.slots[textures.slotIndex(views.slots[v].texture)].info.stencil;
		checkStoreOp(descriptor.depthStencilAttachment.depthStoreOp, -1, "depthStoreOp");
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	d3dSetRenderTargets(context, targets[0], targets[1], targets[2], targets[3], depth);
	d3dSetViewport(context, 0.0, 0.0, pass.width, pass.height, 0.0, 1.0);
	d3dSetScissorRect(context, 0, 0, pass.width, pass.height);
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] == 0) { continue; }
		if (isClear(descriptor.colorAttachments[i].loadOp, i, "loadOp")) {
			const color = descriptor.colorAttachments[i].clearValue;
			d3dClearRtv(context, targets[i], color.r, color.g, color.b, color.a);
		}
	}
	if (depthView != 0 && isClear(descriptor.depthStencilAttachment.depthLoadOp, -1, "depthLoadOp")) {
		const flags = depthStencil ? CLEAR_DEPTH | CLEAR_STENCIL : CLEAR_DEPTH;
		d3dClearDsv(context, depth, flags, descriptor.depthStencilAttachment.depthClearValue, 0);
	}
	nativeBinds = { indexFormat: 0 };
	bound.appliedPipeline = 0;
	bound.blendConstant = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
	bound.stencilReference = 0;
	bound.vertexDirty = true;
	bound.indexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
	return { id: 1 };
}

function passExtent(texture: uint32, baseMip: int32): void {
	const t = textures.slotIndex(texture);
	const width = Math.max(1, textures.slots[t].width >> baseMip);
	const height = Math.max(1, textures.slots[t].height >> baseMip);
	checkedPassExtent(pass.width, pass.height, width, height);
	pass.width = width;
	pass.height = height;
}

@noinline function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): uint32 {
	if (resolveId == 0) { return 0; }
	const r = views.slotIndex(resolveId);
	const resolveTexture = textures.slotIndex(views.slots[r].texture);
	const color = textures.slotIndex(colorTexture);
	checkedResolveTarget(
		attachment,
		textures.slots[color].sampleCount,
		textures.slots[color].width,
		textures.slots[color].height,
		Math.max(1, textures.slots[resolveTexture].width >> views.slots[r].baseMip),
		Math.max(1, textures.slots[resolveTexture].height >> views.slots[r].baseMip),
	);
	if (textures.slots[resolveTexture].sampleCount != 1 || views.slots[r].renderTarget == null) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample color RENDER_ATTACHMENT`);
	}
	return resolveId;
}

function attachmentMember(index: int32, field: string): string {
	return index < 0 ? `depthStencilAttachment.${field}` : `colorAttachments[${index}].${field}`;
}

function isClear(loadOp: string, index: int32, field: string): boolean {
	const value = match (loadOp) {
		"clear" => 1,
		"load" => 0,
		_ => stopOnMember(attachmentMember(index, field), loadOp),
	};
	return value == 1;
}

@noinline function checkStoreOp(storeOp: string, index: int32, field: string): void {
	if (storeOp != "store" && storeOp != "discard") { stopOnMember(attachmentMember(index, field), storeOp); }
}

export function endPass(): void {
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] == 0) { continue; }
		const v = views.slotIndex(pass.colorViews[i]);
		if (views.slots[v].swapchain && views.slots[v].swapchainResolve != null) {
			const format = formatInfo(canvas.format, "canvas format").renderTarget;
			d3dResolveViews(context, views.slots[v].swapchainResolve, views.slots[v].renderTarget, format);
		}
		if (pass.resolveViews[i] != 0) {
			const source = textures.slotIndex(views.slots[v].texture);
			const destination = textures.slotIndex(views.slots[views.slotIndex(pass.resolveViews[i])].texture);
			const format = textures.slots[source].info.renderTarget;
			const target = views.slotIndex(pass.resolveViews[i]);
			const subresource = views.slots[target].baseMip + views.slots[target].baseLayer * textures.slots[destination].mipLevels;
			d3dResolveSubresource(context, textures.slots[destination].native, subresource, textures.slots[source].native, format);
		}
		if (pass.sliceTargets[i] != null) {
			d3dRelease(pass.sliceTargets[i] as Ptr<void>);
			pass.sliceTargets[i] = NO_RTV;
		}
	}
	if (pass.timestampSet != 0 && pass.timestampEnd >= 0) { writeTimestamp(pass.timestampSet, pass.timestampEnd); }
	if (pass.labeled) { d3dEndEvent(context); }
	d3dClearState(context);
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const s = shaders.slotIndex(descriptor.compute.module.id);
	const entry = descriptor.compute.entryPoint == "" ? "main" : descriptor.compute.entryPoint;
	checkedComputeModule(shaders.slots[s].compute != null, entry, shaders.slots[s].computeEntry);
	const id = allocate(pipelines);
	const slot: PipelineSlot = { id: id, shader: descriptor.compute.module.id, compute: true };
	store(pipelines, slot);
	return { id: id };
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	checkTimestampWrites("GPUComputePassDescriptor.timestampWrites", descriptor.timestampWrites);
	computeBound = {
		timestampSet: descriptor.timestampWrites.querySet.id,
		timestampEnd: descriptor.timestampWrites.endOfPassWriteIndex,
	};
	computeBound.labeled = labelPass(descriptor.label);
	if (computeBound.timestampSet != 0 && descriptor.timestampWrites.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(computeBound.timestampSet, descriptor.timestampWrites.beginningOfPassWriteIndex);
	}
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	checkedComputePipeline(pipeline.id, pipelines.slots[pipelines.slotIndex(pipeline.id)].compute);
	computeBound.pipeline = pipeline.id;
	computeBound.dirty = true;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (index != GPU_RESOURCE_GROUP) { stop(`a compute pipeline has no uniform group: setBindGroup(${index}) takes group ${GPU_RESOURCE_GROUP}`); }
	if (dynamicOffsets.length != 0) { stop("a compute bind group takes no dynamic offsets"); }
	if (bindGroup.id != 0 && bindGroups.slots[bindGroups.slotIndex(bindGroup.id)].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups.slots[bindGroups.slotIndex(bindGroup.id)].group}`);
	}
	computeBound.bindGroup = bindGroup.id;
	computeBound.dirty = true;
}

function applyCompute(): void {
	if (!computeBound.dirty) { return; }
	const s = shaders.slotIndex(pipelines.slots[pipelines.slotIndex(computeBound.pipeline)].shader);
	d3dCsClearViews(context);
	d3dCsSetShader(context, shaders.slots[s].compute);
	computeBound.dirty = false;
	if (shaders.slots[s].resourceCount == 0) { return; }
	if (computeBound.bindGroup == 0) { stop("the compute pipeline reads bind group 1, which is not set"); }
	const g = bindGroups.slotIndex(computeBound.bindGroup);
	for (let r = 0; r < shaders.slots[s].resourceCount; r++) {
		const binding: NativeBinding = shaders.slots[s].resources[r];
		const e = entryOf(bindGroups.slots[g], binding.binding);
		if (binding.kind == BindingKind.Texture) {
			d3dCsSetShaderResource(context, binding.nativeSlot, views.slots[views.slotIndex(bindGroups.slots[g].entries[e].textureView.id)].shaderResource);
		} else if (binding.kind == BindingKind.Sampler) {
			d3dCsSetSampler(context, binding.nativeSlot, samplers.slots[samplers.slotIndex(bindGroups.slots[g].entries[e].sampler.id)].native);
		} else if (binding.kind == BindingKind.StorageBuffer) {
			if (binding.writable) {
				d3dCsSetUnorderedAccessView(context, binding.nativeSlot, bindGroups.slots[g].uav[e]);
			} else {
				d3dCsSetShaderResource(context, binding.nativeSlot, bindGroups.slots[g].srv[e]);
			}
		} else {
			d3dCsSetUnorderedAccessView(context, binding.nativeSlot, views.slots[views.slotIndex(bindGroups.slots[g].entries[e].textureView.id)].unordered);
		}
	}
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	applyCompute();
	d3dDispatch(context, x, y, z);
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = buffers.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, buffers.slots[b].usage, buffers.slots[b].size, offset);
	applyCompute();
	d3dDispatchIndirect(context, buffers.slots[b].native, offset);
}

export function endComputePass(): void {
	if (computeBound.timestampSet != 0 && computeBound.timestampEnd >= 0) { writeTimestamp(computeBound.timestampSet, computeBound.timestampEnd); }
	if (computeBound.labeled) { d3dEndEvent(context); }
	d3dClearState(context);
	computeBound = { pipeline: 0 };
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	checkedRenderPassPipeline(pipeline.id, pipelines.slots[pipelines.slotIndex(pipeline.id)].compute);
	bound.pipeline = pipeline.id;
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) { stopOnMember("setVertexBuffer slot", `${slot}`); }
	bound.vertexBuffers[slot] = buffer.id;
	bound.vertexOffsets[slot] = offset;
	bound.vertexDirty = true;
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	bound.indexBuffer = buffer.id;
	bound.indexFormat = indexFormat(format);
	bound.indexOffset = offset;
	bound.indexDirty = true;
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	bound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroups.slotIndex(bindGroup.id);
	checkedBindGroupSet(index, bindGroups.slots[g].group, bindGroups.slots[g].dynamicCount, dynamicOffsets, UNIFORM_OFFSET_ALIGNMENT);
	if (index == GPU_UNIFORM_GROUP) {
		for (let i = 0; i < bindGroups.slots[g].dynamicCount; i++) {
			bound.dynamicOffsets[i] = dynamicOffsets[i];
		}
		bound.uniformsDirty = true;
	} else {
		bound.resourcesDirty = true;
	}
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	d3dSetScissorRect(context, x, y, x + width, y + height);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	d3dSetViewport(context, x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	bound.blendConstant = color;
	if (bound.appliedPipeline != 0) { applyBlend(pipelines.slotIndex(bound.appliedPipeline)); }
}

export function setStencilReference(reference: uint32): void {
	bound.stencilReference = reference;
	if (bound.appliedPipeline != 0) { applyDepthStencil(pipelines.slotIndex(bound.appliedPipeline)); }
}

function applyBlend(p: int32): void {
	const color = bound.blendConstant;
	d3dOmSetBlendState(context, pipelines.slots[p].blend, color.r, color.g, color.b, color.a);
}

function applyDepthStencil(p: int32): void {
	d3dOmSetDepthStencilState(
		context,
		pipelines.slots[p].depthStencil,
		bound.stencilReference as int32,
	);
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush(false);
	checkDrawOffsets("draw", "firstVertex", firstVertex, firstInstance);
	if (instanceCount > 1 || firstInstance != 0) {
		d3dDrawInstanced(context, vertexCount, instanceCount, firstVertex, firstInstance);
	} else {
		d3dDraw(context, vertexCount, firstVertex);
	}
}

export function drawIndexed(
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	if (instanceCount == 0) { return; }
	flush(true);
	checkDrawOffsets("drawIndexed", "baseVertex", baseVertex, firstInstance);
	if (instanceCount > 1 || firstInstance != 0) {
		d3dDrawIndexedInstanced(context, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
	} else {
		d3dDrawIndexed(context, indexCount, firstIndex, baseVertex);
	}
}

function checkDrawOffsets(call: string, vertexMember: string, vertexOffset: int32, firstInstance: int32): void {
	if (vertexOffset == 0 && firstInstance == 0) { return; }
	const p = pipelines.slotIndex(bound.pipeline);
	if (firstInstance != 0 && pipelines.slots[p].readsInstanceIndex) { stop(firstInstanceRefusal(call, labelOf(pipelines.slots[p].label), firstInstance)); }
	if (vertexOffset != 0 && pipelines.slots[p].readsVertexIndex) {
		stop(vertexOffsetRefusal(call, labelOf(pipelines.slots[p].label), vertexMember, vertexOffset));
	}
}

function flush(indexed: boolean): void {
	const p = pipelines.slotIndex(bound.pipeline);
	const s = liveShader(p);
	if (bound.appliedPipeline != bound.pipeline) { applyPipeline(p, s); }
	if (bound.vertexDirty) { applyVertexBuffers(p); }
	if (indexed && bound.indexDirty) { applyIndexBuffer(); }
	if (indexed) { checkStripIndexFormat(p); }
	if (bound.resourcesDirty) { applyResources(s); }
	if (bound.uniformsDirty) { applyUniforms(s); }
}

function liveShader(p: int32): int32 {
	if (!shaders.alive(pipelines.slots[p].shader)) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	return shaders.slotIndex(pipelines.slots[p].shader);
}

function applyPipeline(p: int32, s: int32): void {
	d3dRsSetState(context, pipelines.slots[p].rasterizer);
	bound.appliedPipeline = bound.pipeline;
	applyDepthStencil(p);
	applyBlend(p);
	d3dIaSetPrimitiveTopology(context, pipelines.slots[p].topology);
	d3dIaSetInputLayout(context, pipelines.slots[p].inputLayout);
	d3dVsSetShader(context, shaders.slots[s].vertex);
	d3dPsSetShader(context, shaders.slots[s].fragment);
	for (let u = 0; u < shaders.slots[s].uniformCount && !offsetUniforms; u++) {
		for (let vertex = 0; vertex < 2; vertex++) {
			if (!readsStage(shaders.slots[s].uniforms[u], vertex)) { continue; }
			d3dSetConstantBuffer(context, vertex, shaders.slots[s].uniforms[u].nativeSlot, shaders.slots[s].constantBuffers[u]);
		}
	}
	forgetAppliedUniforms();
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
}

@noinline function checkStripIndexFormat(p: int32): void {
	const topology = pipelines.slots[p].topology;
	checkedStripDraw(topology == TOPOLOGY_LINE_STRIP || topology == TOPOLOGY_TRIANGLE_STRIP, pipelines.slots[p].stripIndexFormat == bound.indexFormat);
}

function applyVertexBuffers(p: int32): void {
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		const stride = pipelines.slots[p].strides[slot];
		if (stride == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		const b = buffers.slotIndex(bound.vertexBuffers[slot]);
		const native = buffers.slots[b].native;
		const offset = bound.vertexOffsets[slot] as int32;
		if (nativeBinds.vertexBuffer[slot] == native && nativeBinds.vertexStride[slot] == stride && nativeBinds.vertexOffset[slot] == offset) { continue; }
		d3dIaSetVertexBuffer(context, slot, native, stride, offset);
		nativeBinds.vertexBuffer[slot] = native;
		nativeBinds.vertexStride[slot] = stride;
		nativeBinds.vertexOffset[slot] = offset;
		stats.vertexBuffers += 1;
	}
	bound.vertexDirty = false;
}

function applyIndexBuffer(): void {
	const b = buffers.slotIndex(bound.indexBuffer);
	const native = buffers.slots[b].native;
	const offset = bound.indexOffset as int32;
	bound.indexDirty = false;
	if (nativeBinds.indexBuffer == native && nativeBinds.indexFormat == bound.indexFormat && nativeBinds.indexOffset == offset) { return; }
	d3dIaSetIndexBuffer(context, native, bound.indexFormat, offset);
	nativeBinds.indexBuffer = native;
	nativeBinds.indexFormat = bound.indexFormat;
	nativeBinds.indexOffset = offset;
	stats.indexBuffers += 1;
}


function applyResources(s: int32): void {
	bound.resourcesDirty = false;
	if (shaders.slots[s].resourceCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	const g = bindGroups.slotIndex(bound.bindGroups[GPU_RESOURCE_GROUP]);
	for (let r = 0; r < shaders.slots[s].resourceCount; r++) {
		const binding: NativeBinding = shaders.slots[s].resources[r];
		const e = entryOf(bindGroups.slots[g], binding.binding);
		if (binding.kind == BindingKind.StorageTexture) { stop("a storage texture in a render stage is not ported to d3d11"); }
		if (binding.kind == BindingKind.Texture || binding.kind == BindingKind.StorageBuffer) {
			const view = binding.kind == BindingKind.Texture ? views.slots[views.slotIndex(bindGroups.slots[g].entries[e].textureView.id)].shaderResource : bindGroups.slots[g].srv[e];
			for (let vertex = 0; vertex < 2; vertex++) {
				if (!readsStage(binding, vertex)) { continue; }
				const cached = (vertex == 1 ? 0 : MAX_STAGE_SHADER_RESOURCES) + binding.nativeSlot;
				if (nativeBinds.shaderResource[cached] == view) { continue; }
				d3dSetShaderResource(context, vertex, binding.nativeSlot, view);
				nativeBinds.shaderResource[cached] = view;
				stats.shaderResources += 1;
			}
		} else {
			const sampler = samplers.slots[samplers.slotIndex(bindGroups.slots[g].entries[e].sampler.id)].native;
			for (let vertex = 0; vertex < 2; vertex++) {
				if (!readsStage(binding, vertex)) { continue; }
				const cached = (vertex == 1 ? 0 : MAX_STAGE_SAMPLERS) + binding.nativeSlot;
				if (nativeBinds.sampler[cached] == sampler) { continue; }
				d3dSetSampler(context, vertex, binding.nativeSlot, sampler);
				nativeBinds.sampler[cached] = sampler;
				stats.samplers += 1;
			}
		}
	}
}

function applyUniforms(s: int32): void {
	bound.uniformsDirty = false;
	if (shaders.slots[s].uniformCount == 0) { return; }
	if (bound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the pipeline reads bind group 0, which is not set"); }
	const g = bindGroups.slotIndex(bound.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders.slots[s].uniformCount; u++) {
		const e = entryOf(bindGroups.slots[g], shaders.slots[s].uniforms[u].binding);
		const offset = (bound.dynamicOffsets[bindGroups.slots[g].dynamicIndex[e]] as int64) + bindGroups.slots[g].entries[e].offset;
		const b = buffers.slotIndex(bindGroups.slots[g].entries[e].buffer.id);
		const block = shaders.slots[s].uniforms[u];
		if (offset + (block.size as int64) > buffers.slots[b].size) {
			stop(`uniform binding ${block.binding} at offset ${offset} overruns its buffer`);
		}
		if (offsetUniforms) {
			if (bound.uniformBuffer[u] == buffers.slots[b].id && bound.uniformFirst[u] == offset) { continue; }
			const constants = roundUp256(block.size as int64) / 16;
			if (constants > MAX_BLOCK_CONSTANTS || offset + constants * 16 > roundUp256(buffers.slots[b].size)) {
				stop(`uniform binding ${block.binding} of ${block.size} bytes at ${offset} does not fit one constant buffer view`);
			}
			for (let vertex = 0; vertex < 2; vertex++) {
				if (!readsStage(block, vertex)) { continue; }
				d3dSetConstantBufferRange(context1, vertex, block.nativeSlot, buffers.slots[b].native, offset / 16, constants);
			}
			bound.uniformBuffer[u] = buffers.slots[b].id;
			bound.uniformFirst[u] = offset;
		} else {
			const bytes = roundUp16(block.size as int64);
			if (offset + bytes > (buffers.slots[b].shadow.length as int64)) {
				stop(`uniform binding ${block.binding} at offset ${offset} overruns its buffer`);
			}
			d3dUpdateIfChanged(context, shaders.slots[s].constantBuffers[u], shaders.slots[s].blockCache[0], shaders.slots[s].cacheOffset[u] as int64, buffers.slots[b].shadow[0], offset, bytes, shaders.slots[s].cacheFresh[u]);
			shaders.slots[s].cacheFresh[u] = 0;
		}
	}
}
