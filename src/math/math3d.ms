// Void 3D math — port of h3d.Vector / h3d.Matrix / h3d.Quat, the subset void3d uses.
//
// Heaps conventions are kept as-is:
// - row vectors: a point transforms as `p * m`, and `a * b` applies `a` first, then `b`,
//   so a world matrix is `local * parent` (h3d.scene.Object.calcAbsPos);
// - translation lives in m41/m42/m43;
// - the 16 fields in declaration order are the upload order: GLSL reads them column-major,
//   which is the transpose, so `uniformMatrix * vec4(p, 1.0)` equals `p * m` here.

const EPSILON: float32 = 1e-10;

export struct Vec3 {
	x: float32;
	y: float32;
	z: float32;
}

export struct Vec4 {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
}

export struct Mat4 {
	m11: float32; m12: float32; m13: float32; m14: float32;
	m21: float32; m22: float32; m23: float32; m24: float32;
	m31: float32; m32: float32; m33: float32; m34: float32;
	m41: float32; m42: float32; m43: float32; m44: float32;
}

export struct Quat {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
}

function sine(a: float32): float32 { return Math.sin(a) as float32; }
function cosine(a: float32): float32 { return Math.cos(a) as float32; }
function squareRoot(a: float32): float32 { return Math.sqrt(a) as float32; }
function absolute(a: float32): float32 { return a < 0.0 ? -a : a; }

// ---- Vec3 (h3d.Vector) ----

export function vec3(x: float32, y: float32, z: float32): Vec3 {
	return { x: x, y: y, z: z };
}

export function `+`(this a: Vec3, b: Vec3): Vec3 {
	return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
}

export function `-`(this a: Vec3, b: Vec3): Vec3 {
	return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };
}

// Not an `*` overload: a second `*` on the same receiver is invisible to importing modules
// on msc 0.2.53, and `p * m` is the one that matters.
export function scaled(this a: Vec3, s: float32): Vec3 {
	return { x: a.x * s, y: a.y * s, z: a.z * s };
}

export function dot(this a: Vec3, b: Vec3): float32 {
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

export function cross(this a: Vec3, b: Vec3): Vec3 {
	return { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x };
}

export function lengthSquared(this a: Vec3): float32 {
	return a.x * a.x + a.y * a.y + a.z * a.z;
}

export function length(this a: Vec3): float32 {
	return squareRoot(a.lengthSquared());
}

// h3d.Vector.normalized: a zero vector stays zero.
export function normalized(this a: Vec3): Vec3 {
	const lengthSquared: float32 = a.lengthSquared();
	if (lengthSquared < EPSILON) {
		return { x: 0.0, y: 0.0, z: 0.0 };
	}
	return a.scaled(1.0 / squareRoot(lengthSquared));
}

export function lerp(this a: Vec3, b: Vec3, k: float32): Vec3 {
	return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, z: a.z + (b.z - a.z) * k };
}

// h3d.Vector.transform: a point, w = 1, the 4th column ignored (affine matrices).
export function `*`(this p: Vec3, m: Mat4): Vec3 {
	return {
		x: p.x * m.m11 + p.y * m.m21 + p.z * m.m31 + m.m41,
		y: p.x * m.m12 + p.y * m.m22 + p.z * m.m32 + m.m42,
		z: p.x * m.m13 + p.y * m.m23 + p.z * m.m33 + m.m43,
	};
}

// h3d.Vector.transform3x3: a direction, translation ignored.
export function transformDirection(this d: Vec3, m: Mat4): Vec3 {
	return {
		x: d.x * m.m11 + d.y * m.m21 + d.z * m.m31,
		y: d.x * m.m12 + d.y * m.m22 + d.z * m.m32,
		z: d.x * m.m13 + d.y * m.m23 + d.z * m.m33,
	};
}

// ---- Vec4 (h3d.Vector4) ----

export function vec4(x: float32, y: float32, z: float32, w: float32): Vec4 {
	return { x: x, y: y, z: z, w: w };
}

