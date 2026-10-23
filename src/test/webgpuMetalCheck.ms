import {
	GPU_NO_QUERY_INDEX,
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBlendFactor,
	GPUCommandEncoder,
	GPUCompareFunction,
	GPUComputePipeline,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPUIndexFormat,
	GPUMapMode,
	GPUVertexFormat,
	GPUPrimitiveTopology,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerBindingType,
	GPUShaderBinding,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilOperation,
	GPUStorageTextureAccess,
	GPUTexture,
	GPUTextureDimension,
	GPUTextureFormat,
	GPUTextureSampleType,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDimension,
} from "../webgpu/types.ms";
import { exec } from "std/process";
import { getCurrentDepthTexture, getCurrentTexture, requestDevice } from "../webgpu/device.ms";
import { nativeQueue, nativeTexture } from "../webgpu/metal/backend.ms";
import { metalLabel, metalReadback, metalSystemDevice } from "./metalDevice.h";

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

function uniformGroupAt(device: GPUDevice, pipeline: GPURenderPipeline, uniforms: GPUBuffer, offset: int64): GPUBindGroup {
	let descriptor: GPUBindGroupDescriptor = { label: "colours", layout: pipeline.getBindGroupLayout(0) };
	descriptor.entries[0] = { binding: 0, buffer: uniforms, offset: offset, size: 16 };
	return device.createBindGroup(descriptor);
}

function uniformGroup(device: GPUDevice, pipeline: GPURenderPipeline, uniforms: GPUBuffer): GPUBindGroup {
	return uniformGroupAt(device, pipeline, uniforms, 0);
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

function readBytes(texture: GPUTexture, level: int32, slice: int32, plane: int32, width: int32, height: int32, bytesPerPixel: int32): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(width * height * bytesPerPixel);
	if (metalReadback(nativeQueue(), nativeTexture(texture), level, slice, plane, bytes[0], width, height, bytesPerPixel) != 1) {
		stopOnMetal("the blit readback failed");
	}
	return bytes;
}

function readPixels(texture: GPUTexture): Vec<uint8> { return readBytes(texture, 0, 0, 0, SIZE, SIZE, 4); }

function pixel(pixels: Vec<uint8>, x: int32, y: int32): uint32 {
	const at = (y * SIZE + x) * 4;
	return ((pixels[at] as uint32) << 24) | ((pixels[at + 1] as uint32) << 16) |
		((pixels[at + 2] as uint32) << 8) | (pixels[at + 3] as uint32);
}

function drawTriangle(device: GPUDevice, sampleCount: int32, dynamicOffset: uint32): Vec<uint8> {
	return drawTriangleAt(device, sampleCount, dynamicOffset, 0);
}

function drawTriangleAt(device: GPUDevice, sampleCount: int32, dynamicOffset: uint32, entryOffset: int64): Vec<uint8> {
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, sampleCount);
	const uniforms = colourUniforms(device);
	const group = uniformGroupAt(device, pipeline, uniforms, entryOffset);
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

function sampledShader(device: GPUDevice, fragmentCode: string, entryPoint: string, texture: GPUShaderBinding, sampler: GPUShaderBinding): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "sampled",
		vertexCode: VERTEX_MSL,
		vertexEntryPoint: "vmain",
		fragmentCode: fragmentCode,
		fragmentEntryPoint: entryPoint,
	};
	descriptor.bindings[0] = texture;
	descriptor.bindings[1] = sampler;
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	return device.createShaderModule(descriptor);
}

function textureBinding(sampleType: GPUTextureSampleType, viewDimension: GPUTextureViewDimension, multisampled: boolean): GPUShaderBinding {
	return {
		group: 1,
		binding: 0,
		kind: "texture",
		stage: "fragment",
		size: 0,
		nativeSlot: 0,
		sampleType: sampleType,
		viewDimension: viewDimension,
		multisampled: multisampled,
	};
}

function samplerBinding(samplerType: GPUSamplerBindingType): GPUShaderBinding {
	return { group: 1, binding: 1, kind: "sampler", stage: "fragment", size: 0, nativeSlot: 0, samplerType: samplerType };
}

const NO_BINDING: GPUShaderBinding = { group: 1, binding: 1 };

function sampleCentreWith(device: GPUDevice, module: GPUShaderModule, view: GPUTextureView, sampler: GPUSampler): uint32 {
	const pipeline = flatPipeline(device, module, 1);
	let descriptor: GPUBindGroupDescriptor = { label: "resources", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = { binding: 0, textureView: view };
	if (sampler.id != 0) { descriptor.entries[1] = { binding: 1, sampler: sampler }; }
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
	const module = sampledShader(device, COMPARE_FRAGMENT_MSL, "cmain", textureBinding("depth", "2d", false), samplerBinding("comparison"));
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

const FLOAT_COLOUR_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct In { float2 position [[attribute(0)]]; float4 color [[attribute(1)]]; };\nstruct Out { float4 position [[position]]; float4 color; };\nvertex Out cmain(In in [[stage_in]]) { Out out; out.position = float4(in.position, 0.0, 1.0); out.color = float4(in.color.rgb, 1.0); return out; }\nfragment float4 fcolour(Out in [[stage_in]]) { return in.color; }\n";
const UINT_COLOUR_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct In { float2 position [[attribute(0)]]; uint4 color [[attribute(1)]]; };\nstruct Out { float4 position [[position]]; float4 color; };\nvertex Out cmain(In in [[stage_in]]) { Out out; out.position = float4(in.position, 0.0, 1.0); out.color = float4(float3(in.color.rgb) / 255.0, 1.0); return out; }\nfragment float4 fcolour(Out in [[stage_in]]) { return in.color; }\n";
const SINT_COLOUR_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct In { float2 position [[attribute(0)]]; int4 color [[attribute(1)]]; };\nstruct Out { float4 position [[position]]; float4 color; };\nvertex Out cmain(In in [[stage_in]]) { Out out; out.position = float4(in.position, 0.0, 1.0); out.color = float4(float3(in.color.rgb) / 127.0, 1.0); return out; }\nfragment float4 fcolour(Out in [[stage_in]]) { return in.color; }\n";

function upload<T>(device: GPUDevice, data: Vec<T>): GPUBuffer {
	const buffer = vertexBuffer(device, (data.length as int64) * (sizeof T as int64));
	device.queue.writeBuffer(buffer, 0, data);
	return buffer;
}

function colourOfFormat(device: GPUDevice, code: string, format: GPUVertexFormat, stride: int32, colours: GPUBuffer): uint32 {
	let shader: GPUShaderModuleDescriptor = {
		label: "colour",
		vertexCode: code,
		vertexEntryPoint: "cmain",
		fragmentCode: code,
		fragmentEntryPoint: "fcolour",
	};
	shader.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	shader.attributes[1] = { location: 1, nativeName: null, semanticIndex: 1 };
	const module = device.createShaderModule(shader);
	let descriptor: GPURenderPipelineDescriptor = { label: "colour" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.vertex.buffers[1].arrayStride = stride;
	descriptor.vertex.buffers[1].stepMode = "instance";
	descriptor.vertex.buffers[1].attributes[0] = { format: format, offset: 0, shaderLocation: 1 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(descriptor);
	const positions = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-1.0, -1.0, -1.0, 3.0, 3.0, -1.0];
	device.queue.writeBuffer(positions, 0, triangle);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, positions, 0);
	pass.setVertexBuffer(1, colours, 0);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return pixel(readPixels(target), 32, 32);
}

test "float, unorm, snorm and half vertex formats reach a float4 attribute, narrower ones padded with 0 and 1" {
	const device = openDevice();
	const one: Vec<float32> = [1.0];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "float32", 4, upload(device, one)) == RED;
	const f2: Vec<float32> = [0.0, 1.0];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "float32x2", 8, upload(device, f2)) == GREEN;
	const f3: Vec<float32> = [0.0, 1.0, 0.0];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "float32x3", 12, upload(device, f3)) == GREEN;
	const f4: Vec<float32> = [0.0, 1.0, 0.0, 1.0];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "float32x4", 16, upload(device, f4)) == GREEN;
	const un8x2: Vec<uint8> = [0, 255, 0, 0];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "unorm8x2", 4, upload(device, un8x2)) == GREEN;
	const un8x4: Vec<uint8> = [0, 255, 0, 255];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "unorm8x4", 4, upload(device, un8x4)) == GREEN;
	const sn8x2: Vec<int8> = [0, 127, 0, 0];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "snorm8x2", 4, upload(device, sn8x2)) == GREEN;
	const sn8x4: Vec<int8> = [0, 127, 0, 127];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "snorm8x4", 4, upload(device, sn8x4)) == GREEN;
	const un16x2: Vec<uint16> = [0, 65535];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "unorm16x2", 4, upload(device, un16x2)) == GREEN;
	const un16x4: Vec<uint16> = [0, 65535, 0, 65535];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "unorm16x4", 8, upload(device, un16x4)) == GREEN;
	const sn16x2: Vec<int16> = [0, 32767];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "snorm16x2", 4, upload(device, sn16x2)) == GREEN;
	const sn16x4: Vec<int16> = [0, 32767, 0, 32767];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "snorm16x4", 8, upload(device, sn16x4)) == GREEN;
	const h2: Vec<uint16> = [0, 0x3C00];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "float16x2", 4, upload(device, h2)) == GREEN;
	const h4: Vec<uint16> = [0, 0x3C00, 0, 0x3C00];
	assert colourOfFormat(device, FLOAT_COLOUR_MSL, "float16x4", 8, upload(device, h4)) == GREEN;
	device.destroy();
}

