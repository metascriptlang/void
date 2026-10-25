import {
	BindingKind,
	GPUBindGroupEntry,
	GPUBufferUsage,
	GPUPrimitiveState,
	GPUQuerySetDescriptor,
	GPURenderPipelineDescriptor,
	GPUSamplerDescriptor,
	GPUShaderBinding,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUSupportedLimits,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	samplerMaxLod,
	stop,
} from "./types.ms";

// The checks every backend repeats, once, above the backends: device.ms calls them before it
// calls backend.X, so a fifth backend gets them without copying. They stay on in release.
// A refusal function is pure and returns "" or the message; the checked* wrappers stop with it.

export const PASS_NONE: int32 = 0;
export const PASS_RENDER: int32 = 1;
export const PASS_COMPUTE: int32 = 2;

// One open command encoder: Void's backends record on one native encoder, so a second one is refused.
// The pass record rides here too: what a pass has set and its occlusion query, which WebGPU
// resets at every pass. `serial` counts passes for the life of the device so that a query index
// a backend remembers as used names the pass that used it.
export struct EncoderState {
	open: boolean;
	pass: int32;
	depth: int32;
	base: int32;
	serial: int64;
	pipelineSet: boolean;
	indexSet: boolean;
	occlusionSet: uint32;
	occlusionOpen: boolean;
	occlusionIndex: int32;
}

function passName(kind: int32): string { return kind == PASS_RENDER ? "render" : "compute"; }

export function createRefusal(this ref s: EncoderState): string {
	if (s.open) { return "createCommandEncoder with the frame's encoder not yet finished"; }
	s = { open: true, serial: s.serial };
	return "";
}

export function finishRefusal(this ref s: EncoderState): string {
	if (s.pass != PASS_NONE) { return `finish with a ${passName(s.pass)} pass still open`; }
	if (s.depth != 0) { return `finish with ${s.depth} debug groups still open`; }
	if (!s.open) { return "finish without createCommandEncoder"; }
	s = { open: false, serial: s.serial };
	return "";
}

export function beginPassRefusal(this ref s: EncoderState, kind: int32): string {
	const call = kind == PASS_RENDER ? "beginRenderPass" : "beginComputePass";
	if (s.pass != PASS_NONE) { return `${call} with a pass already open`; }
	if (!s.open) { return `${call} without createCommandEncoder`; }
	s.pass = kind;
	s.base = s.depth;
	s.serial += 1;
	s.pipelineSet = false;
	s.indexSet = false;
	s.occlusionSet = 0;
	s.occlusionOpen = false;
	return "";
}

export function endPassRefusal(this ref s: EncoderState, kind: int32): string {
	if (s.pass != kind) { return `end without an open ${passName(kind)} pass`; }
	if (s.depth != s.base) { return `end with ${s.depth - s.base} debug groups still open`; }
	if (s.occlusionOpen) { return "end with an occlusion query still open"; }
	s.pass = PASS_NONE;
	s.base = 0;
	s.pipelineSet = false;
	s.indexSet = false;
	s.occlusionSet = 0;
	return "";
}

export function inPassRefusal(this s: EncoderState, kind: int32, call: string): string {
	return s.pass == kind ? "" : `${call} outside a ${passName(kind)} pass`;
}

// A copy or a query resolve records on the encoder between passes.
export function outsidePassRefusal(this s: EncoderState, call: string): string {
	if (s.pass != PASS_NONE) { return `${call} inside a pass`; }
	return s.open ? "" : `${call} without createCommandEncoder`;
}

export function pushGroupRefusal(this ref s: EncoderState): string {
	if (!s.open) { return "pushDebugGroup without createCommandEncoder"; }
	s.depth += 1;
	return "";
}

// A pass cannot pop a group it did not push: `base` is the depth the open pass began at.
export function popGroupRefusal(this ref s: EncoderState): string {
	if (!s.open) { return "popDebugGroup without createCommandEncoder"; }
	if (s.depth <= s.base) { return "popDebugGroup without a matching pushDebugGroup"; }
	s.depth -= 1;
	return "";
}

export function markerRefusal(this s: EncoderState): string {
	return s.open ? "" : "insertDebugMarker without createCommandEncoder";
}

