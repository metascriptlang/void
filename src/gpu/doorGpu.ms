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
	GPUBufferDescriptor,
	GPUBufferUsage,
	GPUMapMode,
	GPUPassTimestampWrites,
	GPUCommandEncoder,
	GPUCompareFunction,
	GPUCullMode,
	GPUDevice,
	GPUExtent3D,
	GPUFilterMode,
	GPUMipmapFilterMode,
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
	GPUTextureDescriptor,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPUVertexBufferLayout,
	GPUVertexFormat,
	GPUVertexStepMode,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_NO_QUERY_INDEX,
	GPU_UNIFORM_GROUP,
	GPU_RESOURCE_GROUP,
	DUMMY_SAMPLER_BINDING,
} from "../webgpu/types.ms";
import {
	GPUNativeEnvironment,
	getCurrentDepthTexture,
	getCurrentTexture,
	requestDevice,
} from "../webgpu/device.ms";
import {
	voidSwapchainDepthStencilView,
	voidSwapchainHeight,
	voidSwapchainRenderView,
	voidSwapchainResolveView,
	voidSwapchainSampleCount,
	voidSwapchainWidth,
} from "../platform/swapchain.h";
import "../sokol/gpu";
import { stop } from "./stop";
import {
	GPU_TIMER_ON,
	timerBufferCount,
	timerBuild,
	timerEnable,
	timerFrameEnd,
	timerPassWrites,
	timerResultCount,
	timerResultFrame,
	timerResultLabel,
	timerResultMs,
	timerState,
} from "./gpuTimer";
import { Vec4 } from "../math/math3d";
import {
	Blend,
	Compare,
	Face,
	FilterMode,
	Operation,
	RenderState,
	Wrap,
} from "./state";
import {
	DOOR_BINDING_INDEX_BUFFER,
	DOOR_BINDING_LENGTH,
	DOOR_BINDING_SAMPLER,
	DOOR_BINDING_VERTEX_BUFFER,
	DOOR_BINDING_VIEW,
} from "./doorWords.h";

export const DOOR_UNIFORM_SLOTS: int32 = 8;
export const DOOR_MAX_COLOR_ATTACHMENTS: int32 = 4;
const VIEW_SLOTS: int32 = 9;
const PASS_VIEW_SLOTS: int32 = 5;
const SAMPLER_SLOTS: int32 = 5;
const SAMPLER_BINDING_BASE: int32 = 32;
const UNIFORM_RING_BYTES: int64 = 4 * 1024 * 1024;
const UNIFORM_ALIGNMENT: int64 = 256;
const BIND_GROUP_CACHE: int32 = 1024;
const CUBE_FACES: int32 = 6;

// Default is the swapchain's own format, for pipelines drawn to the screen. The ordinals are
// door.h's DOOR_PIXEL_FORMAT_*.
export enum PixelFormat {
	None,
	Default,
	Rgba8,
	Depth,
	Bgra8,
	DepthStencil,
	Rgba16f,
	R8,
}

export enum LoadAction {
	Clear,
	Load,
	DontCare,
}

// A depth attachment left at DontCare is discarded at the end of the pass on Metal and WebGPU:
// a depth read later needs Store.
export enum StoreAction {
	Store,
	DontCare,
}

// The ordinals are door.h's DOOR_PASS_NONE, DOOR_PASS_TARGET and DOOR_PASS_SCREEN.
export enum PassState {
	None,
	Target,
	Screen,
}

export enum IndexType {
	None,
	Uint16,
	Uint32,
}

export struct TargetLayout {
	color0: PixelFormat;
	color1: PixelFormat;
	color2: PixelFormat;
	color3: PixelFormat;
	depth: PixelFormat;
	sampleCount: int32;
}

export struct ColorAttachment {
	view: uint32;
	format: PixelFormat;
	load: LoadAction;
	clear: Vec4;
	generation: int32;
}

export struct DepthAttachment {
	view: uint32;
	format: PixelFormat;
	load: LoadAction;
	store: StoreAction;
	clear: float32;
	generation: int32;
}

export struct PipelineDescriptor {
	shader: uint32;
	layout: int32;
	state: RenderState;
	targets: TargetLayout;
	indexType: IndexType;
}

export struct DoorLayout { buffers: GPUVertexBufferLayout[GPU_MAX_VERTEX_BUFFERS]; }

