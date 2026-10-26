import {
	BindingKind,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBufferUsage,
	GPUMapMode,
	GPUPrimitiveState,
	GPURenderPassDescriptor,
	GPUQuerySetDescriptor,
	GPURenderPipelineDescriptor,
	GPUSamplerDescriptor,
	GPUShaderBinding,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUSupportedLimits,
	GPUTextureDescriptor,
	GPUTextureUsage,
	GPUTextureViewDescriptor,
} from "../webgpu/types";
import {
	AttachmentFacts,
	EncoderState,
	RenderPassFacts,
	PASS_COMPUTE,
	PASS_RENDER,
	addressesBinding,
	attachOcclusion,
	beginOcclusionRefusal,
	bindGroupIndexRefusal,
	bindGroupSetRefusal,
	dynamicIndexOf,
	shaderBindingAt,
	copyBufferRefusal,
	copyTextureRefusal,
	uniformEntryCount,
	beginPassRefusal,
	bufferRefusal,
	canvasRefusal,
	resolvedRenderPipeline,
	stencil8Mask,
	clampedAnisotropy,
	computeModuleRefusal,
	computePipelineRefusal,
	createRefusal,
	dispatchRefusal,
	drawOffsetRefusal,
	drawRefusal,
	endOcclusionRefusal,
	entryBytes,
	endPassRefusal,
	finishRefusal,
	groupOfKind,
	inPassRefusal,
	isDepthFormat,
	isStripTopology,
	markIndexBuffer,
	markPipeline,
	markerRefusal,
	occlusionRangeRefusal,
	occlusionReuseRefusal,
	occlusionSetKindRefusal,
	pipelineSetRefusal,
	queriesWrittenRefusal,
	querySetRefusal,
	resolvedViewDimension,
	resolvedViewRange,
	cubeCapable,
	viewRangeRefusal,
	sampledViewRefusal,
	storageEntryRefusal,
	storageViewRefusal,
	viewDimensionRefusal,
	outsidePassRefusal,
	popGroupRefusal,
	primitiveRefusal,
	pushGroupRefusal,
	renderModuleRefusal,
	renderPassExtent,
	renderPassRefusal,
	renderPassPipelineRefusal,
	renderPipelineRefusal,
	scissorRefusal,
	samplerRefusal,
	shaderModuleRefusal,
	shutdownRefusal,
	stripDrawRefusal,
	textureRefusal,
	uniformEntryRefusal,
	vertexSlotRefusal,
	viewportRefusal,
	writeBufferRefusal,
} from "../webgpu/validate";
import { BufferRecord, PipelineRecord, QuerySetRecord, QueryState, ShaderRecord, TextureRecord } from "../webgpu/pool";

function openEncoder(): EncoderState {
	let s: EncoderState = { open: false };
	s.createRefusal();
	return s;
}

function entryAt(offset: int64, size: int64): GPUBindGroupEntry {
	return { binding: 2, offset: offset, size: size };
}

test "a second command encoder is refused while the first is open and allowed after finish" {
	let s = openEncoder();
	assert s.createRefusal() == "createCommandEncoder with the frame's encoder not yet finished";
	assert s.finishRefusal() == "";
	assert s.createRefusal() == "";
}

test "a second encoder is refused with a pass or a debug group open on the first" {
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.createRefusal() != "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
	assert s.pushGroupRefusal() == "";
	assert s.createRefusal() != "";
}

test "finish names what is still open and a missing encoder" {
	let none: EncoderState = { open: false };
	assert none.finishRefusal() == "finish without createCommandEncoder";
	let render = openEncoder();
	assert render.beginPassRefusal(PASS_RENDER) == "";
	assert render.finishRefusal() == "finish with a render pass still open";
	let compute = openEncoder();
	assert compute.beginPassRefusal(PASS_COMPUTE) == "";
	assert compute.finishRefusal() == "finish with a compute pass still open";
	let groups = openEncoder();
	assert groups.pushGroupRefusal() == "";
	assert groups.pushGroupRefusal() == "";
	assert groups.finishRefusal() == "finish with 2 debug groups still open";
}

test "a pass begins only on an open encoder with no pass open, for either kind" {
	let none: EncoderState = { open: false };
	assert none.beginPassRefusal(PASS_RENDER) == "beginRenderPass without createCommandEncoder";
	assert none.beginPassRefusal(PASS_COMPUTE) == "beginComputePass without createCommandEncoder";
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_RENDER) == "beginRenderPass with a pass already open";
	assert s.beginPassRefusal(PASS_COMPUTE) == "beginComputePass with a pass already open";
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
}

test "end names the pass kind it closes and the groups the pass left open" {
	let s = openEncoder();
	assert s.endPassRefusal(PASS_RENDER) == "end without an open render pass";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.endPassRefusal(PASS_RENDER) == "end without an open render pass";
	assert s.pushGroupRefusal() == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "end with 1 debug groups still open";
	assert s.popGroupRefusal() == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
}

test "a pass cannot pop a group the encoder pushed before it, and the encoder can after the pass" {
	let s = openEncoder();
	assert s.pushGroupRefusal() == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.popGroupRefusal() == "popDebugGroup without a matching pushDebugGroup";
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.popGroupRefusal() == "";
	assert s.popGroupRefusal() == "popDebugGroup without a matching pushDebugGroup";
}

test "debug calls and copies need an open encoder, and copies need no open pass" {
	let none: EncoderState = { open: false };
	assert none.pushGroupRefusal() == "pushDebugGroup without createCommandEncoder";
	assert none.popGroupRefusal() == "popDebugGroup without createCommandEncoder";
	assert none.markerRefusal() == "insertDebugMarker without createCommandEncoder";
	assert none.outsidePassRefusal("copyBufferToBuffer") == "copyBufferToBuffer without createCommandEncoder";
	let s = openEncoder();
	assert s.outsidePassRefusal("resolveQuerySet") == "";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.outsidePassRefusal("resolveQuerySet") == "resolveQuerySet inside a pass";
	assert s.markerRefusal() == "";
}

test "a pass call is refused outside a pass of its kind, naming the call" {
	let s = openEncoder();
	assert s.inPassRefusal(PASS_RENDER, "draw") == "draw outside a render pass";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.inPassRefusal(PASS_RENDER, "setViewport") == "setViewport outside a render pass";
	assert s.inPassRefusal(PASS_COMPUTE, "dispatchWorkgroups") == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
	assert s.inPassRefusal(PASS_COMPUTE, "setPipeline") == "setPipeline outside a compute pass";
}