export function attachOcclusion(this ref s: EncoderState, set: uint32): void { s.occlusionSet = set; }
export function markPipeline(this ref s: EncoderState): void { s.pipelineSet = true; }
export function markIndexBuffer(this ref s: EncoderState): void { s.indexSet = true; }

// A draw or a dispatch names the call; a pass that never set a pipeline has none, whatever an earlier pass set.
export function pipelineSetRefusal(this s: EncoderState, call: string): string {
	return s.pipelineSet ? "" : `${call} without setPipeline`;
}

export function drawRefusal(this s: EncoderState, call: string, indexed: boolean): string {
	if (!s.pipelineSet) { return `${call} without setPipeline`; }
	if (indexed && !s.indexSet) { return `${call} without setIndexBuffer`; }
	return "";
}

export function beginOcclusionRefusal(this ref s: EncoderState, queryIndex: int32): string {
	if (s.occlusionSet == 0) { return "beginOcclusionQuery needs GPURenderPassDescriptor.occlusionQuerySet"; }
	if (s.occlusionOpen) { return "beginOcclusionQuery with an occlusion query already open"; }
	s.occlusionOpen = true;
	s.occlusionIndex = queryIndex;
	return "";
}

export function endOcclusionRefusal(this ref s: EncoderState): string {
	if (!s.occlusionOpen) { return "endOcclusionQuery without an open occlusion query"; }
	s.occlusionOpen = false;
	return "";
}

export function occlusionRangeRefusal(queryIndex: int32, count: int32): string {
	if (queryIndex < 0 || queryIndex >= count) { return `beginOcclusionQuery index ${queryIndex} is outside the query set of ${count}`; }
	return "";
}

// `lastPass` is the serial of the pass the backend last saw use this index; 0 is never.
export function occlusionReuseRefusal(this s: EncoderState, queryIndex: int32, lastPass: int64): string {
	return lastPass == s.serial ? `beginOcclusionQuery index ${queryIndex} was already used in this pass` : "";
}

export function occlusionSetKindRefusal(isTimestampSet: boolean): string {
	return isTimestampSet ? "GPURenderPassDescriptor.occlusionQuerySet is a timestamp set: an occlusion set is required" : "";
}

export function shutdownRefusal(this s: EncoderState): string {
	return s.pass == PASS_NONE ? "" : `shutdown with a ${passName(s.pass)} pass still open`;
}

let encoder: EncoderState = { open: false };

@inline function refuse(message: string): void {
	if (message != "") { stop(message); }
}

@inline export function occlusionSetId(): uint32 { return encoder.occlusionSet; }
@inline export function occlusionQueryIndex(): int32 { return encoder.occlusionIndex; }
@inline export function passSerial(): int64 { return encoder.serial; }
@inline export function renderPassOpen(): boolean { return encoder.pass == PASS_RENDER; }
@inline export function computePassOpen(): boolean { return encoder.pass == PASS_COMPUTE; }
@inline export function openDebugGroups(): int32 { return encoder.depth; }

export function resetEncoder(): void { encoder = { open: false }; }
export function attachOcclusionSet(set: uint32): void { encoder.attachOcclusion(set); }
export function markPipelineSet(): void { encoder.markPipeline(); }
export function markIndexSet(): void { encoder.markIndexBuffer(); }
export function checkedPipelineSet(call: string): void { refuse(encoder.pipelineSetRefusal(call)); }
export function checkedDrawState(call: string, indexed: boolean): void { refuse(encoder.drawRefusal(call, indexed)); }
export function checkedBeginOcclusion(queryIndex: int32): void { refuse(encoder.beginOcclusionRefusal(queryIndex)); }
export function checkedEndOcclusion(): void { refuse(encoder.endOcclusionRefusal()); }
export function checkedOcclusionRange(queryIndex: int32, count: int32): void { refuse(occlusionRangeRefusal(queryIndex, count)); }
export function checkedOcclusionReuse(queryIndex: int32, lastPass: int64): void { refuse(encoder.occlusionReuseRefusal(queryIndex, lastPass)); }
export function checkedOcclusionSetKind(isTimestampSet: boolean): void { refuse(occlusionSetKindRefusal(isTimestampSet)); }
export function checkedShutdown(): void { refuse(encoder.shutdownRefusal()); }
export function checkedCreateEncoder(): void { refuse(encoder.createRefusal()); }
export function checkedFinish(): void { refuse(encoder.finishRefusal()); }
export function checkedBeginPass(kind: int32): void { refuse(encoder.beginPassRefusal(kind)); }
export function checkedEndPass(kind: int32): void { refuse(encoder.endPassRefusal(kind)); }
export function checkedOutsidePass(call: string): void { refuse(encoder.outsidePassRefusal(call)); }
export function checkedPushGroup(): void { refuse(encoder.pushGroupRefusal()); }
export function checkedPopGroup(): void { refuse(encoder.popGroupRefusal()); }
export function checkedMarker(): void { refuse(encoder.markerRefusal()); }

