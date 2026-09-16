import { sinf, cosf } from "../math/mat4";

export const VERTEX_PARAMS_LENGTH: int32 = 24;
export const vertexParams: Vec<float32> = new Array(VERTEX_PARAMS_LENGTH);

export struct OrthoCamera {
	yaw: float32;
	pitch: float32;
	halfWidth: float32;
	halfHeight: float32;
	distance: float32;
	depthRange: float32;
}

export function writeVertexParams(this camera: OrthoCamera): void {
	const yawSin: float32 = sinf(camera.yaw);
	const yawCos: float32 = cosf(camera.yaw);
	const pitchSin: float32 = sinf(camera.pitch);
	const pitchCos: float32 = cosf(camera.pitch);

	const rightX: float32 = yawCos;
	const rightZ: float32 = -yawSin;
	const upX: float32 = -yawSin * pitchSin;
	const upY: float32 = pitchCos;
	const upZ: float32 = -yawCos * pitchSin;
	const forwardX: float32 = -yawSin * pitchCos;
	const forwardY: float32 = -pitchSin;
	const forwardZ: float32 = -yawCos * pitchCos;

	vertexParams[0] = rightX / camera.halfWidth;
	vertexParams[1] = upX / camera.halfHeight;
	vertexParams[2] = forwardX / camera.depthRange;
	vertexParams[3] = 0.0;
	vertexParams[4] = 0.0;
	vertexParams[5] = upY / camera.halfHeight;
	vertexParams[6] = forwardY / camera.depthRange;
	vertexParams[7] = 0.0;
	vertexParams[8] = rightZ / camera.halfWidth;
	vertexParams[9] = upZ / camera.halfHeight;
	vertexParams[10] = forwardZ / camera.depthRange;
	vertexParams[11] = 0.0;
	vertexParams[12] = 0.0;
	vertexParams[13] = 0.0;
	vertexParams[14] = camera.distance / camera.depthRange;
	vertexParams[15] = 1.0;

	vertexParams[16] = rightX;
	vertexParams[17] = 0.0;
	vertexParams[18] = rightZ;
	vertexParams[19] = 0.0;
	vertexParams[20] = upX;
	vertexParams[21] = upY;
	vertexParams[22] = upZ;
	vertexParams[23] = 0.0;
}
