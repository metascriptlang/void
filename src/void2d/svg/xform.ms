export const NSVG_PI: float32 = 3.14159265358979323846;
export const NSVG_KAPPA90: float32 = 0.5522847493;

const NSVG_EPSILON: float64 = 1e-12;

export function xformIdentity(t: float32[]): void {
	t[0] = 1.0;
	t[1] = 0.0;
	t[2] = 0.0;
	t[3] = 1.0;
	t[4] = 0.0;
	t[5] = 0.0;
}

export function xformSetTranslation(t: float32[], tx: float32, ty: float32): void {
	t[0] = 1.0;
	t[1] = 0.0;
	t[2] = 0.0;
	t[3] = 1.0;
	t[4] = tx;
	t[5] = ty;
}

export function xformSetScale(t: float32[], sx: float32, sy: float32): void {
	t[0] = sx;
	t[1] = 0.0;
	t[2] = 0.0;
	t[3] = sy;
	t[4] = 0.0;
	t[5] = 0.0;
}

export function xformSetSkewX(t: float32[], a: float32): void {
	t[0] = 1.0;
	t[1] = 0.0;
	t[2] = Math.tan(a as float64) as float32;
	t[3] = 1.0;
	t[4] = 0.0;
	t[5] = 0.0;
}

export function xformSetSkewY(t: float32[], a: float32): void {
	t[0] = 1.0;
	t[1] = Math.tan(a as float64) as float32;
	t[2] = 0.0;
	t[3] = 1.0;
	t[4] = 0.0;
	t[5] = 0.0;
}

export function xformSetRotation(t: float32[], a: float32): void {
	const cs: float32 = Math.cos(a as float64) as float32;
	const sn: float32 = Math.sin(a as float64) as float32;
	t[0] = cs;
	t[1] = sn;
	t[2] = -sn;
	t[3] = cs;
	t[4] = 0.0;
	t[5] = 0.0;
}

export function xformMultiply(t: float32[], s: float32[]): void {
	const t0: float32 = t[0] * s[0] + t[1] * s[2];
	const t2: float32 = t[2] * s[0] + t[3] * s[2];
	const t4: float32 = t[4] * s[0] + t[5] * s[2] + s[4];
	const t1: float32 = t[0] * s[1] + t[1] * s[3];
	const t3: float32 = t[2] * s[1] + t[3] * s[3];
	const t5: float32 = t[4] * s[1] + t[5] * s[3] + s[5];
	t[1] = t1;
	t[3] = t3;
	t[5] = t5;
	t[0] = t0;
	t[2] = t2;
	t[4] = t4;
}

// nsvg__xformInverse: a singular matrix turns `t` into the identity and leaves `inv` as it was.
export function xformInverse(inv: float32[], t: float32[]): void {
	const det: float64 = (t[0] as float64) * (t[3] as float64) - (t[2] as float64) * (t[1] as float64);
	if (det > -1e-6 && det < 1e-6) {
		xformIdentity(t);
		return;
	}
	const invdet: float64 = 1.0 / det;
	inv[0] = ((t[3] as float64) * invdet) as float32;
	inv[2] = (-(t[2] as float64) * invdet) as float32;
	inv[4] = (((t[2] as float64) * (t[5] as float64) - (t[3] as float64) * (t[4] as float64)) *
		invdet) as float32;
	inv[1] = (-(t[1] as float64) * invdet) as float32;
	inv[3] = ((t[0] as float64) * invdet) as float32;
	inv[5] = (((t[1] as float64) * (t[4] as float64) - (t[0] as float64) * (t[5] as float64)) *
		invdet) as float32;
}

export function xformPremultiply(t: float32[], s: float32[]): void {
	const s2: float32[] = [s[0], s[1], s[2], s[3], s[4], s[5]];
	xformMultiply(s2, t);
	for (let i: int32 = 0; i < 6; i++) { t[i] = s2[i]; }
}