export struct DoorProgram {
	source: (index: int32) => GPUShaderModuleDescriptor;
	index: int32;
	layout: int32;
	uniformMask: uint32;
	uniformBytes: int32[DOOR_UNIFORM_SLOTS];
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
	views: uint32[VIEW_SLOTS];
	samplers: uint32[SAMPLER_SLOTS];
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
let uniformOffsets: uint32[DOOR_UNIFORM_SLOTS] = [0, 0, 0, 0, 0, 0, 0, 0];
// Per slot, which apply last wrote it (counted from 1) and 0 when none has since the pipeline last
// changed: a block applied once stays bound for every draw of that pipeline.
let uniformStamps: int32[DOOR_UNIFORM_SLOTS] = [0, 0, 0, 0, 0, 0, 0, 0];
let uniformStampCounter: int32 = 0;
let encoder: GPUCommandEncoder = { id: 0 };
let pass: GPURenderPassEncoder = { id: 0 };
let current: int32 = -1;
let openPass: PassState = PassState.None;
let passViews: uint32[PASS_VIEW_SLOTS] = [0, 0, 0, 0, 0];
let passWidth: int32 = 0;
let passHeight: int32 = 0;
// Cube images by id, so a texture view of one samples it as a cube, as sokol's does.
let cubeImages: Vec<uint32> = [];

// The platform hands its device over once it exists, and again after a device loss; ids made
// before a new setup are stale, which doorContextGeneration tells the layers above. It starts at
// 1 and only a setup after the first moves it, as bridgeWin.c and bridgeWeb.c counted, so 0 stays
// the generation nothing current carries.
@exportName("doorSetup")
export function doorSetup(
	nativeDevice: Ptr<void> | null,
	nativeContext: Ptr<void> | null,
	colorFormat: int32,
	depthFormat: int32,
	sampleCount: int32,
): void {
	let environment: GPUNativeEnvironment = {
		device: nativeDevice,
		context: nativeContext,
		colorFormat: textureFormatOf(colorFormat as PixelFormat),
		sampleCount,
	};
	if ((depthFormat as PixelFormat) != PixelFormat.None) {
		environment.depthFormat = textureFormatOf(depthFormat as PixelFormat);
	}
	device = requestDevice(environment);
	shaders.length = 0;
	pipelines.length = 0;
	bindCache.length = 0;
	appendCursors.length = 0;
	cubeImages.length = 0;
	uniformRing = device.createBuffer({
		label: "uniforms",
		size: UNIFORM_RING_BYTES,
		usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
	});
	uniformCursor = 0;
	uniformStamps = [0, 0, 0, 0, 0, 0, 0, 0];
	encoder = { id: 0 };
	pass = { id: 0 };
	openPass = PassState.None;
	passViews = [0, 0, 0, 0, 0];
	current = -1;
	resetStats();
	timerBuild(device);
	if (everSetUp) { generation++; }
	everSetUp = true;
}

@exportName("doorShutdown")
export function doorShutdown(): void {
	if (device.id == 0) { return; }
	device.destroy();
	device = { id: 0, queue: { id: 0 } };
	resetStats();
}

// sokol's sg_frame_stats, the members frameClock.c reads: counted through a frame and handed
// over at commit as the previous frame's (sokol_gfx.h _sg_update_stats). The first
// DOOR_STAT_PER_FRAME_COUNT are those per-frame counts; the DOOR_STAT_RESIDENT_* after them are
// the bytes alive now, never reset per frame, and read live rather than from the previous frame.
export const DOOR_STAT_DRAWS: int32 = 0;
export const DOOR_STAT_PIPELINES: int32 = 1;
export const DOOR_STAT_PASSES: int32 = 2;
export const DOOR_STAT_BUFFER_BYTES: int32 = 3;
export const DOOR_STAT_IMAGE_BYTES: int32 = 4;
export const DOOR_STAT_UNIFORM_APPLIES: int32 = 5;
export const DOOR_STAT_UNIFORM_RING_BYTES: int32 = 6;
export const DOOR_STAT_PIPELINE_CHANGES: int32 = 7;
export const DOOR_STAT_PER_FRAME_COUNT: int32 = 8;
export const DOOR_STAT_RESIDENT_BUFFER_BYTES: int32 = 8;
export const DOOR_STAT_RESIDENT_IMAGE_BYTES: int32 = 9;
export const DOOR_STAT_RESIDENT_TARGET_BYTES: int32 = 10;
export const DOOR_STAT_COUNT: int32 = 11;

let frameStats: int64[DOOR_STAT_COUNT] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
let lastFrameStats: int64[DOOR_STAT_COUNT] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

@exportName("doorFrameStat")
export function doorFrameStat(which: int32): int64 {
	if (which < 0 || which >= DOOR_STAT_COUNT) {
		stop("no frame stat " + String(which) + ", the door counts " + String(DOOR_STAT_COUNT));
	}
	return which < DOOR_STAT_PER_FRAME_COUNT ? lastFrameStats[which] : frameStats[which];
}

function endFrameStats(): void {
	lastFrameStats = frameStats;
	for (let i = 0; i < DOOR_STAT_PER_FRAME_COUNT; i++) { frameStats[i] = 0; }
}

struct ResidentBuffer { id: uint32; bytes: int64; }
struct ResidentTexture { id: uint32; bytes: int64; stat: int32; }

let residentBuffers: Vec<ResidentBuffer> = [];
let residentTextures: Vec<ResidentTexture> = [];

// A device is gone with everything it made, so the ids and bytes of the old one go with it.
function resetStats(): void {
	residentBuffers.length = 0;
	residentTextures.length = 0;
	for (let i = 0; i < DOOR_STAT_COUNT; i++) {
		frameStats[i] = 0;
		lastFrameStats[i] = 0;
	}
}

export function trackBuffer(id: uint32, bytes: int64): void {
	for (let i = 0; i < residentBuffers.length; i++) {
		if (residentBuffers[i].id == id) { stop("buffer " + String(id) + " is made twice"); }
	}
	residentBuffers.push({ id, bytes });
	frameStats[DOOR_STAT_RESIDENT_BUFFER_BYTES] += bytes;
}

export function untrackBuffer(id: uint32): void {
	for (let i = 0; i < residentBuffers.length; i++) {
		if (residentBuffers[i].id == id) {
			frameStats[DOOR_STAT_RESIDENT_BUFFER_BYTES] -= residentBuffers[i].bytes;
			residentBuffers.splice(i, 1);
			return;
		}
	}
	stop("destroy of buffer " + String(id) + ", which the door did not make or already destroyed");
}

export function trackTexture(id: uint32, bytes: int64, target: boolean): void {
	for (let i = 0; i < residentTextures.length; i++) {
		if (residentTextures[i].id == id) { stop("image " + String(id) + " is made twice"); }
	}
	const stat = target ? DOOR_STAT_RESIDENT_TARGET_BYTES : DOOR_STAT_RESIDENT_IMAGE_BYTES;
	residentTextures.push({ id, bytes, stat });
	frameStats[stat] += bytes;
}

export function untrackTexture(id: uint32): void {
	for (let i = 0; i < residentTextures.length; i++) {
		if (residentTextures[i].id == id) {
			frameStats[residentTextures[i].stat] -= residentTextures[i].bytes;
			residentTextures.splice(i, 1);
			return;
		}
	}
	stop("destroy of image " + String(id) + ", which the door did not make or already destroyed");
}

export function texelBytes(format: GPUTextureFormat): int64 {
	if (format == "rgba8unorm" || format == "bgra8unorm" || format == "depth32float" ||
		format == "depth24plus-stencil8") { return 4; }
	if (format == "rgba16float") { return 8; }
	if (format == "r8unorm") { return 1; }
	stop("no texel size for texture format " + format);
}

// The bytes of every mip level of every layer; depth24plus-stencil8 counts its nominal 4 bytes,
// the backend picks the real layout.
export function textureBytes(format: GPUTextureFormat, size: GPUExtent3D, levels: int32): int64 {
	let texels: int64 = 0;
	for (let level = 0; level < levels; level++) {
		texels += (mipSide(size.width, level) as int64) * (mipSide(size.height, level) as int64) *
			(size.depthOrArrayLayers as int64);
	}
	return texels * texelBytes(format);
}

function makeTexture(descriptor: GPUTextureDescriptor, target: boolean): GPUTexture {
	const texture = device.createTexture(descriptor);
	if (texture.id != 0) {
		const levels = descriptor.mipLevelCount == 0 ? 1 : descriptor.mipLevelCount;
		trackTexture(texture.id, textureBytes(descriptor.format, descriptor.size, levels), target);
	}
	return texture;
}

function makeBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
	const buffer = device.createBuffer(descriptor);
	if (buffer.id != 0) { trackBuffer(buffer.id, descriptor.size); }
	return buffer;
}

@exportName("doorValid")
export function doorValid(): int32 { return device.id != 0 ? 1 : 0; }

@exportName("doorContextGeneration")
export function doorContextGeneration(): int32 { return generation; }

// ---- registries ----

export struct DoorAttribute {
	location: int32;
	format: GPUVertexFormat;
	buffer: int32;
}

function formatBytes(format: GPUVertexFormat): int32 {
	return match (format) {
		"float32" | "unorm8x4" => 4,
		"float32x2" => 8,
		"float32x3" => 12,
		"float32x4" => 16,
		_ => { stop("vertex format " + format + " has no size"); },
	};
}

// Attributes packed in order per buffer and each stride their sum, as sokol fills a layout whose
// offsets are all zero (_sg_pipeline_desc_defaults).
export function doorLayout(
	attributes: Readonly<Span<DoorAttribute>>,
	steps: Readonly<Span<GPUVertexStepMode>>,
): DoorLayout {
	let layout: DoorLayout = {};
	let counts: int32[GPU_MAX_VERTEX_BUFFERS] = [0, 0];
	for (const attribute of attributes) {
		if (attribute.buffer < 0 || attribute.buffer >= GPU_MAX_VERTEX_BUFFERS) {
			stop("attribute " + String(attribute.location) + " names vertex buffer " +
				String(attribute.buffer));
		}
		const buffer = attribute.buffer;
		layout.buffers[buffer].attributes[counts[buffer]] = {
			format: attribute.format,
			offset: layout.buffers[buffer].arrayStride,
			shaderLocation: attribute.location,
		};
		layout.buffers[buffer].arrayStride += formatBytes(attribute.format);
		counts[buffer]++;
	}
	for (let b = 0; b < steps.length && b < GPU_MAX_VERTEX_BUFFERS; b++) {
		layout.buffers[b].stepMode = steps[b];
	}
	return layout;
}

export function doorRegisterLayouts(entries: Readonly<Span<DoorLayout>>): int32 {
	const base = layouts.length as int32;
	for (const entry of entries) { layouts.push(entry); }
	return base;
}

// `source(i)` builds the module of program i for i in 0..layoutIds.length.
export function doorRegisterPrograms(
	source: (index: int32) => GPUShaderModuleDescriptor,
	layoutIds: Readonly<Span<int32>>,
): int32 {
	const base = programs.length as int32;
	for (let i = 0; i < layoutIds.length; i++) {
		const reflected = source(i as int32);
		let uniformMask: uint32 = 0;
		let textureMask: uint32 = 0;
		let samplerMask: uint32 = 0;
		let bytes: int32[DOOR_UNIFORM_SLOTS] = [0, 0, 0, 0, 0, 0, 0, 0];
		for (const binding of reflected.bindings) {
			if (binding.kind == "uniform") {
				uniformMask |= (1 as uint32) << (binding.binding as uint32);
				bytes[binding.binding] = binding.size;
			} else if (binding.kind == "texture") {
				textureMask |= (1 as uint32) << (binding.binding as uint32);
			} else if (binding.kind == "sampler" && binding.binding != DUMMY_SAMPLER_BINDING) {
				const slot = binding.binding - SAMPLER_BINDING_BASE;
				samplerMask |= (1 as uint32) << (slot as uint32);
			}
		}
		programs.push({
			source,
			index: i as int32,
			layout: layoutIds[i],
			uniformMask,
			uniformBytes: bytes,
			textureMask,
			samplerMask,
		});
	}
	return base;
}

