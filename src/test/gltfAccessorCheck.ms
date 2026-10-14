import {
	GltfAccessorBuffer,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
	GltfAccessorError,
	GltfAccessorLayout,
	GltfAccessorValues,
	GltfAccessorIndices,
} from "../void3d/gltfAccessor";

function scalarFixture(component: int32, count: int32): GltfAccessorSource {
	return {
		bufferView: 0, byteOffset: null, componentType: component,
		shape: GltfAccessorShape.Scalar, normalized: false, count: count,
		role: GltfAccessorRole.Other, sparse: null,
	};
}

function packedView(length: int32): GltfAccessorView {
	return {
		buffer: 0, byteOffset: 0, byteLength: length, byteStride: null, target: null,
	};
}

test "gltfAccessor final strided element needs no trailing stride padding" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [90, 91, 92, 93, 1, 2, 3, 88, 80, 81, 82, 83, 4, 5, 6],
		byteLength: 15,
	}];
	const views: Vec<GltfAccessorView> = [{
		buffer: 0, byteOffset: 0, byteLength: 15, byteStride: 8, target: 34962,
	}];
	const base = scalarFixture(5121, 2);
	const source: GltfAccessorSource = {
		...base, byteOffset: 4, shape: GltfAccessorShape.Vec3,
		role: GltfAccessorRole.Attribute,
	};
	const layout = GltfAccessorLayout.fromSource(source, buffers, views);
	assert layout.ok;
	if (layout.ok) {
		assert layout.value.elementBytes == 3;
		assert layout.value.stride == 8;
	}
	const decoded = GltfAccessorValues.decode(source, buffers, views);
	assert decoded.ok;
	if (!decoded.ok) { return; }
	const data = decoded.value;
	assert data.values.length == 6;
	assert data.values[0] == 1.0 && data.values[2] == 3.0;
	assert data.values[3] == 4.0 && data.values[5] == 6.0;
	const shortViews: Vec<GltfAccessorView> = [{ ...views[0], byteLength: 14 }];
	const short = GltfAccessorValues.decode(source, buffers, shortViews);
	assert !short.ok;
	if (!short.ok) { assert short.error == GltfAccessorError.Bounds; }
	const oddStride: Vec<GltfAccessorView> = [{ ...views[0], byteStride: 7 }];
	assert !GltfAccessorValues.decode(source, buffers, oddStride).ok;
	const wrongTarget: Vec<GltfAccessorView> = [{ ...views[0], target: 34963 }];
	assert !GltfAccessorValues.decode(source, buffers, wrongTarget).ok;
}

test "gltfAccessor sparse zero and dense bases replace rather than add and own bytes" {
	let buffers: Vec<GltfAccessorBuffer> = [
		{ bytes: [0, 0, 0, 0, 2, 0, 0, 0], byteLength: 8 },
		{ bytes: [7, 11], byteLength: 2 },
		{ bytes: [1, 2, 3, 4], byteLength: 4 },
	];
	const views: Vec<GltfAccessorView> = [
		packedView(8),
		{ ...packedView(2), buffer: 1 },
		{ ...packedView(4), buffer: 2 },
	];
	const base = scalarFixture(5121, 4);
	const source: GltfAccessorSource = {
		...base, bufferView: null,
		sparse: {
			count: 2, indicesView: 0, indicesByteOffset: 0, indicesComponentType: 5125,
			valuesView: 1, valuesByteOffset: 0,
		},
	};
	const zero = GltfAccessorValues.decode(source, buffers, views);
	assert zero.ok;
	if (!zero.ok) { return; }
	const zeroData = zero.value;
	assert zeroData.values[0] == 7.0 && zeroData.values[1] == 0.0;
	assert zeroData.values[2] == 11.0 && zeroData.values[3] == 0.0;
	const denseSource: GltfAccessorSource = { ...source, bufferView: 2 };
	const dense = GltfAccessorValues.decode(denseSource, buffers, views);
	assert dense.ok;
	if (!dense.ok) { return; }
	const denseData = dense.value;
	assert denseData.values[0] == 7.0 && denseData.values[1] == 2.0;
	assert denseData.values[2] == 11.0 && denseData.values[3] == 4.0;
	buffers[1].bytes[0] = 99;
	assert zeroData.values[0] == 7.0 && denseData.values[0] == 7.0;
	buffers[0].bytes[4] = 0;
	const duplicate = GltfAccessorValues.decode(source, buffers, views);
	assert !duplicate.ok;
	if (!duplicate.ok) { assert duplicate.error == GltfAccessorError.SparseOrder; }
	buffers[0].bytes[0] = 2;
	const descending = GltfAccessorValues.decode(source, buffers, views);
	assert !descending.ok;
	if (!descending.ok) { assert descending.error == GltfAccessorError.SparseOrder; }
	buffers[0].bytes[0] = 0;
	buffers[0].bytes[4] = 4;
	assert !GltfAccessorValues.decode(source, buffers, views).ok;
	buffers[0].bytes[4] = 2;
	const targeted: Vec<GltfAccessorView> = [
		views[0], { ...views[1], target: 34962 }, views[2],
	];
	assert !GltfAccessorValues.decode(source, buffers, targeted).ok;
	const strided: Vec<GltfAccessorView> = [
		{ ...views[0], byteStride: 4 }, views[1], views[2],
	];
	assert !GltfAccessorValues.decode(source, buffers, strided).ok;
}