test "uint vertex formats reach a uint4 attribute at every width" {
	const device = openDevice();
	const u8x2: Vec<uint8> = [0, 255, 0, 0];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint8x2", 4, upload(device, u8x2)) == GREEN;
	const u8x4: Vec<uint8> = [0, 255, 0, 255];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint8x4", 4, upload(device, u8x4)) == GREEN;
	const u16x2: Vec<uint16> = [0, 255];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint16x2", 4, upload(device, u16x2)) == GREEN;
	const u16x4: Vec<uint16> = [0, 255, 0, 255];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint16x4", 8, upload(device, u16x4)) == GREEN;
	const u32: Vec<uint32> = [255];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint32", 4, upload(device, u32)) == RED;
	const u32x2: Vec<uint32> = [0, 255];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint32x2", 8, upload(device, u32x2)) == GREEN;
	const u32x3: Vec<uint32> = [0, 255, 0];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint32x3", 12, upload(device, u32x3)) == GREEN;
	const u32x4: Vec<uint32> = [0, 255, 0, 255];
	assert colourOfFormat(device, UINT_COLOUR_MSL, "uint32x4", 16, upload(device, u32x4)) == GREEN;
	device.destroy();
}

test "sint vertex formats reach an int4 attribute at every width" {
	const device = openDevice();
	const s8x2: Vec<int8> = [0, 127, 0, 0];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint8x2", 4, upload(device, s8x2)) == GREEN;
	const s8x4: Vec<int8> = [0, 127, 0, 127];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint8x4", 4, upload(device, s8x4)) == GREEN;
	const s16x2: Vec<int16> = [0, 127];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint16x2", 4, upload(device, s16x2)) == GREEN;
	const s16x4: Vec<int16> = [0, 127, 0, 127];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint16x4", 8, upload(device, s16x4)) == GREEN;
	const s32: Vec<int32> = [127];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint32", 4, upload(device, s32)) == RED;
	const s32x2: Vec<int32> = [0, 127];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint32x2", 8, upload(device, s32x2)) == GREEN;
	const s32x3: Vec<int32> = [0, 127, 0];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint32x3", 12, upload(device, s32x3)) == GREEN;
	const s32x4: Vec<int32> = [0, 127, 0, 127];
	assert colourOfFormat(device, SINT_COLOUR_MSL, "sint32x4", 16, upload(device, s32x4)) == GREEN;
	device.destroy();
}