@inline export function checkedInPass(kind: int32, call: string): void {
	if (encoder.pass != kind) { stop(encoder.inPassRefusal(kind, call)); }
}

// A shader binding lives in the group its kind names, so a bind group entry addresses only the
// bindings of its own group: group 1 binding 0 is not the uniform block at binding 0.
export function groupOfKind(kind: BindingKind): int32 {
	return kind == BindingKind.Uniform ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
}

export function addressesBinding(group: int32, entryBinding: int32, binding: int32, kind: BindingKind): boolean {
	return entryBinding == binding && group == groupOfKind(kind);
}

export function uniformEntryRefusal(
	entry: GPUBindGroupEntry,
	bufferIsUniform: boolean,
	bufferSize: int64,
	blockSize: int32,
	alignment: int64,
): string {
	if (!bufferIsUniform) { return `bind group entry ${entry.binding} needs a UNIFORM buffer`; }
	if (entry.offset < 0 || entry.offset % alignment != 0) {
		return `bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${alignment}`;
	}
	if (entry.offset + (blockSize as int64) > bufferSize) {
		return `bind group entry ${entry.binding} offset ${entry.offset} overruns its buffer`;
	}
	if (entry.size != 0 && entry.size < (blockSize as int64)) {
		return `bind group entry ${entry.binding} size ${entry.size} is below its block of ${blockSize}`;
	}
	return "";
}

export function checkedUniformEntry(entry: GPUBindGroupEntry, bufferIsUniform: boolean, bufferSize: int64, blockSize: int32, alignment: int64): void {
	refuse(uniformEntryRefusal(entry, bufferIsUniform, bufferSize, blockSize, alignment));
}

// WebGPU lets a mappable buffer carry only the one copy usage that matches its map direction.
export function bufferRefusal(size: int64, usage: int32): string {
	const mapRead = GPUBufferUsage.MAP_READ as int32;
	const mapWrite = GPUBufferUsage.MAP_WRITE as int32;
	if (size <= 0) { return "GPUBufferDescriptor.size must be positive"; }
	if ((usage & mapRead) != 0 && usage != (mapRead | (GPUBufferUsage.COPY_DST as int32))) {
		return "GPUBufferUsage MAP_READ combines only with COPY_DST";
	}
	if ((usage & mapWrite) != 0 && usage != (mapWrite | (GPUBufferUsage.COPY_SRC as int32))) {
		return "GPUBufferUsage MAP_WRITE combines only with COPY_SRC";
	}
	return "";
}

export function isDepthFormat(format: GPUTextureFormat): boolean {
	return format == "depth16unorm" || format == "depth32float" || format == "depth24plus-stencil8";
}

