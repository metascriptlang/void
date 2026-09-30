import { Vec3, Vec4, Mat4, vec3 } from "../math/math3d";
import { LowResView, ViewPoint } from "./blit";
import { Ray } from "./ray";

export const CAMERA_BLOCK_LENGTH: int32 = 24;

export enum ProjectionKind {
	Orthographic,
	Perspective,
}

export type CameraProjection = match (kind: ProjectionKind) {
	ProjectionKind.Orthographic => { worldPerTexel: float32, snap: boolean },
	ProjectionKind.Perspective => { fovY: float32 },
};

export struct Camera3D {
	position: Vec3;
	yaw: float32;
	pitch: float32;
	nearPlane: float32;
	farPlane: float32;
	projection: CameraProjection;
}

// The camera's own axes. With world up at +Y this is exactly Heaps' lookAt basis (`ax =
// up.cross(az)`, `ay = az.cross(ax)`), written as trigonometry instead: the axes come out
// unit-length with no normalize, and yaw and pitch are what the caller has anyway.
export struct CameraBasis {
	right: Vec3;
	up: Vec3;
	forward: Vec3;
}

// h3d.Camera.orthoBounds, in camera space: the camera matrix puts the target at the origin, so
// x and y are symmetric around it and z runs from the near plane to the far one.
export struct OrthoBounds {
	minX: float32;
	maxX: float32;
	minY: float32;
	maxY: float32;
	minZ: float32;
	maxZ: float32;
}

export struct CameraView {
	eye: Vec3;
	basis: CameraBasis;
	viewProj: Mat4;
	inverseViewProj: Mat4;
	// What the snap left over: the true eye minus the snapped one, in low-res texels along
	// `right` and `up`, each in [0, 1). blit.ms `withRemainder` puts it back as a blit offset,
	// so the image shows the true position while the scene is drawn from the snapped one.
	remainderX: float32;
	remainderY: float32;
	// The low-res target this view was resolved for.
	texelWidth: int32;
	texelHeight: int32;
}

export enum CameraError {
	EmptyTarget,
	BadWorldPerTexel,
	EmptyDepthRange,
	BadFov,
	NonFinitePose,
	NonFiniteProjection,
	UnrepresentableDepthRange,
	UnprojectableView,
}

// Where the eye landed and by how much it missed, in texels.
struct SnappedEye {
	eye: Vec3;
	remainderX: float32;
	remainderY: float32;
}

function sine(a: float32): float32 { return Math.sin(a) as float32; }
function cosine(a: float32): float32 { return Math.cos(a) as float32; }
function floored(a: float32): float32 { return Math.floor(a) as float32; }

// ---- Basis, camera matrix, projection ----

export function basisOf(this camera: Camera3D): CameraBasis {
	const yawSin: float32 = sine(camera.yaw);
	const yawCos: float32 = cosine(camera.yaw);
	const pitchSin: float32 = sine(camera.pitch);
	const pitchCos: float32 = cosine(camera.pitch);
	return {
		right: vec3(yawCos, 0.0, -yawSin),
		up: vec3(-yawSin * pitchSin, pitchCos, -yawCos * pitchSin),
		forward: vec3(-yawSin * pitchCos, -pitchSin, -yawCos * pitchCos),
	};
}

// h3d.Camera.makeCameraMatrix: the transpose of a lookAt, so that `p * m` reads `p - eye` in the
// camera's own axes.
export function makeCameraMatrix(this basis: CameraBasis, eye: Vec3): Mat4 {
	return {
		m11: basis.right.x, m12: basis.up.x, m13: basis.forward.x, m14: 0.0,
		m21: basis.right.y, m22: basis.up.y, m23: basis.forward.y, m24: 0.0,
		m31: basis.right.z, m32: basis.up.z, m33: basis.forward.z, m34: 0.0,
		m41: -basis.right.dot(eye),
		m42: -basis.up.dot(eye),
		m43: -basis.forward.dot(eye),
		m44: 1.0,
	};
}

