// The GPU door on Void's WebGPU-shaped layer (docs/GPU.md): the door's contract, kept so the
// render layers above see no change, with sokol's own mechanisms for what WebGPU leaves to the
// caller (uniform ring, bind group cache).

import {
	GPUBindGroup,
	GPUAddressMode,
	GPUBindGroupDescriptor,
	GPUBlendFactor,
	GPUCanvasConfiguration,
	GPUBlendOperation,
	GPUBuffer,
	GPUBufferUsage,
	GPUCommandEncoder,
	GPUCompareFunction,
	GPUCullMode,
	GPUDevice,
	GPUFilterMode,
	GPUIndexFormat,
	GPULoadOp,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStoreOp,
	GPUTexture,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUVertexBufferLayout,
	GPUVertexFormat,
	GPUVertexStepMode,
	GPU_UNIFORM_GROUP,
	GPU_RESOURCE_GROUP,
} from "../webgpu/types.ms";
import { GPUNativeEnvironment, getCurrentDepthTexture, getCurrentTexture, requestDevice } from "../webgpu/device.ms";
import {
	voidSwapchainDepthStencilView,
	voidSwapchainHeight,
	voidSwapchainRenderView,
	voidSwapchainResolveView,
	voidSwapchainSampleCount,
	voidSwapchainWidth,
} from "../platform/swapchain.h";
import "../sokol/gpu";
import { exit } from "std/process";

export const DOOR_UNIFORM_SLOTS = 8;
export const DOOR_MAX_COLOR_ATTACHMENTS = 4;
const VIEW_SLOTS = 6;
const SAMPLER_SLOTS = 3;
const UNIFORM_RING_BYTES = 4 * 1024 * 1024;
const UNIFORM_ALIGNMENT = 256;
const BIND_GROUP_CACHE = 1024;

export struct DoorLayout { buffers: GPUVertexBufferLayout[2]; }

export struct DoorProgram {
	source: (index: int32) => GPUShaderModuleDescriptor;
	index: int32;
	layout: int32;
	uniformMask: uint32;
	uniformBytes: int32[8];
	textureMask: uint32;
	samplerMask: uint32;
}

struct PipelineRecord {
	pipeline: GPURenderPipeline;
	indexFormat: GPUIndexFormat;
	indexed: boolean;
	uniformMask: uint32;
	textureMask: uint32;
	samplerMask: uint32;
	uniformGroup: GPUBindGroup;
}

struct ShaderRecord { module: GPUShaderModule; program: int32; }

struct BindKey {
	pipeline: uint32;
	views: uint32[6];
	samplers: uint32[3];
}

struct BindEntry { key: BindKey; group: GPUBindGroup; }

struct AppendCursor { buffer: uint32; frame: uint32; position: int64; }

let device: GPUDevice = { id: 0, queue: { id: 0 } };
let layouts: Vec<DoorLayout> = [];
let programs: Vec<DoorProgram> = [];
let shaders: Vec<ShaderRecord> = [];
let pipelines: Vec<PipelineRecord> = [];
let bindCache: Vec<BindEntry> = [];
let appendCursors: Vec<AppendCursor> = [];
let generation: int32 = 1;
let everSetUp = false;
let uniformRing: GPUBuffer = { id: 0 };
let uniformCursor: int64 = 0;
let uniformOffsets: uint32[8] = [0, 0, 0, 0, 0, 0, 0, 0];
let encoder: GPUCommandEncoder = { id: 0 };
let pass: GPURenderPassEncoder = { id: 0 };
let current: int32 = -1;
let openPass: int32 = 0;
let passViews: uint32[5] = [0, 0, 0, 0, 0];

function fail(message: string): never {
	console.error("gpu door: " + message);
	exit(1);
}

