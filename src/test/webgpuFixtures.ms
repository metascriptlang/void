import {
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPULoadOp,
	GPUMapMode,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUShaderModule,
	GPUTexture,
	GPUTextureUsage,
	GPUTextureView,
	GPU_UNIFORM_GROUP,
} from "../webgpu/types.ms";
import "../webgpu/device.ms";

export const SIZE = 64;
export const BLUE: uint32 = 0x0000FFFF;
export const RED: uint32 = 0xFF0000FF;
export const GREEN: uint32 = 0x00FF00FF;

export function colourUniforms(device: GPUDevice): GPUBuffer {
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

export function vertexBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "vertices",
		size: size,
		usage: (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
}

export function colourTarget(device: GPUDevice, sampleCount: int32): GPUTexture {
	return device.createTexture({
		label: "target",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: sampleCount,
	});
}

export function drawOverLoadedStencil(device: GPUDevice, tester: GPURenderPipeline, target: GPUTexture, depthLoadOp: GPULoadOp = "clear"): void {
	const vertices = vertexBuffer(device, 32);
	const full: Vec<float32> = [-1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0];
	device.queue.writeBuffer(vertices, 0, full);
	const depth = device.createTexture({
		label: "depth stencil",
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: "depth24plus-stencil8",
		usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
		sampleCount: 1,
	});
	let first = clearingPass(target.createView({ label: null }), { id: 0 });
	first.depthStencilAttachment = {
		view: depth.createView({ label: null }),
		depthClearValue: 1.0,
		depthLoadOp: depthLoadOp,
		depthStoreOp: "store",
		stencilClearValue: 1,
		stencilLoadOp: "clear",
		stencilStoreOp: "store",
	};
	let second = first;
	second.depthStencilAttachment.stencilLoadOp = "load";
	const encoder = device.createCommandEncoder();
	encoder.beginRenderPass(first).end();
	const pass = encoder.beginRenderPass(second);
	const green: Vec<uint32> = [256];
	pass.setStencilReference(1);
	pass.setPipeline(tester);
	pass.setVertexBuffer(0, vertices, 0);
	pass.setBindGroup(GPU_UNIFORM_GROUP, uniformGroup(device, tester, colourUniforms(device)), green);
	pass.draw(4, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
}

export function drawMaskedTriangle(device: GPUDevice, module: GPUShaderModule, writeMask: int32 | null, target: GPUTexture): void {
	let descriptor: GPURenderPipelineDescriptor = { label: "masked" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.fragment.targets[0].writeMask = writeMask;
	const pipeline = device.createRenderPipeline(descriptor);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	drawTriangleIn(device, pipeline, pass);
	pass.end();
	device.queue.submit(encoder.finish());
}

// Two indirect records in one call: the left triangle in instance 1's colour, then the right one
// reached only through firstIndex 3 and baseVertex 3, in instance 2's colour.
export function drawIndirectRows(device: GPUDevice, module: GPUShaderModule, target: GPUTexture): void {
	let descriptor: GPURenderPipelineDescriptor = { label: "indirect rows" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.vertex.buffers[1].arrayStride = 4;
	descriptor.vertex.buffers[1].stepMode = "instance";
	descriptor.vertex.buffers[1].attributes[0] = { format: "unorm8x4", offset: 0, shaderLocation: 1 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(descriptor);
	const positions = vertexBuffer(device, 72);
	const corners: Vec<float32> = [-1.0, -1.0, 0.0, -1.0, -1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 1.0, 0.0, 1.0];
	device.queue.writeBuffer(positions, 0, corners);
	const colours = vertexBuffer(device, 12);
	const rows: Vec<uint8> = [0, 0, 0, 255, 0, 255, 0, 255, 255, 0, 0, 255];
	device.queue.writeBuffer(colours, 0, rows);
	const indices = device.createBuffer({
		label: "indirect indices",
		size: 12,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order: Vec<uint16> = [0, 1, 2, 3, 4, 5];
	device.queue.writeBuffer(indices, 0, order);
	const records = device.createBuffer({
		label: "indirect records",
		size: 40,
		usage: (GPUBufferUsage.INDIRECT as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const draws: Vec<uint32> = [3, 1, 0, 0, 1, 3, 1, 3, 3, 2];
	device.queue.writeBuffer(records, 0, draws);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, positions, 0);
	pass.setVertexBuffer(1, colours, 0);
	pass.setIndexBuffer(indices, "uint16", 0);
	pass.multiDrawIndexedIndirect(records, 0, 2);
	pass.end();
	device.queue.submit(encoder.finish());
}

export function clearingPass(view: GPUTextureView, resolve: GPUTextureView): GPURenderPassDescriptor {
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

export function pixel(pixels: Vec<uint8>, x: int32, y: int32): uint32 {
	const at = (y * SIZE + x) * 4;
	return ((pixels[at] as uint32) << 24) | ((pixels[at + 1] as uint32) << 16) |
		((pixels[at + 2] as uint32) << 8) | (pixels[at + 3] as uint32);
}

export function texels(red: uint8, green: uint8, blue: uint8, count: int32): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(count * 4);
	for (let i = 0; i < count; i++) {
		bytes[i * 4] = red;
		bytes[i * 4 + 1] = green;
		bytes[i * 4 + 2] = blue;
		bytes[i * 4 + 3] = 255;
	}
	return bytes;
}

export function readBack(buffer: GPUBuffer): Vec<uint8> {
	buffer.mapAsync(GPUMapMode.READ as int32, 0, 0);
	const bytes = buffer.getMappedRange(0, 0);
	buffer.unmap();
	return bytes;
}

export function readbackBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "readback",
		size: size,
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
}

export function texelAt(bytes: Vec<uint8>, bytesPerRow: int32, x: int32, y: int32): uint32 {
	const at = y * bytesPerRow + x * 4;
	return ((bytes[at] as uint32) << 24) | ((bytes[at + 1] as uint32) << 16) | ((bytes[at + 2] as uint32) << 8) | (bytes[at + 3] as uint32);
}

export function resolveBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "resolved",
		size: size,
		usage: (GPUBufferUsage.QUERY_RESOLVE as int32) | (GPUBufferUsage.COPY_SRC as int32),
	});
}

export function readCounters(device: GPUDevice, resolved: GPUBuffer, count: int32): Vec<uint64> {
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

export function drawTriangleIn(device: GPUDevice, pipeline: GPURenderPipeline, pass: GPURenderPassEncoder): void {
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

export function uniformGroupAt(device: GPUDevice, pipeline: GPURenderPipeline, uniforms: GPUBuffer, offset: int64): GPUBindGroup {
	let descriptor: GPUBindGroupDescriptor = { label: "colours", layout: pipeline.getBindGroupLayout(0) };
	descriptor.entries[0] = { binding: 0, buffer: uniforms, offset: offset, size: 16 };
	return device.createBindGroup(descriptor);
}

export function uniformGroup(device: GPUDevice, pipeline: GPURenderPipeline, uniforms: GPUBuffer): GPUBindGroup {
	return uniformGroupAt(device, pipeline, uniforms, 0);
}
