import {
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPUMapMode,
	GPURenderPassDescriptor,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUTexture,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
} from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import {
	vulkanAdapterSelect,
	vulkanDeviceCreate,
	vulkanError,
	vulkanInstanceCreate,
	vulkanLoaderOpen,
	vulkanShutdown,
	vulkanValidationErrors,
} from "../webgpu/vulkan/vulkan.h";
import {
	BLUE,
	GREEN,
	RED,
	SIZE,
	clearingPass,
	colourTarget,
	colourUniforms,
	drawIndirectRows,
	drawMaskedTriangle,
	drawOverLoadedStencil,
	pixel,
	readBack,
	readbackBuffer,
	texelAt,
	texels,
	uniformGroup,
	vertexBuffer,
} from "./webgpuFixtures.ms";
import { spirvColoured, spirvCompute, spirvFlat, spirvTextured, spirvTint } from "./vulkanSpirv.ms";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_POWER_HIGH: int32 = 2;
const WHITE: uint32 = 0xFFFFFFFF;
const BLACK: uint32 = 0x000000FF;
const ROW = SIZE * 4;
const TINT_BLOCK = 32;

function openDevice(): GPUDevice {
	if (vulkanLoaderOpen() != 0 || vulkanInstanceCreate() != 0 || vulkanAdapterSelect(VULKAN_POWER_HIGH) != 0 || vulkanDeviceCreate() != 0) {
		console.log(`webgpuVulkanCheck: ${vulkanError()}`);
		unreachable;
	}
	return requestDevice({
		device: null,
		context: null,
		colorFormat: "rgba8unorm",
		depthFormat: "depth32float",
		sampleCount: 1,
	});
}

function validationErrorsAfterClose(device: GPUDevice): int32 {
	device.destroy();
	vulkanShutdown();
	return vulkanValidationErrors();
}

function flatShader(device: GPUDevice): GPUShaderModule {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "flat",
		vertexEntryPoint: "vs",
		fragmentEntryPoint: "fs",
		vertexBytecode: spirvFlat(),
		fragmentBytecode: spirvFlat(),
	};
	descriptor.bindings[0] = { group: GPU_UNIFORM_GROUP, binding: 0, kind: "uniform", visibility: GPUShaderStage.FRAGMENT as int32, size: 16 };
	return device.createShaderModule(descriptor);
}

function colouredShader(device: GPUDevice): GPUShaderModule {
	return device.createShaderModule({
		label: "coloured",
		vertexEntryPoint: "vs",
		fragmentEntryPoint: "fs",
		vertexBytecode: spirvColoured(),
		fragmentBytecode: spirvColoured(),
	});
}

function flatPipeline(device: GPUDevice, sampleCount: int32): GPURenderPipeline {
	const module = flatShader(device);
	let descriptor: GPURenderPipelineDescriptor = { label: "flat" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.multisample.count = sampleCount;
	return device.createRenderPipeline(descriptor);
}

function stencilTester(device: GPUDevice): GPURenderPipeline {
	const module = flatShader(device);
	let descriptor: GPURenderPipelineDescriptor = { label: "stencil equal" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	descriptor.primitive.topology = "triangle-strip";
	descriptor.depthStencil.format = "depth24plus-stencil8";
	descriptor.depthStencil.depthCompare = "always";
	descriptor.depthStencil.stencilFront = { compare: "equal", passOp: "keep" };
	descriptor.depthStencil.stencilBack = { compare: "equal", passOp: "keep" };
	return device.createRenderPipeline(descriptor);
}

function readTexture(device: GPUDevice, texture: GPUTexture): Vec<uint8> {
	const destination = readbackBuffer(device, ROW * SIZE);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: texture },
		{ buffer: destination, offset: 0, bytesPerRow: ROW, rowsPerImage: SIZE },
		{ width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	return readBack(destination);
}

function drawTriangle(device: GPUDevice, sampleCount: int32, dynamicOffset: uint32): Vec<uint8> {
	const pipeline = flatPipeline(device, sampleCount);
	const group = uniformGroup(device, pipeline, colourUniforms(device));
	const vertices = vertexBuffer(device, 24);
	const triangle: Vec<float32> = [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5];
	device.queue.writeBuffer(vertices, 0, triangle);
	const target = colourTarget(device, sampleCount);
	let resolved = target;
	let resolveView: GPUTextureView = { id: 0 };
	if (sampleCount > 1) {
		resolved = colourTarget(device, 1);
		resolveView = resolved.createView({ label: null });
	}
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), resolveView));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const offsets: Vec<uint32> = [dynamicOffset];
	pass.setBindGroup(GPU_UNIFORM_GROUP, group, offsets);
	pass.draw(3, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	return readTexture(device, resolved);
}