// `limits` is the backend's own query. The rules run in the order a descriptor is read: size,
// layers, the mip chain the largest side allows, multisample, then format against dimension.
export function textureRefusal(descriptor: GPUTextureDescriptor, limits: GPUSupportedLimits): string {
	const width = descriptor.size.width;
	const height = descriptor.size.height;
	const dimension: string = descriptor.dimension;
	const volume = dimension == "3d";
	if (width <= 0 || height <= 0) { return "GPUTextureDescriptor.size needs a positive width and height"; }
	if (descriptor.size.depthOrArrayLayers < 0) { return "GPUTextureDescriptor.size.depthOrArrayLayers is negative"; }
	const layers = descriptor.size.depthOrArrayLayers == 0 ? 1 : descriptor.size.depthOrArrayLayers;
	const largestSide = volume ? Math.max(Math.max(width, height), layers) : Math.max(width, height);
	const sideLimit = volume ? limits.maxTextureDimension3D : limits.maxTextureDimension2D;
	if (largestSide > sideLimit || (!volume && layers > limits.maxTextureArrayLayers)) {
		return `GPUTextureDescriptor.size ${width}x${height}x${layers} is over the limits ${sideLimit} per side and ${limits.maxTextureArrayLayers} array layers`;
	}
	const mipLevels = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
	let possible = 1;
	while ((largestSide >> possible) > 0) { possible += 1; }
	if (mipLevels < 1 || mipLevels > possible) {
		return `GPUTextureDescriptor.mipLevelCount ${mipLevels} is outside 1..${possible} for a ${width}x${height} texture`;
	}
	const sampleCount = descriptor.sampleCount == 0 ? 1 : descriptor.sampleCount;
	if (sampleCount > 1 && (volume || layers > 1 || mipLevels > 1)) {
		return "WebGPU allows a multisampled texture only as a 2d texture with one mip level and one array layer";
	}
	if (sampleCount > 1 && (descriptor.usage & (GPUTextureUsage.RENDER_ATTACHMENT as int32)) == 0) {
		return "a multisampled texture must be a RENDER_ATTACHMENT";
	}
	if (volume && isDepthFormat(descriptor.format)) { return "WebGPU allows a depth or stencil format only on a 2d texture"; }
	return "";
}

export function checkedBuffer(size: int64, usage: int32): void { refuse(bufferRefusal(size, usage)); }
export function checkedTexture(descriptor: GPUTextureDescriptor, limits: GPUSupportedLimits): void { refuse(textureRefusal(descriptor, limits)); }

function visibilityRefusal(binding: GPUShaderBinding, compute: boolean): string {
	const render = (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);
	const allowed = compute ? GPUShaderStage.COMPUTE as int32 : render;
	if (binding.visibility == 0 || (binding.visibility & ~allowed) != 0) {
		return `shader binding ${binding.binding} has visibility ${binding.visibility}, but a ${compute ? "compute" : "vertex and fragment"} module allows only ${allowed}`;
	}
	return "";
}

// A uint or sint texture cannot be filtered (WebGPU's bind group layout rule, sokol's
// VALIDATE_SHADERDESC_NONFILTERING_SAMPLER_REQUIRED), so a sampler paired with one must be non-filtering.
function integerTexturePairRefusal(descriptor: GPUShaderModuleDescriptor): string {
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const sampler = descriptor.bindings[i];
		const kind: string = sampler.kind;
		const samplerType: string = sampler.samplerType;
		if (kind != "sampler" || sampler.textureBinding < 0 || samplerType == "non-filtering") { continue; }
		for (let j = 0; j < descriptor.bindings.length; j++) {
			const texture = descriptor.bindings[j];
			const textureKind: string = texture.kind;
			const sampleType: string = texture.sampleType;
			if (textureKind == "texture" && texture.binding == sampler.textureBinding && (sampleType == "uint" || sampleType == "sint")) {
				return `sampler binding ${sampler.binding} is '${samplerType == "" ? "filtering" : samplerType}' but pairs with the ${sampleType} texture binding ${texture.binding}; an integer texture needs a non-filtering sampler`;
			}
		}
	}
	return "";
}