// Full 4x4 transform of (x, y, z, w).
export function `*`(this p: Vec4, m: Mat4): Vec4 {
	return {
		x: p.x * m.m11 + p.y * m.m21 + p.z * m.m31 + p.w * m.m41,
		y: p.x * m.m12 + p.y * m.m22 + p.z * m.m32 + p.w * m.m42,
		z: p.x * m.m13 + p.y * m.m23 + p.z * m.m33 + p.w * m.m43,
		w: p.x * m.m14 + p.y * m.m24 + p.z * m.m34 + p.w * m.m44,
	};
}

// h3d.Vector.project: transform the point through a projection and divide by w.
export function project(this p: Vec3, m: Mat4): Vec3 {
	const clip: Vec4 = vec4(p.x, p.y, p.z, 1.0) * m;
	const inverseW: float32 = 1.0 / clip.w;
	return { x: clip.x * inverseW, y: clip.y * inverseW, z: clip.z * inverseW };
}

// ---- Mat4 (h3d.Matrix) ----

export function zeroMatrix(): Mat4 {
	return {
		m11: 0.0, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: 0.0, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: 0.0, m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 0.0,
	};
}

export function identity(): Mat4 {
	return {
		m11: 1.0, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: 1.0, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: 1.0, m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 1.0,
	};
}

export function translation(x: float32, y: float32, z: float32): Mat4 {
	return { ...identity(), m41: x, m42: y, m43: z };
}

export function scaling(x: float32, y: float32, z: float32): Mat4 {
	return { ...identity(), m11: x, m22: y, m33: z };
}

export function rotationX(angle: float32): Mat4 {
	const c: float32 = cosine(angle);
	const s: float32 = sine(angle);
	return { ...identity(), m22: c, m23: s, m32: -s, m33: c };
}

export function rotationY(angle: float32): Mat4 {
	const c: float32 = cosine(angle);
	const s: float32 = sine(angle);
	return { ...identity(), m11: c, m13: -s, m31: s, m33: c };
}

export function rotationZ(angle: float32): Mat4 {
	const c: float32 = cosine(angle);
	const s: float32 = sine(angle);
	return { ...identity(), m11: c, m12: s, m21: -s, m22: c };
}

// h3d.Matrix.initRotation: Euler angles, X then Y then Z.
export function rotationEuler(x: float32, y: float32, z: float32): Mat4 {
	const cx: float32 = cosine(x);
	const sx: float32 = sine(x);
	const cy: float32 = cosine(y);
	const sy: float32 = sine(y);
	const cz: float32 = cosine(z);
	const sz: float32 = sine(z);
	const cxsy: float32 = cx * sy;
	const sxsy: float32 = sx * sy;
	return {
		m11: cy * cz, m12: cy * sz, m13: -sy, m14: 0.0,
		m21: sxsy * cz - cx * sz, m22: sxsy * sz + cx * cz, m23: sx * cy, m24: 0.0,
		m31: cxsy * cz + sx * sz, m32: cxsy * sz - sx * cz, m33: cx * cy, m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 1.0,
	};
}

