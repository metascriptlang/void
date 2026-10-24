// The receiver's side of cascaded sun shadows (cascades.ms makes the maps): Bevy's
// fetch_directional_shadow (bevy_pbr/src/render/shadows.wesl:134-262). The fragment's view depth
// picks the first cascade whose far bound lies beyond it, and across the overlap before that far
// bound the next cascade's answer is blended in. Each cascade is one layer of the depth array,
// read at its texel as the single sun map is; the read itself sits with the program's bindings,
// and a uniform block reaches these helpers one member at a time.

import { Mat4x4f, Vec3f, Vec4f, clamp, dot, vec2f, vec2i, vec4f } from "../shader/std";
import { mapCoord, mapLit } from "./shadowLookup";

// cascadeMatrices[i] takes a world position to layer i's texel space and depth (cascade i's
// clipFromWorld times dirShadowMap's map matrix). cascadeFar holds the four far bounds in view
// depth. cascadeInfo holds the cascade count, the overlap, the depth bias and the opacity;
// cascadeView the camera's forward and the map size in texels.
export struct CascadeParams {
	cascadeMatrices: Mat4x4f[4];
	cascadeFar: Vec4f;
	cascadeInfo: Vec4f;
	cascadeView: Vec4f;
}

export function cascadeDepthOf(position: Vec3f, eye: Vec3f, view: Vec4f): float32 {
	return dot(position - eye, view.xyz);
}

export function cascadeCountOf(info: Vec4f): int32 {
	return (info.x + 0.5) as int32;
}

function farOf(far: Vec4f, cascade: int32): float32 {
	if (cascade == 0) {
		return far.x;
	}
	if (cascade == 1) {
		return far.y;
	}
	if (cascade == 2) {
		return far.z;
	}
	return far.w;
}

// get_cascade_index: the count when the depth lies past the last far bound.
export function cascadeIndexOf(depth: float32, far: Vec4f, info: Vec4f): int32 {
	const count = cascadeCountOf(info);
	for (let i = 0; i < count; i++) {
		if (depth < farOf(far, i)) {
			return i;
		}
	}
	return count;
}

// How much of the next cascade's answer the fragment takes: 0 before the overlap or with no next
// cascade, rising to 1 at this cascade's far bound.
export function cascadeBlendOf(depth: float32, cascade: int32, far: Vec4f, info: Vec4f): float32 {
	if (cascade + 1 >= cascadeCountOf(info)) {
		return 0.0;
	}
	const bound = farOf(far, cascade);
	const nextNear = (1.0 - info.y) * bound;
	if (depth < nextNear) {
		return 0.0;
	}
	return (depth - nextNear) / (bound - nextNear);
}

// The texel of a cascade's layer the position reads and its depth in that map, w 0 off the map.
export function cascadeTexelOf(position: Vec3f, matrix: Mat4x4f, view: Vec4f): Vec4f {
	const at = mapCoord(position, matrix);
	if (at.w < 0.5) {
		return vec4f(0.0, 0.0, 0.0, 0.0);
	}
	const size = (view.w + 0.5) as int32;
	const texel = clamp(vec2i(at.xy * vec2f(size as float32)), vec2i(0, 0),
		vec2i(size - 1, size - 1));
	return vec4f(texel.x as float32, texel.y as float32, at.z, 1.0);
}

// The lit share of a fragment whose texel holds `stored`.
export function cascadeLitOf(texel: Vec4f, stored: float32, info: Vec4f): float32 {
	if (texel.w < 0.5) {
		return 1.0;
	}
	return mapLit(texel.z, stored, info.z, info.w);
}
