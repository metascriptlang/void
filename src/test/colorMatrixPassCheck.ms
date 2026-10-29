// post3d.ms colorMatrixFs on the CPU, through the block colorMatrixPass.ms writes, against
// values worked from h3d.pass.ColorMatrix and h3d.shader.ColorMatrix.

import { Wrap } from "../gpu/state";
import { Mat4, Vec4, vec4, identity } from "../math/math3d";
import { Mat4x4f, Texture2d, Vec4f, vec4f } from "../shader/std";
import { ColorMatrixParams, colorMatrixFs } from "../void3d/post3d";
import {
	COLOR_MATRIX,
	COLOR_MATRIX_FLAGS,
	COLOR_MATRIX_MASK_A,
	COLOR_MATRIX_MASK_B,
	COLOR_MATRIX_MASK_CHANNEL,
	COLOR_MATRIX_SECOND,
	COLOR_MATRIX_UNIFORM_LENGTH,
	ColorMatrixSettings,
	ColorMatrixMask,
	ColorMatrixError,
	materialColorMatrixRaw,
	writeColorMatrixBlock,
} from "../void3d/colorMatrixPass";

function closeChannel(a: float32, b: float32): boolean {
	return Number.isFinite(a) && Math.abs(a - b) < 0.000002;
}

function closeColor(a: Vec4, b: Vec4): boolean {
	return closeChannel(a.x, b.x) && closeChannel(a.y, b.y) &&
		closeChannel(a.z, b.z) && closeChannel(a.w, b.w);
}

function matrixA(): Mat4 {
	return {
		m11: 1.0, m12: 0.5, m13: -0.25, m14: 0.25,
		m21: -0.5, m22: 1.0, m23: 0.5, m24: -0.125,
		m31: 0.25, m32: -0.25, m33: 1.0, m34: 0.5,
		m41: 0.125, m42: 0.25, m43: -0.125, m44: 0.75,
	};
}

function matrixB(): Mat4 {
	return {
		m11: 0.5, m12: -0.25, m13: 0.75, m14: -0.5,
		m21: 0.25, m22: 1.0, m23: -0.5, m24: 0.25,
		m31: -0.5, m32: 0.5, m33: 1.0, m34: 0.125,
		m41: 0.25, m42: -0.125, m43: 0.5, m44: 0.625,
	};
}

function weightedMask(): ColorMatrixMask {
	return {
		matA: { x: 2.0, y: -1.0, z: 0.125 },
		matB: { x: -0.5, y: 0.25, z: 0.75 },
		channel: vec4(0.25, 0.5, 0.125, 0.125),
		power: 2.0,
		invert: false,
	};
}

function texture(width: int32, height: int32, texel: (x: int32) => Vec4): Texture2d {
	let texels: float32[] = [];
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const c: Vec4 = texel(x);
			texels.push(c.x);
			texels.push(c.y);
			texels.push(c.z);
			texels.push(c.w);
		}
	}
	return { width, height, texels };
}

function flat(color: Vec4): Texture2d {
	return texture(1, 1, (_x: int32): Vec4 => color);
}

function matrixAt(values: Vec<float32>, at: int32): Mat4x4f {
	return { columns: [
		vec4f(values[at], values[at + 1], values[at + 2], values[at + 3]),
		vec4f(values[at + 4], values[at + 5], values[at + 6], values[at + 7]),
		vec4f(values[at + 8], values[at + 9], values[at + 10], values[at + 11]),
		vec4f(values[at + 12], values[at + 13], values[at + 14], values[at + 15]),
	] };
}

function quadAt(values: Vec<float32>, at: int32): Vec4f {
	return vec4f(values[at], values[at + 1], values[at + 2], values[at + 3]);
}

function shaded(
	source: Texture2d,
	maskTexture: Texture2d,
	settings: ColorMatrixSettings,
	mask: ColorMatrixMask | null,
	x: float32,
	y: float32,
): Vec4 {
	let values: Vec<float32> = new Array(COLOR_MATRIX_UNIFORM_LENGTH);
	writeColorMatrixBlock(settings, mask, values);
	const params: ColorMatrixParams = {
		colorMatrix: matrixAt(values, COLOR_MATRIX),
		colorMatrixSecond: matrixAt(values, COLOR_MATRIX_SECOND),
		colorMaskA: quadAt(values, COLOR_MATRIX_MASK_A),
		colorMaskB: quadAt(values, COLOR_MATRIX_MASK_B),
		colorMaskChannel: quadAt(values, COLOR_MATRIX_MASK_CHANNEL),
		colorMatrixFlags: quadAt(values, COLOR_MATRIX_FLAGS),
	};
	const c: Vec4f = colorMatrixFs({ position: { x, y, z: 0.5, w: 1.0 } }, {
		colorSource: source,
		colorMask: maskTexture,
		colorSampler: { nearest: false, wrap: Wrap.Clamp },
		colorMaskSampler: { nearest: false, wrap: Wrap.Clamp },
		colorMatrixParams: params,
	});
	return vec4(c.x, c.y, c.z, c.w);
}

