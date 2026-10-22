// Writes a particle system's live particles as Program.ParticleVisual instances, in the order
// its renderer sorts them (docs/PARTICLES.md, tier T0's CPU writer; the layout is gpu3d.c's
// ParticleVisual: position, width, height, anchor, clockwise rotation, uv rect, colour).

import { Vec3, vec3 } from "../math/math3d";
import { ParticleSortMode, RenderMode, RenderAlignment, SimulationSpace } from "../particles/asset";
import { unitDraw } from "../particles/curve";
import {
	ParticleSystem, POS_X, POS_Y, POS_Z, ROT_Z, SIZE_X, SIZE_Y, COLOR_R, COLOR_G, COLOR_B,
	COLOR_A, FRAME, AGE, DRAW_FLIP_U, DRAW_FLIP_V,
} from "../particles/system";
import { AtlasTile } from "./billboard";
import { PARTICLE_VISUAL_INSTANCE_STRIDE } from "./particles";

export enum ParticleWriteError {
	ShortInstances,
	// The frames do not cover the texture sheet: one tile per sheet frame, or one without a sheet.
	FrameCount,
	// The renderer asks for a mode or alignment the visual billboard program does not draw.
	UnsupportedRenderMode,
	NonFinite,
}

// Scratch for the sort, kept across frames so writing allocates only when the count grows.
export struct ParticleWriter3D {
	order: Vec<int32>;
	keys: Vec<float32>;
	scratch: Vec<int32>;
}

export function create(this typeof ParticleWriter3D): ParticleWriter3D {
	return { order: [], keys: [], scratch: [] };
}

// The frames of a texture sheet laid over `t`, left to right then top to bottom.
export function sheetTiles(t: AtlasTile, across: int32, down: int32): Vec<AtlasTile> {
	const du: float32 = (t.u2 - t.u) / (across as float32);
	const dv: float32 = (t.v2 - t.v) / (down as float32);
	let out: Vec<AtlasTile> = [];
	for (let row = 0; row < down; row++) {
		for (let col = 0; col < across; col++) {
			out.push({
				u: t.u + du * (col as float32), v: t.v + dv * (row as float32),
				u2: t.u + du * ((col + 1) as float32), v2: t.v + dv * ((row + 1) as float32),
			});
		}
	}
	return out;
}

function grow(ref w: ParticleWriter3D, count: int32): void {
	while ((w.order.length as int32) < count) {
		w.order.push(0);
		w.keys.push(0.0);
		w.scratch.push(0);
	}
}

// A stable merge sort of `order[0, count)` by ascending key, through `scratch`.
function sortOrder(ref w: ParticleWriter3D, count: int32): void {
	let width: int32 = 1;
	while (width < count) {
		let start: int32 = 0;
		while (start < count) {
			const middle: int32 = start + width < count ? start + width : count;
			const end: int32 = start + 2 * width < count ? start + 2 * width : count;
			let left: int32 = start;
			let right: int32 = middle;
			for (let at = start; at < end; at++) {
				const takeLeft: boolean = right >= end || (left < middle
					&& !(w.keys[w.order[right]] < w.keys[w.order[left]]));
				if (takeLeft) {
					w.scratch[at] = w.order[left];
					left = left + 1;
				} else {
					w.scratch[at] = w.order[right];
					right = right + 1;
				}
			}
			start = end;
		}
		for (let i = 0; i < count; i++) { w.order[i] = w.scratch[i]; }
		width = width * 2;
	}
}

function placed(sys: ParticleSystem, i: int32): Vec3 {
	const cap: int32 = sys.capacity;
	const p: Vec3 = vec3(sys.data[POS_X * cap + i], sys.data[POS_Y * cap + i], sys.data[POS_Z * cap + i]);
	return sys.asset.main.simulationSpace == SimulationSpace.Local ? p * sys.world : p;
}