function programAt(program: int32): DoorProgram {
	if (program < 0 || program >= (programs.length as int32)) {
		stop("unregistered program id " + String(program));
	}
	return programs[program];
}

function layoutAt(layout: int32): DoorLayout {
	if (layout < 0 || layout >= (layouts.length as int32)) {
		stop("unregistered layout id " + String(layout));
	}
	return layouts[layout];
}

export function doorProgramCount(): int32 { return programs.length as int32; }
export function doorProgramLayout(program: int32): int32 { return programAt(program).layout; }
export function doorUniformSlotMask(program: int32): uint32 {
	return programAt(program).uniformMask;
}
export function doorTextureSlotMask(program: int32): uint32 {
	return programAt(program).textureMask;
}
export function doorSamplerSlotMask(program: int32): uint32 {
	return programAt(program).samplerMask;
}

export function doorUniformBlockBytes(program: int32, slot: int32): int32 {
	if (slot < 0 || slot >= DOOR_UNIFORM_SLOTS) { return 0; }
	return programAt(program).uniformBytes[slot];
}

function formatFloats(format: GPUVertexFormat): int32 {
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
	for (const attribute of state.attributes) {
		if ((attribute.format as string) == "") { continue; }
		const size = formatFloats(attribute.format);
		if (size < 0) { return -1; }
		floats += size;
	}
	return floats;
}

export function doorLayoutPerInstance(layout: int32, buffer: int32): int32 {
	if (buffer < 0 || buffer >= GPU_MAX_VERTEX_BUFFERS) { return 0; }
	return layoutAt(layout).buffers[buffer].stepMode == "instance" ? 1 : 0;
}

// ---- resources ----

@noinline export function doorMakeShader(program: int32): uint32 {
	const record = programAt(program);
	const module = device.createShaderModule(record.source(record.index));
	if (module.id == 0) { return 0; }
	shaders.push({ module, program });
	return module.id;
}

function shaderProgram(shader: uint32): int32 {
	for (const record of shaders) {
		if (record.module.id == shader) { return record.program; }
	}
	stop("pipeline names shader " + String(shader) + ", which the door did not make");
}

const CULL_MODES: GPUCullMode[3] = ["none", "back", "front"];
const COMPARE_FUNCTIONS: GPUCompareFunction[8] = [
	"always",
	"never",
	"equal",
	"not-equal",
	"greater",
	"greater-equal",
	"less",
	"less-equal",
];
const BLEND_FACTORS: GPUBlendFactor[10] = [
	"one",
	"zero",
	"src-alpha",
	"src",
	"dst-alpha",
	"dst",
	"one-minus-src-alpha",
	"one-minus-src",
	"one-minus-dst-alpha",
	"one-minus-dst",
];
const ALPHA_BLEND_FACTORS: GPUBlendFactor[10] = [
	"one",
	"zero",
	"src-alpha",
	"src-alpha",
	"dst-alpha",
	"dst-alpha",
	"one-minus-src-alpha",
	"one-minus-src-alpha",
	"one-minus-dst-alpha",
	"one-minus-dst-alpha",
];
const BLEND_OPERATIONS: GPUBlendOperation[5] = [
	"add",
	"subtract",
	"reverse-subtract",
	"min",
	"max",
];
const FILTERS: GPUFilterMode[2] = ["nearest", "linear"];
// TextureMipFilter None, Nearest, Linear: None is a nearest mip filter whose lod range the caller
// ends at level 0, as on sokol.
const MIP_FILTERS: GPUMipmapFilterMode[3] = ["nearest", "nearest", "linear"];
const WRAPS: GPUAddressMode[3] = ["clamp-to-edge", "repeat", "mirror-repeat"];

// WebGPU has no DontCare load: it clears.
const LOAD_OPS: GPULoadOp[3] = ["clear", "load", "clear"];
const STORE_OPS: GPUStoreOp[2] = ["store", "discard"];

function isDepthFormat(format: PixelFormat): boolean {
	return format == PixelFormat.Depth || format == PixelFormat.DepthStencil;
}

function textureFormatOf(format: PixelFormat): GPUTextureFormat {
	if (format == PixelFormat.Rgba8) { return "rgba8unorm"; }
	if (format == PixelFormat.Depth) { return "depth32float"; }
	if (format == PixelFormat.Bgra8) { return "bgra8unorm"; }
	if (format == PixelFormat.DepthStencil) { return "depth24plus-stencil8"; }
	if (format == PixelFormat.Rgba16f) { return "rgba16float"; }
	if (format == PixelFormat.R8) { return "r8unorm"; }
	stop("PixelFormat " + format.toString() + " names no texture format");
}

function colorTextureFormat(format: PixelFormat): GPUTextureFormat {
	if (format == PixelFormat.Default) { return device.getCanvasConfiguration().format; }
	return textureFormatOf(format);
}

function depthTextureFormat(format: PixelFormat): GPUTextureFormat {
	if (format == PixelFormat.Default) { return device.getCanvasConfiguration().depthFormat; }
	return textureFormatOf(format);
}

function colorFormatAt(targets: TargetLayout, index: int32): PixelFormat {
	return match (index) {
		0 => targets.color0,
		1 => targets.color1,
		2 => targets.color2,
		_ => targets.color3,
	};
}

@noinline export function doorMakePipeline(description: PipelineDescriptor): uint32 {
	const program = shaderProgram(description.shader);
	const reflected = programAt(program);
	const layout = layoutAt(description.layout);
	const state = description.state;
	const srcColor = BLEND_FACTORS[state.blendSource as int32];
	const dstColor = BLEND_FACTORS[state.blendDestination as int32];
	const srcAlpha = ALPHA_BLEND_FACTORS[state.blendAlphaSource as int32];
	const dstAlpha = ALPHA_BLEND_FACTORS[state.blendAlphaDestination as int32];
	const opColor = BLEND_OPERATIONS[state.blendOperation as int32];
	const opAlpha = BLEND_OPERATIONS[state.blendAlphaOperation as int32];
	const writeMask = (state.colorMask as uint32) as int32;
	const depthFormat = description.targets.depth;
	const indexType = description.indexType;
	const module: GPUShaderModule = { id: description.shader };
	let descriptor = {
		label: "makePipeline",
		vertex: { module, buffers: layout.buffers },
		primitive: {
			topology: "triangle-list",
			frontFace: "ccw",
			cullMode: CULL_MODES[state.culling as int32],
		},
		multisample: { count: description.targets.sampleCount },
		fragment: { module },
	} as GPURenderPipelineDescriptor;
	if (depthFormat != PixelFormat.None) {
		descriptor.depthStencil = {
			format: depthTextureFormat(depthFormat),
			depthWriteEnabled: state.depthWrite,
			depthCompare: COMPARE_FUNCTIONS[state.depthTest as int32],
		};
	}
	for (let i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
		const format = colorFormatAt(description.targets, i);
		if (format == PixelFormat.None) { break; }
		descriptor.fragment.targets[i] = {
			format: colorTextureFormat(format),
			blendEnabled: state.blends(),
			blend: {
				color: { operation: opColor, srcFactor: srcColor, dstFactor: dstColor },
				alpha: { operation: opAlpha, srcFactor: srcAlpha, dstFactor: dstAlpha },
			},
			writeMask,
		};
	}
	const pipeline = device.createRenderPipeline(descriptor);
	if (pipeline.id == 0) { return 0; }
	let uniformGroup: GPUBindGroup = { id: 0 };
	if (reflected.uniformMask != 0) {
		let entries = {
			label: "makePipeline uniforms",
			layout: pipeline.getBindGroupLayout(GPU_UNIFORM_GROUP),
		} as GPUBindGroupDescriptor;
		let n = 0;
		for (let slot = 0; slot < DOOR_UNIFORM_SLOTS; slot++) {
			if ((reflected.uniformMask & ((1 as uint32) << (slot as uint32))) == 0) { continue; }
			entries.entries[n] = {
				binding: slot,
				buffer: uniformRing,
				size: reflected.uniformBytes[slot] as int64,
			};
			n++;
		}
		uniformGroup = device.createBindGroup(entries);
	}
	pipelines.push({
		pipeline,
		indexFormat: indexType == IndexType.Uint32 ? "uint32" : "uint16",
		indexed: indexType != IndexType.None,
		uniformMask: reflected.uniformMask,
		textureMask: reflected.textureMask,
		samplerMask: reflected.samplerMask,
		uniformGroup,
	});
	return pipeline.id;
}

