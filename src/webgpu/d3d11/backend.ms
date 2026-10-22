import {
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
	checkedMapRange,
	checkedTexelBufferLayout,
	checkedTexelCopyRegion,
	checkedTexelWritePitch,
	featureBit,
	stopOnUnportedShaderBindings,
} from "../types.ms";
import {
	D3dBlobImpl,
	D3dBlendStateImpl,
	D3dBufferImpl,
	D3dComputeShaderImpl,
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
	d3dBlendTarget,
	d3dClearDsv,
	d3dClearRtv,
	d3dClearState,
	d3dCompile,
	d3dCompileLog,
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
	d3dReleaseComputeShader,
	d3dReleaseUav,
	d3dCreateDepthStencilState,
	d3dCreateDsv,
	d3dCreateInputLayout,
	d3dCreatePixelShader,
	d3dCreateQuery,
	d3dCreateRasterizerState,
	d3dCreateRtv,
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
	d3dInputElement,
	d3dMapWrite,
	d3dOmSetBlendState,
	d3dOmSetDepthStencilState,
	d3dPsSetConstantBuffer,
	d3dPsSetSampler,
	d3dPsSetShader,
	d3dPsSetShaderResource,
	d3dReadBuffer,
	d3dReleaseBlendState,
	d3dReleaseBlob,
	d3dReleaseBuffer,
	d3dReleaseDepthStencilState,
	d3dReleaseDsv,
	d3dReleaseInputLayout,
	d3dReleasePixelShader,
	d3dQueryBegin,
	d3dQueryEnd,
	d3dQueryFrequency,
	d3dQuerySupported,
	d3dQueryTicks,
	d3dReleaseAnnotation,
	d3dReleaseQuery,
	d3dReleaseRasterizerState,
	d3dReleaseRtv,
	d3dReleaseSampler,
	d3dReleaseSrv,
	d3dReleaseTexture,
	d3dReleaseVertexShader,
	d3dResolveSubresource,
	d3dResolveViews,
	d3dRsSetState,
	d3dRtvFrom,
	d3dSetRenderTargets,
	d3dSetMarker,
	d3dSetName,
	d3dSetScissorRect,
	d3dTicksToNanoseconds,
	d3dSetViewport,
	d3dTextureNative,
	d3dUpdateBuffer,
	d3dUpdateIfChanged,
	d3dUpdateTexture,
	d3dUniformOffsetting,
	d3dReleaseUniformOffsetting,
	d3dVsSetConstantBufferRange,
	d3dPsSetConstantBufferRange,
	d3dVsSetConstantBuffer,
	d3dVsSetSampler,
	d3dVsSetShader,
	d3dVsSetShaderResource,
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

const SLOT_SHIFT = 16;
const SLOT_MASK = 0xFFFF;
const UNIFORM_OFFSET_ALIGNMENT = 256;
const MAX_BLOCK_CONSTANTS = 4096;
const MAX_STAGE_CONSTANT_BUFFERS = 14;
const MAX_STAGE_SHADER_RESOURCES = 128;
const MAX_STAGE_SAMPLERS = 16;
const MAX_STAGE_UNORDERED_ACCESS_VIEWS = 8;
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
const MAX_QUERY_COUNT = 4096;
const QUERY_OCCLUSION = 0;
const QUERY_TIMESTAMP = 1;
const QUERY_DISJOINT = 2;
const QUERY_UNWRITTEN: uint8 = 0;
const QUERY_OPEN: uint8 = 1;
const QUERY_WRITTEN: uint8 = 2;
const RESOLVE_OFFSET_ALIGNMENT = 256;
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
const MAX_ANISOTROPY = 16;
const COMPARISON_NEVER = 1;
const DEFAULT_LOD_MAX_CLAMP = 32.0;
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
const NO_COMPUTE = null as unknown as Ptr<D3dComputeShaderImpl>;
const NO_QUERY = null as unknown as Ptr<D3dQueryImpl>;

enum BindingKind {
	Uniform,
	Texture,
	Sampler,
	StorageBuffer,
	StorageTexture,
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

struct SlotQueue {
	free: Vec<int32>;
	generations: Vec<uint32>;
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
	baseLayer: int32;
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
	computeStage: boolean;
	writable: boolean;
	nativeSlot: int32;
	size: int32;
}

struct ShaderSlot {
	id: uint32;
	vertex: Ptr<D3dVertexShaderImpl>;
	fragment: Ptr<D3dPixelShaderImpl>;
	compute: Ptr<D3dComputeShaderImpl>;
	computeEntry: string;
	vertexBlob: Ptr<D3dBlobImpl>;
	uniforms: NativeBinding[8];
	uniformCount: int32;
	constantBuffers: Ptr<D3dBufferImpl>[8];
	blockCache: Vec<uint8>;
	cacheOffset: int32[8];
	cacheFresh: int32[8];
	resources: NativeBinding[8];
	resourceCount: int32;
	attributes: GPUShaderAttribute[16];
}

struct PipelineSlot {
	id: uint32;
	shader: uint32;
	rasterizer: Ptr<D3dRasterizerStateImpl>;
	depthStencil: Ptr<D3dDepthStencilStateImpl>;
	blend: Ptr<D3dBlendStateImpl>;
	inputLayout: Ptr<D3dInputLayoutImpl>;
	strides: int32[2];
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
	entries: GPUBindGroupEntry[8];
	srv: Ptr<D3dSrvImpl>[8];
	uav: Ptr<D3dUavImpl>[8];
	entryCount: int32;
	dynamicIndex: int32[8];
	dynamicCount: int32;
}

struct QuerySetSlot {
	id: uint32;
	timestamp: boolean;
	count: int32;
	queries: Vec<Ptr<D3dQueryImpl>>;
	state: Vec<uint8>;
	usedPass: Vec<int64>;
	disjoint: Ptr<D3dQueryImpl>;
	disjointOpen: boolean;
	frequency: uint64;
}

struct PassState {
	active: boolean;
	serial: int64;
	labeled: boolean;
	groupBase: int32;
	timestampSet: uint32;
	timestampEnd: int32;
	occlusionSet: uint32;
	occlusionOpen: boolean;
	occlusionIndex: int32;
	width: int32;
	height: int32;
	colorViews: uint32[4];
	resolveViews: uint32[4];
}

struct ComputeState {
	active: boolean;
	labeled: boolean;
	groupBase: int32;
	timestampSet: uint32;
	timestampEnd: int32;
	pipeline: uint32;
	bindGroup: uint32;
	dirty: boolean;
}

struct BoundState {
	pipeline: uint32;
	appliedPipeline: uint32;
	vertexBuffers: uint32[2];
	vertexOffsets: int64[2];
	indexBuffer: uint32;
	indexFormat: int32;
	indexOffset: int64;
	bindGroups: uint32[2];
	dynamicOffsets: uint32[8];
	vertexDirty: boolean;
	indexDirty: boolean;
	resourcesDirty: boolean;
	uniformsDirty: boolean;
	uniformBuffer: uint32[8];
	uniformFirst: int64[8];
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
	vertexBuffer: Ptr<D3dBufferImpl>[2];
	vertexStride: int32[2];
	vertexOffset: int32[2];
	indexBuffer: Ptr<D3dBufferImpl>;
	indexFormat: int32;
	indexOffset: int32;
	vertexShaderResource: Ptr<D3dSrvImpl>[128];
	fragmentShaderResource: Ptr<D3dSrvImpl>[128];
	vertexSampler: Ptr<D3dSamplerImpl>[16];
	fragmentSampler: Ptr<D3dSamplerImpl>[16];
}

let device: Ptr<D3dDeviceImpl> = null as unknown as Ptr<D3dDeviceImpl>;
let context: Ptr<D3dContextImpl> = null as unknown as Ptr<D3dContextImpl>;
let offsetUniforms = false;
let frame: int64 = 0;
let passSerial: int64 = 0;
let groupDepth: int32 = 0;
let pass: PassState = { active: false };
let bound: BoundState = { pipeline: 0 };
let computeBound: ComputeState = { active: false };
let nativeBinds: NativeBinds = { indexFormat: 0 };
let stats: BindStats = { vertexBuffers: 0 };
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let canvas: GPUCanvasConfiguration = { format: "bgra8unorm", depthFormat: "depth32float", sampleCount: 1 };

let bufferQueue: SlotQueue = { free: [], generations: [] };
let textureQueue: SlotQueue = { free: [], generations: [] };
let viewQueue: SlotQueue = { free: [], generations: [] };
let samplerQueue: SlotQueue = { free: [], generations: [] };
let shaderQueue: SlotQueue = { free: [], generations: [] };
let pipelineQueue: SlotQueue = { free: [], generations: [] };
let layoutQueue: SlotQueue = { free: [], generations: [] };
let querySetQueue: SlotQueue = { free: [], generations: [] };
let bindGroupQueue: SlotQueue = { free: [], generations: [] };

let buffers: Vec<BufferSlot> = [];
let textures: Vec<TextureSlot> = [];
let views: Vec<ViewSlot> = [];
let samplers: Vec<SamplerSlot> = [];
let shaders: Vec<ShaderSlot> = [];
let pipelines: Vec<PipelineSlot> = [];
let layouts: Vec<LayoutSlot> = [];
let querySets: Vec<QuerySetSlot> = [];
let bindGroups: Vec<BindGroupSlot> = [];

function stop(message: string): void {
	console.log(`webgpu d3d11: ${message}`);
	unreachable;
}

function stopOnMember(member: string, value: string): int32 {
	console.log(`webgpu d3d11: ${member} '${value}' is not supported`);
	unreachable;
}

function stopOnFormat(member: string, value: string): FormatInfo {
	console.log(`webgpu d3d11: ${member} '${value}' is not supported`);
	unreachable;
}

function stopOnHandle(kind: string, id: uint32): int32 {
	console.log(`webgpu d3d11: ${kind} ${id} is not a live handle`);
	unreachable;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

@inline function roundUp16(bytes: int64): int64 { return (bytes + 15) & ~(15 as int64); }

@inline function roundUp256(bytes: int64): int64 { return (bytes + 255) & ~(255 as int64); }

function forgetNativeBinds(): void {
	for (let i = 0; i < GPU_MAX_VERTEX_BUFFERS; i++) {
		nativeBinds.vertexBuffer[i] = NO_BUFFER;
		nativeBinds.vertexStride[i] = 0;
		nativeBinds.vertexOffset[i] = 0;
	}
	nativeBinds.indexBuffer = NO_BUFFER;
	for (let i = 0; i < MAX_STAGE_SHADER_RESOURCES; i++) {
		nativeBinds.vertexShaderResource[i] = NO_SRV;
		nativeBinds.fragmentShaderResource[i] = NO_SRV;
	}
	for (let i = 0; i < MAX_STAGE_SAMPLERS; i++) {
		nativeBinds.vertexSampler[i] = NO_SAMPLER;
		nativeBinds.fragmentSampler[i] = NO_SAMPLER;
	}
}

export function bindStats(): BindStats { return stats; }

function forgetAppliedUniforms(): void {
	for (let u = 0; u < GPU_MAX_UNIFORM_BLOCKS; u++) { bound.uniformBuffer[u] = 0; }
}

function allocateId(ref queue: SlotQueue, what: string): uint32 {
	let index: int32 = 0;
	if (queue.free.length > 0) {
		index = queue.free[queue.free.length - 1];
		queue.free.pop();
	} else {
		if (queue.generations.length == 0) { queue.generations.push(0); }
		index = queue.generations.length as int32;
		if (index > SLOT_MASK) {
			console.error(`webgpu d3d11: ${what} pool exhausted (65535 live handles)`);
			return 0;
		}
		queue.generations.push(0);
	}
	queue.generations[index] += 1;
	return (queue.generations[index] << SLOT_SHIFT) | (index as uint32);
}

function releaseId(ref queue: SlotQueue, id: uint32): void {
	queue.free.push((id & SLOT_MASK) as int32);
}

@inline function slotOf(id: uint32): int32 { return (id & SLOT_MASK) as int32; }

function bufferIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= buffers.length || buffers[index].id != id) {
		return stopOnHandle("GPUBuffer", id);
	}
	return index;
}

function textureIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= textures.length || textures[index].id != id) {
		return stopOnHandle("GPUTexture", id);
	}
	return index;
}

function viewIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= views.length || views[index].id != id) {
		return stopOnHandle("GPUTextureView", id);
	}
	return index;
}

function samplerIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= samplers.length || samplers[index].id != id) {
		return stopOnHandle("GPUSampler", id);
	}
	return index;
}

function shaderIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= shaders.length || shaders[index].id != id) {
		return stopOnHandle("GPUShaderModule", id);
	}
	return index;
}

function pipelineIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= pipelines.length || pipelines[index].id != id) {
		return stopOnHandle("GPURenderPipeline", id);
	}
	return index;
}

function querySetIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= querySets.length || querySets[index].id != id) {
		return stopOnHandle("GPUQuerySet", id);
	}
	return index;
}

function layoutIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= layouts.length || layouts[index].id != id) {
		return stopOnHandle("GPUBindGroupLayout", id);
	}
	return index;
}

function bindGroupIndex(id: uint32): int32 {
	const index = slotOf(id);
	if (id == 0 || index >= bindGroups.length || bindGroups[index].id != id) {
		return stopOnHandle("GPUBindGroup", id);
	}
	return index;
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

function linearFilter(filter: string, member: string): boolean {
	const value = match (filter) {
		"" | "nearest" => 0,
		"linear" => 1,
		_ => stopOnMember(member, filter),
	};
	return value == 1;
}

function indexFormat(format: GPUIndexFormat): int32 {
	const value: string = format;
	return match (value) {
		"uint16" => DXGI_R16_UINT,
		"uint32" => DXGI_R32_UINT,
		_ => stopOnMember("setIndexBuffer indexFormat", value),
	};
}

function bindingKind(kind: string): BindingKind {
	return match (kind) {
		"uniform" => BindingKind.Uniform,
		"texture" => BindingKind.Texture,
		"sampler" => BindingKind.Sampler,
		"storage-buffer" => BindingKind.StorageBuffer,
		"storage-texture" => BindingKind.StorageTexture,
		_ => stopOnMember("GPUShaderBinding.kind", kind) as BindingKind,
	};
}

function vertexStage(stage: string): boolean {
	const value = match (stage) {
		"vertex" => 1,
		"fragment" => 0,
		"compute" => 0,
		_ => stopOnMember("GPUShaderBinding.stage", stage),
	};
	return value == 1;
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device === null || environment.context === null) {
		stop("requestDevice needs the native ID3D11Device and ID3D11DeviceContext");
	}
	device = d3dDeviceFrom(environment.device);
	context = d3dContextFrom(environment.context);
	frame = 0;
	passSerial = 0;
	groupDepth = 0;
	pass = { active: false };
	bound = { pipeline: 0 };
	computeBound = { active: false };
	offsetUniforms = d3dUniformOffsetting(device, context) != 0;
	buffers = [{ id: 0 }];
	textures = [{ id: 0 }];
	views = [{ id: 0 }];
	samplers = [{ id: 0 }];
	shaders = [{ id: 0 }];
	pipelines = [{ id: 0 }];
	layouts = [{ id: 0 }];
	querySets = [{ id: 0 }];
	bindGroups = [{ id: 0 }];
	bufferQueue = { free: [], generations: [] };
	textureQueue = { free: [], generations: [] };
	viewQueue = { free: [], generations: [] };
	samplerQueue = { free: [], generations: [] };
	shaderQueue = { free: [], generations: [] };
	pipelineQueue = { free: [], generations: [] };
	layoutQueue = { free: [], generations: [] };
	querySetQueue = { free: [], generations: [] };
	bindGroupQueue = { free: [], generations: [] };
	canvas = canvasOf(environment);
	swapchainColor = reserveSwapchainTexture(canvas.format);
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
	let counts: GPULiveCounts = { buffers: 0 };
	for (let i = 1; i < buffers.length; i++) { if (buffers[i].id != 0) { counts.buffers += 1; } }
	for (let i = 1; i < textures.length; i++) {
		if (textures[i].id != 0 && textures[i].swapchainView == 0) { counts.textures += 1; }
	}
	for (let i = 1; i < views.length; i++) { if (views[i].id != 0 && !views[i].swapchain) { counts.views += 1; } }
	for (let i = 1; i < samplers.length; i++) { if (samplers[i].id != 0) { counts.samplers += 1; } }
	for (let i = 1; i < shaders.length; i++) { if (shaders[i].id != 0) { counts.shaderModules += 1; } }
	for (let i = 1; i < pipelines.length; i++) { if (pipelines[i].id != 0) { counts.pipelines += 1; } }
	return counts;
}

export function bufferAlive(buffer: GPUBuffer): boolean {
	const index = slotOf(buffer.id);
	return buffer.id != 0 && index < buffers.length && buffers[index].id == buffer.id;
}

export function textureAlive(texture: GPUTexture): boolean {
	const index = slotOf(texture.id);
	return texture.id != 0 && index < textures.length && textures[index].id == texture.id;
}

export function viewAlive(view: GPUTextureView): boolean {
	const index = slotOf(view.id);
	return view.id != 0 && index < views.length && views[index].id == view.id;
}

export function samplerAlive(sampler: GPUSampler): boolean {
	const index = slotOf(sampler.id);
	return sampler.id != 0 && index < samplers.length && samplers[index].id == sampler.id;
}

function reserveSwapchainTexture(format: GPUTextureFormat): uint32 {
	const textureId = allocateId(textureQueue, "texture");
	const viewId = allocateId(viewQueue, "view");
	if (textureId == 0 || viewId == 0) { stop("the swapchain texture and view found their pools exhausted"); }
	textures.push({
		id: textureId,
		format: format,
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
		swapchainView: viewId,
	});
	views.push({ id: viewId, texture: textureId, swapchain: true });
	return textureId;
}

export function shutdown(): void {
	if (pass.active) { stop("shutdown with a render pass still open"); }
	d3dClearState(context);
	d3dReleaseUniformOffsetting();
	d3dReleaseAnnotation();
	for (let i = 1; i < querySets.length; i++) {
		if (querySets[i].id != 0) { destroyQuerySet({ id: querySets[i].id }); }
	}
	for (let i = 1; i < bindGroups.length; i++) {
		if (bindGroups[i].id != 0) { destroyBindGroup({ id: bindGroups[i].id }); }
	}
	for (let i = 1; i < pipelines.length; i++) {
		if (pipelines[i].id != 0) { destroyRenderPipeline({ id: pipelines[i].id }); }
	}
	for (let i = 1; i < shaders.length; i++) {
		if (shaders[i].id != 0) { destroyShaderModule({ id: shaders[i].id }); }
	}
	for (let i = 1; i < samplers.length; i++) {
		if (samplers[i].id != 0) { destroySampler({ id: samplers[i].id }); }
	}
	for (let i = 1; i < views.length; i++) {
		if (views[i].id != 0 && !views[i].swapchain) { destroyView({ id: views[i].id }); }
	}
	for (let i = 1; i < textures.length; i++) {
		if (textures[i].id != 0 && textures[i].swapchainView == 0) { destroyTexture({ id: textures[i].id }); }
	}
	for (let i = 1; i < buffers.length; i++) {
		if (buffers[i].id != 0) { destroyBuffer({ id: buffers[i].id }); }
	}
	buffers = [];
	textures = [];
	views = [];
	samplers = [];
	shaders = [];
	pipelines = [];
	layouts = [];
	querySets = [];
	bindGroups = [];
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "d3d11", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const id = allocateId(bufferQueue, "buffer");
	if (id == 0) { return { id: 0 }; }
	const usage = descriptor.usage;
	if (descriptor.size <= 0) { stop("GPUBufferDescriptor.size must be positive"); }
	const mapRead = has(usage, GPUBufferUsage.MAP_READ as int32);
	const mapWrite = has(usage, GPUBufferUsage.MAP_WRITE as int32);
	if (mapRead && usage != ((GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32))) {
		stop("GPUBufferUsage MAP_READ combines only with COPY_DST");
	}
	if (mapWrite && usage != ((GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32))) {
		stop("GPUBufferUsage MAP_WRITE combines only with COPY_SRC");
	}
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
	storeBuffer(slot);
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
	if ((float32 & 1) != 0) { bits |= featureBit("float32-filterable"); }
	if ((float32 & 4) != 0) { bits |= featureBit("float32-blendable"); }
	if ((formatCaps("rg11b10ufloat") & 2) != 0) { bits |= featureBit("rg11b10ufloat-renderable"); }
	return { bits: bits };
}

export function pushDebugGroup(label: string): void {
	d3dBeginEvent(context, label);
	groupDepth += 1;
}

export function popDebugGroup(): void {
	const base = pass.active ? pass.groupBase : (computeBound.active ? computeBound.groupBase : 0);
	if (groupDepth <= base) { stop("popDebugGroup without a matching pushDebugGroup"); }
	d3dEndEvent(context);
	groupDepth -= 1;
}

export function insertDebugMarker(label: string): void { d3dSetMarker(context, label); }

function labelPass(label: string | null): boolean {
	if (label === null) { return false; }
	d3dBeginEvent(context, label);
	return true;
}

function checkGroupsClosed(base: int32, what: string): void {
	if (groupDepth != base) { stop(`${what} with ${groupDepth - base} debug groups still open`); }
}

export function createQuerySet(descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	const kind: string = descriptor.type;
	if (kind != "timestamp" && kind != "occlusion") { stopOnMember("GPUQuerySetDescriptor.type", kind); }
	const timestamp = kind == "timestamp";
	if (descriptor.count < 1 || descriptor.count > MAX_QUERY_COUNT) {
		stop(`GPUQuerySetDescriptor.count ${descriptor.count} is outside 1..${MAX_QUERY_COUNT}`);
	}
	if (timestamp && !supportsTimestamps()) { stop("this device has no timestamp queries: features().has('timestamp-query') is false"); }
	const id = allocateId(querySetQueue, "query set");
	if (id == 0) { return { id: 0 }; }
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
	const index = slotOf(id);
	if (index < querySets.length) { querySets[index] = slot; } else { querySets.push(slot); }
	return { id: id };
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	const index = querySetIndex(querySet.id);
	for (let i = 0; i < querySets[index].queries.length; i++) { d3dReleaseQuery(querySets[index].queries[i]); }
	d3dReleaseQuery(querySets[index].disjoint);
	querySets[index] = { id: 0 };
	releaseId(querySetQueue, querySet.id);
}

function writeTimestamp(querySet: uint32, queryIndex: int32): void {
	const q = querySetIndex(querySet);
	if (!querySets[q].disjointOpen) {
		d3dQueryBegin(context, querySets[q].disjoint);
		querySets[q].disjointOpen = true;
	}
	d3dQueryEnd(context, querySets[q].queries[queryIndex]);
	querySets[q].state[queryIndex] = QUERY_WRITTEN;
}

