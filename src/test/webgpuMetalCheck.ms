import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBlendFactor,
	GPUCompareFunction,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPUIndexFormat,
	GPUPrimitiveTopology,
	GPURenderPassDescriptor,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilOperation,
	GPUTexture,
	GPUTextureUsage,
	GPUTextureView,
} from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { nativeQueue, nativeTexture } from "../webgpu/metal/backend.ms";
import { metalReadback, metalSystemDevice } from "./metalDevice.h";

@compile("./metalDevice.m");

const SIZE = 64;
const BLUE: uint32 = 0x0000FFFF;
const RED: uint32 = 0xFF0000FF;
const GREEN: uint32 = 0x00FF00FF;

const VERTEX_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct In { float2 position [[attribute(0)]]; };\nstruct Out { float4 position [[position]]; };\nvertex Out vmain(In in [[stage_in]]) { Out out; out.position = float4(in.position, 0.0, 1.0); return out; }\n";
const FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Params { float4 color; };\nfragment float4 fmain(constant Params& params [[buffer(0)]]) { return params.color; }\n";

function stopOnMetal(message: string): void {
	console.log(`webgpuMetalCheck: ${message}`);
	unreachable;
}

function openDevice(): GPUDevice {
	const native = metalSystemDevice();
	if (native == null) { stopOnMetal("MTLCreateSystemDefaultDevice returned nil"); }
	return requestDevice({
		device: native,
		context: null,
		colorFormat: "rgba8unorm",
		depthFormat: "depth32float",
		sampleCount: 1,
	});
}

function flatShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "flat",
		vertexCode: VERTEX_MSL,
		vertexEntryPoint: "vmain",
		fragmentCode: FRAGMENT_MSL,
		fragmentEntryPoint: "fmain",
	};
	descriptor.bindings[0] = { group: 0, binding: 0, kind: "uniform", stage: "fragment", size: 16, nativeSlot: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	return device.createShaderModule(descriptor);
}