// The view's extents at a low-res target size: one texel is `worldPerTexel` world units, so the
// visible world grows with the target and the margin the blit asks for is rendered rather than
// invented.
export function orthoBounds(
	this camera: Camera3D,
	texelWidth: int32,
	texelHeight: int32,
): OrthoBounds {
	let projection: CameraProjection = camera.projection;
	if (projection.kind != ProjectionKind.Orthographic) {
		console.log("void3d: orthoBounds asked of a perspective camera");
		unreachable;
	}
	let half: float32 = projection.worldPerTexel * 0.5;
	const halfWidth: float32 = (texelWidth as float32) * half;
	const halfHeight: float32 = (texelHeight as float32) * half;
	return {
		minX: -halfWidth,
		maxX: halfWidth,
		minY: -halfHeight,
		maxY: halfHeight,
		minZ: camera.nearPlane,
		maxZ: camera.farPlane,
	};
}

// h3d.Camera.makeFrustumMatrix, its orthoBounds branch: the box maps onto x and y in [-1, 1] and
// z in [0, 1].
export function projectionMatrix(this bounds: OrthoBounds): Mat4 {
	const width: float32 = 1.0 / (bounds.maxX - bounds.minX);
	const height: float32 = 1.0 / (bounds.maxY - bounds.minY);
	const depth: float32 = 1.0 / (bounds.maxZ - bounds.minZ);
	const scaleX: float32 = 2.0 * width;
	const scaleY: float32 = 2.0 * height;
	const offsetX: float32 = -(bounds.minX + bounds.maxX) * width;
	const offsetY: float32 = -(bounds.minY + bounds.maxY) * height;
	const offsetZ: float32 = -bounds.minZ * depth;
	return {
		m11: scaleX, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: scaleY, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: depth, m34: 0.0,
		m41: offsetX, m42: offsetY, m43: offsetZ, m44: 1.0,
	};
}

// ---- The snap ----

// The grid is the camera's own: the eye's components along `right` and `up` are measured in
// texels and floored, while the component along `forward` is left alone, because moving an
// orthographic camera along its view direction does not move the image. The remainder is the
// true position minus the snapped one, so it is in [0, 1) by construction, and the subtractions
// are exact — a float minus its own floor loses nothing.
function snapEye(this basis: CameraBasis, eye: Vec3, worldPerTexel: float32): SnappedEye {
	const alongRight: float32 = eye.dot(basis.right) / worldPerTexel;
	const alongUp: float32 = eye.dot(basis.up) / worldPerTexel;
	const remainderX: float32 = alongRight - floored(alongRight);
	const remainderY: float32 = alongUp - floored(alongUp);
	const back: Vec3 = basis.right.scaled(remainderX * worldPerTexel) +
		basis.up.scaled(remainderY * worldPerTexel);
	return { eye: eye - back, remainderX: remainderX, remainderY: remainderY };
}

