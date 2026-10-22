import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPU_NO_QUERY_INDEX,
	GPUMapMode,
	GPURenderPassEncoder,
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
import { DUMMY_SAMPLER_BINDING, nativeTexture, bindStats } from "../webgpu/gl/backend.ms";
import { glWindowError, glWindowOpen, glWindowReadback } from "./glWindow.h";

@passL("-lopengl32");
@passL("-lgdi32");
@passL("-luser32");

const SIZE = 64;
const BLUE: uint32 = 0x0000FFFF;
const RED: uint32 = 0xFF0000FF;
const GREEN: uint32 = 0x00FF00FF;
const WHITE: uint32 = 0xFFFFFFFF;

const VERTEX_GLSL = "#version 430\nlayout(location = 0) in vec2 position;\nvoid main() { gl_Position = vec4(position, 0.0, 1.0); }\n";
const FRAGMENT_GLSL = "#version 430\nuniform vec4 params[1];\nlayout(location = 0) out vec4 frag_color;\nvoid main() { frag_color = params[0]; }\n";
const TEXTURED_VERTEX_GLSL = "#version 430\nlayout(location = 0) in vec2 position;\nout vec2 uv;\nvoid main() { gl_Position = vec4(position, 0.0, 1.0); uv = position * 0.5 + 0.5; }\n";
const TEXTURED_FRAGMENT_GLSL = "#version 430\nlayout(binding = 0) uniform sampler2D tex_smp;\nin vec2 uv;\nlayout(location = 0) out vec4 frag_color;\nvoid main() { frag_color = texture(tex_smp, uv); }\n";
const DUMMY_FRAGMENT_GLSL = "#version 430
layout(binding = 0) uniform sampler2D tex_SPIRV_Cross_DummySampler;
in vec2 uv;
layout(location = 0) out vec4 frag_color;
void main() { frag_color = texelFetch(tex_SPIRV_Cross_DummySampler, ivec2(uv * 2.0), 0); }
";

function stopOnGl(message: string): void {
	console.log(`webgpuGlCheck: ${message}`);
	unreachable;
}

function openDevice(): GPUDevice {
	if (glWindowOpen() != 1) {
		const error: string = glWindowError();
		stopOnGl(error);
	}
	return requestDevice({
		device: null,
		context: null,
		colorFormat: "rgba8unorm",
		depthFormat: "depth32float",
		sampleCount: 1,
	});
}

function flatShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "flat",
		vertexCode: VERTEX_GLSL,
		vertexEntryPoint: "",
		fragmentCode: FRAGMENT_GLSL,
		fragmentEntryPoint: "",
	};
	descriptor.bindings[0] = { group: 0, binding: 0, kind: "uniform", stage: "fragment", size: 16, nativeSlot: -1, nativeName: "params", textureBinding: -1 };
	descriptor.attributes[0] = { location: 0, nativeName: "position", semanticIndex: 0 };
	return device.createShaderModule(descriptor);
}

function texturedShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "textured",
		vertexCode: TEXTURED_VERTEX_GLSL,
		vertexEntryPoint: "",
		fragmentCode: TEXTURED_FRAGMENT_GLSL,
		fragmentEntryPoint: "",
	};
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "texture", stage: "fragment", size: 0, sampleType: "float", nativeSlot: -1, textureBinding: -1 };
	descriptor.bindings[1] = { group: 1, binding: 32, kind: "sampler", stage: "fragment", size: 0, samplerType: "filtering", nativeSlot: -1, nativeName: "tex_smp", textureBinding: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: "position", semanticIndex: 0 };
	return device.createShaderModule(descriptor);
}

function dummySamplerShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "dummy sampler",
		vertexCode: TEXTURED_VERTEX_GLSL,
		vertexEntryPoint: "",
		fragmentCode: DUMMY_FRAGMENT_GLSL,
		fragmentEntryPoint: "",
	};
	descriptor.bindings[0] = { group: 1, binding: 0, kind: "texture", stage: "fragment", size: 0, sampleType: "unfilterable-float", nativeSlot: -1, textureBinding: -1 };
	descriptor.bindings[1] = { group: 1, binding: DUMMY_SAMPLER_BINDING, kind: "sampler", stage: "fragment", size: 0, samplerType: "non-filtering", nativeSlot: -1, nativeName: "tex_SPIRV_Cross_DummySampler", textureBinding: 0 };
	descriptor.attributes[0] = { location: 0, nativeName: "position", semanticIndex: 0 };
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

function fullScreenQuad(device: GPUDevice): GPUBuffer {
	const vertices = vertexBuffer(device, 48);
	const quad: Vec<float32> = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	return vertices;
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

function readPixelsBottomUp(texture: GPUTexture): Vec<uint8> {
	let pixels: Vec<uint8> = new Array(SIZE * SIZE * 4);
	if (glWindowReadback(nativeTexture(texture), pixels[0], SIZE, SIZE) != 1) { stopOnGl("the glReadPixels readback failed"); }
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
	return readPixelsBottomUp(readTexture);
}

test "a GL triangle takes its colour from the uniform block at the dynamic offset" {
	const device = openDevice();
	assert device.getAdapterInfo().originTopLeft == false;
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
	const pixels = readPixelsBottomUp(target);
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

test "a texture-sampler pair samples the last write of a 2x2 texture, row 0 at uv v = 0" {
	const device = openDevice();
	const module = texturedShader(device);
	let pipelineDescriptor: GPURenderPipelineDescriptor = { label: "textured" };
	pipelineDescriptor.vertex.module = module;
	pipelineDescriptor.vertex.buffers[0].arrayStride = 8;
	pipelineDescriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	pipelineDescriptor.fragment.module = module;
	pipelineDescriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(pipelineDescriptor);
	const texture = device.createTexture({
		label: "checker",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	const grey: Vec<uint8> = [9, 9, 9, 255, 9, 9, 9, 255, 9, 9, 9, 255, 9, 9, 9, 255];
	const checker: Vec<uint8> = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255];
	device.queue.writeTexture({ texture: texture }, grey, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	device.queue.writeTexture({ texture: texture }, checker, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	const sampler = device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" });
	let groupDescriptor: GPUBindGroupDescriptor = { label: "checker", layout: pipeline.getBindGroupLayout(1) };
	groupDescriptor.entries[0] = { binding: 0, textureView: texture.createView({ label: null }) };
	groupDescriptor.entries[1] = { binding: 32, sampler: sampler };
	const group = device.createBindGroup(groupDescriptor);
	const vertices = fullScreenQuad(device);
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
	const pixels = readPixelsBottomUp(target);
	assert pixel(pixels, 16, 16) == RED;
	assert pixel(pixels, 48, 16) == GREEN;
	assert pixel(pixels, 16, 48) == BLUE;
	assert pixel(pixels, 48, 48) == WHITE;
	device.destroy();
}

test "a texel-fetching stage binds the backend dummy sampler, which has no bind group entry" {
	const device = openDevice();
	const module = dummySamplerShader(device);
	let pipelineDescriptor: GPURenderPipelineDescriptor = { label: "dummy sampler" };
	pipelineDescriptor.vertex.module = module;
	pipelineDescriptor.vertex.buffers[0].arrayStride = 8;
	pipelineDescriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	pipelineDescriptor.fragment.module = module;
	pipelineDescriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(pipelineDescriptor);
	const texture = device.createTexture({
		label: "checker",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	const checker: Vec<uint8> = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255];
	device.queue.writeTexture({ texture: texture }, checker, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	let groupDescriptor: GPUBindGroupDescriptor = { label: "checker", layout: pipeline.getBindGroupLayout(1) };
	groupDescriptor.entries[0] = { binding: 0, textureView: texture.createView({ label: null }) };
	const group = device.createBindGroup(groupDescriptor);
	const vertices = fullScreenQuad(device);
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
	const pixels = readPixelsBottomUp(target);
	assert pixel(pixels, 16, 16) == RED;
	assert pixel(pixels, 48, 16) == GREEN;
	assert pixel(pixels, 16, 48) == BLUE;
	assert pixel(pixels, 48, 48) == WHITE;
	device.destroy();
}

test "a top-left scissor rect covers the top rows, which GL stores last" {
	const device = openDevice();
	const module = flatShader(device);
	const pipeline = flatPipeline(device, module, 1);
	const uniforms = colourUniforms(device);
	const group = uniformGroup(device, pipeline, uniforms);
	const vertices = fullScreenQuad(device);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(0, group, offsets);
	pass.setScissorRect(0, 0, 32, 32);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readPixelsBottomUp(target);
	assert pixel(pixels, 16, 48) == RED;
	assert pixel(pixels, 16, 16) == BLUE;
	assert pixel(pixels, 48, 48) == BLUE;
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
	const pixels = readPixelsBottomUp(texture);
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

test "a bind that did not change issues no native call, and a texture rotation or a new pass issues one" {
	const device = openDevice();
	const module = texturedShader(device);
	let pipelineDescriptor: GPURenderPipelineDescriptor = { label: "textured" };
	pipelineDescriptor.vertex.module = module;
	pipelineDescriptor.vertex.buffers[0].arrayStride = 8;
	pipelineDescriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	pipelineDescriptor.fragment.module = module;
	pipelineDescriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(pipelineDescriptor);
	const texture = device.createTexture({
		label: "rotating",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	const texel: Vec<uint8> = [255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255];
	device.queue.writeTexture({ texture: texture }, texel, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	const sampler: GPUSampler = device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" });
	let groupDescriptor: GPUBindGroupDescriptor = { label: "rotating", layout: pipeline.getBindGroupLayout(1) };
	groupDescriptor.entries[0] = { binding: 0, textureView: texture.createView({ label: null }) };
	groupDescriptor.entries[1] = { binding: 32, sampler: sampler };
	const group = device.createBindGroup(groupDescriptor);
	const vertices = fullScreenQuad(device);
	const target = colourTarget(device, 1);
	const view = target.createView({ label: null });
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	let pass = encoder.beginRenderPass(clearingPass(view, { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(1, group, noOffsets);
	pass.draw(6, 1, 0, 0);
	const first = bindStats();
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(1, group, noOffsets);
	pass.draw(6, 1, 0, 0);
	let now = bindStats();
	assert now.vertexBuffers == first.vertexBuffers && now.indexBuffers == first.indexBuffers;
	assert now.shaderResources == first.shaderResources && now.samplers == first.samplers;
	device.queue.writeTexture({ texture: texture }, texel, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	const beforeRotation = bindStats();
	pass.draw(6, 1, 0, 0);
	now = bindStats();
	assert now.shaderResources > beforeRotation.shaderResources;
	assert now.vertexBuffers == beforeRotation.vertexBuffers;
	pass.end();
	device.queue.submit(encoder.finish());
	device.destroy();
}

test "a mipped texture takes a write into mip 1 and a view of that mip is a render attachment" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "mips",
		size: { width: 8, height: 8, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		mipLevelCount: 3,
	});
	const texel: Vec<uint8> = new Array(64);
	device.queue.writeTexture({ texture: texture, mipLevel: 1 }, texel, { offset: 0, bytesPerRow: 16, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	const mip1 = texture.createView({ label: null, baseMipLevel: 1, mipLevelCount: 1 });
	assert mip1.id != 0;
	device.destroy();
}

test "a six-layer texture is a cube map and writes one face per layer" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "cube",
		size: { width: 2, height: 2, depthOrArrayLayers: 6 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
	});
	const texel: Vec<uint8> = new Array(96);
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 2 } }, texel, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 2 });
	const cube = texture.createView({ label: null, dimension: "cube" });
	assert cube.id != 0;
	device.destroy();
}

test "a 3d texture takes a slice write and a 3d view" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "volume",
		size: { width: 2, height: 2, depthOrArrayLayers: 2 },
		dimension: "3d",
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
	});
	const texel: Vec<uint8> = new Array(16);
	device.queue.writeTexture({ texture: texture, origin: { x: 0, y: 0, z: 1 } }, texel, { offset: 0, bytesPerRow: 8, rowsPerImage: 2 }, { width: 2, height: 2, depthOrArrayLayers: 1 });
	assert texture.createView({ label: null }).id != 0;
	device.destroy();
}

test "setViewport, setBlendConstant and setStencilReference run inside a pass" {
	const device = openDevice();
	const target = colourTarget(device, 1);
	const view = target.createView({ label: null });
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(view, { id: 0 }));
	pass.setViewport(0, 0, SIZE / 2, SIZE, 0, 1);
	pass.setBlendConstant({ r: 1, g: 0, b: 0, a: 1 });
	pass.setStencilReference(1);
	pass.end();
	device.queue.submit(encoder.finish());
	device.destroy();
}

function texels(red: uint8, green: uint8, blue: uint8, count: int32): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(count * 4);
	for (let i = 0; i < count; i++) {
		bytes[i * 4] = red;
		bytes[i * 4 + 1] = green;
		bytes[i * 4 + 2] = blue;
		bytes[i * 4 + 3] = 255;
	}
	return bytes;
}


function readBack(buffer: GPUBuffer): Vec<uint8> {
	buffer.mapAsync(GPUMapMode.READ as int32, 0, 0);
	const bytes = buffer.getMappedRange(0, 0);
	buffer.unmap();
	return bytes;
}

function readbackBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "readback",
		size: size,
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
}

function texelAt(bytes: Vec<uint8>, bytesPerRow: int32, x: int32, y: int32): uint32 {
	const at = y * bytesPerRow + x * 4;
	return ((bytes[at] as uint32) << 24) | ((bytes[at + 1] as uint32) << 16) | ((bytes[at + 2] as uint32) << 8) | (bytes[at + 3] as uint32);
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

const DOUBLE_GLSL = "#version 430\nlayout(local_size_x = 4) in;\nlayout(std430, binding = 0) buffer Data { uint data[]; };\nvoid main() { data[gl_GlobalInvocationID.x] *= 2u; }\n";
const FILL_GLSL = "#version 430\nlayout(local_size_x = 4, local_size_y = 4) in;\nlayout(r32ui, binding = 0) writeonly uniform uimage2D image;\nvoid main() { imageStore(image, ivec2(gl_GlobalInvocationID.xy), uvec4(gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * 10u)); }\n";
const STORAGE_FRAGMENT_GLSL = "#version 430\nlayout(std430, binding = 0) readonly buffer Colors { vec4 colors[]; };\nlayout(location = 0) out vec4 frag_color;\nvoid main() { frag_color = colors[0]; }\n";

function computeModule(device: GPUDevice, code: string, kind: string, workgroupX: int32, workgroupY: int32): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = { label: "compute", computeCode: code, computeEntryPoint: "" };
	descriptor.workgroupSize = [workgroupX, workgroupY, 1];
	if (kind == "storage-buffer") {
		descriptor.bindings[0] = { group: 1, binding: 0, kind: "storage-buffer", stage: "compute", bufferType: "storage", nativeSlot: 0 };
	} else {
		descriptor.bindings[0] = {
			group: 1,
			binding: 0,
			kind: "storage-texture",
			stage: "compute",
			storageAccess: "write-only",
			storageFormat: "r32uint",
			nativeSlot: 0,
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
	const module = computeModule(device, DOUBLE_GLSL, "storage-buffer", 4, 1);
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

test "a compute pass writes a storage texture that copies back" {
	const device = openDevice();
	const module = computeModule(device, FILL_GLSL, "storage-texture", 4, 4);
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
		vertexCode: VERTEX_GLSL,
		vertexEntryPoint: "",
		fragmentCode: STORAGE_FRAGMENT_GLSL,
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
	descriptor.attributes[0] = { location: 0, nativeName: "position", semanticIndex: 0 };
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
	const pixels = readPixelsBottomUp(target);
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == RED;
	device.destroy();
}

test "the limits are the context's own and the features say what the context can do" {
	const device = openDevice();
	const limits = device.limits();
	assert limits.maxTextureDimension1D > 0 && limits.maxTextureDimension2D >= 8192 && limits.maxTextureDimension3D >= 256;
	assert limits.maxTextureArrayLayers >= 256 && limits.maxBindGroups == 2;
	assert limits.maxSampledTexturesPerShaderStage > 0 && limits.maxSamplersPerShaderStage > 0;
	assert limits.maxStorageBuffersPerShaderStage > 0 && limits.maxStorageTexturesPerShaderStage > 0;
	assert limits.maxUniformBuffersPerShaderStage > 0 && limits.maxUniformBufferBindingSize >= 16384;
	assert limits.maxStorageBufferBindingSize > 0 && limits.maxVertexBuffers > 0 && limits.maxVertexAttributes >= 16;
	assert limits.maxColorAttachments >= 4 && limits.maxComputeWorkgroupSizeX >= 1024 && limits.maxComputeWorkgroupSizeY >= 1024;
	assert limits.maxComputeWorkgroupSizeZ >= 64 && limits.maxComputeInvocationsPerWorkgroup >= 1024;
	assert limits.maxComputeWorkgroupsPerDimension >= 65535;
	assert limits.minUniformBufferOffsetAlignment == 256 && limits.minStorageBufferOffsetAlignment == 256;
	const features = device.features();
	assert features.has("timestamp-query") && features.has("float32-filterable") && features.has("rg11b10ufloat-renderable");
	assert !features.has("texture-compression-bc") && !features.has("depth32float-stencil8") && !features.has("shader-f16");
	device.destroy();
}

test "labels and debug groups balance across an encoder, a render pass and a compute pass" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "labelled texture",
		size: { width: 4, height: 4, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
	});
	assert texture.width() == 4;
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

function resolveBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "resolved",
		size: size,
		usage: (GPUBufferUsage.QUERY_RESOLVE as int32) | (GPUBufferUsage.COPY_SRC as int32),
	});
}

function readCounters(device: GPUDevice, resolved: GPUBuffer, count: int32): Vec<uint64> {
	const readback = readbackBuffer(device, (count as int64) * 8);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(resolved, 0, readback, 0, (count as int64) * 8);
	device.queue.submit(encoder.finish());
	const bytes = readBack(readback);
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
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const offsets: Vec<uint32> = [0];
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(0, uniformGroup(device, pipeline, uniforms), offsets);
	pass.draw(3, 1, 0, 0);
}

test "two timestamps around a render pass and around a compute pass resolve to non-decreasing nanoseconds" {
	const device = openDevice();
	const set = device.createQuerySet({ label: "timing", type: "timestamp", count: 4 });
	const pipeline = flatPipeline(device, flatShader(device), 1);
	const target = colourTarget(device, 1);
	let descriptor = clearingPass(target.createView({ label: null }), { id: 0 });
	descriptor.timestampWrites = { querySet: set, beginningOfPassWriteIndex: 0, endOfPassWriteIndex: 1 };
	let encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(descriptor);
	drawTriangleIn(device, pipeline, pass);
	pass.end();
	const module = computeModule(device, DOUBLE_GLSL, "storage-buffer", 4, 1);
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
	const pipeline = flatPipeline(device, flatShader(device), 1);
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