// Full 4x4 product, `a` applied first (h3d.Matrix.multiply(a, b)).
export function `*`(this a: Mat4, b: Mat4): Mat4 {
	return {
		m11: a.m11 * b.m11 + a.m12 * b.m21 + a.m13 * b.m31 + a.m14 * b.m41,
		m12: a.m11 * b.m12 + a.m12 * b.m22 + a.m13 * b.m32 + a.m14 * b.m42,
		m13: a.m11 * b.m13 + a.m12 * b.m23 + a.m13 * b.m33 + a.m14 * b.m43,
		m14: a.m11 * b.m14 + a.m12 * b.m24 + a.m13 * b.m34 + a.m14 * b.m44,

		m21: a.m21 * b.m11 + a.m22 * b.m21 + a.m23 * b.m31 + a.m24 * b.m41,
		m22: a.m21 * b.m12 + a.m22 * b.m22 + a.m23 * b.m32 + a.m24 * b.m42,
		m23: a.m21 * b.m13 + a.m22 * b.m23 + a.m23 * b.m33 + a.m24 * b.m43,
		m24: a.m21 * b.m14 + a.m22 * b.m24 + a.m23 * b.m34 + a.m24 * b.m44,

		m31: a.m31 * b.m11 + a.m32 * b.m21 + a.m33 * b.m31 + a.m34 * b.m41,
		m32: a.m31 * b.m12 + a.m32 * b.m22 + a.m33 * b.m32 + a.m34 * b.m42,
		m33: a.m31 * b.m13 + a.m32 * b.m23 + a.m33 * b.m33 + a.m34 * b.m43,
		m34: a.m31 * b.m14 + a.m32 * b.m24 + a.m33 * b.m34 + a.m34 * b.m44,

		m41: a.m41 * b.m11 + a.m42 * b.m21 + a.m43 * b.m31 + a.m44 * b.m41,
		m42: a.m41 * b.m12 + a.m42 * b.m22 + a.m43 * b.m32 + a.m44 * b.m42,
		m43: a.m41 * b.m13 + a.m42 * b.m23 + a.m43 * b.m33 + a.m44 * b.m43,
		m44: a.m41 * b.m14 + a.m42 * b.m24 + a.m43 * b.m34 + a.m44 * b.m44,
	};
}

// h3d.Matrix.multiply3x4: both operands affine, the 4th column is forced to (0, 0, 0, 1).
export function multiplyAffine(this a: Mat4, b: Mat4): Mat4 {
	return {
		m11: a.m11 * b.m11 + a.m12 * b.m21 + a.m13 * b.m31,
		m12: a.m11 * b.m12 + a.m12 * b.m22 + a.m13 * b.m32,
		m13: a.m11 * b.m13 + a.m12 * b.m23 + a.m13 * b.m33,
		m14: 0.0,
		m21: a.m21 * b.m11 + a.m22 * b.m21 + a.m23 * b.m31,
		m22: a.m21 * b.m12 + a.m22 * b.m22 + a.m23 * b.m32,
		m23: a.m21 * b.m13 + a.m22 * b.m23 + a.m23 * b.m33,
		m24: 0.0,
		m31: a.m31 * b.m11 + a.m32 * b.m21 + a.m33 * b.m31,
		m32: a.m31 * b.m12 + a.m32 * b.m22 + a.m33 * b.m32,
		m33: a.m31 * b.m13 + a.m32 * b.m23 + a.m33 * b.m33,
		m34: 0.0,
		m41: a.m41 * b.m11 + a.m42 * b.m21 + a.m43 * b.m31 + b.m41,
		m42: a.m41 * b.m12 + a.m42 * b.m22 + a.m43 * b.m32 + b.m42,
		m43: a.m41 * b.m13 + a.m42 * b.m23 + a.m43 * b.m33 + b.m43,
		m44: 1.0,
	};
}

export function transposed(this m: Mat4): Mat4 {
	return {
		m11: m.m11, m12: m.m21, m13: m.m31, m14: m.m41,
		m21: m.m12, m22: m.m22, m23: m.m32, m24: m.m42,
		m31: m.m13, m32: m.m23, m33: m.m33, m34: m.m43,
		m41: m.m14, m42: m.m24, m43: m.m34, m44: m.m44,
	};
}

export function position(this m: Mat4): Vec3 {
	return { x: m.m41, y: m.m42, z: m.m43 };
}

export function determinant3x3(this m: Mat4): float32 {
	return m.m11 * (m.m22 * m.m33 - m.m23 * m.m32) + m.m12 * (m.m23 * m.m31 - m.m21 * m.m33) + m.m13 * (m.m21 * m.m32 - m.m22 * m.m31);
}