// The descriptor-only rules of a shader module: one kind of code, each binding's stages and group,
// the binding counts a bind group holds, a uniform block's size against the uniform limit, the
// integer textures' samplers, and the workgroup against the compute limits.
export function shaderModuleRefusal(descriptor: GPUShaderModuleDescriptor, limits: GPUSupportedLimits): string {
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	if (compute && (descriptor.vertexCode != "" || descriptor.fragmentCode != "" || descriptor.vertexBytecode.length > 0 || descriptor.fragmentBytecode.length > 0)) {
		return "a GPUShaderModule is either a compute module or a vertex and fragment module";
	}
	let uniforms = 0;
	let resources = 0;
	for (let i = 0; i < descriptor.bindings.length; i++) {
		const kind: string = descriptor.bindings[i].kind;
		if (kind == "") { continue; }
		const visibility = visibilityRefusal(descriptor.bindings[i], compute);
		if (visibility != "") { return visibility; }
		const binding = descriptor.bindings[i].binding;
		const group = descriptor.bindings[i].group;
		const expected = kind == "uniform" ? GPU_UNIFORM_GROUP : GPU_RESOURCE_GROUP;
		if (group != expected) { return `shader binding ${binding} (${kind}) belongs in group ${expected}, not ${group}`; }
		if (kind == "uniform") {
			const size = descriptor.bindings[i].size;
			if (size <= 0) { return `uniform binding ${binding} needs its block size`; }
			if ((size as int64) > limits.maxUniformBufferBindingSize) {
				return `uniform binding ${binding} of ${size} bytes is over the limit of ${limits.maxUniformBufferBindingSize}`;
			}
			uniforms += 1;
			if (uniforms > GPU_MAX_UNIFORM_BLOCKS) { return `a shader module has over ${GPU_MAX_UNIFORM_BLOCKS} uniform blocks`; }
		} else {
			resources += 1;
			if (resources > GPU_MAX_BIND_GROUP_ENTRIES) { return `a shader module has over ${GPU_MAX_BIND_GROUP_ENTRIES} resources`; }
		}
	}
	const pairs = integerTexturePairRefusal(descriptor);
	if (pairs != "") { return pairs; }
	const size: int32[3] = descriptor.workgroupSize;
	if (compute && (size[0] > limits.maxComputeWorkgroupSizeX || size[1] > limits.maxComputeWorkgroupSizeY
		|| size[2] > limits.maxComputeWorkgroupSizeZ || size[0] * size[1] * size[2] > limits.maxComputeInvocationsPerWorkgroup)) {
		return `workgroupSize ${size[0]}x${size[1]}x${size[2]} is over the limits ${limits.maxComputeWorkgroupSizeX}x${limits.maxComputeWorkgroupSizeY}x${limits.maxComputeWorkgroupSizeZ} and ${limits.maxComputeInvocationsPerWorkgroup} invocations`;
	}
	return "";
}

export function isStripTopology(topology: string): boolean {
	return topology == "line-strip" || topology == "triangle-strip";
}

export function primitiveRefusal(primitive: GPUPrimitiveState): string {
	const format: string = primitive.stripIndexFormat;
	if (format != "" && !isStripTopology(primitive.topology)) {
		return `primitive.stripIndexFormat '${format}' needs a strip topology`;
	}
	return "";
}

export function renderPipelineRefusal(descriptor: GPURenderPipelineDescriptor): string {
	if (descriptor.fragment.module.id != descriptor.vertex.module.id) {
		return "vertex and fragment stages come from one GPUShaderModule in Void";
	}
	return primitiveRefusal(descriptor.primitive);
}

// A backend passes whether its module holds compute code: the module record is the backend's own.
export function renderModuleRefusal(moduleIsCompute: boolean): string {
	return moduleIsCompute ? "a compute GPUShaderModule cannot make a GPURenderPipeline" : "";
}

export function computeModuleRefusal(moduleIsCompute: boolean, entry: string, moduleEntry: string): string {
	if (!moduleIsCompute) { return "createComputePipeline needs a GPUShaderModule made with computeCode"; }
	if (entry != moduleEntry) { return `compute.entryPoint '${entry}' differs from the module's computeEntryPoint '${moduleEntry}'`; }
	return "";
}

export function computePipelineRefusal(pipeline: uint32, isCompute: boolean): string {
	return isCompute ? "" : `GPUPipeline ${pipeline} is not a compute pipeline`;
}

export function renderPassPipelineRefusal(pipeline: uint32, isCompute: boolean): string {
	return isCompute ? `GPUPipeline ${pipeline} is a compute pipeline: setPipeline on a render pass takes a render pipeline` : "";
}

// `matches` is whether the pipeline's strip index format is the bound index format; none never matches.
export function stripDrawRefusal(strip: boolean, matches: boolean): string {
	if (strip && !matches) { return "an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format"; }
	return "";
}

