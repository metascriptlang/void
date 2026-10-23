import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBufferUsage,
	GPUDevice,
	GPU_NO_QUERY_INDEX,
	GPUMapMode,
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
import { getCurrentTexture, requestDevice } from "../webgpu/device.ms";
import {
	doorBeginColorPass,
	doorEndPass,
	doorMakeAttachmentView,
	doorMakeTargetImage,
	doorReadTexture,
	doorSetup,
	doorShutdown,
} from "../gpu/doorGpu.ms";
import { nativeTexture, bindStats } from "../webgpu/d3d11/backend.ms";
import {
	BLUE,
	GREEN,
	RED,
	SIZE,
	clearingPass,
	colourTarget,
	colourUniforms,
	drawTriangleIn,
	pixel,
	readBack,
	readCounters,
	readbackBuffer,
	resolveBuffer,
	texelAt,
	texels,
	uniformGroup,
	uniformGroupAt,
	vertexBuffer,
} from "./webgpuFixtures.ms";
import { d3dBlobFree, d3dBlobRead, d3dCompile, d3dCompileLog } from "../webgpu/d3d11/d3d11.h";
import { warpDevice, warpContext, warpReadback, warpReadback3d, warpReadbackSubresource, warpObjectName, warpTarget, warpTargetView } from "./d3d11Warp.h";

@passL("-ld3d11");


const VERTEX_HLSL = "float4 main(float2 position : TEXCOORD0) : SV_Position { return float4(position, 0.0, 1.0); }";
const TEXTURED_FRAGMENT_HLSL = "Texture2D tex : register(t0);\nSamplerState smp : register(s0);\nfloat4 main(float4 p : SV_Position) : SV_Target0 { return tex.Sample(smp, p.xy / 64.0); }";
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