function checkTimestampWrites(member: string, writes: GPUPassTimestampWrites): void {
	if (writes.querySet.id == 0) { return; }
	const q = querySetIndex(writes.querySet.id);
	if (!querySets[q].timestamp) { stop(`${member}.querySet is an occlusion set: a timestamp set is required`); }
	const begin = writes.beginningOfPassWriteIndex;
	const end = writes.endOfPassWriteIndex;
	if (begin == end) {
		stop(`${member} writes index ${begin} at both ends: give each end its own index, or -1 (GPU_NO_QUERY_INDEX) to skip one`);
	}
	if (begin < -1 || begin >= querySets[q].count || end < -1 || end >= querySets[q].count) {
		stop(`${member} indices ${begin} and ${end} are outside the query set of ${querySets[q].count}`);
	}
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	if (pass.active || computeBound.active) { stop("resolveQuerySet inside a pass"); }
	const q = querySetIndex(querySet.id);
	if (firstQuery < 0 || queryCount < 0 || firstQuery + queryCount > querySets[q].count) {
		stop(`resolveQuerySet ${firstQuery}+${queryCount} overruns the query set of ${querySets[q].count}`);
	}
	const b = bufferIndex(destination.id);
	if (!has(buffers[b].usage, GPUBufferUsage.QUERY_RESOLVE as int32)) {
		stop(`resolveQuerySet: GPUBuffer ${destination.id} was created without QUERY_RESOLVE`);
	}
	if (destinationOffset < 0 || destinationOffset % RESOLVE_OFFSET_ALIGNMENT != 0) {
		stop(`resolveQuerySet destinationOffset ${destinationOffset} is not a multiple of ${RESOLVE_OFFSET_ALIGNMENT}`);
	}
	const bytes = (queryCount as int64) * 8;
	if (destinationOffset + bytes > buffers[b].size) {
		stop(`resolveQuerySet of ${bytes} bytes at ${destinationOffset} overruns GPUBuffer ${destination.id} of ${buffers[b].size}`);
	}
	if (queryCount == 0) { return; }
	for (let i = 0; i < queryCount; i++) {
		const state = querySets[q].state[firstQuery + i];
		if (state == QUERY_UNWRITTEN) { stop(`resolveQuerySet: query ${firstQuery + i} was never written`); }
		if (state == QUERY_OPEN) { stop(`resolveQuerySet: query ${firstQuery + i} is still open`); }
	}
	if (querySets[q].disjointOpen) {
		d3dQueryEnd(context, querySets[q].disjoint);
		querySets[q].disjointOpen = false;
		let frequency: uint64 = 0;
		const status = d3dQueryFrequency(context, querySets[q].disjoint, frequency);
		if (status == 0) { stop("the timestamp frequency never arrived from the GPU"); }
		if (status < 0) { stop("the GPU clock was disjoint while the timestamps were written: the values are unreliable"); }
		querySets[q].frequency = frequency;
	}
	let values: Vec<uint64> = new Array(queryCount);
	for (let i = 0; i < queryCount; i++) {
		let ticks: uint64 = 0;
		if (d3dQueryTicks(context, querySets[q].queries[firstQuery + i], ticks) == 0) {
			stop(`query ${firstQuery + i} never arrived from the GPU`);
		}
		values[i] = querySets[q].timestamp ? d3dTicksToNanoseconds(ticks, querySets[q].frequency) : ticks;
	}
	d3dUpdateBuffer(context, buffers[b].native, destinationOffset, values[0], bytes);
}

export function beginOcclusionQuery(queryIndex: int32): void {
	if (!pass.active) { stop("beginOcclusionQuery outside a render pass"); }
	if (pass.occlusionSet == 0) { stop("beginOcclusionQuery needs GPURenderPassDescriptor.occlusionQuerySet"); }
	if (pass.occlusionOpen) { stop("beginOcclusionQuery with an occlusion query already open"); }
	const q = querySetIndex(pass.occlusionSet);
	if (queryIndex < 0 || queryIndex >= querySets[q].count) {
		stop(`beginOcclusionQuery index ${queryIndex} is outside the query set of ${querySets[q].count}`);
	}
	if (querySets[q].usedPass[queryIndex] == pass.serial) {
		stop(`beginOcclusionQuery index ${queryIndex} was already used in this pass`);
	}
	querySets[q].usedPass[queryIndex] = pass.serial;
	querySets[q].state[queryIndex] = QUERY_OPEN;
	d3dQueryBegin(context, querySets[q].queries[queryIndex]);
	pass.occlusionOpen = true;
	pass.occlusionIndex = queryIndex;
}

export function endOcclusionQuery(): void {
	if (!pass.active || !pass.occlusionOpen) { stop("endOcclusionQuery without an open occlusion query"); }
	const q = querySetIndex(pass.occlusionSet);
	d3dQueryEnd(context, querySets[q].queries[pass.occlusionIndex]);
	querySets[q].state[pass.occlusionIndex] = QUERY_WRITTEN;
	pass.occlusionOpen = false;
}

function storeBuffer(slot: BufferSlot): void {
	const index = slotOf(slot.id);
	if (index < buffers.length) { buffers[index] = slot; } else { buffers.push(slot); }
}

export function destroyBuffer(buffer: GPUBuffer): void {
	const index = bufferIndex(buffer.id);
	d3dReleaseBuffer(buffers[index].native);
	buffers[index] = { id: 0 };
	releaseId(bufferQueue, buffer.id);
}

export function bufferSize(buffer: GPUBuffer): int64 { return buffers[bufferIndex(buffer.id)].size; }

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = writableBuffer(buffer.id, offset, bytes);
	if (buffers[index].staging) { stop(`writeBuffer on GPUBuffer ${buffer.id}, a MAP buffer: write it through mapAsync and writeMappedRange or a copy`); }
	if (buffers[index].updatable) {
		d3dUpdateBuffer(context, buffers[index].native, offset, data[0], bytes);
		return;
	}
	if (buffers[index].writtenFrame == -2) {
		stop(`GPUBuffer ${buffer.id} was created without COPY_DST`);
	}
	const discard = buffers[index].writtenFrame != frame;
	if (discard) {
		buffers[index].writtenFrame = frame;
	} else if (offset < buffers[index].writtenEnd) {
		stop(`writeBuffer at ${offset} on GPUBuffer ${buffer.id} rewrites bytes this frame already wrote, up to ${buffers[index].writtenEnd}`);
	}
	buffers[index].writtenEnd = offset + bytes;
	if (buffers[index].uniform && !offsetUniforms) {
		d3dCopyBytes(buffers[index].shadow[0], offset, data[0], bytes);
		bound.uniformsDirty = true;
		return;
	}
	const mapType = discard ? MAP_WRITE_DISCARD : MAP_WRITE_NO_OVERWRITE;
	if (d3dMapWrite(context, buffers[index].native, mapType, offset, data[0], bytes) == 0) {
		stop(`Map for writeBuffer failed on GPUBuffer ${buffer.id}`);
	}
}

function writableBuffer(id: uint32, offset: int64, bytes: int64): int32 {
	const index = bufferIndex(id);
	if (offset < 0 || offset + bytes > buffers[index].size) {
		stop(`writeBuffer of ${bytes} bytes at ${offset} overruns GPUBuffer ${id} of ${buffers[index].size}`);
	}
	return index;
}

function mipLevelCountOf(descriptor: GPUTextureDescriptor, volume: boolean, layers: int32): int32 {
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

export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture {
	const id = allocateId(textureQueue, "texture");
	if (id == 0) { return { id: 0 }; }
	const info = formatInfo(descriptor.format, "GPUTextureDescriptor.format");
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	if (width <= 0 || height <= 0) { stop("GPUTextureDescriptor.size needs a positive width and height"); }
	const dimension: string = descriptor.dimension;
	if (dimension != "" && dimension != "2d" && dimension != "3d") { stopOnMember("GPUTextureDescriptor.dimension", dimension); }
	const volume = dimension == "3d";
	if (descriptor.size.depthOrArrayLayers < 0) { stop("GPUTextureDescriptor.size.depthOrArrayLayers is negative"); }
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const largestSide = volume ? Math.max(Math.max(width, height), layers) : Math.max(width, height);
	const sideLimit = volume ? MAX_TEXTURE_DIMENSION_3D : MAX_TEXTURE_DIMENSION_2D;
	if (largestSide > sideLimit || (!volume && layers > MAX_TEXTURE_ARRAY_LAYERS)) {
		stop(`GPUTextureDescriptor.size ${width}x${height}x${layers} is over the limits ${sideLimit} per side and ${MAX_TEXTURE_ARRAY_LAYERS} array layers`);
	}
	const mipLevels = mipLevelCountOf(descriptor, volume, layers);
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount != 1 && sampleCount != 4) {
		stopOnMember("GPUTextureDescriptor.sampleCount", `${sampleCount}`);
	}
	if (sampleCount > 1 && (volume || layers > 1 || mipLevels > 1)) {
		stop("a multisampled texture with mips, array layers or a 3d dimension is not ported to d3d11 yet");
	}
	const usage = descriptor.usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const copyDestination = has(usage, GPUTextureUsage.COPY_DST as int32);
	if (attachment && copyDestination) {
		stop("COPY_DST with RENDER_ATTACHMENT has no Void caller: a multisampled target takes no UpdateSubresource");
	}
	if (sampleCount > 1 && !attachment) { stop("a multisampled texture must be a RENDER_ATTACHMENT"); }
	if (volume && (attachment || info.depth)) { stop("a 3d texture as RENDER_ATTACHMENT or with a depth format is not ported to d3d11 yet"); }
	const cube = !volume && layers % 6 == 0 && width == height && has(usage, GPUTextureUsage.TEXTURE_BINDING as int32) && sampleCount == 1;
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
		swapchainView: 0,
	};
	const index = slotOf(id);
	if (index < textures.length) { textures[index] = slot; } else { textures.push(slot); }
	return { id: id };
}

export function destroyTexture(texture: GPUTexture): void {
	const index = textureIndex(texture.id);
	if (textures[index].swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	d3dReleaseTexture(textures[index].native);
	textures[index] = { id: 0 };
	releaseId(textureQueue, texture.id);
}

export function textureWidth(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].width; }
export function textureHeight(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].height; }
export function textureUsage(texture: GPUTexture): int32 { return textures[textureIndex(texture.id)].usage; }
export function textureFormat(texture: GPUTexture): GPUTextureFormat { return textures[textureIndex(texture.id)].format; }