function screen(color: Vec4, settings: ColorMatrixSettings): Vec4 {
	return shaded(flat(color), flat(color), settings, null, 0.5, 0.5);
}

function masked(
	color: Vec4,
	settings: ColorMatrixSettings,
	mask: ColorMatrixMask,
	sample: Vec4,
): Vec4 {
	return shaded(flat(color), flat(sample), settings, mask, 0.5, 0.5);
}

test "the material matrix separates RGB from full alpha, and the pass's useAlpha picks either" {
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const material = materialColorMatrixRaw(color, matrixA());
	assert material.ok;
	if (material.ok) { assert closeColor(material.value, vec4(0.3125, 0.6875, 0.8125, 0.65625)); }
	const full: ColorMatrixSettings = { matrix: matrixA(), useAlpha: true, secondMatrix: null };
	assert closeColor(screen(color, full), vec4(0.234375, 0.53125, 0.890625, 0.65625));
	const opaque: ColorMatrixSettings = { ...full, useAlpha: false };
	assert closeColor(screen(color, opaque), vec4(0.3125, 0.6875, 0.8125, 1.125));
}

test "neither matrix clamps: negative alpha and RGB past 1 come through" {
	const color: Vec4 = vec4(0.75, 0.125, 0.5, 0.25);
	const material = materialColorMatrixRaw(color, matrixB());
	assert material.ok;
	if (material.ok) { assert closeColor(material.value, vec4(0.40625, 0.0625, 1.5, -0.125)); }
	const full: ColorMatrixSettings = { matrix: matrixB(), useAlpha: true, secondMatrix: null };
	assert closeColor(screen(color, full), vec4(0.21875, 0.15625, 1.125, -0.125));
	const opaque: ColorMatrixSettings = { ...full, useAlpha: false };
	assert closeColor(screen(color, opaque), vec4(0.40625, 0.0625, 1.5, 0.34375));
}

test "a transposed matrix or a forced alpha gives another material colour" {
	const colors: Vec<Vec4> = [vec4(0.25, 0.5, 0.75, 0.375), vec4(0.75, 0.125, 0.5, 0.25)];
	const matrices: Vec<Mat4> = [matrixA(), matrixB()];
	for (let i: int32 = 0; i < 2; i++) {
		const correct = materialColorMatrixRaw(colors[i], matrices[i]);
		const transpose = materialColorMatrixRaw(colors[i], matrices[i].transposed());
		const forceAlpha = materialColorMatrixRaw({ ...colors[i], w: 1.0 }, matrices[i]);
		assert correct.ok && transpose.ok && forceAlpha.ok;
		if (correct.ok && transpose.ok && forceAlpha.ok) {
			assert !closeColor(correct.value, transpose.value);
			assert !closeChannel(correct.value.w, forceAlpha.value.w);
		}
	}
}

test "a mask mixes toward the second matrix, and its invert mixes the other way" {
	const settings: ColorMatrixSettings =
		{ matrix: matrixA(), useAlpha: true, secondMatrix: matrixB() };
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const sample: Vec4 = vec4(0.5, 0.25, 0.75, 0.5);
	assert closeColor(masked(color, settings, weightedMask(), sample),
		vec4(0.1905364990234375, 0.5699310302734375, 0.8880462646484375, 0.6020965576171875));
	const inverted: ColorMatrixMask = { ...weightedMask(), invert: true };
	assert closeColor(masked(color, settings, inverted, sample),
		vec4(0.0125885009765625, 0.7269439697265625, 0.8775787353515625, 0.3822784423828125));
}

