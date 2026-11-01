import { dx12CompileLog, dx12ComputePipelineCreate, dx12MemoryRead, dx12Release, dx12RenderPipelineCreate, dx12ShaderCompile } from "./d3d12.h";
import { formatInfo } from "./conv.ms";
import { DX12_OK, NativeError, checked, stop } from "./frame.ms";
import {
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_SHADER_BINDINGS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPUBlendComponent,
	GPUComputePipelineDescriptor,
	GPURenderPipelineDescriptor,
	GPUShaderAttribute,
	GPUShaderBinding,
	GPUShaderModuleDescriptor,
	GPUStencilFaceState,
	blendFactorNative,
	blendOperationNative,
	compareNative,
	labelOf,
	stencilOperationNative,
	stopOnUnportedShaderBindings,
	topologyIndex,
	vertexFormatNative,
} from "../types.ms";
import { checkedComputeModule, checkedRenderModule, colorWriteBits, stencil8Mask } from "../validate.ms";
import { put, vacate } from "../pool.ms";

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
const DXGI_R8G8B8A8_UNORM = 28;
const DXGI_R8G8B8A8_UINT = 30;
const DXGI_R8G8B8A8_SNORM = 31;
const DXGI_R8G8B8A8_SINT = 32;
const DXGI_R16G16_FLOAT = 34;
const DXGI_R16G16_UNORM = 35;
const DXGI_R16G16_UINT = 36;
const DXGI_R16G16_SNORM = 37;
const DXGI_R16G16_SINT = 38;
const DXGI_R32_FLOAT = 41;
const DXGI_R32_UINT = 42;
const DXGI_R32_SINT = 43;
const DXGI_R8G8_UNORM = 49;
const DXGI_R8G8_UINT = 50;
const DXGI_R8G8_SNORM = 51;
const DXGI_R8G8_SINT = 52;
const DXGI_UNKNOWN = 0;

const VERTEX_FORMATS: int32[] = [
	DXGI_R8G8_UINT, DXGI_R8G8B8A8_UINT, DXGI_R8G8_SINT, DXGI_R8G8B8A8_SINT, DXGI_R8G8_UNORM, DXGI_R8G8B8A8_UNORM, DXGI_R8G8_SNORM, DXGI_R8G8B8A8_SNORM,
	DXGI_R16G16_UINT, DXGI_R16G16B16A16_UINT, DXGI_R16G16_SINT, DXGI_R16G16B16A16_SINT, DXGI_R16G16_UNORM, DXGI_R16G16B16A16_UNORM, DXGI_R16G16_SNORM, DXGI_R16G16B16A16_SNORM,
	DXGI_R16G16_FLOAT, DXGI_R16G16B16A16_FLOAT, DXGI_R32_FLOAT, DXGI_R32G32_FLOAT, DXGI_R32G32B32_FLOAT, DXGI_R32G32B32A32_FLOAT, DXGI_R32_UINT, DXGI_R32G32_UINT,
	DXGI_R32G32B32_UINT, DXGI_R32G32B32A32_UINT, DXGI_R32_SINT, DXGI_R32G32_SINT, DXGI_R32G32B32_SINT, DXGI_R32G32B32A32_SINT,
];

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
const BLEND_FACTORS: int32[] = [
	BLEND_ZERO, BLEND_ONE, BLEND_SRC_COLOR, BLEND_INV_SRC_COLOR, BLEND_SRC_ALPHA, BLEND_INV_SRC_ALPHA, BLEND_DEST_COLOR, BLEND_INV_DEST_COLOR,
	BLEND_DEST_ALPHA, BLEND_INV_DEST_ALPHA, BLEND_SRC_ALPHA_SAT, BLEND_BLEND_FACTOR, BLEND_INV_BLEND_FACTOR,
];
const ALPHA_BLEND_FACTORS: int32[] = [
	BLEND_ZERO, BLEND_ONE, BLEND_SRC_ALPHA, BLEND_INV_SRC_ALPHA, BLEND_SRC_ALPHA, BLEND_INV_SRC_ALPHA, BLEND_DEST_ALPHA, BLEND_INV_DEST_ALPHA,
	BLEND_DEST_ALPHA, BLEND_INV_DEST_ALPHA, BLEND_SRC_ALPHA_SAT, BLEND_BLEND_FACTOR, BLEND_INV_BLEND_FACTOR,
];
const BLEND_OPERATIONS: int32[] = [1, 2, 3, 4, 5];
const COMPARE_FUNCTIONS: int32[] = [1, 2, 3, 4, 5, 6, 7, 8];
const STENCIL_OPERATIONS: int32[] = [1, 2, 3, 6, 4, 5, 7, 8];
const TOPOLOGY_TYPES: int32[] = [1, 2, 2, 3, 3];
const TOPOLOGIES: int32[] = [1, 2, 3, 4, 5];
const CULL_NONE = 1;
const CULL_FRONT = 2;
const CULL_BACK = 3;
const STRIP_CUT_DISABLED = 0;
const STRIP_CUT_16 = 1;
const STRIP_CUT_32 = 2;

