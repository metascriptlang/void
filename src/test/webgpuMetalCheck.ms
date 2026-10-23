import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBlendFactor,
	GPUCompareFunction,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPUIndexFormat,
	GPUVertexFormat,
	GPUPrimitiveTopology,
	GPURenderPassDescriptor,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerBindingType,
	GPUShaderBinding,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilOperation,
	GPUTexture,
	GPUTextureDimension,
	GPUTextureFormat,
	GPUTextureSampleType,
	GPUTextureUsage,
	GPUTextureView,
	GPUTextureViewDimension,
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
