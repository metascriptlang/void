import { Mat4, identity, multiplyAffine } from "../math/math3d";

export const MAX_SKIN_PALETTE_JOINTS: int32 = 64;
export const SKIN_JOINT_FLOATS: int32 = 12;
export const SKIN_PALETTE_FLOATS: int32 = MAX_SKIN_PALETTE_JOINTS * SKIN_JOINT_FLOATS;
export const SKIN_PALETTE_BYTES: int32 = SKIN_PALETTE_FLOATS * 4;

export enum SkinPaletteError {
	Empty,
	PaletteTooLarge,
	JointOutOfRange,
	PoseLength,
	OutputLength,
	NotAffine,
	NonFinite,
}

export struct SkinPalette {
	joints: Vec<int32>;
}

export function create(
	this typeof SkinPalette,
	joints: Readonly<Span<int32>>,
): Result<SkinPalette, SkinPaletteError> {
	const count: int32 = joints.length as int32;
	if (count < 1) { return Result.err(SkinPaletteError.Empty); }
	if (count > MAX_SKIN_PALETTE_JOINTS) {
		return Result.err(SkinPaletteError.PaletteTooLarge);
	}
	let palette: SkinPalette = { joints: [] };
	for (const joint of joints) {
		if (joint < 0) { return Result.err(SkinPaletteError.JointOutOfRange); }
		palette.joints.push(joint);
	}
	return Result.ok(move palette);
}

function isFinite(this matrix: Mat4): boolean {
	return Number.isFinite(matrix.m11) && Number.isFinite(matrix.m12) &&
		Number.isFinite(matrix.m13) && Number.isFinite(matrix.m14) &&
		Number.isFinite(matrix.m21) && Number.isFinite(matrix.m22) &&
		Number.isFinite(matrix.m23) && Number.isFinite(matrix.m24) &&
		Number.isFinite(matrix.m31) && Number.isFinite(matrix.m32) &&
		Number.isFinite(matrix.m33) && Number.isFinite(matrix.m34) &&
		Number.isFinite(matrix.m41) && Number.isFinite(matrix.m42) &&
		Number.isFinite(matrix.m43) && Number.isFinite(matrix.m44);
}

function isAffine(this matrix: Mat4): boolean {
	return matrix.m14 == 0.0 && matrix.m24 == 0.0 &&
		matrix.m34 == 0.0 && matrix.m44 == 1.0;
}

function writeAffineColumns(this matrix: Mat4, output: Span<float32>): void {
	output[0] = matrix.m11; output[1] = matrix.m21;
	output[2] = matrix.m31; output[3] = matrix.m41;
	output[4] = matrix.m12; output[5] = matrix.m22;
	output[6] = matrix.m32; output[7] = matrix.m42;
	output[8] = matrix.m13; output[9] = matrix.m23;
	output[10] = matrix.m33; output[11] = matrix.m43;
}

export function writePalette(
	this palette: SkinPalette,
	jointWorlds: Readonly<Span<Mat4>>,
	inverseBindMatrices: Readonly<Span<Mat4>>,
	output: Span<float32>,
): Result<void, SkinPaletteError> {
	const count: int32 = palette.joints.length as int32;
	if (count < 1) { return Result.err(SkinPaletteError.Empty); }
	if (count > MAX_SKIN_PALETTE_JOINTS) {
		return Result.err(SkinPaletteError.PaletteTooLarge);
	}
	if (jointWorlds.length != inverseBindMatrices.length) {
		return Result.err(SkinPaletteError.PoseLength);
	}
	if (output.length != SKIN_PALETTE_FLOATS) {
		return Result.err(SkinPaletteError.OutputLength);
	}
	for (const joint of palette.joints) {
		if (joint < 0 || joint >= jointWorlds.length) {
			return Result.err(SkinPaletteError.JointOutOfRange);
		}
		if (!jointWorlds[joint].isFinite() || !inverseBindMatrices[joint].isFinite()) {
			return Result.err(SkinPaletteError.NonFinite);
		}
		if (!jointWorlds[joint].isAffine() || !inverseBindMatrices[joint].isAffine()) {
			return Result.err(SkinPaletteError.NotAffine);
		}
		const posed: Mat4 = inverseBindMatrices[joint].multiplyAffine(jointWorlds[joint]);
		if (!posed.isFinite()) { return Result.err(SkinPaletteError.NonFinite); }
	}
	for (let slot = 0; slot < MAX_SKIN_PALETTE_JOINTS; slot++) {
		let posed: Mat4 = identity();
		if (slot < count) {
			const joint: int32 = palette.joints[slot];
			posed = inverseBindMatrices[joint].multiplyAffine(jointWorlds[joint]);
		}
		const start: int32 = slot * SKIN_JOINT_FLOATS;
		posed.writeAffineColumns(output[start..start + SKIN_JOINT_FLOATS]);
	}
	return Result.ok(null);
}