function words(values: Readonly<Span<int32>>): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const value of values) {
		const bits = value as uint32;
		for (let shift: uint32 = 0; shift < 32; shift += 8) { bytes.push(((bits >> shift) & 0xFF) as uint8); }
	}
	return bytes;
}

function wordAt(bytes: Vec<uint8>, i: int32): uint32 {
	let value: uint32 = 0;
	for (let b = 3; b >= 0; b--) { value = (value << 8) | (bytes[i * 4 + b] as uint32); }
	return value;
}

test "a Vulkan triangle takes its colour from the uniform block at the dynamic offset" {
	const device = openDevice();
	assert device.getAdapterInfo().originTopLeft && device.getAdapterInfo().depthZeroToOne;
	const pixels = drawTriangle(device, 1, 256);
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == GREEN;
	assert pixel(pixels, 63, 63) == BLUE;
	const live = device.liveCounts();
	assert live.buffers == 3 && live.textures == 1 && live.views == 1 && live.shaderModules == 1 && live.pipelines == 1;
	assert validationErrorsAfterClose(device) == 0;
}

test "a colour target with writeMask 0 keeps its clear colour where an omitted mask takes the triangle" {
	const device = openDevice();
	const target = colourTarget(device, 1);
	drawMaskedTriangle(device, flatShader(device), 0, target);
	assert pixel(readTexture(device, target), 32, 32) == BLUE;
	drawMaskedTriangle(device, flatShader(device), null, target);
	assert pixel(readTexture(device, target), 32, 32) == RED;
	assert validationErrorsAfterClose(device) == 0;
}

test "two indexed indirect records in one call honour firstIndex, baseVertex and firstInstance" {
	const device = openDevice();
	const target = colourTarget(device, 1);
	drawIndirectRows(device, colouredShader(device), target);
	const pixels = readTexture(device, target);
	assert pixel(pixels, 2, 32) == GREEN;
	assert pixel(pixels, 61, 32) == RED;
	assert pixel(pixels, 32, 32) == BLUE;
	assert validationErrorsAfterClose(device) == 0;
}

test "a stencil cleared to 1 and stored is loaded by the next pass while that pass clears its depth" {
	const device = openDevice();
	const target = colourTarget(device, 1);
	drawOverLoadedStencil(device, stencilTester(device), target);
	const pixels = readTexture(device, target);
	assert pixel(pixels, 0, 0) == GREEN && pixel(pixels, 63, 63) == GREEN;
	assert validationErrorsAfterClose(device) == 0;
}

test "a 4x multisampled target resolves into its single-sample resolve target" {
	const device = openDevice();
	const pixels = drawTriangle(device, 4, 0);
	assert pixel(pixels, 0, 0) == BLUE;
	assert pixel(pixels, 32, 32) == RED;
	assert validationErrorsAfterClose(device) == 0;
}

