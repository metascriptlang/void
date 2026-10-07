import {
	Vec3, Quat, Mat4, vec3, eulerQuat, transformDirection, composeTransform,
} from "../math/math3d";
import { Camera3D, CameraBasis, CameraError, ProjectionKind } from "../void3d/camera";
import {
	Anchor, ANCHOR_CENTER, ANCHOR_BOTTOM_CENTER, ANCHOR_TOP_RIGHT,
} from "../void3d/billboard";
import { MeshData, MeshError, LIT_TEXTURED_VERTEX_STRIDE } from "../void3d/meshData";
import {
	LabelUv, facingRotation, labelQuad, localFor, grown, uvOfSubRect,
} from "../void3d/worldLabel";
import { approx } from "./helpers";

function near(a: Vec3, b: Vec3): boolean {
	return approx(a.x, b.x) && approx(a.y, b.y) && approx(a.z, b.z);
}

function cameraAt(yaw: float32, pitch: float32): Camera3D {
	return {
		position: vec3(0.0, 0.0, 0.0), yaw: yaw, pitch: pitch, orientation: null,
		nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false,
		},
	};
}

function turnsQuadToCamera(basis: CameraBasis): boolean {
	const turn: Quat = facingRotation(basis);
	const matrix: Mat4 = turn.toMatrix();
	return near(transformDirection(vec3(1.0, 0.0, 0.0), matrix), basis.right) &&
		near(transformDirection(vec3(0.0, 1.0, 0.0), matrix), basis.up) &&
		near(transformDirection(vec3(0.0, 0.0, 1.0), matrix), basis.forward.scaled(-1.0));
}

function quadOf(anchor: Anchor, flipV: boolean): MeshData {
	const made: Result<MeshData, MeshError> = labelQuad(anchor, flipV);
	if (made.ok) { return made.value; }
	unreachable;
}

function cornerOf(data: MeshData, corner: int32): Vec3 {
	const at: int32 = corner * LIT_TEXTURED_VERTEX_STRIDE;
	return vec3(data.vertices[at], data.vertices[at + 1], data.vertices[at + 2]);
}

function uOf(data: MeshData, corner: int32): float32 {
	return data.vertices[corner * LIT_TEXTURED_VERTEX_STRIDE + 6];
}

function vOf(data: MeshData, corner: int32): float32 {
	return data.vertices[corner * LIT_TEXTURED_VERTEX_STRIDE + 7];
}

test "a label's quad turns its x to the camera's right, y to its up, z toward the eye" {
	assert turnsQuadToCamera(cameraAt(0.0, 0.0).basisOf());
	assert turnsQuadToCamera(cameraAt(0.785398, 0.6).basisOf());
	assert turnsQuadToCamera(cameraAt(-2.4, -0.9).basisOf());
	assert turnsQuadToCamera(cameraAt(3.0, 1.2).basisOf());
}

test "a camera node's own rotation is the rotation that faces it" {
	const pose: Quat = eulerQuat(0.3, -0.7, 1.1);
	const placed: Result<Camera3D, CameraError> =
		Camera3D.fromWorld(pose.toMatrix(), cameraAt(0.0, 0.0));
	if (!placed.ok) { unreachable; }
	const faced: Mat4 = facingRotation(placed.value.basisOf()).toMatrix();
	const own: Mat4 = pose.toMatrix();
	assert approx(faced.m11, own.m11) && approx(faced.m12, own.m12) && approx(faced.m13, own.m13);
	assert approx(faced.m21, own.m21) && approx(faced.m22, own.m22) && approx(faced.m23, own.m23);
	assert approx(faced.m31, own.m31) && approx(faced.m32, own.m32) && approx(faced.m33, own.m33);
}

test "the quad is one unit across, centred on its anchor, face on" {
	const centred: MeshData = quadOf(ANCHOR_CENTER, false);
	assert centred.vertexCount() == 4 && centred.triangleCount() == 2;
	assert near(cornerOf(centred, 0), vec3(-0.5, -0.5, 0.0));
	assert near(cornerOf(centred, 2), vec3(0.5, 0.5, 0.0));
}