function pipelineIndex(pipeline: uint32): int32 {
	if (current >= 0 && pipelines[current].pipeline.id == pipeline) { return current; }
	for (let i = 0; i < pipelines.length; i++) {
		if (pipelines[i].pipeline.id == pipeline) { return i as int32; }
	}
	stop("apply of pipeline " + String(pipeline) + ", which the door did not make");
}

function texture2dSize(width: int32, height: int32): GPUExtent3D {
	return { width, height, depthOrArrayLayers: 1 };
}

export function doorMakeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32 {
	if (width <= 0 || height <= 0 || rgba.length != (width as int64) * (height as int64)) {
		return 0;
	}
	const texture = makeTexture({
		label: "makeImage",
		size: texture2dSize(width, height),
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
		sampleCount: 1,
	}, false);
	if (texture.id == 0) { return 0; }
	device.queue.writeTexture(
		{ texture },
		rgba,
		{ offset: 0, bytesPerRow: width * 4, rowsPerImage: height },
		texture2dSize(width, height),
	);
	return texture.id;
}

export function fullMipChain(largest: int32): int32 {
	let levels = 1;
	for (let size = largest; size > 1; size = size / 2) { levels++; }
	return levels;
}

export function mipSide(size: int32, level: int32): int32 {
	return Math.max(1, size >> level);
}

export function doorMakeImageMips(
	rgba: Readonly<Span<uint32>>, width: int32, height: int32, levels: int32,
): uint32 {
	if (width <= 0 || height <= 0 || levels < 1) { return 0; }
	if (levels != 1 && levels != fullMipChain(width > height ? width : height)) { return 0; }
	let words: int64 = 0;
	for (let level = 0; level < levels; level++) {
		words += (mipSide(width, level) as int64) * (mipSide(height, level) as int64);
	}
	if (rgba.length != words) { return 0; }
	const texture = makeTexture({
		label: "makeImageMips",
		size: texture2dSize(width, height),
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
		sampleCount: 1,
		mipLevelCount: levels,
	}, false);
	if (texture.id == 0) { return 0; }
	let offset: int64 = 0;
	for (let level = 0; level < levels; level++) {
		const w = mipSide(width, level);
		const h = mipSide(height, level);
		device.queue.writeTexture(
			{ texture, mipLevel: level },
			rgba,
			{ offset: offset * 4, bytesPerRow: w * 4, rowsPerImage: h },
			texture2dSize(w, h),
		);
		offset += (w as int64) * (h as int64);
	}
	return texture.id;
}

function cubeSize(size: int32): GPUExtent3D {
	return { width: size, height: size, depthOrArrayLayers: CUBE_FACES };
}

export function doorMakeCubeImage(rgba: Readonly<Span<uint32>>, size: int32): uint32 {
	const texels = (size as int64) * (size as int64) * (CUBE_FACES as int64);
	if (size <= 0 || rgba.length != texels) { return 0; }
	const texture = makeTexture({
		label: "makeCubeImage",
		size: cubeSize(size),
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
		sampleCount: 1,
	}, false);
	if (texture.id == 0) { return 0; }
	device.queue.writeTexture(
		{ texture },
		rgba,
		{ offset: 0, bytesPerRow: size * 4, rowsPerImage: size },
		cubeSize(size),
	);
	cubeImages.push(texture.id);
	return texture.id;
}

export function doorMakeCubeTargetImage(size: int32, levels: int32, format: int32): uint32 {
	const pixelFormat = format as PixelFormat;
	if (size <= 0 || levels < 1 || levels > fullMipChain(size) || isDepthFormat(pixelFormat)) {
		return 0;
	}
	const texture = makeTexture({
		label: "makeCubeTargetImage",
		size: cubeSize(size),
		format: colorTextureFormat(pixelFormat),
		usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING |
			GPUTextureUsage.COPY_SRC,
		sampleCount: 1,
		mipLevelCount: levels,
	}, true);
	if (texture.id == 0) { return 0; }
	cubeImages.push(texture.id);
	return texture.id;
}

export function doorMakeCubeAttachmentView(image: uint32, face: int32, level: int32): uint32 {
	if (face < 0 || face >= CUBE_FACES || level < 0) { return 0; }
	const texture: GPUTexture = { id: image };
	return texture.createView({
		label: "makeCubeAttachmentView",
		dimension: "2d",
		baseMipLevel: level,
		mipLevelCount: 1,
		baseArrayLayer: face,
		arrayLayerCount: 1,
	}).id;
}

export function doorMakeTargetImage(width: int32, height: int32, format: int32): uint32 {
	if (width <= 0 || height <= 0) { return 0; }
	const pixelFormat = format as PixelFormat;
	return makeTexture({
		label: isDepthFormat(pixelFormat) ? "makeTargetImage depth" : "makeTargetImage color",
		size: texture2dSize(width, height),
		format: isDepthFormat(pixelFormat)
			? depthTextureFormat(pixelFormat)
			: colorTextureFormat(pixelFormat),
		usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING |
			GPUTextureUsage.COPY_SRC,
		sampleCount: 1,
	}, true).id;
}

@exportName("doorMakeTextureView")
export function doorMakeTextureView(image: uint32): uint32 {
	const texture: GPUTexture = { id: image };
	if (cubeImages.includes(image)) {
		return texture.createView({ label: "makeTextureView cube", dimension: "cube" }).id;
	}
	return texture.createView({ label: "makeTextureView" }).id;
}

@exportName("doorMakeSampler")
export function doorMakeSampler(filter: int32, wrap: int32): uint32 {
	const f = FILTERS[filter as FilterMode as int32];
	const w = WRAPS[wrap as Wrap as int32];
	return device.createSampler({
		label: "makeSampler",
		addressModeU: w,
		addressModeV: w,
		magFilter: f,
		minFilter: f,
	}).id;
}

export function doorAnisotropyPortable(): int32 {
	const backend: string = device.getAdapterInfo().backend;
	return backend == "glcore" || backend == "gles3" ? 0 : 1;
}

export function doorMakeSamplerEx(
	minFilter: int32, magFilter: int32, mipFilter: int32, wrapU: int32, wrapV: int32,
	minLod: float32, maxLod: float32, maxAnisotropy: int32,
): uint32 {
	if (minFilter < 0 || minFilter >= 2 || magFilter < 0 || magFilter >= 2 || mipFilter < 0 ||
		mipFilter >= 3 || wrapU < 0 || wrapU >= 3 || wrapV < 0 || wrapV >= 3) { return 0; }
	if (!(minLod >= 0.0) || !(maxLod > 0.0) || maxLod < minLod) { return 0; }
	if (maxAnisotropy < 1 || maxAnisotropy > 16) { return 0; }
	if (maxAnisotropy > 1 && (doorAnisotropyPortable() == 0 || minFilter != 1 || magFilter != 1 ||
		mipFilter != 2)) { return 0; }
	return device.createSampler({
		label: "makeSamplerEx",
		addressModeU: WRAPS[wrapU],
		addressModeV: WRAPS[wrapV],
		magFilter: FILTERS[magFilter],
		minFilter: FILTERS[minFilter],
		mipmapFilter: MIP_FILTERS[mipFilter],
		lodMinClamp: minLod,
		lodMaxClamp: maxLod,
		maxAnisotropy,
	}).id;
}