// Writes `sys`'s particles into `out`, drawn first to last, seen from `eye` looking along
// `forward`. `frames` holds one tile per sheet frame. Returns the instance count.
export function writeParticles(
	ref w: ParticleWriter3D, sys: ParticleSystem, frames: Readonly<Span<AtlasTile>>, eye: Vec3, forward: Vec3,
	out: Span<float32>,
): Result<int32, ParticleWriteError> {
	const renderer = sys.asset.renderer;
	if (renderer.renderMode == RenderMode.None) { return Result.ok(0); }
	if (renderer.renderMode != RenderMode.Billboard || renderer.alignment != RenderAlignment.View) {
		return Result.err(ParticleWriteError.UnsupportedRenderMode);
	}
	const sheet = sys.asset.textureSheetAnimation;
	const wanted: int32 = sheet.enabled ? sheet.numTilesX * sheet.numTilesY : 1;
	if ((frames.length as int32) != wanted) { return Result.err(ParticleWriteError.FrameCount); }
	const count: int32 = sys.count;
	const stride: int32 = PARTICLE_VISUAL_INSTANCE_STRIDE;
	if (count > 2147483647 / stride || (out.length as int32) < count * stride) {
		return Result.err(ParticleWriteError.ShortInstances);
	}
	grow(w, count);
	const cap: int32 = sys.capacity;
	for (let i = 0; i < count; i++) { w.order[i] = i; }
	// Keys sort ascending, so whatever is drawn first gets the smallest key.
	const mode: ParticleSortMode = renderer.sortMode;
	if (mode != ParticleSortMode.None) {
		for (let i = 0; i < count; i++) {
			const p: Vec3 = placed(sys, i);
			const age: float32 = sys.data[AGE * cap + i];
			w.keys[i] = match (mode) {
				ParticleSortMode.None => 0.0,
				ParticleSortMode.Distance => -(p - eye).length(),
				ParticleSortMode.DistanceReverse => (p - eye).length(),
				ParticleSortMode.Depth => -(p - eye).dot(forward),
				ParticleSortMode.DepthReverse => (p - eye).dot(forward),
				ParticleSortMode.OldestInFront => age,
				ParticleSortMode.YoungestInFront => -age,
			};
		}
		sortOrder(w, count);
	}
	const flipU: float32 = sheet.enabled ? renderer.flip.x + sheet.flipU - renderer.flip.x * sheet.flipU : renderer.flip.x;
	const flipV: float32 = sheet.enabled ? renderer.flip.y + sheet.flipV - renderer.flip.y * sheet.flipV : renderer.flip.y;
	const last: int32 = wanted - 1;
	for (let k = 0; k < count; k++) {
		const i: int32 = w.order[k];
		const p: Vec3 = placed(sys, i);
		let frame: int32 = sheet.enabled ? sys.data[FRAME * cap + i] as int32 : 0;
		if (frame > last) { frame = last; }
		const t: AtlasTile = frames[frame];
		const seed: uint32 = sys.seeds[i];
		const mirrorU: boolean = unitDraw(seed, DRAW_FLIP_U) < flipU;
		const mirrorV: boolean = unitDraw(seed, DRAW_FLIP_V) < flipV;
		const at: int32 = k * stride;
		out[at] = p.x;
		out[at + 1] = p.y;
		out[at + 2] = p.z;
		out[at + 3] = sys.data[SIZE_X * cap + i];
		out[at + 4] = sys.data[SIZE_Y * cap + i];
		// Unity's pivot moves the quad by that many particle sizes; the anchor is the quad
		// point placed on the particle.
		out[at + 5] = -renderer.pivot.x;
		out[at + 6] = -renderer.pivot.y;
		out[at + 7] = sys.data[ROT_Z * cap + i];
		out[at + 8] = mirrorU ? t.u2 : t.u;
		out[at + 9] = mirrorV ? t.v2 : t.v;
		out[at + 10] = mirrorU ? t.u : t.u2;
		out[at + 11] = mirrorV ? t.v : t.v2;
		out[at + 12] = sys.data[COLOR_R * cap + i];
		out[at + 13] = sys.data[COLOR_G * cap + i];
		out[at + 14] = sys.data[COLOR_B * cap + i];
		out[at + 15] = sys.data[COLOR_A * cap + i];
		for (let c = 0; c < stride; c++) {
			if (!Number.isFinite(out[at + c])) { return Result.err(ParticleWriteError.NonFinite); }
		}
	}
	return Result.ok(count);
}