const INPUT_ELEMENT_WORDS: int32 = 5;
const TARGET_WORDS: int32 = 10;
const PIPELINE_TOPOLOGY_TYPE: int32 = 0;
const PIPELINE_SAMPLE_COUNT: int32 = 1;
const PIPELINE_CULL: int32 = 2;
const PIPELINE_FRONT_CCW: int32 = 3;
const PIPELINE_DEPTH_BIAS: int32 = 4;
const PIPELINE_DSV_FORMAT: int32 = 5;
const PIPELINE_DEPTH_ENABLE: int32 = 6;
const PIPELINE_DEPTH_WRITE: int32 = 7;
const PIPELINE_DEPTH_FUNC: int32 = 8;
const PIPELINE_STENCIL_ENABLE: int32 = 9;
const PIPELINE_STENCIL_READ_MASK: int32 = 10;
const PIPELINE_STENCIL_WRITE_MASK: int32 = 11;
const PIPELINE_FRONT_FACE: int32 = 12;
const PIPELINE_BACK_FACE: int32 = 16;
const PIPELINE_STRIP_CUT: int32 = 20;
const PIPELINE_WORDS: int32 = 21;
const COMPARE_ALWAYS = 8;

export struct ShaderNative {
	compute: boolean;
	vertex: Vec<uint8>;
	pixel: Vec<uint8>;
	computeBytes: Vec<uint8>;
	computeEntry: string;
	bindings: GPUShaderBinding[GPU_MAX_SHADER_BINDINGS];
	attributes: GPUShaderAttribute[GPU_MAX_VERTEX_ATTRIBUTES];
}

export struct PipelineNative {
	state: uint64;
	topology: int32;
	strides: int32[GPU_MAX_VERTEX_BUFFERS];
}

export const NO_SHADER: ShaderNative = { compute: false, vertex: [], pixel: [], computeBytes: [], computeEntry: "" };
export const NO_PIPELINE: PipelineNative = { state: 0, topology: 0 };

@noinline function stopOnMember(member: string, value: string): never {
	stop(`${member} '${value}' is not supported`);
}

// A stage's precompiled bytes skip D3DCompile; no stage reaching it loads d3dcompiler_47.dll.
function stageBytes(code: string, bytecode: Vec<uint8>, entryPoint: string, target: string, label: string | null): Vec<uint8> {
	if (bytecode.length > 0) { return bytecode; }
	return compileStage(code, entryName(entryPoint), target, label);
}

function entryName(entryPoint: string): string {
	return entryPoint == "" ? "main" : entryPoint;
}

function compileStage(code: string, entryPoint: string, target: string, label: string | null): Vec<uint8> {
	let blob: uint64 = 0;
	let pointer: uint64 = 0;
	let size: uint64 = 0;
	if (dx12ShaderCompile(code, entryPoint, target, blob, pointer, size) != DX12_OK) {
		const log: string = dx12CompileLog();
		stop(`D3DCompile ${target} failed for ${labelOf(label)}:\n${log}`);
	}
	let bytes: Vec<uint8> = new Array(size as number);
	dx12MemoryRead(pointer, bytes[0], size);
	dx12Release(blob);
	return bytes;
}

export function createShaderModule(ref shaders: Vec<ShaderNative>, id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	stopOnUnportedShaderBindings("d3d12", descriptor);
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	const label = descriptor.label;
	put(shaders, id, {
		compute: compute,
		vertex: compute ? [] : stageBytes(descriptor.vertexCode, descriptor.vertexBytecode, descriptor.vertexEntryPoint, "vs_5_0", label),
		pixel: compute ? [] : stageBytes(descriptor.fragmentCode, descriptor.fragmentBytecode, descriptor.fragmentEntryPoint, "ps_5_0", label),
		computeBytes: compute ? stageBytes(descriptor.computeCode, descriptor.computeBytecode, descriptor.computeEntryPoint, "cs_5_0", label) : [],
		computeEntry: entryName(descriptor.computeEntryPoint),
		bindings: descriptor.bindings,
		attributes: descriptor.attributes,
	});
}

