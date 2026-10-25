import {
	BindingKind,
	GPUBindGroupEntry,
	GPUBufferUsage,
	GPUSupportedLimits,
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
} from "./types.ms";

// The checks every backend repeats, once, above the backends: device.ms calls them before it
// calls backend.X, so a fifth backend gets them without copying. They stay on in release.
// A refusal function is pure and returns "" or the message; the checked* wrappers stop with it.

export const PASS_NONE: int32 = 0;
export const PASS_RENDER: int32 = 1;
export const PASS_COMPUTE: int32 = 2;

// One open command encoder: Void's backends record on one native encoder, so a second one is refused.
export struct EncoderState {
	open: boolean;
	pass: int32;
	depth: int32;
	base: int32;
}

@noinline function stop(message: string): never {
	console.log(`webgpu: ${message}`);
	unreachable;
}

function passName(kind: int32): string { return kind == PASS_RENDER ? "render" : "compute"; }

export function createRefusal(this ref s: EncoderState): string {
	if (s.open) { return "createCommandEncoder with the frame's encoder not yet finished"; }
	s = { open: true };
	return "";
}

export function finishRefusal(this ref s: EncoderState): string {
	if (s.pass != PASS_NONE) { return `finish with a ${passName(s.pass)} pass still open`; }
	if (s.depth != 0) { return `finish with ${s.depth} debug groups still open`; }
	if (!s.open) { return "finish without createCommandEncoder"; }
	s = { open: false };
	return "";
}

export function beginPassRefusal(this ref s: EncoderState, kind: int32): string {
	const call = kind == PASS_RENDER ? "beginRenderPass" : "beginComputePass";
	if (s.pass != PASS_NONE) { return `${call} with a pass already open`; }
	if (!s.open) { return `${call} without createCommandEncoder`; }
	s.pass = kind;
	s.base = s.depth;
	return "";
}

export function endPassRefusal(this ref s: EncoderState, kind: int32): string {
	if (s.pass != kind) { return `end without an open ${passName(kind)} pass`; }
	if (s.depth != s.base) { return `end with ${s.depth - s.base} debug groups still open`; }
	s.pass = PASS_NONE;
	s.base = 0;
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

export function shutdownRefusal(this s: EncoderState): string {
	return s.pass == PASS_NONE ? "" : `shutdown with a ${passName(s.pass)} pass still open`;
}

let encoder: EncoderState = { open: false };

@inline function refuse(message: string): void {
	if (message != "") { stop(message); }
}

@inline export function renderPassOpen(): boolean { return encoder.pass == PASS_RENDER; }
@inline export function computePassOpen(): boolean { return encoder.pass == PASS_COMPUTE; }
@inline export function openDebugGroups(): int32 { return encoder.depth; }

export function resetEncoder(): void { encoder = { open: false }; }
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

export function checkedBindingGroup(binding: int32, kind: BindingKind, group: int32): void {
	const expected = groupOfKind(kind);
	if (group != expected) {
		stop(`shader binding ${binding} (${kind.toString()}) belongs in group ${expected}, not ${group}`);
	}
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
