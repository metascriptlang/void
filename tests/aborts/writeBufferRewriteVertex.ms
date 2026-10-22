// expect: rewrites bytes this frame already wrote, up to 16
import { GPUBufferUsage } from "../../src/webgpu/types.ms";
import { requestDevice } from "../../src/webgpu/device.ms";
import { warpDevice, warpContext } from "../../src/test/d3d11Warp.h";

@passL("-ld3d11");

const device = requestDevice({
	device: warpDevice(),
	context: warpContext(),
	colorFormat: "rgba8unorm",
	depthFormat: "depth32float",
	sampleCount: 1,
});
const buffer = device.createBuffer({ label: "rewritten", size: 512, usage: (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.COPY_DST as int32) });
const first: Vec<float32> = [1.0, 0.0, 0.0, 1.0];
const second: Vec<float32> = [0.0, 1.0];
device.queue.writeBuffer(buffer, 0, first);
device.queue.writeBuffer(buffer, 8, second);
console.log("a second write over bytes the frame already wrote returned");
