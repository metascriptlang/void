import { Mat4, Vec3, Vec4, vec4, identity } from "../math/math3d";

export enum ColorMatrixError {
	NonFinite,
	UndefinedMaskPower,
}

export struct ColorMatrixUv {
	x: float32;
	y: float32;
}

export struct ColorMatrixMask {
	matA: Vec3;
	matB: Vec3;
	channel: Vec4;
	power: float32;
	invert: boolean;
}

export struct ColorMatrixPass {
	matrix: Mat4;
	useAlpha: boolean;
	secondMatrix: Mat4 | null;
}

// Heaps ColorMatrix raw RGBA is not Void's premultiplied target contract. Keep adaptation
// outside these reference evaluators until target alpha semantics are explicitly settled.
export function create(this typeof ColorMatrixPass): ColorMatrixPass {
	return { matrix: identity(), useAlpha: false, secondMatrix: null };
}

export function create(this typeof ColorMatrixMask): ColorMatrixMask {
	return {
		matA: { x: 1.0, y: 0.0, z: 0.0 },
		matB: { x: 0.0, y: 1.0, z: 0.0 },
		channel: vec4(1.0, 0.0, 0.0, 0.0),
		power: 1.0,
		invert: false,
	};
}

export function materialColorMatrixRaw(
	color: Vec4,
	matrix: Mat4,
	enabled: boolean = true,
): Result<Vec4, ColorMatrixError> {
	if (!finiteColor(color)) { return Result.err(ColorMatrixError.NonFinite); }
	if (!enabled) { return Result.ok(color); }
	if (!finiteMatrix(matrix)) { return Result.err(ColorMatrixError.NonFinite); }
	const rgb: Vec4 = vec4(color.x, color.y, color.z, 1.0) * matrix;
	const rgba: Vec4 = color * matrix;
	return checkedColor(vec4(rgb.x, rgb.y, rgb.z, rgba.w));
}

export function applyRaw(
	this pass: ColorMatrixPass,
	color: Vec4,
): Result<Vec4, ColorMatrixError> {
	return screenColorRaw(color, pass.matrix, pass.useAlpha);
}

export function maskUv(
	this mask: ColorMatrixMask,
	uv: ColorMatrixUv,
): Result<ColorMatrixUv, ColorMatrixError> {
	if (!Number.isFinite(uv.x) || !Number.isFinite(uv.y) ||
		!finiteVector(mask.matA) || !finiteVector(mask.matB)) {
		return Result.err(ColorMatrixError.NonFinite);
	}
	const mapped: ColorMatrixUv = {
		x: uv.x * mask.matA.x + uv.y * mask.matA.y + mask.matA.z,
		y: uv.x * mask.matB.x + uv.y * mask.matB.y + mask.matB.z,
	};
	if (!Number.isFinite(mapped.x) || !Number.isFinite(mapped.y)) {
		return Result.err(ColorMatrixError.NonFinite);
	}
	return Result.ok(mapped);
}

export function applyMaskedRaw(
	this pass: ColorMatrixPass,
	color: Vec4,
	mask: ColorMatrixMask,
	maskSample: Vec4,
): Result<Vec4, ColorMatrixError> {
	const first: Vec4 = try pass.applyRaw(color);
	if (!finiteColor(maskSample) || !finiteColor(mask.channel) ||
		!Number.isFinite(mask.power)) {
		return Result.err(ColorMatrixError.NonFinite);
	}
	const base: float32 = maskSample.x * mask.channel.x + maskSample.y * mask.channel.y +
		maskSample.z * mask.channel.z + maskSample.w * mask.channel.w;
	if (!Number.isFinite(base)) { return Result.err(ColorMatrixError.NonFinite); }
	if (base < 0.0 || (base == 0.0 && mask.power <= 0.0)) {
		return Result.err(ColorMatrixError.UndefinedMaskPower);
	}
	const weight: float32 = base == 0.0 ? 0.0 : Math.pow(base, mask.power) as float32;
	if (!Number.isFinite(weight)) { return Result.err(ColorMatrixError.NonFinite); }
	let second: Vec4 = color;
	const matrix2 = pass.secondMatrix;
	if (matrix2 !== null) { second = try screenColorRaw(color, matrix2, pass.useAlpha); }
	return mask.invert ? mixedRaw(second, first, weight) : mixedRaw(first, second, weight);
}

function screenColorRaw(
	color: Vec4,
	matrix: Mat4,
	useAlpha: boolean,
): Result<Vec4, ColorMatrixError> {
	if (!finiteColor(color) || !finiteMatrix(matrix)) {
		return Result.err(ColorMatrixError.NonFinite);
	}
	const input: Vec4 = useAlpha ? color : vec4(color.x, color.y, color.z, 1.0);
	return checkedColor(input * matrix);
}

function mixedRaw(a: Vec4, b: Vec4, weight: float32): Result<Vec4, ColorMatrixError> {
	const keep: float32 = 1.0 - weight;
	return checkedColor(vec4(
		a.x * keep + b.x * weight,
		a.y * keep + b.y * weight,
		a.z * keep + b.z * weight,
		a.w * keep + b.w * weight,
	));
}

function checkedColor(color: Vec4): Result<Vec4, ColorMatrixError> {
	if (!finiteColor(color)) { return Result.err(ColorMatrixError.NonFinite); }
	return Result.ok(color);
}

function finiteColor(color: Vec4): boolean {
	return Number.isFinite(color.x) && Number.isFinite(color.y) &&
		Number.isFinite(color.z) && Number.isFinite(color.w);
}

function finiteVector(value: Vec3): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function finiteMatrix(matrix: Mat4): boolean {
	return Number.isFinite(matrix.m11) && Number.isFinite(matrix.m12) &&
		Number.isFinite(matrix.m13) && Number.isFinite(matrix.m14) &&
		Number.isFinite(matrix.m21) && Number.isFinite(matrix.m22) &&
		Number.isFinite(matrix.m23) && Number.isFinite(matrix.m24) &&
		Number.isFinite(matrix.m31) && Number.isFinite(matrix.m32) &&
		Number.isFinite(matrix.m33) && Number.isFinite(matrix.m34) &&
		Number.isFinite(matrix.m41) && Number.isFinite(matrix.m42) &&
		Number.isFinite(matrix.m43) && Number.isFinite(matrix.m44);
}
