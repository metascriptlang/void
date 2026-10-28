// The geometry the simulation asks of the particle world: swept hits against planes and
// analytic colliders, trigger overlap, and the push of a force field (docs/PARTICLES-SIM.md §3,
// §5.5). Pure functions of their inputs; the system owns the columns they update.

import { Vec3, vec3 } from "../math/math3d";
import { CollisionPlane, ParticleCollider, ColliderShape, ForceField, ForceFieldShape } from "./asset";

export struct Hit {
	hit: boolean;
	// Fraction of the step's displacement before contact, in [0, 1].
	fraction: float32;
	normal: Vec3;
	collider: int32;
}

export const MISS: Hit = { hit: false, fraction: 1.0, normal: { x: 0.0, y: 1.0, z: 0.0 }, collider: -1 };

function absVec(v: Vec3): Vec3 {
	return vec3(v.x < 0.0 ? -v.x : v.x, v.y < 0.0 ? -v.y : v.y, v.z < 0.0 ? -v.z : v.z);
}

function maxf(a: float32, b: float32): float32 {
	return a > b ? a : b;
}

function minf(a: float32, b: float32): float32 {
	return a < b ? a : b;
}

// Signed distance from `p` to the collider's surface: negative inside.
export function distanceTo(this c: ParticleCollider, p: Vec3): float32 {
	return match (c.shape) {
		ColliderShape.Sphere => (p - c.center).length() - c.radius,
		ColliderShape.Box => {
			const q: Vec3 = absVec(p - c.center) - c.extents;
			const outside: Vec3 = vec3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0));
			return outside.length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0);
		},
		ColliderShape.Capsule => {
			const axis: Vec3 = c.end - c.center;
			const lengthSquared: float32 = axis.lengthSquared();
			let t: float32 = lengthSquared > 0.0 ? (p - c.center).dot(axis) / lengthSquared : 0.0;
			if (t < 0.0) { t = 0.0; }
			if (t > 1.0) { t = 1.0; }
			return (p - (c.center + axis.scaled(t))).length() - c.radius;
		},
	};
}

// The outward surface normal at `p`, from the distance field's central differences.
function normalAt(c: ParticleCollider, p: Vec3): Vec3 {
	const e: float32 = 0.0005;
	const n: Vec3 = vec3(
		c.distanceTo(p + vec3(e, 0.0, 0.0)) - c.distanceTo(p - vec3(e, 0.0, 0.0)),
		c.distanceTo(p + vec3(0.0, e, 0.0)) - c.distanceTo(p - vec3(0.0, e, 0.0)),
		c.distanceTo(p + vec3(0.0, 0.0, e)) - c.distanceTo(p - vec3(0.0, 0.0, e)),
	);
	return n.normalized();
}

// The first contact of a sphere of `radius` moving from `p0` by `d` with the planes and
// colliders; a particle already behind a surface passes through it, as Unity's one-sided planes.
export function sweep(
	p0: Vec3, d: Vec3, radius: float32, planes: Readonly<Span<CollisionPlane>>,
	colliders: Readonly<Span<ParticleCollider>>, mask: uint32,
): Hit {
	let best: Hit = MISS;
	for (let k = 0; k < (planes.length as int32); k++) {
		const plane: CollisionPlane = planes[k];
		const s0: float32 = (p0 - plane.point).dot(plane.normal) - radius;
		const s1: float32 = (p0 + d - plane.point).dot(plane.normal) - radius;
		if (s0 >= 0.0 && s1 < 0.0) {
			const f: float32 = s0 / (s0 - s1);
			if (f < best.fraction || !best.hit) {
				best = { hit: true, fraction: f, normal: plane.normal, collider: k };
			}
		}
	}
	for (let k = 0; k < (colliders.length as int32); k++) {
		const c: ParticleCollider = colliders[k];
		if ((mask & ((1 as uint32) << (c.layer as uint32))) == 0) { continue; }
		const s0: float32 = c.distanceTo(p0) - radius;
		const s1: float32 = c.distanceTo(p0 + d) - radius;
		if (!(s0 >= 0.0 && s1 < 0.0)) { continue; }
		// The crossing by bisection: the distance field is not linear along the path.
		let lo: float32 = 0.0;
		let hi: float32 = 1.0;
		for (let it = 0; it < 12; it++) {
			const mid: float32 = (lo + hi) * 0.5;
			if (c.distanceTo(p0 + d.scaled(mid)) - radius >= 0.0) { lo = mid; } else { hi = mid; }
		}
		if (lo < best.fraction || !best.hit) {
			best = { hit: true, fraction: lo, normal: normalAt(c, p0 + d.scaled(lo)), collider: planes.length as int32 + k };
		}
	}
	return best;
}

// Which trigger colliders a sphere of `radius` at `p` overlaps, one bit per collider.
export function overlaps(p: Vec3, radius: float32, colliders: Readonly<Span<ParticleCollider>>): uint32 {
	let inside: uint32 = 0;
	for (let k = 0; k < (colliders.length as int32); k++) {
		if (colliders[k].distanceTo(p) < radius) { inside = inside | ((1 as uint32) << (k as uint32)); }
	}
	return inside;
}

export struct FieldPush {
	acceleration: Vec3;
	// Speed lost to the field's drag per second.
	drag: float32;
}

// A force field's push on a particle at `p`: its direction, gravity toward (or past the focus,
// away from) its centre, and drag, all fading linearly from startRange to endRange. The fade and
// focus forms are Unity's described intent (docs/PARTICLES-SIM.md §5.5, not yet captured).
export function fieldPush(field: ForceField, p: Vec3, speed: float32, size: float32): FieldPush {
	const none: FieldPush = { acceleration: vec3(0.0, 0.0, 0.0), drag: 0.0 };
	const lp: Vec3 = p - field.position;
	const d: float32 = match (field.shape) {
		ForceFieldShape.Sphere => lp.length(),
		ForceFieldShape.Hemisphere => lp.y < 0.0 ? field.endRange + 1.0 : lp.length(),
		ForceFieldShape.Cylinder => {
			const half: float32 = field.length * 0.5;
			(lp.y > half || lp.y < -half) ? field.endRange + 1.0 : vec3(lp.x, 0.0, lp.z).length()
		},
		ForceFieldShape.Box => {
			const a: Vec3 = absVec(lp);
			maxf(a.x, maxf(a.y, a.z))
		},
	};
	if (d > field.endRange) { return none; }
	const span: float32 = field.endRange - field.startRange;
	const weight: float32 = d <= field.startRange || !(span > 0.0) ? 1.0 : 1.0 - (d - field.startRange) / span;
	const focus: float32 = field.endRange * field.gravityFocus;
	const toward: Vec3 = lp.normalized().scaled(d >= focus ? -1.0 : 1.0);
	const acceleration: Vec3 = (field.direction + toward.scaled(field.gravity)).scaled(weight);
	let drag: float32 = field.drag * weight;
	if (field.multiplyDragByParticleSize) { drag = drag * size * size; }
	if (field.multiplyDragByParticleVelocity) { drag = drag * speed * speed; }
	return { acceleration: acceleration, drag: drag };
}
