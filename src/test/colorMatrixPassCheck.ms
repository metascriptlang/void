import { Mat4, Vec4, vec4, identity } from "../math/math3d";
import {
	ColorMatrixPass,
	ColorMatrixMask,
	ColorMatrixError,
	materialColorMatrixRaw,
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

test "colorMatrixPass A separates material RGB from full alpha and screen useAlpha" {
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const material = materialColorMatrixRaw(color, matrixA());
	assert material.ok;
	if (material.ok) { assert closeColor(material.value, vec4(0.3125, 0.6875, 0.8125, 0.65625)); }
	const pass: ColorMatrixPass = { matrix: matrixA(), useAlpha: true, secondMatrix: null };
	const full = pass.applyRaw(color);
	assert full.ok;
	if (full.ok) { assert closeColor(full.value, vec4(0.234375, 0.53125, 0.890625, 0.65625)); }
	const opaque: ColorMatrixPass = { ...pass, useAlpha: false };
	const forced = opaque.applyRaw(color);
	assert forced.ok;
	if (forced.ok) { assert closeColor(forced.value, vec4(0.3125, 0.6875, 0.8125, 1.125)); }
}

test "colorMatrixPass B retains negative alpha and HDR RGB without clamping" {
	const color: Vec4 = vec4(0.75, 0.125, 0.5, 0.25);
	const material = materialColorMatrixRaw(color, matrixB());
	assert material.ok;
	if (material.ok) { assert closeColor(material.value, vec4(0.40625, 0.0625, 1.5, -0.125)); }
	const pass: ColorMatrixPass = { matrix: matrixB(), useAlpha: true, secondMatrix: null };
	const full = pass.applyRaw(color);
	assert full.ok;
	if (full.ok) { assert closeColor(full.value, vec4(0.21875, 0.15625, 1.125, -0.125)); }
	const opaque: ColorMatrixPass = { ...pass, useAlpha: false };
	const forced = opaque.applyRaw(color);
	assert forced.ok;
	if (forced.ok) { assert closeColor(forced.value, vec4(0.40625, 0.0625, 1.5, 0.34375)); }
}

test "colorMatrixPass transpose and force-alpha controls differ in both fixtures" {
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

test "colorMatrixPass mask maps UV and mixes second matrix in reference direction" {
	const mask: ColorMatrixMask = weightedMask();
	const uv = mask.maskUv({ x: 0.25, y: 0.5 });
	assert uv.ok;
	if (uv.ok) { assert closeChannel(uv.value.x, 0.125) && closeChannel(uv.value.y, 0.75); }
	const pass: ColorMatrixPass = { matrix: matrixA(), useAlpha: true, secondMatrix: matrixB() };
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const sample: Vec4 = vec4(0.5, 0.25, 0.75, 0.5);
	const normal = pass.applyMaskedRaw(color, mask, sample);
	assert normal.ok;
	if (normal.ok) {
		assert closeColor(normal.value,
			vec4(0.1905364990234375, 0.5699310302734375, 0.8880462646484375, 0.6020965576171875));
	}
	const inverted: ColorMatrixMask = { ...mask, invert: true };
	const reverse = pass.applyMaskedRaw(color, inverted, sample);
	assert reverse.ok;
	if (reverse.ok) {
		assert closeColor(reverse.value,
			vec4(0.0125885009765625, 0.7269439697265625, 0.8775787353515625, 0.3822784423828125));
	}
}

test "colorMatrixPass second mask variant preserves alpha and absent-second original" {
	const mask: ColorMatrixMask = weightedMask();
	const color: Vec4 = vec4(0.75, 0.125, 0.5, 0.25);
	const sample: Vec4 = vec4(0.5, 0.25, 0.75, 0.5);
	const pass: ColorMatrixPass = { matrix: matrixB(), useAlpha: true, secondMatrix: matrixA() };
	const normal = pass.applyMaskedRaw(color, mask, sample);
	assert normal.ok;
	if (normal.ok) {
		assert closeColor(normal.value,
			vec4(0.3218994140625, 0.202667236328125, 0.996063232421875, -0.0037994384765625));
	}
	const original: ColorMatrixPass = { ...pass, useAlpha: false, secondMatrix: null };
	const fallback = original.applyMaskedRaw(color, mask, sample);
	assert fallback.ok;
	if (fallback.ok) {
		assert closeColor(fallback.value,
			vec4(0.462982177734375, 0.07281494140625, 1.3349609375, 0.328277587890625));
	}
}

test "colorMatrixPass defaults reuse saturation and preserve disabled material" {
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const identityPass = ColorMatrixPass.create();
	const screen = identityPass.applyRaw(color);
	assert screen.ok;
	if (screen.ok) { assert closeColor(screen.value, vec4(0.25, 0.5, 0.75, 1.0)); }
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

test "colorMatrixPass mask zero positive power and unclamped extrapolation" {
	const pass: ColorMatrixPass = { matrix: matrixA(), useAlpha: false, secondMatrix: null };
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const mask = ColorMatrixMask.create();
	const zero = pass.applyMaskedRaw(color, mask, vec4(0.0, 0.0, 0.0, 0.0));
	assert zero.ok;
	if (zero.ok) { assert closeColor(zero.value, vec4(0.3125, 0.6875, 0.8125, 1.125)); }
	const extrapolated = pass.applyMaskedRaw(color, mask, vec4(2.0, 0.0, 0.0, 0.0));
	assert extrapolated.ok;
	if (extrapolated.ok) {
		assert closeColor(extrapolated.value, vec4(0.1875, 0.3125, 0.6875, -0.375));
	}
}

test "colorMatrixPass refuses nonfinite inputs outputs UV and undefined power" {
	const huge: float32 = 3e38;
	const color: Vec4 = vec4(0.25, 0.5, 0.75, 0.375);
	const pass = ColorMatrixPass.create();
	const mask = ColorMatrixMask.create();
	const negative = pass.applyMaskedRaw(color, mask, vec4(-0.5, 0.0, 0.0, 0.0));
	assert !negative.ok;
	if (!negative.ok) { assert negative.error == ColorMatrixError.UndefinedMaskPower; }
	const zeroPower: ColorMatrixMask = { ...mask, power: 0.0 };
	assert !pass.applyMaskedRaw(color, zeroPower, vec4(0.0, 0.0, 0.0, 0.0)).ok;
	const inversePower: ColorMatrixMask = { ...mask, power: -1.0 };
	assert !pass.applyMaskedRaw(color, inversePower, vec4(0.0, 0.0, 0.0, 0.0)).ok;
	const overflow: Mat4 = { ...identity(), m11: huge };
	const refused = materialColorMatrixRaw(vec4(2.0, 0.0, 0.0, 1.0), overflow);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == ColorMatrixError.NonFinite; }
	const nan: float32 = Math.sqrt(-1.0) as float32;
	assert !materialColorMatrixRaw(color, { ...identity(), m14: nan }).ok;
	assert !pass.applyRaw(vec4(nan, 0.0, 0.0, 1.0)).ok;
	const badMask: ColorMatrixMask = { ...mask, matA: { x: huge, y: huge, z: 0.0 } };
	assert !badMask.maskUv({ x: 2.0, y: 2.0 }).ok;
	const badPower: ColorMatrixMask = { ...mask, power: nan };
	assert !pass.applyMaskedRaw(color, badPower, vec4(1.0, 0.0, 0.0, 0.0)).ok;
}
