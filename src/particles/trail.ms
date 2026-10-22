// The Trails module's output: each trail as a chain of vertices in the effect's world space,
// with width, colour and the texture coordinate along it. PerParticle chains run from the
// particle's oldest recorded point to the particle; Ribbon chains link the live particles in
// emission order. A chain is ready for any writer: 2D triangles, 3D segments.

import { Vec3, vec3, position } from "../math/math3d";
import { SimulationSpace, TrailMode, TrailTextureMode, RingBufferMode, TrailModule } from "./asset";
import { ParticleColor, rgbaColor, unitDraw } from "./curve";
import {
	ParticleSystem, POS_X, POS_Y, POS_Z, SIZE_X, COLOR_R, COLOR_G, COLOR_B, COLOR_A, AGE, LIFETIME,
	RIBBON, DRAW_TRAIL, hasTrail,
} from "./system";
import { TRAIL_POINT_FLOATS } from "./trailRing";

export struct TrailVertex {
	position: Vec3;
	width: float32;
	color: ParticleColor;
	// Along the trail, by the module's texture mode; 0 at the particle.
	u: float32;
}

// Chain c is vertices[starts[c], starts[c + 1]), the last chain ends at vertices.length.
export struct TrailChains {
	vertices: Vec<TrailVertex>;
	starts: Vec<int32>;
	// Scratch, per vertex of the chain being built: its distance from the chain's far end.
	distances: Vec<float32>;
}

export function create(this typeof TrailChains): TrailChains {
	return { vertices: [], starts: [], distances: [] };
}

export function chainCount(this c: TrailChains): int32 {
	return c.starts.length as int32;
}

export function chainEnd(this c: TrailChains, chain: int32): int32 {
	return chain + 1 < (c.starts.length as int32) ? c.starts[chain + 1] : c.vertices.length as int32;
}

function get(sys: ParticleSystem, column: int32, i: int32): float32 {
	return sys.data[column * sys.capacity + i];
}

function colorOf(sys: ParticleSystem, i: int32): ParticleColor {
	return rgbaColor(get(sys, COLOR_R, i), get(sys, COLOR_G, i), get(sys, COLOR_B, i), get(sys, COLOR_A, i));
}

function times(a: ParticleColor, b: ParticleColor): ParticleColor {
	return { r: a.r * b.r, g: a.g * b.g, b: a.b * b.b, a: a.a * b.a };
}

// Recorded points live in simulation space, or in world space when a local system's trails ask.
function pointsInWorld(sys: ParticleSystem): boolean {
	return sys.asset.main.simulationSpace == SimulationSpace.World || sys.asset.trails.worldSpace;
}

function toWorld(sys: ParticleSystem, p: Vec3, inWorld: boolean): Vec3 {
	return inWorld ? p : p * sys.world;
}

// Writes every trail of `sys` into `out`, replacing what it held.
export function buildTrails(sys: ParticleSystem, ref out: TrailChains): void {
	out.vertices.length = 0;
	out.starts.length = 0;
	const t: Borrow<TrailModule> = sys.asset.trails;
	if (!t.enabled) { return; }
	if (t.mode == TrailMode.Ribbon) {
		buildRibbons(sys, out);
		return;
	}
	const inWorld: boolean = pointsInWorld(sys);
	const particleWorld: boolean = sys.asset.main.simulationSpace == SimulationSpace.World;
	for (let i = 0; i < sys.count; i++) {
		const n: int32 = sys.trails.pointCount(i);
		if (n == 0 || !hasTrail(sys, i)) { continue; }
		const start: int32 = out.vertices.length as int32;
		out.starts.push(start);
		const head: Vec3 = vec3(get(sys, POS_X, i), get(sys, POS_Y, i), get(sys, POS_Z, i));
		const headWorld: Vec3 = particleWorld ? head : head * sys.world;
		const tN: float32 = get(sys, AGE, i) / get(sys, LIFETIME, i);
		const look: ParticleColor = trailTint(sys, colorOf(sys, i), tN);
		const size: float32 = get(sys, SIZE_X, i);
		// Newest first: the particle, then its points back to the oldest. A point recorded this
		// step sits on the particle and is left out.
		pushVertex(out, headWorld, size, look);
		const newestPoint: Vec3 = toWorld(sys, sys.trails.pointOf(i, n - 1), inWorld);
		const gap: float32 = (headWorld - newestPoint).length();
		const from: int32 = gap > 0.0 ? n - 1 : n - 2;
		for (let k = from; k >= 0; k--) {
			pushVertex(out, toWorld(sys, sys.trails.pointOf(i, k), inWorld), size, look);
		}
		if ((out.vertices.length as int32) - start < 2) {
			out.vertices.length = start;
			out.starts.length = out.starts.length - 1;
			continue;
		}
		finishChain(sys, out, start, sys.seeds[i], sys.trails.distanceOf(i, n - 1) + gap);
	}
	for (const o of sys.trails.orphans) {
		const start: int32 = out.vertices.length as int32;
		out.starts.push(start);
		const tN: float32 = o.lifetime > 0.0 ? o.age / o.lifetime : 1.0;
		const look: ParticleColor = trailTint(sys, o.color, tN > 1.0 ? 1.0 : tN);
		for (let k = o.count - 1; k >= 0; k--) {
			const at: int32 = k * TRAIL_POINT_FLOATS;
			pushVertex(out, toWorld(sys, vec3(o.points[at], o.points[at + 1], o.points[at + 2]), inWorld), o.size, look);
		}
		finishChain(sys, out, start, o.seed, o.points[(o.count - 1) * TRAIL_POINT_FLOATS + 4]);
	}
}

