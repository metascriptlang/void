import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPURenderPassDescriptor,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUTexture,
	GPUTextureUsage,
	GPUTextureView,
} from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { nativeTexture } from "../webgpu/gl/backend.ms";
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
