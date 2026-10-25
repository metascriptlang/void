// The shadow-map lookups every shadowed program shares: a world position through a map matrix to
// the map's texel space, and the depth comparison that darkens it.

import {
	Mat4x4f, Vec2f, Vec2i, Vec3f, Vec4f, clamp, cos, dot, fract, mix, sin, vec2f, vec2i, vec3f,
	vec4f,
} from "../shader/std";

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

// h3d.shader.ShadowSampling's PCF: PCF_SAMPLES taps of a Poisson disk turned by a hash of the
// world position, the scale in texels where Heaps divides pcfScale by the map's width.
export const PCF_SAMPLES: int32 = 16;
export const POISSON_DISK: Vec2f[16] = [
	vec2f(-0.94201624, -0.39906216), vec2f(0.94558609, -0.76890725),
	vec2f(-0.09418410, -0.92938870), vec2f(0.34495938, 0.29387760),
	vec2f(-0.91588581, 0.45771432), vec2f(-0.81544232, -0.87912464),
	vec2f(-0.38277543, 0.27676845), vec2f(0.97484398, 0.75648379),
	vec2f(0.44323325, -0.97511554), vec2f(0.53742981, -0.47373420),
	vec2f(-0.26496911, -0.41893023), vec2f(0.79197514, 0.19090188),
	vec2f(-0.24188840, 0.99706507), vec2f(-0.81409955, 0.91437590),
	vec2f(0.19984126, 0.78641367), vec2f(0.14383161, -0.14100790),
];

export function poissonRotation(position: Vec3f): Vec2f {
	const dp = dot(vec4f(position.x + position.y + position.z),
		vec4f(12.9898, 78.233, 45.164, 94.673));
	const rotation = fract(sin(dp) * 43758.5453) * 3.14 * 2.0;
	return vec2f(cos(rotation), sin(rotation));
}

export function poissonOffset(tap: int32, rotation: Vec2f, scale: float32): Vec2f {
	const o = POISSON_DISK[tap] * scale;
	return vec2f(rotation.x * o.x - rotation.y * o.y, rotation.x * o.y + rotation.y * o.x);
}

// The texel of map-space `uv` moved by `offset` texels, clamped to the map.
export function pcfTexelOf(uv: Vec4f, size: int32, offset: Vec2f): Vec2i {
	return clamp(vec2i(uv.xy * vec2f(size as float32) + offset), vec2i(0, 0),
		vec2i(size - 1, size - 1));
}

// ShadowSampling's cubeShadowPcf directions, scaled by pcfScale / size around the unit direction.
export const CUBE_PCF_SAMPLES: int32 = 20;
export const CUBE_PCF_OFFSETS: Vec3f[20] = [
	vec3f(1.0, 1.0, 1.0), vec3f(1.0, -1.0, 1.0), vec3f(-1.0, -1.0, 1.0), vec3f(-1.0, 1.0, 1.0),
	vec3f(1.0, 1.0, -1.0), vec3f(1.0, -1.0, -1.0), vec3f(-1.0, -1.0, -1.0), vec3f(-1.0, 1.0, -1.0),
	vec3f(1.0, 1.0, 0.0), vec3f(1.0, -1.0, 0.0), vec3f(-1.0, -1.0, 0.0), vec3f(-1.0, 1.0, 0.0),
	vec3f(1.0, 0.0, 1.0), vec3f(-1.0, 0.0, 1.0), vec3f(1.0, 0.0, -1.0), vec3f(-1.0, 0.0, -1.0),
	vec3f(0.0, 1.0, 1.0), vec3f(0.0, -1.0, 1.0), vec3f(0.0, -1.0, -1.0), vec3f(0.0, 1.0, -1.0),
];
