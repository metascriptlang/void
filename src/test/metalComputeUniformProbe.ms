import { GPUBindGroupDescriptor, GPUBufferUsage } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { glslComputeIr } from "../shader/emit";
import { metalSystemDevice } from "./metalDevice.h";
import { scaledKernel, shadyComputeDescriptor } from "./metalShadyCompute";

@compile("./metalDevice.m");

const device = requestDevice({ device: metalSystemDevice(), context: null, colorFormat: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 });
const pipeline = device.createComputePipeline({
	label: "scaled",
	compute: { module: device.createShaderModule(shadyComputeDescriptor("scaled", glslComputeIr(scaledKernel, [32, 1, 1]))), entryPoint: "main0" },
});
const storage = (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32);
const params = device.createBuffer({ label: "params", size: 256, usage: (GPUBufferUsage.UNIFORM as int32) | (GPUBufferUsage.COPY_DST as int32) });
const xs = device.createBuffer({ label: "xs", size: 128, usage: storage });
const ks = device.createBuffer({ label: "ks", size: 128, usage: storage });
const cells = device.createBuffer({ label: "cells", size: 384, usage: storage });
let uniformEntries: GPUBindGroupDescriptor = { label: "uniforms", layout: pipeline.getBindGroupLayout(0) };
uniformEntries.entries[0] = { binding: 0, buffer: params, offset: 0, size: 16 };
let resourceEntries: GPUBindGroupDescriptor = { label: "resources", layout: pipeline.getBindGroupLayout(1) };
resourceEntries.entries[0] = { binding: 0, buffer: xs };
resourceEntries.entries[1] = { binding: 1, buffer: ks };
resourceEntries.entries[2] = { binding: 2, buffer: cells };
const uniforms = device.createBindGroup(uniformEntries);
const resources = device.createBindGroup(resourceEntries);
const encoder = device.createCommandEncoder();
const pass = encoder.beginComputePass({ label: null });
pass.setPipeline(pipeline);
pass.setBindGroup(0, uniforms, [0] as Vec<uint32>);
pass.setBindGroup(1, resources, [] as Vec<uint32>);
pass.dispatchWorkgroups(1, 1, 1);
console.log("probe: the control dispatched");
when (overrun) {
	pass.setBindGroup(0, uniforms, [256] as Vec<uint32>);
} else {
	pass.setBindGroup(0, { id: 0 }, [] as Vec<uint32>);
}
pass.dispatchWorkgroups(1, 1, 1);
console.log("probe: the faulty dispatch ran");