export function resolve(
	this camera: Camera3D,
	texelWidth: int32,
	texelHeight: int32,
): Result<CameraView, CameraError> {
	if (texelWidth <= 0 || texelHeight <= 0) {
		return Result.err(CameraError.EmptyTarget);
	}
	if (!Number.isFinite(camera.position.x) || !Number.isFinite(camera.position.y) ||
		!Number.isFinite(camera.position.z) || !Number.isFinite(camera.yaw) ||
		!Number.isFinite(camera.pitch)) {
		return Result.err(CameraError.NonFinitePose);
	}
	if (!Number.isFinite(camera.nearPlane) || !Number.isFinite(camera.farPlane) ||
		camera.farPlane <= camera.nearPlane) {
		return Result.err(CameraError.EmptyDepthRange);
	}
	let basis: CameraBasis = camera.basisOf();
	let placed: SnappedEye = { eye: camera.position, remainderX: 0.0, remainderY: 0.0 };
	let matrix: Mat4;
	let projection: CameraProjection = camera.projection;
	match (projection.kind) {
		ProjectionKind.Orthographic => {
			if (!Number.isFinite(projection.worldPerTexel) || projection.worldPerTexel <= 0.0) {
				return Result.err(CameraError.BadWorldPerTexel);
			}
			if (projection.snap) {
				placed = basis.snapEye(camera.position, projection.worldPerTexel);
			}
			matrix = camera.orthoBounds(texelWidth, texelHeight).projectionMatrix();
		},
		ProjectionKind.Perspective => {
			if (!Number.isFinite(projection.fovY) ||
				projection.fovY <= 0.0 || projection.fovY >= 3.141592653589793) {
				return Result.err(CameraError.BadFov);
			}
			if (camera.nearPlane <= 0.0) {
				return Result.err(CameraError.EmptyDepthRange);
			}
			let scaleY: float32 = (1.0 / Math.tan(projection.fovY * 0.5)) as float32;
			let scaleX: float32 = scaleY * (texelHeight as float32) / (texelWidth as float32);
			let depth: float32 = camera.farPlane / (camera.farPlane - camera.nearPlane);
			if (depth <= 1.0) {
				return Result.err(CameraError.UnrepresentableDepthRange);
			}
			let offsetZ: float32 = -camera.nearPlane * depth;
			matrix = {
				m11: scaleX, m12: 0.0, m13: 0.0, m14: 0.0,
				m21: 0.0, m22: scaleY, m23: 0.0, m24: 0.0,
				m31: 0.0, m32: 0.0, m33: depth, m34: 1.0,
				m41: 0.0, m42: 0.0, m43: offsetZ, m44: 0.0,
			};
		},
	}
	if (!Number.isFinite(matrix.m11) || !Number.isFinite(matrix.m22) ||
		!Number.isFinite(matrix.m33) || !Number.isFinite(matrix.m43)) {
		return Result.err(CameraError.NonFiniteProjection);
	}
	let cameraMatrix: Mat4 = basis.makeCameraMatrix(placed.eye);
	let viewProj: Mat4 = cameraMatrix * matrix;
	let inverseViewProj: Mat4 = viewProj.inverse();
	if (projection.kind == ProjectionKind.Perspective && !inverseViewProj.supportsScreenRays()) {
		return Result.err(CameraError.UnprojectableView);
	}
	return Result.ok({
		eye: placed.eye,
		basis: basis,
		viewProj: viewProj,
		inverseViewProj: inverseViewProj,
		remainderX: placed.remainderX,
		remainderY: placed.remainderY,
		texelWidth: texelWidth,
		texelHeight: texelHeight,
	});
}

// ---- Uniforms ----

// The scene programs' camera block: viewProj in upload order, then the world-space right and up
// the billboard program builds its quads from (shader3d.glsl `vertexParams`).
export function writeCameraBlock(this view: CameraView, out: Span<float32>): void {
	view.viewProj.writeTo(out, 0);
	out[16] = view.basis.right.x;
	out[17] = view.basis.right.y;
	out[18] = view.basis.right.z;
	out[19] = 0.0;
	out[20] = view.basis.up.x;
	out[21] = view.basis.up.y;
	out[22] = view.basis.up.z;
	out[23] = 0.0;
}

// ---- Screen and back ----

// Normalized device coordinates of a continuous low-res texel coordinate, and back. The texel
// coordinate is in the target's row order, which is the framebuffer's: row 0 is the top on D3D11
// and Metal and the bottom on GL (gpu3d `originTopLeft`), so this is the flag the blit already
// takes.
function ndcOf(texel: ViewPoint, width: int32, height: int32, originTopLeft: boolean): ViewPoint {
	const across: float32 = texel.x * 2.0 / (width as float32) - 1.0;
	const down: float32 = texel.y * 2.0 / (height as float32);
	const up: float32 = originTopLeft ? 1.0 - down : down - 1.0;
	return { x: across, y: up };
}