// x*t[0] + y*t[2] + t[4] and x*t[1] + y*t[3] + t[5], as float32.
export function xformPointX(x: float32, y: float32, t: float32[]): float32 {
	const px: float32 = x * t[0] + y * t[2] + t[4];
	return px;
}

export function xformPointY(x: float32, y: float32, t: float32[]): float32 {
	const py: float32 = x * t[1] + y * t[3] + t[5];
	return py;
}

export function xformVecX(x: float32, y: float32, t: float32[]): float32 {
	const vx: float32 = x * t[0] + y * t[2];
	return vx;
}

export function xformVecY(x: float32, y: float32, t: float32[]): float32 {
	const vy: float32 = x * t[1] + y * t[3];
	return vy;
}

export function minf(a: float32, b: float32): float32 {
	return a < b ? a : b;
}

export function maxf(a: float32, b: float32): float32 {
	return a > b ? a : b;
}

function ptInBounds(x: float32, y: float32, bounds: float32[]): boolean {
	return x >= bounds[0] && x <= bounds[2] && y >= bounds[1] && y <= bounds[3];
}

function evalBezier(t: float64, p0: float64, p1: float64, p2: float64, p3: float64): float64 {
	const it: float64 = 1.0 - t;
	return it * it * it * p0 + 3.0 * it * it * t * p1 + 3.0 * it * t * t * p2 + t * t * t * p3;
}

// nsvg__curveBounds over the cubic curve[base .. base+7].
export function curveBounds(bounds: float32[], curve: float32[], base: int32): void {
	bounds[0] = minf(curve[base], curve[base + 6]);
	bounds[1] = minf(curve[base + 1], curve[base + 7]);
	bounds[2] = maxf(curve[base], curve[base + 6]);
	bounds[3] = maxf(curve[base + 1], curve[base + 7]);
	if (
		ptInBounds(curve[base + 2], curve[base + 3], bounds) &&
		ptInBounds(curve[base + 4], curve[base + 5], bounds)
	) { return; }
	for (let i: int32 = 0; i < 2; i++) {
		const v0 = curve[base + i] as float64;
		const v1 = curve[base + 2 + i] as float64;
		const v2 = curve[base + 4 + i] as float64;
		const v3 = curve[base + 6 + i] as float64;
		const a: float64 = -3.0 * v0 + 9.0 * v1 - 9.0 * v2 + 3.0 * v3;
		const b: float64 = 6.0 * v0 - 12.0 * v1 + 6.0 * v2;
		const c: float64 = 3.0 * v1 - 3.0 * v0;
		const roots: float64[] = [0.0, 0.0];
		let count: int32 = 0;
		if (Math.abs(a) < NSVG_EPSILON) {
			if (Math.abs(b) > NSVG_EPSILON) {
				const t: float64 = -c / b;
				if (t > NSVG_EPSILON && t < 1.0 - NSVG_EPSILON) {
					roots[count] = t;
					count += 1;
				}
			}
		} else {
			const b2ac: float64 = b * b - 4.0 * c * a;
			if (b2ac > NSVG_EPSILON) {
				const root = Math.sqrt(b2ac);
				const t0: float64 = (-b + root) / (2.0 * a);
				if (t0 > NSVG_EPSILON && t0 < 1.0 - NSVG_EPSILON) {
					roots[count] = t0;
					count += 1;
				}
				const t1: float64 = (-b - root) / (2.0 * a);
				if (t1 > NSVG_EPSILON && t1 < 1.0 - NSVG_EPSILON) {
					roots[count] = t1;
					count += 1;
				}
			}
		}
		for (let j: int32 = 0; j < count; j++) {
			const v = evalBezier(roots[j], v0, v1, v2, v3) as float32;
			bounds[0 + i] = minf(bounds[0 + i], v);
			bounds[2 + i] = maxf(bounds[2 + i], v);
		}
	}
}

export function sqrtf(x: float32): float32 {
	return Math.sqrt(x as float64) as float32;
}

export function absf(x: float32): float32 {
	return Math.abs(x as float64) as float32;
}