function readPixels(texture: GPUTexture): Vec<uint8> {
	let pixels: Vec<uint8> = new Array(SIZE * SIZE * 4);
	if (warpReadback(nativeTexture(texture), pixels[0], SIZE, SIZE) != 1) { stopOnWarp("the staging readback failed"); }
	return pixels;
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

const GREEN_HLSL = "float4 main() : SV_Target0 { return float4(0.0, 1.0, 0.0, 1.0); }";

function dxbc(code: string, target: string): Vec<uint8> {
	const blob = d3dCompile(code, "main", target);
	if (blob == null) { stopOnWarp(`D3DCompile ${target} failed: ${d3dCompileLog()}`); }
	let bytes: Vec<uint8> = new Array(65536);
	const size = d3dBlobRead(blob, bytes[0], 65536);
	d3dBlobFree(blob);
	if (size <= 0) { stopOnWarp("the compiled blob did not fit 64 KiB"); }
	bytes.setLength(size as number);
	return bytes;
}

function greenTriangle(device: GPUDevice, descriptor: GPUShaderModuleDescriptor): Vec<uint8> {
	const pipeline = flatPipeline(device, device.createShaderModule(descriptor), 1);
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readPixels(target);
}

test "a module built from precompiled DXBC with empty text draws, and a stage without a blob still compiles its text" {
	const device = openDevice();
	let blobs: GPUShaderModuleDescriptor = {
		label: "blobs",
		vertexCode: "",
		vertexEntryPoint: "",
		fragmentCode: "",
		fragmentEntryPoint: "",
		vertexBytecode: dxbc(VERTEX_HLSL, "vs_5_0"),
		fragmentBytecode: dxbc(GREEN_HLSL, "ps_5_0"),
	};
	blobs.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const fromBlobs = greenTriangle(device, blobs);
	assert pixel(fromBlobs, 0, 0) == BLUE;
	assert pixel(fromBlobs, 32, 32) == GREEN;
	let mixed: GPUShaderModuleDescriptor = {
		label: "mixed",
		vertexCode: "",
		vertexEntryPoint: "",
		fragmentCode: GREEN_HLSL,
		fragmentEntryPoint: "",
		vertexBytecode: dxbc(VERTEX_HLSL, "vs_5_0"),
	};
	mixed.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	assert pixel(greenTriangle(device, mixed), 32, 32) == GREEN;
	device.destroy();
}

test "a compute module built from precompiled DXBC with empty text doubles a storage buffer" {
	const device = openDevice();
	let descriptor: GPUShaderModuleDescriptor = { label: "compute", computeCode: "", computeEntryPoint: "", computeBytecode: dxbc(DOUBLE_HLSL, "cs_5_0") };
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-buffer", stage: "compute", bufferType: "storage", nativeSlot: 0 };
	const module = device.createShaderModule(descriptor);
	const storage = device.createBuffer({
		label: "storage",
		size: 16,
		usage: (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32) | (GPUBufferUsage.COPY_SRC as int32),
	});
	const values: Vec<uint32> = [1, 2, 3, 4];
	device.queue.writeBuffer(storage, 0, values);
	dispatchOnce(device, module, { binding: 0, buffer: storage });
	const readback = readbackBuffer(device, 16);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(storage, 0, readback, 0, 16);
	device.queue.submit(encoder.finish());
	const read = readBack(readback);
	assert read[0] == 2 && read[4] == 4 && read[8] == 6 && read[12] == 8;
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

function drawStrip(device: GPUDevice, topology: GPUPrimitiveTopology, points: Vec<float32>, count: int32, colourOffset: uint32, viewportWidth: float32): Vec<uint8> {
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

const COLOURED_VERTEX_HLSL = "struct Out { float4 position : SV_Position; float4 color : TEXCOORD0; };\nOut main(float2 position : TEXCOORD0, float4 color : TEXCOORD1) { Out o; o.position = float4(position, 0.0, 1.0); o.color = color; return o; }";
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

function readSubresource(texture: GPUTexture, subresource: int32, width: int32, height: int32): Vec<uint8> {
	let pixels: Vec<uint8> = new Array(width * height * 4);
	if (warpReadbackSubresource(nativeTexture(texture), subresource, pixels[0], width, height) != 1) {
		stopOnWarp("the staging readback of a subresource failed");
	}
	return pixels;
}

function centreOf(pixels: Vec<uint8>, width: int32): uint32 {
	const at = ((width / 2) * width + width / 2) * 4;
	return ((pixels[at] as uint32) << 24) | ((pixels[at + 1] as uint32) << 16) |
		((pixels[at + 2] as uint32) << 8) | (pixels[at + 3] as uint32);
}

function sampleCentre(device: GPUDevice, view: GPUTextureView): uint32 {
	return sampleCentreWith(device, texturedShader(device), view);
}

function sampleCentreWith(device: GPUDevice, module: GPUShaderModule, view: GPUTextureView): uint32 {
	const pipeline = flatPipeline(device, module, 1);
	const sampler = device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" });
	let descriptor: GPUBindGroupDescriptor = { label: "resources", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = { binding: 0, textureView: view };
	descriptor.entries[1] = { binding: 32, sampler: sampler };
	const group = device.createBindGroup(descriptor);
	const vertices = vertexBuffer(device, 32);
	const quad: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0, -1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	const indices = device.createBuffer({
		label: "indices",
		size: 12,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order: Vec<uint16> = [0, 1, 2, 0, 2, 3];
	device.queue.writeBuffer(indices, 0, order);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setIndexBuffer(indices, "uint16", 0);
	const noOffsets: Vec<uint32> = [];
	pass.setBindGroup(1, group, noOffsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return pixel(readPixels(target), 32, 32);
}

test "a view of mip 1 alone samples mip 1 of a three-mip texture" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "mips",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
		mipLevelCount: 3,
	});
	device.queue.writeTexture({ texture: texture, mipLevel: 0 }, texels(255, 0, 0, 16), { offset: 0, bytesPerRow: 16, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.writeTexture({ texture: texture, mipLevel: 1 }, texels(0, 255, 0, 4), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	device.queue.writeTexture({ texture: texture, mipLevel: 2 }, texels(0, 0, 255, 1), { offset: 0, bytesPerRow: 4, rowsPerImage: 1 }, { width: 1, height: 1, depthOrArrayLayers: 1 });
	const mip0 = texture.createView({ label: null, baseMipLevel: 0, mipLevelCount: 1 });
	const mip1 = texture.createView({ label: null, baseMipLevel: 1, mipLevelCount: 1 });
	const mip2 = texture.createView({ label: null, baseMipLevel: 2, mipLevelCount: 1 });
	assert sampleCentre(device, mip1) == GREEN;
	assert sampleCentre(device, mip0) == RED;
	assert sampleCentre(device, mip2) == BLUE;
	device.destroy();
}

test "a single-mip attachment view renders into mip 1 and leaves mip 0 alone" {
	const device = openDevice();
	const target = device.createTexture({
		label: "mipped target",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
		mipLevelCount: 2,
	});
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, 1);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const view = target.createView({ label: null, baseMipLevel: 1, mipLevelCount: 1 });
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(view, { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const half = readSubresource(target, 1, 32, 32);
	assert half[0] == 0 && half[1] == 0 && half[2] == 255 && half[3] == 255;
	assert centreOf(half, 32) == RED;
	const full = readSubresource(target, 0, SIZE, SIZE);
	assert centreOf(full, SIZE) == 0;
	device.destroy();
}

test "a two-dimensional array writes per layer and a 2d view at baseArrayLayer samples that layer" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "layers",
		size: { width: 2, height: 2, depthOrArrayLayers: 3 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 2 } }, texels(0, 0, 255, 4), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	let both: Vec<uint8> = texels(255, 0, 0, 4);
	const second = texels(0, 255, 0, 4);
	for (let i = 0; i < 16; i++) { both.push(second[i]); }
	device.queue.writeTexture({ texture: texture }, both, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 2 });
	const layer2 = texture.createView({ label: null, dimension: "2d", baseArrayLayer: 2 });
	const layer1 = texture.createView({ label: null, dimension: "2d", baseArrayLayer: 1 });
	const layer0 = texture.createView({ label: null, dimension: "2d", baseArrayLayer: 0 });
	const all = texture.createView({ label: null });
	assert all.isAlive();
	assert sampleCentre(device, layer2) == BLUE;
	assert sampleCentre(device, layer1) == GREEN;
	assert sampleCentre(device, layer0) == RED;
	device.destroy();
}

test "a six-layer texture creates a cube view and a cube-array view" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "cube",
		size: { width: 2, height: 2, depthOrArrayLayers: 6 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 5 } }, texels(255, 0, 0, 4), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	const cube = texture.createView({ label: null, dimension: "cube" });
	const cubes = texture.createView({ label: null, dimension: "cube-array", arrayLayerCount: 6 });
	const faces = texture.createView({ label: null, dimension: "2d-array", baseArrayLayer: 3, arrayLayerCount: 3 });
	assert cube.isAlive() && cubes.isAlive() && faces.isAlive();
	device.destroy();
}

test "a 4x4x4 three-dimensional texture takes a write with rowsPerImage and a 3d view" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "volume",
		size: { width: 4, height: 4, depthOrArrayLayers: 4 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
		dimension: "3d",
		mipLevelCount: 2,
	});
	device.queue.writeTexture({ texture: texture }, texels(255, 0, 0, 64), { offset: 0, bytesPerRow: 16, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 4 });
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 2 } }, texels(0, 255, 0, 32), { offset: 0, bytesPerRow: 16, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 2 });
	device.queue.writeTexture({ texture: texture, mipLevel: 1 }, texels(0, 0, 255, 8), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 2 });
	const volume = texture.createView({ label: null, dimension: "3d" });
	const volumeMip = texture.createView({ label: null, dimension: "3d", baseMipLevel: 1, mipLevelCount: 1 });
	assert volume.isAlive() && volumeMip.isAlive();
	device.destroy();
}