test "a device shuts down only with no pass open" {
	let s = openEncoder();
	assert s.shutdownRefusal() == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.shutdownRefusal() == "shutdown with a render pass still open";
}

test "a bind group entry addresses only the bindings of its own group" {
	assert groupOfKind(BindingKind.Uniform) == 0;
	assert groupOfKind(BindingKind.StorageBuffer) == 1;
	assert addressesBinding(0, 3, 3, BindingKind.Uniform);
	assert !addressesBinding(1, 3, 3, BindingKind.Uniform);
	assert addressesBinding(1, 3, 3, BindingKind.StorageBuffer);
	assert !addressesBinding(0, 3, 3, BindingKind.StorageBuffer);
	assert addressesBinding(1, 3, 3, BindingKind.Texture);
	assert !addressesBinding(0, 3, 3, BindingKind.Sampler);
	assert !addressesBinding(0, 3, 4, BindingKind.Uniform);
}

test "a shader binding is found by its own group, binding and kind" {
	let shader: ShaderRecord = { id: 1, bindingCount: 3 };
	shader.bindings[0] = { binding: 0, kind: BindingKind.Uniform, size: 64 };
	shader.bindings[1] = { binding: 0, kind: BindingKind.Texture };
	shader.bindings[2] = { binding: 1, kind: BindingKind.Sampler };
	assert shaderBindingAt(shader, 0, 0, BindingKind.Uniform) == 0;
	assert shaderBindingAt(shader, 1, 0, BindingKind.Texture) == 1;
	assert shaderBindingAt(shader, 1, 1, BindingKind.Sampler) == 2;
	assert shaderBindingAt(shader, 1, 0, BindingKind.Uniform) < 0;
	assert shaderBindingAt(shader, 1, 0, BindingKind.Sampler) < 0;
	assert shaderBindingAt(shader, 1, 2, BindingKind.Texture) < 0;
}

test "a vertex buffer slot outside the pipeline's slots is refused" {
	assert vertexSlotRefusal(0) == "";
	assert vertexSlotRefusal(1) == "";
	assert vertexSlotRefusal(2) == "setVertexBuffer slot 2 is outside the 2 vertex buffer slots";
	assert vertexSlotRefusal(-1) == "setVertexBuffer slot -1 is outside the 2 vertex buffer slots";
}

test "a uniform entry is refused by usage, alignment, overrun and size below its block" {
	assert uniformEntryRefusal(entryAt(256, 0), true, 512, 64, 256) == "";
	assert uniformEntryRefusal(entryAt(256, 0), false, 512, 64, 256) == "bind group entry 2 needs a UNIFORM buffer";
	assert uniformEntryRefusal(entryAt(100, 0), true, 512, 64, 256) == "bind group entry 2 offset 100 is not a multiple of 256";
	assert uniformEntryRefusal(entryAt(512, 0), true, 512, 64, 256) == "bind group entry 2 offset 512 overruns its buffer";
	assert uniformEntryRefusal(entryAt(0, 16), true, 512, 64, 256) == "bind group entry 2 size 16 is below its block of 64";
	assert uniformEntryRefusal(entryAt(0, 16), true, 512, 64, 16) == "bind group entry 2 size 16 is below its block of 64";
}

const MAP_READ = GPUBufferUsage.MAP_READ as int32;
const MAP_WRITE = GPUBufferUsage.MAP_WRITE as int32;
const COPY_SRC = GPUBufferUsage.COPY_SRC as int32;
const COPY_DST = GPUBufferUsage.COPY_DST as int32;
const VERTEX = GPUBufferUsage.VERTEX as int32;
const STORAGE = GPUBufferUsage.STORAGE as int32;
const ATTACHMENT = GPUTextureUsage.RENDER_ATTACHMENT as int32;
const SAMPLED = GPUTextureUsage.TEXTURE_BINDING as int32;
const RENDER_STAGES = (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);

function smallLimits(): GPUSupportedLimits {
	return { maxTextureDimension2D: 4096, maxTextureDimension3D: 256, maxTextureArrayLayers: 8 };
}

function texture(width: int32, height: int32, layers: int32): GPUTextureDescriptor {
	return { size: { width: width, height: height, depthOrArrayLayers: layers }, format: "rgba8unorm", usage: SAMPLED };
}

test "a buffer needs a positive size and a mappable buffer only its direction's copy usage" {
	assert bufferRefusal(16, VERTEX | COPY_DST) == "";
	assert bufferRefusal(0, VERTEX) == "GPUBufferDescriptor.size must be positive";
	assert bufferRefusal(-4, VERTEX) == "GPUBufferDescriptor.size must be positive";
	assert bufferRefusal(16, MAP_READ | COPY_DST) == "";
	assert bufferRefusal(16, MAP_READ | VERTEX) == "GPUBufferUsage MAP_READ combines only with COPY_DST";
	assert bufferRefusal(16, MAP_WRITE | COPY_SRC) == "";
	assert bufferRefusal(16, MAP_WRITE | COPY_DST) == "GPUBufferUsage MAP_WRITE combines only with COPY_SRC";
}

function written(usage: int32, frame: int64, end: int64): BufferRecord {
	return { id: 7, size: 64, usage: usage, writtenFrame: frame, writtenEnd: end };
}

test "writeBuffer needs COPY_DST and a 4-byte-aligned offset inside the buffer" {
	assert writeBufferRefusal(written(VERTEX | COPY_DST, -1, 0), 0, 64, 3) == "";
	assert writeBufferRefusal(written(VERTEX, -1, 0), 0, 16, 3) == "GPUBuffer 7 was created without COPY_DST";
	assert writeBufferRefusal(written(VERTEX | COPY_DST, -1, 0), 56, 16, 3) == "writeBuffer of 16 bytes at 56 overruns GPUBuffer 7 of 64";
	assert writeBufferRefusal(written(VERTEX | COPY_DST, -1, 0), -4, 4, 3) == "writeBuffer of 4 bytes at -4 overruns GPUBuffer 7 of 64";
	assert writeBufferRefusal(written(VERTEX | COPY_DST, -1, 0), 2, 4, 3) == "writeBuffer offset 2 is not a multiple of 4";
}

test "writeBuffer takes an unmapped MAP_READ buffer and refuses it while mapped" {
	let buffer = written(MAP_READ | COPY_DST, -1, 0);
	assert writeBufferRefusal(buffer, 0, 16, 3) == "";
	buffer.mapMode = GPUMapMode.READ as int32;
	assert writeBufferRefusal(buffer, 0, 16, 3) == "writeBuffer on GPUBuffer 7, which is mapped";
}

