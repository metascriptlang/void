import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPURenderPassDescriptor,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUCompareFunction,
	GPUPrimitiveTopology,
	GPUSampler,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilOperation,
	GPUTexture,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
} from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { nativeTexture, bindStats } from "../webgpu/d3d11/backend.ms";
import { warpDevice, warpContext, warpReadback } from "./d3d11Warp.h";

@passL("-ld3d11");

const SIZE = 64;
const BLUE: uint32 = 0x0000FFFF;
const RED: uint32 = 0xFF0000FF;
const GREEN: uint32 = 0x00FF00FF;

const VERTEX_HLSL = "float4 main(float2 position : TEXCOORD0) : SV_Position { return float4(position, 0.0, 1.0); }";
const TEXTURED_FRAGMENT_HLSL = "Texture2D tex : register(t0);
SamplerState smp : register(s0);
float4 main(float4 p : SV_Position) : SV_Target0 { return tex.Sample(smp, p.xy / 64.0); }";
const FRAGMENT_HLSL = "cbuffer params : register(b0) { float4 color; };\nfloat4 main() : SV_Target0 { return color; }";

function stopOnWarp(message: string): void {
	console.log(`webgpuD3d11Check: ${message}`);
	unreachable;
}

function openDevice(): GPUDevice {
	const native = warpDevice();
	if (native == null) { stopOnWarp("D3D11CreateDevice with D3D_DRIVER_TYPE_WARP failed"); }
	return requestDevice({
		device: native,
		context: warpContext(),
		colorFormat: "rgba8unorm",
		depthFormat: "depth32float",
		sampleCount: 1,
	});
}

function flatShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "flat",
		vertexCode: VERTEX_HLSL,
		vertexEntryPoint: "",
		fragmentCode: FRAGMENT_HLSL,
		fragmentEntryPoint: "",
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

function readPixels(texture: GPUTexture): Vec<uint8> {
	let pixels: Vec<uint8> = new Array(SIZE * SIZE * 4);
	if (warpReadback(nativeTexture(texture), pixels[0], SIZE, SIZE) != 1) { stopOnWarp("the staging readback failed"); }
	return pixels;
}

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

test "a WARP triangle takes its colour from the uniform block at the dynamic offset" {
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

test "a partial writeTexture changes only its sub-rect, read from an offset with a padded row" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "atlas",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	let grey: Vec<uint8> = new Array(SIZE * SIZE * 4);
	for (let i = 0; i < SIZE * SIZE; i++) {
		grey[i * 4] = 9;
		grey[i * 4 + 1] = 9;
		grey[i * 4 + 2] = 9;
		grey[i * 4 + 3] = 255;
	}
	device.queue.writeTexture({ texture: texture }, grey, { offset: 0, bytesPerRow: SIZE * 4, rowsPerImage: SIZE }, { width: SIZE, height: SIZE, depthOrArrayLayers: 1 });
	let patch: Vec<uint8> = new Array(48);
	for (let i = 0; i < 48; i++) { patch[i] = 77; }
	for (let row = 0; row < 2; row++) {
		for (let column = 0; column < 4; column++) {
			const at = 8 + row * 24 + column * 4;
			patch[at] = 255;
			patch[at + 1] = 0;
			patch[at + 2] = 0;
			patch[at + 3] = 255;
		}
	}
	device.queue.writeTexture(
		{ texture: texture, origin: { x: 10, y: 20, z: 0 } },
		patch,
		{ offset: 8, bytesPerRow: 24, rowsPerImage: 2 },
		{ width: 4, height: 2, depthOrArrayLayers: 1 },
	);
	const pixels = readPixels(texture);
	const GREY: uint32 = 0x090909FF;
	for (let y = 20; y < 22; y++) {
		for (let x = 10; x < 14; x++) { assert pixel(pixels, x, y) == RED; }
	}
	assert pixel(pixels, 9, 20) == GREY;
	assert pixel(pixels, 14, 20) == GREY;
	assert pixel(pixels, 10, 19) == GREY;
	assert pixel(pixels, 13, 22) == GREY;
	assert pixel(pixels, 0, 0) == GREY;
	assert pixel(pixels, 63, 63) == GREY;
	device.destroy();
}

function texturedShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "textured",
		vertexCode: VERTEX_HLSL,
		vertexEntryPoint: "",
		fragmentCode: TEXTURED_FRAGMENT_HLSL,
		fragmentEntryPoint: "",
	};
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "texture", stage: "fragment", size: 0, nativeSlot: 0 };
	descriptor.bindings[1] = { group: 1, binding: 32, kind: "sampler", stage: "fragment", size: 0, nativeSlot: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	return device.createShaderModule(descriptor);
}

