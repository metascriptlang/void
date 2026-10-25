import { Mat4x4f, Texture2d, Texture2dArray, Vec4f, mat4x4f, vec4f } from "../shader/std";
import {
	SHADOW_CASCADE_FAR,
	SHADOW_CASCADE_INFO,
	SHADOW_CASCADE_VIEW,
	SHADOW_CASCADE_FILTER,
	SHADOW_SPOT_BASE,
	SHADOW_SPOT_BIAS,
	SHADOW_CUBE_BASE,
	SHADOW_CUBE_BIAS,
	SHADOW_CUBE_POSITION,
} from "../void3d/gpu3d";
import { ShadowParams } from "../void3d/shader3d";

const ALL_DEPTHS: float32 = 3.0e38;
const NONE: Vec4f = vec4f(0.0, 0.0, 0.0, 0.0);
const ZERO: Mat4x4f = mat4x4f(NONE, NONE, NONE, NONE);

export function oneLayer(texture: Texture2d): Texture2dArray {
	return { width: texture.width, height: texture.height, layers: 1, texels: texture.texels };
}

// The block a one-cascade sun map writes: `sun` and `spot` carry each map's bias and opacity in x
// and y, and `size` is both maps' width in texels. Its point part is zero.
export function oneCascade(
	sunMatrix: Mat4x4f,
	sun: Vec4f,
	spotMatrix: Mat4x4f,
	spot: Vec4f,
	size: float32,
): ShadowParams {
	return {
		cascadeMatrices: [sunMatrix, sunMatrix, sunMatrix, sunMatrix],
		cascadeFar: vec4f(ALL_DEPTHS, 0.0, 0.0, 0.0),
		cascadeInfo: vec4f(1.0, 0.0, sun.x, sun.y),
		cascadeView: vec4f(0.0, 0.0, 1.0, size),
		cascadeFilter: NONE,
		spotMatrix: spotMatrix,
		spotShadow: vec4f(spot.x, spot.y, size, 0.0),
		cubeMatrices: [ZERO, ZERO, ZERO, ZERO, ZERO, ZERO],
		cubeShadow: NONE,
		cubeLight: NONE,
	};
}

function quadAt(values: Vec<float32>, at: int32): Vec4f {
	return vec4f(values[at], values[at + 1], values[at + 2], values[at + 3]);
}

function matrixAt(values: Vec<float32>, at: int32): Mat4x4f {
	return mat4x4f(quadAt(values, at), quadAt(values, at + 4), quadAt(values, at + 8),
		quadAt(values, at + 12));
}

export function shadowParamsOf(values: Vec<float32>): ShadowParams {
	return {
		cascadeMatrices: [
			matrixAt(values, 0), matrixAt(values, 16), matrixAt(values, 32), matrixAt(values, 48),
		],
		cascadeFar: quadAt(values, SHADOW_CASCADE_FAR),
		cascadeInfo: quadAt(values, SHADOW_CASCADE_INFO),
		cascadeView: quadAt(values, SHADOW_CASCADE_VIEW),
		cascadeFilter: quadAt(values, SHADOW_CASCADE_FILTER),
		spotMatrix: matrixAt(values, SHADOW_SPOT_BASE),
		spotShadow: quadAt(values, SHADOW_SPOT_BIAS),
		cubeMatrices: [
			matrixAt(values, SHADOW_CUBE_BASE), matrixAt(values, SHADOW_CUBE_BASE + 16),
			matrixAt(values, SHADOW_CUBE_BASE + 32), matrixAt(values, SHADOW_CUBE_BASE + 48),
			matrixAt(values, SHADOW_CUBE_BASE + 64), matrixAt(values, SHADOW_CUBE_BASE + 80),
		],
		cubeShadow: quadAt(values, SHADOW_CUBE_BIAS),
		cubeLight: quadAt(values, SHADOW_CUBE_POSITION),
	};
}