test "a copy reads a COPY_SRC buffer and writes a COPY_DST one, neither of them mapped" {
	let buffer = written(COPY_SRC, -1, 0);
	assert copyBufferRefusal("copyBufferToBuffer", buffer, true) == "";
	assert copyBufferRefusal("copyBufferToBuffer", buffer, false) == "copyBufferToBuffer destination: GPUBuffer 7 was created without COPY_DST";
	assert copyBufferRefusal("copyTextureToBuffer", written(VERTEX, -1, 0), true) == "copyTextureToBuffer source: GPUBuffer 7 was created without COPY_SRC";
	buffer.mapMode = GPUMapMode.WRITE as int32;
	assert copyBufferRefusal("copyBufferToBuffer", buffer, true) == "copyBufferToBuffer source: GPUBuffer 7 is mapped";
}

test "a copy reads a COPY_SRC texture and writes a COPY_DST one, single-sampled unless it is the swapchain's" {
	let texture: TextureRecord = { id: 9, width: 4, height: 4, format: "rgba8unorm", usage: GPUTextureUsage.COPY_SRC as int32, sampleCount: 1 };
	assert copyTextureRefusal("copyTextureToTexture", texture, true) == "";
	assert copyTextureRefusal("copyTextureToTexture", texture, false) == "copyTextureToTexture destination: GPUTexture 9 was created without COPY_DST";
	texture.sampleCount = 4;
	assert copyTextureRefusal("copyTextureToBuffer", texture, true) == "copyTextureToBuffer source: GPUTexture 9 is multisampled";
	texture.swapchainView = 3;
	assert copyTextureRefusal("copyTextureToBuffer", texture, true) == "";
}

test "a frame writes each buffer's bytes once, appending after its last write, whatever the usage" {
	const rewrite = "writeBuffer at 8 on GPUBuffer 7 rewrites bytes this frame already wrote, up to 16";
	assert writeBufferRefusal(written(VERTEX | COPY_DST, 3, 16), 8, 4, 3) == rewrite;
	assert writeBufferRefusal(written(STORAGE | COPY_DST, 3, 16), 8, 4, 3) == rewrite;
	assert writeBufferRefusal(written(MAP_READ | COPY_DST, 3, 16), 8, 4, 3) == rewrite;
	assert writeBufferRefusal(written(STORAGE | COPY_DST, 3, 16), 16, 4, 3) == "";
	assert writeBufferRefusal(written(STORAGE | COPY_DST, 2, 16), 0, 4, 3) == "";
}

test "a draw refuses firstInstance and firstVertex or baseVertex only where the vertex stage reads their index" {
	const reads: PipelineRecord = { id: 3, label: "quad", readsInstanceIndex: true, readsVertexIndex: true };
	const plain: PipelineRecord = { id: 4, label: "plain" };
	assert drawOffsetRefusal(reads, "draw", "firstVertex", 0, 0) == "";
	assert drawOffsetRefusal(plain, "draw", "firstVertex", 6, 2) == "";
	assert drawOffsetRefusal(reads, "draw", "firstVertex", 0, 2) == "draw with firstInstance 2 on pipeline 'quad': firstInstance must be 0 because the vertex stage reads instance_index";
	assert drawOffsetRefusal(reads, "draw", "firstVertex", 6, 0) == "draw with firstVertex 6 on pipeline 'quad': firstVertex must be 0 because the vertex stage reads vertex_index";
	assert drawOffsetRefusal(reads, "drawIndexed", "baseVertex", -3, 0) == "drawIndexed with baseVertex -3 on pipeline 'quad': baseVertex must be 0 because the vertex stage reads vertex_index";
}

test "a texture size is positive and inside the backend's limits for its dimension" {
	const limits = smallLimits();
	assert textureRefusal(texture(256, 128, 1), limits) == "";
	assert textureRefusal(texture(0, 128, 1), limits) == "GPUTextureDescriptor.size needs a positive width and height";
	assert textureRefusal(texture(8, -1, 1), limits) == "GPUTextureDescriptor.size needs a positive width and height";
	assert textureRefusal(texture(4097, 8, 1), limits) == "GPUTextureDescriptor.size 4097x8x1 is over the limits 4096 per side and 8 array layers";
	assert textureRefusal(texture(8, 8, 9), limits) == "GPUTextureDescriptor.size 8x8x9 is over the limits 4096 per side and 8 array layers";
	assert textureRefusal(texture(8, 8, -1), limits) == "GPUTextureDescriptor.size.depthOrArrayLayers is negative";
	let volume = texture(64, 64, 257);
	volume.dimension = "3d";
	assert textureRefusal(volume, limits) == "GPUTextureDescriptor.size 64x64x257 is over the limits 256 per side and 8 array layers";
	volume.size.depthOrArrayLayers = 200;
	assert textureRefusal(volume, limits) == "";
}

test "the same size is refused or accepted by the limits the backend reports, not by a constant" {
	const big = texture(8192, 8192, 1);
	assert textureRefusal(big, smallLimits()) != "";
	let wide = smallLimits();
	wide.maxTextureDimension2D = 16384;
	assert textureRefusal(big, wide) == "";
}

test "a texture mip count stops at the chain its largest side allows, and a 3d texture counts its depth" {
	const limits = smallLimits();
	let t = texture(16, 8, 1);
	t.mipLevelCount = 5;
	assert textureRefusal(t, limits) == "";
	t.mipLevelCount = 6;
	assert textureRefusal(t, limits) == "GPUTextureDescriptor.mipLevelCount 6 is outside 1..5 for a 16x8 texture";
	t.mipLevelCount = -1;
	assert textureRefusal(t, limits) == "GPUTextureDescriptor.mipLevelCount -1 is outside 1..5 for a 16x8 texture";
	let volume = texture(4, 4, 64);
	volume.dimension = "3d";
	volume.mipLevelCount = 7;
	assert textureRefusal(volume, limits) == "";
}

test "a multisampled texture is a single-mip single-layer 2d render attachment" {
	const limits = smallLimits();
	let t = texture(16, 16, 1);
	t.sampleCount = 4;
	assert textureRefusal(t, limits) == "a multisampled texture must be a RENDER_ATTACHMENT";
	t.usage = ATTACHMENT;
	assert textureRefusal(t, limits) == "";
	t.size.depthOrArrayLayers = 2;
	assert textureRefusal(t, limits) == "WebGPU allows a multisampled texture only as a 2d texture with one mip level and one array layer";
	t.size.depthOrArrayLayers = 1;
	t.mipLevelCount = 2;
	assert textureRefusal(t, limits) == "WebGPU allows a multisampled texture only as a 2d texture with one mip level and one array layer";
}

