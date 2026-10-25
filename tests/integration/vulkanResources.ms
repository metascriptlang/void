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
	collect,
	copyBufferToBuffer,
	copyTextureToBuffer,
	createBuffer,
	createSampler,
	createTexture,
	createView,
	destroyBuffer,
	destroySampler,
	destroyTexture,
	destroyView,
	openResources,
	readMapped,
	submit,
	wait,
	writeBuffer,
	writeTexture,
} from "../../src/webgpu/vulkan/resources";
import { GPUBufferUsage, GPUTextureUsage } from "../../src/webgpu/types.ms";
import { live } from "../../src/webgpu/pool.ms";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_OK: int32 = 0;
const VULKAN_POWER_HIGH: int32 = 2;
const BUFFER_BYTES = 1000;
const WIDTH = 13;
const HEIGHT = 7;
const TEXEL = 4;
const SOURCE_PITCH = WIDTH * TEXEL + 3;
const READ_PITCH = 256;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan resources: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	return false;
}

function refused(name: string, error: ResourceError): int32 {
	console.log(`FAIL vulkan resources: ${name} refused with ${error.toString()}: ${vulkanError()}`);
	vulkanShutdown();
	return 1;
}

function compared(name: string, expected: Readonly<Span<uint8>>, actual: Readonly<Span<uint8>>): boolean {
	for (let i = 0; i < expected.length; i++) {
		if (expected[i] != actual[i]) {
			console.log(`FAIL vulkan resources: ${name} byte ${i} read ${actual[i]}, wrote ${expected[i]}`);
			return false;
		}
	}
	return true;
}

