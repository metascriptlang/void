import { GPUBuffer, GPUBufferUsage, GPUDevice } from "../webgpu/types.ms";
import "../webgpu/device.ms";
import { openTestDevice } from "./testDevice";
import { readBack, readbackBuffer } from "./webgpuFixtures";

when (voidDummy) {
	const SOURCE_USAGE = (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32);

	function copiedBack(device: GPUDevice, source: GPUBuffer, size: int64): Vec<uint8> {
		const target = readbackBuffer(device, size);
		const encoder = device.createCommandEncoder();
		encoder.copyBufferToBuffer(source, 0, target, 0, size);
		device.queue.submit(encoder.finish());
		return readBack(target);
	}

	test "the dummy device keeps the little-endian bytes of what writeBuffer takes" {
		const device = openTestDevice();
		const source = device.createBuffer({ label: "source", size: 32, usage: SOURCE_USAGE });
		const floats: Vec<float32> = [1.0, -2.5];
		const shorts: Vec<uint16> = [0x0102, 0xFFFE];
		const ints: Vec<int32> = [-2, 0x01020304];
		device.queue.writeBuffer(source, 0, floats);
		device.queue.writeBuffer(source, 8, shorts);
		device.queue.writeBuffer(source, 12, ints);
		const bytes = copiedBack(device, source, 32);
		const expected: uint8[] = [
			0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x20, 0xC0,
			0x02, 0x01, 0xFE, 0xFF,
			0xFE, 0xFF, 0xFF, 0xFF, 0x04, 0x03, 0x02, 0x01,
		];
		for (let i = 0; i < expected.length; i++) { assert bytes[i] == expected[i]; }
		for (let i = expected.length; i < 32; i++) { assert bytes[i] == 0; }
	}

	test "a copy at an offset moves the bytes and leaves the rest" {
		const device = openTestDevice();
		const source = device.createBuffer({ label: "source", size: 16, usage: SOURCE_USAGE });
		const bytes: Vec<uint8> = [1, 2, 3, 4, 5, 6, 7, 8];
		device.queue.writeBuffer(source, 4, bytes);
		const target = readbackBuffer(device, 16);
		const encoder = device.createCommandEncoder();
		encoder.copyBufferToBuffer(source, 8, target, 4, 4);
		device.queue.submit(encoder.finish());
		const read = readBack(target);
		const expected: uint8[] = [0, 0, 0, 0, 5, 6, 7, 8, 0, 0];
		for (let i = 0; i < expected.length; i++) { assert read[i] == expected[i]; }
	}
}
