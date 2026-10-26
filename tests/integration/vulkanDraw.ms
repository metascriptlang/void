import { env } from "std/process";
import {
	vulkanAdapterName,
	vulkanAdapterSelect,
	vulkanDeviceCreate,
	vulkanError,
	vulkanInstanceCreate,
	vulkanLoaderOpen,
	vulkanShutdown,
	vulkanValidationEnabled,
	vulkanValidationErrors,
	vulkanValidationWarnings,
} from "../../src/webgpu/vulkan/vulkan.h";
import {
	ResourceError,
	VulkanResources,
	closeResources,
	copyTextureToBuffer,
	createBuffer,
	createTexture,
	createView,
	openResources,
	readMapped,
	submit,
	wait,
	writeBuffer,
} from "../../src/webgpu/vulkan/resources";
import { RenderPassCache, beginRenderPass, closeRenderPasses, endRenderPass, newRenderPassCache } from "../../src/webgpu/vulkan/pass";
import {
	VulkanPipelines,
	beginBindings,
	closePipelines,
	createBindGroup,
	createRenderPipeline,
	createShaderModule,
	draw,
	drawIndexed,
	openPipelines,
	setBindGroup,
	setIndexBuffer,
	setPipeline,
	setVertexBuffer,
	setViewport,
} from "../../src/webgpu/vulkan/pipeline";
import { spirvDraw } from "./vulkanSpirv";
import {
	GPUBindGroupDescriptor,
	GPUBufferUsage,
	GPURenderPassDescriptor,
	GPURenderPipelineDescriptor,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPUTextureUsage,
	GPU_UNIFORM_GROUP,
} from "../../src/webgpu/types.ms";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_OK: int32 = 0;
const VULKAN_POWER_HIGH: int32 = 2;
const WIDTH = 16;
const HEIGHT = 8;
const TEXEL = 4;
const PITCH = WIDTH * TEXEL;
const BLOCK = 32;
const SECOND_BLOCK = 256;
const THIRD_BLOCK = 512;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan draw: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	return false;
}

function refused(name: string, error: string): int32 {
	console.log(`FAIL vulkan draw: ${name} refused with ${error}: ${vulkanError()}`);
	vulkanShutdown();
	return 1;
}

function words(values: Readonly<Span<int32>>): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const value of values) {
		const bits = value as uint32;
		for (let shift: uint32 = 0; shift < 32; shift += 8) { bytes.push(((bits >> shift) & 0xFF) as uint8); }
	}
	return bytes;
}

function shaderDescriptor(): GPUShaderModuleDescriptor {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "tint",
		vertexEntryPoint: "vs",
		fragmentEntryPoint: "fs",
		vertexBytecode: spirvDraw(),
		fragmentBytecode: spirvDraw(),
	};
	descriptor.bindings[0] = {
		group: GPU_UNIFORM_GROUP,
		binding: 0,
		kind: "uniform",
		visibility: (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32),
		size: BLOCK,
	};
	return descriptor;
}

function pipelineDescriptor(shader: uint32): GPURenderPipelineDescriptor {
	let descriptor: GPURenderPipelineDescriptor = { label: "tint" };
	descriptor.vertex.module = { id: shader };
	descriptor.vertex.buffers[0].arrayStride = 8;
	descriptor.vertex.buffers[0].attributes[0] = { format: "sint32x2", offset: 0, shaderLocation: 0 };
	descriptor.primitive.topology = "triangle-list";
	descriptor.primitive.frontFace = "ccw";
	descriptor.primitive.cullMode = "back";
	descriptor.multisample.count = 1;
	descriptor.depthStencil.stencilReadMask = 0xFFFFFFFF;
	descriptor.depthStencil.stencilWriteMask = 0xFFFFFFFF;
	descriptor.fragment.module = { id: shader };
	descriptor.fragment.targets[0].format = "rgba8unorm";
	return descriptor;
}