export function destroyShaderModule(ref shaders: Vec<ShaderNative>, id: uint32): void {
	vacate(shaders, id);
}

function cullMode(cull: string): int32 {
	return match (cull) {
		"none" => CULL_NONE,
		"front" => CULL_FRONT,
		"back" => CULL_BACK,
		_ => stopOnMember("primitive.cullMode", cull),
	};
}

function frontCounterClockwise(face: string): int32 {
	return match (face) {
		"ccw" => 1,
		"cw" => 0,
		_ => stopOnMember("primitive.frontFace", face),
	};
}

function stripCut(topology: int32, format: string | null): int32 {
	if (topology != 2 && topology != 4 || format == null) { return STRIP_CUT_DISABLED; }
	return match (format) {
		"uint16" => STRIP_CUT_16,
		"uint32" => STRIP_CUT_32,
		_ => stopOnMember("primitive.stripIndexFormat", format),
	};
}

function blendFactor(factor: string | null, alpha: boolean, member: string): int32 {
	return blendFactorNative(alpha ? ALPHA_BLEND_FACTORS : BLEND_FACTORS, factor, member, "d3d12");
}

function destinationFactor(factor: string | null, alpha: boolean, member: string): int32 {
	if (factor == null) { return BLEND_ZERO; }
	return blendFactor(factor, alpha, member);
}

function semanticIndexOf(shader: ShaderNative, location: int32): int32 {
	for (const attribute of shader.attributes) {
		if (attribute.location == location) { return attribute.semanticIndex; }
	}
	return stopOnMember("vertex attribute shaderLocation (absent from the shader reflection)", `${location}`);
}

function stencilFace(ref words: int32[PIPELINE_WORDS], at: int32, face: GPUStencilFaceState, side: string): void {
	words[at] = stencilOperationNative(STENCIL_OPERATIONS, face.failOp, `depthStencil.${side}.failOp`, "d3d12");
	words[at + 1] = stencilOperationNative(STENCIL_OPERATIONS, face.depthFailOp, `depthStencil.${side}.depthFailOp`, "d3d12");
	words[at + 2] = stencilOperationNative(STENCIL_OPERATIONS, face.passOp, `depthStencil.${side}.passOp`, "d3d12");
	words[at + 3] = compareNative(COMPARE_FUNCTIONS, face.compare, `depthStencil.${side}.compare`, "d3d12");
}

function pipelineWords(descriptor: GPURenderPipelineDescriptor, topology: int32): int32[PIPELINE_WORDS] {
	let words: int32[PIPELINE_WORDS] = [0];
	words[PIPELINE_TOPOLOGY_TYPE] = TOPOLOGY_TYPES[topology];
	words[PIPELINE_SAMPLE_COUNT] = descriptor.multisample.count;
	words[PIPELINE_CULL] = cullMode(descriptor.primitive.cullMode ?? "none");
	words[PIPELINE_FRONT_CCW] = frontCounterClockwise(descriptor.primitive.frontFace ?? "ccw");
	words[PIPELINE_DEPTH_BIAS] = descriptor.depthStencil.depthBias;
	words[PIPELINE_STRIP_CUT] = stripCut(topology, descriptor.primitive.stripIndexFormat);
	words[PIPELINE_STENCIL_READ_MASK] = stencil8Mask(descriptor.depthStencil.stencilReadMask);
	words[PIPELINE_STENCIL_WRITE_MASK] = stencil8Mask(descriptor.depthStencil.stencilWriteMask);
	stencilFace(words, PIPELINE_FRONT_FACE, descriptor.depthStencil.stencilFront, "stencilFront");
	stencilFace(words, PIPELINE_BACK_FACE, descriptor.depthStencil.stencilBack, "stencilBack");
	words[PIPELINE_DSV_FORMAT] = DXGI_UNKNOWN;
	words[PIPELINE_DEPTH_FUNC] = COMPARE_ALWAYS;
	const depthFormat = descriptor.depthStencil.format;
	if (depthFormat == null) { return words; }
	const info = formatInfo(depthFormat, "depthStencil.format");
	words[PIPELINE_DSV_FORMAT] = info.depthStencil;
	words[PIPELINE_DEPTH_ENABLE] = 1;
	words[PIPELINE_DEPTH_WRITE] = descriptor.depthStencil.depthWriteEnabled ? 1 : 0;
	words[PIPELINE_DEPTH_FUNC] = compareNative(COMPARE_FUNCTIONS, descriptor.depthStencil.depthCompare, "depthStencil.depthCompare", "d3d12");
	words[PIPELINE_STENCIL_ENABLE] = info.stencil ? 1 : 0;
	return words;
}

