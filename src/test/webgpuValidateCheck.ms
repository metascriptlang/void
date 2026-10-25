import {
	BindingKind,
	GPUBindGroupEntry,
	GPUBufferUsage,
	GPUPrimitiveState,
	GPUShaderModuleDescriptor,
	GPUSupportedLimits,
	GPUTextureDescriptor,
	GPUTextureUsage,
} from "../webgpu/types";
import {
	EncoderState,
	PASS_COMPUTE,
	PASS_RENDER,
	addressesBinding,
	attachOcclusion,
	beginOcclusionRefusal,
	beginPassRefusal,
	bufferRefusal,
	computeModuleRefusal,
	computePipelineRefusal,
	createRefusal,
	drawRefusal,
	endOcclusionRefusal,
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
	outsidePassRefusal,
	popGroupRefusal,
	primitiveRefusal,
	pushGroupRefusal,
	renderModuleRefusal,
	shaderModuleRefusal,
	shutdownRefusal,
	stripDrawRefusal,
	textureRefusal,
	uniformEntryRefusal,
} from "../webgpu/validate";

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
const ATTACHMENT = GPUTextureUsage.RENDER_ATTACHMENT as int32;
const SAMPLED = GPUTextureUsage.TEXTURE_BINDING as int32;

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
	for (let i = 0; i < 8; i++) { blocks.bindings[i] = { binding: i, kind: "uniform", size: 16 }; }
	assert shaderModuleRefusal(blocks, limits) == "";
	blocks.bindings[8] = { binding: 8, kind: "uniform", size: 16 };
	assert shaderModuleRefusal(blocks, limits) == "a shader module has over 8 uniform blocks";
	let resources: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	for (let i = 0; i < 16; i++) { resources.bindings[i] = { binding: i, kind: "texture" }; }
	assert shaderModuleRefusal(resources, limits) == "";
	resources.bindings[16] = { binding: 16, kind: "sampler" };
	assert shaderModuleRefusal(resources, limits) == "a shader module has over 16 resources";
	let sized: GPUShaderModuleDescriptor = { vertexCode: "vs", fragmentCode: "fs" };
	sized.bindings[0] = { binding: 3, kind: "uniform", size: 0 };
	assert shaderModuleRefusal(sized, limits) == "uniform binding 3 needs its block size";
	sized.bindings[0].size = 65536;
	assert shaderModuleRefusal(sized, limits) == "";
	sized.bindings[0].size = 65552;
	assert shaderModuleRefusal(sized, limits) == "uniform binding 3 of 65552 bytes is over the limit of 65536";
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
