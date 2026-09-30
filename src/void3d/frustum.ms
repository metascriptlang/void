import { Mat4, Vec3, Vec4, vec4 } from "../math/math3d";
import { Bounds3D } from "./bounds";

export struct Frustum3D {
	left: Vec4;
	right: Vec4;
	bottom: Vec4;
	top: Vec4;
	nearPlane: Vec4;
	farPlane: Vec4;
}

export function fromMatrix(this typeof Frustum3D, m: Mat4): Frustum3D {
	return {
		left: vec4(m.m14 + m.m11, m.m24 + m.m21, m.m34 + m.m31, m.m44 + m.m41),
		right: vec4(m.m14 - m.m11, m.m24 - m.m21, m.m34 - m.m31, m.m44 - m.m41),
		bottom: vec4(m.m14 + m.m12, m.m24 + m.m22, m.m34 + m.m32, m.m44 + m.m42),
		top: vec4(m.m14 - m.m12, m.m24 - m.m22, m.m34 - m.m32, m.m44 - m.m42),
		nearPlane: vec4(m.m13, m.m23, m.m33, m.m43),
		farPlane: vec4(m.m14 - m.m13, m.m24 - m.m23, m.m34 - m.m33, m.m44 - m.m43),
	};
}

function absolute(value: float32): float32 {
	return value < 0.0 ? -value : value;
}

function intersectsPlane(plane: Vec4, center: Vec3, half: Vec3, world: Mat4): boolean {
	let radius: float32 =
		absolute(plane.x * world.m11 + plane.y * world.m12 + plane.z * world.m13) * half.x +
		absolute(plane.x * world.m21 + plane.y * world.m22 + plane.z * world.m23) * half.y +
		absolute(plane.x * world.m31 + plane.y * world.m32 + plane.z * world.m33) * half.z;
	let distance: float32 = plane.x * center.x + plane.y * center.y + plane.z * center.z + plane.w;
	return distance + radius >= 0.0;
}

export function intersectsBounds(this frustum: Frustum3D, bounds: Bounds3D, world: Mat4): boolean {
	if (bounds.isEmpty()) { return true; }
	let center: Vec3 = bounds.center() * world;
	let half: Vec3 = (bounds.max - bounds.min).scaled(0.5);
	return intersectsPlane(frustum.left, center, half, world) &&
		intersectsPlane(frustum.right, center, half, world) &&
		intersectsPlane(frustum.bottom, center, half, world) &&
		intersectsPlane(frustum.top, center, half, world) &&
		intersectsPlane(frustum.nearPlane, center, half, world) &&
		intersectsPlane(frustum.farPlane, center, half, world);
}
