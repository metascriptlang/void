import { approx } from "./helpers";
import {
	Mat4,
	vec3,
	project,
	identity,
	translation,
	rotationZ,
	scaling,
	multiplyAffine,
} from "../math/math3d";
import {
	SkinPalette,
	SkinPaletteError,
	SKIN_PALETTE_FLOATS,
	SKIN_PALETTE_BYTES,
	create,
	writePalette,
} from "../void3d/skinPalette";

function paletteScratch(length: int32 = SKIN_PALETTE_FLOATS): Vec<float32> {
	let result: Vec<float32> = [];
	for (let i = 0; i < length; i++) { result.push(99.0); }
	return result;
}

test "a skin palette has 64 affine joints, 768 floats and 3072 bytes, not a rig limit" {
	assert SKIN_PALETTE_FLOATS == 768;
	assert SKIN_PALETTE_BYTES == 3072;
	let slots: Vec<int32> = [];
	for (let i = 0; i < 64; i++) { slots.push(i); }
	const full = SkinPalette.create(slots);
	assert full.ok;
	slots.push(64);
	const tooLarge = SkinPalette.create(slots);
	assert !tooLarge.ok;
	if (!tooLarge.ok) { assert tooLarge.error == SkinPaletteError.PaletteTooLarge; }
	const empty = SkinPalette.create([]);
	assert !empty.ok;
}

test "palette owns its joint map rather than aliasing the constructor input" {
	let slots: Vec<int32> = [1, 0];
	const made = SkinPalette.create(slots);
	assert made.ok;
	if (!made.ok) { return; }
	slots[0] = 0;
	assert made.value.joints[0] == 1;
}

test "palette packs IBM before joint world in the joint-map order" {
	const made = SkinPalette.create([1, 0]);
	assert made.ok;
	if (!made.ok) { return; }
	const worlds: Vec<Mat4> = [
		translation(0.0, 0.0, 7.0),
		rotationZ(1.57079632679).multiplyAffine(translation(5.0, 0.0, 0.0)),
	];
	const inverses: Vec<Mat4> = [identity(), translation(-2.0, 0.0, 0.0)];
	let packed = paletteScratch();
	const written = made.value.writePalette(worlds, inverses, packed);
	assert written.ok;
	const point = vec3(2.0, 0.0, 0.0).project(inverses[1].multiplyAffine(worlds[1]));
	assert approx(packed[0] * 2.0 + packed[3], point.x);
	assert approx(packed[4] * 2.0 + packed[7], point.y);
	assert approx(packed[8] * 2.0 + packed[11], point.z);
	assert approx(point.x, 5.0) && approx(point.y, 0.0);
	assert approx(packed[12 + 11], 7.0);
}

test "palette padding removes the former actor's matrices from a reused range" {
	const made = SkinPalette.create([0]);
	assert made.ok;
	if (!made.ok) { return; }
	let packed = paletteScratch();
	assert made.value.writePalette([translation(1.0, 2.0, 3.0)], [identity()], packed).ok;
	for (let joint = 1; joint < 64; joint++) {
		for (let field = 0; field < 12; field++) {
			const expected: float32 = field == 0 || field == 5 || field == 10 ? 1.0 : 0.0;
			assert approx(packed[joint * 12 + field], expected);
		}
	}
}

test "a global joint index outside the pose refuses without a partial palette write" {
	const made = SkinPalette.create([0, 2]);
	assert made.ok;
	if (!made.ok) { return; }
	let packed = paletteScratch();
	const written = made.value.writePalette([identity()], [identity()], packed);
	assert !written.ok;
	if (!written.ok) { assert written.error == SkinPaletteError.JointOutOfRange; }
	for (const field of packed) { assert field == 99.0; }
}

test "affine pose validation and declared output length happen before mutation" {
	const made = SkinPalette.create([0]);
	assert made.ok;
	if (!made.ok) { return; }
	let packed = paletteScratch();
	const projective: Mat4 = { ...identity(), m14: 1.0 };
	const badMatrix = made.value.writePalette([projective], [identity()], packed);
	assert !badMatrix.ok;
	if (!badMatrix.ok) { assert badMatrix.error == SkinPaletteError.NotAffine; }
	for (const field of packed) { assert field == 99.0; }
	const short = made.value.writePalette([identity()], [identity()], packed[0..12]);
	assert !short.ok;
	if (!short.ok) { assert short.error == SkinPaletteError.OutputLength; }
}

test "palette validation rejects a mismatched pose and overflow before writing" {
	const made = SkinPalette.create([0]);
	assert made.ok;
	if (!made.ok) { return; }
	let packed = paletteScratch();
	const mismatch = made.value.writePalette([identity()], [], packed);
	assert !mismatch.ok;
	if (!mismatch.ok) { assert mismatch.error == SkinPaletteError.PoseLength; }
	const large: float32 = 1e20;
	const overflow = made.value.writePalette(
		[scaling(large, large, large)], [scaling(large, large, large)], packed,
	);
	assert !overflow.ok;
	if (!overflow.ok) { assert overflow.error == SkinPaletteError.NonFinite; }
	for (const field of packed) { assert field == 99.0; }
	const negative = SkinPalette.create([-1]);
	assert !negative.ok;
	if (!negative.ok) { assert negative.error == SkinPaletteError.JointOutOfRange; }
}

test "palette map may repeat a joint to fill the reference splitter's index holes" {
	const made = SkinPalette.create([0, 1, 0]);
	assert made.ok;
	if (!made.ok) { return; }
	let packed = paletteScratch();
	assert made.value.writePalette(
		[translation(2.0, 0.0, 0.0), translation(3.0, 0.0, 0.0)],
		[identity(), identity()], packed,
	).ok;
	assert approx(packed[3], 2.0) && approx(packed[15], 3.0) && approx(packed[27], 2.0);
}