test "an anchor moves the quad so that its point sits at the node's origin" {
	const feet: MeshData = quadOf(ANCHOR_BOTTOM_CENTER, false);
	assert near(cornerOf(feet, 0), vec3(-0.5, 0.0, 0.0));
	assert near(cornerOf(feet, 2), vec3(0.5, 1.0, 0.0));
	const corner: MeshData = quadOf(ANCHOR_TOP_RIGHT, false);
	assert near(cornerOf(corner, 0), vec3(-1.0, -1.0, 0.0));
	assert near(cornerOf(corner, 2), vec3(0.0, 0.0, 0.0));
}

test "the target's top row is v 0 where the origin is top left and v 1 where it is not" {
	const topLeft: MeshData = quadOf(ANCHOR_CENTER, false);
	assert vOf(topLeft, 0) == 1.0 && vOf(topLeft, 2) == 0.0;
	const bottomLeft: MeshData = quadOf(ANCHOR_CENTER, true);
	assert vOf(bottomLeft, 0) == 0.0 && vOf(bottomLeft, 2) == 1.0;
}

function sameMatrix(a: Mat4, b: Mat4): boolean {
	return approx(a.m11, b.m11) && approx(a.m12, b.m12) && approx(a.m13, b.m13) &&
		approx(a.m21, b.m21) && approx(a.m22, b.m22) && approx(a.m23, b.m23) &&
		approx(a.m31, b.m31) && approx(a.m32, b.m32) && approx(a.m33, b.m33) &&
		approx(a.m41, b.m41) && approx(a.m42, b.m42) && approx(a.m43, b.m43);
}

test "a world pose under a moved, turned, scaled parent comes back as its local pose" {
	const world: Mat4 = composeTransform(
		vec3(1.0, 2.0, -3.0), eulerQuat(0.4, -0.2, 0.9), vec3(2.0, 1.5, 1.0),
	);
	const parent: Mat4 = composeTransform(
		vec3(-4.0, 0.5, 2.0), eulerQuat(-0.3, 1.1, 0.2), vec3(2.0, 2.0, 2.0),
	);
	const local: Mat4 = composeTransform(
		localFor(world, parent).position, localFor(world, parent).rotation,
		localFor(world, parent).scale,
	);
	assert sameMatrix(local.multiplyAffine(parent), world);
}

test "a label's target only grows: a smaller text keeps the capacity, a larger one takes its own" {
	assert grown(40, 30) == 40;
	assert grown(40, 40) == 40;
	assert grown(40, 57) == 57;
}

test "the sub-rect's uv is the used share of the capacity, from the target's top left" {
	const whole: LabelUv = LabelUv.uvOfSubRect(40, 20, 40, 20, true);
	assert whole.scaleU == 1.0 && whole.scaleV == 1.0 && whole.offsetV == 0.0;
	const topLeft: LabelUv = LabelUv.uvOfSubRect(20, 10, 40, 40, true);
	assert topLeft.scaleU == 0.5 && topLeft.scaleV == 0.25 && topLeft.offsetV == 0.0;
	const bottomLeft: LabelUv = LabelUv.uvOfSubRect(20, 10, 40, 40, false);
	assert bottomLeft.scaleU == 0.5 && bottomLeft.scaleV == 0.25 && bottomLeft.offsetV == 0.75;
	const whole2: LabelUv = LabelUv.uvOfSubRect(40, 20, 40, 20, false);
	assert whole2.scaleV == 1.0 && whole2.offsetV == 0.0;
}

test "the moved quad shows the target's top rows and left columns and no others" {
	for (const topLeft of [true, false]) {
		const data: MeshData = quadOf(ANCHOR_CENTER, !topLeft);
		const uv: LabelUv = LabelUv.uvOfSubRect(20, 10, 40, 40, topLeft);
		const bottom: float32 = vOf(data, 0) * uv.scaleV + uv.offsetV;
		const top: float32 = vOf(data, 2) * uv.scaleV + uv.offsetV;
		const left: float32 = uOf(data, 0) * uv.scaleU;
		const right: float32 = uOf(data, 2) * uv.scaleU;
		assert left == 0.0 && right == 0.5;
		if (topLeft) {
			assert top == 0.0 && bottom == 0.25;
		} else {
			assert top == 1.0 && bottom == 0.75;
		}
	}
}
