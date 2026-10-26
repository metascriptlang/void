import { GPUBufferUsage, GPUTextureUsage } from "../webgpu/types.ms";
import {
	ACCESS_HOST_READ,
	ACCESS_SHADER_READ,
	ACCESS_TRANSFER_WRITE,
	ASPECT_COLOR,
	LAYOUT_GENERAL,
	LAYOUT_SHADER_READ_ONLY,
	LAYOUT_TRANSFER_DST,
	STAGE_COMPUTE_SHADER,
	STAGE_FRAGMENT_SHADER,
	STAGE_HOST,
	STAGE_VERTEX_SHADER,
	bufferRest,
	compareOp,
	cubeCompatible,
	depthStencilNative,
	formatInfo,
	rowLength,
	textureRest,
} from "../webgpu/vulkan/conv";
import {
	ACCESS_TRANSFER_READ,
	LAYOUT_TRANSFER_SRC,
	LAYOUT_UNDEFINED,
	STAGE_TRANSFER,
	cleared,
	copyFromBuffer,
	copyFromTexture,
	endPass,
	initTexture,
	newTracker,
	readFromTexture,
	writeToBuffer,
	writeToTexture,
} from "../webgpu/vulkan/tracker";

const SHADER_STAGES: uint32 = STAGE_VERTEX_SHADER | STAGE_FRAGMENT_SHADER | STAGE_COMPUTE_SHADER;

function readback(): int32 { return (GPUBufferUsage.MAP_READ as int32) | (GPUBufferUsage.COPY_DST as int32); }

function sampled(): int32 {
	return (GPUTextureUsage.COPY_SRC as int32) | (GPUTextureUsage.COPY_DST as int32) |
		(GPUTextureUsage.TEXTURE_BINDING as int32);
}

test "a readback buffer rests in host reads with transfer added for its copy usage" {
	const rest = bufferRest(readback());
	assert rest.stages == (STAGE_HOST | STAGE_TRANSFER);
	assert rest.access == ACCESS_HOST_READ;
	const staging = bufferRest((GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32));
	assert staging.stages == STAGE_TRANSFER;
	assert staging.access == ACCESS_TRANSFER_READ;
}

test "a sampled texture rests in shader-read-only with its copy stages, a copy-only one in general" {
	const rest = textureRest(sampled(), ASPECT_COLOR);
	assert rest.layout == LAYOUT_SHADER_READ_ONLY;
	assert rest.stages == (SHADER_STAGES | STAGE_TRANSFER);
	assert rest.access == (ACCESS_SHADER_READ | ACCESS_TRANSFER_READ);
	const copyOnly = textureRest(GPUTextureUsage.COPY_DST as int32, ASPECT_COLOR);
	assert copyOnly.layout == LAYOUT_GENERAL;
	assert copyOnly.stages == STAGE_TRANSFER;
}