function sampledTexture(device: GPUDevice): GPUTexture {
	return device.createTexture({
		label: "sampled",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
}

function resourceGroup(device: GPUDevice, pipeline: GPURenderPipeline, texture: GPUTexture, sampler: GPUSampler): GPUBindGroup {
	let descriptor: GPUBindGroupDescriptor = { label: "resources", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = { binding: 0, textureView: texture.createView({ label: null }) };
	descriptor.entries[1] = { binding: 32, sampler: sampler };
	return device.createBindGroup(descriptor);
}

test "a bind that did not change issues no native call, and every change or new pass issues one" {
	const device = openDevice();
	const module = texturedShader(device);
	const pipeline = flatPipeline(device, module, 1);
	const first = sampledTexture(device);
	const second = sampledTexture(device);
	const sampler = device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" });
	const firstGroup = resourceGroup(device, pipeline, first, sampler);
	const secondGroup = resourceGroup(device, pipeline, second, sampler);
	const vertices = vertexBuffer(device, 64);
	const quad: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0, -1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	device.queue.writeBuffer(vertices, 32, quad);
	const indices = device.createBuffer({
		label: "indices",
		size: 12,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order: Vec<uint16> = [0, 1, 2, 0, 2, 3];
	device.queue.writeBuffer(indices, 0, order);
	const texel: Vec<uint8> = [255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255];
	const target = colourTarget(device, 1);
	const view = target.createView({ label: null });
	const noOffsets: Vec<uint32> = [];
	const start = bindStats();
	const encoder = device.createCommandEncoder();
	let pass = encoder.beginRenderPass(clearingPass(view, { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setIndexBuffer(indices, "uint16", 0);
	pass.setBindGroup(1, firstGroup, noOffsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	let now = bindStats();
	assert now.vertexBuffers - start.vertexBuffers == 1 && now.indexBuffers - start.indexBuffers == 1;
	assert now.shaderResources - start.shaderResources == 1 && now.samplers - start.samplers == 1;
	pass.setVertexBuffer(0, vertices, 0);
	pass.setIndexBuffer(indices, "uint16", 0);
	pass.setBindGroup(1, firstGroup, noOffsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	now = bindStats();
	assert now.vertexBuffers - start.vertexBuffers == 1 && now.indexBuffers - start.indexBuffers == 1;
	assert now.shaderResources - start.shaderResources == 1 && now.samplers - start.samplers == 1;
	pass.setBindGroup(1, secondGroup, noOffsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	now = bindStats();
	assert now.shaderResources - start.shaderResources == 2 && now.samplers - start.samplers == 1;
	pass.setVertexBuffer(0, vertices, 32);
	pass.drawIndexed(6, 1, 0, 0, 0);
	now = bindStats();
	assert now.vertexBuffers - start.vertexBuffers == 2 && now.indexBuffers - start.indexBuffers == 1;
	device.queue.writeTexture({ texture: second }, texel, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	pass.setBindGroup(1, secondGroup, noOffsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	now = bindStats();
	assert now.shaderResources - start.shaderResources == 2;
	pass.end();
	pass = encoder.beginRenderPass(clearingPass(view, { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 32);
	pass.setIndexBuffer(indices, "uint16", 0);
	pass.setBindGroup(1, secondGroup, noOffsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	now = bindStats();
	assert now.vertexBuffers - start.vertexBuffers == 3 && now.indexBuffers - start.indexBuffers == 2;
	assert now.shaderResources - start.shaderResources == 3 && now.samplers - start.samplers == 2;
	device.destroy();
}

function stripPipeline(device: GPUDevice, module: GPUShaderModule, topology: GPUPrimitiveTopology): GPURenderPipeline {
	let descriptor: GPURenderPipelineDescriptor = { label: "strip" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.primitive.topology = topology;
	return device.createRenderPipeline(descriptor);
}

function drawStrip(device: GPUDevice, topology: GPUPrimitiveTopology, points: Vec<float32>, count: int32, colourOffset: uint32, viewportWidth: number): Vec<uint8> {
	const module = flatShader(device);
	const pipeline = stripPipeline(device, module, topology);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 64);
	device.queue.writeBuffer(vertices, 0, points);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	if (viewportWidth > 0) { pass.setViewport(0, 0, viewportWidth, SIZE, 0, 1); }
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [colourOffset];
	pass.setBindGroup(0, group, offsets);
	pass.draw(count, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "setViewport confines a full-target triangle strip to the left half" {
	const device = openDevice();
	const full: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0];
	const pixels = drawStrip(device, "triangle-strip", full, 4, 256, 32.0);
	assert pixel(pixels, 16, 32) == GREEN;
	assert pixel(pixels, 2, 2) == GREEN;
	assert pixel(pixels, 48, 32) == BLUE;
	assert pixel(pixels, 62, 62) == BLUE;
	const whole = drawStrip(device, "triangle-strip", full, 4, 256, 0.0);
	assert pixel(whole, 48, 32) == GREEN;
	device.destroy();
}

test "a line-list draws a horizontal line and a triangle-strip fills a quad" {
	const device = openDevice();
	const line: Vec<float32> = [-1.0, -0.51, 1.0, -0.51];
	const pixels = drawStrip(device, "line-list", line, 2, 0, 0.0);
	assert pixel(pixels, 32, 48) == RED;
	assert pixel(pixels, 32, 40) == BLUE;
	assert pixel(pixels, 32, 56) == BLUE;
	const strip: Vec<float32> = [-0.5, -0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5];
	const quad = drawStrip(device, "triangle-strip", strip, 4, 0, 0.0);
	assert pixel(quad, 32, 32) == RED;
	assert pixel(quad, 20, 44) == RED;
	assert pixel(quad, 4, 4) == BLUE;
	device.destroy();
}

const COLOURED_VERTEX_HLSL = "struct Out { float4 position : SV_Position; float4 color : TEXCOORD0; };
Out main(float2 position : TEXCOORD0, float4 color : TEXCOORD1) { Out o; o.position = float4(position, 0.0, 1.0); o.color = color; return o; }";
const COLOURED_FRAGMENT_HLSL = "float4 main(float4 p : SV_Position, float4 color : TEXCOORD0) : SV_Target0 { return color; }";

test "a unorm8x4 vertex colour from a second vertex buffer reaches the fragment shader" {
	const device = openDevice();
	let descriptor: GPUShaderModuleDescriptor = {
		label: "coloured",
		vertexCode: COLOURED_VERTEX_HLSL,
		vertexEntryPoint: "",
		fragmentCode: COLOURED_FRAGMENT_HLSL,
		fragmentEntryPoint: "",
	};
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	descriptor.attributes[1] = { location: 1, nativeName: null, semanticIndex: 1 };
	const module = device.createShaderModule(descriptor);
	let pipelineDescriptor: GPURenderPipelineDescriptor = { label: "coloured" };
	pipelineDescriptor.vertex.module = module;
	pipelineDescriptor.vertex.buffers[0].arrayStride = 8;
	pipelineDescriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	pipelineDescriptor.vertex.buffers[1].arrayStride = 4;
	pipelineDescriptor.vertex.buffers[1].attributes[0] = { format: "unorm8x4", offset: 0, shaderLocation: 1 };
	pipelineDescriptor.fragment.module = module;
	pipelineDescriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(pipelineDescriptor);
	const positions = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(positions, 0, triangle);
	const colours = vertexBuffer(device, 12);
	const green: Vec<uint8> = [0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255];
	device.queue.writeBuffer(colours, 0, green);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, positions, 0);
	pass.setVertexBuffer(1, colours, 0);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	assert pixel(pixels, 32, 32) == GREEN;
	assert pixel(pixels, 2, 2) == BLUE;
	device.destroy();
}

test "comparison, anisotropic and mip-filtered samplers with W addressing and LOD clamps create" {
	const device = openDevice();
	const comparison = device.createSampler({ label: "shadow", magFilter: "linear", minFilter: "linear", compare: "less" });
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
	assert comparison.isAlive() && anisotropic.isAlive();
	assert device.liveCounts().samplers == 2;
	comparison.destroy();
	anisotropic.destroy();
	assert device.liveCounts().samplers == 0;
	device.destroy();
}

test "an sRGB render target stores a linear clear as its encoded bytes" {
	const device = openDevice();
	const target = device.createTexture({
		label: "srgb",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "rgba8unorm-srgb",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	let descriptor: GPURenderPassDescriptor = { label: "srgb clear" };
	descriptor.colorAttachments[0] = {
		view: target.createView({ label: null }),
		clearValue: { r: 0.5, g: 0.5, b: 0.5, a: 1.0 },
		loadOp: "clear",
		storeOp: "store",
	};
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	const red = pixel(readPixels(target), 10, 10) >> 24;
	assert red >= 186 && red <= 190;
	device.destroy();
}

function formatRoundTrip(device: GPUDevice, format: GPUTextureFormat): boolean {
	const texture = device.createTexture({
		label: "format",
		size: { width: 8, height: 8, depthOrArrayLayers: 1 },
		format: format,
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32),
		sampleCount: 1,
	});
	const view = texture.createView({ label: null });
	const alive = view.isAlive();
	view.destroy();
	texture.destroy();
	return alive;
}

test "every pixel format of the descriptor creates a texture and a view" {
	const device = openDevice();
	assert formatRoundTrip(device, "r8unorm");
	assert formatRoundTrip(device, "rg8unorm");
	assert formatRoundTrip(device, "rgba8unorm");
	assert formatRoundTrip(device, "rgba8unorm-srgb");
	assert formatRoundTrip(device, "bgra8unorm");
	assert formatRoundTrip(device, "bgra8unorm-srgb");
	assert formatRoundTrip(device, "rgba8uint");
	assert formatRoundTrip(device, "rgba8sint");
	assert formatRoundTrip(device, "r16float");
	assert formatRoundTrip(device, "rg16float");
	assert formatRoundTrip(device, "rgba16float");
	assert formatRoundTrip(device, "rgba16uint");
	assert formatRoundTrip(device, "r32float");
	assert formatRoundTrip(device, "rg32float");
	assert formatRoundTrip(device, "rgba32float");
	assert formatRoundTrip(device, "r32uint");
	assert formatRoundTrip(device, "rgb10a2unorm");
	assert formatRoundTrip(device, "rg11b10ufloat");
	assert formatRoundTrip(device, "depth16unorm");
	assert formatRoundTrip(device, "depth32float");
	assert formatRoundTrip(device, "depth24plus-stencil8");
	assert device.liveCounts().textures == 0;
	device.destroy();
}

function stencilPipeline(device: GPUDevice, module: GPUShaderModule, compare: GPUCompareFunction, passOp: GPUStencilOperation): GPURenderPipeline {
	let descriptor: GPURenderPipelineDescriptor = { label: "stencil" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.primitive.topology = "triangle-strip";
	descriptor.depthStencil.format = "depth24plus-stencil8";
	descriptor.depthStencil.depthCompare = "always";
	descriptor.depthStencil.stencilFront = { compare: compare, passOp: passOp };
	descriptor.depthStencil.stencilBack = { compare: compare, passOp: passOp };
	return device.createRenderPipeline(descriptor);
}

test "a stencil write at reference 1 masks a later equal-test draw to the left half" {
	const device = openDevice();
	const module = flatShader(device);
	const writer = stencilPipeline(device, module, "always", "replace");
	const tester = stencilPipeline(device, module, "equal", "keep");
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, writer, uniforms);
	const vertices = vertexBuffer(device, 64);
	const left: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 0.0, -1.0, 0.0, 1.0];
	const full: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0];
	device.queue.writeBuffer(vertices, 0, left);
	device.queue.writeBuffer(vertices, 32, full);
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
	pass.setStencilReference(1);
	pass.setPipeline(writer);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(0, group, red);
	pass.draw(4, 1, 0, 0);
	pass.setPipeline(tester);
	pass.setVertexBuffer(0, vertices, 32);
	pass.setBindGroup(0, group, green);
	pass.draw(4, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	assert pixel(pixels, 16, 32) == GREEN;
	assert pixel(pixels, 48, 32) == BLUE;
	device.destroy();
}

test "a pipeline with depth bias, slope scale and clamp creates" {
	const device = openDevice();
	const module = flatShader(device);
	let descriptor: GPURenderPipelineDescriptor = { label: "bias" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.depthStencil.format = "depth32float";
	descriptor.depthStencil.depthWriteEnabled = true;
	descriptor.depthStencil.depthCompare = "less";
	descriptor.depthStencil.depthBias = 2;
	descriptor.depthStencil.depthBiasSlopeScale = 1.5;
	descriptor.depthStencil.depthBiasClamp = 0.1;
	const pipeline = device.createRenderPipeline(descriptor);
	assert pipeline.id != 0;
	assert device.liveCounts().pipelines == 1;
	device.destroy();
}

test "a bind group entry offset selects the second uniform block" {
	const device = openDevice();
	const pixels = drawTriangleAt(device, 1, 0, 256);
	assert pixel(pixels, 32, 32) == GREEN;
	assert pixel(pixels, 0, 0) == BLUE;
	device.destroy();
}
