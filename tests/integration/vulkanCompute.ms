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
	copyBufferToBuffer,
	createBuffer,
	openResources,
	readMapped,
	submit,
	wait,
	writeBuffer,
} from "../../src/webgpu/vulkan/resources";
import {
	VulkanPipelines,
	beginBindings,
	closePipelines,
	createBindGroup,
	createComputePipeline,
	createShaderModule,
	dispatchWorkgroups,
	dispatchWorkgroupsIndirect,
	openPipelines,
	setBindGroup,
	setComputePipeline,
} from "../../src/webgpu/vulkan/pipeline";
import { spirvCompute } from "./vulkanSpirv";
import {
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferUsage,
	GPUShaderModuleDescriptor,
	GPUShaderStage,
	GPU_RESOURCE_GROUP,
} from "../../src/webgpu/types.ms";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_OK: int32 = 0;
const VULKAN_POWER_HIGH: int32 = 2;
const COUNT = 256;
const WORKGROUP = 64;
const BYTES = COUNT * 4;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan compute: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	return false;
}

function refused(name: string, error: string): int32 {
	console.log(`FAIL vulkan compute: ${name} refused with ${error}: ${vulkanError()}`);
	vulkanShutdown();
	return 1;
}

function words(values: Readonly<Span<uint32>>): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const value of values) {
		for (let shift: uint32 = 0; shift < 32; shift += 8) { bytes.push(((value >> shift) & 0xFF) as uint8); }
	}
	return bytes;
}

function shaderDescriptor(): GPUShaderModuleDescriptor {
	let descriptor: GPUShaderModuleDescriptor = {
		label: "triple",
		computeEntryPoint: "main",
		computeBytecode: spirvCompute(),
		workgroupSize: [WORKGROUP, 1, 1],
	};
	descriptor.bindings[0] = {
		group: GPU_RESOURCE_GROUP,
		binding: 0,
		kind: "storage-buffer",
		visibility: GPUShaderStage.COMPUTE as int32,
		bufferType: "read-only-storage",
	};
	descriptor.bindings[1] = {
		group: GPU_RESOURCE_GROUP,
		binding: 1,
		kind: "storage-buffer",
		visibility: GPUShaderStage.COMPUTE as int32,
		bufferType: "storage",
	};
	return descriptor;
}

function storage(ref r: VulkanResources, label: string): Result<GPUBuffer, ResourceError> {
	return createBuffer(r, {
		label: label,
		size: BYTES,
		usage: (GPUBufferUsage.STORAGE as int32) | (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
}

function groupOf(source: GPUBuffer, result: GPUBuffer): GPUBindGroupDescriptor {
	let descriptor: GPUBindGroupDescriptor = { label: "triple" };
	descriptor.entries[0] = { binding: 0, buffer: source, offset: 0, size: 0 };
	descriptor.entries[1] = { binding: 1, buffer: result, offset: 0, size: 0 };
	return descriptor;
}

function computed(ref r: VulkanResources, ref p: VulkanPipelines): Result<int32, ResourceError> {
	const input = try storage(r, "input");
	const middle = try storage(r, "middle");
	const output = try storage(r, "output");
	const readback = try createBuffer(r, {
		label: "readback",
		size: BYTES,
		usage: (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	const indirect = try createBuffer(r, {
		label: "indirect",
		size: 12,
		usage: (GPUBufferUsage.INDIRECT as int32) | (GPUBufferUsage.COPY_DST as int32),
	});
	let values: Vec<uint32> = [];
	for (let i = 0; i < COUNT; i++) { values.push(i as uint32); }
	try writeBuffer(r, input, 0, words(values));
	const groups: uint32[3] = [(COUNT / WORKGROUP) as uint32, 1, 1];
	try writeBuffer(r, indirect, 0, words(groups));

	const shader = try createShaderModule(p, r, shaderDescriptor());
	const pipeline = try createComputePipeline(p, { label: "triple", compute: { module: shader, entryPoint: "main" } });
	const first = try createBindGroup(p, r, shader, GPU_RESOURCE_GROUP, groupOf(input, middle));
	const second = try createBindGroup(p, r, shader, GPU_RESOURCE_GROUP, groupOf(middle, output));

	const none: uint32[0] = [];
	beginBindings(p, true);
	setBindGroup(p, GPU_RESOURCE_GROUP, first, none);
	setComputePipeline(p, pipeline);
	try dispatchWorkgroups(p, r, COUNT / WORKGROUP, 1, 1);
	setBindGroup(p, GPU_RESOURCE_GROUP, second, none);
	try dispatchWorkgroupsIndirect(p, r, indirect, 0);
	try copyBufferToBuffer(r, output, 0, readback, 0, BYTES);
	const serial = try submit(r);
	try wait(r, serial);
	const bytes = try readMapped(r, readback, 0, BYTES);
	for (let i = 0; i < COUNT; i++) {
		let got: uint32 = 0;
		for (let b = 3; b >= 0; b--) { got = (got << 8) | (bytes[i * 4 + b] as uint32); }
		const expected = ((i as uint32) * 3 + 1) * 3 + 1;
		if (got != expected) {
			console.log(`FAIL vulkan compute: element ${i} read ${got}, expected ${expected}`);
			return Result.ok(1);
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
	const result = computed(r, p);
	if (!result.ok) { return refused("compute", result.error.toString()); }
	if (result.value != 0) {
		vulkanShutdown();
		return 1;
	}
	closePipelines(p, r);
	const closed = closeResources(r);
	if (!closed.ok) { return refused("closeResources", closed.error.toString()); }
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ${vulkanValidationWarnings()} warnings`);
	if (env.get("VOID_VULKAN_VALIDATION").equals("1") && !validated) {
		console.log("FAIL vulkan compute: VOID_VULKAN_VALIDATION=1 found no validation layer");
		return 1;
	}
	if (errors != 0) {
		console.log(`FAIL vulkan compute: ${errors} validation errors`);
		return 1;
	}
	console.log(`PASS vulkan compute: ${COUNT} elements tripled-plus-one twice, the second dispatch indirect and reading the first's output`);
	return 0;
}

process.exit(main());