@exportName("doorImageAlive")
export function doorImageAlive(image: uint32): int32 {
	const texture: GPUTexture = { id: image };
	return texture.isAlive() ? 1 : 0;
}

@exportName("doorViewAlive")
export function doorViewAlive(view: uint32): int32 {
	const textureView: GPUTextureView = { id: view };
	return textureView.isAlive() ? 1 : 0;
}

export function doorSamplerAlive(sampler: uint32): boolean {
	const handle: GPUSampler = { id: sampler };
	return handle.isAlive();
}

export function doorDestroyShader(shader: uint32): void {
	for (let i = 0; i < shaders.length; i++) {
		if (shaders[i].module.id == shader) {
			shaders[i].module.destroy();
			shaders.splice(i, 1);
			return;
		}
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
export function doorDestroyImage(image: uint32): void {
	if (image == 0) { return; }
	const cube = cubeImages.indexOf(image);
	if (cube >= 0) { cubeImages.splice(cube, 1); }
	untrackTexture(image);
	const texture: GPUTexture = { id: image };
	texture.destroy();
}

@exportName("doorDestroyView")
export function doorDestroyView(view: uint32): void {
	if (view == 0) { return; }
	const textureView: GPUTextureView = { id: view };
	textureView.destroy();
}

@exportName("doorDestroySampler")
export function doorDestroySampler(sampler: uint32): void {
	if (sampler == 0) { return; }
	const handle: GPUSampler = { id: sampler };
	handle.destroy();
}

// ---- buffers and textures for the C layers ----

export const DOOR_BUFFER_VERTEX = 1;
export const DOOR_BUFFER_INDEX = 2;

function alignedToFour(bytes: int64): int64 {
	return (bytes + 3) & ~(3 as int64);
}

// `data` empty makes a buffer of `size` bytes to fill later; otherwise the buffer is `data`.
@exportName("doorMakeBuffer")
export function doorMakeBuffer(usage: int32, data: Readonly<Span<uint8>>, size: int64): uint32 {
	const bytes = data.length > 0 ? data.length as int64 : size;
	if (bytes <= 0) { return 0; }
	const buffer = makeBuffer({
		label: (usage & DOOR_BUFFER_INDEX) != 0 ? "makeBuffer index" : "makeBuffer vertex",
		size: alignedToFour(bytes),
		usage: doorBufferUsage(usage),
	});
	if (buffer.id != 0 && data.length > 0) { device.queue.writeBuffer(buffer, 0, data); }
	return buffer.id;
}

export function doorMakeBufferOf<T>(usage: int32, data: Readonly<Span<T>>): uint32 {
	if (data.length == 0) { return 0; }
	const buffer = makeBuffer({
		label: (usage & DOOR_BUFFER_INDEX) != 0 ? "makeBuffer index" : "makeBuffer vertex",
		size: alignedToFour((data.length as int64) * (sizeof(T) as int64)),
		usage: doorBufferUsage(usage),
	});
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
	frameStats[DOOR_STAT_BUFFER_BYTES] += bytes;
	return 1;
}

@exportName("doorUpdateBuffer")
export function doorUpdateBuffer(id: uint32, data: Readonly<Span<uint8>>): int32 {
	return doorUpdateBufferOf(id, data);
}

function appendCursorOf(buffer: uint32): int32 {
	for (let i = 0; i < appendCursors.length; i++) {
		if (appendCursors[i].buffer == buffer) { return i as int32; }
	}
	return -1;
}

// sokol's sg_append_buffer: each append lands after the last one this frame, 4-byte aligned,
// and returns its offset; the first append of a frame starts at 0. -1 when it does not fit.
@exportName("doorAppendBuffer")
export function doorAppendBuffer(id: uint32, data: Readonly<Span<uint8>>): int64 {
	const buffer: GPUBuffer = { id };
	const frame = device.frameIndex();
	let at = appendCursorOf(id);
	if (at < 0) {
		appendCursors.push({ buffer: id, frame, position: 0 });
		at = (appendCursors.length - 1) as int32;
	}
	if (appendCursors[at].frame != frame) {
		appendCursors[at] = { buffer: id, frame, position: 0 };
	}
	const offset = appendCursors[at].position;
	const bytes = data.length as int64;
	if (offset + bytes > buffer.size()) { return -1; }
	if (bytes > 0) { device.queue.writeBuffer(buffer, offset, data); }
	frameStats[DOOR_STAT_BUFFER_BYTES] += bytes;
	appendCursors[at].position = alignedToFour(offset + bytes);
	return offset;
}

@exportName("doorDestroyBuffer")
export function doorDestroyBuffer(id: uint32): void {
	if (id == 0) { return; }
	untrackBuffer(id);
	const buffer: GPUBuffer = { id };
	buffer.destroy();
	const at = appendCursorOf(id);
	if (at >= 0) { appendCursors.splice(at, 1); }
}

@exportName("doorBufferAlive")
export function doorBufferAlive(id: uint32): int32 {
	const buffer: GPUBuffer = { id };
	return buffer.isAlive() ? 1 : 0;
}

export function doorBufferSize(id: uint32): int64 {
	if (id == 0) { return 0; }
	const buffer: GPUBuffer = { id };
	return buffer.size();
}

// A sampled texture of PixelFormat `format`; `data` empty leaves it to doorUpdateTexture.
@exportName("doorMakeTexture")
export function doorMakeTexture(
	width: int32,
	height: int32,
	format: int32,
	data: Readonly<Span<uint8>>,
): uint32 {
	if (width <= 0 || height <= 0) { return 0; }
	const texture = makeTexture({
		label: "makeTexture",
		size: texture2dSize(width, height),
		format: textureFormatOf(format as PixelFormat),
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST |
			GPUTextureUsage.COPY_SRC,
		sampleCount: 1,
	}, false);
	if (texture.id != 0 && data.length > 0) { doorUpdateTexture(texture.id, data); }
	return texture.id;
}

// sokol's sg_update_image: the whole texture, `data` exactly its rows.
@exportName("doorUpdateTexture")
export function doorUpdateTexture(id: uint32, data: Readonly<Span<uint8>>): void {
	doorUpdateTextureOf(id, data);
}

export function doorUpdateTextureOf<T>(id: uint32, data: Readonly<Span<T>>): void {
	const texture: GPUTexture = { id };
	if (!texture.isAlive()) { return; }
	const width = texture.width();
	const height = texture.height();
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (bytes % (height as int64) != 0) {
		stop("updateTexture of " + String(bytes) + " bytes is not whole rows of a texture " +
			String(height) + " high");
	}
	const rowBytes = bytes / (height as int64);
	frameStats[DOOR_STAT_IMAGE_BYTES] += bytes;
	device.queue.writeTexture(
		{ texture },
		data,
		{ offset: 0, bytesPerRow: rowBytes as int32, rowsPerImage: height },
		texture2dSize(width, height),
	);
}

// A partial sampled-texture write: `data` starts at the rectangle's first texel and holds rows
// `bytesPerRow` apart, the last one only as far as the rectangle's width.
@exportName("doorUpdateTextureRect")
export function doorUpdateTextureRect(
	id: uint32,
	x: int32,
	y: int32,
	width: int32,
	height: int32,
	bytesPerRow: int32,
	data: Readonly<Span<uint8>>,
): void {
	const texture: GPUTexture = { id };
	if (!texture.isAlive()) { return; }
	frameStats[DOOR_STAT_IMAGE_BYTES] += data.length as int64;
	device.queue.writeTexture(
		{ texture, origin: { x, y, z: 0 } },
		data,
		{ offset: 0, bytesPerRow, rowsPerImage: height },
		texture2dSize(width, height),
	);
}

export function doorTextureWidth(id: uint32): int32 {
	if (id == 0) { return 0; }
	const texture: GPUTexture = { id };
	return texture.width();
}

export function doorTextureHeight(id: uint32): int32 {
	if (id == 0) { return 0; }
	const texture: GPUTexture = { id };
	return texture.height();
}

@exportName("doorViewImage")
export function doorViewImage(view: uint32): uint32 {
	const textureView: GPUTextureView = { id: view };
	return textureView.isAlive() ? textureView.texture().id : 0;
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
		frameStats[DOOR_STAT_PIPELINE_CHANGES]++;
		current = index;
		pass.setPipeline(pipelines[current].pipeline);
		uniformOffsets = [0, 0, 0, 0, 0, 0, 0, 0];
		uniformStamps = [0, 0, 0, 0, 0, 0, 0, 0];
	}
}

// The stamp of the apply that last wrote `slot` for the current pipeline, 0 when none did: a
// layer that applied a block earlier compares it with the stamp it kept to know the block is
// still the one bound.
export function doorUniformStamp(slot: int32): int32 {
	if (slot < 0 || slot >= DOOR_UNIFORM_SLOTS) { stop("uniform stamp of slot " + String(slot)); }
	return uniformStamps[slot];
}

function sameKey(a: BindKey, b: BindKey): boolean {
	if (a.pipeline != b.pipeline) { return false; }
	for (let i = 0; i < VIEW_SLOTS; i++) { if (a.views[i] != b.views[i]) { return false; } }
	for (let i = 0; i < SAMPLER_SLOTS; i++) {
		if (a.samplers[i] != b.samplers[i]) { return false; }
	}
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
		for (let i = 0; i < BIND_GROUP_CACHE; i++) {
			bindCache.push({ key: { pipeline: 0 }, group: { id: 0 } });
		}
	}
	const at = keyHash(key);
	if (bindCache[at].group.id != 0 && sameKey(bindCache[at].key, key)) {
		return bindCache[at].group;
	}
	if (bindCache[at].group.id != 0) { bindCache[at].group.destroy(); }
	const record = pipelines[current];
	let descriptor = {
		label: "applyBindings",
		layout: record.pipeline.getBindGroupLayout(GPU_RESOURCE_GROUP),
	} as GPUBindGroupDescriptor;
	let n = 0;
	for (let i = 0; i < VIEW_SLOTS; i++) {
		if ((record.textureMask & ((1 as uint32) << (i as uint32))) == 0) { continue; }
		descriptor.entries[n] = { binding: i, textureView: { id: key.views[i] } };
		n++;
	}
	for (let i = 0; i < SAMPLER_SLOTS; i++) {
		if ((record.samplerMask & ((1 as uint32) << (i as uint32))) == 0) { continue; }
		descriptor.entries[n] = {
			binding: SAMPLER_BINDING_BASE + i,
			sampler: { id: key.samplers[i] },
		};
		n++;
	}
	const group = device.createBindGroup(descriptor);
	bindCache[at] = { key, group };
	return group;
}