test "gltfAccessor matrix columns skip byte and short padding" {
	const bytes: Vec<uint8> = [1, 2, 3, 99, 4, 5, 6, 99, 7, 8, 9, 99];
	const buffers: Vec<GltfAccessorBuffer> = [{ bytes: bytes, byteLength: 12 }];
	const views: Vec<GltfAccessorView> = [packedView(12)];
	const base = scalarFixture(5121, 1);
	const source: GltfAccessorSource = { ...base, shape: GltfAccessorShape.Mat3 };
	const decoded = GltfAccessorValues.decode(source, buffers, views);
	assert decoded.ok;
	if (!decoded.ok) { return; }
	const data = decoded.value;
	assert data.values.length == 9;
	for (let i = 0; i < 9; i++) { assert data.values[i] == (i + 1) as float64; }
	const shorts: Vec<GltfAccessorBuffer> = [{
		bytes: [1, 0, 2, 0, 3, 0, 99, 99, 4, 0, 5, 0, 6, 0, 99, 99,
			7, 0, 8, 0, 9, 0, 99, 99],
		byteLength: 24,
	}];
	const shortViews: Vec<GltfAccessorView> = [packedView(24)];
	const shortSource: GltfAccessorSource = { ...source, componentType: 5123 };
	const decodedShorts = GltfAccessorValues.decode(shortSource, shorts, shortViews);
	assert decodedShorts.ok;
	if (!decodedShorts.ok) { return; }
	const shortData = decodedShorts.value;
	for (let i = 0; i < 9; i++) { assert shortData.values[i] == (i + 1) as float64; }
}

test "gltfAccessor signed normalization clamps redundant negative encodings" {
	const bytes: Vec<GltfAccessorBuffer> = [{ bytes: [128, 129, 127], byteLength: 3 }];
	const views: Vec<GltfAccessorView> = [packedView(3)];
	const base = scalarFixture(5120, 3);
	const source: GltfAccessorSource = { ...base, normalized: true };
	const decoded = GltfAccessorValues.decode(source, bytes, views);
	assert decoded.ok;
	if (decoded.ok) {
		assert decoded.value.values[0] == -1.0;
		assert decoded.value.values[1] == -1.0 && decoded.value.values[2] == 1.0;
	}
	const shorts: Vec<GltfAccessorBuffer> = [{
		bytes: [0, 128, 1, 128, 255, 127], byteLength: 6,
	}];
	const shortViews: Vec<GltfAccessorView> = [packedView(6)];
	const shortSource: GltfAccessorSource = { ...source, componentType: 5122 };
	const decodedShorts = GltfAccessorValues.decode(shortSource, shorts, shortViews);
	assert decodedShorts.ok;
	if (decodedShorts.ok) {
		assert decodedShorts.value.values[0] == -1.0;
		assert decodedShorts.value.values[1] == -1.0 && decodedShorts.value.values[2] == 1.0;
	}
}

test "gltfAccessor index source width survives u16 boundary and high u32 bit" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [0, 0, 1, 0, 1, 0, 0, 128], byteLength: 8,
	}];
	const views: Vec<GltfAccessorView> = [packedView(8)];
	const base = scalarFixture(5125, 2);
	const source: GltfAccessorSource = { ...base, role: GltfAccessorRole.Indices };
	const highBit: uint32 = 0x80000000;
	const decoded = GltfAccessorIndices.fromAccessor(source, buffers, views, highBit + 2);
	assert decoded.ok;
	if (decoded.ok) {
		assert decoded.value.componentType == 5125;
		assert decoded.value.values[0] == 65536 as uint32;
		assert decoded.value.values[1] == highBit + 1;
	}
	const shortBuffers: Vec<GltfAccessorBuffer> = [{ bytes: [254, 255], byteLength: 2 }];
	const shortViews: Vec<GltfAccessorView> = [packedView(2)];
	const shortSource: GltfAccessorSource = { ...source, componentType: 5123, count: 1 };
	const small = GltfAccessorIndices.fromAccessor(shortSource, shortBuffers, shortViews, 65536);
	assert small.ok;
	if (small.ok) {
		assert small.value.componentType == 5123 && small.value.values[0] == 65534 as uint32;
	}
	const sentinel: Vec<GltfAccessorBuffer> = [{ bytes: [255, 255], byteLength: 2 }];
	assert !GltfAccessorIndices.fromAccessor(shortSource, sentinel, shortViews, 65536).ok;
	assert !GltfAccessorIndices.fromAccessor(source, buffers, views, 65536).ok;
	const byteSource: GltfAccessorSource = { ...source, componentType: 5121, count: 1 };
	const byteViews: Vec<GltfAccessorView> = [packedView(1)];
	const byteSentinel: Vec<GltfAccessorBuffer> = [{ bytes: [255], byteLength: 1 }];
	assert !GltfAccessorIndices.fromAccessor(byteSource, byteSentinel, byteViews, 256).ok;
	const wideSentinel: Vec<GltfAccessorBuffer> = [{
		bytes: [255, 255, 255, 255], byteLength: 4,
	}];
	const wideViews: Vec<GltfAccessorView> = [packedView(4)];
	const wideSource: GltfAccessorSource = { ...source, count: 1 };
	const maximum: uint32 = 0xffffffff;
	assert !GltfAccessorIndices.fromAccessor(wideSource, wideSentinel, wideViews, maximum).ok;
}