export function nativeTexture(texture: GPUTexture): Ptr<void> {
	return d3dTextureNative(textures[textureIndex(texture.id)].native);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	const index = textureIndex(destination.texture.id);
	const bytes = (data.length as int64) * (sizeof T as int64);
	if (!has(textures[index].usage, GPUTextureUsage.COPY_DST as int32)) {
		stop(`writeTexture on GPUTexture ${textures[index].id}, created without COPY_DST`);
	}
	const bytesPerPixel = formatInfo(textures[index].format, "texture format").bytesPerPixel;
	const mip = destination.mipLevel;
	const mips = textures[index].mipLevels;
	const volume = textures[index].volume;
	const depth = volume && mip >= 0 && mip < mips ? Math.max(1, textures[index].layers >> mip) : textures[index].layers;
	const rowPitch = checkedTexelWritePitch(
		textures[index].width,
		textures[index].height,
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
			textures[index].native,
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
			textures[index].native,
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
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	const index = bufferIndex(buffer.id);
	if (!has(buffers[index].usage, flag)) { stop(`${member}: GPUBuffer ${buffer.id} was created without ${flagName}`); }
	if (buffers[index].mapMode != 0) { stop(`${member}: GPUBuffer ${buffer.id} is mapped`); }
	if (buffers[index].native == null) { stop(`${member}: GPUBuffer ${buffer.id} is a CPU shadow uniform block on d3d11 and cannot be copied`); }
	return index;
}

function copyDestinationBuffer(buffer: GPUBuffer, member: string): int32 {
	const index = copyableBuffer(buffer, member, GPUBufferUsage.COPY_DST as int32, "COPY_DST");
	if (!buffers[index].staging && !buffers[index].updatable) {
		stop(`${member}: GPUBuffer ${buffer.id} is a DYNAMIC VERTEX or INDEX buffer written by writeBuffer and cannot take a GPU copy on d3d11 yet`);
	}
	return index;
}

function copyableTexture(info: GPUTexelCopyTextureInfo, member: string, flag: int32, flagName: string): int32 {
	if (pass.active || computeBound.active) { stop(`${member} inside a pass`); }
	const index = textureIndex(info.texture.id);
	if (!has(textures[index].usage, flag)) { stop(`${member}: GPUTexture ${info.texture.id} was created without ${flagName}`); }
	if (textures[index].sampleCount != 1) { stop(`${member}: GPUTexture ${info.texture.id} is multisampled`); }
	return index;
}

function copyRegion(member: string, info: GPUTexelCopyTextureInfo, index: int32, size: GPUExtent3D): void {
	checkedTexelCopyRegion(
		member,
		textures[index].id,
		textures[index].width,
		textures[index].height,
		textures[index].mipLevels,
		textures[index].layers,
		textures[index].volume,
		info,
		size,
	);
}

function texelCopyBytes(index: int32, member: string): int32 {
	const info = formatInfo(textures[index].format, "texture format");
	if (info.depth) { stop(`${member}: depth or stencil GPUTexture ${textures[index].id} is not ported to d3d11 yet`); }
	if (textures[index].volume) { stop(`${member}: 3d GPUTexture ${textures[index].id} is not ported to d3d11 yet`); }
	return info.bytesPerPixel;
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
	checkedBufferCopy(source.id, buffers[from].size, sourceOffset, destination.id, buffers[to].size, destinationOffset, size);
	if (size == 0) { return; }
	d3dCopyBuffer(context, buffers[to].native, destinationOffset, buffers[from].native, sourceOffset, size);
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToBuffer source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyDestinationBuffer(destination.buffer, "copyTextureToBuffer destination");
	const bytesPerPixel = texelCopyBytes(from, "copyTextureToBuffer source");
	copyRegion("copyTextureToBuffer source", source, from, size);
	const bytesPerRow = checkedTexelBufferLayout("copyTextureToBuffer destination", bytesPerPixel, buffers[to].size, destination, size);
	const rowsPerImage = destination.rowsPerImage == 0 ? size.height : destination.rowsPerImage;
	const mips = textures[from].mipLevels;
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		const copied = d3dCopyTextureToBuffer(
			device,
			context,
			textures[from].native,
			source.mipLevel + (source.origin.z + i) * mips,
			source.origin.x,
			source.origin.y,
			size.width,
			size.height,
			buffers[to].native,
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
	const bytesPerPixel = texelCopyBytes(to, "copyBufferToTexture destination");
	copyRegion("copyBufferToTexture destination", destination, to, size);
	const bytesPerRow = checkedTexelBufferLayout("copyBufferToTexture source", bytesPerPixel, buffers[from].size, source, size);
	const rowsPerImage = source.rowsPerImage == 0 ? size.height : source.rowsPerImage;
	const imageBytes = (bytesPerRow as int64) * (rowsPerImage as int64);
	const rowBytes = size.width * bytesPerPixel;
	let readable = buffers[from].native;
	let offset = source.offset;
	const temporary = !buffers[from].staging;
	if (temporary) {
		const span = imageBytes * ((size.depthOrArrayLayers - 1) as int64) + (bytesPerRow as int64) * ((size.height - 1) as int64) + (rowBytes as int64);
		readable = d3dCreateBuffer(device, span, USAGE_STAGING, 0, CPU_ACCESS_READ | CPU_ACCESS_WRITE, 0);
		if (readable == null) { stop(`CreateBuffer failed for the copy of GPUBuffer ${source.buffer.id}`); }
		d3dCopyBuffer(context, readable, 0, buffers[from].native, offset, span);
		offset = 0;
	}
	const mips = textures[to].mipLevels;
	for (let i = 0; i < size.depthOrArrayLayers; i++) {
		const copied = d3dCopyBufferToTexture(
			context,
			readable,
			offset + imageBytes * (i as int64),
			bytesPerRow,
			rowBytes,
			textures[to].native,
			destination.mipLevel + (destination.origin.z + i) * mips,
			destination.origin.x,
			destination.origin.y,
			size.width,
			size.height,
		);
		if (copied == 0) { stop(`copyBufferToTexture failed on GPUTexture ${destination.texture.id}`); }
	}
	if (temporary) { d3dReleaseBuffer(readable); }
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	const from = copyableTexture(source, "copyTextureToTexture source", GPUTextureUsage.COPY_SRC as int32, "COPY_SRC");
	const to = copyableTexture(destination, "copyTextureToTexture destination", GPUTextureUsage.COPY_DST as int32, "COPY_DST");
	const fromFormat: string = textures[from].format;
	const toFormat: string = textures[to].format;
	if (fromFormat != toFormat) { stop(`copyTextureToTexture between formats '${fromFormat}' and '${toFormat}'`); }
	if (textures[from].volume != textures[to].volume) { stop("copyTextureToTexture between a 3d and a 2d GPUTexture"); }
	copyRegion("copyTextureToTexture source", source, from, size);
	copyRegion("copyTextureToTexture destination", destination, to, size);
	const mipWidth = Math.max(1, textures[from].width >> source.mipLevel);
	const mipHeight = Math.max(1, textures[from].height >> source.mipLevel);
	if (formatInfo(textures[from].format, "texture format").depth && (size.width != mipWidth || size.height != mipHeight)) {
		stop(`copyTextureToTexture of depth GPUTexture ${source.texture.id} copies whole mips only on d3d11`);
	}
	if (
		from == to && source.mipLevel == destination.mipLevel
			&& source.origin.z < destination.origin.z + size.depthOrArrayLayers && destination.origin.z < source.origin.z + size.depthOrArrayLayers
			&& source.origin.x < destination.origin.x + size.width && destination.origin.x < source.origin.x + size.width
			&& source.origin.y < destination.origin.y + size.height && destination.origin.y < source.origin.y + size.height
	) {
		stop(`copyTextureToTexture regions overlap inside mip ${source.mipLevel} of GPUTexture ${source.texture.id}`);
	}
	if (textures[from].volume) {
		d3dCopyTexture(
			context,
			textures[to].native,
			destination.mipLevel,
			destination.origin.x,
			destination.origin.y,
			destination.origin.z,
			textures[from].native,
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
			textures[to].native,
			destination.mipLevel + (destination.origin.z + i) * textures[to].mipLevels,
			destination.origin.x,
			destination.origin.y,
			0,
			textures[from].native,
			source.mipLevel + (source.origin.z + i) * textures[from].mipLevels,
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
	const index = bufferIndex(buffer.id);
	const read = mode == (GPUMapMode.READ as int32);
	if (!read && mode != (GPUMapMode.WRITE as int32)) { stop(`mapAsync mode ${mode} is not GPUMapMode READ or WRITE`); }
	const need = read ? GPUBufferUsage.MAP_READ as int32 : GPUBufferUsage.MAP_WRITE as int32;
	if (!has(buffers[index].usage, need)) { stop(`mapAsync ${read ? "READ" : "WRITE"} on GPUBuffer ${buffer.id}, created without ${read ? "MAP_READ" : "MAP_WRITE"}`); }
	if (buffers[index].mapMode != 0) { stop(`mapAsync on GPUBuffer ${buffer.id}, which is already mapped`); }
	const length = checkedMapRange("mapAsync", buffer.id, buffers[index].size, offset, size);
	buffers[index].mapMode = mode;
	buffers[index].mapOffset = offset;
	buffers[index].mapSize = length;
}

function mappedRange(member: string, buffer: GPUBuffer, mode: int32, offset: int64, size: int64): int64 {
	const index = bufferIndex(buffer.id);
	if (buffers[index].mapMode != mode) { stop(`${member} on GPUBuffer ${buffer.id}, which is not mapped for ${mode == 1 ? "READ" : "WRITE"}`); }
	const length = checkedMapRange(member, buffer.id, buffers[index].size, offset, size == 0 ? buffers[index].mapOffset + buffers[index].mapSize - offset : size);
	if (offset < buffers[index].mapOffset || offset + length > buffers[index].mapOffset + buffers[index].mapSize) {
		stop(`${member} of ${length} bytes at ${offset} leaves the mapped range ${buffers[index].mapOffset}..${buffers[index].mapOffset + buffers[index].mapSize} of GPUBuffer ${buffer.id}`);
	}
	return length;
}

// A copy of the mapped bytes: WebGPU's ArrayBuffer view has no MetaScript counterpart on a native pointer.
export function getMappedRange(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	const length = mappedRange("getMappedRange", buffer, GPUMapMode.READ as int32, offset, size);
	let bytes: Vec<uint8> = new Array(length);
	if (d3dReadBuffer(context, buffers[bufferIndex(buffer.id)].native, offset, bytes[0], length) == 0) {
		stop(`Map for getMappedRange failed on GPUBuffer ${buffer.id}`);
	}
	return bytes;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	mappedRange("writeMappedRange", buffer, GPUMapMode.WRITE as int32, offset, bytes);
	if (d3dMapWrite(context, buffers[bufferIndex(buffer.id)].native, MAP_WRITE, offset, data[0], bytes) == 0) {
		stop(`Map for writeMappedRange failed on GPUBuffer ${buffer.id}`);
	}
}

export function unmap(buffer: GPUBuffer): void {
	const index = bufferIndex(buffer.id);
	if (buffers[index].mapMode == 0) { stop(`unmap on GPUBuffer ${buffer.id}, which is not mapped`); }
	buffers[index].mapMode = 0;
}

function viewDimensionOf(descriptor: GPUTextureViewDescriptor, t: int32): int32 {
	let name: string = descriptor.dimension;
	if (name == "") { name = textures[t].volume ? "3d" : (textures[t].layers > 1 ? "2d-array" : "2d"); }
	if ((name == "3d") != textures[t].volume) {
		stop(`GPUTextureViewDescriptor.dimension '${name}' does not match the ${textures[t].volume ? "3d" : "2d"} GPUTexture ${textures[t].id}`);
	}
	if (name == "2d") { return VIEW_2D; }
	if (name == "2d-array") { return VIEW_2D_ARRAY; }
	if (name == "cube") { return VIEW_CUBE; }
	if (name == "cube-array") { return VIEW_CUBE_ARRAY; }
	if (name == "3d") { return VIEW_3D; }
	return stopOnMember("GPUTextureViewDescriptor.dimension", name);
}

export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const t = textureIndex(texture.id);
	if (textures[t].swapchainView != 0) { return { id: textures[t].swapchainView }; }
	const id = allocateId(viewQueue, "view");
	if (id == 0) { return { id: 0 }; }
	const info = formatInfo(textures[t].format, "texture format");
	const multisampled = textures[t].sampleCount > 1 ? 1 : 0;
	const usage = textures[t].usage;
	const attachment = has(usage, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	const layers = textures[t].layers;
	const baseMip = descriptor.baseMipLevel;
	const mipCount = descriptor.mipLevelCount == 0 ? textures[t].mipLevels - baseMip : descriptor.mipLevelCount;
	if (baseMip < 0 || mipCount < 1 || baseMip + mipCount > textures[t].mipLevels) {
		stop(`view mips ${baseMip}+${mipCount} overrun GPUTexture ${textures[t].id}, which has ${textures[t].mipLevels} mips`);
	}
	let dimension = viewDimensionOf(descriptor, t);
	let baseLayer = descriptor.baseArrayLayer;
	let layerCount = descriptor.arrayLayerCount;
	if (dimension == VIEW_3D) {
		if (baseLayer != 0 || layerCount > 1) { stop("a 3d view takes no baseArrayLayer or arrayLayerCount"); }
		baseLayer = 0;
		layerCount = 1;
	} else {
		if (dimension == VIEW_2D) { layerCount = 1; }
		if (dimension == VIEW_CUBE) { layerCount = 6; }
		if (layerCount == 0) { layerCount = layers - baseLayer; }
		if (baseLayer < 0 || layerCount < 1 || baseLayer + layerCount > layers) {
			stop(`view layers ${baseLayer}+${layerCount} overrun GPUTexture ${textures[t].id}, which has ${layers} layers`);
		}
	}
	if (dimension == VIEW_CUBE || dimension == VIEW_CUBE_ARRAY) {
		if (!textures[t].cube) {
			stop(`a cube view needs GPUTexture ${textures[t].id} created square, with TEXTURE_BINDING and a depthOrArrayLayers multiple of 6`);
		}
		if (layerCount % 6 != 0 || baseLayer % 6 != 0) { stop("a cube view takes whole cubes: baseArrayLayer and arrayLayerCount multiples of 6"); }
		if (dimension == VIEW_CUBE && baseLayer != 0) { stop("a cube view at baseArrayLayer above 0 is not ported to d3d11 yet"); }
	}
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
		baseLayer: baseLayer,
		swapchain: false,
	};
	const native = textures[t].native;
	if (has(usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
		if (dimension == VIEW_2D && baseLayer > 0) { dimension = VIEW_2D_ARRAY; }
		slot.shaderResource = d3dCreateSrv(device, native, info.shaderResource, multisampled, dimension, baseMip, mipCount, baseLayer, layerCount);
		if (slot.shaderResource == null) { stop(`CreateShaderResourceView failed for ${labelOf(descriptor.label)}`); }
	}
	if (has(usage, GPUTextureUsage.STORAGE_BINDING as int32) && mipCount == 1) {
		const uavDimension = textures[t].volume ? VIEW_3D : (layers > 1 ? VIEW_2D_ARRAY : VIEW_2D);
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
	const index = slotOf(slot.id);
	if (index < views.length) { views[index] = slot; } else { views.push(slot); }
	return { id: slot.id };
}

export function destroyView(view: GPUTextureView): void {
	const index = viewIndex(view.id);
	if (views[index].swapchain) { return; }
	d3dReleaseSrv(views[index].shaderResource);
	d3dReleaseUav(views[index].unordered);
	d3dReleaseRtv(views[index].renderTarget);
	d3dReleaseDsv(views[index].depthStencil);
	views[index] = { id: 0 };
	releaseId(viewQueue, view.id);
}

export function viewTexture(view: GPUTextureView): GPUTexture { return { id: views[viewIndex(view.id)].texture }; }

export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture {
	if (swapchain.renderView === null) { stop("the native swapchain has no render view"); }
	updateSwapchainTexture(swapchainColor, swapchain);
	const v = viewIndex(textures[textureIndex(swapchainColor)].swapchainView);
	views[v].renderTarget = d3dRtvFrom(swapchain.renderView);
	views[v].swapchainResolve = d3dRtvFrom(swapchain.resolveView);
	if (swapchainDepth != 0) {
		updateSwapchainTexture(swapchainDepth, swapchain);
		const d = viewIndex(textures[textureIndex(swapchainDepth)].swapchainView);
		views[d].depthStencil = d3dDsvFrom(swapchain.depthStencilView);
	}
	return { id: swapchainColor };
}

export function swapchainDepthTexture(): GPUTexture { return { id: swapchainDepth }; }

function updateSwapchainTexture(id: uint32, swapchain: NativeSwapchain): void {
	const t = textureIndex(id);
	textures[t].width = swapchain.width;
	textures[t].height = swapchain.height;
	textures[t].sampleCount = swapchain.sampleCount == 0 ? 1 : swapchain.sampleCount;
}

export function createSampler(descriptor: GPUSamplerDescriptor): GPUSampler {
	const id = allocateId(samplerQueue, "sampler");
	if (id == 0) { return { id: 0 }; }
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter");
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter");
	const compare: string = descriptor.compare;
	let maxAnisotropy = descriptor.maxAnisotropy;
	if (maxAnisotropy < 1) { maxAnisotropy = 1; }
	if (maxAnisotropy > MAX_ANISOTROPY) { stopOnMember("GPUSamplerDescriptor.maxAnisotropy", `${maxAnisotropy}`); }
	if (maxAnisotropy > 1 && !(magLinear && minLinear && mipLinear)) {
		stop("GPUSamplerDescriptor.maxAnisotropy above 1 needs linear magFilter, minFilter and mipmapFilter");
	}
	let filter = 0;
	if (maxAnisotropy > 1) {
		filter = FILTER_ANISOTROPIC;
	} else {
		if (mipLinear) { filter |= FILTER_MIP_LINEAR; }
		if (magLinear) { filter |= FILTER_MAG_LINEAR; }
		if (minLinear) { filter |= FILTER_MIN_LINEAR; }
	}
	if (compare != "") { filter |= FILTER_COMPARISON; }
	if (descriptor.lodMinClamp < 0) { stopOnMember("GPUSamplerDescriptor.lodMinClamp", `${descriptor.lodMinClamp}`); }
	const maxLod = descriptor.lodMaxClamp == 0 ? DEFAULT_LOD_MAX_CLAMP : descriptor.lodMaxClamp;
	if (maxLod < descriptor.lodMinClamp) {
		stop(`GPUSamplerDescriptor.lodMaxClamp ${maxLod} is below lodMinClamp ${descriptor.lodMinClamp}`);
	}
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
	const index = slotOf(id);
	const slot: SamplerSlot = { id: id, native: native };
	if (index < samplers.length) { samplers[index] = slot; } else { samplers.push(slot); }
	return { id: id };
}

export function destroySampler(sampler: GPUSampler): void {
	const index = samplerIndex(sampler.id);
	d3dReleaseSampler(samplers[index].native);
	samplers[index] = { id: 0 };
	releaseId(samplerQueue, sampler.id);
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
	const compute = descriptor.computeCode != "";
	if (compute && (descriptor.vertexCode != "" || descriptor.fragmentCode != "")) {
		stop("a GPUShaderModule is either a compute module or a vertex and fragment module");
	}
	const id = allocateId(shaderQueue, "shader module");
	if (id == 0) { return { id: 0 }; }
	let slot: ShaderSlot = { id: 0 };
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const stageName: string = descriptor.bindings[i].stage;
		if ((stageName == "compute") != compute) {
			stop(`shader binding ${descriptor.bindings[i].binding} stage '${stageName}' does not match a ${compute ? "compute" : "vertex and fragment"} module`);
		}
		const native: NativeBinding = {
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName),
			vertexStage: vertexStage(stageName),
			computeStage: stageName == "compute",
			writable: bindingWritable(descriptor.bindings[i]),
			nativeSlot: descriptor.bindings[i].nativeSlot,
			size: descriptor.bindings[i].size,
		};
		checkBinding(native, descriptor.bindings[i].group);
		if (native.kind == BindingKind.Uniform) {
			if (slot.uniformCount == GPU_MAX_UNIFORM_BLOCKS) { stop("a shader module has over 8 uniform blocks"); }
			slot.uniforms[slot.uniformCount] = native;
			slot.uniformCount += 1;
		} else {
			if (slot.resourceCount == GPU_MAX_BIND_GROUP_ENTRIES) { stop("a shader module has over 8 resources"); }
			slot.resources[slot.resourceCount] = native;
			slot.resourceCount += 1;
		}
	}
	slot.attributes = descriptor.attributes;
	if (compute) {
		slot.computeEntry = descriptor.computeEntryPoint == "" ? "main" : descriptor.computeEntryPoint;
		const size: int32[3] = descriptor.workgroupSize;
		if (size[0] > MAX_WORKGROUP_SIZE_X || size[1] > MAX_WORKGROUP_SIZE_Y || size[2] > MAX_WORKGROUP_SIZE_Z || size[0] * size[1] * size[2] > MAX_WORKGROUP_INVOCATIONS) {
			stop(`workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the limits ${MAX_WORKGROUP_SIZE_X}x${MAX_WORKGROUP_SIZE_Y}x${MAX_WORKGROUP_SIZE_Z} and ${MAX_WORKGROUP_INVOCATIONS} invocations`);
		}
		const computeBlob = compileStage(descriptor.computeCode, slot.computeEntry, "cs_5_0", descriptor.label);
		slot.compute = d3dCreateComputeShader(device, computeBlob);
		d3dReleaseBlob(computeBlob);
		if (slot.compute == null) { stop(`CreateComputeShader failed for ${labelOf(descriptor.label)}`); }
		setLabel(slot.compute, descriptor.label);
	} else {
		slot.vertexBlob = compileStage(descriptor.vertexCode, descriptor.vertexEntryPoint, "vs_5_0", descriptor.label);
		const fragmentBlob = compileStage(descriptor.fragmentCode, descriptor.fragmentEntryPoint, "ps_5_0", descriptor.label);
		slot.vertex = d3dCreateVertexShader(device, slot.vertexBlob);
		slot.fragment = d3dCreatePixelShader(device, fragmentBlob);
		d3dReleaseBlob(fragmentBlob);
		if (slot.vertex == null || slot.fragment == null) { stop(`CreateVertexShader/CreatePixelShader failed for ${labelOf(descriptor.label)}`); }
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
	const index = slotOf(slot.id);
	if (index < shaders.length) { shaders[index] = slot; } else { shaders.push(slot); }
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

function checkBinding(native: NativeBinding, group: int32): void {
	const expectedGroup = native.kind == BindingKind.Uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
	if (group != expectedGroup) {
		stop(`shader binding ${native.binding} (${native.kind.toString()}) belongs in group ${expectedGroup}, not ${group}`);
	}
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
	if (native.kind == BindingKind.Uniform && native.size <= 0) {
		stop(`uniform binding ${native.binding} needs its block size`);
	}
	if (native.kind == BindingKind.Uniform && (native.size as int64) > MAX_UNIFORM_BUFFER_BINDING_SIZE) {
		stop(`uniform binding ${native.binding} of ${native.size} bytes is over the limit of ${MAX_UNIFORM_BUFFER_BINDING_SIZE}`);
	}
}

export function destroyShaderModule(module: GPUShaderModule): void {
	const index = shaderIndex(module.id);
	d3dReleaseVertexShader(shaders[index].vertex);
	d3dReleasePixelShader(shaders[index].fragment);
	d3dReleaseComputeShader(shaders[index].compute);
	d3dReleaseBlob(shaders[index].vertexBlob);
	for (let u = 0; u < shaders[index].uniformCount; u++) { d3dReleaseBuffer(shaders[index].constantBuffers[u]); }
	shaders[index] = { id: 0 };
	releaseId(shaderQueue, module.id);
}

function semanticIndexOf(shader: int32, location: int32): int32 {
	for (let i = 0; i < GPU_MAX_VERTEX_ATTRIBUTES; i++) {
		if (shaders[shader].attributes[i].location == location) {
			return shaders[shader].attributes[i].semanticIndex;
		}
	}
	return stopOnMember("vertex attribute shaderLocation (absent from the shader reflection)", `${location}`);
}

export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	const id = allocateId(pipelineQueue, "render pipeline");
	if (id == 0) { return { id: 0 }; }
	const s = shaderIndex(descriptor.vertex.module.id);
	if (shaders[s].compute != null) { stop("a compute GPUShaderModule cannot make a GPURenderPipeline"); }
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		stop("vertex and fragment stages come from one GPUShaderModule on D3D11");
	}
	let slot: PipelineSlot = { id: 0, shader: descriptor.vertex.module.id };
	slot.topology = primitiveTopology(descriptor.primitive.topology);
	slot.stripIndexFormat = stripIndexFormatOf(descriptor.primitive, slot.topology);
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
	describeBlendTargets(descriptor);
	slot.blend = d3dCreateBlendState(device);
	if (slot.rasterizer == null || slot.depthStencil == null || slot.blend == null) {
		stop(`a D3D11 state object failed for pipeline ${labelOf(descriptor.label)}`);
	}
	setLabel(slot.inputLayout, descriptor.label);
	setLabel(slot.rasterizer, descriptor.label);
	setLabel(slot.depthStencil, descriptor.label);
	setLabel(slot.blend, descriptor.label);
	slot.id = id;
	const index = slotOf(slot.id);
	if (index < pipelines.length) { pipelines[index] = slot; } else { pipelines.push(slot); }
	return { id: slot.id };
}

function stripIndexFormatOf(state: GPUPrimitiveState, topology: int32): int32 {
	const format: string = state.stripIndexFormat;
	if (format == "") { return 0; }
	if (topology != TOPOLOGY_LINE_STRIP && topology != TOPOLOGY_TRIANGLE_STRIP) {
		stop(`primitive.stripIndexFormat '${format}' needs a strip topology`);
	}
	return indexFormat(state.stripIndexFormat);
}

function createInputLayout(
	shader: int32,
	descriptor: GPURenderPipelineDescriptor,
	ref slot: PipelineSlot,
): Ptr<D3dInputLayoutImpl> {
	let count = 0;
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const stepMode: string = descriptor.vertex.buffers[b].stepMode;
		if (stepMode != "" && stepMode != "vertex" && stepMode != "instance") {
			stopOnMember("vertex.buffers stepMode", stepMode);
		}
		const perInstance = stepMode == "instance" ? 1 : 0;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const format: string = descriptor.vertex.buffers[b].attributes[a].format;
			if (format == "") { continue; }
			if (count == GPU_MAX_VERTEX_ATTRIBUTES) { stop("a pipeline has over 16 vertex attributes"); }
			const location = descriptor.vertex.buffers[b].attributes[a].shaderLocation;
			d3dInputElement(
				count,
				semanticIndexOf(shader, location),
				vertexFormat(format),
				b,
				descriptor.vertex.buffers[b].attributes[a].offset,
				perInstance,
			);
			count += 1;
			slot.strides[b] = descriptor.vertex.buffers[b].arrayStride;
		}
		if (slot.strides[b] == 0 && descriptor.vertex.buffers[b].arrayStride != 0) {
			slot.strides[b] = descriptor.vertex.buffers[b].arrayStride;
		}
	}
	if (count == 0) { return null as unknown as Ptr<D3dInputLayoutImpl>; }
	const layout = d3dCreateInputLayout(device, count, shaders[shader].vertexBlob);
	if (layout == null) { stop(`CreateInputLayout failed for pipeline ${labelOf(descriptor.label)}`); }
	return layout;
}

function describeBlendTargets(descriptor: GPURenderPipelineDescriptor): void {
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") { continue; }
		formatInfo(descriptor.fragment.targets[i].format, `fragment.targets[${i}].format`);
		const color: GPUBlendComponent = descriptor.fragment.targets[i].blend.color;
		const alpha: GPUBlendComponent = descriptor.fragment.targets[i].blend.alpha;
		const writeMask = descriptor.fragment.targets[i].writeMask;
		d3dBlendTarget(
			i,
			descriptor.fragment.targets[i].blendEnabled ? 1 : 0,
			blendFactor(color.srcFactor, false, "blend.color.srcFactor"),
			destinationFactor(color.dstFactor, false, "blend.color.dstFactor"),
			blendOperation(color.operation, "blend.color.operation"),
			blendFactor(alpha.srcFactor, true, "blend.alpha.srcFactor"),
			destinationFactor(alpha.dstFactor, true, "blend.alpha.dstFactor"),
			blendOperation(alpha.operation, "blend.alpha.operation"),
			writeMask == 0 ? COLOR_WRITE_ALL : writeMask,
		);
	}
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	const index = pipelineIndex(pipeline.id);
	d3dReleaseInputLayout(pipelines[index].inputLayout);
	d3dReleaseRasterizerState(pipelines[index].rasterizer);
	d3dReleaseDepthStencilState(pipelines[index].depthStencil);
	d3dReleaseBlendState(pipelines[index].blend);
	for (let g = 0; g < 2; g++) {
		const layout = pipelines[index].layouts[g];
		if (layout != 0) {
			layouts[layoutIndex(layout)] = { id: 0 };
			releaseId(layoutQueue, layout);
		}
	}
	pipelines[index] = { id: 0 };
	releaseId(pipelineQueue, pipeline.id);
}