test "a blend constant of 0.5 weights a red source over black to half red" {
	const device = openDevice();
	const module = flatShader(device);
	let descriptor: GPURenderPipelineDescriptor = { label: "blend" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.fragment.targets[0].blendEnabled = true;
	descriptor.fragment.targets[0].blend = {
		color: { operation: "add", srcFactor: "constant", dstFactor: "one-minus-constant" },
		alpha: { operation: "add", srcFactor: "one", dstFactor: "zero" },
	};
	const pipeline = device.createRenderPipeline(descriptor);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, 1);
	let pass: GPURenderPassDescriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	pass.colorAttachments[0].clearValue = { r: 0.0, g: 0.0, b: 0.0, a: 1.0 };
	const encoder = device.createCommandEncoder();
	const encoded = encoder.beginRenderPass(pass);
	encoded.setPipeline(pipeline);
	encoded.setVertexBuffer(0, vertices, 0);
	encoded.setBlendConstant({ r: 0.5, g: 0.5, b: 0.5, a: 0.5 });
	const offsets: Vec<uint32> = [0];
	encoded.setBindGroup(0, group, offsets);
	encoded.draw(3, 1, 0, 0);
	encoded.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	const at = (32 * SIZE + 32) * 4;
	assert pixels[at] >= 126 && pixels[at] <= 129;
	assert pixels[at + 1] == 0 && pixels[at + 2] == 0 && pixels[at + 3] == 255;
	assert pixel(pixels, 0, 0) == 0x000000FF;
	device.destroy();
}