function flatPipeline(device: GPUDevice, module: GPUShaderModule, sampleCount: int32): GPURenderPipeline {
	let descriptor: GPURenderPipelineDescriptor = { label: "flat" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.multisample.count = sampleCount;
	return device.createRenderPipeline(descriptor);
}

function colourUniforms(device: GPUDevice): GPUBuffer {
	const buffer = device.createBuffer({
		label: "colours",
		size: 512,
		usage: (GPUBufferUsage.UNIFORM as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const red: Vec<float32> = [1.0, 0.0, 0.0, 1.0];
	const green: Vec<float32> = [0.0, 1.0, 0.0, 1.0];
	device.queue.writeBuffer(buffer, 0, red);
	device.queue.writeBuffer(buffer, 256, green);
	return buffer;
}

function uniformGroup(device: GPUDevice, pipeline: GPURenderPipeline, uniforms: GPUBuffer): GPUBindGroup {
	let descriptor: GPUBindGroupDescriptor = { label: "colours", layout: pipeline.getBindGroupLayout(0) };
	descriptor.entries[0] = { binding: 0, buffer: uniforms, size: 16 };
	return device.createBindGroup(descriptor);
}

function vertexBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "vertices",
		size: size,
		usage: (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
}

function colourTarget(device: GPUDevice, sampleCount: int32): GPUTexture {
	return device.createTexture({
		label: "target",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: sampleCount,
	});
}

function clearingPass(view: GPUTextureView, resolve: GPUTextureView): GPURenderPassDescriptor {
	let descriptor: GPURenderPassDescriptor = { label: "pass" };
	descriptor.colorAttachments[0] = {
		view: view,
		resolveTarget: resolve,
		clearValue: { r: 0.0, g: 0.0, b: 1.0, a: 1.0 },
		loadOp: "clear",
		storeOp: "store",
	};
	return descriptor;
}

function readPixels(texture: GPUTexture): Vec<uint8> {
	let pixels: Vec<uint8> = new Array(SIZE * SIZE * 4);
	if (metalReadback(nativeQueue(), nativeTexture(texture), pixels[0], SIZE, SIZE) != 1) { stopOnMetal("the blit readback failed"); }
	return pixels;
}

function pixel(pixels: Vec<uint8>, x: int32, y: int32): uint32 {
	const at = (y * SIZE + x) * 4;
	return ((pixels[at] as uint32) << 24) | ((pixels[at + 1] as uint32) << 16) |
		((pixels[at + 2] as uint32) << 8) | (pixels[at + 3] as uint32);
}

function drawTriangle(device: GPUDevice, sampleCount: int32, dynamicOffset: uint32): Vec<uint8> {
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, sampleCount);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, sampleCount);
	const view = target.createView({ label: null });
	let readTexture = target;
	let resolveView: GPUTextureView = { id: 0 };
	if (sampleCount > 1) {
		readTexture = colourTarget(device, 1);
		resolveView = readTexture.createView({ label: null });
	}
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(view, resolveView));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [dynamicOffset];
	pass.setBindGroup(0, group, offsets);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(readTexture);
}

test "a Metal triangle takes its colour from the uniform block at the dynamic offset" {
	const device = openDevice();
	assert device.frameIndex() == 1;
	const pixels = drawTriangle(device, 1, 256);
	assert device.frameIndex() == 2;
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == GREEN;
	assert pixel(pixels, 63, 63) == BLUE;
	const live = device.liveCounts();
	assert live.buffers == 2 && live.textures == 1 && live.views == 1 && live.shaderModules == 1 && live.pipelines == 1;
	device.destroy();
}

test "a 4x multisampled target resolves into its single-sample resolve target" {
	const device = openDevice();
	const pixels = drawTriangle(device, 4, 0);
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == RED;
	device.destroy();
}

test "an indexed uint16 quad draws from a vertex buffer written twice in one frame" {
	const device = openDevice();
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, 1);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 128);
	const junk: Vec<float32> = [9.0, 9.0, 9.0, 9.0];
	const quad: Vec<float32> = [-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, junk);
	device.queue.writeBuffer(vertices, 64, quad);
	const indices = device.createBuffer({
		label: "indices",
		size: 12,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order: Vec<uint16> = [0, 1, 2, 0, 2, 3];
	device.queue.writeBuffer(indices, 0, order);
	const target = colourTarget(device, 1);
	const view = target.createView({ label: null });
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(view, { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 64);
	pass.setIndexBuffer(indices, "uint16", 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	assert pixel(pixels, 4, 4) == BLUE;
	assert pixel(pixels, 20, 20) == RED;
	assert pixel(pixels, 44, 44) == RED;
	assert pixel(pixels, 20, 44) == RED;
	assert pixel(pixels, 60, 32) == BLUE;
	assert uniforms.isAlive();
	uniforms.destroy();
	assert !uniforms.isAlive();
	device.destroy();
}

const TEXTURED_FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 tmain(Out in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) { return tex.sample(smp, in.position.xy / 64.0); }\n";
const COMPARE_FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 cmain(Out in [[stage_in]], depth2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) { float2 uv = in.position.xy / 64.0; return float4(tex.sample_compare(smp, uv, 0.25), tex.sample_compare(smp, uv, 0.75), 0.0, 1.0); }\n";

function sampledShader(device: GPUDevice, fragmentCode: string, entryPoint: string): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "sampled",
		vertexCode: VERTEX_MSL,
		vertexEntryPoint: "vmain",
		fragmentCode: fragmentCode,
		fragmentEntryPoint: entryPoint,
	};
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "texture", stage: "fragment", size: 0, nativeSlot: 0 };
	descriptor.bindings[1] = { group: 1, binding: 1, kind: "sampler", stage: "fragment", size: 0, nativeSlot: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	return device.createShaderModule(descriptor);
}

function sampleCentreWith(device: GPUDevice, module: GPUShaderModule, view: GPUTextureView, sampler: GPUSampler): uint32 {
	const pipeline = flatPipeline(device, module, 1);
	let descriptor: GPUBindGroupDescriptor = { label: "resources", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = { binding: 0, textureView: view };
	descriptor.entries[1] = { binding: 1, sampler: sampler };
	const group = device.createBindGroup(descriptor);
	const vertices = vertexBuffer(device, 48);
	const quad: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const noOffsets: Vec<uint32> = [];
	pass.setBindGroup(1, group, noOffsets);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return pixel(readPixels(target), 32, 32);
}

function clearedDepth(device: GPUDevice, value: float32): GPUTextureView {
	const depth = device.createTexture({
		label: "depth",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "depth32float",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32),
		sampleCount: 1,
	});
	const view = depth.createView({ label: null });
	let descriptor: GPURenderPassDescriptor = { label: "clear depth" };
	descriptor.depthStencilAttachment = { view: view, depthClearValue: value, depthLoadOp: "clear", depthStoreOp: "store" };
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	return view;
}

test "a comparison sampler passes a reference by its compare function against the stored depth" {
	const device = openDevice();
	const module = sampledShader(device, COMPARE_FRAGMENT_MSL, "cmain");
	const depth = clearedDepth(device, 0.5);
	const less = device.createSampler({ label: "less", magFilter: "linear", minFilter: "linear", compare: "less" });
	const greater = device.createSampler({ label: "greater", magFilter: "linear", minFilter: "linear", compare: "greater" });
	assert sampleCentreWith(device, module, depth, less) == RED;
	assert sampleCentreWith(device, module, depth, greater) == GREEN;
	device.destroy();
}

test "anisotropic and mip-filtered samplers with W addressing and LOD clamps create" {
	const device = openDevice();
	const anisotropic = device.createSampler({
		label: "aniso",
		addressModeU: "repeat",
		addressModeV: "mirror-repeat",
		addressModeW: "repeat",
		magFilter: "linear",
		minFilter: "linear",
		mipmapFilter: "linear",
		lodMinClamp: 1.0,
		lodMaxClamp: 8.0,
		maxAnisotropy: 8,
	});
	assert anisotropic.isAlive();
	assert device.liveCounts().samplers == 1;
	anisotropic.destroy();
	assert device.liveCounts().samplers == 0;
	device.destroy();
}

function drawFullQuad(device: GPUDevice, viewport: Vec<float32>): Vec<uint8> {
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, 1);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 48);
	const quad: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	if (viewport.length > 0) { pass.setViewport(viewport[0], viewport[1], viewport[2], viewport[3], 0, 1); }
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [256];
	pass.setBindGroup(0, group, offsets);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "setViewport confines a full-target quad to the left half, then to the bottom half" {
	const device = openDevice();
	const left: Vec<float32> = [0.0, 0.0, 32.0, 64.0];
	const leftHalf = drawFullQuad(device, left);
	assert pixel(leftHalf, 16, 32) == GREEN;
	assert pixel(leftHalf, 2, 2) == GREEN;
	assert pixel(leftHalf, 48, 32) == BLUE;
	assert pixel(leftHalf, 62, 62) == BLUE;
	const bottom: Vec<float32> = [0.0, 32.0, 64.0, 32.0];
	const bottomHalf = drawFullQuad(device, bottom);
	assert pixel(bottomHalf, 32, 48) == GREEN;
	assert pixel(bottomHalf, 32, 16) == BLUE;
	const none: Vec<float32> = [];
	assert pixel(drawFullQuad(device, none), 62, 2) == GREEN;
	device.destroy();
}