test "back-face-culled ccw quads take one uniform group at three dynamic offsets, drawn, indexed and in a top-right viewport" {
	const device = openDevice();
	let shader: GPUShaderModuleDescriptor = {
		label: "tint",
		vertexEntryPoint: "vs",
		fragmentEntryPoint: "fs",
		vertexBytecode: spirvTint(),
		fragmentBytecode: spirvTint(),
	};
	shader.bindings[0] = {
		group: GPU_UNIFORM_GROUP,
		binding: 0,
		kind: "uniform",
		visibility: (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32),
		size: TINT_BLOCK,
	};
	const module = device.createShaderModule(shader);
	let descriptor: GPURenderPipelineDescriptor = { label: "tint" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "sint32x2", offset: 0, shaderLocation: 0 };
	descriptor.primitive.frontFace = "ccw";
	descriptor.primitive.cullMode = "back";
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(descriptor);
	const vertices = vertexBuffer(device, 48);
	const quad: int32[12] = [-1, 0, 0, 0, 0, 1, -1, 0, 0, 1, -1, 1];
	device.queue.writeBuffer(vertices, 0, words(quad));
	const indices = device.createBuffer({
		label: "indices",
		size: 12,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order: Vec<uint16> = [0, 1, 2, 3, 4, 5];
	device.queue.writeBuffer(indices, 0, order);
	const tints = device.createBuffer({
		label: "tints",
		size: 512 + TINT_BLOCK,
		usage: (GPUBufferUsage.UNIFORM as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const red: int32[8] = [255, 0, 0, 255, 0, 0, 0, 0];
	const blue: int32[8] = [0, 0, 255, 255, 1, -1, 0, 0];
	const green: int32[8] = [0, 255, 0, 255, 0, 0, 0, 0];
	device.queue.writeBuffer(tints, 0, words(red));
	device.queue.writeBuffer(tints, 256, words(blue));
	device.queue.writeBuffer(tints, 512, words(green));
	let entries: GPUBindGroupDescriptor = { label: "tints", layout: pipeline.getBindGroupLayout(GPU_UNIFORM_GROUP) };
	entries.entries[0] = { binding: 0, buffer: tints, offset: 0, size: TINT_BLOCK };
	const group = device.createBindGroup(entries);
	const target = colourTarget(device, 1);
	let pass: GPURenderPassDescriptor = { label: "tint" };
	pass.colorAttachments[0] = {
		view: target.createView({ label: null }),
		resolveTarget: { id: 0 },
		clearValue: { r: 0.0, g: 0.0, b: 0.0, a: 1.0 },
		loadOp: "clear",
		storeOp: "store",
	};
	const encoder = device.createCommandEncoder();
	const render = encoder.beginRenderPass(pass);
	render.setPipeline(pipeline);
	render.setVertexBuffer(0, vertices, 0);
	const first: Vec<uint32> = [0];
	render.setBindGroup(GPU_UNIFORM_GROUP, group, first);
	render.draw(6, 1, 0, 0);
	const second: Vec<uint32> = [256];
	render.setBindGroup(GPU_UNIFORM_GROUP, group, second);
	render.setIndexBuffer(indices, "uint16", 0);
	render.drawIndexed(6, 1, 0, 0, 0);
	const third: Vec<uint32> = [512];
	render.setBindGroup(GPU_UNIFORM_GROUP, group, third);
	render.setViewport((SIZE / 2) as float32, 0.0, (SIZE / 2) as float32, (SIZE / 2) as float32, 0.0, 1.0);
	render.draw(6, 1, 0, 0);
	render.end();
	device.queue.submit(encoder.finish());
	const pixels = readTexture(device, target);
	assert pixel(pixels, 8, 8) == RED && pixel(pixels, 24, 24) == RED;
	assert pixel(pixels, 40, 40) == BLUE && pixel(pixels, 56, 56) == BLUE;
	assert pixel(pixels, 40, 8) == GREEN && pixel(pixels, 56, 8) == BLACK && pixel(pixels, 40, 24) == BLACK;
	assert pixel(pixels, 8, 40) == BLACK;
	assert validationErrorsAfterClose(device) == 0;
}

test "a vertex buffer written after the draw was recorded holds that write when the draw runs" {
	const device = openDevice();
	const pipeline = flatPipeline(device, 1);
	const group = uniformGroup(device, pipeline, colourUniforms(device));
	const vertices = vertexBuffer(device, 128);
	const quad: Vec<float32> = [-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5];
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
	pass.setVertexBuffer(0, vertices, 64);
	pass.setIndexBuffer(indices, "uint16", 0);
	const offsets: Vec<uint32> = [0];
	pass.setBindGroup(GPU_UNIFORM_GROUP, group, offsets);
	pass.drawIndexed(6, 1, 0, 0, 0);
	pass.end();
	device.queue.writeBuffer(vertices, 64, quad);
	device.queue.submit(encoder.finish());
	const pixels = readTexture(device, target);
	assert pixel(pixels, 4, 4) == BLUE;
	assert pixel(pixels, 20, 20) == RED && pixel(pixels, 44, 44) == RED && pixel(pixels, 20, 44) == RED;
	assert pixel(pixels, 60, 32) == BLUE;
	assert validationErrorsAfterClose(device) == 0;
}

test "a queue write into a MAP_READ buffer lands before a mapAsync that follows it without a submit" {
	const device = openDevice();
	const destination = readbackBuffer(device, 16);
	const bytes: Vec<uint8> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
	device.queue.writeBuffer(destination, 0, bytes);
	const read = readBack(destination);
	for (let i = 0; i < 16; i++) { assert read[i] == (i + 1) as uint8; }
	assert validationErrorsAfterClose(device) == 0;
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
	assert validationErrorsAfterClose(device) == 0;
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
	assert validationErrorsAfterClose(device) == 0;
}

test "a 1000-byte buffer and a 13x7 texture written at a 56-byte pitch round trip byte for byte" {
	const device = openDevice();
	let bufferBytes: Vec<uint8> = new Array(1000);
	for (let i = 0; i < 1000; i++) { bufferBytes[i] = ((i * 7 + 3) % 251) as uint8; }
	const stored = device.createBuffer({
		label: "stored",
		size: 1000,
		usage: (GPUBufferUsage.COPY_DST as int32) | (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.VERTEX as int32),
	});
	device.queue.writeBuffer(stored, 0, bufferBytes);
	const pitch = 14 * 4;
	let source: Vec<uint8> = new Array(pitch * 7);
	for (let y = 0; y < 7; y++) {
		for (let x = 0; x < pitch; x++) { source[y * pitch + x] = ((y * 31 + x * 5 + 1) % 253) as uint8; }
	}
	const texture = device.createTexture({
		label: "odd",
		size: { width: 13, height: 7, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32),
		sampleCount: 1,
	});
	device.queue.writeTexture({ texture: texture }, source, { offset: 0, bytesPerRow: pitch, rowsPerImage: 7 }, { width: 13, height: 7, depthOrArrayLayers: 1 });
	const bufferBack = readbackBuffer(device, 1000);
	const texelsBack = readbackBuffer(device, 256 * 7);
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(stored, 0, bufferBack, 0, 1000);
	encoder.copyTextureToBuffer(
		{ texture: texture },
		{ buffer: texelsBack, offset: 0, bytesPerRow: 256, rowsPerImage: 7 },
		{ width: 13, height: 7, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const readBuffer = readBack(bufferBack);
	for (let i = 0; i < 1000; i++) { assert readBuffer[i] == bufferBytes[i]; }
	const readTexels = readBack(texelsBack);
	for (let y = 0; y < 7; y++) {
		for (let x = 0; x < 13 * 4; x++) { assert readTexels[y * 256 + x] == source[y * pitch + x]; }
	}
	assert validationErrorsAfterClose(device) == 0;
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
	assert validationErrorsAfterClose(device) == 0;
}

function clearTarget(device: GPUDevice, format: GPUTextureFormat): GPUTexture {
	return device.createTexture({
		label: format,
		size: { width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		format: format,
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
}

test "unorm, uint and depth targets clear, a later pass loads them, and each copies back byte for byte" {
	const device = openDevice();
	const unorm = clearTarget(device, "rgba8unorm");
	const integer = clearTarget(device, "rgba8uint");
	const depth = clearTarget(device, "depth32float");
	const unormView = unorm.createView({ label: null });
	const encoder = device.createCommandEncoder();
	let first: GPURenderPassDescriptor = { label: "clear" };
	first.colorAttachments[0] = { view: unormView, resolveTarget: { id: 0 }, clearValue: { r: 0.2, g: 0.6, b: 1.0, a: 1.0 }, loadOp: "clear", storeOp: "store" };
	first.depthStencilAttachment.view = depth.createView({ label: null });
	first.depthStencilAttachment.depthLoadOp = "clear";
	first.depthStencilAttachment.depthStoreOp = "store";
	first.depthStencilAttachment.depthClearValue = 0.5;
	encoder.beginRenderPass(first).end();
	let second: GPURenderPassDescriptor = { label: "load" };
	second.colorAttachments[0] = { view: unormView, resolveTarget: { id: 0 }, clearValue: { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }, loadOp: "load", storeOp: "store" };
	second.colorAttachments[1] = { view: integer.createView({ label: null }), resolveTarget: { id: 0 }, clearValue: { r: 7, g: 8, b: 9, a: 10 }, loadOp: "clear", storeOp: "store" };
	encoder.beginRenderPass(second).end();
	encoder.beginRenderPass(second).end();
	const readbacks: Vec<GPUBuffer> = [readbackBuffer(device, ROW * SIZE), readbackBuffer(device, ROW * SIZE), readbackBuffer(device, ROW * SIZE)];
	const targets: Vec<GPUTexture> = [unorm, integer, depth];
	for (let i = 0; i < 3; i++) {
		encoder.copyTextureToBuffer(
			{ texture: targets[i] },
			{ buffer: readbacks[i], offset: 0, bytesPerRow: ROW, rowsPerImage: SIZE },
			{ width: SIZE, height: SIZE, depthOrArrayLayers: 1 },
		);
	}
	device.queue.submit(encoder.finish());
	const loaded = readBack(readbacks[0]);
	const integers = readBack(readbacks[1]);
	const half = readBack(readbacks[2]);
	for (let y = 0; y < SIZE; y++) {
		for (let x = 0; x < SIZE; x++) {
			assert texelAt(loaded, ROW, x, y) == 0x3399FFFF;
			assert texelAt(integers, ROW, x, y) == 0x0708090A;
			assert texelAt(half, ROW, x, y) == 0x0000003F;
		}
	}
	assert validationErrorsAfterClose(device) == 0;
}

test "copyTextureToTexture copies mip 1 into a region of mip 0 of another texture" {
	const device = openDevice();
	const mips = device.createTexture({
		label: "mips",
		size: { width: 8, height: 8, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
		mipLevelCount: 2,
	});
	const canvas = device.createTexture({
		label: "canvas",
		size: { width: 8, height: 8, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
	});
	device.queue.writeTexture({ texture: canvas }, texels(255, 0, 0, 64), { offset: 0, bytesPerRow: 32, rowsPerImage: 8 }, { width: 8, height: 8, depthOrArrayLayers: 1 });
	device.queue.writeTexture({ texture: mips, mipLevel: 1 }, texels(0, 255, 0, 16), { offset: 0, bytesPerRow: 16, rowsPerImage: 4 }, { width: 4, height: 4, depthOrArrayLayers: 1 });
	const destination = readbackBuffer(device, 256 * 8);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToTexture(
		{ texture: mips, mipLevel: 1 },
		{ texture: canvas, origin: { x: 2, y: 2, z: 0 } },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	encoder.copyTextureToBuffer(
		{ texture: canvas },
		{ buffer: destination, offset: 0, bytesPerRow: 256, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readBack(destination);
	assert texelAt(read, 256, 1, 1) == RED;
	assert texelAt(read, 256, 2, 2) == GREEN && texelAt(read, 256, 5, 5) == GREEN;
	assert texelAt(read, 256, 6, 6) == RED && texelAt(read, 256, 2, 6) == RED;
	assert validationErrorsAfterClose(device) == 0;
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
	assert validationErrorsAfterClose(device) == 0;
}

test "a texture-sampler pair samples the last write of a 2x2 texture, row 0 at uv v = 0" {
	const device = openDevice();
	let shader: GPUShaderModuleDescriptor = {
		label: "textured",
		vertexEntryPoint: "vs",
		fragmentEntryPoint: "fs",
		vertexBytecode: spirvTextured(),
		fragmentBytecode: spirvTextured(),
	};
	shader.bindings[0] = { group: GPU_RESOURCE_GROUP, binding: 0, kind: "texture", visibility: GPUShaderStage.FRAGMENT as int32, sampleType: "float" };
	shader.bindings[1] = { group: GPU_RESOURCE_GROUP, binding: 1, kind: "sampler", visibility: GPUShaderStage.FRAGMENT as int32, samplerType: "filtering" };
	const module = device.createShaderModule(shader);
	let descriptor: GPURenderPipelineDescriptor = { label: "textured" };
	descriptor.vertex.module = module;
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	const pipeline = device.createRenderPipeline(descriptor);
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
	let entries: GPUBindGroupDescriptor = { label: "checker", layout: pipeline.getBindGroupLayout(GPU_RESOURCE_GROUP) };
	entries.entries[0] = { binding: 0, textureView: texture.createView({ label: null }) };
	entries.entries[1] = { binding: 1, sampler: device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" }) };
	const group = device.createBindGroup(entries);
	const vertices = vertexBuffer(device, 48);
	const quad: Vec<float32> = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0];
	device.queue.writeBuffer(vertices, 0, quad);
	const target = colourTarget(device, 1);
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertices, 0);
	const noOffsets: Vec<uint32> = [];
	pass.setBindGroup(GPU_RESOURCE_GROUP, group, noOffsets);
	pass.draw(6, 1, 0, 0);
	pass.end();
	device.queue.submit(encoder.finish());
	const pixels = readTexture(device, target);
	assert pixel(pixels, 16, 48) == RED;
	assert pixel(pixels, 48, 48) == GREEN;
	assert pixel(pixels, 16, 16) == BLUE;
	assert pixel(pixels, 48, 16) == WHITE;
	assert validationErrorsAfterClose(device) == 0;
}

test "a compute pass triples-plus-one 256 elements twice, the second dispatch indirect and reading the first's output" {
	const device = openDevice();
	let shader: GPUShaderModuleDescriptor = { label: "triple", computeEntryPoint: "main", computeBytecode: spirvCompute() };
	shader.workgroupSize = [64, 1, 1];
	shader.bindings[0] = { group: GPU_RESOURCE_GROUP, binding: 0, kind: "storage-buffer", visibility: GPUShaderStage.COMPUTE as int32, bufferType: "read-only-storage" };
	shader.bindings[1] = { group: GPU_RESOURCE_GROUP, binding: 1, kind: "storage-buffer", visibility: GPUShaderStage.COMPUTE as int32, bufferType: "storage" };
	const pipeline = device.createComputePipeline({ label: "triple", compute: { module: device.createShaderModule(shader), entryPoint: "main" } });
	const usage = (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32);
	const input = device.createBuffer({ label: "input", size: 1024, usage: usage });
	const middle = device.createBuffer({ label: "middle", size: 1024, usage: usage });
	const output = device.createBuffer({ label: "output", size: 1024, usage: usage });
	let values: Vec<uint32> = [];
	for (let i = 0; i < 256; i++) { values.push(i as uint32); }
	device.queue.writeBuffer(input, 0, values);
	const arguments = device.createBuffer({
		label: "arguments",
		size: 12,
		usage: (GPUBufferUsage.INDIRECT as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const counts: Vec<uint32> = [4, 1, 1];
	device.queue.writeBuffer(arguments, 0, counts);
	let firstEntries: GPUBindGroupDescriptor = { label: "first", layout: pipeline.getBindGroupLayout(GPU_RESOURCE_GROUP) };
	firstEntries.entries[0] = { binding: 0, buffer: input };
	firstEntries.entries[1] = { binding: 1, buffer: middle };
	let secondEntries: GPUBindGroupDescriptor = { label: "second", layout: pipeline.getBindGroupLayout(GPU_RESOURCE_GROUP) };
	secondEntries.entries[0] = { binding: 0, buffer: middle };
	secondEntries.entries[1] = { binding: 1, buffer: output };
	const readback = readbackBuffer(device, 1024);
	const noOffsets: Vec<uint32> = [];
	const encoder = device.createCommandEncoder();
	const pass = encoder.beginComputePass({ label: null });
	pass.setPipeline(pipeline);
	pass.setBindGroup(GPU_RESOURCE_GROUP, device.createBindGroup(firstEntries), noOffsets);
	pass.dispatchWorkgroups(4, 1, 1);
	pass.setBindGroup(GPU_RESOURCE_GROUP, device.createBindGroup(secondEntries), noOffsets);
	pass.dispatchWorkgroupsIndirect(arguments, 0);
	pass.end();
	encoder.copyBufferToBuffer(output, 0, readback, 0, 1024);
	device.queue.submit(encoder.finish());
	const read = readBack(readback);
	for (let i = 0; i < 256; i++) { assert wordAt(read, i) == ((i as uint32) * 3 + 1) * 3 + 1; }
	assert validationErrorsAfterClose(device) == 0;
}

test "the limits are the adapter's within Void's ceilings and the features say what its formats can do" {
	const device = openDevice();
	const limits = device.limits();
	assert limits.maxTextureDimension2D >= 4096 && limits.maxTextureDimension3D >= 256 && limits.maxTextureArrayLayers >= 256;
	assert limits.maxBindGroups == 2 && limits.maxColorAttachments >= 4 && limits.maxVertexAttributes >= 16;
	assert limits.maxUniformBufferBindingSize >= 16384 && limits.maxStorageBufferBindingSize >= 134217728;
	assert limits.maxComputeWorkgroupSizeX >= 256 && limits.maxComputeInvocationsPerWorkgroup >= 256;
	assert limits.maxComputeWorkgroupsPerDimension >= 65535;
	assert limits.minUniformBufferOffsetAlignment <= 256 && limits.minStorageBufferOffsetAlignment <= 256;
	const features = device.features();
	assert !features.has("timestamp-query") && !features.has("texture-compression-bc");
	assert validationErrorsAfterClose(device) == 0;
}

test "labels and debug groups balance across an encoder, a render pass and a compute pass" {
	const device = openDevice();
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
	assert pixel(readTexture(device, target), 5, 5) == BLUE;
	assert validationErrorsAfterClose(device) == 0;
}
