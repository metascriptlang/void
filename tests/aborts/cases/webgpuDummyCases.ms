// flags: -d:voidDummy
// expect stripIndexMismatch: an indexed strip draw needs primitive.stripIndexFormat equal to the setIndexBuffer format
// expect indirectWithoutUsage: dispatchWorkgroupsIndirect: GPUBuffer 65537 was created without INDIRECT
// expect shaderDestroyed: the shader module of GPURenderPipeline 65537 was destroyed
import { argv } from "std/process";
import {
	GPUBindGroupDescriptor,
	GPUBufferUsage,
	GPUComputePipelineDescriptor,
	GPURenderPipelineDescriptor,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUTextureView,
} from "../../../src/webgpu/types.ms";
import "../../../src/webgpu/device.ms";
import { openTestDevice } from "../../../src/test/testDevice";
import {
	clearingPass,
	colourTarget,
	colourUniforms,
	vertexBuffer,
} from "../../../src/test/webgpuFixtures.ms";

function run(name: string): void {
	const device = openTestDevice();
	const encoder = device.createCommandEncoder();
	if (name == "indirectWithoutUsage") {
		let kd: GPUShaderModuleDescriptor = {
			label: "kernel",
			computeCode: "k",
			computeEntryPoint: "main",
		};
		kd.workgroupSize = [1, 1, 1];
		let cd: GPUComputePipelineDescriptor = { label: "kernel" };
		cd.compute.module = device.createShaderModule(kd);
		const pipeline = device.createComputePipeline(cd);
		const usage = (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32);
		const args = device.createBuffer({ label: "args", size: 16, usage: usage });
		const pass = encoder.beginComputePass({ label: "dispatch" });
		pass.setPipeline(pipeline);
		pass.dispatchWorkgroupsIndirect(args, 0);
		console.log("an indirect dispatch from a buffer without INDIRECT returned");
		return;
	}
	if (name != "stripIndexMismatch" && name != "shaderDestroyed") {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	let sd: GPUShaderModuleDescriptor = {
		label: "flat",
		vertexCode: "v",
		vertexEntryPoint: "vmain",
		fragmentCode: "f",
		fragmentEntryPoint: "fmain",
	};
	sd.bindings[0] = {
		group: 0,
		binding: 0,
		kind: "uniform",
		visibility: GPUShaderStage.FRAGMENT as int32,
		size: 16,
		nativeSlot: 0,
	};
	sd.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
	const module = device.createShaderModule(sd);
	let pd: GPURenderPipelineDescriptor = { label: "strip" };
	pd.vertex.module = module;
	pd.vertex.buffers[0].arrayStride = 8;
	pd.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
	pd.fragment.module = module;
	pd.fragment.targets[0].format = "rgba8unorm";
	pd.primitive.topology = "triangle-strip";
	pd.primitive.stripIndexFormat = "uint16";
	const pipeline = device.createRenderPipeline(pd);
	let gd: GPUBindGroupDescriptor = { label: "colour", layout: pipeline.getBindGroupLayout(0) };
	gd.entries[0] = { binding: 0, buffer: colourUniforms(device), offset: 0, size: 16 };
	const group = device.createBindGroup(gd);
	const indexUsage = (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32);
	const indices = device.createBuffer({ label: "indices", size: 16, usage: indexUsage });
	const noResolve: GPUTextureView = { id: 0 };
	const offsets: Vec<uint32> = [0];
	if (name == "shaderDestroyed") { module.destroy(); }
	const view = colourTarget(device, 1).createView({ label: null });
	const pass = encoder.beginRenderPass(clearingPass(view, noResolve));
	pass.setPipeline(pipeline);
	pass.setVertexBuffer(0, vertexBuffer(device, 24), 0);
	pass.setBindGroup(0, group, offsets);
	pass.setIndexBuffer(indices, name == "stripIndexMismatch" ? "uint32" : "uint16", 0);
	pass.drawIndexed(3, 1, 0, 0, 0);
	console.log(`${name}: the indexed draw returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