export function getBindGroupLayout(pipeline: GPURenderPipeline, index: int32): GPUBindGroupLayout {
	const p = pipelineIndex(pipeline.id);
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) {
		stopOnMember("getBindGroupLayout index", `${index}`);
	}
	if (pipelines[p].layouts[index] == 0) {
		const id = allocateId(layoutQueue, "bind group layout");
		if (id == 0) { return { id: 0 }; }
		const slot: LayoutSlot = { id: id, pipeline: pipeline.id, group: index };
		const l = slotOf(id);
		if (l < layouts.length) { layouts[l] = slot; } else { layouts.push(slot); }
		pipelines[p].layouts[index] = id;
	}
	return { id: pipelines[p].layouts[index] };
}

export function createBindGroup(descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	const id = allocateId(bindGroupQueue, "bind group");
	if (id == 0) { return { id: 0 }; }
	const l = layoutIndex(descriptor.layout.id);
	const group = layouts[l].group;
	const shader = shaderIndex(pipelines[pipelineIndex(layouts[l].pipeline)].shader);
	let slot: BindGroupSlot = { id: 0, group: group };
	for (let i = 0; i < GPU_MAX_BIND_GROUP_ENTRIES; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0) { continue; }
		checkEntry(shader, group, entry);
		if (entry.buffer.id != 0 && buffers[bufferIndex(entry.buffer.id)].storage) { storageViews(slot, shader, entry); }
		slot.entries[slot.entryCount] = entry;
		slot.entryCount += 1;
	}
	for (let i = 0; i < slot.entryCount; i++) {
		if (slot.entries[i].buffer.id == 0 || !buffers[bufferIndex(slot.entries[i].buffer.id)].uniform) { continue; }
		let rank = 0;
		for (let j = 0; j < slot.entryCount; j++) {
			if (slot.entries[j].buffer.id != 0 && buffers[bufferIndex(slot.entries[j].buffer.id)].uniform && slot.entries[j].binding < slot.entries[i].binding) { rank += 1; }
		}
		slot.dynamicIndex[i] = rank;
		slot.dynamicCount += 1;
	}
	slot.id = id;
	const index = slotOf(slot.id);
	if (index < bindGroups.length) { bindGroups[index] = slot; } else { bindGroups.push(slot); }
	return { id: slot.id };
}

