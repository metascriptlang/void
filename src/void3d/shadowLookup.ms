// The shadow-map lookups every shadowed program shares: a world position through a map matrix to
// the map's texel space, and the depth comparison that darkens it.

import { Mat4x4f, Vec3f, Vec4f, clamp, mix, vec4f } from "../shader/std";

export function mapCoord(position: Vec3f, matrix: Mat4x4f): Vec4f {
	const q = matrix * vec4f(position, 1.0);
	if (q.w <= 0.0) {
		return vec4f(0.0, 0.0, 0.0, 0.0);
	}
	const p = q.xyz / q.w;
	if (p.x <= 0.0 || p.x >= 1.0 || p.y <= 0.0 || p.y >= 1.0) {
		return vec4f(0.0, 0.0, 0.0, 0.0);
	}
	return vec4f(p, 1.0);
}

export function mapLit(z: float32, depth: float32, bias: float32, opacity: float32): float32 {
	const lit: float32 = clamp(z, 0.0, 1.0) - bias > depth ? 0.0 : 1.0;
	return mix(1.0, lit, opacity);
}
