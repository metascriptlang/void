import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPURenderPassDescriptor,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
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