function resourceOf(shader: int32, binding: int32): int32 {
	for (let r = 0; r < shaders[shader].resourceCount; r++) {
		if (shaders[shader].resources[r].binding == binding) { return r; }
	}
	return -1;
}

function storageRange(entry: GPUBindGroupEntry, b: int32): int64 {
	if (entry.offset < 0 || entry.offset % STORAGE_OFFSET_ALIGNMENT != 0) {
		stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${STORAGE_OFFSET_ALIGNMENT}`);
	}
	const bytes = entry.size == 0 ? buffers[b].size - entry.offset : entry.size;
	if (bytes <= 0 || bytes % 4 != 0 || entry.offset + bytes > buffers[b].size) {
		stop(`bind group entry ${entry.binding} range ${entry.offset}+${bytes} is not a positive multiple of 4 inside its buffer of ${buffers[b].size}`);
	}
	if (bytes > MAX_STORAGE_BUFFER_BINDING_SIZE) {
		stop(`bind group entry ${entry.binding} range of ${bytes} bytes is over the limit of ${MAX_STORAGE_BUFFER_BINDING_SIZE}`);
	}
	return bytes;
}

function storageViews(ref slot: BindGroupSlot, shader: int32, entry: GPUBindGroupEntry): void {
	const b = bufferIndex(entry.buffer.id);
	const bytes = storageRange(entry, b);
	const binding = shaders[shader].resources[resourceOf(shader, entry.binding)];
	if (binding.writable) {
		slot.uav[slot.entryCount] = d3dCreateBufferUav(device, buffers[b].native, entry.offset, bytes);
		if (slot.uav[slot.entryCount] == null) { stop(`CreateUnorderedAccessView failed for bind group entry ${entry.binding}`); }
	} else {
		slot.srv[slot.entryCount] = d3dCreateBufferSrv(device, buffers[b].native, entry.offset, bytes);
		if (slot.srv[slot.entryCount] == null) { stop(`CreateShaderResourceView failed for bind group entry ${entry.binding}`); }
	}
}

function checkEntry(shader: int32, group: int32, entry: GPUBindGroupEntry): void {
	if (entry.buffer.id != 0) {
		const b = bufferIndex(entry.buffer.id);
		for (let u = 0; u < shaders[shader].uniformCount; u++) {
			const binding = shaders[shader].uniforms[u];
			if (binding.binding == entry.binding) {
				if (!buffers[b].uniform) { stop(`bind group entry ${entry.binding} needs a UNIFORM buffer`); }
				if (entry.offset < 0 || entry.offset % UNIFORM_OFFSET_ALIGNMENT != 0) {
					stop(`bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${UNIFORM_OFFSET_ALIGNMENT}`);
				}
				if (entry.offset + (binding.size as int64) > buffers[b].size) {
					stop(`bind group entry ${entry.binding} offset ${entry.offset} overruns its buffer`);
				}
				if (entry.size != 0 && entry.size < (binding.size as int64)) {
					stop(`bind group entry ${entry.binding} size ${entry.size} is below its block of ${binding.size}`);
				}
				return;
			}
		}
		const r = resourceOf(shader, entry.binding);
		if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.StorageBuffer) {
			if (!buffers[b].storage) { stop(`bind group entry ${entry.binding} needs a STORAGE buffer`); }
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (buffer) is not a binding of the pipeline's shader`);
	}
	const r = resourceOf(shader, entry.binding);
	if (entry.textureView.id != 0) {
		const v = viewIndex(entry.textureView.id);
		if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.Texture) {
			if (views[v].shaderResource == null) { stop(`bind group entry ${entry.binding}: the view's texture lacks TEXTURE_BINDING`); }
			return;
		}
		if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.StorageTexture) {
			if (views[v].unordered == null) { stop(`bind group entry ${entry.binding}: the view's texture lacks STORAGE_BINDING or the view spans several mips`); }
			return;
		}
		stop(`bind group ${group} entry ${entry.binding} (texture) is not a binding of the pipeline's shader`);
	}
	samplerIndex(entry.sampler.id);
	if (r >= 0 && shaders[shader].resources[r].kind == BindingKind.Sampler) { return; }
	stop(`bind group ${group} entry ${entry.binding} (sampler) is not a binding of the pipeline's shader`);
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	const index = bindGroupIndex(bindGroup.id);
	for (let e = 0; e < bindGroups[index].entryCount; e++) {
		d3dReleaseSrv(bindGroups[index].srv[e]);
		d3dReleaseUav(bindGroups[index].uav[e]);
	}
	bindGroups[index] = { id: 0 };
	releaseId(bindGroupQueue, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	if (pass.active) { stop("finish with a render pass still open"); }
	if (computeBound.active) { stop("finish with a compute pass still open"); }
	checkGroupsClosed(0, "finish");
	return { id: 1 };
}

