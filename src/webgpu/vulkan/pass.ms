import { vulkanPassBegin, vulkanPassEnd, vulkanRenderPassCreate, vulkanRenderPassDestroy } from "./vulkan.h";
import {
	ACCESS_COLOR_ATTACHMENT_READ,
	ACCESS_COLOR_ATTACHMENT_WRITE,
	ACCESS_DEPTH_STENCIL_ATTACHMENT_READ,
	ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE,
	ASPECT_STENCIL,
	LAYOUT_COLOR_ATTACHMENT,
	LAYOUT_DEPTH_STENCIL_ATTACHMENT,
	LOAD_OP_DONT_CARE,
	STAGE_COLOR_ATTACHMENT_OUTPUT,
	STAGE_EARLY_FRAGMENT_TESTS,
	STAGE_LATE_FRAGMENT_TESTS,
	STORE_OP_DONT_CARE,
	loadOp,
	storeOp,
} from "./conv";
import { writeToTexture } from "./tracker";
import { slotOf, textureRecords, viewRecords } from "../pool.ms";
import {
	ResourceError,
	VULKAN_OK,
	VulkanResources,
	checked,
	flush,
	settle,
	stopOnVulkan,
} from "./resources";
import { GPUExtent3D, GPU_MAX_COLOR_ATTACHMENTS, GPURenderPassDescriptor, stop } from "../types.ms";

@passC("-I../../../deps/vulkan-headers/include");

export const COLOR_KEY_WORDS: int32 = 5;
export const DEPTH_KEY_WORDS: int32 = 8;

const COLOR_ACCESS: uint32 = ACCESS_COLOR_ATTACHMENT_READ | ACCESS_COLOR_ATTACHMENT_WRITE;
const DEPTH_ACCESS: uint32 = ACCESS_DEPTH_STENCIL_ATTACHMENT_READ | ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE;
const DEPTH_STAGES: uint32 = STAGE_EARLY_FRAGMENT_TESTS | STAGE_LATE_FRAGMENT_TESTS;

struct CachedPass {
	start: int32;
	words: int32;
	native: uint64;
}

export struct RenderPassCache {
	keys: Vec<uint32>;
	passes: Vec<CachedPass>;
}

export function newRenderPassCache(): RenderPassCache {
	return { keys: [], passes: [] };
}

export function newPassKey(): Vec<uint32> {
	return [0];
}

export function colorKeyWords(ref key: Vec<uint32>, format: int32, samples: int32, load: uint32, store: uint32, resolveFormat: int32): void {
	key[0] += 1;
	key.push(format as uint32);
	key.push(samples as uint32);
	key.push(load);
	key.push(store);
	key.push(resolveFormat as uint32);
}

export function unusedColorKeyWords(ref key: Vec<uint32>): void {
	colorKeyWords(key, 0, 1, LOAD_OP_DONT_CARE, STORE_OP_DONT_CARE, 0);
}

export function depthKeyWords(
	ref key: Vec<uint32>,
	format: int32,
	samples: int32,
	load: uint32,
	store: uint32,
	stencil: boolean,
	readOnly: boolean,
): void {
	key.push(1);
	key.push(format as uint32);
	key.push(samples as uint32);
	key.push(load);
	key.push(store);
	key.push(stencil ? load : LOAD_OP_DONT_CARE);
	key.push(stencil ? store : STORE_OP_DONT_CARE);
	key.push(readOnly ? 1 : 0);
}

export function noDepthKeyWords(ref key: Vec<uint32>): void {
	for (let i: int32 = 0; i < DEPTH_KEY_WORDS; i++) { key.push(0); }
}

export function cachedPass(this cache: RenderPassCache, key: Readonly<Span<uint32>>): uint64 {
	for (const pass of cache.passes) {
		if (pass.words != key.length) { continue; }
		let same = true;
		for (let i: int32 = 0; i < pass.words && same; i++) { same = cache.keys[pass.start + i] == key[i]; }
		if (same) { return pass.native; }
	}
	return 0;
}

export function rememberPass(ref cache: RenderPassCache, key: Readonly<Span<uint32>>, native: uint64): void {
	cache.passes.push({ start: cache.keys.length, words: key.length, native: native });
	for (const word of key) { cache.keys.push(word); }
}

