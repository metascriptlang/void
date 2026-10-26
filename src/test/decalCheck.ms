// Heaps' DecalOverlay fragment math on the CPU: a scene depth back through a real camera into the
// decal's box, the depth fade across the box and the overlay's color and alpha.

import { Vec3, Mat4, vec3, identity, scaling, translation } from "../math/math3d";
import { Mat4x4f, Vec3f, Vec4f, mat4x4f, vec2f, vec4f } from "../shader/std";
import { Camera3D, CameraError, CameraView, ProjectionKind } from "../void3d/camera";
import {
	decalFade, decalLocalAt, decalOverlayColor, ndcDepthOf, outsideDecal,
} from "../void3d/shader3d";
import { DecalOverlay, DecalError, DecalPass, decalBlock } from "../void3d/decal";
import { Material, Phase } from "../void3d/material";
import { Program } from "../void3d/gpu3d";
import { Compare, Face } from "../gpu/state";
import { approx } from "./helpers";

function asMat4x4f(m: Mat4): Mat4x4f {
	return mat4x4f(
		vec4f(m.m11, m.m12, m.m13, m.m14), vec4f(m.m21, m.m22, m.m23, m.m24),
		vec4f(m.m31, m.m32, m.m33, m.m34), vec4f(m.m41, m.m42, m.m43, m.m44),
	);
}

function nearVec3(actual: Vec3f, x: float32, y: float32, z: float32): boolean {
	return approx(actual.x, x) && approx(actual.y, y) && approx(actual.z, z);
}

function nearVec4(actual: Vec4f, x: float32, y: float32, z: float32, w: float32): boolean {
	return approx(actual.x, x) && approx(actual.y, y) && approx(actual.z, z) && approx(actual.w, w);
}

function cameraView(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 4.0, 4.0), yaw: 0.0, pitch: 0.785398,
		nearPlane: 0.1, farPlane: 20.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 0.8 },
	};
	const view: Result<CameraView, CameraError> = camera.resolve(320, 240);
	if (!view.ok) { unreachable; }
	return view.value;
}

// The decal's box: 2 x 1 x 2 world units centred on (0.5, 0, -0.25).
function boxToLocal(): Mat4x4f {
	const world: Mat4 = scaling(2.0, 1.0, 2.0) * translation(0.5, 0.0, -0.25);
	return asMat4x4f(world.inverse());
}

function localUnder(view: CameraView, p: Vec3): Vec3f {
	const m: Mat4 = view.viewProj;
	const x: float32 = p.x * m.m11 + p.y * m.m21 + p.z * m.m31 + m.m41;
	const y: float32 = p.x * m.m12 + p.y * m.m22 + p.z * m.m32 + m.m42;
	const z: float32 = p.x * m.m13 + p.y * m.m23 + p.z * m.m33 + m.m43;
	const w: float32 = p.x * m.m14 + p.y * m.m24 + p.z * m.m34 + m.m44;
	const screenToLocal: Mat4x4f = boxToLocal() * asMat4x4f(view.inverseViewProj);
	return decalLocalAt(vec2f(x / w, y / w), z / w, screenToLocal);
}

test "a depth under the identity camera lands in the box's local space" {
	const toLocal: Mat4x4f = boxToLocal() * asMat4x4f(identity());
	const inside: Vec3f = decalLocalAt(vec2f(1.0, 0.25), 0.5, toLocal);
	assert nearVec3(inside, 0.25, 0.25, 0.375) && !outsideDecal(inside);
	const beside: Vec3f = decalLocalAt(vec2f(1.7, 0.0), 0.0, toLocal);
	assert approx(beside.x, 0.6) && outsideDecal(beside);
}

test "a scene depth through a perspective camera returns the world point's place in the box" {
	const view: CameraView = cameraView();
	const ground: Vec3f = localUnder(view, vec3(1.0, 0.0, 0.25));
	assert nearVec3(ground, 0.25, 0.0, 0.25) && !outsideDecal(ground);
	const corner: Vec3f = localUnder(view, vec3(1.4, 0.4, -1.1));
	assert nearVec3(corner, 0.45, 0.4, -0.425) && !outsideDecal(corner);
	assert outsideDecal(localUnder(view, vec3(0.5, 0.6, -0.25)));
	assert outsideDecal(localUnder(view, vec3(0.5, 0.0, 0.8)));
}

test "the fade starts at fadeStart across the box's depth and follows fadePower" {
	assert decalFade(0.1, 0.5, 1.0, 1.0) == 1.0;
	assert approx(decalFade(0.25, 0.0, 1.0, 1.0), 0.5);
	assert approx(decalFade(-0.25, 0.0, 1.0, 2.0), 0.75);
	assert approx(decalFade(0.375, 0.5, 1.0, 1.0), 0.5);
	assert decalFade(0.5, 0.0, 1.0, 1.0) == 0.0;
}

test "the overlay multiplies the tint, squares under gamma, lifts by the emissive" {
	const tint: Vec4f = vec4f(0.5, 1.0, 1.0, 1.0);
	const texel: Vec4f = vec4f(0.5, 0.5, 0.25, 0.4);
	assert nearVec4(decalOverlayColor(tint, texel, 1.0, false, true, 0.5), 0.5, 1.0, 0.5, 0.5);
	assert nearVec4(decalOverlayColor(tint, texel, 1.0, false, false, 0.5), 0.5, 1.0, 0.5, 0.2);
	assert nearVec4(
		decalOverlayColor(tint, texel, 0.0, true, true, 1.0), 0.0625, 0.25, 0.0625, 0.25);
	assert nearVec4(decalOverlayColor(tint, texel, 3.0, false, true, 1.0), 1.0, 2.0, 1.0, 1.0);
}

test "a stored depth is NDC as is on a 0..1 backend and mapped from 0..1 to -1..1 otherwise" {
	assert ndcDepthOf(0.25, 1.0) == 0.25;
	assert ndcDepthOf(0.25, 0.0) == -0.5;
	assert ndcDepthOf(1.0, 0.0) == 1.0;
}

test "a decal's block holds DecalOverlay's defaults, and an empty fade range is refused" {
	const overlay: DecalOverlay = DecalOverlay.defaults();
	const block: Result<Vec<float32>, DecalError> = decalBlock(overlay, DecalPass.BeforeToneMap);
	if (!block.ok) { unreachable; }
	const expected: Vec<float32> = [1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0];
	assert block.value.length == expected.length;
	for (let i = 0; i < expected.length; i++) { assert block.value[i] == expected[i]; }
	const after: Result<Vec<float32>, DecalError> = decalBlock(overlay, DecalPass.AfterToneMap);
	assert after.ok && after.value[11] == 0.0;
	const empty: Result<Vec<float32>, DecalError> =
		decalBlock({ ...overlay, fadeEnd: 0.0 }, DecalPass.BeforeToneMap);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == DecalError.FadeRange; }
}

test "a decal material draws in its pass's phase with no depth and its back faces" {
	const before: Material = Material.decal(DecalPass.BeforeToneMap);
	assert before.program.program == Program.Decal && before.phase == Phase.Decal;
	assert !before.pass.depthWrite && before.pass.depthTest == Compare.Always;
	assert before.pass.culling == Face.Front;
	const after: Material = Material.decal(DecalPass.AfterToneMap);
	assert after.program.program == Program.Decal && after.phase == Phase.DecalAfterToneMap;
	assert after.pass.blendSource == before.pass.blendSource && after.pass.culling == Face.Front;
}