test "gltfAccessor byte and short RGBA attributes require a declared stride" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [255, 255, 255, 255, 255, 255, 255, 255], byteLength: 8,
	}];
	const views: Vec<GltfAccessorView> = [packedView(8)];
	const source: GltfAccessorSource = {
		bufferView: 0, byteOffset: 0, componentType: 5121,
		shape: GltfAccessorShape.Vec4, normalized: true, count: 1,
		role: GltfAccessorRole.Attribute, sparse: null,
	};
	const packedByte = GltfAccessorValues.decode(source, buffers, views);
	assert !packedByte.ok;
	if (!packedByte.ok) { assert packedByte.error == GltfAccessorError.Alignment; }
	const byteViews: Vec<GltfAccessorView> = [{ ...views[0], byteStride: 4 }];
	const byte = GltfAccessorValues.decode(source, buffers, byteViews);
	assert byte.ok;
	if (byte.ok) {
		assert byte.value.values.length == 4;
		for (const value of byte.value.values) { assert value == 1.0; }
	}
	const shortSource: GltfAccessorSource = { ...source, componentType: 5123 };
	const packedShort = GltfAccessorValues.decode(shortSource, buffers, views);
	assert !packedShort.ok;
	if (!packedShort.ok) { assert packedShort.error == GltfAccessorError.Alignment; }
	const shortViews: Vec<GltfAccessorView> = [{ ...views[0], byteStride: 8 }];
	const short = GltfAccessorValues.decode(shortSource, buffers, shortViews);
	assert short.ok;
	if (short.ok) {
		assert short.value.values.length == 4;
		for (const value of short.value.values) { assert value == 1.0; }
	}
}

test "gltfAccessor refuses malformed metadata before component reads" {
	const buffers: Vec<GltfAccessorBuffer> = [{ bytes: [0, 0, 128, 63], byteLength: 4 }];
	const views: Vec<GltfAccessorView> = [packedView(4)];
	const source = scalarFixture(5126, 1);
	const normalized: GltfAccessorSource = { ...source, normalized: true };
	assert !GltfAccessorValues.decode(normalized, buffers, views).ok;
	const normalizedWide: GltfAccessorSource = {
		...normalized, componentType: 5125,
	};
	assert !GltfAccessorValues.decode(normalizedWide, buffers, views).ok;
	const empty: GltfAccessorSource = { ...source, count: 0 };
	assert !GltfAccessorValues.decode(empty, buffers, views).ok;
	const overflow: GltfAccessorSource = { ...source, count: 0x7fffffff };
	assert !GltfAccessorValues.decode(overflow, buffers, views).ok;
	const unaligned: GltfAccessorSource = { ...source, byteOffset: 1 };
	assert !GltfAccessorValues.decode(unaligned, buffers, views).ok;
	const absentOffset: GltfAccessorSource = { ...source, bufferView: null, byteOffset: 0 };
	assert !GltfAccessorValues.decode(absentOffset, buffers, views).ok;
	const strideViews: Vec<GltfAccessorView> = [{ ...views[0], byteStride: 4 }];
	assert !GltfAccessorValues.decode(source, buffers, strideViews).ok;
	const attribute: GltfAccessorSource = {
		...source, componentType: 5121, role: GltfAccessorRole.Attribute,
	};
	assert !GltfAccessorValues.decode(attribute, buffers, views).ok;
	const badTarget: Vec<GltfAccessorView> = [{ ...views[0], target: 34962 }];
	assert !GltfAccessorValues.decode(source, buffers, badTarget).ok;
	const shortBuffers: Vec<GltfAccessorBuffer> = [{ ...buffers[0], byteLength: 3 }];
	assert !GltfAccessorValues.decode(source, shortBuffers, views).ok;
	const unalignedViews: Vec<GltfAccessorView> = [{ ...views[0], byteOffset: 1 }];
	assert !GltfAccessorValues.decode(source, buffers, unalignedViews).ok;
	const infinity: Vec<GltfAccessorBuffer> = [{ bytes: [0, 0, 128, 127], byteLength: 4 }];
	const infinite = GltfAccessorValues.decode(source, infinity, views);
	assert !infinite.ok;
	if (!infinite.ok) { assert infinite.error == GltfAccessorError.NonFinite; }
	const nan: Vec<GltfAccessorBuffer> = [{ bytes: [1, 0, 128, 127], byteLength: 4 }];
	assert !GltfAccessorValues.decode(source, nan, views).ok;
}
