// M4: the orthographic camera, its snap to the low-res texel grid, and the screen mapping it
// shares with the blit. All of it is arithmetic, so none of it needs a GPU.

import {
	OrthoCamera,
	CameraView,
	CameraError,
	CameraBasis,
	OrthoBounds,
	Ray,
	CAMERA_BLOCK_LENGTH,
} from "../void3d/camera";
import { LowResView, lowResView } from "../void3d/blit";
import { Vec3, vec3, identity } from "../math/math3d";
import { VERTEX_UNIFORM_LENGTH } from "../void3d/gpu3d";
import { approx } from "./helpers";

// The campfire's camera, and its rule for the texel size: 20 world units across the low-res
// image's short side (src/examples/campfireScene.ms).
const YAW: float32 = 0.785398;
const PITCH: float32 = 0.6;
const UNITS_ON_SHORT_SIDE: float32 = 20.0;
const TEXEL_WIDTH: int32 = 640;
const TEXEL_HEIGHT: int32 = 360;
const WORLD_PER_TEXEL: float32 = UNITS_ON_SHORT_SIDE / 360.0;
const PREVIEW_PER_TEXEL: float32 = UNITS_ON_SHORT_SIDE / 180.0;
const TOP_LEFT: boolean = true;
const BOTTOM_LEFT: boolean = false;

const NO_BASIS: CameraBasis = {
	right: vec3(0.0, 0.0, 0.0),
	up: vec3(0.0, 0.0, 0.0),
	forward: vec3(0.0, 0.0, 0.0),
};

const NO_VIEW: CameraView = {
	eye: vec3(0.0, 0.0, 0.0),
	basis: NO_BASIS,
	viewProj: identity(),
	remainderX: 0.0,
	remainderY: 0.0,
	texelWidth: 0,
	texelHeight: 0,
	worldPerTexel: 0.0,
};

const NO_LOW_RES: LowResView = { width: 0, height: 0, scale: 0, offsetX: 0.0, offsetY: 0.0 };

function snapping(snap: boolean): OrthoCamera {
	return {
		target: vec3(0.0, 0.0, 0.0),
		yaw: YAW,
		pitch: PITCH,
		worldPerTexel: WORLD_PER_TEXEL,
		nearPlane: -50.0,
		farPlane: 50.0,
		snap: snap,
	};
}

// The camera looking at a target `texels` along its own right axis.
function slid(snap: boolean, texels: float32): OrthoCamera {
	const base: OrthoCamera = snapping(snap);
	return { ...base, target: base.basisOf().right.scaled(texels * WORLD_PER_TEXEL) };
}

function viewOf(camera: OrthoCamera): CameraView {
	return try camera.resolve(TEXEL_WIDTH, TEXEL_HEIGHT) catch NO_VIEW;
}

// The blit of a 1280x720 framebuffer at the campfire's settings: 640x360 texels at 2x.
function blitOf(margin: int32): LowResView {
	return try lowResView(1280, 720, 360, 1, margin) catch NO_LOW_RES;
}

// Where the eye sits along an axis, counted in texels.
function texelsAlong(view: CameraView, axis: Vec3): float32 {
	return view.eye.dot(axis) / WORLD_PER_TEXEL;
}

// How far a texel count is from the nearest whole texel. Not `x - floor(x)`: a count that
// lands a hair below a whole texel is on the grid too.
function offGrid(texels: float32): float32 {
	const under: float32 = texels - (Math.floor(texels) as float32);
	return under < 0.5 ? under : 1.0 - under;
}

function nearVec(a: Vec3, b: Vec3): boolean {
	return approx(a.x, b.x) && approx(a.y, b.y) && approx(a.z, b.z);
}

test "the camera block is the scene programs' vertex block" {
	assert CAMERA_BLOCK_LENGTH == VERTEX_UNIFORM_LENGTH;
	const view: CameraView = viewOf(snapping(false));
	const block: Vec<float32> = new Array(CAMERA_BLOCK_LENGTH);
	view.writeCameraBlock(block);
	assert approx(block[16], view.basis.right.x);
	assert approx(block[18], view.basis.right.z);
	assert approx(block[20], view.basis.up.x);
	assert approx(block[21], view.basis.up.y);
	assert block[19] == 0.0 && block[23] == 0.0;
}

test "the basis is orthonormal and looks down from the yaw" {
	const basis: CameraBasis = snapping(false).basisOf();
	assert approx(basis.right.length(), 1.0);
	assert approx(basis.up.length(), 1.0);
	assert approx(basis.forward.length(), 1.0);
	assert approx(basis.right.dot(basis.up), 0.0);
	assert approx(basis.right.dot(basis.forward), 0.0);
	assert approx(basis.up.dot(basis.forward), 0.0);
	// Pitched down: the view direction points below the horizon and the up axis stays above it.
	assert basis.forward.y < 0.0 && basis.up.y > 0.0;
	// Yaw only turns around Y, so right stays level.
	assert approx(basis.right.y, 0.0);
}