function blendPipeline(device: GPUDevice, module: GPUShaderModule, source: GPUBlendFactor, destination: GPUBlendFactor): GPURenderPipeline {
	let descriptor: GPURenderPipelineDescriptor = { label: "blend" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.fragment.targets[0].blendEnabled = true;
	descriptor.fragment.targets[0].blend = {
		color: { operation: "add", srcFactor: source, dstFactor: destination },
		alpha: { operation: "add", srcFactor: "one", dstFactor: "zero" },
	};
	return device.createRenderPipeline(descriptor);
}

function blendedRed(device: GPUDevice, source: GPUBlendFactor, destination: GPUBlendFactor, constant: Vec<float64>): uint8 {
	const module = flatShader(device);
	const pipeline = blendPipeline(device, module, source, destination);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, 1);
	let descriptor: GPURenderPassDescriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.colorAttachments[0].clearValue = { r: 0.0, g: 0.0, b: 0.0, a: 1.0 };
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(descriptor);
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	if (constant.length > 0) { pass.setBlendConstant({ r: constant[0], g: constant[0], b: constant[0], a: constant[0] }); }
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	return pixels[(32 * SIZE + 32) * 4];
}

test "a blend constant weights a red source over black, and is zero until set" {
	const device = openDevice();
	const half: Vec<float64> = [0.5];
	const quarter: Vec<float64> = [0.25];
	const unset: Vec<float64> = [];
	const halfRed = blendedRed(device, "constant", "one-minus-constant", half);
	assert halfRed >= 126 && halfRed <= 129;
	const invertedQuarter = blendedRed(device, "one-minus-constant", "constant", quarter);
	assert invertedQuarter >= 190 && invertedQuarter <= 193;
	assert blendedRed(device, "constant", "one-minus-constant", unset) == 0;
	device.destroy();
}

