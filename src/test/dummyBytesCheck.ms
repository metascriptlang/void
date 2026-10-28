import { copyBytes, storeElements, storeTicks, zeroBytes } from "../webgpu/dummy/bytes.ms";

test "storeElements writes the little-endian bytes of each element type" {
	let bytes: Vec<uint8> = new Array(32);
	const floats: Vec<float32> = [1.0, -2.5];
	const shorts: Vec<uint16> = [0x0102, 0xFFFE];
	const ints: Vec<int32> = [-2, 0x01020304];
	storeElements(bytes, 0, floats);
	storeElements(bytes, 8, shorts);
	storeElements(bytes, 12, ints);
	const expected: uint8[] = [
		0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x20, 0xC0,
		0x02, 0x01, 0xFE, 0xFF,
		0xFE, 0xFF, 0xFF, 0xFF, 0x04, 0x03, 0x02, 0x01,
	];
	for (let i = 0; i < expected.length; i++) { assert bytes[i] == expected[i]; }
	for (let i = expected.length; i < 32; i++) { assert bytes[i] == 0; }
}

test "storeElements writes 8-byte and 1-byte elements" {
	let bytes: Vec<uint8> = new Array(16);
	const doubles: Vec<float64> = [1.0];
	const longs: Vec<int64> = [-1];
	const singles: Vec<uint8> = [7];
	storeElements(bytes, 0, doubles);
	storeElements(bytes, 8, longs);
	storeElements(bytes, 15, singles);
	const expected: uint8[] = [0, 0, 0, 0, 0, 0, 0xF0, 0x3F, 255, 255, 255, 255, 255, 255, 255, 7];
	for (let i = 0; i < expected.length; i++) { assert bytes[i] == expected[i]; }
}

test "storeTicks writes each query value as 8 bytes" {
	let bytes: Vec<uint8> = new Array(16);
	const ticks: Vec<uint64> = [0, 0x0102030405060708, 9];
	storeTicks(bytes, 0, ticks, 1, 2);
	const expected: uint8[] = [8, 7, 6, 5, 4, 3, 2, 1, 9, 0, 0, 0, 0, 0, 0, 0];
	for (let i = 0; i < expected.length; i++) { assert bytes[i] == expected[i]; }
}

test "copyBytes copies a range, also over itself in either direction, and zeroBytes clears one" {
	let bytes: Vec<uint8> = [1, 2, 3, 4, 5, 6, 7, 8];
	copyBytes(bytes, 2, bytes, 0, 4);
	const forward: uint8[] = [1, 2, 1, 2, 3, 4, 7, 8];
	for (let i = 0; i < forward.length; i++) { assert bytes[i] == forward[i]; }
	copyBytes(bytes, 0, bytes, 2, 4);
	const backward: uint8[] = [1, 2, 3, 4, 3, 4, 7, 8];
	for (let i = 0; i < backward.length; i++) { assert bytes[i] == backward[i]; }
	zeroBytes(bytes, 1, 3);
	const cleared: uint8[] = [1, 0, 0, 0, 3, 4, 7, 8];
	for (let i = 0; i < cleared.length; i++) { assert bytes[i] == cleared[i]; }
}