export function samplerRefusal(descriptor: GPUSamplerDescriptor): string {
	const mag: string = descriptor.magFilter;
	const min: string = descriptor.minFilter;
	const mip: string = descriptor.mipmapFilter;
	if (descriptor.maxAnisotropy > 1 && (mag != "linear" || min != "linear" || mip != "linear")) {
		return "GPUSamplerDescriptor.maxAnisotropy above 1 needs linear magFilter, minFilter and mipmapFilter";
	}
	if (descriptor.lodMinClamp < 0) { return `GPUSamplerDescriptor.lodMinClamp ${descriptor.lodMinClamp} is negative`; }
	const maxLod = samplerMaxLod(descriptor.lodMaxClamp);
	if (maxLod < descriptor.lodMinClamp) { return `GPUSamplerDescriptor.lodMaxClamp ${maxLod} is below lodMinClamp ${descriptor.lodMinClamp}`; }
	return "";
}

export function querySetRefusal(descriptor: GPUQuerySetDescriptor): string {
	const kind: string = descriptor.type;
	if (kind != "timestamp" && kind != "occlusion") { return `GPUQuerySetDescriptor.type '${kind}' is neither 'timestamp' nor 'occlusion'`; }
	if (descriptor.count < 1 || descriptor.count > 4096) { return `GPUQuerySetDescriptor.count ${descriptor.count} is outside 1..4096`; }
	return "";
}

export function viewportRefusal(width: float32, height: float32, minDepth: float32, maxDepth: float32): string {
	if (width < 0 || height < 0 || minDepth < 0 || maxDepth > 1 || minDepth > maxDepth) {
		return `setViewport ${width}x${height} depth ${minDepth}..${maxDepth} is outside WebGPU's valid range`;
	}
	return "";
}

// `limit` is the backend's maxComputeWorkgroupsPerDimension.
export function dispatchRefusal(x: int32, y: int32, z: int32, limit: int32): string {
	if (x < 0 || y < 0 || z < 0 || x > limit || y > limit || z > limit) { return `dispatchWorkgroups ${x},${y},${z} is outside 0..${limit}`; }
	return "";
}

export function checkedShaderModule(descriptor: GPUShaderModuleDescriptor, limits: GPUSupportedLimits): void { refuse(shaderModuleRefusal(descriptor, limits)); }
export function checkedRenderPipeline(descriptor: GPURenderPipelineDescriptor): void { refuse(renderPipelineRefusal(descriptor)); }
export function checkedRenderModule(moduleIsCompute: boolean): void { refuse(renderModuleRefusal(moduleIsCompute)); }
export function checkedComputeModule(moduleIsCompute: boolean, entry: string, moduleEntry: string): void { refuse(computeModuleRefusal(moduleIsCompute, entry, moduleEntry)); }
export function checkedComputePipeline(pipeline: uint32, isCompute: boolean): void { refuse(computePipelineRefusal(pipeline, isCompute)); }
export function checkedRenderPassPipeline(pipeline: uint32, isCompute: boolean): void { refuse(renderPassPipelineRefusal(pipeline, isCompute)); }
export function checkedStripDraw(strip: boolean, matches: boolean): void { refuse(stripDrawRefusal(strip, matches)); }
export function checkedSampler(descriptor: GPUSamplerDescriptor): void { refuse(samplerRefusal(descriptor)); }
export function checkedQuerySet(descriptor: GPUQuerySetDescriptor): void { refuse(querySetRefusal(descriptor)); }
export function checkedViewport(width: float32, height: float32, minDepth: float32, maxDepth: float32): void { refuse(viewportRefusal(width, height, minDepth, maxDepth)); }
export function checkedDispatch(x: int32, y: int32, z: int32, limit: int32): void { refuse(dispatchRefusal(x, y, z, limit)); }

// A view without a dimension takes its texture's; a 3d view needs a 3d texture and no other does.
export function resolvedViewDimension(dimension: string, volume: boolean, layers: int32): string {
	if (dimension != "") { return dimension; }
	return volume ? "3d" : (layers > 1 ? "2d-array" : "2d");
}

export function viewDimensionRefusal(name: string, volume: boolean, texture: uint32): string {
	if ((name == "3d") != volume) {
		return `GPUTextureViewDescriptor.dimension '${name}' does not match the ${volume ? "3d" : "2d"} GPUTexture ${texture}`;
	}
	return "";
}

export function checkedViewDimension(dimension: string, volume: boolean, layers: int32, texture: uint32): string {
	const name = resolvedViewDimension(dimension, volume, layers);
	refuse(viewDimensionRefusal(name, volume, texture));
	return name;
}