// h3d.Matrix.initInverse: a singular matrix inverts to zero, as in Heaps.
export function inverse(this m: Mat4): Mat4 {
	const r: Mat4 = {
		m11: m.m22 * m.m33 * m.m44 - m.m22 * m.m34 * m.m43 - m.m32 * m.m23 * m.m44 + m.m32 * m.m24 * m.m43 + m.m42 * m.m23 * m.m34 - m.m42 * m.m24 * m.m33,
		m12: -m.m12 * m.m33 * m.m44 + m.m12 * m.m34 * m.m43 + m.m32 * m.m13 * m.m44 - m.m32 * m.m14 * m.m43 - m.m42 * m.m13 * m.m34 + m.m42 * m.m14 * m.m33,
		m13: m.m12 * m.m23 * m.m44 - m.m12 * m.m24 * m.m43 - m.m22 * m.m13 * m.m44 + m.m22 * m.m14 * m.m43 + m.m42 * m.m13 * m.m24 - m.m42 * m.m14 * m.m23,
		m14: -m.m12 * m.m23 * m.m34 + m.m12 * m.m24 * m.m33 + m.m22 * m.m13 * m.m34 - m.m22 * m.m14 * m.m33 - m.m32 * m.m13 * m.m24 + m.m32 * m.m14 * m.m23,
		m21: -m.m21 * m.m33 * m.m44 + m.m21 * m.m34 * m.m43 + m.m31 * m.m23 * m.m44 - m.m31 * m.m24 * m.m43 - m.m41 * m.m23 * m.m34 + m.m41 * m.m24 * m.m33,
		m22: m.m11 * m.m33 * m.m44 - m.m11 * m.m34 * m.m43 - m.m31 * m.m13 * m.m44 + m.m31 * m.m14 * m.m43 + m.m41 * m.m13 * m.m34 - m.m41 * m.m14 * m.m33,
		m23: -m.m11 * m.m23 * m.m44 + m.m11 * m.m24 * m.m43 + m.m21 * m.m13 * m.m44 - m.m21 * m.m14 * m.m43 - m.m41 * m.m13 * m.m24 + m.m41 * m.m14 * m.m23,
		m24: m.m11 * m.m23 * m.m34 - m.m11 * m.m24 * m.m33 - m.m21 * m.m13 * m.m34 + m.m21 * m.m14 * m.m33 + m.m31 * m.m13 * m.m24 - m.m31 * m.m14 * m.m23,
		m31: m.m21 * m.m32 * m.m44 - m.m21 * m.m34 * m.m42 - m.m31 * m.m22 * m.m44 + m.m31 * m.m24 * m.m42 + m.m41 * m.m22 * m.m34 - m.m41 * m.m24 * m.m32,
		m32: -m.m11 * m.m32 * m.m44 + m.m11 * m.m34 * m.m42 + m.m31 * m.m12 * m.m44 - m.m31 * m.m14 * m.m42 - m.m41 * m.m12 * m.m34 + m.m41 * m.m14 * m.m32,
		m33: m.m11 * m.m22 * m.m44 - m.m11 * m.m24 * m.m42 - m.m21 * m.m12 * m.m44 + m.m21 * m.m14 * m.m42 + m.m41 * m.m12 * m.m24 - m.m41 * m.m14 * m.m22,
		m34: -m.m11 * m.m22 * m.m34 + m.m11 * m.m24 * m.m32 + m.m21 * m.m12 * m.m34 - m.m21 * m.m14 * m.m32 - m.m31 * m.m12 * m.m24 + m.m31 * m.m14 * m.m22,
		m41: -m.m21 * m.m32 * m.m43 + m.m21 * m.m33 * m.m42 + m.m31 * m.m22 * m.m43 - m.m31 * m.m23 * m.m42 - m.m41 * m.m22 * m.m33 + m.m41 * m.m23 * m.m32,
		m42: m.m11 * m.m32 * m.m43 - m.m11 * m.m33 * m.m42 - m.m31 * m.m12 * m.m43 + m.m31 * m.m13 * m.m42 + m.m41 * m.m12 * m.m33 - m.m41 * m.m13 * m.m32,
		m43: -m.m11 * m.m22 * m.m43 + m.m11 * m.m23 * m.m42 + m.m21 * m.m12 * m.m43 - m.m21 * m.m13 * m.m42 - m.m41 * m.m12 * m.m23 + m.m41 * m.m13 * m.m22,
		m44: m.m11 * m.m22 * m.m33 - m.m11 * m.m23 * m.m32 - m.m21 * m.m12 * m.m33 + m.m21 * m.m13 * m.m32 + m.m31 * m.m12 * m.m23 - m.m31 * m.m13 * m.m22,
	};
	const det: float32 = m.m11 * r.m11 + m.m12 * r.m21 + m.m13 * r.m31 + m.m14 * r.m41;
	if (absolute(det) < EPSILON) {
		return zeroMatrix();
	}
	return r.scaledBy(1.0 / det);
}