// `vertexOffsets` are sokol's vertex_buffer_offsets, in bytes.
@exportName("doorApplyBindings")
export function doorApplyBindings(
	bindings: Readonly<Span<uint32>>,
	vertexOffsets: Readonly<Span<int32>>,
): void {
	if (bindings.length < DOOR_BINDING_LENGTH) {
		stop("applyBindings descriptor holds " + String(bindings.length) + " of " +
			String(DOOR_BINDING_LENGTH) + " words");
	}
	if (current < 0) { stop("applyBindings before applyPipeline"); }
	for (let i = 0; i < GPU_MAX_VERTEX_BUFFERS; i++) {
		const buffer = bindings[DOOR_BINDING_VERTEX_BUFFER + i];
		if (buffer != 0) {
			pass.setVertexBuffer(
				i as int32,
				{ id: buffer },
				i < vertexOffsets.length ? vertexOffsets[i] as int64 : 0,
			);
		}
	}
	const record = pipelines[current];
	if (record.indexed) {
		pass.setIndexBuffer({ id: bindings[DOOR_BINDING_INDEX_BUFFER] }, record.indexFormat, 0);
	}
	if (record.textureMask == 0 && record.samplerMask == 0) { return; }
	let key: BindKey = { pipeline: record.pipeline.id };
	for (let i = 0; i < VIEW_SLOTS; i++) { key.views[i] = bindings[DOOR_BINDING_VIEW + i]; }
	for (let i = 0; i < SAMPLER_SLOTS; i++) {
		key.samplers[i] = bindings[DOOR_BINDING_SAMPLER + i];
	}
	pass.setBindGroup(GPU_RESOURCE_GROUP, resourceGroup(key), []);
}

@exportName("doorApplyUniforms")
export function doorApplyUniforms(slot: int32, data: Readonly<Span<uint8>>): void {
	doorApplyUniformsOf(slot, data);
}

export function doorApplyUniformsOf<T>(slot: int32, data: Readonly<Span<T>>): void {
	if (current < 0) { stop("applyUniforms before applyPipeline"); }
	if (slot < 0 || slot >= DOOR_UNIFORM_SLOTS) { stop("applyUniforms to slot " + String(slot)); }
	const record = pipelines[current];
	const bytes = (data.length as int64) * (sizeof(T) as int64);
	if (uniformCursor + bytes > UNIFORM_RING_BYTES) {
		stop("uniform ring of 4 MiB is full this frame");
	}
	device.queue.writeBuffer(uniformRing, uniformCursor, data);
	frameStats[DOOR_STAT_UNIFORM_APPLIES]++;
	uniformStampCounter++;
	uniformStamps[slot] = uniformStampCounter;
	uniformOffsets[slot] = uniformCursor as uint32;
	uniformCursor = (uniformCursor + bytes + (UNIFORM_ALIGNMENT - 1)) & ~(UNIFORM_ALIGNMENT - 1);
	let offsets: uint32[DOOR_UNIFORM_SLOTS] = [0, 0, 0, 0, 0, 0, 0, 0];
	let n = 0;
	for (let s = 0; s < DOOR_UNIFORM_SLOTS; s++) {
		if ((record.uniformMask & ((1 as uint32) << (s as uint32))) == 0) { continue; }
		offsets[n] = uniformOffsets[s];
		n++;
	}
	pass.setBindGroup(GPU_UNIFORM_GROUP, record.uniformGroup, offsets[0..n]);
}

function requireAppliedBlocks(): void {
	const mask = pipelines[current].uniformMask;
	for (let s = 0; s < DOOR_UNIFORM_SLOTS; s++) {
		if ((mask & ((1 as uint32) << (s as uint32))) != 0 && uniformStamps[s] == 0) {
			stop("draw with a pipeline that declares a uniform block at slot " + String(s) +
				" and none was applied since the pipeline was set");
		}
	}
}

@exportName("doorDraw")
export function doorDraw(base: int32, count: int32, instances: int32): void {
	frameStats[DOOR_STAT_DRAWS]++;
	if (current >= 0) { requireAppliedBlocks(); }
	if (current >= 0 && pipelines[current].indexed) {
		pass.drawIndexed(count, instances, base, 0, 0);
	} else {
		pass.draw(count, instances, base, 0);
	}
}

@exportName("doorApplyScissor")
export function doorApplyScissor(x: int32, y: int32, width: int32, height: int32): void {
	const left = Math.min(Math.max(x, 0), passWidth);
	const top = Math.min(Math.max(y, 0), passHeight);
	const right = Math.max(Math.min(x + width, passWidth), left);
	const bottom = Math.max(Math.min(y + height, passHeight), top);
	pass.setScissorRect(left, top, right - left, bottom - top);
}

function measurePass(view: uint32): void {
	const attachment: GPUTextureView = { id: view };
	const level = attachment.baseMipLevel();
	passWidth = mipSide(attachment.texture().width(), level);
	passHeight = mipSide(attachment.texture().height(), level);
}

