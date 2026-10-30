import {
	DOOR_STAT_RESIDENT_BUFFER_BYTES, DOOR_STAT_RESIDENT_IMAGE_BYTES,
	DOOR_STAT_RESIDENT_TARGET_BYTES, DOOR_STAT_PER_FRAME_COUNT, DOOR_STAT_COUNT,
	doorFrameStat, trackBuffer, untrackBuffer, trackTexture, untrackTexture, textureBytes,
	texelBytes,
} from "../gpu/doorGpu.ms";
import { GPUExtent3D } from "../webgpu/types.ms";

function extent(width: int32, height: int32, layers: int32): GPUExtent3D {
	return { width, height, depthOrArrayLayers: layers };
}

function residentTotal(): int64 {
	let total: int64 = 0;
	for (let i = DOOR_STAT_PER_FRAME_COUNT; i < DOOR_STAT_COUNT; i++) { total += doorFrameStat(i); }
	return total;
}

test "resident buffer bytes rise by what a buffer holds and return exactly when it is destroyed" {
	const before = doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES);
	trackBuffer(900001, 64);
	trackBuffer(900002, 4096);
	assert doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES) == before + 4160;
	untrackBuffer(900001);
	assert doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES) == before + 4096;
	untrackBuffer(900002);
	assert doorFrameStat(DOOR_STAT_RESIDENT_BUFFER_BYTES) == before;
}

test "an image and a render target count under their own stat, over four gigabytes without wrapping" {
	const image = doorFrameStat(DOOR_STAT_RESIDENT_IMAGE_BYTES);
	const target = doorFrameStat(DOOR_STAT_RESIDENT_TARGET_BYTES);
	const total = residentTotal();
	const big = textureBytes("rgba16float", extent(16384, 16384, 4), 1);
	assert big == 8589934592;
	trackTexture(900003, 4 * 1024, false);
	trackTexture(900004, big, true);
	assert doorFrameStat(DOOR_STAT_RESIDENT_IMAGE_BYTES) == image + 4096;
	assert doorFrameStat(DOOR_STAT_RESIDENT_TARGET_BYTES) == target + big;
	untrackTexture(900004);
	untrackTexture(900003);
	assert doorFrameStat(DOOR_STAT_RESIDENT_IMAGE_BYTES) == image;
	assert doorFrameStat(DOOR_STAT_RESIDENT_TARGET_BYTES) == target;
	assert residentTotal() == total;
}

test "a buffer and an image with the same id are two resources" {
	const total = residentTotal();
	trackBuffer(900005, 8);
	trackTexture(900005, 16, false);
	untrackBuffer(900005);
	assert residentTotal() == total + 16;
	untrackTexture(900005);
	assert residentTotal() == total;
}

test "a texture's bytes are its levels and layers times its texel size" {
	assert textureBytes("rgba8unorm", extent(4, 4, 1), 1) == 64;
	assert textureBytes("rgba8unorm", extent(4, 4, 1), 3) == 64 + 16 + 4;
	assert textureBytes("rgba8unorm", extent(8, 4, 6), 4) == (32 + 8 + 2 + 1) * 6 * 4;
	assert textureBytes("r8unorm", extent(3, 5, 1), 1) == 15;
	assert textureBytes("depth32float", extent(2, 2, 1), 1) == 16;
	assert texelBytes("rgba16float") == 8;
}