test "a depth or stencil format is a 2d texture only" {
	const limits = smallLimits();
	assert isDepthFormat("depth16unorm");
	assert isDepthFormat("depth32float");
	assert isDepthFormat("depth24plus-stencil8");
	assert !isDepthFormat("rgba8unorm");
	assert !isDepthFormat("r32float");
	let t = texture(8, 8, 8);
	t.dimension = "3d";
	t.format = "depth32float";
	assert textureRefusal(t, limits) == "WebGPU allows a depth or stencil format only on a 2d texture";
	t.format = "depth24plus-stencil8";
	assert textureRefusal(t, limits) == "WebGPU allows a depth or stencil format only on a 2d texture";
	t.dimension = "2d";
	t.size.depthOrArrayLayers = 1;
	assert textureRefusal(t, limits) == "";
}

function computeLimits(): GPUSupportedLimits {
	return {
		maxUniformBufferBindingSize: 65536,
		maxComputeWorkgroupSizeX: 1024,
		maxComputeWorkgroupSizeY: 1024,
		maxComputeWorkgroupSizeZ: 64,
		maxComputeInvocationsPerWorkgroup: 1024,
	};
}

function computeModule(x: int32, y: int32, z: int32): GPUShaderModuleDescriptor {
	return { computeCode: "kernel", workgroupSize: [x, y, z] };
}

test "a shader module is a compute module or a vertex and fragment module, in code or bytecode" {
	const limits = computeLimits();
	assert shaderModuleRefusal(computeModule(8, 8, 1), limits) == "";
	let mixed = computeModule(8, 8, 1);
	mixed.vertexCode = "vs";
	assert shaderModuleRefusal(mixed, limits) == "a GPUShaderModule is either a compute module or a vertex and fragment module";
	let bytes = computeModule(8, 8, 1);
	bytes.fragmentBytecode = [1, 2, 3];
	assert shaderModuleRefusal(bytes, limits) == "a GPUShaderModule is either a compute module or a vertex and fragment module";
	let compiled = computeModule(8, 8, 1);
	compiled.computeCode = "";
	compiled.computeBytecode = [1];
	compiled.vertexCode = "vs";
	assert shaderModuleRefusal(compiled, limits) != "";
	const render: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	assert shaderModuleRefusal(render, limits) == "";
}

test "a compute workgroup is refused past any one axis or the invocation total of the backend's limits" {
	const limits = computeLimits();
	assert shaderModuleRefusal(computeModule(1024, 1, 1), limits) == "";
	assert shaderModuleRefusal(computeModule(1025, 1, 1), limits) == "workgroupSize 1025x1x1 is over the limits 1024x1024x64 and 1024 invocations";
	assert shaderModuleRefusal(computeModule(1, 1, 65), limits) == "workgroupSize 1x1x65 is over the limits 1024x1024x64 and 1024 invocations";
	assert shaderModuleRefusal(computeModule(64, 32, 1), limits) != "";
	let small = computeLimits();
	small.maxComputeInvocationsPerWorkgroup = 256;
	assert shaderModuleRefusal(computeModule(16, 16, 1), small) == "";
	assert shaderModuleRefusal(computeModule(32, 16, 1), small) != "";
	const render: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs", workgroupSize: [4096, 1, 1] };
	assert shaderModuleRefusal(render, limits) == "";
}

test "a shader module holds at most 8 uniform blocks and 16 resources, and a block has a size inside the limit" {
	const limits = computeLimits();
	let blocks: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	for (let i = 0; i < 8; i++) { blocks.bindings[i] = { binding: i, kind: "uniform", size: 16, visibility: RENDER_STAGES }; }
	assert shaderModuleRefusal(blocks, limits) == "";
	blocks.bindings[8] = { binding: 8, kind: "uniform", size: 16, visibility: RENDER_STAGES };
	assert shaderModuleRefusal(blocks, limits) == "a shader module has over 8 uniform blocks";
	let resources: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	for (let i = 0; i < 16; i++) { resources.bindings[i] = { binding: i, kind: "texture", group: 1, visibility: RENDER_STAGES }; }
	assert shaderModuleRefusal(resources, limits) == "";
	resources.bindings[16] = { binding: 16, kind: "sampler", group: 1, visibility: RENDER_STAGES };
	assert shaderModuleRefusal(resources, limits) == "a shader module has over 16 resources";
	let sized: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	sized.bindings[0] = { binding: 3, kind: "uniform", size: 0, visibility: RENDER_STAGES };
	assert shaderModuleRefusal(sized, limits) == "uniform binding 3 needs its block size";
	sized.bindings[0].size = 65536;
	assert shaderModuleRefusal(sized, limits) == "";
	sized.bindings[0].size = 65552;
	assert shaderModuleRefusal(sized, limits) == "uniform binding 3 of 65552 bytes is over the limit of 65536";
}

test "a shader binding is visible only to its module's stages and lives in its kind's group" {
	const limits = computeLimits();
	let render: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	render.bindings[0] = { binding: 2, kind: "texture", group: 1, visibility: GPUShaderStage.FRAGMENT as int32 };
	assert shaderModuleRefusal(render, limits) == "";
	render.bindings[0].visibility = 0;
	assert shaderModuleRefusal(render, limits) == "shader binding 2 has visibility 0, but a vertex and fragment module allows only 3";
	render.bindings[0].visibility = GPUShaderStage.COMPUTE as int32;
	assert shaderModuleRefusal(render, limits) == "shader binding 2 has visibility 4, but a vertex and fragment module allows only 3";
	render.bindings[0].visibility = RENDER_STAGES;
	render.bindings[0].group = 0;
	assert shaderModuleRefusal(render, limits) == "shader binding 2 (texture) belongs in group 1, not 0";
	let kernel = computeModule(8, 1, 1);
	kernel.bindings[0] = { binding: 0, kind: "uniform", size: 16, group: 1, visibility: GPUShaderStage.COMPUTE as int32 };
	assert shaderModuleRefusal(kernel, limits) == "shader binding 0 (uniform) belongs in group 0, not 1";
	kernel.bindings[0].visibility = GPUShaderStage.VERTEX as int32;
	assert shaderModuleRefusal(kernel, limits) == "shader binding 0 has visibility 1, but a compute module allows only 4";
}

test "an integer texture pairs only with a non-filtering sampler" {
	const limits = computeLimits();
	let module: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	module.bindings[0] = { binding: 0, kind: "texture", sampleType: "uint", group: 1, visibility: RENDER_STAGES };
	module.bindings[1] = { binding: 1, kind: "sampler", textureBinding: 0, samplerType: "non-filtering", group: 1, visibility: RENDER_STAGES };
	assert shaderModuleRefusal(module, limits) == "";
	module.bindings[1].samplerType = "filtering";
	assert shaderModuleRefusal(module, limits) == "sampler binding 1 is 'filtering' but pairs with the uint texture binding 0; an integer texture needs a non-filtering sampler";
	module.bindings[0].sampleType = "float";
	assert shaderModuleRefusal(module, limits) == "";
}

