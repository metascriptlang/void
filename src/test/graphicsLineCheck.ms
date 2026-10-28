// Heaps' LineShader, the screen-space line of h3d.scene.Graphics, run on the CPU: the line keeps
// its width in pixels at any depth, as LineShader.vertex scales it.

import { approx } from "./helpers";
import { Vec2f, Vec4f, vec2f, vec3f, vec4f } from "../shader/std";
import { vec3, vec4, Vec3, Vec4 } from "../math/math3d";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../void3d/camera";
import { lineClipOffset, lineScreenDirection, lineViewDepth } from "../void3d/shader3d";
import { Graphics3D, lineStyle, writeLineBlock } from "../void3d/graphics3d";
import {
	LINE_COLOR, LINE_FAR, LINE_LENGTH_SCALE, LINE_NEAR, LINE_PIXEL_SIZE, LINE_UNIFORM_LENGTH,
	LINE_WIDTH,
} from "../void3d/gpu3d";

const NEAR: float32 = 1.0;
const FAR: float32 = 11.0;

function perspective(): Camera3D {
	return {
		position: vec3(1.0, 2.0, 3.0),
		yaw: 0.5,
		pitch: -0.25,
		orientation: null,
		nearPlane: NEAR,
		farPlane: FAR,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0471976 },
	};
}

function resolved(camera: Camera3D, width: int32, height: int32): CameraView {
	let result: Result<CameraView, CameraError> = camera.resolve(width, height);
	if (result.ok) { return result.value; }
	unreachable;
}

function ahead(view: CameraView, distance: float32): Vec3 {
	const f: Vec3 = view.basis.forward;
	return vec3(view.eye.x + f.x * distance, view.eye.y + f.y * distance,
		view.eye.z + f.z * distance);
}

function clipOf(view: CameraView, point: Vec3): Vec4 {
	return vec4(point.x, point.y, point.z, 1.0) * view.viewProj;
}

function rightOf(view: CameraView): Vec4f {
	const r: Vec3 = view.basis.right;
	return vec4f(r.x, r.y, r.z, view.projectionX);
}

function upOf(view: CameraView): Vec4f {
	const u: Vec3 = view.basis.up;
	return vec4f(u.x, u.y, u.z, view.projectionY);
}

// The two corners of a line through `root` along `direction`, in pixels of a width by height
// target, as LineShader places them.
function corners(
	view: CameraView, root: Vec3, direction: Vec3, lineWidth: float32, width: int32, height: int32,
): Vec4f {
	const clip: Vec4 = clipOf(view, root);
	const across: Vec2f = lineScreenDirection(vec3f(direction.x, direction.y, direction.z),
		rightOf(view), upOf(view));
	const depth: float32 = lineViewDepth(clip.z / clip.w, NEAR, FAR);
	const pixel: Vec2f = vec2f(2.0 / (width as float32), 2.0 / (height as float32));
	const low: Vec2f = lineClipOffset(across, 0.0, depth, pixel, lineWidth);
	const high: Vec2f = lineClipOffset(across, 1.0, depth, pixel, lineWidth);
	const halfW: float32 = (width as float32) * 0.5;
	const halfH: float32 = (height as float32) * 0.5;
	return vec4f((clip.x + low.x) / clip.w * halfW, (clip.y + low.y) / clip.w * halfH,
		(clip.x + high.x) / clip.w * halfW, (clip.y + high.y) / clip.w * halfH);
}

function apart(c: Vec4f): float32 {
	return Math.sqrt((c.z - c.x) * (c.z - c.x) + (c.w - c.y) * (c.w - c.y)) as float32;
}

test "linearize gives back the view depth of a perspective depth, from near to far" {
	const view: CameraView = resolved(perspective(), 200, 200);
	const distances: float32[] = [1.0, 2.5, 7.0, 11.0];
	for (const distance of distances) {
		const clip: Vec4 = clipOf(view, ahead(view, distance));
		assert approx(clip.w, distance);
		const depth: float32 = lineViewDepth(clip.z / clip.w, NEAR, FAR);
		assert Math.abs(depth - distance) < distance * 0.0001;
	}
}

