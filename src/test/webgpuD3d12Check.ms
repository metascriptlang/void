import { GPUBuffer, GPUBufferUsage, GPUDevice, GPUMapMode } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { adapterDescription, drainDebugMessages, executedAllocator, frameAllocator, idleSerial, retiredCount } from "../webgpu/d3d12/backend.ms";
import { readBack, readbackBuffer } from "./webgpuFixtures.ms";

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