test "a sampler's anisotropy defaults to 1 and is clamped to 16 on every backend" {
	assert clampedAnisotropy(0) == 1;
	assert clampedAnisotropy(8) == 8;
	assert clampedAnisotropy(64) == 16;
}

test "a sampler's anisotropy needs every filter linear, and its lod range is non-negative and ordered" {
	let s: GPUSamplerDescriptor = { magFilter: "linear", minFilter: "linear", mipmapFilter: "linear", maxAnisotropy: 8 };
	assert samplerRefusal(s) == "";
	s.mipmapFilter = "nearest";
	assert samplerRefusal(s) == "GPUSamplerDescriptor.maxAnisotropy above 1 needs linear magFilter, minFilter and mipmapFilter";
	s.maxAnisotropy = 1;
	assert samplerRefusal(s) == "";
	s.maxAnisotropy = -1;
	assert samplerRefusal(s) == "GPUSamplerDescriptor.maxAnisotropy -1 is below 1";
	s.maxAnisotropy = 0;
	assert samplerRefusal(s) == "";
	s.lodMinClamp = -1;
	assert samplerRefusal(s) == "GPUSamplerDescriptor.lodMinClamp -1 is negative";
	s.lodMinClamp = 4;
	s.lodMaxClamp = 2;
	assert samplerRefusal(s) == "GPUSamplerDescriptor.lodMaxClamp 2 is below lodMinClamp 4";
	s.lodMaxClamp = 0;
	assert samplerRefusal(s) == "";
}

test "a query set is a timestamp or occlusion set of 1 to 4096 queries" {
	const timestamps: GPUQuerySetDescriptor = { type: "timestamp", count: 4096 };
	assert querySetRefusal(timestamps, true) == "";
	const empty: GPUQuerySetDescriptor = { type: "occlusion", count: 0 };
	assert querySetRefusal(empty, true) == "GPUQuerySetDescriptor.count 0 is outside 1..4096";
	const untyped: GPUQuerySetDescriptor = { count: 4 };
	assert querySetRefusal(untyped, true) == "GPUQuerySetDescriptor.type '' is neither 'timestamp' nor 'occlusion'";
	assert querySetRefusal(timestamps, false) == "this device has no timestamp queries: features().has('timestamp-query') is false";
	const occlusion: GPUQuerySetDescriptor = { type: "occlusion", count: 4 };
	assert querySetRefusal(occlusion, false) == "";
}

test "resolveQuerySet reads only queries a pass wrote and closed" {
	let set: QuerySetRecord = { id: 3, count: 3, state: [QueryState.Written, QueryState.Open, QueryState.Unwritten] };
	assert queriesWrittenRefusal(set, 0, 1) == "";
	assert queriesWrittenRefusal(set, 0, 2) == "resolveQuerySet: query 1 is still open";
	assert queriesWrittenRefusal(set, 2, 1) == "resolveQuerySet: query 2 was never written";
	assert queriesWrittenRefusal(set, 1, 0) == "";
}

test "a viewport and a dispatch stay inside WebGPU's ranges and the backend's limit" {
	assert viewportRefusal(64, 32, 0, 1) == "";
	assert viewportRefusal(-1, 32, 0, 1) == "setViewport -1x32 depth 0..1 is outside WebGPU's valid range";
	assert viewportRefusal(64, 32, 0.75, 0.5) == "setViewport 64x32 depth 0.75..0.5 is outside WebGPU's valid range";
	assert dispatchRefusal(0, 1, 65535, 65535) == "";
	assert dispatchRefusal(1, 1, 65536, 65535) == "dispatchWorkgroups 1,1,65536 is outside 0..65535";
	assert dispatchRefusal(-1, 1, 1, 65535) == "dispatchWorkgroups -1,1,1 is outside 0..65535";
}

test "a scissor rect lies inside the pass attachment" {
	assert scissorRefusal(0, 0, 64, 32, 64, 32) == "";
	assert scissorRefusal(8, 8, 0, 0, 64, 32) == "";
	assert scissorRefusal(1, 0, 64, 32, 64, 32) == "setScissorRect 1,0 64x32 lies outside the 64x32 attachment";
	assert scissorRefusal(-1, 0, 8, 8, 64, 32) == "setScissorRect -1,0 8x8 lies outside the 64x32 attachment";
	assert scissorRefusal(0, 30, 8, 3, 64, 32) == "setScissorRect 0,30 8x3 lies outside the 64x32 attachment";
}

test "a render pipeline takes its vertex and fragment stages from one module" {
	let pipeline: GPURenderPipelineDescriptor = { vertex: { module: { id: 3 } }, fragment: { module: { id: 3 } } };
	assert renderPipelineRefusal(pipeline) == "";
	pipeline.fragment.module = { id: 4 };
	assert renderPipelineRefusal(pipeline) == "vertex and fragment stages come from one GPUShaderModule in Void";
	pipeline.fragment.module = { id: 3 };
	pipeline.primitive = { topology: "triangle-list", stripIndexFormat: "uint16" };
	assert renderPipelineRefusal(pipeline) == "primitive.stripIndexFormat 'uint16' needs a strip topology";
}

test "a render pipeline blends only a target whose format is not an integer one" {
	let pipeline: GPURenderPipelineDescriptor = { vertex: { module: { id: 3 } }, fragment: { module: { id: 3 } } };
	pipeline.fragment.targets[1] = { format: "rgba8unorm", blendEnabled: true };
	assert renderPipelineRefusal(pipeline) == "";
	pipeline.fragment.targets[2] = { format: "r32uint" };
	assert renderPipelineRefusal(pipeline) == "";
	pipeline.fragment.targets[2].blendEnabled = true;
	assert renderPipelineRefusal(pipeline) == "fragment.targets[2] blends r32uint, an integer format";
}

test "a stripIndexFormat needs a strip topology" {
	assert isStripTopology("line-strip");
	assert isStripTopology("triangle-strip");
	assert !isStripTopology("triangle-list");
	assert !isStripTopology("");
	const strip: GPUPrimitiveState = { topology: "triangle-strip", stripIndexFormat: "uint16" };
	assert primitiveRefusal(strip) == "";
	const list: GPUPrimitiveState = { topology: "triangle-list", stripIndexFormat: "uint32" };
	assert primitiveRefusal(list) == "primitive.stripIndexFormat 'uint32' needs a strip topology";
	const none: GPUPrimitiveState = { topology: "line-list" };
	assert primitiveRefusal(none) == "";
}