function roundTrip(ref r: VulkanResources): int32 {
	let bufferBytes: Vec<uint8> = new Array(BUFFER_BYTES);
	for (let i = 0; i < BUFFER_BYTES; i++) { bufferBytes[i] = ((i * 7 + 3) % 251) as uint8; }
	let texels: Vec<uint8> = new Array(SOURCE_PITCH * HEIGHT);
	let expected: Vec<uint8> = new Array(WIDTH * TEXEL * HEIGHT);
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < SOURCE_PITCH; x++) {
			const value = ((y * 31 + x * 5 + 1) % 253) as uint8;
			texels[y * SOURCE_PITCH + x] = value;
			if (x < WIDTH * TEXEL) { expected[y * WIDTH * TEXEL + x] = value; }
		}
	}
	const copyDst = GPUBufferUsage.COPY_DST as int32;
	const device = createBuffer(r, { label: "device", size: BUFFER_BYTES, usage: copyDst | (GPUBufferUsage.COPY_SRC as int32) | (GPUBufferUsage.VERTEX as int32) });
	if (!device.ok) { return refused("createBuffer device", device.error); }
	const readBuffer = createBuffer(r, { label: "read", size: BUFFER_BYTES, usage: copyDst | (GPUBufferUsage.MAP_READ as int32) });
	if (!readBuffer.ok) { return refused("createBuffer read", readBuffer.error); }
	const readTexels = createBuffer(r, { label: "texels", size: READ_PITCH * HEIGHT, usage: copyDst | (GPUBufferUsage.MAP_READ as int32) });
	if (!readTexels.ok) { return refused("createBuffer texels", readTexels.error); }
	const texture = createTexture(r, {
		label: "texture",
		size: { width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32) | (GPUTextureUsage.TEXTURE_BINDING as int32),
		sampleCount: 1,
		dimension: "2d",
		mipLevelCount: 1,
	});
	if (!texture.ok) { return refused("createTexture", texture.error); }
	const view = createView(r, texture.value, {
		label: "view",
		baseMipLevel: 0,
		mipLevelCount: 0,
		baseArrayLayer: 0,
		arrayLayerCount: 0,
	});
	if (!view.ok) { return refused("createView", view.error); }
	const sampler = createSampler(r, {
		label: "sampler",
		addressModeU: "repeat",
		addressModeV: "mirror-repeat",
		addressModeW: "clamp-to-edge",
		magFilter: "linear",
		minFilter: "linear",
		mipmapFilter: "linear",
		lodMinClamp: 0,
		lodMaxClamp: 0,
		maxAnisotropy: 4,
	});
	if (!sampler.ok) { return refused("createSampler", sampler.error); }

	const wroteBuffer = writeBuffer(r, device.value, 0, bufferBytes);
	if (!wroteBuffer.ok) { return refused("writeBuffer", wroteBuffer.error); }
	const copiedBuffer = copyBufferToBuffer(r, device.value, 0, readBuffer.value, 0, BUFFER_BYTES);
	if (!copiedBuffer.ok) { return refused("copyBufferToBuffer", copiedBuffer.error); }
	const wroteTexture = writeTexture(
		r,
		{ texture: texture.value, mipLevel: 0, origin: { x: 0, y: 0, z: 0 } },
		texels,
		{ offset: 0, bytesPerRow: SOURCE_PITCH, rowsPerImage: HEIGHT },
		{ width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
	);
	if (!wroteTexture.ok) { return refused("writeTexture", wroteTexture.error); }
	const copiedTexture = copyTextureToBuffer(
		r,
		{ texture: texture.value, mipLevel: 0, origin: { x: 0, y: 0, z: 0 } },
		{ buffer: readTexels.value, offset: 0, bytesPerRow: READ_PITCH, rowsPerImage: HEIGHT },
		{ width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
	);
	if (!copiedTexture.ok) { return refused("copyTextureToBuffer", copiedTexture.error); }
	const serial = submit(r);
	if (!serial.ok) { return refused("submit", serial.error); }
	const waited = wait(r, serial.value);
	if (!waited.ok) { return refused("wait", waited.error); }

	const bufferBack = readMapped(r, readBuffer.value, 0, BUFFER_BYTES);
	if (!bufferBack.ok) { return refused("readMapped buffer", bufferBack.error); }
	if (!compared("buffer", bufferBytes, bufferBack.value)) { vulkanShutdown(); return 1; }
	const texelsBack = readMapped(r, readTexels.value, 0, READ_PITCH * HEIGHT);
	if (!texelsBack.ok) { return refused("readMapped texels", texelsBack.error); }
	let packed: Vec<uint8> = new Array(WIDTH * TEXEL * HEIGHT);
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH * TEXEL; x++) { packed[y * WIDTH * TEXEL + x] = texelsBack.value[y * READ_PITCH + x]; }
	}
	if (!compared("texture", expected, packed)) { vulkanShutdown(); return 1; }

	destroyView(r, view.value);
	destroySampler(r, sampler.value);
	destroyTexture(r, texture.value);
	destroyBuffer(r, device.value);
	destroyBuffer(r, readBuffer.value);
	destroyBuffer(r, readTexels.value);
	const pending = r.retired.length;
	const drained = collect(r);
	if (!drained.ok) { return refused("collect", drained.error); }
	if (r.retired.length != 0 || r.memory.blockCount != 1) {
		console.log(`FAIL vulkan resources: ${pending} retired, ${r.retired.length} still held and ` +
			`${r.memory.blockCount} blocks open after the fence (the upload page alone should stay)`);
		vulkanShutdown();
		return 1;
	}
	console.log(`round trip: ${BUFFER_BYTES} buffer bytes and a ${WIDTH}x${HEIGHT} rgba8 texture at pitch ` +
		`${SOURCE_PITCH} match; ${pending} resources freed after serial ${serial.value}`);
	return 0;
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	console.log(`adapter ${vulkanAdapterName()}`);
	let r = openResources();
	if (roundTrip(r) != 0) { return 1; }
	const kept = createTexture(r, {
		label: "kept",
		size: { width: WIDTH, height: HEIGHT, depthOrArrayLayers: 1 },
		format: "rgba8unorm",
		usage: GPUTextureUsage.TEXTURE_BINDING as int32,
		sampleCount: 1,
		dimension: "2d",
		mipLevelCount: 1,
	});
	if (!kept.ok) { return refused("createTexture kept", kept.error); }
	const keptView = createView(r, kept.value, { label: "kept", baseMipLevel: 0, mipLevelCount: 0, baseArrayLayer: 0, arrayLayerCount: 0 });
	if (!keptView.ok) { return refused("createView kept", keptView.error); }
	const keptBuffer = createBuffer(r, { label: "kept", size: 64, usage: GPUBufferUsage.VERTEX as int32 });
	if (!keptBuffer.ok) { return refused("createBuffer kept", keptBuffer.error); }
	const closed = closeResources(r);
	if (!closed.ok) { return refused("closeResources", closed.error); }
	if (r.buffers.live() + r.textures.live() + r.views.live() != 0 || r.memory.blockCount != 0) {
		console.log(`FAIL vulkan resources: closeResources left ${r.buffers.live()} buffers, ${r.textures.live()} textures, ` +
			`${r.views.live()} views and ${r.memory.blockCount} blocks`);
		vulkanShutdown();
		return 1;
	}
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ${vulkanValidationWarnings()} warnings`);
	if (env.get("VOID_VULKAN_VALIDATION").equals("1") && !validated) {
		console.log("FAIL vulkan resources: VOID_VULKAN_VALIDATION=1 found no validation layer");
		return 1;
	}
	if (errors != 0) {
		console.log(`FAIL vulkan resources: ${errors} validation errors`);
		return 1;
	}
	console.log("PASS vulkan resources: buffer and odd-pitch texture round trip through staging");
	return 0;
}

process.exit(main());