export function createRenderPipeline(
	ref pipelines: Vec<PipelineNative>,
	device: uint64,
	signature: uint64,
	shader: ShaderNative,
	id: uint32,
	descriptor: GPURenderPipelineDescriptor,
): Result<void, NativeError> {
	checkedRenderModule(shader.compute);
	const topology = topologyIndex(descriptor.primitive.topology, "primitive.topology", "d3d12");
	let native: PipelineNative = { state: 0, topology: TOPOLOGIES[topology] };
	let elements: int32[INPUT_ELEMENT_WORDS * GPU_MAX_VERTEX_ATTRIBUTES] = [0];
	let count: int32 = 0;
	for (let b: int32 = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const buffer = descriptor.vertex.buffers[b];
		const stepMode: string | null = buffer.stepMode;
		if (stepMode != null && stepMode != "vertex" && stepMode != "instance") { stopOnMember("vertex.buffers stepMode", stepMode); }
		native.strides[b] = buffer.arrayStride;
		for (const attribute of buffer.attributes) {
			const format = attribute.format;
			if (format == null) { continue; }
			if (count == GPU_MAX_VERTEX_ATTRIBUTES) { stop(`pipeline ${labelOf(descriptor.label)} has over ${GPU_MAX_VERTEX_ATTRIBUTES} vertex attributes`); }
			const e = count * INPUT_ELEMENT_WORDS;
			elements[e] = semanticIndexOf(shader, attribute.shaderLocation);
			elements[e + 1] = vertexFormatNative(VERTEX_FORMATS, format, "vertex attribute format", "d3d12");
			elements[e + 2] = b;
			elements[e + 3] = attribute.offset;
			elements[e + 4] = stepMode == "instance" ? 1 : 0;
			count += 1;
		}
	}
	let targets: int32[TARGET_WORDS * GPU_MAX_COLOR_ATTACHMENTS] = [0];
	let targetCount: int32 = 0;
	for (let i: int32 = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const target = descriptor.fragment.targets[i];
		const format = target.format;
		if (format == null) { continue; }
		const color: GPUBlendComponent = target.blend.color;
		const alpha: GPUBlendComponent = target.blend.alpha;
		const t = targetCount * TARGET_WORDS;
		targets[t] = i;
		targets[t + 1] = target.blendEnabled ? 1 : 0;
		targets[t + 2] = blendFactor(color.srcFactor, false, "blend.color.srcFactor");
		targets[t + 3] = destinationFactor(color.dstFactor, false, "blend.color.dstFactor");
		targets[t + 4] = blendOperationNative(BLEND_OPERATIONS, color.operation, "blend.color.operation", "d3d12");
		targets[t + 5] = blendFactor(alpha.srcFactor, true, "blend.alpha.srcFactor");
		targets[t + 6] = destinationFactor(alpha.dstFactor, true, "blend.alpha.dstFactor");
		targets[t + 7] = blendOperationNative(BLEND_OPERATIONS, alpha.operation, "blend.alpha.operation", "d3d12");
		targets[t + 8] = colorWriteBits(target.writeMask);
		targets[t + 9] = formatInfo(format, `fragment.targets[${i}].format`).renderTarget;
		targetCount += 1;
	}
	const words = pipelineWords(descriptor, topology);
	let state: uint64 = 0;
	try checked(dx12RenderPipelineCreate(
		device,
		signature,
		shader.vertex[0],
		shader.vertex.length as uint64,
		shader.pixel[0],
		shader.pixel.length as uint64,
		elements[0],
		count as uint32,
		targets[0],
		targetCount as uint32,
		words[0],
		PIPELINE_WORDS as uint32,
		descriptor.depthStencil.depthBiasSlopeScale as float64,
		descriptor.depthStencil.depthBiasClamp as float64,
		state,
	));
	native.state = state;
	put(pipelines, id, native);
	return Result.ok(null);
}

export function createComputePipeline(
	ref pipelines: Vec<PipelineNative>,
	device: uint64,
	signature: uint64,
	shader: ShaderNative,
	id: uint32,
	descriptor: GPUComputePipelineDescriptor,
): Result<void, NativeError> {
	checkedComputeModule(shader.compute, entryName(descriptor.compute.entryPoint), shader.computeEntry);
	let state: uint64 = 0;
	try checked(dx12ComputePipelineCreate(device, signature, shader.computeBytes[0], shader.computeBytes.length as uint64, state));
	put(pipelines, id, { state: state, topology: 0 });
	return Result.ok(null);
}