function drawn(ref r: VulkanResources, ref p: VulkanPipelines, ref cache: RenderPassCache): Result<int32, ResourceError> {
	const texture = try createTexture(r, {
		label: "target",
		size: { width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32),
		sampleCount: 1,
		dimension: "2d",
		mipLevelCount: 1,
	});
	const view = try createView(r, texture, { label: "target", baseMipLevel: 0, mipLevelCount: 0, baseArrayLayer: 0, arrayLayerCount: 0 });
	const readback = try createBuffer(r, {
		label: "readback",
		size: PITCH * HEIGHT,
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const vertices = try createBuffer(r, {
		label: "quad",
		size: 48,
		usage: (GPUBufferUsage.VERTEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const quad: int32[12] = [-1, 0, 0, 0, 0, 1, -1, 0, 0, 1, -1, 1];
	try writeBuffer(r, vertices, 0, words(quad));
	const indices = try createBuffer(r, {
		label: "indices",
		size: 12,
		usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const order: uint8[12] = [0, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0];
	try writeBuffer(r, indices, 0, order);
	const uniforms = try createBuffer(r, {
		label: "tints",
		size: THIRD_BLOCK + BLOCK,
		usage: (GPUBufferUsage.UNIFORM as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const red: int32[8] = [255, 0, 0, 255, 0, 0, 0, 0];
	const blue: int32[8] = [0, 0, 255, 255, 1, -1, 0, 0];
	try writeBuffer(r, uniforms, 0, words(red));
	try writeBuffer(r, uniforms, SECOND_BLOCK, words(blue));
	const green: int32[8] = [0, 255, 0, 255, 0, 0, 0, 0];
	try writeBuffer(r, uniforms, THIRD_BLOCK, words(green));

	const shader = try createShaderModule(p, r, shaderDescriptor());
	const pipeline = try createRenderPipeline(p, r, cache, pipelineDescriptor(shader.id));
	let groupDescriptor: GPUBindGroupDescriptor = { label: "tints" };
	groupDescriptor.entries[0] = { binding: 0, buffer: uniforms, offset: 0, size: BLOCK };
	const group = try createBindGroup(p, r, shader, GPU_UNIFORM_GROUP, groupDescriptor);

	let pass: GPURenderPassDescriptor = { label: "draw" };
	pass.colorAttachments[0].view = view;
	pass.colorAttachments[0].loadOp = "clear";
	pass.colorAttachments[0].storeOp = "store";
	pass.colorAttachments[0].clearValue = { r: 0.0, g: 0.0, b: 0.0, a: 1.0 };
	pass.depthStencilAttachment.depthLoadOp = "load";
	pass.depthStencilAttachment.depthStoreOp = "store";
	try beginRenderPass(r, cache, pass);
	beginBindings(p, false);
	const first: uint32[1] = [0];
	setBindGroup(p, GPU_UNIFORM_GROUP, group, first);
	setPipeline(p, pipeline);
	setVertexBuffer(r, 0, vertices, 0);
	draw(p, r, 6, 1, 0, 0);
	const second: uint32[1] = [SECOND_BLOCK];
	setBindGroup(p, GPU_UNIFORM_GROUP, group, second);
	setIndexBuffer(p, r, indices, "uint16", 0);
	drawIndexed(p, r, 6, 1, 0, 0, 0);
	const third: uint32[1] = [THIRD_BLOCK];
	setBindGroup(p, GPU_UNIFORM_GROUP, group, third);
	setViewport((WIDTH / 2) as float32, 0.0, (WIDTH / 2) as float32, (HEIGHT / 2) as float32, 0.0, 1.0);
	draw(p, r, 6, 1, 0, 0);
	endRenderPass();
	try copyTextureToBuffer(
		r,
		{ texture: texture, mipLevel: 0, origin: { x: 0, y: 0, z: 0 } },
		{ buffer: readback, offset: 0, bytesPerRow: PITCH, rowsPerImage: HEIGHT },
		{ width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
	);
	const serial = try submit(r);
	try wait(r, serial);
	const bytes = try readMapped(r, readback, 0, PITCH * HEIGHT);
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			const top = y < HEIGHT / 2;
			const left = x < WIDTH / 2;
			const corner = y < HEIGHT / 4 && x >= WIDTH / 2 && x < WIDTH * 3 / 4;
			const expected: uint8[4] = top && left ? [255, 0, 0, 255] : !top && !left ? [0, 0, 255, 255] : corner ? [0, 255, 0, 255] : [0, 0, 0, 255];
			for (let c = 0; c < TEXEL; c++) {
				const got = bytes[y * PITCH + x * TEXEL + c];
				if (got != expected[c]) {
					console.log(`FAIL vulkan draw: texel ${x},${y} channel ${c} read ${got}, expected ${expected[c]}`);
					return Result.ok(1);
				}
			}
		}
	}
	return Result.ok(0);
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	console.log(`adapter ${vulkanAdapterName()}`);
	let r = openResources();
	let p = openPipelines();
	let cache = newRenderPassCache();
	const result = drawn(r, p, cache);
	if (!result.ok) { return refused("draw", result.error.toString()); }
	if (result.value != 0) {
		vulkanShutdown();
		return 1;
	}
	closePipelines(p, r);
	closeRenderPasses(cache);
	const closed = closeResources(r);
	if (!closed.ok) { return refused("closeResources", closed.error.toString()); }
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ${vulkanValidationWarnings()} warnings`);
	if (env.get("VOID_VULKAN_VALIDATION").equals("1") && !validated) {
		console.log("FAIL vulkan draw: VOID_VULKAN_VALIDATION=1 found no validation layer");
		return 1;
	}
	if (errors != 0) {
		console.log(`FAIL vulkan draw: ${errors} validation errors`);
		return 1;
	}
	console.log("PASS vulkan draw: back-face-culled ccw quads land top-left and bottom-right through one uniform set at dynamic offsets 0 and 256, drawn and drawn indexed, and a viewport at the top-right quarter keeps its quad at the top");
	return 0;
}

process.exit(main());
