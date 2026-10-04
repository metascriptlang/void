// Void 2D colour effects — h2d.Drawable colorMatrix factories. A 4x4 RGBA transform
// packed column-major for GLSL `colorMatrix * rgba`; identity = no-op.

import { Mat4, identity } from "../math/math3d";

export const NO_COLOR_MATRIX: Mat4 = identity();

// Luminance grayscale (Rec.601). amount 0 = original .. 1 = fully gray.
export function colorMatrixGrayscale(amount: float32): Mat4 {
	const lr: float32 = 0.299;
	const lg: float32 = 0.587;
	const lb: float32 = 0.114;
	const k: float32 = amount;
	const ik: float32 = 1.0 - amount;
	return {
		m11: ik + k * lr, m12: k * lr,      m13: k * lr,      m14: 0.0,
		m21: k * lg,      m22: ik + k * lg, m23: k * lg,      m24: 0.0,
		m31: k * lb,      m32: k * lb,      m33: ik + k * lb, m34: 0.0,
		m41: 0.0,         m42: 0.0,         m43: 0.0,         m44: 1.0,
	};
}

// Silhouette tint (h2d glow / drop-shadow): drops rgb, keeps alpha × gain. Pair with
// colorAdd = the tint colour (a=0) so a blurred render-target becomes a solid-coloured
// halo shaped only by its alpha — the colour of the source is discarded.
export function colorMatrixAlphaOnly(gain: float32): Mat4 {
	return {
		m11: 0.0, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: 0.0, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: 0.0, m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: gain,
	};
}

export function writeColorMatrix(m: Mat4, out: Span<float32>, at: int32): void {
	out[at] = m.m11;
	out[at + 1] = m.m12;
	out[at + 2] = m.m13;
	out[at + 3] = m.m14;
	out[at + 4] = m.m21;
	out[at + 5] = m.m22;
	out[at + 6] = m.m23;
	out[at + 7] = m.m24;
	out[at + 8] = m.m31;
	out[at + 9] = m.m32;
	out[at + 10] = m.m33;
	out[at + 11] = m.m34;
	out[at + 12] = m.m41;
	out[at + 13] = m.m42;
	out[at + 14] = m.m43;
	out[at + 15] = m.m44;
}

export function readColorMatrix(from: Readonly<Span<float32>>, at: int32): Mat4 {
	return {
		m11: from[at], m12: from[at + 1], m13: from[at + 2], m14: from[at + 3],
		m21: from[at + 4], m22: from[at + 5], m23: from[at + 6], m24: from[at + 7],
		m31: from[at + 8], m32: from[at + 9], m33: from[at + 10], m34: from[at + 11],
		m41: from[at + 12], m42: from[at + 13], m43: from[at + 14], m44: from[at + 15],
	};
}