// The platform hands its device over once it exists, and again after a device loss; ids made
// before a new setup are stale, which doorContextGeneration tells the layers above. It starts at
// 1 and only a setup after the first moves it, as bridgeWin.c and bridgeWeb.c counted, so 0 stays
// the generation nothing current carries.
@exportName("doorSetup")
export function doorSetup(nativeDevice: Ptr<void>, nativeContext: Ptr<void>, colorFormat: int32, depthFormat: int32, sampleCount: int32): void {
	let environment: GPUNativeEnvironment = { device: nativeDevice, context: nativeContext, colorFormat: textureFormatOf(colorFormat), sampleCount };
	if (depthFormat != FORMAT_NONE) { environment.depthFormat = textureFormatOf(depthFormat); }
	device = requestDevice(environment);
	shaders.length = 0;
	pipelines.length = 0;
	bindCache.length = 0;
	appendCursors.length = 0;
	uniformRing = device.createBuffer({ label: "uniforms", size: UNIFORM_RING_BYTES, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
	uniformCursor = 0;
	encoder = { id: 0 };
	openPass = DOOR_PASS_NONE;
	current = -1;
	if (everSetUp) { generation++; }
	everSetUp = true;
}

@exportName("doorShutdown")
export function doorShutdown(): void {
	if (device.id == 0) { return; }
	device.destroy();
	device = { id: 0, queue: { id: 0 } };
}

// sokol's sg_frame_stats, the members frameClock.c reads: counted through a frame and handed
// over at commit as the previous frame's (sokol_gfx.h _sg_update_stats).
export const DOOR_STAT_DRAWS = 0;
export const DOOR_STAT_PIPELINES = 1;
export const DOOR_STAT_PASSES = 2;
export const DOOR_STAT_BUFFER_BYTES = 3;
export const DOOR_STAT_IMAGE_BYTES = 4;
let frameStats: int32[5] = [0, 0, 0, 0, 0];
let lastFrameStats: int32[5] = [0, 0, 0, 0, 0];

@exportName("doorFrameStat")
export function doorFrameStat(which: int32): int32 {
	if (which < 0 || which > DOOR_STAT_IMAGE_BYTES) { fail("no frame stat " + String(which)); }
	return lastFrameStats[which];
}

@exportName("doorValid")
export function doorValid(): int32 { return device.id != 0 ? 1 : 0; }

@exportName("doorContextGeneration")
export function doorContextGeneration(): int32 { return generation; }

export function doorDevice(): GPUDevice { return device; }

// ---- registries ----

export struct DoorAttribute {
	location: int32;
	format: GPUVertexFormat;
	buffer: int32;
}

function formatBytes(format: GPUVertexFormat): int32 {
	if (format == "float32") { return 4; }
	if (format == "float32x2") { return 8; }
	if (format == "float32x3") { return 12; }
	if (format == "float32x4") { return 16; }
	if (format == "unorm8x4") { return 4; }
	fail("vertex format " + format + " has no size");
}

// Attributes packed in order per buffer and each stride their sum, as sokol fills a layout whose
// offsets are all zero (_sg_pipeline_desc_defaults).
export function doorLayout(attributes: Readonly<Span<DoorAttribute>>, steps: Readonly<Span<GPUVertexStepMode>>): DoorLayout {
	let layout: DoorLayout = {};
	let counts: int32[2] = [0, 0];
	for (let i = 0; i < attributes.length; i++) {
		const a = attributes[i];
		if (a.buffer < 0 || a.buffer > 1) { fail("attribute " + String(a.location) + " names vertex buffer " + String(a.buffer)); }
		layout.buffers[a.buffer].attributes[counts[a.buffer]] = { format: a.format, offset: layout.buffers[a.buffer].arrayStride, shaderLocation: a.location };
		layout.buffers[a.buffer].arrayStride += formatBytes(a.format);
		counts[a.buffer]++;
	}
	for (let b = 0; b < steps.length && b < 2; b++) { layout.buffers[b].stepMode = steps[b]; }
	return layout;
}


export function doorRegisterLayouts(entries: Readonly<Span<DoorLayout>>): int32 {
	const base = layouts.length as int32;
	for (let i = 0; i < entries.length; i++) { layouts.push(entries[i]); }
	return base;
}

// `source(i)` builds the module of program i for i in 0..layoutIds.length.
export function doorRegisterPrograms(source: (index: int32) => GPUShaderModuleDescriptor, layoutIds: Readonly<Span<int32>>): int32 {
	const base = programs.length as int32;
	for (let i = 0; i < layoutIds.length; i++) {
		const reflected = source(i as int32);
		let uniformMask: uint32 = 0;
		let textureMask: uint32 = 0;
		let samplerMask: uint32 = 0;
		let bytes: int32[8] = [0, 0, 0, 0, 0, 0, 0, 0];
		for (let b = 0; b < 24; b++) {
			const binding = reflected.bindings[b];
			if (binding.kind == "uniform") {
				uniformMask |= (1 as uint32) << (binding.binding as uint32);
				bytes[binding.binding] = binding.size;
			} else if (binding.kind == "texture") {
				textureMask |= (1 as uint32) << (binding.binding as uint32);
			} else if (binding.kind == "sampler") {
				samplerMask |= (1 as uint32) << ((binding.binding - 32) as uint32);
			}
		}
		programs.push({ source, index: i as int32, layout: layoutIds[i], uniformMask, uniformBytes: bytes, textureMask, samplerMask });
	}
	return base;
}

function programAt(program: int32): DoorProgram {
	if (program < 0 || program >= (programs.length as int32)) { fail("unregistered program id " + String(program)); }
	return programs[program];
}

function layoutAt(layout: int32): DoorLayout {
	if (layout < 0 || layout >= (layouts.length as int32)) { fail("unregistered layout id " + String(layout)); }
	return layouts[layout];
}

export function doorProgramCount(): int32 { return programs.length as int32; }
export function doorProgramLayout(program: int32): int32 { return programAt(program).layout; }
export function doorUniformSlotMask(program: int32): uint32 { return programAt(program).uniformMask; }
export function doorTextureSlotMask(program: int32): uint32 { return programAt(program).textureMask; }
export function doorSamplerSlotMask(program: int32): uint32 { return programAt(program).samplerMask; }

export function doorUniformBlockBytes(program: int32, slot: int32): int32 {
	if (slot < 0 || slot >= DOOR_UNIFORM_SLOTS) { return 0; }
	return programAt(program).uniformBytes[slot];
}

function formatFloats(format: string): int32 {
	return match (format) {
		"float32x2" => 2,
		"float32x3" => 3,
		"float32x4" => 4,
		_ => -1,
	};
}

export function doorLayoutFloats(layout: int32, buffer: int32): int32 {
	const state = layoutAt(layout).buffers[buffer];
	let floats = 0;
	for (let i = 0; i < 16; i++) {
		const format = state.attributes[i].format;
		if ((format as string) == "") { continue; }
		const size = formatFloats(format);
		if (size < 0) { return -1; }
		floats += size;
	}
	return floats;
}

export function doorLayoutPerInstance(layout: int32): int32 {
	return layoutAt(layout).buffers[0].stepMode == "instance" ? 1 : 0;
}

// ---- resources ----

export function doorMakeShader(program: int32): uint32 {
	const record = programAt(program);
	const module = device.createShaderModule(record.source(record.index));
	if (module.id == 0) { return 0; }
	shaders.push({ module, program });
	return module.id;
}

function shaderProgram(shader: uint32): int32 {
	for (let i = 0; i < shaders.length; i++) {
		if (shaders[i].module.id == shader) { return shaders[i].program; }
	}
	fail("pipeline names shader " + String(shader) + ", which the door did not make");
}

const CULL_MODES: GPUCullMode[3] = ["none", "back", "front"];
const COMPARE_FUNCTIONS: GPUCompareFunction[8] = ["always", "never", "equal", "not-equal", "greater", "greater-equal", "less", "less-equal"];
const BLEND_FACTORS: GPUBlendFactor[10] = ["one", "zero", "src-alpha", "src", "dst-alpha", "dst", "one-minus-src-alpha", "one-minus-src", "one-minus-dst-alpha", "one-minus-dst"];
const ALPHA_BLEND_FACTORS: GPUBlendFactor[10] = ["one", "zero", "src-alpha", "src-alpha", "dst-alpha", "dst-alpha", "one-minus-src-alpha", "one-minus-src-alpha", "one-minus-dst-alpha", "one-minus-dst-alpha"];
const BLEND_OPERATIONS: GPUBlendOperation[5] = ["add", "subtract", "reverse-subtract", "min", "max"];
const LOAD_OPS: GPULoadOp[3] = ["clear", "load", "clear"];
const STORE_OPS: GPUStoreOp[2] = ["store", "discard"];

const FORMAT_NONE = 0;
const FORMAT_DEFAULT = 1;
const FORMAT_DEPTH = 3;
const FORMAT_DEPTH_STENCIL = 5;

function isDepthFormat(format: int32): boolean { return format == FORMAT_DEPTH || format == FORMAT_DEPTH_STENCIL; }

const FORMAT_R8 = 7;

function textureFormatOf(format: int32): GPUTextureFormat {
	if (format == 2) { return "rgba8unorm"; }
	if (format == FORMAT_DEPTH) { return "depth32float"; }
	if (format == 4) { return "bgra8unorm"; }
	if (format == FORMAT_DEPTH_STENCIL) { return "depth24plus-stencil8"; }
	if (format == 6) { return "rgba16float"; }
	if (format == FORMAT_R8) { return "r8unorm"; }
	fail("PixelFormat " + String(format) + " names no texture format");
}

function textureFormat(format: int32, role: string): GPUTextureFormat {
	if (format == FORMAT_DEFAULT) {
		return role == "depth" ? device.getCanvasConfiguration().depthFormat : device.getCanvasConfiguration().format;
	}
	return textureFormatOf(format);
}

function pick<T>(table: Readonly<Span<T>>, index: uint32): T {
	return index < (table.length as uint32) ? table[index as int32] : table[0];
}

// Words of door.h's pipeline descriptor.
const PIPELINE_SHADER = 0;
const PIPELINE_LAYOUT = 1;
const PIPELINE_CULLING = 2;
const PIPELINE_DEPTH_TEST = 3;
const PIPELINE_DEPTH_WRITE = 4;
const PIPELINE_BLEND_SOURCE = 5;
const PIPELINE_BLEND_DESTINATION = 6;
const PIPELINE_BLEND_ALPHA_SOURCE = 7;
const PIPELINE_BLEND_ALPHA_DESTINATION = 8;
const PIPELINE_BLEND_OPERATION = 9;
const PIPELINE_BLEND_ALPHA_OPERATION = 10;
const PIPELINE_COLOR_MASK = 11;
const PIPELINE_COLOR_FORMAT = 12;
const PIPELINE_DEPTH_FORMAT = 16;
const PIPELINE_SAMPLE_COUNT = 17;
const PIPELINE_INDEX_TYPE = 18;
const PIPELINE_LENGTH = 19;

export function doorMakePipeline(d: Readonly<Span<uint32>>): uint32 {
	if (d.length < PIPELINE_LENGTH) { fail("makePipeline descriptor holds " + String(d.length) + " of 19 words"); }
	const program = shaderProgram(d[PIPELINE_SHADER]);
	const reflected = programAt(program);
	const layout = layoutAt(d[PIPELINE_LAYOUT] as int32);
	const srcColor = pick(BLEND_FACTORS, d[PIPELINE_BLEND_SOURCE]);
	const dstColor = pick(BLEND_FACTORS, d[PIPELINE_BLEND_DESTINATION]);
	const srcAlpha = pick(ALPHA_BLEND_FACTORS, d[PIPELINE_BLEND_ALPHA_SOURCE]);
	const dstAlpha = pick(ALPHA_BLEND_FACTORS, d[PIPELINE_BLEND_ALPHA_DESTINATION]);
	const opColor = pick(BLEND_OPERATIONS, d[PIPELINE_BLEND_OPERATION]);
	const opAlpha = pick(BLEND_OPERATIONS, d[PIPELINE_BLEND_ALPHA_OPERATION]);
	const blendEnabled = !(srcColor == "one" && dstColor == "zero" && srcAlpha == "one" && dstAlpha == "zero" && opColor == "add" && opAlpha == "add");
	const writeMask = (d[PIPELINE_COLOR_MASK] & 15) as int32;
	const depthFormat = d[PIPELINE_DEPTH_FORMAT] as int32;
	const indexType = d[PIPELINE_INDEX_TYPE];
	const module: GPUShaderModule = { id: d[PIPELINE_SHADER] };
	let descriptor = {
		label: null,
		vertex: { module, buffers: layout.buffers },
		primitive: { topology: "triangle-list", frontFace: "ccw", cullMode: pick(CULL_MODES, d[PIPELINE_CULLING]) },
		multisample: { count: d[PIPELINE_SAMPLE_COUNT] as int32 },
		fragment: { module },
	} as GPURenderPipelineDescriptor;
	if (depthFormat != FORMAT_NONE) {
		descriptor.depthStencil = {
			format: textureFormat(depthFormat, "depth"),
			depthWriteEnabled: d[PIPELINE_DEPTH_WRITE] != 0,
			depthCompare: pick(COMPARE_FUNCTIONS, d[PIPELINE_DEPTH_TEST]),
		};
	}
	for (let i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
		const format = d[PIPELINE_COLOR_FORMAT + i] as int32;
		if (format == FORMAT_NONE) { break; }
		descriptor.fragment.targets[i] = {
			format: textureFormat(format, "color"),
			blendEnabled,
			blend: { color: { operation: opColor, srcFactor: srcColor, dstFactor: dstColor }, alpha: { operation: opAlpha, srcFactor: srcAlpha, dstFactor: dstAlpha } },
			writeMask,
		};
	}
	const pipeline = device.createRenderPipeline(descriptor);
	if (pipeline.id == 0) { return 0; }
	let uniformGroup: GPUBindGroup = { id: 0 };
	if (reflected.uniformMask != 0) {
		let entries = { label: null, layout: pipeline.getBindGroupLayout(GPU_UNIFORM_GROUP) } as GPUBindGroupDescriptor;
		let n = 0;
		for (let slot = 0; slot < DOOR_UNIFORM_SLOTS; slot++) {
			if ((reflected.uniformMask & ((1 as uint32) << (slot as uint32))) == 0) { continue; }
			entries.entries[n] = { binding: slot, buffer: uniformRing, size: reflected.uniformBytes[slot] as int64 };
			n++;
		}
		uniformGroup = device.createBindGroup(entries);
	}
	pipelines.push({
		pipeline,
		indexFormat: indexType == 2 ? "uint32" : "uint16",
		indexed: indexType != 0,
		uniformMask: reflected.uniformMask,
		textureMask: reflected.textureMask,
		samplerMask: reflected.samplerMask,
		uniformGroup,
	});
	return pipeline.id;
}

function pipelineIndex(pipeline: uint32): int32 {
	for (let i = 0; i < pipelines.length; i++) {
		if (pipelines[i].pipeline.id == pipeline) { return i as int32; }
	}
	fail("apply of pipeline " + String(pipeline) + ", which the door did not make");
}

export function doorMakeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32 {
	if (width <= 0 || height <= 0 || rgba.length != (width as int64) * (height as int64)) { return 0; }
	const texture = device.createTexture({
		label: null,
		size: { width, height, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
		sampleCount: 1,
	});
	if (texture.id == 0) { return 0; }
	device.queue.writeTexture({ texture }, rgba, { offset: 0, bytesPerRow: width * 4, rowsPerImage: height }, { width, height, depthOrArrayLayers: 1 });
	return texture.id;
}

export function doorMakeTargetImage(width: int32, height: int32, format: int32): uint32 {
	if (width <= 0 || height <= 0) { return 0; }
	return device.createTexture({
		label: null,
		size: { width, height, depthOrArrayLayers: 1 },
		format: textureFormat(format, isDepthFormat(format) ? "depth" : "color"),
		usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
		sampleCount: 1,
	}).id;
}

export function doorMakeAttachmentView(image: uint32, format: int32): uint32 {
	const texture: GPUTexture = { id: image };
	return texture.createView({ label: null }).id;
}

@exportName("doorMakeTextureView")
export function doorMakeTextureView(image: uint32): uint32 {
	const texture: GPUTexture = { id: image };
	return texture.createView({ label: null }).id;
}

const FILTERS: GPUFilterMode[2] = ["nearest", "linear"];
const WRAPS: GPUAddressMode[3] = ["clamp-to-edge", "repeat", "mirror-repeat"];

@exportName("doorMakeSampler")
export function doorMakeSampler(filter: int32, wrap: int32): uint32 {
	const f = pick(FILTERS, filter as uint32);
	const w = pick(WRAPS, wrap as uint32);
	return device.createSampler({ label: null, addressModeU: w, addressModeV: w, magFilter: f, minFilter: f }).id;
}

@exportName("doorImageAlive")
export function doorImageAlive(image: uint32): int32 { const t: GPUTexture = { id: image }; return t.isAlive() ? 1 : 0; }
@exportName("doorViewAlive")
export function doorViewAlive(view: uint32): int32 { const v: GPUTextureView = { id: view }; return v.isAlive() ? 1 : 0; }
export function doorSamplerAlive(sampler: uint32): int32 { const s: GPUSampler = { id: sampler }; return s.isAlive() ? 1 : 0; }

export function doorDestroyShader(shader: uint32): void {
	for (let i = 0; i < shaders.length; i++) {
		if (shaders[i].module.id == shader) { shaders[i].module.destroy(); shaders.splice(i, 1); return; }
	}
}

export function doorDestroyPipeline(pipeline: uint32): void {
	for (let i = 0; i < pipelines.length; i++) {
		if (pipelines[i].pipeline.id != pipeline) { continue; }
		if (pipelines[i].uniformGroup.id != 0) { pipelines[i].uniformGroup.destroy(); }
		pipelines[i].pipeline.destroy();
		pipelines.splice(i, 1);
		current = -1;
		return;
	}
}

@exportName("doorDestroyImage")
export function doorDestroyImage(image: uint32): void { const t: GPUTexture = { id: image }; t.destroy(); }
@exportName("doorDestroyView")
export function doorDestroyView(view: uint32): void { const v: GPUTextureView = { id: view }; v.destroy(); }
@exportName("doorDestroySampler")
export function doorDestroySampler(sampler: uint32): void { const s: GPUSampler = { id: sampler }; s.destroy(); }

// ---- buffers and textures for the C layers ----

export const DOOR_BUFFER_VERTEX = 1;
export const DOOR_BUFFER_INDEX = 2;
export const DOOR_BUFFER_STREAM = 4;

// `data` empty makes a buffer of `size` bytes to fill later; otherwise the buffer is `data`.
@exportName("doorMakeBuffer")
export function doorMakeBuffer(usage: int32, data: Readonly<Span<uint8>>, size: int64): uint32 {
	const bytes = data.length > 0 ? data.length as int64 : size;
	if (bytes <= 0) { return 0; }
	const buffer = device.createBuffer({ label: null, size: (bytes + 3) & ~(3 as int64), usage: doorBufferUsage(usage) });
	if (buffer.id != 0 && data.length > 0) { device.queue.writeBuffer(buffer, 0, data); }
	return buffer.id;
}

export function doorMakeBufferOf<T>(usage: int32, data: Readonly<Span<T>>): uint32 {
	if (data.length == 0) { return 0; }
	const buffer = device.createBuffer({ label: null, size: ((data.length as int64) * (sizeof(T) as int64) + 3) & ~(3 as int64), usage: doorBufferUsage(usage) });
	if (buffer.id != 0) { device.queue.writeBuffer(buffer, 0, data); }
	return buffer.id;
}

function doorBufferUsage(usage: int32): int32 {
	let flags = GPUBufferUsage.COPY_DST as int32;
	if ((usage & DOOR_BUFFER_VERTEX) != 0) { flags |= GPUBufferUsage.VERTEX as int32; }
	if ((usage & DOOR_BUFFER_INDEX) != 0) { flags |= GPUBufferUsage.INDEX as int32; }
	return flags;
}

// sokol's sg_update_buffer: the whole content from offset 0, refused past the buffer's size.
export function doorUpdateBufferOf<T>(id: uint32, data: Readonly<Span<T>>): int32 {
	const buffer: GPUBuffer = { id };
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (bytes <= 0 || !buffer.isAlive() || bytes > buffer.size()) { return 0; }
	device.queue.writeBuffer(buffer, 0, data);
	frameStats[DOOR_STAT_BUFFER_BYTES] += bytes as int32;
	return 1;
}

@exportName("doorUpdateBuffer")
export function doorUpdateBuffer(id: uint32, data: Readonly<Span<uint8>>): int32 { return doorUpdateBufferOf(id, data); }

// sokol's sg_append_buffer: each append lands after the last one this frame, 4-byte aligned,
// and returns its offset; the first append of a frame starts at 0. -1 when it does not fit.
@exportName("doorAppendBuffer")
export function doorAppendBuffer(id: uint32, data: Readonly<Span<uint8>>): int64 {
	const buffer: GPUBuffer = { id };
	const frame = device.frameIndex();
	let at = -1;
	for (let i = 0; i < appendCursors.length; i++) { if (appendCursors[i].buffer == id) { at = i; break; } }
	if (at < 0) { appendCursors.push({ buffer: id, frame, position: 0 }); at = (appendCursors.length - 1) as int32; }
	if (appendCursors[at].frame != frame) { appendCursors[at] = { buffer: id, frame, position: 0 }; }
	const offset = appendCursors[at].position;
	const bytes = data.length as int64;
	if (offset + bytes > buffer.size()) { return -1; }
	if (bytes > 0) { device.queue.writeBuffer(buffer, offset, data); }
	frameStats[DOOR_STAT_BUFFER_BYTES] += bytes as int32;
	appendCursors[at].position = (offset + bytes + 3) & ~(3 as int64);
	return offset;
}

@exportName("doorDestroyBuffer")
export function doorDestroyBuffer(id: uint32): void {
	const buffer: GPUBuffer = { id };
	buffer.destroy();
	for (let i = 0; i < appendCursors.length; i++) { if (appendCursors[i].buffer == id) { appendCursors.splice(i, 1); return; } }
}

@exportName("doorBufferAlive")
export function doorBufferAlive(id: uint32): int32 { const b: GPUBuffer = { id }; return b.isAlive() ? 1 : 0; }

export function doorBufferSize(id: uint32): int64 { const b: GPUBuffer = { id }; return b.size(); }

// A sampled texture of PixelFormat `format`; `data` empty leaves it to doorUpdateTexture.
@exportName("doorMakeTexture")
export function doorMakeTexture(width: int32, height: int32, format: int32, data: Readonly<Span<uint8>>): uint32 {
	if (width <= 0 || height <= 0) { return 0; }
	const texture = device.createTexture({
		label: null,
		size: { width, height, depthOrArrayLayers: 1 },
		format: textureFormatOf(format),
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
		sampleCount: 1,
	});
	if (texture.id != 0 && data.length > 0) { doorUpdateTexture(texture.id, data); }
	return texture.id;
}

// sokol's sg_update_image: the whole texture, `data` exactly its rows.
@exportName("doorUpdateTexture")
export function doorUpdateTexture(id: uint32, data: Readonly<Span<uint8>>): void { doorUpdateTextureOf(id, data); }

export function doorUpdateTextureOf<T>(id: uint32, data: Readonly<Span<T>>): void {
	const texture: GPUTexture = { id };
	if (!texture.isAlive()) { return; }
	const width = texture.width();
	const height = texture.height();
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (bytes % (height as int64) != 0) { fail("updateTexture of " + String(bytes) + " bytes is not whole rows of a texture " + String(height) + " high"); }
	const rowBytes = bytes / (height as int64);
	frameStats[DOOR_STAT_IMAGE_BYTES] += bytes as int32;
	device.queue.writeTexture({ texture }, data, { offset: 0, bytesPerRow: rowBytes as int32, rowsPerImage: height }, { width, height, depthOrArrayLayers: 1 });
}

// A partial sampled-texture write: `data` starts at the rectangle's first texel and holds rows
// `bytesPerRow` apart, the last one only as far as the rectangle's width.
@exportName("doorUpdateTextureRect")
export function doorUpdateTextureRect(id: uint32, x: int32, y: int32, width: int32, height: int32, bytesPerRow: int32, data: Readonly<Span<uint8>>): void {
	const texture: GPUTexture = { id };
	if (!texture.isAlive()) { return; }
	frameStats[DOOR_STAT_IMAGE_BYTES] += (data.length as int32);
	device.queue.writeTexture({ texture, origin: { x, y, z: 0 } }, data, { offset: 0, bytesPerRow, rowsPerImage: height }, { width, height, depthOrArrayLayers: 1 });
}

export function doorTextureWidth(id: uint32): int32 { const t: GPUTexture = { id }; return t.width(); }
export function doorTextureHeight(id: uint32): int32 { const t: GPUTexture = { id }; return t.height(); }

@exportName("doorViewImage")
export function doorViewImage(view: uint32): uint32 {
	const v: GPUTextureView = { id: view };
	return v.isAlive() ? v.texture().id : 0;
}

// sokol's sg_query_image_usage(sg_query_view_image(view)).color_attachment.
@exportName("doorViewIsColorAttachment")
export function doorViewIsColorAttachment(view: uint32): int32 {
	const image = doorViewImage(view);
	if (image == 0) { return 0; }
	const texture: GPUTexture = { id: image };
	const format = texture.format();
	const depth = format == "depth32float" || format == "depth24plus-stencil8";
	return !depth && (texture.usage() & (GPUTextureUsage.RENDER_ATTACHMENT as int32)) != 0 ? 1 : 0;
}

// ---- draw ----

@exportName("doorApplyPipeline")
export function doorApplyPipeline(pipeline: uint32): void {
	frameStats[DOOR_STAT_PIPELINES]++;
	const index = pipelineIndex(pipeline);
	if (index != current) {
		current = index;
		pass.setPipeline(pipelines[current].pipeline);
	}
	uniformOffsets = [0, 0, 0, 0, 0, 0, 0, 0];
}

function sameKey(a: BindKey, b: BindKey): boolean {
	if (a.pipeline != b.pipeline) { return false; }
	for (let i = 0; i < VIEW_SLOTS; i++) { if (a.views[i] != b.views[i]) { return false; } }
	for (let i = 0; i < SAMPLER_SLOTS; i++) { if (a.samplers[i] != b.samplers[i]) { return false; } }
	return true;
}

function keyHash(key: BindKey): int32 {
	let h: uint32 = key.pipeline * 2654435761;
	for (let i = 0; i < VIEW_SLOTS; i++) { h = (h ^ key.views[i]) * 16777619; }
	for (let i = 0; i < SAMPLER_SLOTS; i++) { h = (h ^ key.samplers[i]) * 16777619; }
	return (h & ((BIND_GROUP_CACHE - 1) as uint32)) as int32;
}

function resourceGroup(key: BindKey): GPUBindGroup {
	if (bindCache.length == 0) {
		for (let i = 0; i < BIND_GROUP_CACHE; i++) { bindCache.push({ key: { pipeline: 0 }, group: { id: 0 } }); }
	}
	const at = keyHash(key);
	if (bindCache[at].group.id != 0 && sameKey(bindCache[at].key, key)) { return bindCache[at].group; }
	if (bindCache[at].group.id != 0) { bindCache[at].group.destroy(); }
	const record = pipelines[current];
	let descriptor = { label: null, layout: record.pipeline.getBindGroupLayout(GPU_RESOURCE_GROUP) } as GPUBindGroupDescriptor;
	let n = 0;
	for (let i = 0; i < VIEW_SLOTS; i++) {
		if ((record.textureMask & ((1 as uint32) << (i as uint32))) == 0) { continue; }
		descriptor.entries[n] = { binding: i, textureView: { id: key.views[i] } };
		n++;
	}
	for (let i = 0; i < SAMPLER_SLOTS; i++) {
		if ((record.samplerMask & ((1 as uint32) << (i as uint32))) == 0) { continue; }
		descriptor.entries[n] = { binding: 32 + i, sampler: { id: key.samplers[i] } };
		n++;
	}
	const group = device.createBindGroup(descriptor);
	bindCache[at] = { key, group };
	return group;
}

// Words of draw.h's bindings: vertex buffers 0..1, index buffer 2, views 3..8, samplers 9..11;
// `vertexOffsets` are sokol's vertex_buffer_offsets, in bytes.
@exportName("doorApplyBindings")
export function doorApplyBindings(bindings: Readonly<Span<uint32>>, vertexOffsets: Readonly<Span<int32>>): void {
	if (bindings.length < 12) { fail("applyBindings descriptor holds " + String(bindings.length) + " of 12 words"); }
	if (current < 0) { fail("applyBindings before applyPipeline"); }
	for (let i = 0; i < 2; i++) {
		if (bindings[i] != 0) { pass.setVertexBuffer(i as int32, { id: bindings[i] }, i < vertexOffsets.length ? vertexOffsets[i] as int64 : 0); }
	}
	const record = pipelines[current];
	if (record.indexed) { pass.setIndexBuffer({ id: bindings[2] }, record.indexFormat, 0); }
	if (record.textureMask == 0 && record.samplerMask == 0) { return; }
	let key: BindKey = { pipeline: record.pipeline.id };
	for (let i = 0; i < VIEW_SLOTS; i++) { key.views[i] = bindings[3 + i]; }
	for (let i = 0; i < SAMPLER_SLOTS; i++) { key.samplers[i] = bindings[9 + i]; }
	pass.setBindGroup(GPU_RESOURCE_GROUP, resourceGroup(key), []);
}

@exportName("doorApplyUniforms")
export function doorApplyUniforms(slot: int32, data: Readonly<Span<uint8>>): void { doorApplyUniformsOf(slot, data); }

export function doorApplyUniformsOf<T>(slot: int32, data: Readonly<Span<T>>): void {
	if (current < 0) { fail("applyUniforms before applyPipeline"); }
	if (slot < 0 || slot >= DOOR_UNIFORM_SLOTS) { fail("applyUniforms to slot " + String(slot)); }
	const record = pipelines[current];
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (uniformCursor + bytes > UNIFORM_RING_BYTES) { fail("uniform ring of 4 MiB is full this frame"); }
	device.queue.writeBuffer(uniformRing, uniformCursor, data);
	uniformOffsets[slot] = uniformCursor as uint32;
	uniformCursor = (uniformCursor + bytes + (UNIFORM_ALIGNMENT - 1)) & ~((UNIFORM_ALIGNMENT - 1) as int64);
	let offsets: uint32[8] = [0, 0, 0, 0, 0, 0, 0, 0];
	let n = 0;
	for (let s = 0; s < DOOR_UNIFORM_SLOTS; s++) {
		if ((record.uniformMask & ((1 as uint32) << (s as uint32))) == 0) { continue; }
		offsets[n] = uniformOffsets[s];
		n++;
	}
	pass.setBindGroup(GPU_UNIFORM_GROUP, record.uniformGroup, offsets[0..n]);
}

@exportName("doorDraw")
export function doorDraw(base: int32, count: int32, instances: int32): void {
	frameStats[DOOR_STAT_DRAWS]++;
	if (current >= 0 && pipelines[current].indexed) {
		pass.drawIndexed(count, instances, base, 0, 0);
	} else {
		pass.draw(count, instances, base, 0);
	}
}

@exportName("doorApplyScissor")
export function doorApplyScissor(x: int32, y: int32, width: int32, height: int32): void {
	pass.setScissorRect(x, y, width, height);
}

// ---- passes ----

export const DOOR_PASS_NONE = 0;
export const DOOR_PASS_TARGET = 1;
export const DOOR_PASS_SCREEN = 2;

function stopOnOpenPass(call: string): void {
	if (openPass != DOOR_PASS_NONE) { fail(call + " with a pass already open; endPass ends it"); }
}

function frameEncoder(): GPUCommandEncoder {
	if (encoder.id == 0) { encoder = device.createCommandEncoder(); }
	return encoder;
}

// Words of door.h's pass descriptor and its clear values.
export function doorBeginPass(d: Readonly<Span<uint32>>, clear: Readonly<Span<float32>>): void {
	if (d.length < 11 || clear.length < 17) { fail("beginPass descriptor holds " + String(d.length) + " of 11 words and " + String(clear.length) + " of 17 clear values"); }
	stopOnOpenPass("beginPass");
	let descriptor = { label: null } as GPURenderPassDescriptor;
	for (let i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
		const view = d[i];
		if (view == 0) { continue; }
		if (doorViewAlive(view) == 0) { fail("beginPass on color attachment " + String(i) + ", whose view " + String(view) + " is not alive"); }
		descriptor.colorAttachments[i] = {
			view: { id: view },
			resolveTarget: { id: 0 },
			clearValue: { r: clear[i * 4], g: clear[i * 4 + 1], b: clear[i * 4 + 2], a: clear[i * 4 + 3] },
			loadOp: pick(LOAD_OPS, d[4 + i]),
			storeOp: "store",
		};
	}
	const depthView = d[8];
	if (depthView != 0) {
		if (doorViewAlive(depthView) == 0) { fail("beginPass on the depth attachment, whose view " + String(depthView) + " is not alive"); }
		descriptor.depthStencilAttachment = {
			view: { id: depthView },
			depthClearValue: clear[16],
			depthLoadOp: pick(LOAD_OPS, d[9]),
			depthStoreOp: pick(STORE_OPS, d[10]),
		};
	}
	pass = frameEncoder().beginRenderPass(descriptor);
	frameStats[DOOR_STAT_PASSES]++;
	openPass = DOOR_PASS_TARGET;
	for (let i = 0; i < 4; i++) { passViews[i] = d[i]; }
	passViews[4] = depthView;
	current = -1;
}

@exportName("doorBeginColorPass")
export function doorBeginColorPass(view: uint32, red: float32, green: float32, blue: float32, alpha: float32): void {
	stopOnOpenPass("beginColorPass");
	if (doorViewAlive(view) == 0) { fail("beginColorPass on view " + String(view) + ", which is not a live attachment"); }
	let descriptor = { label: null } as GPURenderPassDescriptor;
	descriptor.colorAttachments[0] = { view: { id: view }, resolveTarget: { id: 0 }, clearValue: { r: red, g: green, b: blue, a: alpha }, loadOp: "clear", storeOp: "store" };
	pass = frameEncoder().beginRenderPass(descriptor);
	frameStats[DOOR_STAT_PASSES]++;
	openPass = DOOR_PASS_TARGET;
	passViews = [view, 0, 0, 0, 0];
	current = -1;
}

@exportName("doorBeginScreenPass")
export function doorBeginScreenPass(red: float32, green: float32, blue: float32, alpha: float32): void {
	stopOnOpenPass("beginScreenPass");
	let descriptor = { label: null } as GPURenderPassDescriptor;
	const screen = getCurrentTexture({
		width: voidSwapchainWidth(),
		height: voidSwapchainHeight(),
		sampleCount: voidSwapchainSampleCount(),
		renderView: voidSwapchainRenderView(),
		resolveView: voidSwapchainResolveView(),
		depthStencilView: voidSwapchainDepthStencilView(),
	}).createView({ label: null });
	descriptor.colorAttachments[0] = { view: screen, resolveTarget: { id: 0 }, clearValue: { r: red, g: green, b: blue, a: alpha }, loadOp: "clear", storeOp: "store" };
	const depth = getCurrentDepthTexture();
	if (depth.id != 0) {
		descriptor.depthStencilAttachment = { view: depth.createView({ label: null }), depthClearValue: 1, depthLoadOp: "clear", depthStoreOp: "discard" };
	}
	pass = frameEncoder().beginRenderPass(descriptor);
	frameStats[DOOR_STAT_PASSES]++;
	openPass = DOOR_PASS_SCREEN;
	passViews = [0, 0, 0, 0, 0];
	current = -1;
}

@exportName("doorEndPass")
export function doorEndPass(): void {
	if (openPass == DOOR_PASS_NONE) { fail("endPass with no pass open"); }
	pass.end();
	openPass = DOOR_PASS_NONE;
	passViews = [0, 0, 0, 0, 0];
	current = -1;
}

@include("./bridgeCommit.h");
extern function voidCommit(): void;

// The frame's end as the door's contract has it: the bridge's voidCommit submits through
// doorSubmitFrame, then runs the commit hook and presents.
@exportName("doorCommit")
export function doorCommit(): void {
	stopOnOpenPass("commit");
	voidCommit();
}

@exportName("doorSubmitFrame")
export function doorSubmitFrame(): void {
	stopOnOpenPass("commit");
	device.queue.submit(frameEncoder().finish());
	encoder = { id: 0 };
	uniformCursor = 0;
	lastFrameStats = frameStats;
	frameStats = [0, 0, 0, 0, 0];
}

@exportName("doorPassState")
export function doorPassState(): int32 { return openPass; }

export function doorPassAttachesView(view: uint32): int32 {
	if (view == 0 || openPass != DOOR_PASS_TARGET) { return 0; }
	for (let i = 0; i < 5; i++) { if (passViews[i] == view) { return 1; } }
	return 0;
}

// ---- queries ----

export function doorFormatRenderable(format: int32): int32 {
	if (format == FORMAT_NONE || format == FORMAT_DEFAULT) { fail("formatRenderable was asked about PixelFormat " + String(format) + ", which names no one format"); }
	if (device.id == 0) { fail("formatRenderable was asked before gfxSetup made the device"); }
	return device.isRenderable(textureFormat(format, "color")) ? 1 : 0;
}

function pixelFormatOf(format: GPUTextureFormat, role: string): int32 {
	if ((format as string) == "") { return FORMAT_NONE; }
	return match (format) {
		"rgba8unorm" => 2,
		"depth32float" => 3,
		"bgra8unorm" => 4,
		"depth24plus-stencil8" => 5,
		"rgba16float" => 6,
		_ => { fail("the environment's default " + role + " is " + format + ", which PixelFormat does not name"); },
	};
}

function environment(): GPUCanvasConfiguration {
	if (device.id == 0) { fail("a screen layout was resolved before gfxSetup made the device"); }
	return device.getCanvasConfiguration();
}

export function doorEnvironmentColorFormat(): int32 { return pixelFormatOf(environment().format, "color format"); }
export function doorEnvironmentDepthFormat(): int32 { return pixelFormatOf(environment().depthFormat, "depth format"); }
export function doorEnvironmentSampleCount(): int32 { return environment().sampleCount; }
export function doorFrameIndex(): uint32 { return device.frameIndex(); }
function doorOwnedBuffers(): int32 { return uniformRing.isAlive() ? 1 : 0; }
export function doorLiveBuffers(): int32 { return device.liveCounts().buffers - doorOwnedBuffers(); }
export function doorLiveImages(): int32 { return device.liveCounts().textures; }
export function doorLiveViews(): int32 { return device.liveCounts().views; }
export function doorLiveSamplers(): int32 { return device.liveCounts().samplers; }
export function doorLiveShaders(): int32 { return device.liveCounts().shaderModules; }
export function doorLivePipelines(): int32 { return device.liveCounts().pipelines; }

@exportName("doorOriginTopLeft")
export function doorOriginTopLeft(): int32 { return device.getAdapterInfo().originTopLeft ? 1 : 0; }
export function doorDepthZeroToOne(): int32 { return device.getAdapterInfo().depthZeroToOne ? 1 : 0; }