export function submit(commandBuffer: GPUCommandBuffer): void { frame += 1; }

export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	if (pass.active || computeBound.active) { stop("beginRenderPass with a pass already open"); }
	checkTimestampWrites("GPURenderPassDescriptor.timestampWrites", descriptor.timestampWrites);
	if (descriptor.occlusionQuerySet.id != 0 && querySets[querySetIndex(descriptor.occlusionQuerySet.id)].timestamp) {
		stop("GPURenderPassDescriptor.occlusionQuerySet is a timestamp set: an occlusion set is required");
	}
	passSerial += 1;
	pass = {
		active: true,
		serial: passSerial,
		groupBase: groupDepth,
		timestampSet: descriptor.timestampWrites.querySet.id,
		timestampEnd: descriptor.timestampWrites.endOfPassWriteIndex,
		occlusionSet: descriptor.occlusionQuerySet.id,
	};
	pass.labeled = labelPass(descriptor.label);
	if (pass.timestampSet != 0 && descriptor.timestampWrites.beginningOfPassWriteIndex >= 0) {
		writeTimestamp(pass.timestampSet, descriptor.timestampWrites.beginningOfPassWriteIndex);
	}
	let targets: Ptr<D3dRtvImpl>[4] = [NO_RTV, NO_RTV, NO_RTV, NO_RTV];
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const viewId = descriptor.colorAttachments[i].view.id;
		if (viewId == 0) { continue; }
		const v = viewIndex(viewId);
		if (views[v].renderTarget == null) { stop(`colorAttachments[${i}].view is not a color RENDER_ATTACHMENT`); }
		targets[i] = views[v].renderTarget;
		passExtent(views[v].texture, views[v].baseMip);
		pass.colorViews[i] = viewId;
		pass.resolveViews[i] = checkResolve(i, views[v].texture, descriptor.colorAttachments[i].resolveTarget.id);
		checkStoreOp(descriptor.colorAttachments[i].storeOp, `colorAttachments[${i}].storeOp`);
	}
	let depth = NO_DSV;
	const depthView = descriptor.depthStencilAttachment.view.id;
	let depthStencil = false;
	if (depthView != 0) {
		const v = viewIndex(depthView);
		if (views[v].depthStencil == null) { stop("depthStencilAttachment.view is not a depth RENDER_ATTACHMENT"); }
		depth = views[v].depthStencil;
		passExtent(views[v].texture, views[v].baseMip);
		depthStencil = formatInfo(textures[textureIndex(views[v].texture)].format, "depth format").stencil;
		checkStoreOp(descriptor.depthStencilAttachment.depthStoreOp, "depthStencilAttachment.depthStoreOp");
	}
	if (pass.width == 0) { stop("beginRenderPass without an attachment"); }
	d3dSetRenderTargets(context, targets[0], targets[1], targets[2], targets[3], depth);
	d3dSetViewport(context, 0.0, 0.0, pass.width, pass.height, 0.0, 1.0);
	d3dSetScissorRect(context, 0, 0, pass.width, pass.height);
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] == 0) { continue; }
		if (isClear(descriptor.colorAttachments[i].loadOp, `colorAttachments[${i}].loadOp`)) {
			const color = descriptor.colorAttachments[i].clearValue;
			d3dClearRtv(context, targets[i], color.r, color.g, color.b, color.a);
		}
	}
	if (depthView != 0 && isClear(descriptor.depthStencilAttachment.depthLoadOp, "depthStencilAttachment.depthLoadOp")) {
		const flags = depthStencil ? CLEAR_DEPTH | CLEAR_STENCIL : CLEAR_DEPTH;
		d3dClearDsv(context, depth, flags, descriptor.depthStencilAttachment.depthClearValue, 0);
	}
	forgetNativeBinds();
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
	const t = textureIndex(texture);
	const width = Math.max(1, textures[t].width >> baseMip);
	const height = Math.max(1, textures[t].height >> baseMip);
	if (pass.width == 0) {
		pass.width = width;
		pass.height = height;
	} else if (pass.width != width || pass.height != height) {
		stop("render pass attachments differ in size");
	}
}

function checkResolve(attachment: int32, colorTexture: uint32, resolveId: uint32): uint32 {
	if (resolveId == 0) { return 0; }
	const r = viewIndex(resolveId);
	const resolveTexture = textureIndex(views[r].texture);
	if (views[r].baseMip != 0 || views[r].baseLayer != 0) {
		stop(`colorAttachments[${attachment}].resolveTarget at baseMipLevel or baseArrayLayer above 0 is not ported to d3d11 yet`);
	}
	if (textures[textureIndex(colorTexture)].sampleCount == 1) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a multisampled view`);
	}
	if (textures[resolveTexture].sampleCount != 1 || views[r].renderTarget == null) {
		stop(`colorAttachments[${attachment}].resolveTarget needs a single-sample color RENDER_ATTACHMENT`);
	}
	return resolveId;
}

function isClear(loadOp: string, member: string): boolean {
	const value = match (loadOp) {
		"clear" => 1,
		"load" => 0,
		_ => stopOnMember(member, loadOp),
	};
	return value == 1;
}

function checkStoreOp(storeOp: string, member: string): void {
	if (storeOp != "store" && storeOp != "discard") { stopOnMember(member, storeOp); }
}

export function endPass(): void {
	if (!pass.active) { stop("end without an open render pass"); }
	if (pass.occlusionOpen) { stop("end with an occlusion query still open"); }
	checkGroupsClosed(pass.groupBase, "end");
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.colorViews[i] == 0) { continue; }
		const v = viewIndex(pass.colorViews[i]);
		if (views[v].swapchain && views[v].swapchainResolve != null) {
			const format = formatInfo(canvas.format, "canvas format").renderTarget;
			d3dResolveViews(context, views[v].swapchainResolve, views[v].renderTarget, format);
		}
		if (pass.resolveViews[i] != 0) {
			const source = textureIndex(views[v].texture);
			const destination = textureIndex(views[viewIndex(pass.resolveViews[i])].texture);
			const format = formatInfo(textures[source].format, "resolve format").renderTarget;
			d3dResolveSubresource(context, textures[destination].native, textures[source].native, format);
		}
	}
	if (pass.timestampSet != 0 && pass.timestampEnd >= 0) { writeTimestamp(pass.timestampSet, pass.timestampEnd); }
	if (pass.labeled) { d3dEndEvent(context); }
	d3dClearState(context);
	pass.active = false;
}

export function createComputePipeline(descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const s = shaderIndex(descriptor.compute.module.id);
	if (shaders[s].compute == null) { stop("createComputePipeline needs a GPUShaderModule made with computeCode"); }
	const entry = descriptor.compute.entryPoint == "" ? "main" : descriptor.compute.entryPoint;
	if (entry != shaders[s].computeEntry) {
		stop(`compute.entryPoint '${entry}' differs from the module's computeEntryPoint '${shaders[s].computeEntry}'`);
	}
	const id = allocateId(pipelineQueue, "compute pipeline");
	if (id == 0) { return { id: 0 }; }
	const slot: PipelineSlot = { id: id, shader: descriptor.compute.module.id, compute: true };
	const index = slotOf(id);
	if (index < pipelines.length) { pipelines[index] = slot; } else { pipelines.push(slot); }
	return { id: id };
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	if (pass.active || computeBound.active) { stop("beginComputePass with a pass already open"); }
	checkTimestampWrites("GPUComputePassDescriptor.timestampWrites", descriptor.timestampWrites);
	computeBound = {
		active: true,
		groupBase: groupDepth,
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
	if (!computeBound.active) { stop("setPipeline outside a compute pass"); }
	if (!pipelines[pipelineIndex(pipeline.id)].compute) { stop(`GPUPipeline ${pipeline.id} is not a compute pipeline`); }
	computeBound.pipeline = pipeline.id;
	computeBound.dirty = true;
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	if (!computeBound.active) { stop("setBindGroup outside a compute pass"); }
	if (index != GPU_RESOURCE_GROUP) { stop(`a compute pipeline has no uniform group: setBindGroup(${index}) takes group ${GPU_RESOURCE_GROUP}`); }
	if (dynamicOffsets.length != 0) { stop("a compute bind group takes no dynamic offsets"); }
	if (bindGroup.id != 0 && bindGroups[bindGroupIndex(bindGroup.id)].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups[bindGroupIndex(bindGroup.id)].group}`);
	}
	computeBound.bindGroup = bindGroup.id;
	computeBound.dirty = true;
}

function applyCompute(): void {
	if (!computeBound.active) { stop("dispatch outside a compute pass"); }
	if (computeBound.pipeline == 0) { stop("dispatch without setPipeline"); }
	if (!computeBound.dirty) { return; }
	const s = shaderIndex(pipelines[pipelineIndex(computeBound.pipeline)].shader);
	d3dCsClearViews(context);
	d3dCsSetShader(context, shaders[s].compute);
	computeBound.dirty = false;
	if (shaders[s].resourceCount == 0) { return; }
	if (computeBound.bindGroup == 0) { stop("the compute pipeline reads bind group 1, which is not set"); }
	const g = bindGroupIndex(computeBound.bindGroup);
	for (let r = 0; r < shaders[s].resourceCount; r++) {
		const binding: NativeBinding = shaders[s].resources[r];
		const e = entryOf(g, binding.binding);
		if (binding.kind == BindingKind.Texture) {
			d3dCsSetShaderResource(context, binding.nativeSlot, views[viewIndex(bindGroups[g].entries[e].textureView.id)].shaderResource);
		} else if (binding.kind == BindingKind.Sampler) {
			d3dCsSetSampler(context, binding.nativeSlot, samplers[samplerIndex(bindGroups[g].entries[e].sampler.id)].native);
		} else if (binding.kind == BindingKind.StorageBuffer) {
			if (binding.writable) {
				d3dCsSetUnorderedAccessView(context, binding.nativeSlot, bindGroups[g].uav[e]);
			} else {
				d3dCsSetShaderResource(context, binding.nativeSlot, bindGroups[g].srv[e]);
			}
		} else {
			d3dCsSetUnorderedAccessView(context, binding.nativeSlot, views[viewIndex(bindGroups[g].entries[e].textureView.id)].unordered);
		}
	}
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	if (x < 0 || y < 0 || z < 0 || x > MAX_DISPATCH_GROUPS || y > MAX_DISPATCH_GROUPS || z > MAX_DISPATCH_GROUPS) {
		stop(`dispatchWorkgroups ${x},${y},${z} is outside 0..${MAX_DISPATCH_GROUPS}`);
	}
	applyCompute();
	d3dDispatch(context, x, y, z);
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	const b = bufferIndex(buffer.id);
	if (!has(buffers[b].usage, GPUBufferUsage.INDIRECT as int32)) { stop(`dispatchWorkgroupsIndirect: GPUBuffer ${buffer.id} was created without INDIRECT`); }
	if (offset < 0 || offset % 4 != 0 || offset + 12 > buffers[b].size) {
		stop(`dispatchWorkgroupsIndirect offset ${offset} is not a multiple of 4 with 12 bytes inside GPUBuffer ${buffer.id} of ${buffers[b].size}`);
	}
	applyCompute();
	d3dDispatchIndirect(context, buffers[b].native, offset);
}

export function endComputePass(): void {
	if (!computeBound.active) { stop("end without an open compute pass"); }
	checkGroupsClosed(computeBound.groupBase, "end");
	if (computeBound.timestampSet != 0 && computeBound.timestampEnd >= 0) { writeTimestamp(computeBound.timestampSet, computeBound.timestampEnd); }
	if (computeBound.labeled) { d3dEndEvent(context); }
	d3dClearState(context);
	computeBound = { active: false };
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	pipelineIndex(pipeline.id);
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
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) { stopOnMember("setBindGroup index", `${index}`); }
	bound.bindGroups[index] = bindGroup.id;
	if (bindGroup.id == 0) { return; }
	const g = bindGroupIndex(bindGroup.id);
	if (bindGroups[g].group != index) {
		stop(`setBindGroup(${index}) with a bind group made for group ${bindGroups[g].group}`);
	}
	if ((dynamicOffsets.length as int32) != bindGroups[g].dynamicCount) {
		stop(`setBindGroup(${index}) takes ${bindGroups[g].dynamicCount} dynamic offsets, got ${dynamicOffsets.length}`);
	}
	if (index == GPU_UNIFORM_GROUP) {
		for (let i = 0; i < bindGroups[g].dynamicCount; i++) {
			if (dynamicOffsets[i] % UNIFORM_OFFSET_ALIGNMENT != 0) {
				stop(`dynamic offset ${dynamicOffsets[i]} is not a multiple of ${UNIFORM_OFFSET_ALIGNMENT}`);
			}
			bound.dynamicOffsets[i] = dynamicOffsets[i];
		}
		bound.uniformsDirty = true;
	} else {
		bound.resourcesDirty = true;
	}
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	if (!pass.active) { stop("setScissorRect outside a render pass"); }
	d3dSetScissorRect(context, x, y, x + width, y + height);
}

export function setViewport(x: number, y: number, width: number, height: number, minDepth: number, maxDepth: number): void {
	if (!pass.active) { stop("setViewport outside a render pass"); }
	if (width < 0 || height < 0 || minDepth < 0 || maxDepth > 1 || minDepth > maxDepth) {
		stop(`setViewport ${width}x${height} depth ${minDepth}..${maxDepth} is outside WebGPU's valid range`);
	}
	d3dSetViewport(context, x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	if (!pass.active) { stop("setBlendConstant outside a render pass"); }
	bound.blendConstant = color;
	if (bound.appliedPipeline != 0) { applyBlend(); }
}