test "a mask with no second matrix mixes toward the source colour" {
	const color: Vec4 = vec4(0.75, 0.125, 0.5, 0.25);
	const sample: Vec4 = vec4(0.5, 0.25, 0.75, 0.5);
	const second: ColorMatrixSettings =
		{ matrix: matrixB(), useAlpha: true, secondMatrix: matrixA() };
	assert closeColor(masked(color, second, weightedMask(), sample),
		vec4(0.3218994140625, 0.202667236328125, 0.996063232421875, -0.0037994384765625));
	const original: ColorMatrixSettings = { ...second, useAlpha: false, secondMatrix: null };
	assert closeColor(masked(color, original, weightedMask(), sample),
		vec4(0.462982177734375, 0.07281494140625, 1.3349609375, 0.328277587890625));
}

test "the mask is read where its UV rows map the target's UV" {
	const settings: ColorMatrixSettings = { matrix: matrixA(), useAlpha: false, secondMatrix: null };
	const source: Texture2d = texture(4, 4, (_x: int32): Vec4 => vec4(0.25, 0.5, 0.75, 0.375));
	const ramp: Texture2d = texture(8, 8, (x: int32): Vec4 => vec4((x as float32) / 8.0, 0.0, 0.0, 0.0));
	const mask: ColorMatrixMask = { ...ColorMatrixMask.create(), matA: { x: 2.0, y: -1.0, z: 0.125 } };
	const first: Vec4 = screen(vec4(0.25, 0.5, 0.75, 0.375), settings);
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const weight: float32 = 0.0625;
	const expected: Vec4 = vec4(
		first.x + (color.x - first.x) * weight, first.y + (color.y - first.y) * weight,
		first.z + (color.z - first.z) * weight, first.w + (color.w - first.w) * weight);
	assert closeColor(shaded(source, ramp, settings, mask, 1.0, 2.0), expected);
}

test "the identity pass makes the colour opaque and leaves the rest, and saturation reuses it" {
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const identityPass = ColorMatrixSettings.create();
	assert closeColor(screen(color, identityPass), vec4(0.25, 0.5, 0.75, 1.0));
	const disabled = materialColorMatrixRaw(color, matrixA(), false);
	assert disabled.ok;
	if (disabled.ok) { assert closeColor(disabled.value, color); }
	const saturated = materialColorMatrixRaw(color, identity().colorSaturated(-1.0));
	assert saturated.ok;
	if (saturated.ok) {
		assert closeColor(saturated.value, vec4(0.4648745, 0.4648745, 0.4648745, 0.375));
	}
	let copy = identityPass;
	copy.matrix.m41 = 0.5;
	assert identityPass.matrix.m41 == 0.0;
}

test "a mask texel of 0 under a positive power keeps the first matrix; past 1 it extrapolates" {
	const settings: ColorMatrixSettings = { matrix: matrixA(), useAlpha: false, secondMatrix: null };
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const mask = ColorMatrixMask.create();
	assert closeColor(masked(color, settings, mask, vec4(0.0, 0.0, 0.0, 0.0)),
		vec4(0.3125, 0.6875, 0.8125, 1.125));
	assert closeColor(masked(color, settings, mask, vec4(2.0, 0.0, 0.0, 0.0)),
		vec4(0.1875, 0.3125, 0.6875, -0.375));
}

test "the pass refuses a non-finite matrix or mask and a mask power of 0 or below" {
	const huge: float32 = 3e38;
	const nan: float32 = Math.sqrt(-1.0) as float32;
	const settings = ColorMatrixSettings.create();
	const mask = ColorMatrixMask.create();
	assert settings.validate(mask).ok;
	const zeroPower = settings.validate({ ...mask, power: 0.0 });
	assert !zeroPower.ok;
	if (!zeroPower.ok) { assert zeroPower.error == ColorMatrixError.UndefinedMaskPower; }
	assert !settings.validate({ ...mask, power: -1.0 }).ok;
	assert !settings.validate({ ...mask, power: nan }).ok;
	assert !settings.validate({ ...mask, matA: { x: nan, y: 0.0, z: 0.0 } }).ok;
	const badMatrix: ColorMatrixSettings = { ...settings, matrix: { ...identity(), m14: nan } };
	const refused = badMatrix.validate(null);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == ColorMatrixError.NonFinite; }
	const badSecond: ColorMatrixSettings =
		{ ...settings, secondMatrix: { ...identity(), m11: nan } };
	assert !badSecond.validate(null).ok;
	const overflow: Mat4 = { ...identity(), m11: huge };
	const material = materialColorMatrixRaw(vec4(2.0, 0.0, 0.0, 1.0), overflow);
	assert !material.ok;
	if (!material.ok) { assert material.error == ColorMatrixError.NonFinite; }
}