test "a line keeps its width in pixels at any depth, across its own screen direction" {
	const view: CameraView = resolved(perspective(), 200, 200);
	const direction: Vec3 = view.basis.right.scaled(0.6) + view.basis.up.scaled(0.8) +
		view.basis.forward.scaled(0.3);
	const distances: float32[] = [1.5, 4.0, 10.0];
	for (const distance of distances) {
		const root: Vec3 = ahead(view, distance);
		const c: Vec4f = corners(view, root, direction, 3.0, 200, 200);
		assert Math.abs(apart(c) - 3.0) < 0.001;
		const from: Vec4 = clipOf(view, root);
		const to: Vec4 = clipOf(view, root + direction.scaled(0.01));
		const runX: float32 = to.x / to.w - from.x / from.w;
		const runY: float32 = to.y / to.w - from.y / from.w;
		const run: float32 = Math.sqrt(runX * runX + runY * runY) as float32;
		const crossing: float32 = ((c.z - c.x) * runX + (c.w - c.y) * runY) / (run * apart(c));
		assert Math.abs(crossing) < 0.001;
	}
}

test "on a wide target the corners stay width apart but lean off the perpendicular, as Heaps'" {
	const view: CameraView = resolved(perspective(), 400, 200);
	const diagonal: Vec3 = view.basis.right + view.basis.up;
	const c: Vec4f = corners(view, ahead(view, 4.0), diagonal, 2.0, 400, 200);
	assert Math.abs(apart(c) - 2.0) < 0.001;
	const leaning: float32 = ((c.z - c.x) + (c.w - c.y)) / (Math.sqrt(2.0) as float32 * apart(c));
	assert Math.abs(leaning) > 0.1;
	const level: Vec4f = corners(view, ahead(view, 4.0), view.basis.right, 2.0, 400, 200);
	assert Math.abs(level.z - level.x) < 0.001;
	assert Math.abs(Math.abs(level.w - level.y) - 2.0) < 0.001;
}

test "an orthographic depth goes through the same linearize, from near to far" {
	assert approx(lineViewDepth(0.0, NEAR, FAR), NEAR);
	assert approx(lineViewDepth(1.0, NEAR, FAR), FAR);
	const middle: float32 = 0.5;
	const depth: float32 = NEAR + (FAR - NEAR) * middle;
	assert approx(lineViewDepth(middle, NEAR, FAR), NEAR * FAR / (FAR + NEAR - depth));
}

test "the line block carries lineStyle's width, the target's pixel size and the depth range" {
	let graphics: Graphics3D = Graphics3D.create();
	assert lineStyle(graphics, 4.0, 0xffffff, 1.0).ok;
	const view: CameraView = resolved(perspective(), 320, 180);
	let out: Vec<float32> = new Array(LINE_UNIFORM_LENGTH);
	writeLineBlock(graphics, perspective(), view, { red: 0.5, green: 0.25, blue: 1.0, alpha: 0.75 },
		out);
	assert out[LINE_WIDTH] == 4.0 && out[LINE_LENGTH_SCALE] == 1.0;
	assert approx(out[LINE_PIXEL_SIZE], 2.0 / 320.0);
	assert approx(out[LINE_PIXEL_SIZE + 1], 2.0 / 180.0);
	assert out[LINE_NEAR] == NEAR && out[LINE_FAR] == FAR;
	assert out[LINE_COLOR] == 0.5 && out[LINE_COLOR + 1] == 0.25;
	assert out[LINE_COLOR + 2] == 1.0 && out[LINE_COLOR + 3] == 0.75;
	assert out[LINE_FAR + 1] == 0.0 && out[LINE_FAR + 2] == 0.0;
}
