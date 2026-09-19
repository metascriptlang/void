// Port of h3d.Camera, the orthographic subset void3d needs: `makeCameraMatrix`, the
// `orthoBounds` branch of `makeFrustumMatrix`, `project` and `rayFromScreen` — plus the snap to
// the low-res texel grid, which Heaps has no equivalent of and which RENDERER-BRIEF §3.3 calls
// the single most important part of the look: a camera that moves by less than one low-res texel
// makes the whole image shimmer.
//
// Two structs, because what the caller wants and where the camera ends up are different things
// once the snap is in play. `OrthoCamera` is the request: a target point, a fixed yaw and pitch,
// how many world units one low-res texel covers, and the depth range around it.
// `CameraView` is the resolved frame: the snapped eye and its basis, the viewProj the scene
// programs read, and the remainder the snap left over, which `pixelArtRenderer.viewFor` hands to
// the blit (blit.ms `withRemainder`).
//
// Conventions, as everywhere in void3d: Y up, right-handed, row vectors (`p * m`, `local *
// parent`), depth in [0, 1]. Heaps' `rightHanded` flag negates the camera matrix's third column
// and then negates the projection's z back; both are folded away here, so the third column is
// the view direction itself and z maps [near, far] onto [0, 1] with no sign play. The result is
// Heaps with `rightHanded = true`.
//
// Everything is a value and nothing allocates or touches the GPU, so a lost context costs the
// camera nothing and all of it is tested headless (src/test/cameraCheck.ms).

import { Vec3, Vec4, Mat4, vec3 } from "../math/math3d";
import { LowResView, ViewPoint } from "./blit";

// Floats in the scene programs' camera block: viewProj, then cameraRight and cameraUp
// (shader3d.glsl `vertexParams`). It is gpu3d's VERTEX_UNIFORM_LENGTH, which cameraCheck.ms
// asserts so the two cannot drift.
export const CAMERA_BLOCK_LENGTH: int32 = 24;

export struct OrthoCamera {
	// The point the view is centred on, before snapping.
	target: Vec3;
	// Fixed orientation: yaw turns around Y, pitch tilts the view down from the horizon.
	yaw: float32;
	pitch: float32;
	// World units one low-res texel covers. It sets both the ortho extents and the snap grid.
	worldPerTexel: float32;
	// What the camera sees in front of and behind the target, along the view direction. An
	// orthographic camera has no position along that axis — sliding it there moves nothing but
	// the clip planes — so the target is the eye and there is no distance to set.
	// Named for the plane, not `near`/`far`: those are macros in the Windows C headers
	// (docs/VOID3D.md, Compiler notes).
	nearPlane: float32;
	farPlane: float32;
	// Snap the eye to the texel grid and report the remainder. Off leaves the eye where it is
	// and the remainder at zero, which is what the shimmer looks like.
	snap: boolean;
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

// h3d.col.Ray, the part a pick needs. M10 moves it to its own module with the intersection
// tests against bounds and triangles.
export struct Ray {
	origin: Vec3;
	direction: Vec3;
}

export struct CameraView {
	// Where the camera actually is, after the snap.
	eye: Vec3;
	basis: CameraBasis;
	viewProj: Mat4;
	// What the snap left over: the true eye minus the snapped one, in low-res texels along
	// `right` and `up`, each in [0, 1). blit.ms `withRemainder` puts it back as a blit offset,
	// so the image shows the true position while the scene is drawn from the snapped one.
	remainderX: float32;
	remainderY: float32;
	// The low-res target this view was resolved for.
	texelWidth: int32;
	texelHeight: int32;
	worldPerTexel: float32;
}

export enum CameraError {
	EmptyTarget,
	BadWorldPerTexel,
	EmptyDepthRange,
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

export function basisOf(this camera: OrthoCamera): CameraBasis {
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
	this camera: OrthoCamera,
	texelWidth: int32,
	texelHeight: int32,
): OrthoBounds {
	const half: float32 = camera.worldPerTexel * 0.5;
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

// The frame this camera draws on a `texelWidth` x `texelHeight` low-res target: the snapped eye,
// its viewProj, and the remainder the blit needs. Pure arithmetic — call it every frame.
export function resolve(
	this camera: OrthoCamera,
	texelWidth: int32,
	texelHeight: int32,
): Result<CameraView, CameraError> {
	if (texelWidth <= 0 || texelHeight <= 0) {
		return Result.err(CameraError.EmptyTarget);
	}
	if (camera.worldPerTexel <= 0.0) {
		return Result.err(CameraError.BadWorldPerTexel);
	}
	if (camera.farPlane <= camera.nearPlane) {
		return Result.err(CameraError.EmptyDepthRange);
	}
	const basis: CameraBasis = camera.basisOf();
	const placed: SnappedEye = camera.snap ?
		basis.snapEye(camera.target, camera.worldPerTexel) :
		{ eye: camera.target, remainderX: 0.0, remainderY: 0.0 };
	const cameraMatrix: Mat4 = basis.makeCameraMatrix(placed.eye);
	const projection: Mat4 = camera.orthoBounds(texelWidth, texelHeight).projectionMatrix();
	return Result.ok({
		eye: placed.eye,
		basis: basis,
		viewProj: cameraMatrix * projection,
		remainderX: placed.remainderX,
		remainderY: placed.remainderY,
		texelWidth: texelWidth,
		texelHeight: texelHeight,
		worldPerTexel: camera.worldPerTexel,
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
// floor (blit.ms `texelAt`). Orthographic, so the direction comes out the same for every pixel
// and only the origin moves; reading it off the matrix anyway is what checks the matrix.
export function rayFromScreen(
	this view: CameraView,
	framebufferX: float32,
	framebufferY: float32,
	blit: LowResView,
	originTopLeft: boolean,
): Ray {
	const texel: ViewPoint = blit.texelAt(framebufferX, framebufferY);
	const ndc: ViewPoint = ndcOf(texel, view.texelWidth, view.texelHeight, originTopLeft);
	const backwards: Mat4 = view.viewProj.inverse();
	const atNear: Vec3 = unproject(ndc, 0.0, backwards);
	const atFar: Vec3 = unproject(ndc, 1.0, backwards);
	return { origin: atNear, direction: (atFar - atNear).normalized() };
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
