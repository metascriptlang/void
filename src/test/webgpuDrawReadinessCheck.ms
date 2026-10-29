import {
	GPUBindGroupDescriptor,
	GPUDevice,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUBindGroup,
	GPUBuffer,
	GPUBufferUsage,
} from "../webgpu/types.ms";
import "../webgpu/device.ms";
import { ASPECT_ALL, ASPECT_GROUPS, ASPECT_INDEX, ASPECT_VERTEX, boundFacts } from "../webgpu/validate.ms";
import { openTestDevice } from "./testDevice";
import { clearingPass, colourTarget, colourUniforms, vertexBuffer } from "./webgpuFixtures";

when (voidDummy) {
	function flatPipeline(device: GPUDevice): GPURenderPipeline {
		let sd: GPUShaderModuleDescriptor = { label: "flat", vertexCode: "v", vertexEntryPoint: "vmain", fragmentCode: "f", fragmentEntryPoint: "fmain" };
		sd.bindings[0] = { group: 0, binding: 0, kind: "uniform", visibility: GPUShaderStage.FRAGMENT as int32, size: 16, nativeSlot: 0 };
		sd.attributes[0] = { location: 0, nativeName: null, semanticIndex: 0 };
		const module = device.createShaderModule(sd);
		let pd: GPURenderPipelineDescriptor = { label: "flat" };
		pd.vertex.module = module;
		pd.vertex.buffers[0].arrayStride = 8;
		pd.vertex.buffers[0].attributes[0] = { format: "float32x2", offset: 0, shaderLocation: 0 };
		pd.fragment.module = module;
		pd.fragment.targets[0].format = "rgba8unorm";
		return device.createRenderPipeline(pd);
	}

	function groupOf(device: GPUDevice, pipeline: GPURenderPipeline, uniforms: GPUBuffer): GPUBindGroup {
		let gd: GPUBindGroupDescriptor = { label: "colour", layout: pipeline.getBindGroupLayout(0) };
		gd.entries[0] = { binding: 0, buffer: uniforms, offset: 0, size: 16 };
		return device.createBindGroup(gd);
	}

	function openPass(device: GPUDevice): GPURenderPassEncoder {
		const view = colourTarget(device, 1).createView({ label: null });
		return device.createCommandEncoder().beginRenderPass(clearingPass(view, { id: 0 }));
	}

	test "a dynamic-offset-only setBindGroup keeps the draw readiness" {
		const device = openTestDevice();
		const pipeline = flatPipeline(device);
		const uniforms = colourUniforms(device);
		const group = groupOf(device, pipeline, uniforms);
		const pass = openPass(device);
		const first: Vec<uint32> = [0];
		const second: Vec<uint32> = [256];
		pass.setPipeline(pipeline);
		pass.setVertexBuffer(0, vertexBuffer(device, 24), 0);
		pass.setBindGroup(0, group, first);
		pass.draw(3, 1, 0, 0);
		assert boundFacts.stale == ASPECT_INDEX;
		pass.setBindGroup(0, group, second);
		assert boundFacts.stale == ASPECT_INDEX;
		assert boundFacts.dynamicOffsets[0] == 256;
		pass.draw(3, 1, 0, 0);
	}

	test "a different group at the same index drops the draw readiness" {
		const device = openTestDevice();
		const pipeline = flatPipeline(device);
		const uniforms = colourUniforms(device);
		const group = groupOf(device, pipeline, uniforms);
		const other = groupOf(device, pipeline, uniforms);
		const pass = openPass(device);
		const offsets: Vec<uint32> = [0];
		pass.setPipeline(pipeline);
		pass.setVertexBuffer(0, vertexBuffer(device, 24), 0);
		pass.setBindGroup(0, group, offsets);
		pass.draw(3, 1, 0, 0);
		pass.setBindGroup(0, other, offsets);
		assert (boundFacts.stale & ASPECT_GROUPS) != 0;
		pass.draw(3, 1, 0, 0);
		assert boundFacts.stale == ASPECT_INDEX;
	}

	test "a vertex or index set leaves the bind groups judged" {
		const device = openTestDevice();
		const pipeline = flatPipeline(device);
		const group = groupOf(device, pipeline, colourUniforms(device));
		const indexUsage = (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32);
		const indices = device.createBuffer({ label: "indices", size: 16, usage: indexUsage });
		const vertices = vertexBuffer(device, 48);
		const pass = openPass(device);
		const offsets: Vec<uint32> = [0];
		pass.setPipeline(pipeline);
		assert boundFacts.stale == ASPECT_ALL;
		pass.setVertexBuffer(0, vertices, 0);
		pass.setBindGroup(0, group, offsets);
		pass.setIndexBuffer(indices, "uint16", 0);
		pass.drawIndexed(3, 1, 0, 0, 0);
		assert boundFacts.stale == 0;
		pass.setVertexBuffer(0, vertices, 8);
		assert boundFacts.stale == ASPECT_VERTEX;
		pass.draw(3, 1, 0, 0);
		assert boundFacts.stale == 0;
		pass.setIndexBuffer(indices, "uint32", 0);
		assert boundFacts.stale == ASPECT_INDEX;
		pass.draw(3, 1, 0, 0);
		assert boundFacts.stale == ASPECT_INDEX;
		pass.drawIndexed(3, 1, 0, 0, 0);
		assert boundFacts.stale == 0;
	}

	test "a setPipeline of the bound pipeline resets nothing and another pipeline resets all" {
		const device = openTestDevice();
		const pipeline = flatPipeline(device);
		const group = groupOf(device, pipeline, colourUniforms(device));
		const pass = openPass(device);
		const offsets: Vec<uint32> = [0];
		pass.setPipeline(pipeline);
		pass.setVertexBuffer(0, vertexBuffer(device, 24), 0);
		pass.setBindGroup(0, group, offsets);
		pass.draw(3, 1, 0, 0);
		assert (boundFacts.stale & (ASPECT_GROUPS | ASPECT_VERTEX)) == 0;
		pass.setPipeline(pipeline);
		assert (boundFacts.stale & (ASPECT_GROUPS | ASPECT_VERTEX)) == 0;
		const other = flatPipeline(device);
		pass.setPipeline(other);
		assert boundFacts.stale == ASPECT_ALL;
	}

	test "a draw that exactly fills the bound vertex and index ranges passes" {
		const device = openTestDevice();
		const pipeline = flatPipeline(device);
		const group = groupOf(device, pipeline, colourUniforms(device));
		const indexUsage = (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32);
		const pass = openPass(device);
		const offsets: Vec<uint32> = [0];
		pass.setPipeline(pipeline);
		pass.setVertexBuffer(0, vertexBuffer(device, 24), 0);
		pass.setBindGroup(0, group, offsets);
		pass.setIndexBuffer(device.createBuffer({ label: "indices", size: 16, usage: indexUsage }), "uint16", 0);
		pass.draw(3, 1, 0, 0);
		pass.draw(0, 1, 3, 0);
		pass.drawIndexed(8, 1, 0, 0, 0);
		pass.drawIndexed(0, 1, 8, 0, 0);
	}
}
