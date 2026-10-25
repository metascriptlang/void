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
} from "../../src/webgpu/vulkan/resources";
import {
	RenderPassCache,
	beginRenderPass,
	closeRenderPasses,
	endRenderPass,
	newRenderPassCache,
} from "../../src/webgpu/vulkan/pass";
import {
	GPUBuffer,
	GPUBufferUsage,
	GPURenderPassDescriptor,
	GPUTexture,
	GPUTextureFormat,
	GPUTextureUsage,
	GPUTextureView,
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

struct Target {
	texture: GPUTexture;
	view: GPUTextureView;
	readback: GPUBuffer;
}

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan clear: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	return false;
}

function refused(name: string, error: string): int32 {
	console.log(`FAIL vulkan clear: ${name} refused with ${error}: ${vulkanError()}`);
	vulkanShutdown();
	return 1;
}

function target(ref r: VulkanResources, format: GPUTextureFormat): Result<Target, ResourceError> {
	const texture = try createTexture(r, {
		label: "target",
		size: { width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
		format: format,
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
	return Result.ok({ texture: texture, view: view, readback: readback });
}

function emptyPass(): GPURenderPassDescriptor {
	let descriptor: GPURenderPassDescriptor = { label: "clear" };
	for (let i = 0; i < 4; i++) {
		descriptor.colorAttachments[i].loadOp = "load";
		descriptor.colorAttachments[i].storeOp = "store";
	}
	descriptor.depthStencilAttachment.depthLoadOp = "load";
	descriptor.depthStencilAttachment.depthStoreOp = "store";
	return descriptor;
}

function pass(ref r: VulkanResources, ref cache: RenderPassCache, descriptor: GPURenderPassDescriptor): Result<void, ResourceError> {
	try beginRenderPass(r, cache, descriptor);
	endRenderPass();
	return Result.ok(null);
}

function copied(ref r: VulkanResources, t: Target): Result<void, ResourceError> {
	return copyTextureToBuffer(
		r,
		{ texture: t.texture, mipLevel: 0, origin: { x: 0, y: 0, z: 0 } },
		{ buffer: t.readback, offset: 0, bytesPerRow: PITCH, rowsPerImage: HEIGHT },
		{ width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
	);
}

function matches(ref r: VulkanResources, name: string, t: Target, texel: uint8[4]): boolean {
	const bytes = readMapped(r, t.readback, 0, PITCH * HEIGHT);
	if (!bytes.ok) {
		console.log(`FAIL vulkan clear: readMapped ${name} refused with ${bytes.error.toString()}`);
		return false;
	}
	for (let i = 0; i < PITCH * HEIGHT; i++) {
		if (bytes.value[i] != texel[i % TEXEL]) {
			console.log(`FAIL vulkan clear: ${name} byte ${i} read ${bytes.value[i]}, expected ${texel[i % TEXEL]}`);
			return false;
		}
	}
	return true;
}

function clears(ref r: VulkanResources, ref cache: RenderPassCache): int32 {
	const unorm = target(r, "rgba8unorm");
	if (!unorm.ok) { return refused("rgba8unorm target", unorm.error.toString()); }
	const uint = target(r, "rgba8uint");
	if (!uint.ok) { return refused("rgba8uint target", uint.error.toString()); }
	const depth = target(r, "depth32float");
	if (!depth.ok) { return refused("depth32float target", depth.error.toString()); }

	let first = emptyPass();
	first.colorAttachments[0].view = unorm.value.view;
	first.colorAttachments[0].loadOp = "clear";
	first.colorAttachments[0].clearValue = { r: 0.2, g: 0.6, b: 1.0, a: 1.0 };
	first.depthStencilAttachment.view = depth.value.view;
	first.depthStencilAttachment.depthLoadOp = "clear";
	first.depthStencilAttachment.depthClearValue = 0.5;
	const firstPass = pass(r, cache, first);
	if (!firstPass.ok) { return refused("clear pass", firstPass.error.toString()); }

	let second = emptyPass();
	second.colorAttachments[0].view = unorm.value.view;
	second.colorAttachments[1].view = uint.value.view;
	second.colorAttachments[1].loadOp = "clear";
	second.colorAttachments[1].clearValue = { r: 7, g: 8, b: 9, a: 10 };
	for (let round = 0; round < 2; round++) {
		const secondPass = pass(r, cache, second);
		if (!secondPass.ok) { return refused("load pass", secondPass.error.toString()); }
	}
	if (cache.passes.length != 2) {
		console.log(`FAIL vulkan clear: three passes over two descriptors made ${cache.passes.length} render passes`);
		vulkanShutdown();
		return 1;
	}

	for (const t of [unorm.value, uint.value, depth.value]) {
		const copy = copied(r, t);
		if (!copy.ok) { return refused("copyTextureToBuffer", copy.error.toString()); }
	}
	const serial = submit(r);
	if (!serial.ok) { return refused("submit", serial.error.toString()); }
	const waited = wait(r, serial.value);
	if (!waited.ok) { return refused("wait", waited.error.toString()); }

	const loaded: uint8[4] = [51, 153, 255, 255];
	const integers: uint8[4] = [7, 8, 9, 10];
	const half: uint8[4] = [0, 0, 0, 63];
	if (!matches(r, "rgba8unorm cleared then loaded", unorm.value, loaded) ||
		!matches(r, "rgba8uint cleared as integers", uint.value, integers) ||
		!matches(r, "depth32float cleared to 0.5", depth.value, half)) {
		vulkanShutdown();
		return 1;
	}
	console.log(`clears: ${WIDTH}x${HEIGHT} rgba8unorm cleared then loaded, rgba8uint cleared to 7,8,9,10 and depth 0.5 ` +
		`match byte for byte over ${cache.passes.length} cached render passes`);
	return 0;
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	console.log(`adapter ${vulkanAdapterName()}`);
	let r = openResources();
	let cache = newRenderPassCache();
	if (clears(r, cache) != 0) { return 1; }
	closeRenderPasses(cache);
	const closed = closeResources(r);
	if (!closed.ok) { return refused("closeResources", closed.error.toString()); }
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ${vulkanValidationWarnings()} warnings`);
	if (env.get("VOID_VULKAN_VALIDATION").equals("1") && !validated) {
		console.log("FAIL vulkan clear: VOID_VULKAN_VALIDATION=1 found no validation layer");
		return 1;
	}
	if (errors != 0) {
		console.log(`FAIL vulkan clear: ${errors} validation errors`);
		return 1;
	}
	console.log("PASS vulkan clear: clear and load passes over unorm, uint and depth targets read back byte for byte");
	return 0;
}

process.exit(main());