test "a pipeline takes the module kind it is for, and a compute entry point the module declares" {
	assert renderModuleRefusal(false) == "";
	assert renderModuleRefusal(true) == "a compute GPUShaderModule cannot make a GPURenderPipeline";
	assert computeModuleRefusal(true, "main", "main") == "";
	assert computeModuleRefusal(false, "main", "main") == "createComputePipeline needs a GPUShaderModule made with computeCode";
	assert computeModuleRefusal(true, "other", "main") == "compute.entryPoint 'other' differs from the module's computeEntryPoint 'main'";
	assert computePipelineRefusal(7, true) == "";
	assert computePipelineRefusal(7, false) == "GPUPipeline 7 is not a compute pipeline";
	assert renderPassPipelineRefusal(7, false) == "";
	assert renderPassPipelineRefusal(7, true) == "GPUPipeline 7 is a compute pipeline: setPipeline on a render pass takes a render pipeline";
}

test "an indexed strip draw needs the pipeline's strip index format to be the bound index format, none included" {
	assert stripDrawRefusal(false, false) == "";
	assert stripDrawRefusal(true, true) == "";
	assert stripDrawRefusal(true, false) == "an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format";
}

test "a draw needs a pipeline and an indexed draw an index buffer, both set in this pass" {
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.drawRefusal("draw", false) == "draw without setPipeline";
	assert s.drawRefusal("drawIndexed", true) == "drawIndexed without setPipeline";
	s.markPipeline();
	assert s.drawRefusal("draw", false) == "";
	assert s.drawRefusal("drawIndexed", true) == "drawIndexed without setIndexBuffer";
	s.markIndexBuffer();
	assert s.drawRefusal("drawIndexed", true) == "";
}

test "a new pass starts with no pipeline and no index buffer, whatever the last pass set" {
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	s.markPipeline();
	s.markIndexBuffer();
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.drawRefusal("draw", false) == "draw without setPipeline";
	s.markPipeline();
	assert s.drawRefusal("drawIndexed", true) == "drawIndexed without setIndexBuffer";
}

test "a dispatch needs the pipeline its compute pass set, naming the call" {
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.pipelineSetRefusal("dispatchWorkgroups") == "dispatchWorkgroups without setPipeline";
	assert s.pipelineSetRefusal("dispatchWorkgroupsIndirect") == "dispatchWorkgroupsIndirect without setPipeline";
	s.markPipeline();
	assert s.pipelineSetRefusal("dispatchWorkgroups") == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.pipelineSetRefusal("dispatchWorkgroups") == "dispatchWorkgroups without setPipeline";
}

test "an occlusion query needs the pass's occlusion set, one open at a time, closed before the pass ends" {
	let none = openEncoder();
	assert none.beginPassRefusal(PASS_RENDER) == "";
	assert none.beginOcclusionRefusal(0) == "beginOcclusionQuery needs GPURenderPassDescriptor.occlusionQuerySet";
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	s.attachOcclusion(5);
	assert s.beginOcclusionRefusal(2) == "";
	assert s.occlusionIndex == 2;
	assert s.beginOcclusionRefusal(3) == "beginOcclusionQuery with an occlusion query already open";
	assert s.endPassRefusal(PASS_RENDER) == "end with an occlusion query still open";
	assert s.endOcclusionRefusal() == "";
	assert s.endOcclusionRefusal() == "endOcclusionQuery without an open occlusion query";
	assert s.endPassRefusal(PASS_RENDER) == "";
}

test "a pass keeps no occlusion set of the pass before it" {
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	s.attachOcclusion(5);
	assert s.beginOcclusionRefusal(0) == "";
	assert s.endOcclusionRefusal() == "";
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.beginOcclusionRefusal(0) == "beginOcclusionQuery needs GPURenderPassDescriptor.occlusionQuerySet";
}

test "an occlusion index is inside its set and used once per pass, across passes and encoders" {
	assert occlusionRangeRefusal(0, 4) == "";
	assert occlusionRangeRefusal(3, 4) == "";
	assert occlusionRangeRefusal(4, 4) == "beginOcclusionQuery index 4 is outside the query set of 4";
	assert occlusionRangeRefusal(-1, 4) == "beginOcclusionQuery index -1 is outside the query set of 4";
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	const first = s.serial;
	assert s.occlusionReuseRefusal(1, 0) == "";
	assert s.occlusionReuseRefusal(1, first) == "beginOcclusionQuery index 1 was already used in this pass";
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
	assert s.finishRefusal() == "";
	assert s.createRefusal() == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.serial == first + 2;
	assert s.occlusionReuseRefusal(1, first) == "";
	assert s.occlusionReuseRefusal(1, s.serial) != "";
}

test "an occlusion slot takes an occlusion set, not a timestamp set" {
	assert occlusionSetKindRefusal(false) == "";
	assert occlusionSetKindRefusal(true) == "GPURenderPassDescriptor.occlusionQuerySet is a timestamp set: an occlusion set is required";
}

test "a view takes its texture's dimension unless it names one, and 3d goes with 3d only" {
	assert resolvedViewDimension("", false, 1) == "2d";
	assert resolvedViewDimension("", false, 6) == "2d-array";
	assert resolvedViewDimension("", true, 1) == "3d";
	assert resolvedViewDimension("cube", false, 6) == "cube";
	assert viewDimensionRefusal("2d", false, 9) == "";
	assert viewDimensionRefusal("3d", true, 9) == "";
	assert viewDimensionRefusal("3d", false, 9) == "GPUTextureViewDescriptor.dimension '3d' does not match the 2d GPUTexture 9";
	assert viewDimensionRefusal("2d-array", true, 9) == "GPUTextureViewDescriptor.dimension '2d-array' does not match the 3d GPUTexture 9";
}

function viewRefusal(descriptor: GPUTextureViewDescriptor, mipLevels: int32, layers: int32, volume: boolean, cube: boolean): string {
	return viewRangeRefusal(descriptor, resolvedViewRange(descriptor, mipLevels, layers, volume), 9, mipLevels, layers, volume, cube);
}

