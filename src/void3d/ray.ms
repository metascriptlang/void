// Port of h3d.col.Ray: an origin and a unit direction.

import { Vec3, Mat4 } from "../math/math3d";

export struct Ray {
	origin: Vec3;
	direction: Vec3;
}

export function fromPoints(this typeof Ray, from: Vec3, to: Vec3): Ray {
	return { origin: from, direction: (to - from).normalized() };
}

// h3d.col.Ray.transform: the origin as a point, the direction as a vector, renormalized.
export function transformed(this ray: Ray, matrix: Mat4): Ray {
	return {
		origin: ray.origin * matrix,
		direction: ray.direction.transformDirection(matrix).normalized(),
	};
}

export function pointAt(this ray: Ray, distance: float32): Vec3 {
	return ray.origin + ray.direction.scaled(distance);
}
