import { Mat4x4f, Texture2d, Texture2dArray, Vec4f, mat4x4f, vec4f } from "../shader/std";
import {
	SHADOW_CASCADE_FAR,
	SHADOW_CASCADE_INFO,
	SHADOW_CASCADE_VIEW,
	SHADOW_SPOT_BASE,
	SHADOW_SPOT_BIAS,
} from "../void3d/gpu3d";
import { ShadowParams } from "../void3d/shader3d";

const ALL_DEPTHS: float32 = 3.0e38;

export function oneLayer(texture: Texture2d): Texture2dArray {
	return { width: texture.width, height: texture.height, layers: 1, texels: texture.texels };
}

// The block a one-cascade sun map writes: `sun` and `spot` carry each map's bias and opacity in x
// and y, and `size` is both maps' width in texels.
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
		spotMatrix: spotMatrix,
		spotShadow: vec4f(spot.x, spot.y, size, 0.0),
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
		spotMatrix: matrixAt(values, SHADOW_SPOT_BASE),
		spotShadow: quadAt(values, SHADOW_SPOT_BIAS),
	};
}