function texelOf(ndc: ViewPoint, width: int32, height: int32, originTopLeft: boolean): ViewPoint {
	const across: float32 = (ndc.x + 1.0) * 0.5 * (width as float32);
	const down: float32 = originTopLeft ? 1.0 - ndc.y : ndc.y + 1.0;
	const row: float32 = down * 0.5 * (height as float32);
	return { x: across, y: row };
}

// h3d.Camera.project: a world point to the framebuffer pixel the blit puts it on, with the depth
// the pipeline sees in z. The path is the scene's viewProj, then the low-res texel grid, then
// the blit's own mapping (blit.ms `framebufferAt`), which makes it the inverse of
// `rayFromScreen` down to the shader's floor. Continuous, not rounded: Heaps' `snapToPixel` is
// the caller's business.
export function project(
	this view: CameraView,
	point: Vec3,
	blit: LowResView,
	originTopLeft: boolean,
): Vec3 {
	const clip: Vec4 = pointAt(point) * view.viewProj;
	const inverseW: float32 = 1.0 / clip.w;
	const ndc: ViewPoint = { x: clip.x * inverseW, y: clip.y * inverseW };
	const texel: ViewPoint = texelOf(ndc, view.texelWidth, view.texelHeight, originTopLeft);
	const pixel: ViewPoint = blit.framebufferAt(texel.x, texel.y);
	return vec3(pixel.x, pixel.y, clip.z * inverseW);
}

// h3d.Camera.rayFromScreen: the ray through a framebuffer pixel, from the near plane to the far
// one. Going back through the blit is what makes the argument a framebuffer pixel and not a
// low-res texel — the same `texel = (fragment + offset) / scale` the blit shader runs, minus its
// floor (blit.ms `texelAt`).
export function rayFromScreen(
	this view: CameraView,
	framebufferX: float32,
	framebufferY: float32,
	blit: LowResView,
	originTopLeft: boolean,
): Ray {
	const texel: ViewPoint = blit.texelAt(framebufferX, framebufferY);
	const ndc: ViewPoint = ndcOf(texel, view.texelWidth, view.texelHeight, originTopLeft);
	let atNear: Vec3 = unproject(ndc, 0.0, view.inverseViewProj);
	let atFar: Vec3 = unproject(ndc, 1.0, view.inverseViewProj);
	return Ray.fromPoints(atNear, atFar);
}

function pointAt(p: Vec3): Vec4 {
	return { x: p.x, y: p.y, z: p.z, w: 1.0 };
}

// h3d.Camera.unproject: a point of the [-1, 1] x [-1, 1] x [0, 1] view volume back to the world.
function unproject(ndc: ViewPoint, depth: float32, inverseViewProj: Mat4): Vec3 {
	const volume: Vec4 = { x: ndc.x, y: ndc.y, z: depth, w: 1.0 };
	const clip: Vec4 = volume * inverseViewProj;
	const inverseW: float32 = 1.0 / clip.w;
	return vec3(clip.x * inverseW, clip.y * inverseW, clip.z * inverseW);
}

function finitePoint(this point: Vec3): boolean {
	return Number.isFinite(point.x) && Number.isFinite(point.y) && Number.isFinite(point.z);
}

function supportsScreenRays(this inverseViewProj: Mat4): boolean {
	for (let sample = 0; sample < 5; sample++) {
		let x: float32 = sample == 4 ? 0.0 : (sample & 1) == 0 ? -1.0 : 1.0;
		let y: float32 = sample == 4 ? 0.0 : (sample & 2) == 0 ? -1.0 : 1.0;
		let ndc: ViewPoint = { x: x, y: y };
		let atNear: Vec3 = unproject(ndc, 0.0, inverseViewProj);
		let atFar: Vec3 = unproject(ndc, 1.0, inverseViewProj);
		if (!atNear.finitePoint() || !atFar.finitePoint()) { return false; }
		let ray: Ray = Ray.fromPoints(atNear, atFar);
		if (!ray.direction.finitePoint() || ray.direction.lengthSquared() <= 0.0) { return false; }
	}
	return true;
}