function trailTint(sys: ParticleSystem, particle: ParticleColor, tN: float32): ParticleColor {
	const t: Borrow<TrailModule> = sys.asset.trails;
	const base: ParticleColor = t.inheritParticleColor ? particle : rgbaColor(1.0, 1.0, 1.0, 1.0);
	return times(base, t.colorOverLifetime.evaluate(tN, 0.0));
}

function pushVertex(ref out: TrailChains, p: Vec3, size: float32, color: ParticleColor): void {
	out.vertices.push({ position: p, width: size, color: color, u: 0.0 });
}

// Sets the chain's widths, colours over the trail and texture coordinates once its vertices,
// newest first, are in. `travelled` is the distance from the trail's birth to its newest vertex.
function finishChain(sys: ParticleSystem, ref out: TrailChains, start: int32, seed: uint32, travelled: float32): void {
	const t: Borrow<TrailModule> = sys.asset.trails;
	const end: int32 = out.vertices.length as int32;
	const n: int32 = end - start;
	out.distances.length = 0;
	let along: float32 = 0.0;
	out.distances.push(0.0);
	for (let k = start + 1; k < end; k++) {
		along = along + (out.vertices[k].position - out.vertices[k - 1].position).length();
		out.distances.push(along);
	}
	const total: float32 = along;
	const r: float32 = unitDraw(seed, DRAW_TRAIL + 2);
	for (let k = 0; k < n; k++) {
		const s: float32 = out.distances[k];
		const share: float32 = total > 0.0 ? s / total : 0.0;
		let v: TrailVertex = out.vertices[start + k];
		const width: float32 = sys.curves.trailWidth.evaluate(share, r);
		v.width = t.sizeAffectsWidth ? width * v.width : width;
		v.color = times(v.color, t.colorOverTrail.evaluate(share, r));
		v.u = match (t.textureMode) {
			TrailTextureMode.Stretch => share,
			TrailTextureMode.Tile => s * t.textureScale.x,
			TrailTextureMode.DistributePerSegment => n > 1 ? (k as float32) / ((n - 1) as float32) : 0.0,
			TrailTextureMode.RepeatPerSegment => k as float32,
			TrailTextureMode.Static => (travelled - s) * t.textureScale.x,
		};
		out.vertices[start + k] = v;
	}
}

// The slot of the k-th newest particle. Slots keep emission order, except that a full ring
// buffer overwrites its oldest slot, so its newest sits just before `ringIndex`.
function newest(sys: ParticleSystem, k: int32): int32 {
	const ring: boolean = sys.asset.main.ringBufferMode != RingBufferMode.Disabled && sys.count == sys.capacity;
	const top: int32 = ring ? sys.ringIndex - 1 : sys.count - 1;
	return (top - k + sys.count) % sys.count;
}

// Ribbon mode: the live particles in emission order, `ribbonCount` chains taking turns, newest
// first; the emitter closes each chain when ribbons attach to the transform.
function buildRibbons(sys: ParticleSystem, ref out: TrailChains): void {
	const t: Borrow<TrailModule> = sys.asset.trails;
	const ribbons: int32 = t.ribbonCount > 0 ? t.ribbonCount : 1;
	const particleWorld: boolean = sys.asset.main.simulationSpace == SimulationSpace.World;
	const emitter: Vec3 = particleWorld ? sys.world.position() : vec3(0.0, 0.0, 0.0);
	for (let chain = 0; chain < ribbons; chain++) {
		const start: int32 = out.vertices.length as int32;
		if (t.attachRibbonsToTransform) {
			pushVertex(out, particleWorld ? emitter : emitter * sys.world, 0.0, rgbaColor(1.0, 1.0, 1.0, 1.0));
		}
		for (let k = 0; k < sys.count; k++) {
			const i: int32 = newest(sys, k);
			if ((get(sys, RIBBON, i) as int32) != chain) { continue; }
			const p: Vec3 = vec3(get(sys, POS_X, i), get(sys, POS_Y, i), get(sys, POS_Z, i));
			const tN: float32 = get(sys, AGE, i) / get(sys, LIFETIME, i);
			pushVertex(out, particleWorld ? p : p * sys.world, get(sys, SIZE_X, i), trailTint(sys, colorOf(sys, i), tN));
		}
		if (t.attachRibbonsToTransform && (out.vertices.length as int32) > start + 1) {
			let first: TrailVertex = out.vertices[start];
			first.width = out.vertices[start + 1].width;
			first.color = out.vertices[start + 1].color;
			out.vertices[start] = first;
		}
		if ((out.vertices.length as int32) - start < 2) {
			out.vertices.length = start;
			continue;
		}
		out.starts.push(start);
		finishChain(sys, out, start, (chain as uint32) + 1, 0.0);
	}
}