function scaledBy(this m: Mat4, k: float32): Mat4 {
	return {
		m11: m.m11 * k, m12: m.m12 * k, m13: m.m13 * k, m14: m.m14 * k,
		m21: m.m21 * k, m22: m.m22 * k, m23: m.m23 * k, m24: m.m24 * k,
		m31: m.m31 * k, m32: m.m32 * k, m33: m.m33 * k, m34: m.m34 * k,
		m41: m.m41 * k, m42: m.m42 * k, m43: m.m43 * k, m44: m.m44 * k,
	};
}

// h3d.Matrix.inverse3x4: inverse of an affine matrix.
export function inverseAffine(this m: Mat4): Mat4 {
	const r: Mat4 = {
		m11: m.m22 * m.m33 - m.m23 * m.m32,
		m12: m.m13 * m.m32 - m.m12 * m.m33,
		m13: m.m12 * m.m23 - m.m13 * m.m22,
		m14: 0.0,
		m21: m.m23 * m.m31 - m.m21 * m.m33,
		m22: m.m11 * m.m33 - m.m13 * m.m31,
		m23: m.m13 * m.m21 - m.m11 * m.m23,
		m24: 0.0,
		m31: m.m21 * m.m32 - m.m22 * m.m31,
		m32: m.m12 * m.m31 - m.m11 * m.m32,
		m33: m.m11 * m.m22 - m.m12 * m.m21,
		m34: 0.0,
		m41: -m.m21 * m.m32 * m.m43 + m.m21 * m.m33 * m.m42 + m.m31 * m.m22 * m.m43 - m.m31 * m.m23 * m.m42 - m.m41 * m.m22 * m.m33 + m.m41 * m.m23 * m.m32,
		m42: m.m11 * m.m32 * m.m43 - m.m11 * m.m33 * m.m42 - m.m31 * m.m12 * m.m43 + m.m31 * m.m13 * m.m42 + m.m41 * m.m12 * m.m33 - m.m41 * m.m13 * m.m32,
		m43: -m.m11 * m.m22 * m.m43 + m.m11 * m.m23 * m.m42 + m.m21 * m.m12 * m.m43 - m.m21 * m.m13 * m.m42 - m.m41 * m.m12 * m.m23 + m.m41 * m.m13 * m.m22,
		m44: 1.0,
	};
	const det: float32 = m.m11 * r.m11 + m.m12 * r.m21 + m.m13 * r.m31;
	if (absolute(det) < EPSILON) {
		return zeroMatrix();
	}
	const k: float32 = 1.0 / det;
	return { ...r.scaledBy(k), m14: 0.0, m24: 0.0, m34: 0.0, m44: 1.0 };
}

