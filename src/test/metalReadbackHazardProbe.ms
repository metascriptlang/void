import { GPUBufferUsage, GPUMapMode } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { metalSystemDevice } from "./metalDevice.h";

@compile("./metalDevice.m");

const device = requestDevice({ device: metalSystemDevice(), context: null, colorFormat: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 });
const source = device.createBuffer({ label: "source", size: 16, usage: (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32) });
device.queue.writeBuffer(source, 0, [1, 2, 3, 4] as Vec<int32>);
const read = device.createBuffer({ label: "read", size: 16, usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32) });
const encoder = device.createCommandEncoder();
encoder.copyBufferToBuffer(source, 0, read, 0, 16);
read.mapAsync(GPUMapMode.READ as int32, 0, 0);
console.log("probe: mapAsync returned with the frame's command buffer open");