const READBACK_ROW_ALIGNMENT = 256;

// Tightly packed RGBA8 rows, top row first, of a w x h rectangle at (x, y) of an RGBA8 or BGRA8
// texture. The copy rides the frame's encoder and submits it, so earlier passes have run.
// 0 when `out` is not exactly w * h * 4 bytes.
function readTexture(
	texture: GPUTexture,
	x: int32,
	y: int32,
	width: int32,
	height: int32,
	out: Span<uint8>,
): int32 {
	stopOnOpenPass("readTexture");
	const expectedBytes = (width as int64) * (height as int64) * 4;
	if (width <= 0 || height <= 0 || (out.length as int64) != expectedBytes) { return 0; }
	const format = texture.format();
	if (format != "rgba8unorm" && format != "bgra8unorm") {
		stop("readTexture of " + format + ", which is neither rgba8unorm nor bgra8unorm");
	}
	const rowBytes = width * 4;
	const bytesPerRow = (rowBytes + READBACK_ROW_ALIGNMENT - 1) & ~(READBACK_ROW_ALIGNMENT - 1);
	const staging = device.createBuffer({
		label: "readTexture",
		size: (bytesPerRow as int64) * (height as int64),
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	frameEncoder().copyTextureToBuffer(
		{ texture, mipLevel: 0, origin: { x, y, z: 0 } },
		{ buffer: staging, offset: 0, bytesPerRow, rowsPerImage: height },
		texture2dSize(width, height),
	);
	device.queue.submit(frameEncoder().finish());
	encoder = { id: 0 };
	staging.mapAsync(GPUMapMode.READ as int32, 0, 0);
	const mapped = staging.getMappedRange(0, 0);
	const swizzle = format == "bgra8unorm";
	for (let row = 0; row < height; row++) {
		for (let column = 0; column < width; column++) {
			const from = row * bytesPerRow + column * 4;
			const to = row * rowBytes + column * 4;
			out[to] = mapped[swizzle ? from + 2 : from];
			out[to + 1] = mapped[from + 1];
			out[to + 2] = mapped[swizzle ? from : from + 2];
			out[to + 3] = mapped[from + 3];
		}
	}
	staging.unmap();
	staging.destroy();
	return 1;
}

@exportName("doorReadTexture")
export function doorReadTexture(
	image: uint32,
	x: int32,
	y: int32,
	width: int32,
	height: int32,
	out: Span<uint8>,
): int32 {
	const texture: GPUTexture = { id: image };
	if (!texture.isAlive()) {
		stop("readTexture of image " + String(image) + ", which is not alive");
	}
	return readTexture(texture, x, y, width, height, out);
}

function swapchainTexture(): GPUTexture {
	return getCurrentTexture({
		width: voidSwapchainWidth(),
		height: voidSwapchainHeight(),
		sampleCount: voidSwapchainSampleCount(),
		renderView: voidSwapchainRenderView(),
		resolveView: voidSwapchainResolveView(),
		depthStencilView: voidSwapchainDepthStencilView(),
	});
}

// The screen pass's color target as of the last frame that drew it: the whole swapchain buffer.
@exportName("doorReadScreen")
export function doorReadScreen(out: Span<uint8>): int32 {
	return readTexture(
		swapchainTexture(),
		0,
		0,
		voidSwapchainWidth(),
		voidSwapchainHeight(),
		out,
	);
}

// ---- passes ----

@noinline function stopOnOpenPass(call: string): void {
	if (openPass != PassState.None) { stop(call + " with a pass already open; endPass ends it"); }
}

function timestampsOf(label: string): GPUPassTimestampWrites {
	if (timerState() == GPU_TIMER_ON) { return timerPassWrites(label); }
	return { querySet: { id: 0 }, beginningOfPassWriteIndex: GPU_NO_QUERY_INDEX, endOfPassWriteIndex: GPU_NO_QUERY_INDEX };
}

// The GPU time of each pass, read GPU_TIMER_RING - 1 frames after it was drawn so the read never
// waits (src/gpu/gpuTimer.ms). Returns GPU_TIMER_ON or GPU_TIMER_UNSUPPORTED.
export function doorEnableGpuTimer(maxPasses: int32): int32 { return timerEnable(device, maxPasses); }
export function doorGpuTimerState(): int32 { return timerState(); }
export function doorGpuTimerFrame(): int64 { return timerResultFrame(); }
export function doorGpuTimerPassCount(): int32 { return timerResultCount(); }
export function doorGpuTimerPassMs(index: int32): float64 { return timerResultMs(index); }
export function doorGpuTimerPassLabel(index: int32): string { return timerResultLabel(index); }

function frameEncoder(): GPUCommandEncoder {
	if (encoder.id == 0) { encoder = device.createCommandEncoder(); }
	return encoder;
}

export function doorBeginPass(
	colors: Readonly<Span<ColorAttachment>>, depth: DepthAttachment,
): void {
	if ((colors.length as int32) > DOOR_MAX_COLOR_ATTACHMENTS) {
		stop("beginPass takes at most " + String(DOOR_MAX_COLOR_ATTACHMENTS) +
			" color attachments, given " + String(colors.length));
	}
	stopOnOpenPass("beginPass");
	let descriptor = { label: null } as GPURenderPassDescriptor;
	for (let i = 0; i < (colors.length as int32); i++) {
		const view = colors[i].view;
		if (view == 0) { continue; }
		if (doorViewAlive(view) == 0) {
			stop("beginPass on color attachment " + String(i) + ", whose view " + String(view) +
				" is not alive");
		}
		descriptor.colorAttachments[i] = {
			view: { id: view },
			resolveTarget: { id: 0 },
			clearValue: {
				r: colors[i].clear.x,
				g: colors[i].clear.y,
				b: colors[i].clear.z,
				a: colors[i].clear.w,
			},
			loadOp: LOAD_OPS[colors[i].load as int32],
			storeOp: "store",
		};
	}
	if (depth.view != 0) {
		if (doorViewAlive(depth.view) == 0) {
			stop("beginPass on the depth attachment, whose view " + String(depth.view) +
				" is not alive");
		}
		descriptor.depthStencilAttachment = {
			view: { id: depth.view },
			depthClearValue: depth.clear,
			depthLoadOp: LOAD_OPS[depth.load as int32],
			depthStoreOp: STORE_OPS[depth.store as int32],
		};
	}
	descriptor.timestampWrites = timestampsOf("target");
	pass = frameEncoder().beginRenderPass(descriptor);
	frameStats[DOOR_STAT_PASSES]++;
	openPass = PassState.Target;
	passViews = [0, 0, 0, 0, 0];
	for (let i = 0; i < (colors.length as int32); i++) {
		passViews[i] = colors[i].view;
	}
	passViews[DOOR_MAX_COLOR_ATTACHMENTS] = depth.view;
	for (let i = 0; i < PASS_VIEW_SLOTS; i++) {
		if (passViews[i] != 0) { measurePass(passViews[i]); break; }
	}
	current = -1;
}

@exportName("doorBeginColorPass")
export function doorBeginColorPass(
	view: uint32,
	red: float32,
	green: float32,
	blue: float32,
	alpha: float32,
): void {
	stopOnOpenPass("beginColorPass");
	if (doorViewAlive(view) == 0) {
		stop("beginColorPass on view " + String(view) + ", which is not a live attachment");
	}
	let descriptor = { label: null } as GPURenderPassDescriptor;
	descriptor.colorAttachments[0] = {
		view: { id: view },
		resolveTarget: { id: 0 },
		clearValue: { r: red, g: green, b: blue, a: alpha },
		loadOp: "clear",
		storeOp: "store",
	};
	descriptor.timestampWrites = timestampsOf("color");
	pass = frameEncoder().beginRenderPass(descriptor);
	frameStats[DOOR_STAT_PASSES]++;
	openPass = PassState.Target;
	passViews = [view, 0, 0, 0, 0];
	measurePass(view);
	current = -1;
}

@exportName("doorBeginScreenPass")
export function doorBeginScreenPass(
	red: float32,
	green: float32,
	blue: float32,
	alpha: float32,
): void {
	stopOnOpenPass("beginScreenPass");
	let descriptor = { label: null } as GPURenderPassDescriptor;
	const screen = swapchainTexture().createView({ label: null });
	descriptor.colorAttachments[0] = {
		view: screen,
		resolveTarget: { id: 0 },
		clearValue: { r: red, g: green, b: blue, a: alpha },
		loadOp: "clear",
		storeOp: "store",
	};
	const depth = getCurrentDepthTexture();
	if (depth.id != 0) {
		descriptor.depthStencilAttachment = {
			view: depth.createView({ label: null }),
			depthClearValue: 1,
			depthLoadOp: "clear",
			depthStoreOp: "discard",
		};
	}
	descriptor.timestampWrites = timestampsOf("screen");
	pass = frameEncoder().beginRenderPass(descriptor);
	frameStats[DOOR_STAT_PASSES]++;
	openPass = PassState.Screen;
	passViews = [0, 0, 0, 0, 0];
	measurePass(screen.id);
	current = -1;
}

@exportName("doorEndPass")
export function doorEndPass(): void {
	if (openPass == PassState.None) { stop("endPass with no pass open"); }
	pass.end();
	openPass = PassState.None;
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
	if (timerState() == GPU_TIMER_ON) { timerFrameEnd(frameEncoder()); }
	device.queue.submit(frameEncoder().finish());
	encoder = { id: 0 };
	frameStats[DOOR_STAT_UNIFORM_RING_BYTES] = uniformCursor;
	uniformCursor = 0;
	endFrameStats();
}

@exportName("doorPassState")
export function doorPassState(): int32 { return openPass as int32; }

export function doorPassAttachesView(view: uint32): boolean {
	if (view == 0 || openPass != PassState.Target) { return false; }
	for (const attached of passViews) { if (attached == view) { return true; } }
	return false;
}

// ---- queries ----

export function doorFormatRenderable(format: int32): boolean {
	const pixelFormat = format as PixelFormat;
	if (pixelFormat == PixelFormat.None || pixelFormat == PixelFormat.Default) {
		stop("formatRenderable was asked about PixelFormat " + pixelFormat.toString() +
			", which names no one format");
	}
	if (device.id == 0) { stop("formatRenderable was asked before gfxSetup made the device"); }
	return device.isRenderable(textureFormatOf(pixelFormat));
}

function pixelFormatOf(format: GPUTextureFormat, role: string): PixelFormat {
	if ((format as string) == "") { return PixelFormat.None; }
	return match (format) {
		"rgba8unorm" => PixelFormat.Rgba8,
		"depth32float" => PixelFormat.Depth,
		"bgra8unorm" => PixelFormat.Bgra8,
		"depth24plus-stencil8" => PixelFormat.DepthStencil,
		"rgba16float" => PixelFormat.Rgba16f,
		_ => {
			stop("the environment's default " + role + " is " + format +
				", which PixelFormat does not name");
		},
	};
}

function environment(): GPUCanvasConfiguration {
	if (device.id == 0) { stop("a screen layout was resolved before gfxSetup made the device"); }
	return device.getCanvasConfiguration();
}

export function doorEnvironmentColorFormat(): PixelFormat {
	return pixelFormatOf(environment().format, "color format");
}

export function doorEnvironmentDepthFormat(): PixelFormat {
	return pixelFormatOf(environment().depthFormat, "depth format");
}

export function doorEnvironmentSampleCount(): int32 { return environment().sampleCount; }
export function doorFrameIndex(): uint32 { return device.frameIndex(); }

function doorOwnedBuffers(): int32 { return (uniformRing.isAlive() ? 1 : 0) + timerBufferCount(); }

export function doorLiveBuffers(): int32 {
	return device.liveCounts().buffers - doorOwnedBuffers();
}
export function doorLiveImages(): int32 { return device.liveCounts().textures; }
export function doorLiveViews(): int32 { return device.liveCounts().views; }
export function doorLiveSamplers(): int32 { return device.liveCounts().samplers; }
export function doorLiveShaders(): int32 { return device.liveCounts().shaderModules; }
export function doorLivePipelines(): int32 { return device.liveCounts().pipelines; }

@exportName("doorOriginTopLeft")
export function doorOriginTopLeft(): int32 { return device.getAdapterInfo().originTopLeft ? 1 : 0; }
export function doorDepthZeroToOne(): boolean { return device.getAdapterInfo().depthZeroToOne; }

test "door tables hold one entry per member of the enum that indexes them" {
	assert CULL_MODES.length as int32 == (Face.Front as int32) + 1;
	assert COMPARE_FUNCTIONS.length as int32 == (Compare.LessEqual as int32) + 1;
	assert BLEND_FACTORS.length as int32 == (Blend.OneMinusDestinationColor as int32) + 1;
	assert ALPHA_BLEND_FACTORS.length as int32 == BLEND_FACTORS.length as int32;
	assert BLEND_OPERATIONS.length as int32 == (Operation.Max as int32) + 1;
	assert FILTERS.length as int32 == (FilterMode.Linear as int32) + 1;
	assert WRAPS.length as int32 == (Wrap.Mirror as int32) + 1;
	assert LOAD_OPS.length as int32 == (LoadAction.DontCare as int32) + 1;
	assert STORE_OPS.length as int32 == (StoreAction.DontCare as int32) + 1;
}

test "the binding words of door.h agree with the slot counts" {
	assert VIEW_SLOTS == DOOR_BINDING_SAMPLER - DOOR_BINDING_VIEW;
	assert SAMPLER_SLOTS == DOOR_BINDING_LENGTH - DOOR_BINDING_SAMPLER;
	assert DOOR_BINDING_INDEX_BUFFER == GPU_MAX_VERTEX_BUFFERS;
}

test "a pass names a view per color attachment and one for depth" {
	assert PASS_VIEW_SLOTS == DOOR_MAX_COLOR_ATTACHMENTS + 1;
}

test "doorFrameStat answers each stat from its own slot of the previous frame" {
	resetStats();
	for (let i = 0; i < DOOR_STAT_PER_FRAME_COUNT; i++) { frameStats[i] = (i as int64) + 1; }
	endFrameStats();
	for (let i = 0; i < DOOR_STAT_PER_FRAME_COUNT; i++) {
		assert doorFrameStat(i) == (i as int64) + 1;
		assert frameStats[i] == 0;
	}
	resetStats();
}

test "the door's ordinals stay the numbers door.h gives the C layers" {
	assert (PixelFormat.None as int32) == 0;
	assert (PixelFormat.Rgba8 as int32) == 2;
	assert (PixelFormat.Depth as int32) == 3;
	assert (PixelFormat.Bgra8 as int32) == 4;
	assert (PixelFormat.DepthStencil as int32) == 5;
	assert (PixelFormat.R8 as int32) == 7;
	assert (PassState.None as int32) == 0;
	assert (PassState.Target as int32) == 1;
	assert (PassState.Screen as int32) == 2;
	assert DOOR_STAT_DRAWS == 0;
	assert DOOR_STAT_PIPELINES == 1;
	assert DOOR_STAT_PASSES == 2;
	assert DOOR_STAT_BUFFER_BYTES == 3;
	assert DOOR_STAT_IMAGE_BYTES == 4;
	assert DOOR_STAT_UNIFORM_APPLIES == 5;
	assert DOOR_STAT_UNIFORM_RING_BYTES == 6;
	assert DOOR_STAT_PIPELINE_CHANGES == 7;
	assert DOOR_STAT_RESIDENT_BUFFER_BYTES == 8;
	assert DOOR_STAT_RESIDENT_IMAGE_BYTES == 9;
	assert DOOR_STAT_RESIDENT_TARGET_BYTES == 10;
	assert DOOR_STAT_COUNT == 11;
	assert DOOR_BUFFER_VERTEX == 1;
	assert DOOR_BUFFER_INDEX == 2;
}