export function setStencilReference(reference: uint32): void {
	if (!pass.active) { stop("setStencilReference outside a render pass"); }
	bound.stencilReference = reference;
	if (bound.appliedPipeline != 0) { applyDepthStencil(); }
}

function applyBlend(): void {
	const color = bound.blendConstant;
	d3dOmSetBlendState(context, pipelines[pipelineIndex(bound.appliedPipeline)].blend, color.r, color.g, color.b, color.a);
}

function applyDepthStencil(): void {
	d3dOmSetDepthStencilState(
		context,
		pipelines[pipelineIndex(bound.appliedPipeline)].depthStencil,
		bound.stencilReference as int32,
	);
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	flush(false);
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
	if (instanceCount > 1 || firstInstance != 0) {
		d3dDrawIndexedInstanced(context, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
	} else {
		d3dDrawIndexed(context, indexCount, firstIndex, baseVertex);
	}
}

function flush(indexed: boolean): void {
	if (!pass.active) { stop("draw outside a render pass"); }
	if (bound.pipeline == 0) { stop("draw without setPipeline"); }
	if (bound.appliedPipeline != bound.pipeline) { applyPipeline(); }
	if (bound.vertexDirty) { applyVertexBuffers(); }
	if (indexed && bound.indexDirty) { applyIndexBuffer(); }
	if (indexed) { checkStripIndexFormat(); }
	if (bound.resourcesDirty) { applyResources(); }
	if (bound.uniformsDirty) { applyUniforms(); }
}

function applyPipeline(): void {
	const p = pipelineIndex(bound.pipeline);
	if (shaders.length <= slotOf(pipelines[p].shader) || shaders[slotOf(pipelines[p].shader)].id != pipelines[p].shader) {
		stop(`the shader module of GPURenderPipeline ${bound.pipeline} was destroyed`);
	}
	const s = shaderIndex(pipelines[p].shader);
	d3dRsSetState(context, pipelines[p].rasterizer);
	bound.appliedPipeline = bound.pipeline;
	applyDepthStencil();
	applyBlend();
	d3dIaSetPrimitiveTopology(context, pipelines[p].topology);
	d3dIaSetInputLayout(context, pipelines[p].inputLayout);
	d3dVsSetShader(context, shaders[s].vertex);
	d3dPsSetShader(context, shaders[s].fragment);
	for (let u = 0; u < shaders[s].uniformCount && !offsetUniforms; u++) {
		if (shaders[s].uniforms[u].vertexStage) {
			d3dVsSetConstantBuffer(context, shaders[s].uniforms[u].nativeSlot, shaders[s].constantBuffers[u]);
		} else {
			d3dPsSetConstantBuffer(context, shaders[s].uniforms[u].nativeSlot, shaders[s].constantBuffers[u]);
		}
	}
	forgetAppliedUniforms();
	bound.vertexDirty = true;
	bound.resourcesDirty = true;
	bound.uniformsDirty = true;
}

function checkStripIndexFormat(): void {
	const p = pipelineIndex(bound.pipeline);
	const topology = pipelines[p].topology;
	if (topology != TOPOLOGY_LINE_STRIP && topology != TOPOLOGY_TRIANGLE_STRIP) { return; }
	if (pipelines[p].stripIndexFormat != bound.indexFormat) {
		stop("an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format");
	}
}

function applyVertexBuffers(): void {
	const p = pipelineIndex(bound.pipeline);
	for (let slot = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
		const stride = pipelines[p].strides[slot];
		if (stride == 0) { continue; }
		if (bound.vertexBuffers[slot] == 0) { stop(`the pipeline reads vertex buffer ${slot}, which is not set`); }
		const b = bufferIndex(bound.vertexBuffers[slot]);
		const native = buffers[b].native;
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
	if (bound.indexBuffer == 0) { stop("drawIndexed without setIndexBuffer"); }
	const b = bufferIndex(bound.indexBuffer);
	const native = buffers[b].native;
	const offset = bound.indexOffset as int32;
	bound.indexDirty = false;
	if (nativeBinds.indexBuffer == native && nativeBinds.indexFormat == bound.indexFormat && nativeBinds.indexOffset == offset) { return; }
	d3dIaSetIndexBuffer(context, native, bound.indexFormat, offset);
	nativeBinds.indexBuffer = native;
	nativeBinds.indexFormat = bound.indexFormat;
	nativeBinds.indexOffset = offset;
	stats.indexBuffers += 1;
}

function entryOf(group: int32, binding: int32): int32 {
	for (let e = 0; e < bindGroups[group].entryCount; e++) {
		if (bindGroups[group].entries[e].binding == binding) { return e; }
	}
	return stopOnMember("bound bind group: missing entry for binding", `${binding}`);
}

function applyResources(): void {
	const s = shaderIndex(pipelines[pipelineIndex(bound.pipeline)].shader);
	bound.resourcesDirty = false;
	if (shaders[s].resourceCount == 0) { return; }
	if (bound.bindGroups[GPU_RESOURCE_GROUP] == 0) { stop("the pipeline reads bind group 1, which is not set"); }
	const g = bindGroupIndex(bound.bindGroups[GPU_RESOURCE_GROUP]);
	for (let r = 0; r < shaders[s].resourceCount; r++) {
		const binding: NativeBinding = shaders[s].resources[r];
		const e = entryOf(g, binding.binding);
		if (binding.kind == BindingKind.StorageTexture) { stop("a storage texture in a render stage is not ported to d3d11"); }
		if (binding.kind == BindingKind.Texture || binding.kind == BindingKind.StorageBuffer) {
			const view = binding.kind == BindingKind.Texture ? views[viewIndex(bindGroups[g].entries[e].textureView.id)].shaderResource : bindGroups[g].srv[e];
			if (binding.vertexStage) {
				if (nativeBinds.vertexShaderResource[binding.nativeSlot] == view) { continue; }
				d3dVsSetShaderResource(context, binding.nativeSlot, view);
				nativeBinds.vertexShaderResource[binding.nativeSlot] = view;
			} else {
				if (nativeBinds.fragmentShaderResource[binding.nativeSlot] == view) { continue; }
				d3dPsSetShaderResource(context, binding.nativeSlot, view);
				nativeBinds.fragmentShaderResource[binding.nativeSlot] = view;
			}
			stats.shaderResources += 1;
		} else {
			const sampler = samplers[samplerIndex(bindGroups[g].entries[e].sampler.id)].native;
			if (binding.vertexStage) {
				if (nativeBinds.vertexSampler[binding.nativeSlot] == sampler) { continue; }
				d3dVsSetSampler(context, binding.nativeSlot, sampler);
				nativeBinds.vertexSampler[binding.nativeSlot] = sampler;
			} else {
				if (nativeBinds.fragmentSampler[binding.nativeSlot] == sampler) { continue; }
				d3dPsSetSampler(context, binding.nativeSlot, sampler);
				nativeBinds.fragmentSampler[binding.nativeSlot] = sampler;
			}
			stats.samplers += 1;
		}
	}
}

function applyUniforms(): void {
	const s = shaderIndex(pipelines[pipelineIndex(bound.pipeline)].shader);
	bound.uniformsDirty = false;
	if (shaders[s].uniformCount == 0) { return; }
	if (bound.bindGroups[GPU_UNIFORM_GROUP] == 0) { stop("the pipeline reads bind group 0, which is not set"); }
	const g = bindGroupIndex(bound.bindGroups[GPU_UNIFORM_GROUP]);
	for (let u = 0; u < shaders[s].uniformCount; u++) {
		const e = entryOf(g, shaders[s].uniforms[u].binding);
		const offset = (bound.dynamicOffsets[bindGroups[g].dynamicIndex[e]] as int64) + bindGroups[g].entries[e].offset;
		const b = bufferIndex(bindGroups[g].entries[e].buffer.id);
		const block = shaders[s].uniforms[u];
		if (offset + (block.size as int64) > buffers[b].size) {
			stop(`uniform binding ${block.binding} at offset ${offset} overruns its buffer`);
		}
		if (offsetUniforms) {
			if (bound.uniformBuffer[u] == buffers[b].id && bound.uniformFirst[u] == offset) { continue; }
			const constants = roundUp256(block.size as int64) / 16;
			if (constants > MAX_BLOCK_CONSTANTS || offset + constants * 16 > roundUp256(buffers[b].size)) {
				stop(`uniform binding ${block.binding} of ${block.size} bytes at ${offset} does not fit one constant buffer view`);
			}
			if (block.vertexStage) {
				d3dVsSetConstantBufferRange(block.nativeSlot, buffers[b].native, offset / 16, constants);
			} else {
				d3dPsSetConstantBufferRange(block.nativeSlot, buffers[b].native, offset / 16, constants);
			}
			bound.uniformBuffer[u] = buffers[b].id;
			bound.uniformFirst[u] = offset;
		} else {
			const bytes = roundUp16(block.size as int64);
			if (offset + bytes > (buffers[b].shadow.length as int64)) {
				stop(`uniform binding ${block.binding} at offset ${offset} overruns its buffer`);
			}
			d3dUpdateIfChanged(context, shaders[s].constantBuffers[u], shaders[s].blockCache[0], shaders[s].cacheOffset[u] as int64, buffers[b].shadow[0], offset, bytes, shaders[s].cacheFresh[u]);
			shaders[s].cacheFresh[u] = 0;
		}
	}
}
