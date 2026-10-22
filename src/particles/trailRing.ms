// The Trails module's points in PerParticle mode: per particle slot a ring of `perSlot` points,
// each its position, the particle's age when recorded and the distance travelled to it
// (docs/PARTICLES-RENDER.md §A.8: a fixed history per particle, no per-frame allocation).
// A trail whose particle died, when it outlives it, moves to the orphans and drains there.

import { Vec3, vec3 } from "../math/math3d";
import { ParticleColor } from "./curve";

export const TRAIL_POINT_FLOATS: int32 = 5;
const AT_X: int32 = 0;
const AT_Y: int32 = 1;
const AT_Z: int32 = 2;
const AT_AGE: int32 = 3;
const AT_DIST: int32 = 4;

export struct TrailRings {
	perSlot: int32;
	points: Vec<float32>;
	head: Vec<int32>;
	count: Vec<int32>;
	orphans: Vec<OrphanTrail>;
}

// A dead particle's trail: its points oldest first, with the particle's last look, aging on.
export struct OrphanTrail {
	points: Vec<float32>;
	count: int32;
	// Seconds since the particle's birth: the clock its points' ages are measured against.
	age: float32;
	seconds: float32;
	color: ParticleColor;
	size: float32;
	lifetime: float32;
	seed: uint32;
}

export function create(this typeof TrailRings, capacity: int32, perSlot: int32): TrailRings {
	let points: Vec<float32> = new Array(capacity * perSlot * TRAIL_POINT_FLOATS);
	let head: Vec<int32> = new Array(capacity);
	let count: Vec<int32> = new Array(capacity);
	for (let i = 0; i < capacity; i++) {
		head[i] = 0;
		count[i] = 0;
	}
	return { perSlot: perSlot, points: points, head: head, count: count, orphans: [] };
}

function at(r: TrailRings, slot: int32, k: int32): int32 {
	return (slot * r.perSlot + (r.head[slot] + k) % r.perSlot) * TRAIL_POINT_FLOATS;
}

export function clearSlot(this ref r: TrailRings, slot: int32): void {
	r.head[slot] = 0;
	r.count[slot] = 0;
}

export function pointCount(this r: TrailRings, slot: int32): int32 {
	return r.count[slot];
}

// The k-th point of a slot's trail, oldest first.
export function pointOf(this r: TrailRings, slot: int32, k: int32): Vec3 {
	const p: int32 = at(r, slot, k);
	return vec3(r.points[p + AT_X], r.points[p + AT_Y], r.points[p + AT_Z]);
}

export function ageOf(this r: TrailRings, slot: int32, k: int32): float32 {
	return r.points[at(r, slot, k) + AT_AGE];
}

export function distanceOf(this r: TrailRings, slot: int32, k: int32): float32 {
	return r.points[at(r, slot, k) + AT_DIST];
}

// Drops the points older than `seconds` at particle age `age`, then records `p` when it lies at
// least `minDistance` from the newest point. A full ring drops its oldest point.
export function record(this ref r: TrailRings, slot: int32, p: Vec3, age: float32, seconds: float32, minDistance: float32): void {
	while (r.count[slot] > 0 && age - r.ageOf(slot, 0) > seconds) {
		r.head[slot] = (r.head[slot] + 1) % r.perSlot;
		r.count[slot] = r.count[slot] - 1;
	}
	let travelled: float32 = 0.0;
	if (r.count[slot] > 0) {
		const last: Vec3 = r.pointOf(slot, r.count[slot] - 1);
		const step: float32 = (p - last).length();
		if (step < minDistance) { return; }
		travelled = r.distanceOf(slot, r.count[slot] - 1) + step;
	}
	if (r.count[slot] == r.perSlot) {
		r.head[slot] = (r.head[slot] + 1) % r.perSlot;
		r.count[slot] = r.count[slot] - 1;
	}
	const q: int32 = at(r, slot, r.count[slot]);
	r.points[q + AT_X] = p.x;
	r.points[q + AT_Y] = p.y;
	r.points[q + AT_Z] = p.z;
	r.points[q + AT_AGE] = age;
	r.points[q + AT_DIST] = travelled;
	r.count[slot] = r.count[slot] + 1;
}

export function moveSlot(this ref r: TrailRings, from: int32, to: int32): void {
	const n: int32 = r.perSlot * TRAIL_POINT_FLOATS;
	for (let k = 0; k < n; k++) { r.points[to * n + k] = r.points[from * n + k]; }
	r.head[to] = r.head[from];
	r.count[to] = r.count[from];
}

// Moves a dying particle's trail to the orphans, oldest point first.
export function orphan(
	this ref r: TrailRings, slot: int32, age: float32, seconds: float32, color: ParticleColor, size: float32,
	lifetime: float32, seed: uint32,
): void {
	const n: int32 = r.count[slot];
	if (n == 0) { return; }
	let points: Vec<float32> = new Array(n * TRAIL_POINT_FLOATS);
	for (let k = 0; k < n; k++) {
		const p: int32 = at(r, slot, k);
		for (let f = 0; f < TRAIL_POINT_FLOATS; f++) { points[k * TRAIL_POINT_FLOATS + f] = r.points[p + f]; }
	}
	r.orphans.push({
		points: points, count: n, age: age, seconds: seconds, color: color, size: size, lifetime: lifetime, seed: seed,
	});
	r.clearSlot(slot);
}

// Ages the orphans by `dt` and drops the points, then the trails, that expired.
export function drainOrphans(this ref r: TrailRings, dt: float32): void {
	let kept: int32 = 0;
	for (let o = 0; o < (r.orphans.length as int32); o++) {
		let trail: OrphanTrail = r.orphans[o];
		trail.age = trail.age + dt;
		let first: int32 = 0;
		while (first < trail.count && trail.age - trail.points[first * TRAIL_POINT_FLOATS + AT_AGE] > trail.seconds) {
			first = first + 1;
		}
		if (first == trail.count) { continue; }
		if (first > 0) {
			const left: int32 = trail.count - first;
			for (let k = 0; k < left * TRAIL_POINT_FLOATS; k++) {
				trail.points[k] = trail.points[first * TRAIL_POINT_FLOATS + k];
			}
			trail.count = left;
		}
		r.orphans[kept] = trail;
		kept = kept + 1;
	}
	r.orphans.length = kept;
}