test "the target is the middle of the image and the depth range fills [0, 1]" {
	const camera: OrthoCamera = snapping(false);
	const view: CameraView = viewOf(camera);
	const middle: Vec3 = camera.target.project(view.viewProj);
	assert approx(middle.x, 0.0) && approx(middle.y, 0.0);
	assert approx(middle.z, 0.5);
	const atNear: Vec3 = view.basis.forward.scaled(camera.nearPlane).project(view.viewProj);
	const atFar: Vec3 = view.basis.forward.scaled(camera.farPlane).project(view.viewProj);
	assert approx(atNear.z, 0.0) && approx(atFar.z, 1.0);
	// A corner of the low-res image is a corner of the view volume.
	const across: float32 = (TEXEL_WIDTH as float32) * WORLD_PER_TEXEL * 0.5;
	const corner: Vec3 = view.basis.right.scaled(across).project(view.viewProj);
	assert approx(corner.x, 1.0) && approx(corner.y, 0.0);
}

test "ortho bounds follow the low-res view, its divisor and its margin" {
	const camera: OrthoCamera = snapping(false);
	const full: OrthoBounds = camera.orthoBounds(TEXEL_WIDTH, TEXEL_HEIGHT);
	assert approx(full.maxX - full.minX, (TEXEL_WIDTH as float32) * WORLD_PER_TEXEL);
	assert approx(full.maxY - full.minY, UNITS_ON_SHORT_SIDE);
	assert approx(full.minX, -full.maxX) && approx(full.minY, -full.maxY);
	assert full.minZ == camera.nearPlane && full.maxZ == camera.farPlane;

	// The preview halves the target and doubles the texel, so it covers the same world.
	const preview: LowResView = try lowResView(1280, 720, 360, 2, 0) catch NO_LOW_RES;
	const halved: OrthoCamera = { ...camera, worldPerTexel: PREVIEW_PER_TEXEL };
	const smaller: OrthoBounds = halved.orthoBounds(preview.width, preview.height);
	assert preview.width == 320 && preview.height == 180;
	assert approx(smaller.maxX - smaller.minX, full.maxX - full.minX);
	assert approx(smaller.maxY - smaller.minY, full.maxY - full.minY);

	// A margin of one texel is one more texel of world on every side, drawn rather than
	// invented, which is what lets the blit shift the image without sampling past the edge.
	const bordered: LowResView = blitOf(1);
	const grown: OrthoBounds = camera.orthoBounds(bordered.width, bordered.height);
	assert bordered.width == TEXEL_WIDTH + 2 && bordered.height == TEXEL_HEIGHT + 2;
	assert approx(grown.maxX - full.maxX, WORLD_PER_TEXEL);
	assert approx(grown.maxY - full.maxY, WORLD_PER_TEXEL);
}

test "the snap holds the eye still inside a texel and the remainder rises with it" {
	const steps: Vec<float32> = [0.1, 0.3, 0.5, 0.7, 0.9];
	const first: CameraView = viewOf(slid(true, steps[0]));
	for (const step of steps) {
		const view: CameraView = viewOf(slid(true, step));
		assert nearVec(view.eye, first.eye);
		assert approx(view.remainderX, step);
		assert approx(view.remainderY, 0.0);
	}
}

test "a whole texel of travel moves the snapped eye exactly one texel" {
	const before: CameraView = viewOf(slid(true, 0.4));
	const after: CameraView = viewOf(slid(true, 1.4));
	const right: Vec3 = snapping(true).basisOf().right;
	assert approx(texelsAlong(after, right) - texelsAlong(before, right), 1.0);
	assert approx(after.remainderX, before.remainderX);
}

test "the remainder stays in [0, 1) and the eye stays on the grid" {
	const offsets: Vec<float32> = [-7.75, -1.4, -0.2, 0.0, 0.05, 2.5, 3.999, 41.25];
	const basis: CameraBasis = snapping(true).basisOf();
	for (const offset of offsets) {
		const camera: OrthoCamera = {
			...snapping(true),
			target: basis.right.scaled(offset * WORLD_PER_TEXEL) +
				basis.up.scaled(offset * 0.5 * WORLD_PER_TEXEL),
		};
		const view: CameraView = viewOf(camera);
		assert view.remainderX >= 0.0 && view.remainderX < 1.0;
		assert view.remainderY >= 0.0 && view.remainderY < 1.0;
		// The snapped eye sits on a texel of the grid, and the remainder is what is left of the
		// way there: snapped + remainder is the position asked for.
		const alongRight: float32 = texelsAlong(view, basis.right);
		assert approx(offGrid(alongRight), 0.0);
		assert approx(alongRight + view.remainderX, offset);
	}
}

