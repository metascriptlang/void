// expect: rewrites bytes this frame already wrote, up to 16
import { GPUBufferUsage } from "../../src/webgpu/types.ms";
import "../../src/webgpu/device.ms";
import { openTestDevice } from "../../src/test/testDevice";

const device = openTestDevice();
const buffer = device.createBuffer({ label: "rewritten", size: 512, usage: (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.COPY_DST as int32) });
const first: Vec<float32> = [1.0, 0.0, 0.0, 1.0];
const second: Vec<float32> = [0.0, 1.0];
device.queue.writeBuffer(buffer, 0, first);
device.queue.writeBuffer(buffer, 8, second);
console.log("a second write over bytes the frame already wrote returned");
