import { GPUBufferUsage, GPUShaderModule, GPUShaderModuleDescriptor, GPURenderPipeline, GPURenderPipelineDescriptor, GPURenderPassDescriptor, GPUTextureUsage } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { metalSystemDevice } from "./metalDevice.h";

@compile("./metalDevice.m");

const INSTANCE_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nvertex Out vinst(uint v [[vertex_id]], uint i [[instance_id]]) { Out out; out.position = float4(float(v & 1) - 0.5, float(v >> 1) - 0.5, 0.0, 1.0 + float(i)); return out; }\nfragment float4 finst() { return float4(0.0, 1.0, 0.0, 1.0); }\n";

const device = requestDevice({ device: metalSystemDevice(), context: null, colorFormat: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 });
let shader: GPUShaderModuleDescriptor = { label: "instance", vertexCode: INSTANCE_MSL, vertexEntryPoint: "vinst", fragmentCode: INSTANCE_MSL, fragmentEntryPoint: "finst" };
const unflagged = device.createShaderModule(shader);
shader.readsInstanceIndex = true;
const flagged = device.createShaderModule(shader);

function pipelineOf(module: GPUShaderModule, label: string): GPURenderPipeline {
	let descriptor: GPURenderPipelineDescriptor = { label: label };
	descriptor.vertex.module = module;
	descriptor.fragment.module = module;
	descriptor.fragment.targets[0].format = "rgba8unorm";
	return device.createRenderPipeline(descriptor);
}

const ignores = pipelineOf(unflagged, "ignores instance");
const reads = pipelineOf(flagged, "reads instance");
const indices = device.createBuffer({ label: "indices", size: 8, usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32) });
device.queue.writeBuffer(indices, 0, [0, 1, 2, 0] as Vec<uint16>);
const target = device.createTexture({
	label: "target",
	size: { width: 8, height: 8, depthOrArrayLayers: 1 },
	format: "rgba8unorm",
	usage: GPUTextureUsage.RENDER_ATTACHMENT as int32,
});
let passDescriptor: GPURenderPassDescriptor = { label: "pass" };
passDescriptor.colorAttachments[0] = { view: target.createView({ label: null }), resolveTarget: { id: 0 }, clearValue: { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }, loadOp: "clear", storeOp: "store" };
const encoder = device.createCommandEncoder();
const pass = encoder.beginRenderPass(passDescriptor);
pass.setIndexBuffer(indices, "uint16", 0);
pass.setPipeline(ignores);
pass.draw(3, 1, 0, 1);
pass.drawIndexed(3, 1, 0, 0, 1);
pass.setPipeline(reads);
pass.draw(3, 2, 0, 0);
pass.drawIndexed(3, 2, 0, 0, 0);
console.log("probe: the controls drew");
when (firstInstanceIndexed) {
	pass.drawIndexed(3, 1, 0, 0, 1);
} else {
	pass.draw(3, 1, 0, 1);
}
console.log("probe: firstInstance 1 drew");