test "a view range takes the rest of the texture for a count of 0, one layer for 2d and six for a cube" {
	const rest = resolvedViewRange({ baseMipLevel: 1, baseArrayLayer: 2 }, 4, 6, false);
	assert rest.dimension == "2d-array" && rest.mipCount == 3 && rest.baseLayer == 2 && rest.layerCount == 4;
	assert resolvedViewRange({ dimension: "2d", baseArrayLayer: 3 }, 1, 6, false).layerCount == 1;
	assert resolvedViewRange({ dimension: "cube" }, 1, 12, false).layerCount == 6;
	const volume = resolvedViewRange({}, 2, 8, true);
	assert volume.dimension == "3d" && volume.baseLayer == 0 && volume.layerCount == 1;
}

test "a view range stays inside its texture's mips and layers, and a cube view takes whole cubes" {
	assert viewRefusal({}, 4, 6, false, true) == "";
	assert viewRefusal({ baseMipLevel: 2, mipLevelCount: 3 }, 4, 1, false, false) == "view mips 2+3 overrun GPUTexture 9, which has 4 mips";
	assert viewRefusal({ dimension: "3d" }, 1, 1, false, false) == "GPUTextureViewDescriptor.dimension '3d' does not match the 2d GPUTexture 9";
	assert viewRefusal({ baseArrayLayer: 1 }, 1, 8, true, false) == "a 3d view takes no baseArrayLayer or arrayLayerCount";
	assert viewRefusal({ baseArrayLayer: 4, arrayLayerCount: 4 }, 1, 6, false, false) == "view layers 4+4 overrun GPUTexture 9, which has 6 layers";
	assert viewRefusal({ dimension: "cube" }, 1, 6, false, false) == "a cube view needs GPUTexture 9 created square, with TEXTURE_BINDING and a depthOrArrayLayers multiple of 6";
	assert viewRefusal({ dimension: "cube-array", arrayLayerCount: 9 }, 1, 12, false, true) == "a cube view takes whole cubes: baseArrayLayer and arrayLayerCount multiples of 6";
	assert viewRefusal({ dimension: "cube", baseArrayLayer: 6 }, 1, 12, false, true) == "";
}

test "a texture can take a cube view when square, sampled, single-sample and a multiple of 6 layers" {
	const sampled = GPUTextureUsage.TEXTURE_BINDING as int32;
	assert cubeCapable(false, 12, 64, 64, sampled, 1);
	assert !cubeCapable(false, 6, 64, 32, sampled, 1);
	assert !cubeCapable(false, 6, 64, 64, 0, 1);
	assert !cubeCapable(false, 6, 64, 64, sampled, 4);
	assert !cubeCapable(true, 6, 64, 64, sampled, 1);
}

test "setBindGroup takes the door's two groups" {
	assert bindGroupIndexRefusal(0) == "";
	assert bindGroupIndexRefusal(1) == "";
	assert bindGroupIndexRefusal(2) == "setBindGroup index 2 is outside the 2 bind groups";
	assert bindGroupIndexRefusal(-1) == "setBindGroup index -1 is outside the 2 bind groups";
}

test "a bind group is set in the group it was made for, with its dynamic offsets aligned" {
	const none: Vec<uint32> = [];
	const aligned: Vec<uint32> = [0, 512];
	const crooked: Vec<uint32> = [256, 100];
	assert bindGroupSetRefusal(0, 0, 0, none, 256) == "";
	assert bindGroupSetRefusal(0, 0, 2, aligned, 256) == "";
	assert bindGroupSetRefusal(1, 0, 0, none, 256) == "setBindGroup(1) with a bind group made for group 0";
	assert bindGroupSetRefusal(0, 0, 1, none, 256) == "setBindGroup(0) takes 1 dynamic offsets, got 0";
	assert bindGroupSetRefusal(0, 0, 0, aligned, 256) == "setBindGroup(0) takes 0 dynamic offsets, got 2";
	assert bindGroupSetRefusal(0, 0, 2, crooked, 256) == "dynamic offset 100 is not a multiple of 256";
	assert bindGroupSetRefusal(0, 0, 2, crooked, 4) == "";
	assert bindGroupSetRefusal(1, 1, 1, aligned, 256) == "setBindGroup(1) takes 1 dynamic offsets, got 2";
}

test "a uniform group takes one dynamic offset per buffer entry" {
	let descriptor: GPUBindGroupDescriptor = { label: null };
	assert uniformEntryCount(descriptor) == 0;
	descriptor.entries[0].buffer = { id: 5 };
	descriptor.entries[1].sampler = { id: 7 };
	descriptor.entries[3].buffer = { id: 6 };
	assert uniformEntryCount(descriptor) == 2;
}

test "a buffer entry's dynamic offset is its rank by binding among the stored entries" {
	let descriptor: GPUBindGroupDescriptor = { label: null };
	descriptor.entries[0] = { binding: 4, buffer: { id: 5 } };
	descriptor.entries[2] = { binding: 1, sampler: { id: 7 } };
	descriptor.entries[3] = { binding: 2, buffer: { id: 6 } };
	const ranks = dynamicIndexOf(descriptor);
	assert ranks[0] == 1;
	assert ranks[1] == 0;
	assert ranks[2] == 0;
}

test "a storage entry is a positive multiple of 4 bytes inside a STORAGE buffer, on the backend's alignment and limit" {
	assert entryBytes(entryAt(0, 0), 64) == 64;
	assert entryBytes(entryAt(16, 0), 64) == 48;
	assert entryBytes(entryAt(16, 8), 64) == 8;
	assert storageEntryRefusal(entryAt(0, 0), true, 64, 32, 1024) == "";
	assert storageEntryRefusal(entryAt(32, 32), true, 64, 32, 1024) == "";
	assert storageEntryRefusal(entryAt(0, 0), false, 64, 32, 1024) == "bind group entry 2 needs a STORAGE buffer";
	assert storageEntryRefusal(entryAt(16, 0), true, 64, 32, 1024) == "bind group entry 2 offset 16 is not a multiple of 32";
	assert storageEntryRefusal(entryAt(-32, 0), true, 64, 32, 1024) == "bind group entry 2 offset -32 is not a multiple of 32";
	assert storageEntryRefusal(entryAt(0, 6), true, 64, 32, 1024) == "bind group entry 2 range 0+6 is not a positive multiple of 4 inside its buffer of 64";
	assert storageEntryRefusal(entryAt(0, 68), true, 64, 32, 1024) == "bind group entry 2 range 0+68 is not a positive multiple of 4 inside its buffer of 64";
	assert storageEntryRefusal(entryAt(64, 0), true, 64, 32, 1024) == "bind group entry 2 range 64+0 is not a positive multiple of 4 inside its buffer of 64";
	assert storageEntryRefusal(entryAt(0, 0), true, 66, 32, 1024) == "bind group entry 2 range 0+66 is not a positive multiple of 4 inside its buffer of 66";
	assert storageEntryRefusal(entryAt(0, 64), true, 64, 32, 32) == "bind group entry 2 range of 64 bytes is over the limit of 32";
	assert storageEntryRefusal(entryAt(0, 64), true, 64, 256, 64) == "";
}