// `index` is already inside the door's two groups. The group a bind group was made for is the
// backend's record, as are its dynamic offset count and the alignment its buffers need.
export function bindGroupSetRefusal(
	index: int32,
	madeFor: int32,
	dynamicCount: int32,
	dynamicOffsets: Readonly<Span<uint32>>,
	alignment: uint32,
): string {
	if (madeFor != index) { return `setBindGroup(${index}) with a bind group made for group ${madeFor}`; }
	if ((dynamicOffsets.length as int32) != dynamicCount) {
		return `setBindGroup(${index}) takes ${dynamicCount} dynamic offsets, got ${dynamicOffsets.length}`;
	}
	for (let i = 0; i < dynamicCount; i++) {
		if (dynamicOffsets[i] % alignment != 0) { return `dynamic offset ${dynamicOffsets[i]} is not a multiple of ${alignment}`; }
	}
	return "";
}

export function bindGroupIndexRefusal(index: int32): string {
	if (index < GPU_UNIFORM_GROUP || index > GPU_RESOURCE_GROUP) {
		return `setBindGroup index ${index} is outside the ${GPU_RESOURCE_GROUP + 1} bind groups`;
	}
	return "";
}

// The bytes a storage binding covers: size 0 means the rest of the buffer past the offset.
export function entryBytes(entry: GPUBindGroupEntry, bufferSize: int64): int64 {
	return entry.size == 0 ? bufferSize - entry.offset : entry.size;
}

// WebGPU (GPUBindGroup creation): a storage binding's effective size is a positive multiple of 4
// inside its buffer, on every backend. `alignment` and `limit` are the backend's own.
export function storageEntryRefusal(entry: GPUBindGroupEntry, bufferIsStorage: boolean, bufferSize: int64, alignment: int64, limit: int64): string {
	if (!bufferIsStorage) { return `bind group entry ${entry.binding} needs a STORAGE buffer`; }
	if (entry.offset < 0 || entry.offset % alignment != 0) {
		return `bind group entry ${entry.binding} offset ${entry.offset} is not a multiple of ${alignment}`;
	}
	const bytes = entryBytes(entry, bufferSize);
	if (bytes <= 0 || bytes % 4 != 0 || entry.offset + bytes > bufferSize) {
		return `bind group entry ${entry.binding} range ${entry.offset}+${bytes} is not a positive multiple of 4 inside its buffer of ${bufferSize}`;
	}
	if (bytes > limit) { return `bind group entry ${entry.binding} range of ${bytes} bytes is over the limit of ${limit}`; }
	return "";
}

export function sampledViewRefusal(binding: int32, textureIsSampled: boolean): string {
	return textureIsSampled ? "" : `bind group entry ${binding}: the view's texture lacks TEXTURE_BINDING`;
}

export function storageViewRefusal(binding: int32, textureIsStorage: boolean, mipCount: int32): string {
	if (!textureIsStorage) { return `bind group entry ${binding}: the view's texture lacks STORAGE_BINDING`; }
	if (mipCount != 1) { return `bind group entry ${binding}: a storage texture view takes exactly one mip`; }
	return "";
}

export function checkedBindGroupIndex(index: int32): void { refuse(bindGroupIndexRefusal(index)); }

export function checkedBindGroupSet(index: int32, madeFor: int32, dynamicCount: int32, dynamicOffsets: Readonly<Span<uint32>>, alignment: uint32): void {
	refuse(bindGroupSetRefusal(index, madeFor, dynamicCount, dynamicOffsets, alignment));
}

export function checkedStorageEntry(entry: GPUBindGroupEntry, bufferIsStorage: boolean, bufferSize: int64, alignment: int64, limit: int64): void {
	refuse(storageEntryRefusal(entry, bufferIsStorage, bufferSize, alignment, limit));
}

export function checkedSampledView(binding: int32, textureIsSampled: boolean): void { refuse(sampledViewRefusal(binding, textureIsSampled)); }
export function checkedStorageView(binding: int32, textureIsStorage: boolean, mipCount: int32): void { refuse(storageViewRefusal(binding, textureIsStorage, mipCount)); }
