import { approx } from "./helpers";
import {
	SkinInfluences, SkinInfluencesError, fromPacked, fromAccessor,
} from "../void3d/skinInfluences";
import {
	GltfAccessorBuffer,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
} from "../void3d/gltfAccessor";

function attribute(view: int32, component: int32, normalized: boolean): GltfAccessorSource {
	return {
		bufferView: view, byteOffset: 0, componentType: component,
		shape: GltfAccessorShape.Vec4, normalized: normalized, count: 1,
		role: GltfAccessorRole.Attribute, sparse: null,
	};
}

test "packed u8 joints and float weights preserve canonical slots and normalize ratios" {
	const made = SkinInfluences.fromPacked(
		[2, 1, 0, 0], [0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0],
		1, 3, 5121, 5126, false, false,
	);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.joints[0] == 2 && made.value.joints[1] == 1;
	assert approx(made.value.weights[0], 0.5) && approx(made.value.weights[1], 0.5);
}

test "u16 joints are little endian, not a 255-joint or 64-joint rig cap" {
	const made = SkinInfluences.fromPacked(
		[0, 1, 1, 1, 0, 0, 0, 0], [255, 0, 0, 0],
		1, 300, 5123, 5121, false, true,
	);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.joints[0] == 256 && made.value.joints[1] == 257;
	assert made.value.weights[0] == 1.0;
}

test "quantized weights require normalized accessors and exact integer sums" {
	const u8 = SkinInfluences.fromPacked(
		[0, 1, 0, 0], [128, 127, 0, 0], 1, 2, 5121, 5121, false, true,
	);
	assert u8.ok;
	if (u8.ok) {
		assert approx(u8.value.weights[0], 128.0 / 255.0);
		assert approx(u8.value.weights[1], 127.0 / 255.0);
	}
	const u16 = SkinInfluences.fromPacked(
		[0, 1, 0, 0], [0, 128, 255, 127, 0, 0, 0, 0], 1, 2, 5121, 5123, false, true,
	);
	assert u16.ok;
	const bad = SkinInfluences.fromPacked(
		[0, 1, 0, 0], [128, 128, 0, 0], 1, 2, 5121, 5121, false, true,
	);
	assert !bad.ok;
	if (!bad.ok) { assert bad.error == SkinInfluencesError.WeightSum; }
}

test "packed influence shape, encoding and joint trust boundaries reject malformed bytes" {
	assert !SkinInfluences.fromPacked(
		[0, 0, 0], [255, 0, 0, 0], 1, 1, 5121, 5121, false, true,
	).ok;
	assert !SkinInfluences.fromPacked(
		[0, 0, 0, 0], [255, 0, 0, 0], 1, 1, 5121, 5121, true, true,
	).ok;
	assert !SkinInfluences.fromPacked(
		[0, 0, 0, 0], [255, 0, 0, 0], 1, 1, 5121, 5121, false, false,
	).ok;
	assert !SkinInfluences.fromPacked(
		[0, 0, 0, 0], [255, 0, 0, 0], 1, 1, 5121, 5121, false, true, 2,
	).ok;
	const range = SkinInfluences.fromPacked(
		[0, 1, 0, 0], [255, 0, 0, 0], 1, 1, 5121, 5121, false, true,
	);
	assert !range.ok;
	if (!range.ok) { assert range.error == SkinInfluencesError.JointOutOfRange; }
}

test "a joint cannot have two positive weights, but zero-weight duplicates remain legal" {
	const made = SkinInfluences.fromPacked(
		[0, 0, 0, 0], [128, 127, 0, 0], 1, 1, 5121, 5121, false, true,
	);
	assert !made.ok;
	if (!made.ok) { assert made.error == SkinInfluencesError.DuplicateJoint; }
}

test "accessor unorm8 and unorm16 recover exact sums without losing wide source joints" {
	for (const wide of [false, true]) {
		const maximum: int32 = wide ? 65535 : 255;
		const size: int32 = wide ? 8 : 4;
		for (const value of [0, 1, 2, 127, 128, 254, 255]) {
			let bytes: Vec<uint8> = [0, 1, 1, 1, 0, 0, 0, 0];
			for (const weight of [value, maximum - value, 0, 0]) {
				bytes.push((weight & 255) as uint8);
				if (wide) { bytes.push((weight >> 8) as uint8); }
			}
			let buffers: Vec<GltfAccessorBuffer> = [{
				bytes: move bytes, byteLength: 8 + size,
			}];
			const views: Vec<GltfAccessorView> = [
				{ buffer: 0, byteOffset: 0, byteLength: 8, byteStride: 8, target: 34962 },
				{ buffer: 0, byteOffset: 8, byteLength: size, byteStride: size, target: 34962 },
			];
			const joints = attribute(0, 5123, false);
			const weights = attribute(1, wide ? 5123 : 5121, true);
			const made = SkinInfluences.fromAccessor(joints, weights, buffers, views, 300);
			assert made.ok;
			if (!made.ok) { return; }
			assert made.value.joints[0] == 256 && made.value.joints[1] == 257;
			assert approx(made.value.weights[0], value as float32 / maximum as float32);
			buffers[0].bytes[8 + size - 1] = 1;
			const bad = SkinInfluences.fromAccessor(joints, weights, buffers, views, 300);
			assert !bad.ok;
			if (!bad.ok) { assert bad.error == SkinInfluencesError.WeightSum; }
		}
	}
}

test "sparse source joint ordinals remain canonical instead of physical buffer rows" {
	const bytes: Vec<uint8> = [
		1, 0, 0, 0, 1, 0, 0, 0,
		0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	];
	const buffers: Vec<GltfAccessorBuffer> = [{ bytes: bytes, byteLength: 40 }];
	const views: Vec<GltfAccessorView> = [
		{ buffer: 0, byteOffset: 0, byteLength: 1, byteStride: null, target: null },
		{ buffer: 0, byteOffset: 4, byteLength: 4, byteStride: null, target: null },
		{ buffer: 0, byteOffset: 8, byteLength: 32, byteStride: null, target: 34962 },
	];
	const joints: GltfAccessorSource = {
		...attribute(0, 5121, false), bufferView: null, byteOffset: null, count: 2,
		sparse: {
			count: 1, indicesView: 0, indicesByteOffset: 0, indicesComponentType: 5121,
			valuesView: 1, valuesByteOffset: 0,
		},
	};
	const weights: GltfAccessorSource = { ...attribute(2, 5126, false), count: 2 };
	const made = SkinInfluences.fromAccessor(joints, weights, buffers, views, 2);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.joints[0] == 0 && made.value.joints[4] == 1;
	assert made.value.weights[0] == 1.0 && made.value.weights[4] == 1.0;
}

test "zero, negative and nonfinite float weights fail, rather than making bind pose" {
	const joints: Vec<uint8> = [0, 0, 0, 0];
	assert !SkinInfluences.fromPacked(
		joints, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		1, 1, 5121, 5126, false, false,
	).ok;
	assert !SkinInfluences.fromPacked(
		joints, [0, 0, 128, 191, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0],
		1, 1, 5121, 5126, false, false,
	).ok;
	assert !SkinInfluences.fromPacked(
		joints, [0, 0, 128, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		1, 1, 5121, 5126, false, false,
	).ok;
}
