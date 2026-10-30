import {
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUDevice,
	GPUMapMode,
	GPUShaderBinding,
	GPUShaderStage,
	GPUTexture,
	GPUTextureFormat,
	GPUTextureUsage,
} from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { adapterDescription, drainDebugMessages, executedAllocator, frameAllocator, idleSerial, retiredCount, samplerDescriptor, viewDescriptor } from "../webgpu/d3d12/backend.ms";
import { splitTextureCopy } from "../webgpu/d3d12/resources.ms";
import { newCursor, nextPair, serializeRootSignature, shaderLayout, tableEntries } from "../webgpu/d3d12/descriptor.ms";
import { dx12Release } from "../webgpu/d3d12/d3d12.h";
import { GREEN, RED, readBack, readbackBuffer, texelAt, texels } from "./webgpuFixtures.ms";

function openDevice(): GPUDevice {
	return requestDevice({
		device: null,
		context: null,
		colorFormat: "rgba8unorm",
		depthFormat: "depth32float",
		sampleCount: 1,
		warp: true,
		debug: true,
	});
}

function copyBuffer(device: GPUDevice, size: int64): GPUBuffer {
	return device.createBuffer({
		label: "copy",
		size: size,
		usage: (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
}

function copyAndSubmit(device: GPUDevice, source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToBuffer(source, sourceOffset, destination, destinationOffset, size);
	device.queue.submit(encoder.finish());
}

function counting(count: int32, step: int32): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (let i: int32 = 0; i < count; i++) { bytes.push(((i * step + 1) & 0xff) as uint8); }
	return bytes;
}

function submitEmpty(device: GPUDevice): void {
	const encoder = device.createCommandEncoder();
	device.queue.submit(encoder.finish());
}

test "a D3D12 device on WARP says d3d12 with a top-left origin and depth in zero to one" {
	const device = openDevice();
	const info = device.getAdapterInfo();
	const backend: string = info.backend;
	assert backend == "d3d12" && info.originTopLeft && info.depthZeroToOne;
	assert adapterDescription() == "Microsoft Basic Render Driver";
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "three empty submits complete serial 3, the third on allocator 0, with no debug-layer message" {
	const device = openDevice();
	submitEmpty(device);
	submitEmpty(device);
	submitEmpty(device);
	assert executedAllocator() == frameAllocator(0) && frameAllocator(0) != frameAllocator(1);
	assert idleSerial() == 3;
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "writeBuffer copied into a MAP_READ buffer maps back the same bytes" {
	const device = openDevice();
	const source = copyBuffer(device, 16);
	const destination = readbackBuffer(device, 16);
	const bytes: Vec<uint8> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
	device.queue.writeBuffer(source, 0, bytes);
	copyAndSubmit(device, source, 0, destination, 0, 16);
	const read = readBack(destination);
	assert read.length == 16;
	for (let i = 0; i < 16; i++) { assert read[i] == (i + 1) as uint8; }
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "one buffer written, copied and read back over two submits leaves the debug layer silent" {
	const device = openDevice();
	const source = copyBuffer(device, 16);
	const destination = readbackBuffer(device, 16);
	for (let round: int32 = 0; round < 2; round++) {
		const bytes = counting(16, round + 2);
		device.queue.writeBuffer(source, 0, bytes);
		copyAndSubmit(device, source, 0, destination, 0, 16);
		const read = readBack(destination);
		for (let i = 0; i < 16; i++) { assert read[i] == bytes[i]; }
	}
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "a buffer destroyed mid-frame is released only once its frame's serial completes" {
	const device = openDevice();
	const doomed = copyBuffer(device, 16);
	const bytes: Vec<uint8> = [1, 2, 3, 4];
	device.queue.writeBuffer(doomed, 0, bytes);
	assert retiredCount() == 0;
	doomed.destroy();
	assert retiredCount() == 1;
	submitEmpty(device);
	assert idleSerial() == 1 && retiredCount() == 0;
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "a MAP_WRITE buffer filled through writeMappedRange copies to a MAP_READ buffer" {
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
	copyAndSubmit(device, upload, 8, destination, 4, 8);
	const read = readBack(destination);
	for (let i = 0; i < 8; i++) { assert read[4 + i] == (9 - i) as uint8; }
	assert read[3] == 0 && read[12] == 0;
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "two writes of 300 and 40 bytes at offsets 20 and 400 copy back through one upload page" {
	const device = openDevice();
	const source = copyBuffer(device, 1024);
	const destination = readbackBuffer(device, 1024);
	const first = counting(300, 7);
	const second = counting(40, 3);
	device.queue.writeBuffer(source, 20, first);
	device.queue.writeBuffer(source, 400, second);
	copyAndSubmit(device, source, 0, destination, 0, 1024);
	const read = readBack(destination);
	for (let i = 0; i < 300; i++) { assert read[20 + i] == first[i]; }
	for (let i = 0; i < 40; i++) { assert read[400 + i] == second[i]; }
	assert read[19] == 0 && read[320] == 0 && read[440] == 0;
	assert drainDebugMessages() == 0;
	device.destroy();
}

function copyTexture(device: GPUDevice, width: int32, height: int32, layers: int32, mipLevels: int32, format: GPUTextureFormat): GPUTexture {
	return device.createTexture({
		label: "copy",
		size: { width: width, height: height, depthOrArrayLayers: layers },
		format: format,
		usage: (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
		mipLevelCount: mipLevels,
	});
}

function readTexture(device: GPUDevice, texture: GPUTexture, mipLevel: int32, layer: int32, width: int32, height: int32): Vec<uint8> {
	const destination = readbackBuffer(device, 256 * (height as int64));
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToBuffer(
		{ texture: texture, mipLevel: mipLevel, origin: { x: 0, y: 0, z: layer } },
		{ buffer: destination, offset: 0, bytesPerRow: 256, rowsPerImage: height },
		{ width: width, height: height, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	return readBack(destination);
}

function rowsMatch(read: Vec<uint8>, expected: Vec<uint8>, from: int32, pitch: int32, rowBytes: int32, rows: int32): boolean {
	for (let y = 0; y < rows; y++) {
		for (let x = 0; x < rowBytes; x++) {
			if (read[y * 256 + x] != expected[from + y * pitch + x]) { return false; }
		}
	}
	return true;
}

test "a copy 4 bytes past a 512 boundary keeps one region, and one straddling a 256-byte row splits at 512" {
	const near = splitTextureCopy(4, 4, 256, 0, 4, 2);
	assert near.length == 1 && near[0].alignedOffset == 0 && near[0].bufferX == 1 && near[0].bufferY == 0;
	assert near[0].bufferWidth == 5 && near[0].bufferHeight == 2;
	const straddling = splitTextureCopy(504, 4, 256, 4, 4, 2);
	assert straddling.length == 2;
	assert straddling[0].alignedOffset == 0 && straddling[0].bufferX == 62 && straddling[0].bufferY == 1;
	assert straddling[0].width == 2 && straddling[0].bufferWidth == 64 && straddling[0].bufferHeight == 3;
	assert straddling[1].alignedOffset == 512 && straddling[1].bufferX == 0 && straddling[1].bufferY == 0;
	assert straddling[1].textureX == 6 && straddling[1].width == 2 && straddling[1].bufferWidth == 2;
}

test "rgba8unorm texels written to mip 1 and to array layer 1 copy back at 256 bytes per row" {
	const device = openDevice();
	const texture = copyTexture(device, 8, 8, 2, 2, "rgba8unorm");
	const mipTexels = counting(4 * 4 * 4, 3);
	const layerTexels = counting(8 * 8 * 4, 5);
	device.queue.writeTexture(
		{ texture: texture, mipLevel: 1 },
		mipTexels,
		{ offset: 0, bytesPerRow: 16, rowsPerImage: 4 },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	device.queue.writeTexture(
		{ texture: texture, origin: { x: 0, y: 0, z: 1 } },
		layerTexels,
		{ offset: 0, bytesPerRow: 32, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	assert rowsMatch(readTexture(device, texture, 1, 0, 4, 4), mipTexels, 0, 16, 16, 4);
	assert rowsMatch(readTexture(device, texture, 0, 1, 8, 8), layerTexels, 0, 32, 32, 8);
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "a 3x2 writeTexture at 2,1 from a data offset fills that rectangle and leaves the zeroed rest" {
	const device = openDevice();
	const texture = copyTexture(device, 8, 4, 1, 1, "rgba8unorm");
	const data = counting(8 + 12 * 2, 7);
	device.queue.writeTexture(
		{ texture: texture, origin: { x: 2, y: 1, z: 0 } },
		data,
		{ offset: 8, bytesPerRow: 12, rowsPerImage: 2 },
		{ width: 3, height: 2, depthOrArrayLayers: 1 },
	);
	const read = readTexture(device, texture, 0, 0, 8, 4);
	for (let y = 0; y < 4; y++) {
		for (let x = 0; x < 32; x++) {
			const inside = y >= 1 && y < 3 && x >= 8 && x < 20;
			assert read[y * 256 + x] == (inside ? data[8 + (y - 1) * 12 + x - 8] : 0);
		}
	}
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "copyBufferToTexture from offsets 4 and 504 lands both regions, the second split at a 512 boundary" {
	const device = openDevice();
	const source = copyBuffer(device, 1024);
	const bytes = counting(1024, 1);
	device.queue.writeBuffer(source, 0, bytes);
	const texture = copyTexture(device, 8, 4, 1, 1, "rgba8unorm");
	const encoder = device.createCommandEncoder();
	encoder.copyBufferToTexture(
		{ buffer: source, offset: 4, bytesPerRow: 256, rowsPerImage: 2 },
		{ texture: texture },
		{ width: 4, height: 2, depthOrArrayLayers: 1 },
	);
	encoder.copyBufferToTexture(
		{ buffer: source, offset: 504, bytesPerRow: 256, rowsPerImage: 2 },
		{ texture: texture, origin: { x: 4, y: 2, z: 0 } },
		{ width: 4, height: 2, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readTexture(device, texture, 0, 0, 8, 4);
	for (let y = 0; y < 2; y++) {
		for (let x = 0; x < 16; x++) {
			assert read[y * 256 + x] == bytes[4 + y * 256 + x];
			assert read[(y + 2) * 256 + 16 + x] == bytes[504 + y * 256 + x];
			assert read[y * 256 + 16 + x] == 0 && read[(y + 2) * 256 + x] == 0;
		}
	}
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "copyTextureToTexture copies mip 1 of one texture into array layer 1 of another at 2,2" {
	const device = openDevice();
	const mips = copyTexture(device, 8, 8, 1, 2, "rgba8unorm");
	const layers = copyTexture(device, 8, 8, 2, 1, "rgba8unorm");
	device.queue.writeTexture(
		{ texture: mips, mipLevel: 1 },
		texels(0, 255, 0, 16),
		{ offset: 0, bytesPerRow: 16, rowsPerImage: 4 },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	device.queue.writeTexture(
		{ texture: layers, origin: { x: 0, y: 0, z: 1 } },
		texels(255, 0, 0, 64),
		{ offset: 0, bytesPerRow: 32, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToTexture(
		{ texture: mips, mipLevel: 1 },
		{ texture: layers, origin: { x: 2, y: 2, z: 1 } },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readTexture(device, layers, 0, 1, 8, 8);
	assert texelAt(read, 256, 1, 1) == RED && texelAt(read, 256, 6, 6) == RED;
	assert texelAt(read, 256, 2, 2) == GREEN && texelAt(read, 256, 5, 5) == GREEN;
	assert texelAt(readTexture(device, layers, 0, 0, 8, 8), 256, 3, 3) == 0;
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "rgba16float texels of 8 bytes round-trip through writeTexture and copyTextureToBuffer" {
	const device = openDevice();
	const texture = copyTexture(device, 4, 4, 1, 1, "rgba16float");
	let halves: Vec<uint16> = [];
	for (let i: int32 = 0; i < 64; i++) { halves.push((0x3c00 + i * 16) as uint16); }
	device.queue.writeTexture(
		{ texture: texture },
		halves,
		{ offset: 0, bytesPerRow: 32, rowsPerImage: 4 },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	const read = readTexture(device, texture, 0, 0, 4, 4);
	for (let y = 0; y < 4; y++) {
		for (let i = 0; i < 16; i++) {
			const half = halves[y * 16 + i];
			assert read[y * 256 + i * 2] == (half & 0xff) as uint8 && read[y * 256 + i * 2 + 1] == (half >> 8) as uint8;
		}
	}
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "one texture read, written and read again over three submits leaves the debug layer silent" {
	const device = openDevice();
	const texture = copyTexture(device, 4, 4, 1, 1, "rgba8unorm");
	const zeroed = readTexture(device, texture, 0, 0, 4, 4);
	for (let y = 0; y < 4; y++) {
		for (let x = 0; x < 16; x++) { assert zeroed[y * 256 + x] == 0; }
	}
	for (let round: int32 = 0; round < 2; round++) {
		const bytes = counting(64, round + 2);
		device.queue.writeTexture(
			{ texture: texture },
			bytes,
			{ offset: 0, bytesPerRow: 16, rowsPerImage: 4 },
			{ width: 4, height: 4, depthOrArrayLayers: 1 },
		);
		assert rowsMatch(readTexture(device, texture, 0, 0, 4, 4), bytes, 0, 16, 16, 4);
	}
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "copyTextureToTexture copies mip 1 into a region of mip 0" {
	const device = openDevice();
	const texture = copyTexture(device, 8, 8, 1, 2, "rgba8unorm");
	device.queue.writeTexture(
		{ texture: texture },
		texels(255, 0, 0, 64),
		{ offset: 0, bytesPerRow: 32, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	device.queue.writeTexture(
		{ texture: texture, mipLevel: 1 },
		texels(0, 255, 0, 16),
		{ offset: 0, bytesPerRow: 16, rowsPerImage: 4 },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
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
	assert texelAt(read, 256, 1, 1) == RED;
	assert texelAt(read, 256, 2, 2) == GREEN;
	assert texelAt(read, 256, 5, 5) == GREEN;
	assert texelAt(read, 256, 6, 6) == RED;
	assert texelAt(read, 256, 2, 6) == RED;
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "copyTextureToTexture copies array layer 0 into a region of array layer 1 of the same texture" {
	const device = openDevice();
	const texture = copyTexture(device, 8, 8, 2, 1, "rgba8unorm");
	device.queue.writeTexture(
		{ texture: texture },
		texels(0, 255, 0, 64),
		{ offset: 0, bytesPerRow: 32, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	device.queue.writeTexture(
		{ texture: texture, origin: { x: 0, y: 0, z: 1 } },
		texels(255, 0, 0, 64),
		{ offset: 0, bytesPerRow: 32, rowsPerImage: 8 },
		{ width: 8, height: 8, depthOrArrayLayers: 1 },
	);
	const encoder = device.createCommandEncoder();
	encoder.copyTextureToTexture(
		{ texture: texture },
		{ texture: texture, origin: { x: 2, y: 2, z: 1 } },
		{ width: 4, height: 4, depthOrArrayLayers: 1 },
	);
	device.queue.submit(encoder.finish());
	const read = readTexture(device, texture, 0, 1, 8, 8);
	assert texelAt(read, 256, 1, 1) == RED;
	assert texelAt(read, 256, 2, 2) == GREEN;
	assert texelAt(read, 256, 5, 5) == GREEN;
	assert texelAt(read, 256, 6, 6) == RED;
	assert texelAt(read, 256, 2, 6) == RED;
	assert texelAt(readTexture(device, texture, 0, 0, 8, 8), 256, 6, 6) == GREEN;
	assert drainDebugMessages() == 0;
	device.destroy();
}

test "a second sampler with the same descriptor reuses the first one's CPU descriptor, and a different one does not" {
	const device = openDevice();
	const texture = device.createTexture({
		label: "sampled",
		size: { width: 2, height: 2, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.TEXTURE_BINDING as int32) | (GPUTextureUsage.COPY_DST as int32),
		sampleCount: 1,
	});
	const view = texture.createView({ label: null });
	const nearest = device.createSampler({ label: "nearest", magFilter: "nearest", minFilter: "nearest" });
	const again = device.createSampler({ label: "again", magFilter: "nearest", minFilter: "nearest" });
	const linear = device.createSampler({ label: "linear", magFilter: "linear", minFilter: "linear" });
	assert viewDescriptor(view) != 0 && samplerDescriptor(nearest) != 0;
	assert samplerDescriptor(again) == samplerDescriptor(nearest) && samplerDescriptor(linear) != samplerDescriptor(nearest);
	assert drainDebugMessages() == 0;
	device.destroy();
}

function binding(group: int32, binding: int32, kind: GPUShaderBinding["kind"], visibility: int32, nativeSlot: int32): GPUShaderBinding {
	return { group: group, binding: binding, kind: kind, visibility: visibility, size: 0, nativeSlot: nativeSlot };
}

function twoUniformsAndATexture(): GPUShaderBinding[] {
	const both = (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);
	return [
		binding(0, 0, "uniform", both, 0),
		binding(0, 1, "uniform", GPUShaderStage.FRAGMENT as int32, 1),
		binding(1, 0, "texture", both, 0),
		binding(1, 1, "sampler", both, 1),
	];
}

test "a texture and sampler visible to both stages fill the vertex and the pixel tables with the same entries" {
	const layout = shaderLayout(twoUniformsAndATexture(), false);
	assert layout.uniforms.length == 2 && layout.tables.length == 4;
	let descriptor: GPUBindGroupDescriptor = { label: "resources", layout: { id: 0 } };
	descriptor.entries[0] = { binding: 1, sampler: { id: 3 } };
	descriptor.entries[1] = { binding: 0, textureView: { id: 5 } };
	const tables = tableEntries(layout, 1, descriptor);
	assert layout.tables[0].stage == (GPUShaderStage.VERTEX as int32) && !layout.tables[0].samplers && tables[0].entries[0] == 1;
	assert layout.tables[1].stage == (GPUShaderStage.VERTEX as int32) && layout.tables[1].samplers && tables[1].entries[0] == 0;
	assert layout.tables[2].stage == (GPUShaderStage.FRAGMENT as int32) && !layout.tables[2].samplers && tables[2].entries[0] == 1;
	assert layout.tables[3].stage == (GPUShaderStage.FRAGMENT as int32) && layout.tables[3].samplers && tables[3].entries[0] == 0;
}

test "the root signature for two uniform blocks and a texture with its sampler serializes" {
	const serialized = serializeRootSignature(shaderLayout(twoUniformsAndATexture(), false));
	assert serialized.ok && serialized.value.bytes > 0;
	dx12Release(serialized.value.blob);
}

test "five groups of 3 views and a sampler switch to a fresh visible heap pair 3 times when a pair holds 8 views" {
	let cursor = newCursor(8, 4);
	let switches: int32 = 0;
	for (let group: int32 = 0; group < 5; group++) {
		if (!cursor.fits(3, 1)) {
			nextPair(cursor, 3, 1);
			switches += 1;
		}
		cursor.views += 3;
		cursor.samplers += 1;
	}
	assert switches == 3 && cursor.pair == 2;
}
