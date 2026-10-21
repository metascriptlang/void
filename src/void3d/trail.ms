import { Mat4, Quat, Vec3, vec3, identityQuat, slerp, normalized } from "../math/math3d";
import { cross, transformDirection, toMatrix } from "../math/math3d";
import {
	MeshData, addTexturedVertex, addTriangle, hasRoomFor, MAX_MESH_VERTICES,
} from "./meshData";

export struct TrailSettings {
	duration: float64;
	angle: float32;
	sizeStart: float32;
	sizeEnd: float32;
	movementMin: float64;
	movementMax: float64;
	smoothness: float64;
}

export struct TrailPoint {
	x: float64;
	y: float64;
	z: float64;
	t: float64;
	size: float32;
	q: Quat;
}

export struct Trail {
	settings: TrailSettings;
	points: Vec<TrailPoint>;
	pending: TrailPoint;
}

export enum TrailError { Settings, Transform, Time, Capacity, Geometry }

export function defaults(this typeof TrailSettings): TrailSettings {
	return {
		duration: 0.5, angle: 0, sizeStart: 4, sizeEnd: 0,
		movementMin: 0.1, movementMax: 0.5, smoothness: 0.5,
	};
}

export function create(this typeof Trail, settings: TrailSettings): Result<Trail, TrailError> {
	if (!validSettings(settings)) { return Result.err(TrailError.Settings); }
	return Result.ok({
		settings: settings, points: [],
		pending: { x: 0, y: 0, z: 0, t: 0, size: 0, q: identityQuat() },
	});
}

function validSettings(s: TrailSettings): boolean {
	return Number.isFinite(s.duration) && s.duration > 0 &&
		Number.isFinite(s.movementMax) && s.movementMax > 0 &&
		Number.isFinite(s.movementMin) && Number.isFinite(s.smoothness) &&
		Number.isFinite(s.angle) && Number.isFinite(s.sizeStart) && Number.isFinite(s.sizeEnd);
}

function validPoint(p: TrailPoint): boolean {
	const norm: float64 = (p.q.x as float64) * p.q.x + (p.q.y as float64) * p.q.y +
		(p.q.z as float64) * p.q.z + (p.q.w as float64) * p.q.w;
	return Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z) &&
		Number.isFinite(p.t) && Number.isFinite(p.size) && Number.isFinite(norm) &&
		norm <= 3.4028234663852886e38;
}

function trailRotation(m: Mat4): Quat {
	const trace: float64 = (m.m11 as float64) + m.m22 + m.m33;
	if (trace > 0) {
		const s: float64 = Math.sqrt(trace + 1) * 2;
		return {
			x: (((m.m23 as float64) - m.m32) / s) as float32,
			y: (((m.m31 as float64) - m.m13) / s) as float32,
			z: (((m.m12 as float64) - m.m21) / s) as float32, w: (s * 0.25) as float32,
		};
	}
	if (m.m11 > m.m22 && m.m11 > m.m33) {
		const s: float64 = Math.sqrt(1 + (m.m11 as float64) - m.m22 - m.m33) * 2;
		return {
			x: (s * 0.25) as float32, y: (((m.m21 as float64) + m.m12) / s) as float32,
			z: (((m.m31 as float64) + m.m13) / s) as float32,
			w: (((m.m23 as float64) - m.m32) / s) as float32,
		};
	}
	if (m.m22 > m.m33) {
		const s: float64 = Math.sqrt(1 + (m.m22 as float64) - m.m11 - m.m33) * 2;
		return {
			x: (((m.m21 as float64) + m.m12) / s) as float32, y: (s * 0.25) as float32,
			z: (((m.m32 as float64) + m.m23) / s) as float32,
			w: (((m.m31 as float64) - m.m13) / s) as float32,
		};
	}
	const s: float64 = Math.sqrt(1 + (m.m33 as float64) - m.m11 - m.m22) * 2;
	return {
		x: (((m.m31 as float64) + m.m13) / s) as float32,
		y: (((m.m32 as float64) + m.m23) / s) as float32, z: (s * 0.25) as float32,
		w: (((m.m12 as float64) - m.m21) / s) as float32,
	};
}

function distanceSquared(a: TrailPoint, b: TrailPoint): float64 {
	const x: float64 = a.x - b.x;
	const y: float64 = a.y - b.y;
	const z: float64 = a.z - b.z;
	return x * x + y * y + z * z;
}

export function clearTrail(ref trail: Trail): void {
	if (trail.points.length > 0) { trail.points = []; }
}