function clearedBytes(device: GPUDevice, format: GPUTextureFormat, bytesPerPixel: int32, r: float64, g: float64, b: float64, a: float64): Vec<uint8> {
	const target = device.createTexture({
		label: "format",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: format,
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.colorAttachments[0].clearValue = { r: r, g: g, b: b, a: a };
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	return readBytes(target, 0, 0, 0, 2, 2, bytesPerPixel);
}

function clearedDepthBytes(device: GPUDevice, format: GPUTextureFormat, bytesPerPixel: int32, value: float32): Vec<uint8> {
	const target = device.createTexture({
		label: "depth format",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: format,
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	let descriptor: GPURenderPassDescriptor = { label: "clear depth" };
	descriptor.depthStencilAttachment = { view: target.createView({ label: null }), depthClearValue: value, depthLoadOp: "clear", depthStoreOp: "store" };
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	return readBytes(target, 0, 0, 0, 2, 2, bytesPerPixel);
}

test "an 8-bit colour format stores its clear in its own channel order and encoding" {
	const device = openDevice();
	const r8 = clearedBytes(device, "r8unorm", 1, 1.0, 0.0, 0.0, 1.0);
	assert r8[0] == 255;
	const rg8 = clearedBytes(device, "rg8unorm", 2, 1.0, 0.0, 0.0, 1.0);
	assert rg8[0] == 255 && rg8[1] == 0;
	const bgra = clearedBytes(device, "bgra8unorm", 4, 1.0, 0.0, 0.0, 1.0);
	assert bgra[0] == 0 && bgra[1] == 0 && bgra[2] == 255 && bgra[3] == 255;
	const linear = clearedBytes(device, "rgba8unorm", 4, 0.5, 0.0, 0.0, 1.0);
	const srgb = clearedBytes(device, "rgba8unorm-srgb", 4, 0.5, 0.0, 0.0, 1.0);
	const bgraSrgb = clearedBytes(device, "bgra8unorm-srgb", 4, 0.5, 0.0, 0.0, 1.0);
	assert linear[0] >= 127 && linear[0] <= 128;
	assert srgb[0] >= 187 && srgb[0] <= 189 && srgb[3] == 255;
	assert bgraSrgb[2] == srgb[0] && bgraSrgb[0] == 0;
	const uint = clearedBytes(device, "rgba8uint", 4, 7.0, 9.0, 0.0, 1.0);
	assert uint[0] == 7 && uint[1] == 9 && uint[2] == 0 && uint[3] == 1;
	const sint = clearedBytes(device, "rgba8sint", 4, -3.0, 5.0, 0.0, 1.0);
	assert sint[0] == 253 && sint[1] == 5;
	device.destroy();
}

test "16-bit, 32-bit and packed colour formats store their clear bit for bit" {
	const device = openDevice();
	const r16 = clearedBytes(device, "r16float", 2, 1.0, 0.0, 0.0, 1.0);
	assert r16[0] == 0x00 && r16[1] == 0x3C;
	const rg16 = clearedBytes(device, "rg16float", 4, 1.0, 2.0, 0.0, 1.0);
	assert rg16[1] == 0x3C && rg16[3] == 0x40;
	const rgba16 = clearedBytes(device, "rgba16float", 8, 1.0, 0.0, 0.0, 1.0);
	assert rgba16[1] == 0x3C && rgba16[7] == 0x3C;
	const rgba16uint = clearedBytes(device, "rgba16uint", 8, 1000.0, 0.0, 0.0, 1.0);
	assert rgba16uint[0] == 0xE8 && rgba16uint[1] == 0x03;
	const r32 = clearedBytes(device, "r32float", 4, 1.0, 0.0, 0.0, 1.0);
	assert r32[2] == 0x80 && r32[3] == 0x3F;
	const rg32 = clearedBytes(device, "rg32float", 8, 1.0, 2.0, 0.0, 1.0);
	assert rg32[3] == 0x3F && rg32[7] == 0x40;
	const rgba32 = clearedBytes(device, "rgba32float", 16, 1.0, 2.0, 0.0, 1.0);
	assert rgba32[3] == 0x3F && rgba32[7] == 0x40 && rgba32[15] == 0x3F;
	const r32uint = clearedBytes(device, "r32uint", 4, 70000.0, 0.0, 0.0, 1.0);
	assert r32uint[0] == 0x70 && r32uint[1] == 0x11 && r32uint[2] == 0x01;
	const packed = clearedBytes(device, "rgb10a2unorm", 4, 1.0, 0.0, 0.0, 1.0);
	assert packed[0] == 0xFF && packed[1] == 0x03 && packed[2] == 0x00 && packed[3] == 0xC0;
	const small = clearedBytes(device, "rg11b10ufloat", 4, 1.0, 0.0, 0.0, 1.0);
	assert small[0] == 0xC0 && small[1] == 0x03 && small[2] == 0x00;
	device.destroy();
}

test "depth16unorm, depth32float and depth24plus-stencil8 store their cleared depth" {
	const device = openDevice();
	const sixteen = clearedDepthBytes(device, "depth16unorm", 2, 1.0);
	assert sixteen[0] == 0xFF && sixteen[1] == 0xFF;
	const half16 = clearedDepthBytes(device, "depth16unorm", 2, 0.5);
	assert half16[1] >= 0x7F && half16[1] <= 0x80;
	const thirtyTwo = clearedDepthBytes(device, "depth32float", 4, 0.5);
	assert thirtyTwo[2] == 0x00 && thirtyTwo[3] == 0x3F;
	const combined = clearedDepthBytes(device, "depth24plus-stencil8", 4, 0.25);
	assert combined[2] == 0x80 && combined[3] == 0x3E;
	device.destroy();
}

test "a writeTexture of a 16-bit and a two-channel format reads back unchanged" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "rg8",
		size: { width: 4, height: 2, depthOrArrayLayers: 1 },
		format: "rg8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	const data: Vec<uint8> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
	device.queue.writeTexture({ texture: texture }, data, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 4, height: 2, depthOrArrayLayers: 1 });
	device.queue.submit(device.createCommandEncoder().finish());
	const back = readBytes(texture, 0, 0, 0, 4, 2, 2);
	for (let i = 0; i < 16; i++) { assert back[i] == data[i]; }
	const wide = device.createTexture({
		label: "rgba16",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "rgba16float",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	const halves: Vec<uint16> = [0x3C00, 0x4000, 0x4200, 0x4400, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
	device.queue.writeTexture({ texture: wide }, halves, { offset: 0, bytesPerRow: 16, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	device.queue.submit(device.createCommandEncoder().finish());
	const wideBack = readBytes(wide, 0, 0, 0, 2, 2, 8);
	assert wideBack[0] == 0x00 && wideBack[1] == 0x3C && wideBack[7] == 0x44 && wideBack[8] == 1 && wideBack[14] == 4;
	device.destroy();
}

test "a bind group entry offset selects the second uniform block" {
	const device = openDevice();
	const second = drawTriangleAt(device, 1, 0, 256);
	assert pixel(second, 32, 32) == GREEN;
	assert pixel(second, 0, 0) == BLUE;
	const first = drawTriangleAt(device, 1, 0, 0);
	assert pixel(first, 32, 32) == RED;
	device.destroy();
}

const UINT_FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 umain(Out in [[stage_in]], texture2d<uint> tex [[texture(0)]]) { uint4 t = tex.read(uint2(0, 0)); return float4(float3(t.rgb) / 255.0, 1.0); }\n";
const MULTISAMPLED_FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 mmain(Out in [[stage_in]], texture2d_ms<float> tex [[texture(0)]]) { return tex.read(uint2(0, 0), 0); }\n";

function clearedTarget(device: GPUDevice, format: GPUTextureFormat, sampleCount: int32, r: float64, g: float64, b: float64): GPUTextureView {
	const target = device.createTexture({
		label: "cleared",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: format,
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32),
		sampleCount: sampleCount,
	});
	const view = target.createView({ label: null });
	let descriptor = clearingPass(view, { id: 0 });
	descriptor.colorAttachments[0].clearValue = { r: r, g: g, b: b, a: 1.0 };
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	return view;
}

test "a shader reads an unsigned-integer texture and a multisampled texture through their reflected bindings" {
	const device = openDevice();
	const unsigned = sampledShader(device, UINT_FRAGMENT_MSL, "umain", textureBinding("uint", "2d", false), NO_BINDING);
	const integers = clearedTarget(device, "rgba8uint", 1, 0.0, 255.0, 0.0);
	assert sampleCentreWith(device, unsigned, integers, { id: 0 }) == GREEN;
	const swapped = clearedTarget(device, "rgba8uint", 1, 255.0, 0.0, 0.0);
	assert sampleCentreWith(device, unsigned, swapped, { id: 0 }) == RED;
	const multisampled = sampledShader(device, MULTISAMPLED_FRAGMENT_MSL, "mmain", textureBinding("float", "2d", true), NO_BINDING);
	const samples = clearedTarget(device, "rgba8unorm", 4, 0.0, 1.0, 0.0);
	assert sampleCentreWith(device, multisampled, samples, { id: 0 }) == GREEN;
	device.destroy();
}

const COLOURED_USAGE: int32 = (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_SRC as int32);
const READ_LOD1_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 lod1(Out in [[stage_in]], texture2d<float> tex [[texture(0)]]) { return tex.read(uint2(0, 0), 1); }\n";
const READ_LAYER1_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 layer1(Out in [[stage_in]], texture2d_array<float> tex [[texture(0)]]) { return tex.read(uint2(0, 0), 1); }\n";
const READ_FIRST_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 first(Out in [[stage_in]], texture2d<float> tex [[texture(0)]]) { return tex.read(uint2(0, 0), 0); }\n";
const READ_CUBE_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 faces(Out in [[stage_in]], texturecube<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) { return float4(tex.sample(smp, float3(1.0, 0.0, 0.0)).r, tex.sample(smp, float3(0.0, 1.0, 0.0)).g, tex.sample(smp, float3(0.0, 0.0, -1.0)).b, 1.0); }\n";
const READ_VOLUME_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 plane2(Out in [[stage_in]], texture3d<float> tex [[texture(0)]]) { return tex.read(uint3(0, 0, 2), 0); }\n";

function sizedTexture(device: GPUDevice, width: int32, height: int32, layers: int32, mips: int32, dimension: GPUTextureDimension): GPUTexture {
	return device.createTexture({
		label: "sized",
		size: { width: width, height: height, depthOrArrayLayers: layers },
		format: "rgba8unorm",
		usage: COLOURED_USAGE,
		sampleCount: 1,
		mipLevelCount: mips,
		dimension: dimension,
	});
}

function clearView(device: GPUDevice, view: GPUTextureView, r: float64, g: float64, b: float64, depthSlice: int32): void {
	let descriptor = clearingPass(view, { id: 0 });
	descriptor.colorAttachments[0].clearValue = { r: r, g: g, b: b, a: 1.0 };
	descriptor.colorAttachments[0].depthSlice = depthSlice;
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
}

function viewOf(texture: GPUTexture, dimension: GPUTextureViewDimension, baseMip: int32, mips: int32, baseLayer: int32, layers: int32): GPUTextureView {
	return texture.createView({ label: null, dimension: dimension, baseMipLevel: baseMip, mipLevelCount: mips, baseArrayLayer: baseLayer, arrayLayerCount: layers });
}

function firstTexel(bytes: Vec<uint8>): uint32 {
	return ((bytes[0] as uint32) << 24) | ((bytes[1] as uint32) << 16) | ((bytes[2] as uint32) << 8) | (bytes[3] as uint32);
}

test "each mip of a texture is a render attachment sized by its mip, and views select a mip range" {
	const device = openDevice();
	const texture = sizedTexture(device, 8, 8, 1, 4, "2d");
	clearView(device, viewOf(texture, "2d", 0, 1, 0, 1), 1.0, 0.0, 0.0, 0);
	clearView(device, viewOf(texture, "2d", 1, 1, 0, 1), 0.0, 1.0, 0.0, 0);
	clearView(device, viewOf(texture, "2d", 2, 1, 0, 1), 0.0, 0.0, 1.0, 0);
	assert firstTexel(readBytes(texture, 0, 0, 0, 8, 8, 4)) == RED;
	assert firstTexel(readBytes(texture, 1, 0, 0, 4, 4, 4)) == GREEN;
	assert firstTexel(readBytes(texture, 2, 0, 0, 2, 2, 4)) == BLUE;
	const subRange = sampledShader(device, READ_FIRST_MSL, "first", textureBinding("float", "2d", false), NO_BINDING);
	assert sampleCentreWith(device, subRange, viewOf(texture, "2d", 2, 1, 0, 1), { id: 0 }) == BLUE;
	assert sampleCentreWith(device, subRange, viewOf(texture, "2d", 1, 2, 0, 1), { id: 0 }) == GREEN;
	const lod = sampledShader(device, READ_LOD1_MSL, "lod1", textureBinding("float", "2d", false), NO_BINDING);
	assert sampleCentreWith(device, lod, viewOf(texture, "2d", 0, 4, 0, 1), { id: 0 }) == GREEN;
	device.destroy();
}

test "a draw into mip 1 covers that mip's whole extent and leaves mip 0 alone" {
	const device = openDevice();
	const texture = sizedTexture(device, 8, 8, 1, 2, "2d");
	clearView(device, viewOf(texture, "2d", 0, 1, 0, 1), 1.0, 0.0, 0.0, 0);
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, 1);
	const group = uniformGroupAt(device, pipeline, colourUniforms(device), 256);
	const vertices = vertexBuffer(device, 48);
	const quad: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(viewOf(texture, "2d", 1, 1, 0, 1), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const mip1 = readBytes(texture, 1, 0, 0, 4, 4, 4);
	for (let i = 0; i < 16; i++) { assert mip1[i * 4 + 1] == 255 && mip1[i * 4] == 0; }
	const mip0 = readBytes(texture, 0, 0, 0, 8, 8, 4);
	for (let i = 0; i < 64; i++) { assert mip0[i * 4] == 255 && mip0[i * 4 + 1] == 0; }
	device.destroy();
}

test "a sampler's LOD clamp and mip filter choose the mip a shader samples" {
	const device = openDevice();
	const texture = sizedTexture(device, 8, 8, 1, 4, "2d");
	clearView(device, viewOf(texture, "2d", 0, 1, 0, 1), 1.0, 0.0, 0.0, 0);
	clearView(device, viewOf(texture, "2d", 1, 1, 0, 1), 0.0, 1.0, 0.0, 0);
	clearView(device, viewOf(texture, "2d", 2, 1, 0, 1), 0.0, 0.0, 1.0, 0);
	const module = sampledShader(device, TEXTURED_FRAGMENT_MSL, "tmain", textureBinding("float", "2d", false), samplerBinding("filtering"));
	const whole = viewOf(texture, "2d", 0, 4, 0, 1);
	const atTwo = device.createSampler({ label: "lod2", magFilter: "nearest", minFilter: "nearest", mipmapFilter: "nearest", lodMinClamp: 2.0, lodMaxClamp: 2.0 });
	const atOne = device.createSampler({ label: "lod1", magFilter: "nearest", minFilter: "nearest", mipmapFilter: "nearest", lodMinClamp: 1.0, lodMaxClamp: 1.0 });
	const atZero = device.createSampler({ label: "lod0", magFilter: "nearest", minFilter: "nearest", mipmapFilter: "nearest", lodMinClamp: 0.0, lodMaxClamp: 0.0 });
	assert sampleCentreWith(device, module, whole, atTwo) == BLUE;
	assert sampleCentreWith(device, module, whole, atOne) == GREEN;
	assert sampleCentreWith(device, module, whole, atZero) == RED;
	device.destroy();
}

test "array layers are attachments and views select a layer or a range of layers" {
	const device = openDevice();
	const texture = sizedTexture(device, 4, 4, 3, 1, "2d");
	clearView(device, viewOf(texture, "2d", 0, 1, 0, 1), 1.0, 0.0, 0.0, 0);
	clearView(device, viewOf(texture, "2d", 0, 1, 1, 1), 0.0, 1.0, 0.0, 0);
	clearView(device, viewOf(texture, "2d", 0, 1, 2, 1), 0.0, 0.0, 1.0, 0);
	assert firstTexel(readBytes(texture, 0, 0, 0, 4, 4, 4)) == RED;
	assert firstTexel(readBytes(texture, 0, 1, 0, 4, 4, 4)) == GREEN;
	assert firstTexel(readBytes(texture, 0, 2, 0, 4, 4, 4)) == BLUE;
	const arrayShader = sampledShader(device, READ_LAYER1_MSL, "layer1", textureBinding("float", "2d-array", false), NO_BINDING);
	assert sampleCentreWith(device, arrayShader, viewOf(texture, "2d-array", 0, 1, 0, 3), { id: 0 }) == GREEN;
	assert sampleCentreWith(device, arrayShader, viewOf(texture, "2d-array", 0, 1, 1, 2), { id: 0 }) == BLUE;
	const single = sampledShader(device, READ_FIRST_MSL, "first", textureBinding("float", "2d", false), NO_BINDING);
	assert sampleCentreWith(device, single, viewOf(texture, "2d", 0, 1, 2, 1), { id: 0 }) == BLUE;
	device.destroy();
}

test "a cube view of six layers samples each face by direction" {
	const device = openDevice();
	const texture = sizedTexture(device, 4, 4, 6, 1, "2d");
	for (let face = 0; face < 6; face++) {
		clearView(device, viewOf(texture, "2d", 0, 1, face, 1), face == 0 ? 1.0 : 0.0, face == 2 ? 1.0 : 0.0, face == 5 ? 1.0 : 0.0, 0);
	}
	const module = sampledShader(device, READ_CUBE_MSL, "faces", textureBinding("float", "cube", false), samplerBinding("filtering"));
	const sampler = device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" });
	const cube = viewOf(texture, "cube", 0, 1, 0, 6);
	assert sampleCentreWith(device, module, cube, sampler) == 0xFFFFFFFF;
	const other = sizedTexture(device, 4, 4, 6, 1, "2d");
	for (let face = 0; face < 6; face++) { clearView(device, viewOf(other, "2d", 0, 1, face, 1), 0.0, 0.0, 0.0, 0); }
	clearView(device, viewOf(other, "2d", 0, 1, 2, 1), 0.0, 1.0, 0.0, 0);
	assert sampleCentreWith(device, module, viewOf(other, "cube", 0, 1, 0, 6), sampler) == 0x00FF00FF;
	device.destroy();
}

test "a 3d texture takes a render attachment at each depth slice and mip, and a shader reads a slice" {
	const device = openDevice();
	const texture = sizedTexture(device, 4, 4, 4, 3, "3d");
	clearView(device, viewOf(texture, "3d", 0, 1, 0, 0), 1.0, 0.0, 0.0, 0);
	clearView(device, viewOf(texture, "3d", 0, 1, 0, 0), 0.0, 1.0, 0.0, 1);
	clearView(device, viewOf(texture, "3d", 0, 1, 0, 0), 0.0, 0.0, 1.0, 2);
	assert firstTexel(readBytes(texture, 0, 0, 0, 4, 4, 4)) == RED;
	assert firstTexel(readBytes(texture, 0, 0, 1, 4, 4, 4)) == GREEN;
	assert firstTexel(readBytes(texture, 0, 0, 2, 4, 4, 4)) == BLUE;
	const shader = sampledShader(device, READ_VOLUME_MSL, "plane2", textureBinding("float", "3d", false), NO_BINDING);
	assert sampleCentreWith(device, shader, viewOf(texture, "3d", 0, 3, 0, 0), { id: 0 }) == BLUE;
	clearView(device, viewOf(texture, "3d", 1, 1, 0, 0), 1.0, 1.0, 0.0, 1);
	assert firstTexel(readBytes(texture, 1, 0, 1, 2, 2, 4)) == 0xFFFF00FF;
	assert firstTexel(readBytes(texture, 1, 0, 0, 2, 2, 4)) != 0xFFFF00FF;
	device.destroy();
}

test "a multisampled target resolves into a chosen mip, then into a chosen layer" {
	const device = openDevice();
	const mips = sizedTexture(device, 8, 8, 1, 2, "2d");
	clearView(device, viewOf(mips, "2d", 0, 1, 0, 1), 1.0, 0.0, 0.0, 0);
	const samples = device.createTexture({
		label: "samples",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32),
		sampleCount: 4,
	});
	let descriptor = clearingPass(samples.createView({ label: null }), viewOf(mips, "2d", 1, 1, 0, 1));
	descriptor.colorAttachments[0].clearValue = { r: 0.0, g: 1.0, b: 0.0, a: 1.0 };
	let encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	assert firstTexel(readBytes(mips, 1, 0, 0, 4, 4, 4)) == GREEN;
	assert firstTexel(readBytes(mips, 0, 0, 0, 8, 8, 4)) == RED;
	const layers = sizedTexture(device, 4, 4, 2, 1, "2d");
	clearView(device, viewOf(layers, "2d", 0, 1, 0, 1), 1.0, 0.0, 0.0, 0);
	descriptor = clearingPass(samples.createView({ label: null }), viewOf(layers, "2d", 0, 1, 1, 1));
	descriptor.colorAttachments[0].clearValue = { r: 0.0, g: 0.0, b: 1.0, a: 1.0 };
	encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	assert firstTexel(readBytes(layers, 0, 1, 0, 4, 4, 4)) == BLUE;
	assert firstTexel(readBytes(layers, 0, 0, 0, 4, 4, 4)) == RED;
	device.destroy();
}

test "a render pass begins on the swapchain view and draws into the native colour texture" {
	const device = openDevice();
	const colour = colourTarget(device, 1);
	const depth = device.createTexture({
		label: "depth",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "depth32float",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32),
	});
	const swapchain = getCurrentTexture({
		width: SIZE,
		height: SIZE,
		sampleCount: 1,
		renderView: nativeTexture(colour),
		resolveView: null,
		depthStencilView: nativeTexture(depth),
	});
	let descriptor = clearingPass(swapchain.createView({ label: null }), { id: 0 });
	descriptor.depthStencilAttachment = {
		view: getCurrentDepthTexture().createView({ label: null }),
		depthLoadOp: "clear",
		depthStoreOp: "store",
		depthClearValue: 1.0,
	};
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	assert firstTexel(readPixels(colour)) == BLUE;
	device.destroy();
}

const COPY_TEXTURE_USAGE: int32 = (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32);
const MAP_READ_USAGE: int32 = (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32);
const COPY_BUFFER_USAGE: int32 = (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32);

function copyTexture(device: GPUDevice, format: GPUTextureFormat, width: int32, height: int32, layers: int32, mips: int32, dimension: GPUTextureDimension): GPUTexture {
	return device.createTexture({
		label: "copy",
		size: { width: width, height: height, depthOrArrayLayers: layers },
		format: format,
		usage: COPY_TEXTURE_USAGE,
		sampleCount: 1,
		mipLevelCount: mips,
		dimension: dimension,
	});
}

function ramp(count: int32, first: int32): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(count);
	for (let i = 0; i < count; i++) { bytes[i] = ((first + i) & 255) as uint8; }
	return bytes;
}

function mappedRead(buffer: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	buffer.mapAsync(GPUMapMode.READ as int32, offset, size);
	const bytes = buffer.getMappedRange(offset, size);
	buffer.unmap();
	return bytes;
}

function same(actual: Vec<uint8>, expected: Vec<uint8>): boolean {
	if (actual.length != expected.length) { return false; }
	for (let i = 0; i < expected.length; i++) { if (actual[i] != expected[i]) { return false; } }
	return true;
}

function readTexels(device: GPUDevice, texture: GPUTexture, mip: int32, x: int32, y: int32, z: int32, width: int32, height: int32, bytesPerPixel: int32): Vec<uint8> {
	const staging = device.createBuffer({ label: "texels", size: 256 * (height as int64), usage: MAP_READ_USAGE });
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: texture, mipLevel: mip, origin: { x: x, y: y, z: z } },
		{ buffer: staging, offset: 0, bytesPerRow: 256, rowsPerImage: height },
		{ width: width, height: height, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const padded = mappedRead(staging, 0, 256 * (height as int64));
	let tight: Vec<uint8> = new Array(width * height * bytesPerPixel);
	for (let row = 0; row < height; row++) {
		for (let i = 0; i < width * bytesPerPixel; i++) { tight[row * width * bytesPerPixel + i] = padded[row * 256 + i]; }
	}
	staging.destroy();
	return tight;
}

function fill(count: int32, value: uint8): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(count);
	for (let i = 0; i < count; i++) { bytes[i] = value; }
	return bytes;
}

function writeWhole(device: GPUDevice, texture: GPUTexture, mip: int32, layer: int32, width: int32, height: int32, bytesPerPixel: int32, data: Vec<uint8>): void {
	device.queue.writeTexture(
		{ texture: texture, mipLevel: mip, origin: { x: 0, y: 0, z: layer } },
		data,
		{ offset: 0, bytesPerRow: width * bytesPerPixel, rowsPerImage: height },
		{ width: width, height: height, depthOrArrayLayers: 1 },
	);
}

test "copyBufferToBuffer moves a range into a MAP_READ buffer at an offset, and a later writeBuffer lands after the copy" {
	const device = openDevice();
	const source = device.createBuffer({ label: "source", size: 64, usage: COPY_BUFFER_USAGE });
	device.queue.writeBuffer(source, 0, ramp(64, 0));
	const middle = device.createBuffer({ label: "middle", size: 64, usage: COPY_BUFFER_USAGE });
	const read = device.createBuffer({ label: "read", size: 64, usage: MAP_READ_USAGE });
	let encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(source, 16, read, 8, 16);
	encoder.copyBufferToBuffer(source, 0, middle, 0, 64);
	device.queue.submit(encoder.finish());
	assert same(mappedRead(read, 8, 16), ramp(16, 16));
	device.queue.writeBuffer(middle, 4, fill(4, 200));
	encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(middle, 0, read, 0, 8);
	device.queue.submit(encoder.finish());
	const patched = mappedRead(read, 0, 8);
	assert patched[3] == 3 && patched[4] == 200 && patched[7] == 200;
	device.destroy();
}

test "a MAP_WRITE buffer takes mapped bytes and a MAP_READ buffer gives a mapped sub-range back" {
	const device = openDevice();
	const upload = device.createBuffer({ label: "upload", size: 32, usage: (GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32) });
	upload.mapAsync(GPUMapMode.WRITE as int32, 0, 0);
	upload.writeMappedRange(8, ramp(8, 100));
	upload.unmap();
	const read = device.createBuffer({ label: "read", size: 32, usage: MAP_READ_USAGE });
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(upload, 0, read, 0, 32);
	device.queue.submit(encoder.finish());
	assert same(mappedRead(read, 8, 8), ramp(8, 100));
	assert same(mappedRead(read, 16, 8), fill(8, 0));
	upload.mapAsync(GPUMapMode.WRITE as int32, 0, 8);
	upload.writeMappedRange(0, ramp(8, 50));
	upload.unmap();
	const second = device.createCommandEncoder();
	second.copyBufferToBuffer(upload, 0, read, 0, 16);
	device.queue.submit(second.finish());
	assert same(mappedRead(read, 0, 8), ramp(8, 50));
	assert same(mappedRead(read, 8, 8), ramp(8, 100));
	device.destroy();
}

test "copyTextureToBuffer reads a whole rgba8 texture and an unaligned sub-rectangle of an r8 one" {
	const device = openDevice();
	const colour = copyTexture(device, "rgba8unorm", 4, 4, 1, 1, "2d");
	writeWhole(device, colour, 0, 0, 4, 4, 4, ramp(64, 0));
	assert same(readTexels(device, colour, 0, 0, 0, 0, 4, 4, 4), ramp(64, 0));
	const grey = copyTexture(device, "r8unorm", 8, 8, 1, 1, "2d");
	writeWhole(device, grey, 0, 0, 8, 8, 1, ramp(64, 0));
	const rect = readTexels(device, grey, 0, 3, 2, 0, 3, 2, 1);
	assert same(rect, [19, 20, 21, 27, 28, 29] as Vec<uint8>);
	device.destroy();
}

test "copyBufferToTexture fills one mip, one array layer and one 3d slice, each read back apart from its neighbours" {
	const device = openDevice();
	const source = device.createBuffer({ label: "source", size: 4096, usage: COPY_BUFFER_USAGE });
	device.queue.writeBuffer(source, 0, ramp(2048, 1));
	const mips = copyTexture(device, "r8unorm", 8, 8, 1, 3, "2d");
	let encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture({ buffer: source, offset: 0, bytesPerRow: 256, rowsPerImage: 0 }, { texture: mips, mipLevel: 1 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.submit(encoder.finish());
	assert same(readTexels(device, mips, 1, 0, 0, 0, 4, 4, 1), [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4] as Vec<uint8>);
	assert readTexels(device, mips, 0, 0, 0, 0, 4, 4, 1)[0] == 0;
	const layers = copyTexture(device, "r8unorm", 4, 4, 3, 1, "2d");
	encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture({ buffer: source, offset: 4, bytesPerRow: 256, rowsPerImage: 4 }, { texture: layers, origin: { x: 0, y: 0, z: 1 } }, { width: 4, height: 4, depthOrArrayLayers: 2 });
	device.queue.submit(encoder.finish());
	assert readTexels(device, layers, 0, 0, 0, 0, 1, 1, 1)[0] == 0;
	assert readTexels(device, layers, 0, 0, 0, 1, 1, 1, 1)[0] == 5;
	assert readTexels(device, layers, 0, 3, 3, 2, 1, 1, 1)[0] == 8;
	const volume = copyTexture(device, "r8unorm", 4, 4, 4, 1, "3d");
	const deep = device.createBuffer({ label: "deep", size: 4096, usage: COPY_BUFFER_USAGE });
	device.queue.writeBuffer(deep, 0, fill(4096, 7));
	encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture({ buffer: deep, offset: 0, bytesPerRow: 256, rowsPerImage: 4 }, { texture: volume, origin: { x: 0, y: 0, z: 2 } }, { width: 4, height: 4, depthOrArrayLayers: 2 });
	device.queue.submit(encoder.finish());
	assert readTexels(device, volume, 0, 0, 0, 1, 1, 1, 1)[0] == 0;
	assert readTexels(device, volume, 0, 0, 0, 2, 1, 1, 1)[0] == 7;
	assert readTexels(device, volume, 0, 3, 3, 3, 1, 1, 1)[0] == 7;
	device.destroy();
}

function flush(device: GPUDevice): void { device.queue.submit(device.createCommandEncoder().finish()); }

test "copyTextureToTexture copies a layer onto another layer, a mip onto a texture, and a 3d slice onto a slice" {
	const device = openDevice();
	const layers = copyTexture(device, "rgba8unorm", 4, 4, 3, 1, "2d");
	writeWhole(device, layers, 0, 1, 4, 4, 4, ramp(64, 9));
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToTexture({ texture: layers, origin: { x: 1, y: 1, z: 1 } }, { texture: layers, origin: { x: 0, y: 2, z: 2 } }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	device.queue.submit(encoder.finish());
	assert same(readTexels(device, layers, 0, 0, 2, 2, 2, 2, 4), [29, 30, 31, 32, 33, 34, 35, 36, 45, 46, 47, 48, 49, 50, 51, 52] as Vec<uint8>);
	assert readTexels(device, layers, 0, 0, 0, 2, 1, 1, 4)[0] == 0;
	const mips = copyTexture(device, "r8unorm", 8, 8, 1, 2, "2d");
	writeWhole(device, mips, 1, 0, 4, 4, 1, ramp(16, 40));
	const flat = copyTexture(device, "r8unorm", 4, 4, 1, 1, "2d");
	const second = device.createCommandEncoder();
	second.copyTextureToTexture({ texture: mips, mipLevel: 1 }, { texture: flat }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.submit(second.finish());
	assert same(readTexels(device, flat, 0, 0, 0, 0, 4, 4, 1), ramp(16, 40));
	const volume = copyTexture(device, "r8unorm", 4, 4, 4, 1, "3d");
	const other = copyTexture(device, "r8unorm", 4, 4, 4, 1, "3d");
	const deep = device.createBuffer({ label: "deep", size: 4096, usage: COPY_BUFFER_USAGE });
	device.queue.writeBuffer(deep, 0, fill(4096, 9));
	const third = device.createCommandEncoder();
	third.copyBufferToTexture({ buffer: deep, offset: 0, bytesPerRow: 256, rowsPerImage: 4 }, { texture: volume, origin: { x: 0, y: 0, z: 1 } }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	third.copyTextureToTexture({ texture: volume, origin: { x: 0, y: 0, z: 1 } }, { texture: other, origin: { x: 0, y: 0, z: 3 } }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.submit(third.finish());
	assert readTexels(device, other, 0, 2, 2, 3, 1, 1, 1)[0] == 9;
	assert readTexels(device, other, 0, 2, 2, 1, 1, 1, 1)[0] == 0;
	device.destroy();
}

test "a depth16unorm texture takes a buffer copy and gives it back, and a depth32float clear copies out" {
	const device = openDevice();
	const depth16 = device.createTexture({
		label: "depth16",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "depth16unorm",
		usage: COPY_TEXTURE_USAGE,
	});
	const source = device.createBuffer({ label: "source", size: 1024, usage: COPY_BUFFER_USAGE });
	device.queue.writeBuffer(source, 0, ramp(1024, 3));
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture({ buffer: source, offset: 0, bytesPerRow: 256, rowsPerImage: 4 }, { texture: depth16 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.submit(encoder.finish());
	const row: Vec<uint8> = [3, 4, 5, 6, 7, 8, 9, 10];
	const back = readTexels(device, depth16, 0, 0, 0, 0, 4, 4, 2);
	for (let r = 0; r < 4; r++) { for (let j = 0; j < 8; j++) { assert back[r * 8 + j] == row[j]; } }
	const target = device.createTexture({
		label: "depth32",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "depth32float",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
	});
	let descriptor: GPURenderPassDescriptor = { label: "clear depth" };
	descriptor.depthStencilAttachment = { view: target.createView({ label: null }), depthClearValue: 0.5, depthLoadOp: "clear", depthStoreOp: "store" };
	const second = device.createCommandEncoder();
	second.beginRenderPass(descriptor).end();
	device.queue.submit(second.finish());
	const clear = readTexels(device, target, 0, 0, 0, 0, 2, 2, 4);
	assert clear[3] == 0x3F && clear[2] == 0 && clear[1] == 0 && clear[0] == 0 && clear[15] == 0x3F;
	device.destroy();
}

test "writeTexture writes a sub-rectangle in place over a whole write of the same frame, and into one mip, layer or 3d slice" {
	const device = openDevice();
	const grey = copyTexture(device, "r8unorm", 8, 8, 1, 1, "2d");
	writeWhole(device, grey, 0, 0, 8, 8, 1, fill(64, 0x11));
	device.queue.writeTexture({ texture: grey, origin: { x: 3, y: 2, z: 0 } }, fill(16, 0x22), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	flush(device);
	let pixels = readBytes(grey, 0, 0, 0, 8, 8, 1);
	assert pixels[2 * 8 + 3] == 0x22 && pixels[3 * 8 + 4] == 0x22 && pixels[2 * 8 + 2] == 0x11 && pixels[2 * 8 + 5] == 0x11 && pixels[4 * 8 + 3] == 0x11;
	device.queue.writeTexture({ texture: grey, origin: { x: 7, y: 7, z: 0 } }, fill(1, 0x33), { offset: 0, bytesPerRow: 1, rowsPerImage: 1 }, { width: 1, height: 1, depthOrArrayLayers: 1 });
	flush(device);
	pixels = readBytes(grey, 0, 0, 0, 8, 8, 1);
	assert pixels[63] == 0x33 && pixels[3 * 8 + 4] == 0x22 && pixels[0] == 0x11;
	writeWhole(device, grey, 0, 0, 8, 8, 1, fill(64, 0x44));
	writeWhole(device, grey, 0, 0, 8, 8, 1, fill(64, 0x55));
	flush(device);
	assert readBytes(grey, 0, 0, 0, 8, 8, 1)[27] == 0x55;
	const mips = copyTexture(device, "r8unorm", 8, 8, 1, 3, "2d");
	device.queue.writeTexture({ texture: mips, mipLevel: 1, origin: { x: 1, y: 1, z: 0 } }, fill(4, 0x66), { offset: 0, bytesPerRow: 2, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	flush(device);
	pixels = readBytes(mips, 1, 0, 0, 4, 4, 1);
	assert pixels[1 * 4 + 1] == 0x66 && pixels[2 * 4 + 2] == 0x66 && pixels[0] == 0 && pixels[3 * 4 + 3] == 0;
	assert readBytes(mips, 0, 0, 0, 8, 8, 1)[9] == 0;
	const layers = copyTexture(device, "rgba8unorm", 4, 4, 2, 1, "2d");
	device.queue.writeTexture({ texture: layers, origin: { x: 1, y: 1, z: 1 } }, fill(16, 0x77), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	flush(device);
	assert readBytes(layers, 0, 1, 0, 4, 4, 4)[(1 * 4 + 1) * 4] == 0x77;
	assert readBytes(layers, 0, 0, 0, 4, 4, 4)[(1 * 4 + 1) * 4] == 0;
	const volume = copyTexture(device, "r8unorm", 4, 4, 4, 1, "3d");
	device.queue.writeTexture({ texture: volume, origin: { x: 0, y: 0, z: 1 } }, fill(32, 0x88), { offset: 0, bytesPerRow: 4, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 2 });
	flush(device);
	assert readBytes(volume, 0, 0, 1, 4, 4, 1)[5] == 0x88 && readBytes(volume, 0, 0, 2, 4, 4, 1)[5] == 0x88;
	assert readBytes(volume, 0, 0, 0, 4, 4, 1)[5] == 0 && readBytes(volume, 0, 0, 3, 4, 4, 1)[5] == 0;
	device.destroy();
}

test "an attachment texture that is also COPY_DST takes writeTexture and keeps it after a partial write" {
	const device = openDevice();
	const target = device.createTexture({
		label: "target",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32),
	});
	writeWhole(device, target, 0, 0, 4, 4, 4, fill(64, 0x21));
	device.queue.writeTexture({ texture: target, origin: { x: 2, y: 2, z: 0 } }, fill(16, 0x42), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	flush(device);
	const pixels = readBytes(target, 0, 0, 0, 4, 4, 4);
	assert pixels[0] == 0x21 && pixels[(2 * 4 + 2) * 4] == 0x42 && pixels[(3 * 4 + 3) * 4 + 3] == 0x42;
	device.destroy();
}

test "the swapchain texture copies out after its pass, resolved when it is multisampled" {
	const device = openDevice();
	const colour = colourTarget(device, 1);
	const depth = device.createTexture({
		label: "depth",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "depth32float",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32),
	});
	const direct = getCurrentTexture({ width: SIZE, height: SIZE, sampleCount: 1, renderView: nativeTexture(colour), resolveView: null, depthStencilView: nativeTexture(depth) });
	let encoder = device.createCommandEncoder();
	encoder.beginRenderPass(clearingPass(direct.createView({ label: null }), { id: 0 })).end();
	const staging = device.createBuffer({ label: "staging", size: 256 * 8, usage: MAP_READ_USAGE });
	encoder.copyTextureToBuffer({ texture: direct, origin: { x: 8, y: 8, z: 0 } }, { buffer: staging, offset: 0, bytesPerRow: 256, rowsPerImage: 8 }, { width: 8, height: 8, depthOrArrayLayers: 1 });
	device.queue.submit(encoder.finish());
	const direct_ = mappedRead(staging, 0, 256 * 8);
	assert direct_[0] == 0 && direct_[2] == 255 && direct_[3] == 255 && direct_[7 * 256 + 30] == 255;
	const samples = colourTarget(device, 4);
	const resolved = colourTarget(device, 1);
	const multi = getCurrentTexture({ width: SIZE, height: SIZE, sampleCount: 4, renderView: nativeTexture(samples), resolveView: nativeTexture(resolved), depthStencilView: nativeTexture(depth) });
	encoder = device.createCommandEncoder();
	let descriptor = clearingPass(multi.createView({ label: null }), { id: 0 });
	descriptor.colorAttachments[0].clearValue = { r: 1.0, g: 0.0, b: 0.0, a: 1.0 };
	encoder.beginRenderPass(descriptor).end();
	encoder.copyTextureToBuffer({ texture: multi }, { buffer: staging, offset: 0, bytesPerRow: 256, rowsPerImage: 8 }, { width: 8, height: 8, depthOrArrayLayers: 1 });
	device.queue.submit(encoder.finish());
	const back = mappedRead(staging, 0, 256 * 8);
	assert back[0] == 255 && back[1] == 0 && back[3] == 255 && back[7 * 256 + 28] == 255;
	device.destroy();
}

test "a mapAsync that would wait behind the frame's open command buffer stops by name instead of hanging" {
	const run = exec("timeout 120 msc run src/test/metalReadbackHazardProbe.ms 2>&1");
	if (run.ok) { assert false; }
	if (!run.ok) {
		assert run.error.output.includes("which is not committed");
		assert !run.error.output.includes("probe: mapAsync returned");
	}
}

const DOUBLE_MSL = "#include <metal_stdlib>\nusing namespace metal;\nkernel void _main(device uint* data [[buffer(0)]], uint id [[thread_position_in_grid]]) { data[id] = data[id] * 2; }\n";
const HALVE_MSL = "#include <metal_stdlib>\nusing namespace metal;\nkernel void halve(const device float* source [[buffer(0)]], device float* result [[buffer(1)]], uint id [[thread_position_in_grid]]) { result[id] = source[id] * 0.5; }\n";
const FILL_MSL = "#include <metal_stdlib>\nusing namespace metal;\nkernel void _main(texture2d<uint, access::write> image [[texture(0)]], uint2 id [[thread_position_in_grid]]) { image.write(uint4(id.x + id.y * 10), id); }\n";
const INCREMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nkernel void _main(texture2d<uint, access::read_write> image [[texture(0)]], uint2 id [[thread_position_in_grid]]) { image.write(image.read(id) + 1, id); }\n";
const PAINT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nkernel void _main(texture2d<float, access::write> image [[texture(0)]], uint2 id [[thread_position_in_grid]]) { image.write(float4(1.0, 0.0, 0.0, 1.0), id); }\n";
const COLOURS_MSL = "#include <metal_stdlib>\nusing namespace metal;\nkernel void _main(device float4* colours [[buffer(0)]]) { colours[0] = float4(0.0, 1.0, 0.0, 1.0); }\n";
const STORAGE_FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nfragment float4 smain(const device float4* colours [[buffer(0)]]) { return colours[0]; }\n";
const SAMPLE_PAINTED_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nfragment float4 pmain(Out in [[stage_in]], texture2d<float> tex [[texture(0)]]) { return tex.read(uint2(1, 1), 0); }\n";

const STORAGE_BUFFER_USAGE: int32 = (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32) | (GPUBufferUsage.COPY_SRC as int32);

function computeDescriptor(code: string, entry: string, x: int32, y: int32): GPUShaderModuleDescriptor {
	let descriptor: GPUShaderModuleDescriptor = { label: "compute", computeCode: code, computeEntryPoint: entry };
	descriptor.workgroupSize = [x, y, 1];
	return descriptor;
}

function storageBufferModule(device: GPUDevice, code: string, entry: string, workgroup: int32): GPUShaderModule {
	let descriptor = computeDescriptor(code, entry, workgroup, 1);
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-buffer", stage: "compute", bufferType: "storage", nativeSlot: 0 };
	return device.createShaderModule(descriptor);
}

function storageTextureModule(device: GPUDevice, code: string, access: GPUStorageTextureAccess, format: GPUTextureFormat): GPUShaderModule {
	let descriptor = computeDescriptor(code, "", 4, 4);
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-texture", stage: "compute", storageAccess: access, storageFormat: format, nativeSlot: 0 };
	return device.createShaderModule(descriptor);
}

function computeGroup(device: GPUDevice, pipeline: GPUComputePipeline, first: GPUBindGroupEntry, second: GPUBindGroupEntry): GPUBindGroup {
	let descriptor: GPUBindGroupDescriptor = { label: "storage", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = first;
	descriptor.entries[1] = second;
	return device.createBindGroup(descriptor);
}

function noEntry(): GPUBindGroupEntry { return { binding: 7 }; }

function dispatchGroups(device: GPUDevice, encoder: GPUCommandEncoder, pipeline: GPUComputePipeline, group: GPUBindGroup, x: int32): void {
	const noOffsets: Vec<uint32> = [];
	const pass = encoder.beginComputePass({ label: null });
	pass.setPipeline(pipeline);
	pass.setBindGroup(1, group, noOffsets);
	pass.dispatchWorkgroups(x, 1, 1);
	pass.end();
}

test "a compute pass doubles a storage buffer, then again through an indirect dispatch read at an offset" {
	const device = openDevice();
	const module = storageBufferModule(device, DOUBLE_MSL, "", 4);
	const storage = device.createBuffer({ label: "storage", size: 16, usage: STORAGE_BUFFER_USAGE });
	device.queue.writeBuffer(storage, 0, [1, 2, 3, 40000] as Vec<uint32>);
	const pipeline = device.createComputePipeline({ label: "double", compute: { module: module, entryPoint: "" } });
	const group = computeGroup(device, pipeline, { binding: 0, buffer: storage }, noEntry());
	const read = device.createBuffer({ label: "read", size: 16, usage: MAP_READ_USAGE });
	let encoder = device.createCommandEncoder();
	dispatchGroups(device, encoder, pipeline, group, 1);
	encoder.copyBufferToBuffer(storage, 0, read, 0, 16);
	device.queue.submit(encoder.finish());
	let bytes = mappedRead(read, 0, 16);
	assert bytes[0] == 2 && bytes[4] == 4 && bytes[8] == 6 && bytes[12] == 0x80 && bytes[13] == 0x38;
	const wide = storageBufferModule(device, DOUBLE_MSL, "", 2);
	const widePipeline = device.createComputePipeline({ label: "wide", compute: { module: wide, entryPoint: "" } });
	const wideGroup = computeGroup(device, widePipeline, { binding: 0, buffer: storage }, noEntry());
	const arguments = device.createBuffer({ label: "arguments", size: 32, usage: (GPUBufferUsage.INDIRECT as int32) | (GPUBufferUsage.COPY_DST as int32) });
	device.queue.writeBuffer(arguments, 16, [2, 1, 1] as Vec<uint32>);
	encoder = device.createCommandEncoder();
	const noOffsets: Vec<uint32> = [];
	const pass = encoder.beginComputePass({ label: null });
	pass.setPipeline(widePipeline);
	pass.setBindGroup(1, wideGroup, noOffsets);
	pass.dispatchWorkgroupsIndirect(arguments, 16);
	pass.end();
	encoder.copyBufferToBuffer(storage, 0, read, 0, 16);
	device.queue.submit(encoder.finish());
	bytes = mappedRead(read, 0, 16);
	assert bytes[0] == 4 && bytes[4] == 8 && bytes[8] == 12 && bytes[12] == 0x00 && bytes[13] == 0x71;
	device.destroy();
}

test "a compute pass reads a read-only float buffer and writes a read-write one at a bound offset" {
	const device = openDevice();
	let descriptor = computeDescriptor(HALVE_MSL, "halve", 4, 1);
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-buffer", stage: "compute", bufferType: "read-only-storage", nativeSlot: 0 };
	descriptor.bindings[1] = { group: 1, binding: 1, kind: "storage-buffer", stage: "compute", bufferType: "storage", nativeSlot: 1 };
	const module = device.createShaderModule(descriptor);
	const source = device.createBuffer({ label: "source", size: 16, usage: STORAGE_BUFFER_USAGE });
	device.queue.writeBuffer(source, 0, [2.0, 4.0, 6.0, 8.0] as Vec<float32>);
	const result = device.createBuffer({ label: "result", size: 64, usage: STORAGE_BUFFER_USAGE });
	const pipeline = device.createComputePipeline({ label: "halve", compute: { module: module, entryPoint: "halve" } });
	const group = computeGroup(device, pipeline, { binding: 0, buffer: source }, { binding: 1, buffer: result, offset: 32, size: 16 });
	const read = device.createBuffer({ label: "read", size: 64, usage: MAP_READ_USAGE });
	const encoder = device.createCommandEncoder();
	dispatchGroups(device, encoder, pipeline, group, 1);
	encoder.copyBufferToBuffer(result, 0, read, 0, 64);
	device.queue.submit(encoder.finish());
	const bytes = mappedRead(read, 0, 64);
	assert bytes[3] == 0 && bytes[31] == 0;
	assert bytes[34] == 0x80 && bytes[35] == 0x3F && bytes[39] == 0x40 && bytes[42] == 0x40 && bytes[43] == 0x40 && bytes[46] == 0x80 && bytes[47] == 0x40;
	device.destroy();
}

function storageImage(device: GPUDevice, format: GPUTextureFormat, usage: int32): GPUTexture {
	return device.createTexture({
		label: "image",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: format,
		usage: usage,
		sampleCount: 1,
	});
}

function dispatchImage(device: GPUDevice, module: GPUShaderModule, view: GPUTextureView): void {
	const pipeline = device.createComputePipeline({ label: "image", compute: { module: module, entryPoint: "" } });
	const group = computeGroup(device, pipeline, { binding: 0, textureView: view }, noEntry());
	const encoder = device.createCommandEncoder();
	dispatchGroups(device, encoder, pipeline, group, 1);
	device.queue.submit(encoder.finish());
}

const IMAGE_USAGE: int32 = (GPUTextureUsage.STORAGE_BINDING as int32) | (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32);

test "a compute pass writes a storage texture that copies back, and a read-write one adds to bytes a writeTexture put there" {
	const device = openDevice();
	const image = storageImage(device, "r32uint", IMAGE_USAGE);
	dispatchImage(device, storageTextureModule(device, FILL_MSL, "write-only", "r32uint"), image.createView({ label: null }));
	let texels = readTexels(device, image, 0, 0, 0, 0, 4, 4, 4);
	assert texels[0] == 0 && texels[4] == 1 && texels[12] == 3 && texels[16] == 10 && texels[60] == 33;
	writeWhole(device, image, 0, 0, 4, 4, 4, ramp(64, 100));
	dispatchImage(device, storageTextureModule(device, INCREMENT_MSL, "read-write", "r32uint"), image.createView({ label: null }));
	texels = readTexels(device, image, 0, 0, 0, 0, 4, 4, 4);
	assert texels[0] == 101 && texels[4] == 105 && texels[63] == 163;
	device.destroy();
}

test "a storage texture painted by compute is sampled by a later render pass of the same encoder" {
	const device = openDevice();
	const painted = storageImage(device, "rgba8unorm", (GPUTextureUsage.STORAGE_BINDING as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32));
	const module = storageTextureModule(device, PAINT_MSL, "write-only", "rgba8unorm");
	const pipeline = device.createComputePipeline({ label: "paint", compute: { module: module, entryPoint: "" } });
	const group = computeGroup(device, pipeline, { binding: 0, textureView: painted.createView({ label: null }) }, noEntry());
	const renderPipeline = flatPipeline(device, sampledShader(device, SAMPLE_PAINTED_MSL, "pmain", textureBinding("float", "2d", false), NO_BINDING), 1);
	let resources: GPUBindGroupDescriptor = { label: "resources", layout: renderPipeline.getBindGroupLayout(1) };
	resources.entries[0] = { binding: 0, textureView: painted.createView({ label: null }) };
	const vertices = vertexBuffer(device, 48);
	device.queue.writeBuffer(vertices, 0, [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0, -1.0] as Vec<float32>);
	const target = colourTarget(device, 1);
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	dispatchGroups(device, encoder, pipeline, group, 1);
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(renderPipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(1, device.createBindGroup(resources), noOffsets);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	assert pixel(readPixels(target), 32, 32) == RED;
	device.destroy();
}

test "a render pass reads the read-only storage buffer a compute pass of the same encoder wrote" {
	const device = openDevice();
	const module = storageBufferModule(device, COLOURS_MSL, "", 1);
	const colours = device.createBuffer({ label: "colours", size: 16, usage: STORAGE_BUFFER_USAGE });
	const computePipeline = device.createComputePipeline({ label: "colours", compute: { module: module, entryPoint: "" } });
	const computeBinding = computeGroup(device, computePipeline, { binding: 0, buffer: colours }, noEntry());
	let descriptor: GPUShaderModuleDescriptor = {
		label: "storage fragment",
		vertexCode: VERTEX_MSL,
		vertexEntryPoint: "vmain",
		fragmentCode: STORAGE_FRAGMENT_MSL,
		fragmentEntryPoint: "smain",
	};
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-buffer", stage: "fragment", bufferType: "read-only-storage", nativeSlot: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const renderPipeline = flatPipeline(device, device.createShaderModule(descriptor), 1);
	let render: GPUBindGroupDescriptor = { label: "colours", layout: renderPipeline.getBindGroupLayout(1) };
	render.entries[0] = { binding: 0, buffer: colours };
	const vertices = vertexBuffer(device, 24);
	device.queue.writeBuffer(vertices, 0, [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5] as Vec<float32>);
	const target = colourTarget(device, 1);
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	dispatchGroups(device, encoder, computePipeline, computeBinding, 1);
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(renderPipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(1, device.createBindGroup(render), noOffsets);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == GREEN;
	device.destroy();
}

test "the limits are the constants the backend enforces, and the features say what the device can do" {
	const device = openDevice();
	const limits = device.limits();
	assert limits.maxTextureDimension1D == 16384 && limits.maxTextureDimension2D == 16384 && limits.maxTextureDimension3D == 2048;
	assert limits.maxTextureArrayLayers == 2048 && limits.maxBindGroups == 2;
	assert limits.maxSampledTexturesPerShaderStage > 0 && limits.maxSamplersPerShaderStage > 0;
	assert limits.maxStorageBuffersPerShaderStage > 0 && limits.maxStorageTexturesPerShaderStage > 0;
	assert limits.maxUniformBuffersPerShaderStage > 0 && limits.maxUniformBufferBindingSize >= 65536;
	assert limits.maxStorageBufferBindingSize >= 65536 && limits.maxVertexBuffers == 2 && limits.maxVertexAttributes == 16;
	assert limits.maxColorAttachments == 4 && limits.maxComputeWorkgroupSizeX >= 256 && limits.maxComputeWorkgroupSizeY >= 256;
	assert limits.maxComputeWorkgroupSizeZ >= 64 && limits.maxComputeInvocationsPerWorkgroup >= 256;
	assert limits.maxComputeWorkgroupsPerDimension == 65535;
	assert limits.minUniformBufferOffsetAlignment == 256 && limits.minStorageBufferOffsetAlignment == 32;
	const widest = device.createTexture({
		label: "widest",
		size: { width: limits.maxTextureDimension2D, height: 1, depthOrArrayLayers: 1 },
		format: "r8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
	});
	assert widest.width() == limits.maxTextureDimension2D;
	const widePipeline = device.createComputePipeline({ label: "widest", compute: { module: storageBufferModule(device, DOUBLE_MSL, "", limits.maxComputeInvocationsPerWorkgroup), entryPoint: "" } });
	assert widePipeline.id != 0;
	const features = device.features();
	assert features.has("float32-blendable") && features.has("float32-filterable") && features.has("rg11b10ufloat-renderable");
	assert !features.has("texture-compression-bc") && !features.has("depth32float-stencil8") && !features.has("shader-f16");
	device.destroy();
}

test "a label reaches the native object and debug groups balance on the encoder, a render pass and a compute pass" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "labelled texture",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
	});
	let name: Vec<uint8> = new Array(64);
	const length = metalLabel(nativeTexture(texture), name[0], 64);
	assert length == 16;
	assert name[0] == 108 && name[9] == 116 && name[15] == 101;
	const unlabelled = device.createTexture({
		label: null,
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
	});
	assert metalLabel(nativeTexture(unlabelled), name[0], 64) == 0;
	const module = storageBufferModule(device, DOUBLE_MSL, "", 4);
	const pipeline = device.createComputePipeline({ label: "grouped", compute: { module: module, entryPoint: "" } });
	const storage = device.createBuffer({ label: "storage", size: 16, usage: STORAGE_BUFFER_USAGE });
	const group = computeGroup(device, pipeline, { binding: 0, buffer: storage }, noEntry());
	const target = colourTarget(device, 1);
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	encoder.pushDebugGroup("frame");
	encoder.insertDebugMarker("before");
	const render = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	render.pushDebugGroup("inside");
	render.insertDebugMarker("marker");
	render.popDebugGroup();
	render.end();
	const compute = encoder.beginComputePass({ label: "compute" });
	compute.pushDebugGroup("compute group");
	compute.setPipeline(pipeline);
	compute.setBindGroup(1, group, noOffsets);
	compute.insertDebugMarker("compute marker");
	compute.dispatchWorkgroups(1, 1, 1);
	compute.popDebugGroup();
	compute.end();
	encoder.popDebugGroup();
	device.queue.submit(encoder.finish());
	assert pixel(readPixels(target), 0, 0) == BLUE;
	device.destroy();
}

function resolveBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "resolved",
		size: size,
		usage: (GPUBufferUsage.QUERY_RESOLVE as int32) | (GPUBufferUsage.COPY_SRC as int32),
	});
}

function readCounters(device: GPUDevice, resolved: GPUBuffer, count: int32): Vec<uint64> {
	const read = device.createBuffer({ label: "counters", size: (count as int64) * 8, usage: MAP_READ_USAGE });
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(resolved, 0, read, 0, (count as int64) * 8);
	device.queue.submit(encoder.finish());
	const bytes = mappedRead(read, 0, (count as int64) * 8);
	let values: Vec<uint64> = new Array(count);
	for (let i = 0; i < count; i++) {
		let value: uint64 = 0;
		for (let b = 7; b >= 0; b--) { value = (value << 8) | (bytes[i * 8 + b] as uint64); }
		values[i] = value;
	}
	return values;
}

function drawTriangleIn(device: GPUDevice, pipeline: GPURenderPipeline, pass: GPURenderPassEncoder): void {
	const uniforms = colourUniforms(device);
	const vertices = vertexBuffer(device, 24);
	device.queue.writeBuffer(vertices, 0, [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5] as Vec<float32>);
	const offsets: Vec<uint32> = [256];
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(0, uniformGroup(device, pipeline, uniforms), offsets);
	pass.draw(3, 1, 0, 0);
}

test "timestamps around two render passes resolve to nonzero nanoseconds, each pass ending after it began" {
	const device = openDevice();
	if (!device.features().has("timestamp-query")) { stopOnMetal("this device has no timestamp-query: the pin cannot run"); }
	const set = device.createQuerySet({ label: "timing", type: "timestamp", count: 4 });
	const pipeline = flatPipeline(device, flatShader(device), 1);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	for (let i = 0; i < 2; i++) {
		let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
		descriptor.timestampWrites = { querySet: set, beginningOfPassWriteIndex: i * 2, endOfPassWriteIndex: i == 0 ? 1 : GPU_NO_QUERY_INDEX };
		const pass = encoder.beginRenderPass(descriptor);
		drawTriangleIn(device, pipeline, pass);
		pass.end();
	}
	const resolved = resolveBuffer(device, 512);
	encoder.resolveQuerySet(set, 0, 3, resolved, 256);
	encoder.resolveQuerySet(set, 1, 2, resolved, 0);
	device.queue.submit(encoder.finish());
	const times = readCounters(device, resolved, 35);
	assert times[32] > 0;
	assert times[33] > times[32] && times[34] > times[32];
	assert times[0] == times[33] && times[1] == times[34];
	device.destroy();
}

test "an occlusion query counts samples over a drawn triangle, none over an empty one, and a reused set is rewritten" {
	const device = openDevice();
	const set = device.createQuerySet({ label: "occlusion", type: "occlusion", count: 2 });
	const pipeline = flatPipeline(device, flatShader(device), 1);
	const target = colourTarget(device, 1);
	let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.occlusionQuerySet = set;
	let encoder = device.createCommandEncoder();
	let pass = encoder.beginRenderPass(descriptor);
	pass.beginOcclusionQuery(0);
	drawTriangleIn(device, pipeline, pass);
	pass.endOcclusionQuery();
	pass.beginOcclusionQuery(1);
	pass.endOcclusionQuery();
	pass.end();
	const resolved = resolveBuffer(device, 512);
	encoder.resolveQuerySet(set, 0, 2, resolved, 256);
	encoder.resolveQuerySet(set, 0, 1, resolved, 0);
	device.queue.submit(encoder.finish());
	let counts = readCounters(device, resolved, 34);
	assert counts[0] > 0 && counts[32] == counts[0];
	assert counts[33] == 0;
	encoder = device.createCommandEncoder();
	pass = encoder.beginRenderPass(descriptor);
	pass.beginOcclusionQuery(1);
	drawTriangleIn(device, pipeline, pass);
	pass.endOcclusionQuery();
	pass.beginOcclusionQuery(0);
	pass.endOcclusionQuery();
	pass.end();
	encoder.resolveQuerySet(set, 0, 2, resolved, 256);
	device.queue.submit(encoder.finish());
	counts = readCounters(device, resolved, 34);
	assert counts[32] == 0 && counts[33] > 0;
	device.destroy();
}