test "a texture view binds as a sampled texture or a one-mip storage texture only if its texture allows it" {
	assert sampledViewRefusal(3, true) == "";
	assert sampledViewRefusal(3, false) == "bind group entry 3: the view's texture lacks TEXTURE_BINDING";
	assert storageViewRefusal(3, true, 1, "rgba8unorm", "rgba8unorm") == "";
	assert storageViewRefusal(3, false, 1, "rgba8unorm", "rgba8unorm") == "bind group entry 3: the view's texture lacks STORAGE_BINDING";
	assert storageViewRefusal(3, true, 2, "rgba8unorm", "rgba8unorm") == "bind group entry 3: a storage texture view takes exactly one mip";
	assert storageViewRefusal(3, true, 1, "r32float", "rgba8unorm") == "bind group entry 3: the shader declares storage format 'r32float' and the view's texture is 'rgba8unorm'";
	const undeclared: GPUShaderBinding = { kind: "storage-texture" };
	assert storageViewRefusal(3, true, 1, undeclared.storageFormat, "rgba8unorm") == "";
}

function colorTarget(width: int32, height: int32, sampleCount: int32): AttachmentFacts {
	return { texture: 5, renderable: true, single: true, width: width, height: height, layers: 1, sampleCount: sampleCount };
}

function onePass(color: AttachmentFacts): RenderPassFacts {
	let facts: RenderPassFacts = { depth: { texture: 0 } };
	facts.colors[0] = color;
	return facts;
}

function colorPass(): GPURenderPassDescriptor {
	let descriptor: GPURenderPassDescriptor = { label: null };
	descriptor.colorAttachments[0].view = { id: 1 };
	return descriptor;
}

test "a render pass takes renderable one-mip one-layer attachments of one size" {
	let descriptor = colorPass();
	let facts = onePass(colorTarget(64, 32, 1));
	assert renderPassRefusal(descriptor, facts) == "";
	assert renderPassExtent(descriptor, facts).width == 64 && renderPassExtent(descriptor, facts).height == 32;
	facts.colors[0].depth = true;
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].view is not a color RENDER_ATTACHMENT";
	facts.colors[0] = { ...colorTarget(64, 32, 1), single: false };
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].view spans several mips or layers: a render attachment is one mip of one layer";
	facts.colors[0] = { ...colorTarget(64, 32, 1), baseMip: 1 };
	assert renderPassExtent(descriptor, facts).width == 32;
	descriptor.depthStencilAttachment.view = { id: 2 };
	facts.depth = { ...colorTarget(64, 32, 1), depth: true };
	assert renderPassRefusal(descriptor, facts) == "render pass attachments differ in size";
	facts.depth = colorTarget(32, 16, 1);
	assert renderPassRefusal(descriptor, facts) == "depthStencilAttachment.view is not a depth RENDER_ATTACHMENT";
	facts.depth = { ...colorTarget(32, 16, 1), depth: true, single: false };
	assert renderPassRefusal(descriptor, facts) == "depthStencilAttachment.view spans several mips or layers: a render attachment is one mip of one layer";
	assert renderPassRefusal({ label: null }, facts) == "beginRenderPass without an attachment";
}

test "a render pass color attachment names a depth slice only on a 3d view, inside its mip" {
	let descriptor = colorPass();
	let facts = onePass(colorTarget(16, 16, 1));
	descriptor.colorAttachments[0].depthSlice = 2;
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].depthSlice 2 needs a 3d view";
	facts.colors[0] = { ...colorTarget(16, 16, 1), volume: true, layers: 8, baseMip: 2 };
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].depthSlice 2 is outside the 2 slices of mip 2 of GPUTexture 5";
	descriptor.colorAttachments[0].depthSlice = 1;
	assert renderPassRefusal(descriptor, facts) == "";
}

test "a resolve target is a single-sample color attachment of its multisampled view's size" {
	let descriptor = colorPass();
	descriptor.colorAttachments[0].resolveTarget = { id: 3 };
	let facts = onePass(colorTarget(16, 16, 4));
	facts.resolves[0] = colorTarget(16, 16, 1);
	assert renderPassRefusal(descriptor, facts) == "";
	facts.resolves[0].single = false;
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].resolveTarget spans several mips or layers: a render attachment is one mip of one layer";
	facts.resolves[0] = colorTarget(8, 16, 1);
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].resolveTarget differs in size from its multisampled view";
	facts.resolves[0] = colorTarget(16, 16, 4);
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].resolveTarget needs a single-sample color RENDER_ATTACHMENT";
	facts.colors[0].sampleCount = 1;
	assert renderPassRefusal(descriptor, facts) == "colorAttachments[0].resolveTarget needs a multisampled view";
}

test "a canvas names a color format and, when it has one, a depth format" {
	assert canvasRefusal("bgra8unorm", "depth32float", 4) == "";
	assert canvasRefusal("rgba8unorm", "", 0) == "";
	assert canvasRefusal("", "", 1) == "NativeEnvironment.colorFormat is required";
	assert canvasRefusal("depth32float", "", 1) == "NativeEnvironment.colorFormat 'depth32float' is not supported";
	assert canvasRefusal("bgra8unorm", "rgba8unorm", 1) == "NativeEnvironment.depthFormat 'rgba8unorm' is not supported";
	assert canvasRefusal("bgra8unorm", "", -1) == "NativeEnvironment.sampleCount -1 is negative";
}

test "a render pipeline's zero sample count and stencil masks resolve to WebGPU's defaults" {
	let descriptor: GPURenderPipelineDescriptor = {};
	const resolved = resolvedRenderPipeline(descriptor);
	assert resolved.multisample.count == 1;
	assert resolved.depthStencil.stencilReadMask == 0xFFFFFFFF;
	assert resolved.depthStencil.stencilWriteMask == 0xFFFFFFFF;
	descriptor.multisample.count = 4;
	descriptor.depthStencil.stencilReadMask = 0x0F;
	descriptor.depthStencil.stencilWriteMask = 0xF0;
	const kept = resolvedRenderPipeline(descriptor);
	assert kept.multisample.count == 4;
	assert kept.depthStencil.stencilReadMask == 0x0F;
	assert kept.depthStencil.stencilWriteMask == 0xF0;
	assert stencil8Mask(resolved.depthStencil.stencilReadMask) == 0xFF;
	assert stencil8Mask(kept.depthStencil.stencilWriteMask) == 0xF0;
}