function stencilPipeline(
	device: GPUDevice,
	module: GPUShaderModule,
	compare: GPUCompareFunction,
	passOp: GPUStencilOperation,
	writeMask: uint32,
): GPURenderPipeline {
	let descriptor: GPURenderPipelineDescriptor = { label: "stencil" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.depthStencil.format = "depth24plus-stencil8";
	descriptor.depthStencil.depthCompare = "always";
	descriptor.depthStencil.stencilFront = { compare: compare, passOp: passOp };
	descriptor.depthStencil.stencilBack = { compare: compare, passOp: passOp };
	descriptor.depthStencil.stencilWriteMask = writeMask;
	return device.createRenderPipeline(descriptor);
}

function stencilScene(device: GPUDevice, writerReference: uint32, testerReference: uint32, writerMask: uint32): Vec<uint8> {
	const module = flatShader(device);
	const writer = stencilPipeline(device, module, "always", "replace", writerMask);
	const tester = stencilPipeline(device, module, "equal", "keep", 0);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, writer, uniforms);
	const vertices = vertexBuffer(device, 96);
	const left: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 0.0, 1.0, -1.0, -1.0, 0.0, 1.0, 0.0, -1.0];
	const full: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0];
	device.queue.writeBuffer(vertices, 0, left);
	device.queue.writeBuffer(vertices, 48, full);
	const target = colourTarget(device, 1);
	const depth = device.createTexture({
		label: "depth stencil",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "depth24plus-stencil8",
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
	});
	let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.depthStencilAttachment = {
		view: depth.createView({ label: null }),
		depthClearValue: 1.0,
		depthLoadOp: "clear",
		depthStoreOp: "store",
	};
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(descriptor);
	const red: Vec<uint32> = [0];
	const green: Vec<uint32> = [256];
	pass.setStencilReference(writerReference);
	pass.setPipeline(writer);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(0, group, red);
	pass.draw(6, 1, 0, 0);
	pass.setStencilReference(testerReference);
	pass.setPipeline(tester);
	pass.setVertexBuffer(0, vertices, 48);
	pass.setBindGroup(0, group, green);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "a stencil write at a reference masks a later equal-test draw, by reference and by write mask" {
	const device = openDevice();
	const matched = stencilScene(device, 1, 1, 0);
	assert pixel(matched, 16, 32) == GREEN;
	assert pixel(matched, 48, 32) == BLUE;
	const mismatched = stencilScene(device, 1, 2, 0);
	assert pixel(mismatched, 16, 32) == RED;
	assert pixel(mismatched, 48, 32) == BLUE;
	const masked = stencilScene(device, 3, 2, 2);
	assert pixel(masked, 16, 32) == GREEN;
	const maskedMismatch = stencilScene(device, 3, 3, 2);
	assert pixel(maskedMismatch, 16, 32) == RED;
	device.destroy();
}