// Signed cofactor transform for affine normals. The shader normalizes the result, so dividing by
// the determinant adds only overflow risk; its sign is enough to preserve reflected orientation.
// A rank-two transform still has a useful cofactor normal instead of collapsing every normal to 0.
export function normalMatrix(this m: Mat4): Mat4 {
	const r: Mat4 = {
		m11: m.m22 * m.m33 - m.m32 * m.m23,
		m12: -m.m12 * m.m33 + m.m32 * m.m13,
		m13: m.m12 * m.m23 - m.m22 * m.m13,
		m14: 0.0,
		m21: -m.m21 * m.m33 + m.m31 * m.m23,
		m22: m.m11 * m.m33 - m.m31 * m.m13,
		m23: -m.m11 * m.m23 + m.m21 * m.m13,
		m24: 0.0,
		m31: m.m21 * m.m32 - m.m31 * m.m22,
		m32: -m.m11 * m.m32 + m.m31 * m.m12,
		m33: m.m11 * m.m22 - m.m21 * m.m12,
		m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 0.0,
	};
	const det: float32 = m.m11 * r.m11 + m.m12 * r.m21 + m.m13 * r.m31;
	const signed: Mat4 = det < 0.0 ? r.scaledBy(-1.0) : r;
	return { ...signed.transposed(), m44: 1.0 };
}

// Local transform of h3d.scene.Object: scale, then rotate, then translate.
export function composeTransform(position: Vec3, rotation: Quat, scale: Vec3): Mat4 {
	const r: Mat4 = rotation.toMatrix();
	return {
		m11: r.m11 * scale.x, m12: r.m12 * scale.x, m13: r.m13 * scale.x, m14: 0.0,
		m21: r.m21 * scale.y, m22: r.m22 * scale.y, m23: r.m23 * scale.y, m24: 0.0,
		m31: r.m31 * scale.z, m32: r.m32 * scale.z, m33: r.m33 * scale.z, m34: 0.0,
		m41: position.x, m42: position.y, m43: position.z, m44: 1.0,
	};
}

// Upload order: writes the 16 fields at `offset`, for a uniform block (see header).
export function writeTo(this m: Mat4, out: Span<float32>, offset: int32): void {
	out[offset] = m.m11; out[offset + 1] = m.m12; out[offset + 2] = m.m13; out[offset + 3] = m.m14;
	out[offset + 4] = m.m21; out[offset + 5] = m.m22; out[offset + 6] = m.m23; out[offset + 7] = m.m24;
	out[offset + 8] = m.m31; out[offset + 9] = m.m32; out[offset + 10] = m.m33; out[offset + 11] = m.m34;
	out[offset + 12] = m.m41; out[offset + 13] = m.m42; out[offset + 14] = m.m43; out[offset + 15] = m.m44;
}

// ---- Quat (h3d.Quat) ----