test "a buffer copy waits on the target's resting reads and endPass returns it to them" {
	let t = newTracker();
	const staging = bufferRest((GPUBufferUsage.MAP_WRITE as int32) | (GPUBufferUsage.COPY_SRC as int32));
	const target = bufferRest(readback());
	copyFromBuffer(t, 1);
	writeToBuffer(t, 2, target, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	assert t.sourceStages == target.stages;
	assert t.targetStages == STAGE_TRANSFER;
	assert t.sourceAccess == 0 && t.targetAccess == 0;
	cleared(t);
	endPass(t);
	assert t.sourceStages == STAGE_TRANSFER;
	assert t.targetStages == target.stages;
	assert t.sourceAccess == ACCESS_TRANSFER_WRITE;
	assert t.targetAccess == ACCESS_HOST_READ;
	assert t.copyBuffers.length == 0 && t.writtenBuffers.length == 0;
	assert staging.stages == STAGE_TRANSFER;
}

test "a second write to one buffer is a write-after-write on the first" {
	let t = newTracker();
	const target = bufferRest(readback());
	writeToBuffer(t, 2, target, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	cleared(t);
	writeToBuffer(t, 2, target, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE);
	assert t.sourceStages == STAGE_TRANSFER;
	assert t.sourceAccess == ACCESS_TRANSFER_WRITE;
	assert t.targetAccess == ACCESS_TRANSFER_WRITE;
	assert t.writtenBuffers.length == 1;
}

test "a new texture leaves undefined for its resting layout, then a write waits on that rest" {
	let t = newTracker();
	const rest = textureRest(sampled(), ASPECT_COLOR);
	initTexture(t, 5, rest);
	assert t.images.length == 1;
	assert t.images[0].oldLayout == LAYOUT_UNDEFINED && t.images[0].newLayout == LAYOUT_SHADER_READ_ONLY;
	assert t.sourceStages == 0 && t.targetStages == rest.stages;
	cleared(t);
	writeToTexture(t, 5, rest, STAGE_TRANSFER, ACCESS_TRANSFER_WRITE, LAYOUT_TRANSFER_DST);
	assert t.sourceStages == rest.stages;
	assert t.images.length == 1;
	assert t.images[0].oldLayout == LAYOUT_SHADER_READ_ONLY && t.images[0].newLayout == LAYOUT_TRANSFER_DST;
	assert t.images[0].sourceAccess == 0 && t.images[0].targetAccess == ACCESS_TRANSFER_WRITE;
	cleared(t);
	copyFromTexture(t, 5, rest);
	assert t.sourceStages == STAGE_TRANSFER;
	assert t.images[0].oldLayout == LAYOUT_TRANSFER_DST && t.images[0].newLayout == LAYOUT_TRANSFER_SRC;
	assert t.images[0].sourceAccess == ACCESS_TRANSFER_WRITE && t.images[0].targetAccess == ACCESS_TRANSFER_READ;
}

test "a layout change on a read waits on the stages it leaves" {
	let t = newTracker();
	const rest = textureRest(sampled(), ASPECT_COLOR);
	copyFromTexture(t, 5, rest);
	assert t.sourceStages == rest.stages;
	assert t.targetStages == STAGE_TRANSFER;
	cleared(t);
	readFromTexture(t, 5, rest, rest.stages, rest.access, rest.layout);
	assert t.sourceStages == STAGE_TRANSFER;
	assert t.images[0].oldLayout == LAYOUT_TRANSFER_SRC && t.images[0].newLayout == LAYOUT_SHADER_READ_ONLY;
	cleared(t);
	readFromTexture(t, 5, rest, rest.stages, rest.access, rest.layout);
	assert t.sourceStages == 0;
	assert t.images.length == 0;
}

test "endPass returns a copied-from texture to its rest after the transfer" {
	let t = newTracker();
	const rest = textureRest(sampled(), ASPECT_COLOR);
	copyFromTexture(t, 5, rest);
	cleared(t);
	endPass(t);
	assert t.sourceStages == STAGE_TRANSFER;
	assert t.targetStages == rest.stages;
	assert t.images.length == 1;
	assert t.images[0].oldLayout == LAYOUT_TRANSFER_SRC && t.images[0].newLayout == LAYOUT_SHADER_READ_ONLY;
	assert t.copyTextures.length == 0;
}

test "formats, rows and members map onto their Vulkan values" {
	assert formatInfo("rgb10a2unorm", 0, "format").native == 64;
	assert formatInfo("rgba8unorm", 0, "format").texelBytes == 4;
	assert formatInfo("depth24plus-stencil8", 129, "format").native == 129;
	assert depthStencilNative(0x200) == 129;
	assert depthStencilNative(0) == 130;
	assert rowLength(256, 4) == 64;
	assert rowLength(52, 4) == 13;
	assert compareOp("", "compare") == -1;
	assert compareOp("greater-equal", "compare") == 6;
	assert cubeCompatible(false, 64, 64, 6, 1);
	assert !cubeCompatible(false, 64, 64, 6, 4);
	assert !cubeCompatible(true, 64, 64, 6, 1);
}