export function sampleTrail(
	ref trail: Trail, world: Mat4, time: float64,
): Result<int32, TrailError> {
	if (!validSettings(trail.settings)) { return Result.err(TrailError.Settings); }
	if (!Number.isFinite(time)) { return Result.err(TrailError.Time); }
	const current: TrailPoint = {
		x: world.m41 as float64, y: world.m42 as float64, z: world.m43 as float64,
		t: time, size: 1, q: trailRotation(world),
	};
	if (!validPoint(current)) { return Result.err(TrailError.Transform); }
	if (trail.points.length > 2147483626) { return Result.err(TrailError.Capacity); }
	if (trail.points.length > 0 && !validPoint(trail.points[trail.points.length - 1])) {
		return Result.err(TrailError.Geometry);
	}
	if (trail.pending.size != 0 && trail.points.length == 0) { trail.pending.size = 0; }
	if (trail.pending.size != 0) {
		if (!validPoint(trail.pending)) { return Result.err(TrailError.Geometry); }
		const prev = trail.points[trail.points.length - 1];
		const pending = trail.pending;
		const d01: float64 = Math.sqrt(distanceSquared(pending, prev));
		const d12: float64 = Math.sqrt(distanceSquared(current, pending));
		const factor: float64 = trail.settings.smoothness * d01 / (d01 + d12);
		const cx: float64 = pending.x - factor * (current.x - prev.x);
		const cy: float64 = pending.y - factor * (current.y - prev.y);
		const cz: float64 = pending.z - factor * (current.z - prev.z);
		if (!Number.isFinite(cx) || !Number.isFinite(cy) || !Number.isFinite(cz)) {
			return Result.err(TrailError.Geometry);
		}
		const count: float64 = Math.ceil(d01 / trail.settings.movementMax);
		const splits: int32 = count > 20 ? 20 : count as int32;
		for (let i = 0; i < splits; i++) {
			const v: float64 = ((i + 1) as float64) / (splits as float64);
			const b0: float64 = (1 - v) * (1 - v);
			const b1: float64 = 2 * v * (1 - v);
			const b2: float64 = v * v;
			const point: TrailPoint = {
				x: prev.x * b0 + cx * b1 + pending.x * b2,
				y: prev.y * b0 + cy * b1 + pending.y * b2,
				z: prev.z * b0 + cz * b1 + pending.z * b2,
				t: prev.t + (pending.t - prev.t) * v, size: 1,
				q: prev.q.slerp(pending.q, v as float32).normalized(),
			};
			if (!validPoint(point)) { return Result.err(TrailError.Geometry); }
			trail.points.push(point);
		}
		trail.pending.size = 0;
	}
	const last: int32 = (trail.points.length as int32) - 1;
	const distance: float64 = last < 0 ? 0 : distanceSquared(trail.points[last], current);
	if (distance < trail.settings.movementMax * trail.settings.movementMax) {
		let point = current;
		const minimum: float64 = trail.settings.movementMin * trail.settings.movementMin;
		if (last >= 0 && trail.points[last].size == 0 && trail.points.length > 2 &&
			trail.points[last - 1].size == 0 && distance < minimum) {
			point.size = 0;
			trail.points[last] = point;
		} else {
			point.size = last < 0 || distance > minimum ? 1.0 : 0.0;
			trail.points.push(point);
		}
	} else {
		trail.pending = current;
	}
	const oldest: float64 = time - trail.settings.duration;
	let remove: int32 = 0;
	while (remove < trail.points.length && trail.points[remove].t < oldest &&
		(trail.points.length - remove > 1 || trail.pending.size != 0)) {
		remove++;
	}
	if (remove > 0) { trail.points.splice(0, remove); }
	return Result.ok(trail.points.length as int32);
}

export function buildTrailMesh(
	trail: Readonly<Trail>, time: float64,
): Result<MeshData, TrailError> {
	if (!validSettings(trail.settings)) { return Result.err(TrailError.Settings); }
	if (!Number.isFinite(time)) { return Result.err(TrailError.Time); }
	let mesh = MeshData.withUvs();
	if (trail.points.length <= 2) { return Result.ok(mesh); }
	const vertices: float64 = ((trail.points.length as float64) - 1) * 2;
	if (vertices > (MAX_MESH_VERTICES as float64) || !mesh.hasRoomFor(vertices as int32)) {
		return Result.err(TrailError.Capacity);
	}
	const across: Vec3 = vec3(1, 0, 0);
	const up: Vec3 = vec3(0, Math.cos(trail.settings.angle) as float32,
		Math.sin(trail.settings.angle) as float32);
	const localLeft: Vec3 = across.cross(up);
	for (let i = 1; i < trail.points.length; i++) {
		const p = trail.points[i - 1];
		if (!validPoint(p) || !validPoint(trail.points[i])) {
			return Result.err(TrailError.Geometry);
		}
		const left: Vec3 = localLeft.transformDirection(p.q.toMatrix());
		const normal: Vec3 = across.cross(left);
		const age: float64 = (time - p.t) / trail.settings.duration;
		const width: float64 = ((trail.settings.sizeStart as float64) +
			((trail.settings.sizeEnd as float64) - trail.settings.sizeStart) * age) *
			0.5 * trail.points[i].size;
		for (let side = 0; side < 2; side++) {
			const sign: float64 = side == 0 ? -1.0 : 1.0;
			const point: Vec3 = vec3((p.x + left.x * width * sign) as float32,
				(p.y + left.y * width * sign) as float32,
				(p.z + left.z * width * sign) as float32);
			const u: float32 = age as float32;
			if (!Number.isFinite(point.x) || !Number.isFinite(point.y) ||
				!Number.isFinite(point.z) || !Number.isFinite(normal.x) ||
				!Number.isFinite(normal.y) || !Number.isFinite(normal.z) || !Number.isFinite(u)) {
				return Result.err(TrailError.Geometry);
			}
			const added = addTexturedVertex(mesh, point, normal, { u: u, v: side as float32 },
				{ red: 1, green: 1, blue: 1, alpha: 1 });
			if (!added.ok) { return Result.err(TrailError.Capacity); }
		}
	}
	for (let i = 0; i < trail.points.length - 2; i++) {
		const p: int32 = (i as int32) * 2;
		if (!addTriangle(mesh, p, p + 2, p + 1).ok ||
			!addTriangle(mesh, p + 2, p + 3, p + 1).ok) {
			return Result.err(TrailError.Capacity);
		}
	}
	return Result.ok(mesh);
}