test "a buffer range copies to a MAP_READ buffer and a mapped range reads it back" {
	const device = openDevice();
	const source = device.createBuffer({
		label: "source",
		size: 16,
		usage: (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const bytes: Vec<uint8> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
	device.queue.writeBuffer(source, 0, bytes);
	const destination = readbackBuffer(device, 32);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(source, 4, destination, 8, 8);
	device.queue.submit(encoder.finish());
	const read = readBack(destination);
	assert read.length == 32;
	for (let i = 0; i < 8; i++) { assert read[8 + i] == (5 + i) as uint8; }
	assert read[7] == 0 && read[16] == 0;
	device.destroy();
}

test "a MAP_WRITE buffer filled through a mapped range copies to a MAP_READ buffer" {
	const device = openDevice();
	const upload = device.createBuffer({
		label: "upload",
		size: 16,
		usage: (GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32),
	});
	upload.mapAsync(GPUMapMode.WRITE as int32, 0, 0);
	const bytes: Vec<uint8> = [9, 8, 7, 6, 5, 4, 3, 2];
	upload.writeMappedRange(8, bytes);
	upload.unmap();
	const destination = readbackBuffer(device, 16);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(upload, 8, destination, 0, 8);
	device.queue.submit(encoder.finish());
	destination.mapAsync(GPUMapMode.READ as int32, 0, 8);
	const read = destination.getMappedRange(0, 8);
	destination.unmap();
	assert read.length == 8;
	for (let i = 0; i < 8; i++) { assert read[i] == (9 - i) as uint8; }
	device.destroy();
}

test "a writeTexture sub-rect reads back through copyTextureToBuffer with a 256-byte row" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "atlas",
		size: { width: 8, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	let data: Vec<uint8> = new Array(8 * 4 * 4);
	for (let i = 0; i < 32; i++) {
		data[i * 4] = i as uint8;
		data[i * 4 + 1] = (i * 2) as uint8;
		data[i * 4 + 2] = (i * 3) as uint8;
		data[i * 4 + 3] = 255;
	}
	device.queue.writeTexture({ texture: texture }, data, { offset: 0, bytesPerRow: 32, rowsPerImage: 4 }, { width: 8, height: 4, depthOrArrayLayers: 1 });
	const destination = readbackBuffer(device, 1024);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: texture, origin: { x: 2, y: 1, z: 0 } },
		{ buffer: destination, offset: 0, bytesPerRow: 256, rowsPerImage: 2 },
		{ width: 4, height: 2, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readBack(destination);
	for (let y = 0; y < 2; y++) {
		for (let x = 0; x < 4; x++) {
			const i = (y + 1) * 8 + x + 2;
			const want = ((i as uint32) << 24) | (((i * 2) as uint32) << 16) | (((i * 3) as uint32) << 8) | 255;
			assert texelAt(read, 256, x, y) == want;
		}
	}
	device.destroy();
}

test "a cleared render target copies to a buffer and every row holds the clear colour" {
	const device = openDevice();
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 })).end();
	const destination = readbackBuffer(device, 256 * SIZE);
	encoder.copyTextureToBuffer(
		{ texture: target },
		{ buffer: destination, offset: 0, bytesPerRow: 256, rowsPerImage: SIZE },
		{ width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readBack(destination);
	assert texelAt(read, 256, 0, 0) == BLUE;
	assert texelAt(read, 256, 10, 10) == BLUE;
	assert texelAt(read, 256, SIZE - 1, SIZE - 1) == BLUE;
	device.destroy();
}

test "copyTextureToTexture copies mip 1 into a region of mip 0" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "mips",
		size: { width: 8, height: 8, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
		mipLevelCount: 2,
	});
	const red = texels(255, 0, 0, 64);
	const green = texels(0, 255, 0, 16);
	device.queue.writeTexture({ texture: texture }, red, { offset: 0, bytesPerRow: 32, rowsPerImage: 8 }, { width: 8, height: 8, depthOrArrayLayers: 1 });
	device.queue.writeTexture({ texture: texture, mipLevel: 1 }, green, { offset: 0, bytesPerRow: 16, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	const destination = readbackBuffer(device, 256 * 8);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToTexture(
		{ texture: texture, mipLevel: 1 },
		{ texture: texture, mipLevel: 0, origin: { x: 2, y: 2, z: 0 } },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	encoder.copyTextureToBuffer(
		{ texture: texture },
		{ buffer: destination, offset: 0, bytesPerRow: 256, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readBack(destination);
	const RED_TEXEL: uint32 = 0xFF0000FF;
	const GREEN_TEXEL: uint32 = 0x00FF00FF;
	assert texelAt(read, 256, 1, 1) == RED_TEXEL;
	assert texelAt(read, 256, 2, 2) == GREEN_TEXEL;
	assert texelAt(read, 256, 5, 5) == GREEN_TEXEL;
	assert texelAt(read, 256, 6, 6) == RED_TEXEL;
	assert texelAt(read, 256, 2, 6) == RED_TEXEL;
	device.destroy();
}

test "a buffer region at an offset with a 256-byte row copies into a texture sub-rect" {
	const device = openDevice();
	const source = device.createBuffer({
		label: "texels",
		size: 512,
		usage: (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	let data: Vec<uint8> = new Array(288);
	for (let i = 0; i < 288; i++) { data[i] = 0; }
	for (let row = 0; row < 2; row++) {
		for (let column = 0; column < 4; column++) {
			const at = 16 + row * 256 + column * 4;
			data[at] = (column + 1) as uint8;
			data[at + 1] = (row + 1) as uint8;
			data[at + 2] = 7;
			data[at + 3] = 255;
		}
	}
	device.queue.writeBuffer(source, 0, data);
	const texture = device.createTexture({
		label: "target",
		size: { width: 8, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	const destination = readbackBuffer(device, 1024);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture(
		{ buffer: source, offset: 16, bytesPerRow: 256, rowsPerImage: 2 },
		{ texture: texture, origin: { x: 3, y: 1, z: 0 } },
		{ width: 4, height: 2, depthOrArrayLayers: 1 },
	);
	encoder.copyTextureToBuffer(
		{ texture: texture },
		{ buffer: destination, offset: 0, bytesPerRow: 256, rowsPerImage: 4 },
		{ width: 8, height: 4, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readBack(destination);
	assert texelAt(read, 256, 3, 1) == 0x010107FF;
	assert texelAt(read, 256, 6, 2) == 0x040207FF;
	assert texelAt(read, 256, 2, 1) == 0;
	assert texelAt(read, 256, 3, 3) == 0;
	device.destroy();
}

const DOUBLE_HLSL = "RWByteAddressBuffer data : register(u0);\n[numthreads(4, 1, 1)] void main(uint3 id : SV_DispatchThreadID) { uint at = id.x * 4; data.Store(at, data.Load(at) * 2); }";

function computeModule(device: GPUDevice, code: string, kind: string, nativeSlot: int32): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = { label: "compute", computeCode: code, computeEntryPoint: "" };
	if (kind == "storage-buffer") {
		descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-buffer", stage: "compute", bufferType: "storage", nativeSlot: nativeSlot };
	} else {
		descriptor.bindings[0] = {
			group: 1,
			binding: 0,
			kind: "storage-texture",
			stage: "compute",
			storageAccess: "write-only",
			storageFormat: "r32uint",
			nativeSlot: nativeSlot,
		};
	}
	return device.createShaderModule(descriptor);
}

function dispatchOnce(device: GPUDevice, module: GPUShaderModule, entry: GPUBindGroupEntry): void {
	const pipeline = device.createComputePipeline({ label: "compute", compute: { module: module, entryPoint: "" } });
	let descriptor: GPUBindGroupDescriptor = { label: "storage", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = entry;
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginComputePass({ label: null });
	pass.setPipeline(pipeline);
	pass.setBindGroup(1, device.createBindGroup(descriptor), noOffsets);
	pass.dispatchWorkgroups(1, 1, 1);
	pass.end();
	device.queue.submit(encoder.finish());
}

test "a compute pass doubles a storage buffer, directly and through an indirect dispatch" {
	const device = openDevice();
	const module = computeModule(device, DOUBLE_HLSL, "storage-buffer", 0);
	const storage = device.createBuffer({
		label: "storage",
		size: 16,
		usage: (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32) | (GPUBufferUsage.COPY_SRC as int32),
	});
	const values: Vec<uint32> = [1, 2, 3, 40000];
	device.queue.writeBuffer(storage, 0, values);
	dispatchOnce(device, module, { binding: 0, buffer: storage });
	const readback = readbackBuffer(device, 16);
	let encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(storage, 0, readback, 0, 16);
	device.queue.submit(encoder.finish());
	let read = readBack(readback);
	assert read[0] == 2 && read[4] == 4 && read[8] == 6;
	assert read[12] == 0x80 && read[13] == 0x38;

	const pipeline = device.createComputePipeline({ label: "indirect", compute: { module: module, entryPoint: "" } });
	let descriptor: GPUBindGroupDescriptor = { label: "storage", layout: pipeline.getBindGroupLayout(1) };
	descriptor.entries[0] = { binding: 0, buffer: storage };
	const group = device.createBindGroup(descriptor);
	const arguments = device.createBuffer({
		label: "arguments",
		size: 12,
		usage: (GPUBufferUsage.INDIRECT as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const counts: Vec<uint32> = [1, 1, 1];
	device.queue.writeBuffer(arguments, 0, counts);
	const noOffsets: Vec<uint32> = [];
	encoder = device.createCommandEncoder();
	const pass = encoder.beginComputePass({ label: null });
	pass.setPipeline(pipeline);
	pass.setBindGroup(1, group, noOffsets);
	pass.dispatchWorkgroupsIndirect(arguments, 0);
	pass.end();
	encoder.copyBufferToBuffer(storage, 0, readback, 0, 16);
	device.queue.submit(encoder.finish());
	read = readBack(readback);
	assert read[0] == 4 && read[4] == 8 && read[8] == 12;
	device.destroy();
}

const FILL_HLSL = "RWTexture2D<uint> image : register(u0);\n[numthreads(4, 4, 1)] void main(uint3 id : SV_DispatchThreadID) { image[id.xy] = id.x + id.y * 10; }";

test "a compute pass writes a storage texture that copies back" {
	const device = openDevice();
	const module = computeModule(device, FILL_HLSL, "storage-texture", 0);
	const texture = device.createTexture({
		label: "image",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "r32uint",
		usage: (GPUTextureUsage.STORAGE_BINDING as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	dispatchOnce(device, module, { binding: 0, textureView: texture.createView({ label: null }) });
	const readback = readbackBuffer(device, 1024);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: texture },
		{ buffer: readback, offset: 0, bytesPerRow: 256, rowsPerImage: 4 },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readBack(readback);
	assert read[0] == 0 && read[4] == 1 && read[12] == 3;
	assert read[256] == 10 && read[3 * 256 + 3 * 4] == 33;
	device.destroy();
}

test "a fragment shader reads a read-only storage buffer" {
	const device = openDevice();
	let descriptor: GPUShaderModuleDescriptor = {
		label: "storage fragment",
		vertexCode: VERTEX_HLSL,
		vertexEntryPoint: "",
		fragmentCode: "ByteAddressBuffer colors : register(t0);\nfloat4 main() : SV_Target0 { return asfloat(colors.Load4(0)); }",
		fragmentEntryPoint: "",
	};
	descriptor.bindings[0] = {
		group: 1,
		binding: 0,
		kind: "storage-buffer",
		stage: "fragment",
		bufferType: "read-only-storage",
		nativeSlot: 0,
	};
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const module = device.createShaderModule(descriptor);
	const pipeline = flatPipeline(device, module, 1);
	const colours = device.createBuffer({
		label: "colours",
		size: 16,
		usage: (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const red: Vec<float32> = [1.0, 0.0, 0.0, 1.0];
	device.queue.writeBuffer(colours, 0, red);
	let group: GPUBindGroupDescriptor = { label: "colours", layout: pipeline.getBindGroupLayout(1) };
	group.entries[0] = { binding: 0, buffer: colours };
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, 1);
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(1, device.createBindGroup(group), noOffsets);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixels(target);
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == RED;
	device.destroy();
}

test "the limits are the constants the backend enforces, and the features say what the device can do" {
	const device = openDevice();
	const limits = device.limits();
	assert limits.maxTextureDimension1D > 0 && limits.maxTextureDimension2D == 16384 && limits.maxTextureDimension3D == 2048;
	assert limits.maxTextureArrayLayers == 2048 && limits.maxBindGroups == 2;
	assert limits.maxSampledTexturesPerShaderStage > 0 && limits.maxSamplersPerShaderStage > 0;
	assert limits.maxStorageBuffersPerShaderStage > 0 && limits.maxStorageTexturesPerShaderStage > 0;
	assert limits.maxUniformBuffersPerShaderStage > 0 && limits.maxUniformBufferBindingSize == 65536;
	assert limits.maxStorageBufferBindingSize > 0 && limits.maxVertexBuffers == 2 && limits.maxVertexAttributes == 16;
	assert limits.maxColorAttachments == 4 && limits.maxComputeWorkgroupSizeX == 1024 && limits.maxComputeWorkgroupSizeY == 1024;
	assert limits.maxComputeWorkgroupSizeZ == 64 && limits.maxComputeInvocationsPerWorkgroup == 1024;
	assert limits.maxComputeWorkgroupsPerDimension == 65535;
	assert limits.minUniformBufferOffsetAlignment == 256 && limits.minStorageBufferOffsetAlignment == 256;
	const widest = device.createTexture({
		label: "widest",
		size: { width: limits.maxTextureDimension2D, height: 1, depthOrArrayLayers: 1 },
		format: "r8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
	});
	assert widest.width() == limits.maxTextureDimension2D;
	const features = device.features();
	assert features.has("timestamp-query") && features.has("float32-filterable") && features.has("rg11b10ufloat-renderable");
	assert !features.has("texture-compression-bc") && !features.has("depth32float-stencil8") && !features.has("shader-f16");
	device.destroy();
}

test "a label reaches the native object and a pass label and debug groups balance" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "labelled texture",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
	});
	let name: Vec<uint8> = new Array(64);
	const length = warpObjectName(nativeTexture(texture), name[0], 64);
	assert length == 16;
	assert name[0] == 108 && name[9] == 116 && name[15] == 101;
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	encoder.pushDebugGroup("frame");
	encoder.insertDebugMarker("before");
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.pushDebugGroup("inside");
	pass.insertDebugMarker("marker");
	pass.popDebugGroup();
	pass.end();
	const compute = encoder.beginComputePass({ label: "compute" });
	compute.pushDebugGroup("compute group");
	compute.popDebugGroup();
	compute.end();
	encoder.popDebugGroup();
	device.queue.submit(encoder.finish());
	device.destroy();
}

function triangleSetup(device: GPUDevice): GPURenderPipeline {
	return flatPipeline(device, flatShader(device), 1);
}

test "two timestamps around a render pass and around a compute pass resolve to non-decreasing nanoseconds" {
	const device = openDevice();
	const set = device.createQuerySet({ label: "timing", type: "timestamp", count: 4 });
	const pipeline = triangleSetup(device);
	const target = colourTarget(device, 1);
	let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.timestampWrites = { querySet: set, beginningOfPassWriteIndex: 0, endOfPassWriteIndex: 1 };
	let encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(descriptor);
	drawTriangleIn(device, pipeline, pass);
	pass.end();
	const module = computeModule(device, DOUBLE_HLSL, "storage-buffer", 0);
	const storage = device.createBuffer({ label: "storage", size: 16, usage: GPUBufferUsage.STORAGE as int32 });
	const computePipeline = device.createComputePipeline({ label: "compute", compute: { module: module, entryPoint: "" } });
	let group: GPUBindGroupDescriptor = { label: "storage", layout: computePipeline.getBindGroupLayout(1) };
	group.entries[0] = { binding: 0, buffer: storage };
	const noOffsets: Vec<uint32> = [];
	const compute = encoder.beginComputePass({
		label: "timed compute",
		timestampWrites: { querySet: set, beginningOfPassWriteIndex: 2, endOfPassWriteIndex: GPU_NO_QUERY_INDEX },
	});
	compute.setPipeline(computePipeline);
	compute.setBindGroup(1, device.createBindGroup(group), noOffsets);
	compute.dispatchWorkgroups(1, 1, 1);
	compute.end();
	const resolved = resolveBuffer(device, 24);
	encoder.resolveQuerySet(set, 0, 3, resolved, 0);
	device.queue.submit(encoder.finish());
	const times = readCounters(device, resolved, 3);
	assert times[0] > 0;
	assert times[1] >= times[0];
	assert times[2] >= times[1];
	device.destroy();
}

test "an occlusion query counts samples over a drawn triangle and none over an empty pass" {
	const device = openDevice();
	const set = device.createQuerySet({ label: "occlusion", type: "occlusion", count: 2 });
	const pipeline = triangleSetup(device);
	const target = colourTarget(device, 1);
	let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.occlusionQuerySet = set;
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(descriptor);
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
	const counts = readCounters(device, resolved, 34);
	assert counts[0] > 0 && counts[32] == counts[0];
	assert counts[33] == 0;
	device.destroy();
}

const CUBE_FRAGMENT_HLSL = "TextureCube tex : register(t0);\nSamplerState smp : register(s0);\nfloat4 main(float4 p : SV_Position) : SV_Target0 { return tex.Sample(smp, float3(0.0, 0.0, 1.0)); }";

test "a cube view at baseArrayLayer 6 samples the second cube of a twelve-layer texture" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "two cubes",
		size: { width: 2, height: 2, depthOrArrayLayers: 12 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 4 } }, texels(255, 0, 0, 4), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 10 } }, texels(0, 0, 255, 4), { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	let descriptor: GPUShaderModuleDescriptor = {
		label: "cube",
		vertexCode: VERTEX_HLSL,
		vertexEntryPoint: "",
		fragmentCode: CUBE_FRAGMENT_HLSL,
		fragmentEntryPoint: "",
	};
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "texture", stage: "fragment", size: 0, nativeSlot: 0 };
	descriptor.bindings[1] = { group: 1, binding: 32, kind: "sampler", stage: "fragment", size: 0, nativeSlot: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const module = device.createShaderModule(descriptor);
	assert sampleCentreWith(device, module, texture.createView({ label: null, dimension: "cube", baseArrayLayer: 6 })) == BLUE;
	assert sampleCentreWith(device, module, texture.createView({ label: null, dimension: "cube", baseArrayLayer: 0 })) == RED;
	device.destroy();
}

function resolveInto(device: GPUDevice, resolveView: GPUTextureView): void {
	const source = colourTarget(device, 4);
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(clearingPass(source.createView({ label: null }), resolveView)).end();
	device.queue.submit(encoder.finish());
}

test "a resolve target at baseMipLevel 1 and at baseArrayLayer 1 receives the resolved clear and leaves the other subresources alone" {
	const device = openDevice();
	const usage = (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32);
	const mipped = device.createTexture({ label: "mips", size: { width: 2 * SIZE, height: 2 * SIZE, depthOrArrayLayers: 1 }, format: "rgba8unorm", usage: usage, sampleCount: 1, mipLevelCount: 2 });
	resolveInto(device, mipped.createView({ label: null, baseMipLevel: 1, mipLevelCount: 1 }));
	assert centreOf(readSubresource(mipped, 1, SIZE, SIZE), SIZE) == BLUE;
	assert centreOf(readSubresource(mipped, 0, 2 * SIZE, 2 * SIZE), 2 * SIZE) == 0;
	const layered = device.createTexture({ label: "layers", size: { width: SIZE, height: SIZE, depthOrArrayLayers: 2 }, format: "rgba8unorm", usage: usage, sampleCount: 1 });
	resolveInto(device, layered.createView({ label: null, dimension: "2d", baseArrayLayer: 1 }));
	assert centreOf(readSubresource(layered, 1, SIZE, SIZE), SIZE) == BLUE;
	assert centreOf(readSubresource(layered, 0, SIZE, SIZE), SIZE) == 0;
	device.destroy();
}

test "a colour attachment with depthSlice 2 clears that slice of a 3d texture alone" {
	const device = openDevice();
	const volume = device.createTexture({
		label: "volume target",
		size: { width: 4, height: 4, depthOrArrayLayers: 4 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32),
		sampleCount: 1,
		dimension: "3d",
	});
	let descriptor = clearingPass(volume.createView({ label: null, dimension: "3d" }), { id: 0 });
	descriptor.colorAttachments[0].depthSlice = 2;
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(descriptor).end();
	device.queue.submit(encoder.finish());
	let pixels: Vec<uint8> = new Array(4 * 4 * 4);
	assert warpReadback3d(nativeTexture(volume), 0, 2, pixels[0], 4, 4) == 1;
	assert centreOf(pixels, 4) == BLUE;
	assert warpReadback3d(nativeTexture(volume), 0, 1, pixels[0], 4, 4) == 1;
	assert centreOf(pixels, 4) == 0;
	assert warpReadback3d(nativeTexture(volume), 0, 3, pixels[0], 4, 4) == 1;
	assert centreOf(pixels, 4) == 0;
	device.destroy();
}

test "a depth16unorm texture round-trips a buffer copy and a cleared depth32float copies out as a whole subresource" {
	const device = openDevice();
	const sixteen = device.createTexture({
		label: "depth16",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "depth16unorm",
		usage: (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	const upload = device.createBuffer({ label: "up", size: 1024, usage: (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32) });
	let values: Vec<uint16> = [];
	for (let row = 0; row < 4; row++) {
		for (let column = 0; column < 128; column++) { values.push(column < 4 ? ((row * 4 + column + 1) * 1000) as uint16 : 0); }
	}
	device.queue.writeBuffer(upload, 0, values);
	const download = readbackBuffer(device, 1024);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture({ buffer: upload, offset: 0, bytesPerRow: 256, rowsPerImage: 4 }, { texture: sixteen }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	encoder.copyTextureToBuffer({ texture: sixteen }, { buffer: download, offset: 0, bytesPerRow: 256, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.submit(encoder.finish());
	const read = readBack(download);
	assert (read[0] as uint32) + ((read[1] as uint32) << 8) == 1000;
	assert (read[256 + 6] as uint32) + ((read[256 + 7] as uint32) << 8) == 8000;
	assert (read[3 * 256 + 6] as uint32) + ((read[3 * 256 + 7] as uint32) << 8) == 16000;
	const depth = device.createTexture({
		label: "depth32",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "depth32float",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	let pass: GPURenderPassDescriptor = { label: "depth" };
	pass.depthStencilAttachment = { view: depth.createView({ label: null }), depthClearValue: 0.5, depthLoadOp: "clear", depthStoreOp: "store" };
	const second = device.createCommandEncoder();
	second.beginRenderPass(pass).end();
	const floats = readbackBuffer(device, 1024);
	second.copyTextureToBuffer({ texture: depth }, { buffer: floats, offset: 0, bytesPerRow: 256, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	device.queue.submit(second.finish());
	const bits = readBack(floats);
	assert bits[0] == 0 && bits[1] == 0 && bits[2] == 0 && bits[3] == 0x3F;
	assert bits[3 * 256 + 12] == 0 && bits[3 * 256 + 15] == 0x3F;
	device.destroy();
}

test "the swapchain texture copies out of the back buffer, resolved when it is multisampled" {
	const device = openDevice();
	const back = warpTarget(8, 8, 1);
	const backView = warpTargetView(back);
	const screen = getCurrentTexture({ width: 8, height: 8, sampleCount: 1, renderView: backView, resolveView: null, depthStencilView: null });
	const clear = device.createCommandEncoder();
	clear.beginRenderPass(clearingPass(screen.createView({ label: null }), { id: 0 })).end();
	const direct = readbackBuffer(device, 256 * 8);
	clear.copyTextureToBuffer({ texture: screen }, { buffer: direct, offset: 0, bytesPerRow: 256, rowsPerImage: 8 }, { width: 8, height: 8, depthOrArrayLayers: 1 });
	device.queue.submit(clear.finish());
	assert texelAt(readBack(direct), 256, 3, 3) == BLUE;
	const samples = warpTarget(8, 8, 4);
	const resolved = warpTarget(8, 8, 1);
	const multi = getCurrentTexture({ width: 8, height: 8, sampleCount: 4, renderView: warpTargetView(samples), resolveView: warpTargetView(resolved), depthStencilView: null });
	const frame = device.createCommandEncoder();
	frame.beginRenderPass(clearingPass(multi.createView({ label: null }), { id: 0 })).end();
	const copied = readbackBuffer(device, 256 * 8);
	frame.copyTextureToBuffer({ texture: multi }, { buffer: copied, offset: 0, bytesPerRow: 256, rowsPerImage: 8 }, { width: 8, height: 8, depthOrArrayLayers: 1 });
	device.queue.submit(frame.finish());
	assert texelAt(readBack(copied), 256, 7, 7) == BLUE;
	device.destroy();
}

test "the door reads a cleared bgra8 target back as RGBA and refuses a buffer of the wrong size" {
	doorSetup(warpDevice(), warpContext(), 2, 0, 1);
	const image = doorMakeTargetImage(8, 8, 4);
	const view = doorMakeAttachmentView(image, 4);
	doorBeginColorPass(view, 0.0, 0.0, 1.0, 1.0);
	doorEndPass();
	let out: Vec<uint8> = new Array(8 * 8 * 4);
	assert doorReadTexture(image, 0, 0, 8, 8, out) == 1;
	assert out[0] == 0 && out[1] == 0 && out[2] == 255 && out[3] == 255;
	assert out[8 * 8 * 4 - 4] == 0 && out[8 * 8 * 4 - 2] == 255;
	let wrong: Vec<uint8> = new Array(8 * 8 * 4 - 1);
	assert doorReadTexture(image, 0, 0, 8, 8, wrong) == 0;
	doorShutdown();
}
