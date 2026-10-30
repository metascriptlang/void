import { GPUDevice } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { adapterDescription, drainDebugMessages, executedAllocator, frameAllocator, idleSerial } from "../webgpu/d3d12/backend.ms";

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