export function closeRenderPasses(ref cache: RenderPassCache): void {
	for (const pass of cache.passes) { vulkanRenderPassDestroy(pass.native); }
	cache.passes.length = 0;
	cache.keys.length = 0;
}

@noinline function refuseSlice(member: string): never {
	stop(`${member} is a 3d view: a depth-slice attachment is not built on Vulkan`);
}

function attached(member: string, id: uint32): int32 {
	const view = viewRecords.record(id);
	if (view.dimension == "3d") { refuseSlice(member); }
	return slotOf(view.texture);
}

export function beginRenderPass(
	ref r: VulkanResources,
	ref cache: RenderPassCache,
	descriptor: GPURenderPassDescriptor,
	extent: GPUExtent3D,
): Result<void, ResourceError> {
	settle(r);
	let key = newPassKey();
	let views: Vec<uint64> = [];
	let clears: Vec<float32> = [];
	let colors: int32 = 0;
	for (let i: int32 = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (descriptor.colorAttachments[i].view.id != 0) { colors = i + 1; }
	}
	for (let i: int32 = 0; i < colors; i++) {
		const attachment = descriptor.colorAttachments[i];
		if (attachment.view.id == 0) {
			unusedColorKeyWords(key);
			for (let c = 0; c < 4; c++) { clears.push(0.0); }
			continue;
		}
		const t = attached(`colorAttachments[${i}].view`, attachment.view.id);
		const texture = r.textures[t];
		let resolveFormat: int32 = 0;
		views.push(r.views[slotOf(attachment.view.id)].native);
		if (attachment.resolveTarget.id != 0) {
			const resolve = r.textures[attached(`colorAttachments[${i}].resolveTarget`, attachment.resolveTarget.id)];
			resolveFormat = resolve.info.native;
			views.push(r.views[slotOf(attachment.resolveTarget.id)].native);
			writeToTexture(r.tracker, resolve.native, resolve.rest, STAGE_COLOR_ATTACHMENT_OUTPUT, COLOR_ACCESS, LAYOUT_COLOR_ATTACHMENT);
		}
		colorKeyWords(
			key,
			texture.info.native,
			textureRecords.slots[t].sampleCount,
			loadOp(attachment.loadOp, `colorAttachments[${i}].loadOp`),
			storeOp(attachment.storeOp, `colorAttachments[${i}].storeOp`),
			resolveFormat,
		);
		clears.push(attachment.clearValue.r as float32);
		clears.push(attachment.clearValue.g as float32);
		clears.push(attachment.clearValue.b as float32);
		clears.push(attachment.clearValue.a as float32);
		writeToTexture(r.tracker, texture.native, texture.rest, STAGE_COLOR_ATTACHMENT_OUTPUT, COLOR_ACCESS, LAYOUT_COLOR_ATTACHMENT);
	}
	const depth = descriptor.depthStencilAttachment;
	if (depth.view.id != 0) {
		const t = attached("depthStencilAttachment.view", depth.view.id);
		const texture = r.textures[t];
		depthKeyWords(
			key,
			texture.info.native,
			textureRecords.slots[t].sampleCount,
			loadOp(depth.depthLoadOp, "depthStencilAttachment.depthLoadOp"),
			storeOp(depth.depthStoreOp, "depthStencilAttachment.depthStoreOp"),
			(texture.info.aspect & ASPECT_STENCIL) != 0,
			false,
		);
		views.push(r.views[slotOf(depth.view.id)].native);
		clears.push(depth.depthClearValue);
		clears.push(0.0);
		writeToTexture(r.tracker, texture.native, texture.rest, DEPTH_STAGES, DEPTH_ACCESS, LAYOUT_DEPTH_STENCIL_ATTACHMENT);
	} else {
		noDepthKeyWords(key);
	}
	try flush(r);
	let native = cache.cachedPass(key);
	if (native == 0) {
		try checked(vulkanRenderPassCreate(key[0], key.length as uint32, native));
		rememberPass(cache, key, native);
	}
	return checked(vulkanPassBegin(
		native,
		key[0],
		key.length as uint32,
		views[0],
		views.length as uint32,
		extent.width as uint32,
		extent.height as uint32,
		clears[0],
		clears.length as uint32,
	));
}

export function endRenderPass(): void {
	if (vulkanPassEnd() != VULKAN_OK) { stopOnVulkan(); }
}
