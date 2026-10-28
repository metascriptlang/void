// The D3D11 backend takes the DXBC that shaderModule and shaderBuild embed at msc compile time:
// the descriptor holds no HLSL text, yet the module, its pipeline and the draw or dispatch work.

import { GPUBufferUsage, GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { glslComputeIr } from "../shader/emit";
import { shaderBuild, shaderModule } from "../shader/program";
import {
	AtomicU32,
	Vec2f,
	Vec3u,
	Vec4f,
	access,
	atomicAdd,
	binding,
	builtin,
	vec3u,
	vec4f,
} from "../shader/std";

struct PointInput {
	position: Vec2f;
}

struct PointVarying {
	@builtin(position) position: Vec4f;
}

struct TintBlock {
	tint: Vec4f;
}

struct TintBindings {
	@binding(0) block: TintBlock;
}

function pointVs(input: PointInput): PointVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

function constantFs(): Vec4f {
	return vec4f(0.25, 0.5, 0.75, 1.0);
}

function tintFs(b: TintBindings): Vec4f {
	return b.block.tint;
}

struct CountInput {
	@builtin(globalInvocationId) id: Vec3u;
}

struct CountCell {
	hits: AtomicU32;
}

struct CountBindings {
	@binding(0) @access(read_write) cells: CountCell[];
}

function countCs(input: CountInput, b: CountBindings): void {
	atomicAdd(b.cells[input.id.x].hits, 2);
}

shaderModule(constant, pointVs, constantFs);
shaderModule(tinted, pointVs, tintFs);
const counted = shaderBuild("counted", glslComputeIr(countCs, [64, 1, 1]), "", "", "shaderComputeModule");

when (windows && !voidVulkan) {
	import { GPUDevice } from "../webgpu/types.ms";
	import { readBack, readbackBuffer, SIZE, clearingPass, colourTarget, colourUniforms, texelAt, uniformGroup, vertexBuffer, RED, BLUE } from "./webgpuFixtures.ms";
	import "../webgpu/device.ms";
	import { openTestDevice } from "./testDevice.ms";

	const PIXELS_PER_ROW = SIZE * 4;
	const CELLS = 64;

	function triangle(device: GPUDevice, descriptor: GPUShaderModuleDescriptor, tinted: boolean): Vec<uint8> {
		const module = device.createShaderModule(descriptor);
		const pipeline = device.createRenderPipeline({
			label: "bytecode",
			vertex: { module, buffers: [{ arrayStride: 8, attributes: [{ format: "float32x2", offset: 0, shaderLocation: 0 }] }] },
			fragment: { module, targets: [{ format: "rgba8unorm" }] },
		});
		const vertices = vertexBuffer(device, 24);
		device.queue.writeBuffer(vertices, 0, [-0.5, -0.5, 0.0, 0.5, 0.5, -0.5] as Vec<float32>);
		const target = colourTarget(device, 1);
		const encoder = device.createCommandEncoder();
		const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
		pass.setPipeline(pipeline);
		pass.setVertexBuffer(0, vertices, 0);
		if (tinted) {
			const offsets: Vec<uint32> = [0];
			pass.setBindGroup(0, uniformGroup(device, pipeline, colourUniforms(device)), offsets);
		}
		pass.draw(3, 1, 0, 0);
		pass.end();
		const read = readbackBuffer(device, PIXELS_PER_ROW * SIZE);
		encoder.copyTextureToBuffer({ texture: target }, { buffer: read, offset: 0, bytesPerRow: PIXELS_PER_ROW, rowsPerImage: SIZE }, { width: SIZE, height: SIZE, depthOrArrayLayers: 1 });
		device.queue.submit(encoder.finish());
		return readBack(read);
	}

	function near(actual: uint32, red: int32, green: int32, blue: int32): boolean {
		const r = (actual >> 24) as int32;
		const g = ((actual >> 16) & 0xFF) as int32;
		const b = ((actual >> 8) & 0xFF) as int32;
		return (r - red) * (r - red) <= 1 && (g - green) * (g - green) <= 1 && (b - blue) * (b - blue) <= 1 && (actual & 0xFF) == 0xFF;
	}

	test "a shaderModule's embedded DXBC makes a module and a pipeline that draw the fragment's constant" {
		assert constantModule.vertexCode == "" && constantModule.fragmentCode == "";
		assert constantModule.vertexBytecode.length > 0 && constantModule.fragmentBytecode.length > 0;
		const device = openTestDevice();
		const pixels = triangle(device, constantModule, false);
		assert texelAt(pixels, PIXELS_PER_ROW, 0, 0) == BLUE;
		assert near(texelAt(pixels, PIXELS_PER_ROW, 32, 32), 64, 128, 191);
		device.destroy();
	}

	test "a shaderModule's embedded DXBC reads its uniform block" {
		assert tintedModule.fragmentCode == "" && tintedModule.fragmentBytecode.length > 0;
		const device = openTestDevice();
		const pixels = triangle(device, tintedModule, true);
		assert texelAt(pixels, PIXELS_PER_ROW, 0, 0) == BLUE;
		assert texelAt(pixels, PIXELS_PER_ROW, 32, 32) == RED;
		device.destroy();
	}

	test "a shaderComputeModule's embedded cs_5_0 makes a compute pipeline whose dispatch matches the CPU run" {
		assert counted.computeCode == "" && counted.computeBytecode.length > 0;
		let expected: Vec<uint32> = new Array(CELLS);
		const cells: CountCell[] = [];
		for (let i = 0; i < CELLS; i++) { cells.push({ hits: { value: i as uint32 } }); }
		for (let i = 0; i < CELLS; i++) { countCs({ id: vec3u(i as uint32, 0, 0) }, { cells }); }
		for (let i = 0; i < CELLS; i++) { expected[i] = cells[i].hits.value; }

		const device = openTestDevice();
		const module = device.createShaderModule(counted);
		const pipeline = device.createComputePipeline({ label: "counted", compute: { module, entryPoint: "" } });
		const storage = device.createBuffer({
			label: "cells",
			size: CELLS * 4,
			usage: (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_DST as int32) | (GPUBufferUsage.COPY_SRC as int32),
		});
		let start: Vec<uint32> = new Array(CELLS);
		for (let i = 0; i < CELLS; i++) { start[i] = i as uint32; }
		device.queue.writeBuffer(storage, 0, start);
		const group = device.createBindGroup({
			label: "cells",
			layout: pipeline.getBindGroupLayout(counted.bindings[0].group),
			entries: [{ binding: 0, buffer: storage }],
		});
		const read = readbackBuffer(device, CELLS * 4);
		const encoder = device.createCommandEncoder();
		const pass = encoder.beginComputePass({ label: null });
		pass.setPipeline(pipeline);
		const noOffsets: Vec<uint32> = [];
		pass.setBindGroup(counted.bindings[0].group, group, noOffsets);
		pass.dispatchWorkgroups(1, 1, 1);
		pass.end();
		encoder.copyBufferToBuffer(storage, 0, read, 0, CELLS * 4);
		device.queue.submit(encoder.finish());
		const bytes = readBack(read);
		for (let i = 0; i < CELLS; i++) {
			const gpu = (bytes[i * 4] as uint32) | ((bytes[i * 4 + 1] as uint32) << 8) | ((bytes[i * 4 + 2] as uint32) << 16) | ((bytes[i * 4 + 3] as uint32) << 24);
			assert gpu == expected[i];
		}
		assert expected[0] == 2 && expected[63] == 65;
		device.destroy();
	}
}