export function identityQuat(): Quat {
	return { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
}

// h3d.Quat.initRotateAxis: the axis does not need to be normalized.
export function axisAngle(axis: Vec3, angle: float32): Quat {
	const s: float32 = sine(angle * 0.5);
	const c: float32 = cosine(angle * 0.5);
	const q: Quat = { x: axis.x * s, y: axis.y * s, z: axis.z * s, w: c * axis.length() };
	return q.normalized();
}

// h3d.Quat.initRotation: Euler angles, same order as rotationEuler.
export function eulerQuat(x: float32, y: float32, z: float32): Quat {
	const sinX: float32 = sine(x * 0.5);
	const cosX: float32 = cosine(x * 0.5);
	const sinY: float32 = sine(y * 0.5);
	const cosY: float32 = cosine(y * 0.5);
	const sinZ: float32 = sine(z * 0.5);
	const cosZ: float32 = cosine(z * 0.5);
	const cosYZ: float32 = cosY * cosZ;
	const sinYZ: float32 = sinY * sinZ;
	return {
		x: sinX * cosYZ - cosX * sinYZ,
		y: cosX * sinY * cosZ + sinX * cosY * sinZ,
		z: cosX * cosY * sinZ - sinX * sinY * cosZ,
		w: cosX * cosYZ + sinX * sinYZ,
	};
}

// The rotation carrying unit vector `from` onto unit vector `to`, by the shortest arc.
// Half-angle form, so no arccosine: with d = from.dot(to), sin(θ/2)/sin(θ) = 1/(2cos(θ/2)).
export function quatBetween(from: Vec3, to: Vec3): Quat {
	const axis: Vec3 = from.cross(to);
	const radicand: float32 = (1.0 + from.dot(to)) * 0.5;
	// A dot product of two unit vectors can round below -1, and sqrt of that is a NaN the
	// guard below would read as false: clamp by branch, so near-opposite takes the 180° path.
	const half: float32 = radicand > 0.0 ? squareRoot(radicand) : 0.0;
	if (half < EPSILON) {
		// Opposite: a 180-degree turn about any axis perpendicular to `from` carries it onto `to`.
		const helper: Vec3 = absolute(from.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		const perpendicular: Vec3 = from.cross(helper).normalized();
		return { x: perpendicular.x, y: perpendicular.y, z: perpendicular.z, w: 0.0 };
	}
	const k: float32 = 0.5 / half;
	return { x: axis.x * k, y: axis.y * k, z: axis.z * k, w: half };
}

export function dot(this a: Quat, b: Quat): float32 {
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

export function normalized(this q: Quat): Quat {
	const lengthSquared: float32 = q.dot(q);
	if (lengthSquared < EPSILON) {
		return identityQuat();
	}
	const k: float32 = 1.0 / squareRoot(lengthSquared);
	return { x: q.x * k, y: q.y * k, z: q.z * k, w: q.w * k };
}

export function conjugate(this q: Quat): Quat {
	return { x: -q.x, y: -q.y, z: -q.z, w: q.w };
}

// h3d.Quat.multiply(q1, q2): as matrices, `(q1 * q2).toMatrix() == q2.toMatrix() * q1.toMatrix()`.
export function `*`(this a: Quat, b: Quat): Quat {
	return {
		x: a.x * b.w + a.w * b.x + a.y * b.z - a.z * b.y,
		y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	};
}

export function toMatrix(this q: Quat): Mat4 {
	const xx: float32 = q.x * q.x;
	const xy: float32 = q.x * q.y;
	const xz: float32 = q.x * q.z;
	const xw: float32 = q.x * q.w;
	const yy: float32 = q.y * q.y;
	const yz: float32 = q.y * q.z;
	const yw: float32 = q.y * q.w;
	const zz: float32 = q.z * q.z;
	const zw: float32 = q.z * q.w;
	const two: float32 = 2.0;
	const one: float32 = 1.0;
	return {
		m11: one - two * (yy + zz), m12: two * (xy + zw), m13: two * (xz - yw), m14: 0.0,
		m21: two * (xy - zw), m22: one - two * (xx + zz), m23: two * (yz + xw), m24: 0.0,
		m31: two * (xz + yw), m32: two * (yz - xw), m33: one - two * (xx + yy), m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 1.0,
	};
}

// h3d.Quat.lerp with `nearest`: flips `b` onto `a`'s hemisphere, then normalizes.
export function nlerp(this a: Quat, b: Quat, k: float32): Quat {
	const toward: float32 = a.dot(b) < 0.0 ? -k : k;
	const keep: float32 = 1.0 - k;
	const q: Quat = {
		x: a.x * keep + b.x * toward,
		y: a.y * keep + b.y * toward,
		z: a.z * keep + b.z * toward,
		w: a.w * keep + b.w * toward,
	};
	return q.normalized();
}

export function slerp(this a: Quat, b: Quat, k: float32): Quat {
	let cosTheta: float32 = a.dot(b);
	let target: Quat = b;
	if (cosTheta < 0.0) {
		cosTheta = -cosTheta;
		target = { x: -b.x, y: -b.y, z: -b.z, w: -b.w };
	}
	let keep: float32 = 1.0 - k;
	let toward: float32 = k;
	if (1.0 - cosTheta > 0.0001) {
		const omega: float32 = Math.acos(cosTheta) as float32;
		const inverseSine: float32 = 1.0 / sine(omega);
		keep = sine((1.0 - k) * omega) * inverseSine;
		toward = sine(k * omega) * inverseSine;
	}
	return {
		x: keep * a.x + toward * target.x,
		y: keep * a.y + toward * target.y,
		z: keep * a.z + toward * target.z,
		w: keep * a.w + toward * target.w,
	};
}
