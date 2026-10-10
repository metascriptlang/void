import { approx } from "./helpers";
import { SkinInfluences, SkinInfluencesError, fromPacked } from "../void3d/skinInfluences";

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