const DEPTH_VERTEX_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct In { float3 position [[attribute(0)]]; };\nstruct Out { float4 position [[position]]; };\nvertex Out dmain(In in [[stage_in]]) { Out out; out.position = float4(in.position, 1.0); return out; }\n";

function depthBiasScene(device: GPUDevice, compare: GPUCompareFunction, depthBias: int32, clamp: float32): Vec<uint8> {
	let shader: GPUShaderModuleDescriptor = {
		label: "depth",
		vertexCode: DEPTH_VERTEX_MSL,
		vertexEntryPoint: "dmain",
		fragmentCode: FRAGMENT_MSL,
		fragmentEntryPoint: "fmain",
	};
	shader.bindings[0] = { group: 0, binding: 0, kind: "uniform", stage: "fragment", size: 16, nativeSlot: 0 };
	shader.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const module = device.createShaderModule(shader);
	let descriptor: GPURenderPipelineDescriptor = { label: "depth" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 12;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x3", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.depthStencil.format = "depth32float";
	descriptor.depthStencil.depthWriteEnabled = true;
	descriptor.depthStencil.depthCompare = "always";
	const writer = device.createRenderPipeline(descriptor);
	descriptor.depthStencil.depthCompare = compare;
	descriptor.depthStencil.depthBias = depthBias;
	descriptor.depthStencil.depthBiasClamp = clamp;
	const tester = device.createRenderPipeline(descriptor);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, writer, uniforms);
	const vertices = vertexBuffer(device, 36);
	const triangle: Vec<float32> = [-1.0, -1.0, 0.5, -1.0, 3.0, 0.5, 3.0, -1.0, 0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, 1);
	const depth = device.createTexture({
		label: "depth",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "depth32float",
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
	});
	let pass = clearingPass(target.createView({ label: null }), { id: 0 });
	pass.depthStencilAttachment = {
		view: depth.createView({ label: null }),
		depthClearValue: 1.0,
		depthLoadOp: "clear",
		depthStoreOp: "store",
	};
	const encoder = device.createCommandEncoder();
	const encoded = encoder.beginRenderPass(pass);
	const red: Vec<uint32> = [0];
	const green: Vec<uint32> = [256];
	encoded.setPipeline(writer);
	encoded.setVertexBuffer(0, vertices, 0);
	encoded.setBindGroup(0, group, red);
	encoded.draw(3, 1, 0, 0);
	encoded.setPipeline(tester);
	encoded.setBindGroup(0, group, green);
	encoded.draw(3, 1, 0, 0);
	encoded.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "a negative depth bias lets an equal-depth less-test draw pass, a positive one, none and a tight clamp do not" {
	const device = openDevice();
	assert pixel(depthBiasScene(device, "less", 0, 0.0), 32, 32) == RED;
	assert pixel(depthBiasScene(device, "less", 100000, 0.0), 32, 32) == RED;
	assert pixel(depthBiasScene(device, "less", -100000, 0.0), 32, 32) == GREEN;
	assert pixel(depthBiasScene(device, "greater", 100000, 0.0), 32, 32) == GREEN;
	assert pixel(depthBiasScene(device, "greater", 100000, 0.000000001), 32, 32) == RED;
	device.destroy();
}

const POINT_VERTEX_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct In { float2 position [[attribute(0)]]; };\nstruct Out { float4 position [[position]]; float pointSize [[point_size]]; };\nvertex Out pmain(In in [[stage_in]]) { Out out; out.position = float4(in.position, 0.0, 1.0); out.pointSize = 8.0; return out; }\n";

function topologyDescriptor(module: GPUShaderModule, topology: GPUPrimitiveTopology): GPURenderPipelineDescriptor {
	let descriptor: GPURenderPipelineDescriptor = { label: "topology" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.primitive.topology = topology;
	return descriptor;
}

function drawTopology(device: GPUDevice, vertexCode: string, entryPoint: string, topology: GPUPrimitiveTopology, points: Vec<float32>, count: int32): Vec<uint8> {
	let shader: GPUShaderModuleDescriptor = {
		label: "topology",
		vertexCode: vertexCode,
		vertexEntryPoint: entryPoint,
		fragmentCode: FRAGMENT_MSL,
		fragmentEntryPoint: "fmain",
	};
	shader.bindings[0] = { group: 0, binding: 0, kind: "uniform", stage: "fragment", size: 16, nativeSlot: 0 };
	shader.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const module = device.createShaderModule(shader);
	const pipeline = device.createRenderPipeline(topologyDescriptor(module, topology));
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 64);
	device.queue.writeBuffer(vertices, 0, points);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.draw(count, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "a line-list, a line-strip and a point-list draw their primitives and a triangle-strip fills a quad" {
	const device = openDevice();
	const line: Vec<float32> = [-1.0, -0.51, 1.0, -0.51];
	const lines = drawTopology(device, VERTEX_MSL, "vmain", "line-list", line, 2);
	assert pixel(lines, 32, 48) == RED;
	assert pixel(lines, 32, 40) == BLUE;
	assert pixel(lines, 32, 56) == BLUE;
	const corner: Vec<float32> = [-1.0, -0.51, 0.51, -0.51, 0.51, 0.5];
	const strip = drawTopology(device, VERTEX_MSL, "vmain", "line-strip", corner, 3);
	assert pixel(strip, 20, 48) == RED;
	assert pixel(strip, 48, 32) == RED;
	assert pixel(strip, 16, 32) == BLUE;
	const point: Vec<float32> = [0.0, 0.0];
	const dots = drawTopology(device, POINT_VERTEX_MSL, "pmain", "point-list", point, 1);
	assert pixel(dots, 32, 32) == RED;
	assert pixel(dots, 32, 40) == BLUE;
	const quadPoints: Vec<float32> = [-0.5, -0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5];
	const quad = drawTopology(device, VERTEX_MSL, "vmain", "triangle-strip", quadPoints, 4);
	assert pixel(quad, 32, 32) == RED;
	assert pixel(quad, 20, 44) == RED;
	assert pixel(quad, 4, 4) == BLUE;
	device.destroy();
}

function drawIndexedStrip(device: GPUDevice, format: GPUIndexFormat, indices: GPUBuffer): Vec<uint8> {
	const module = flatShader(device);
	let descriptor = topologyDescriptor(module, "triangle-strip");
	descriptor.primitive.stripIndexFormat = format;
	const pipeline = device.createRenderPipeline(descriptor);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 32);
	const quad: Vec<float32> = [-0.5, -0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5];
	device.queue.writeBuffer(vertices, 0, quad);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setIndexBuffer(indices, format, 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.drawIndexed(4, 1, 0, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "an indexed triangle-strip draws with the strip index format of its pipeline, uint16 and uint32" {
	const device = openDevice();
	const narrow = device.createBuffer({
		label: "indices16",
		size: 8,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order16: Vec<uint16> = [0, 1, 2, 3];
	device.queue.writeBuffer(narrow, 0, order16);
	const quad16 = drawIndexedStrip(device, "uint16", narrow);
	assert pixel(quad16, 32, 32) == RED;
	assert pixel(quad16, 4, 4) == BLUE;
	const wide = device.createBuffer({
		label: "indices32",
		size: 16,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order32: Vec<uint32> = [0, 1, 2, 3];
	device.queue.writeBuffer(wide, 0, order32);
	const quad32 = drawIndexedStrip(device, "uint32", wide);
	assert pixel(quad32, 32, 32) == RED;
	assert pixel(quad32, 62, 62) == BLUE;
	device.destroy();
}