test "no snap leaves the camera where it was asked to be" {
	const camera: OrthoCamera = slid(false, 0.37);
	const view: CameraView = viewOf(camera);
	assert view.remainderX == 0.0 && view.remainderY == 0.0;
	assert nearVec(view.eye, camera.target);
}

test "the snap and the blit's remainder cancel, in both row orders" {
	const point: Vec3 = vec3(1.5, 0.75, -2.25);
	const loose: CameraView = viewOf(slid(false, 3.4));
	const snapped: CameraView = viewOf(slid(true, 3.4));
	const plain: LowResView = blitOf(1);
	const shifted: LowResView = plain.withRemainder(
		snapped.remainderX,
		snapped.remainderY,
		TOP_LEFT,
	);
	const loosely: Vec3 = loose.project(point, plain, TOP_LEFT);
	const snaply: Vec3 = snapped.project(point, shifted, TOP_LEFT);
	assert approx(loosely.x, snaply.x) && approx(loosely.y, snaply.y);

	const upward: LowResView = plain.withRemainder(
		snapped.remainderX,
		snapped.remainderY,
		BOTTOM_LEFT,
	);
	const below: Vec3 = loose.project(point, plain, BOTTOM_LEFT);
	const snappedBelow: Vec3 = snapped.project(point, upward, BOTTOM_LEFT);
	assert approx(below.x, snappedBelow.x) && approx(below.y, snappedBelow.y);
}

test "project and rayFromScreen are inverses through the blit" {
	const view: CameraView = viewOf(slid(true, 2.6));
	const blit: LowResView = blitOf(1);
	const points: Vec<Vec3> = [
		vec3(0.0, 0.0, 0.0),
		vec3(3.25, 1.5, -4.0),
		vec3(-6.5, 0.25, 7.75),
	];
	for (const point of points) {
		const screen: Vec3 = view.project(point, blit, TOP_LEFT);
		const ray: Ray = view.rayFromScreen(screen.x, screen.y, blit, TOP_LEFT);
		// Orthographic: the ray runs along the view direction and the point lies on it.
		assert nearVec(ray.direction, view.basis.forward);
		const toPoint: Vec3 = point - ray.origin;
		assert approx(toPoint.dot(view.basis.right), 0.0);
		assert approx(toPoint.dot(view.basis.up), 0.0);
	}
}

test "rayFromScreen reads the framebuffer, not the low-res target" {
	const view: CameraView = viewOf(snapping(false));
	const blit: LowResView = blitOf(0);
	// Two framebuffer pixels inside one texel are the same texel, so their rays are one texel
	// apart at most; two pixels a whole scale apart are exactly one texel apart.
	const step: float32 = blit.scale as float32;
	const first: Ray = view.rayFromScreen(100.0, 100.0, blit, TOP_LEFT);
	const nudged: Ray = view.rayFromScreen(101.0, 100.0, blit, TOP_LEFT);
	const stepped: Ray = view.rayFromScreen(100.0 + step, 100.0, blit, TOP_LEFT);
	const nudge: float32 = (nudged.origin - first.origin).dot(view.basis.right);
	const whole: float32 = (stepped.origin - first.origin).dot(view.basis.right);
	assert approx(whole, WORLD_PER_TEXEL);
	assert approx(nudge, WORLD_PER_TEXEL / step);
	// Top-left row order: going down the framebuffer goes down the camera's up axis.
	const lower: Ray = view.rayFromScreen(100.0, 100.0 + step, blit, TOP_LEFT);
	assert approx((lower.origin - first.origin).dot(view.basis.up), -WORLD_PER_TEXEL);
	const bottomFirst: Ray = view.rayFromScreen(100.0, 100.0, blit, BOTTOM_LEFT);
	const higher: Ray = view.rayFromScreen(100.0, 100.0 + step, blit, BOTTOM_LEFT);
	assert approx((higher.origin - bottomFirst.origin).dot(view.basis.up), WORLD_PER_TEXEL);
}

test "a camera that cannot be resolved says which part is wrong" {
	const camera: OrthoCamera = snapping(true);
	const empty: Result<CameraView, CameraError> = camera.resolve(0, TEXEL_HEIGHT);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == CameraError.EmptyTarget; }

	const noGrid: OrthoCamera = { ...camera, worldPerTexel: 0.0 };
	const gridless: Result<CameraView, CameraError> = noGrid.resolve(TEXEL_WIDTH, TEXEL_HEIGHT);
	assert !gridless.ok;
	if (!gridless.ok) { assert gridless.error == CameraError.BadWorldPerTexel; }

	const noDepth: OrthoCamera = { ...camera, farPlane: camera.nearPlane };
	const flat: Result<CameraView, CameraError> = noDepth.resolve(TEXEL_WIDTH, TEXEL_HEIGHT);
	assert !flat.ok;
	if (!flat.ok) { assert flat.error == CameraError.EmptyDepthRange; }
}
