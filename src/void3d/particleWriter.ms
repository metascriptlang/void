// Writes a particle system's live particles as Program.ParticleVisual instances, in the order its
// renderer sorts them (docs/PARTICLES.md, tier T0's CPU writer; the layout is vertexLayouts.ms's
// ParticleVisual: position, width, height, anchor, clockwise rotation, uv rect, colour, world
// velocity, then the system's render mode, which shader3d.ms particleVisualPoint reads).
// Trails write the same instances, one view-facing quad per trail segment.

import { Vec3, vec3, transformDirection } from "../math/math3d";
import {
	ParticleSortMode, RenderMode, RenderAlignment, SimulationSpace, RendererModule,
	TextureSheetAnimationModule,
} from "../particles/asset";
import { unitDraw } from "../particles/curve";
import { TrailChains, TrailVertex } from "../particles/trail";
import {
	ParticleSystem, POS_X, POS_Y, POS_Z, ROT_Z, SIZE_X, SIZE_Y, COLOR_R, COLOR_G, COLOR_B,
	COLOR_A, FRAME, AGE, DRAW_FLIP_U, DRAW_FLIP_V, MOVE_X, MOVE_Y, MOVE_Z,
} from "../particles/system";
import { AtlasTile } from "./billboard";
import { sortKeyOf } from "./sortKey.h";

// Floats per instance of the Particle layout (position, size, rgba) and of ParticleVisual
// (position, width, height, anchor, rotation, uv rect, rgba, velocity, look, scale, pull and the
// emitter's right and up). The render mode is the same for every particle of a system; it rides
// each instance because a material's one uniform block is the fragment stage's, and the vertex
// stage has no block of its own to read it from (docs/PARTICLES-RENDER.md A.2).
export const PARTICLE_INSTANCE_STRIDE: int32 = 8;
export const PARTICLE_VISUAL_INSTANCE_STRIDE: int32 = 36;
// A mesh instance: three rows of the world-space 3x4 affine, then rgba (particleMeshWriter.ms).
export const PARTICLE_MESH_INSTANCE_STRIDE: int32 = 16;

const RADIX_BITS: int32 = 11;
const RADIX_BUCKETS: int32 = 2048;

export enum ParticleWriteError {
	ShortInstances,
	// The frames do not cover the texture sheet: one tile per sheet frame, or one without a sheet.
	FrameCount,
	// The renderer asks for a mode the program does not draw: Mesh, or anything but a view
	// billboard for the point program.
	UnsupportedRenderMode,
	NonFinite,
}

// Scratch for the sort, kept across frames so writing allocates only when the count grows.
export struct ParticleWriter3D {
	order: Vec<int32>;
	keys: Vec<float32>;
	scratch: Vec<int32>;
	bits: Vec<uint32>;
	bitsScratch: Vec<uint32>;
	buckets: Vec<int32>;
}

export function create(this typeof ParticleWriter3D): ParticleWriter3D {
	return { order: [], keys: [], scratch: [], bits: [], bitsScratch: [], buckets: [] };
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
		w.bits.push(0);
		w.bitsScratch.push(0);
	}
	while ((w.buckets.length as int32) < RADIX_BUCKETS) { w.buckets.push(0); }
}

// One radix pass: `fromKeys`/`fromSlots` scattered stably by the digit at `shift` into
// `toKeys`/`toSlots`.
function scatter(
	fromKeys: Span<uint32>, fromSlots: Span<int32>, toKeys: Span<uint32>, toSlots: Span<int32>,
	buckets: Span<int32>, count: int32, shift: uint32,
): void {
	for (let d = 0; d < RADIX_BUCKETS; d++) { buckets[d] = 0; }
	for (let i = 0; i < count; i++) {
		const d: int32 = ((fromKeys[i] >> shift) & 2047) as int32;
		buckets[d] = buckets[d] + 1;
	}
	let start: int32 = 0;
	for (let d = 0; d < RADIX_BUCKETS; d++) {
		const n: int32 = buckets[d];
		buckets[d] = start;
		start = start + n;
	}
	for (let i = 0; i < count; i++) {
		const key: uint32 = fromKeys[i];
		const d: int32 = ((key >> shift) & 2047) as int32;
		const at: int32 = buckets[d];
		buckets[d] = at + 1;
		toKeys[at] = key;
		toSlots[at] = fromSlots[i];
	}
}

// Sorts `order[0, count)`, slot i keyed by `keys[i]`, ascending and stable: an LSD radix sort
// of the keys' bits in 11-bit digits (docs/PARTICLES-RUNTIME.md §3, sorting).
function sortOrder(ref w: ParticleWriter3D, count: int32): void {
	for (let i = 0; i < count; i++) { w.bits[i] = sortKeyOf(w.keys[w.order[i]]); }
	scatter(w.bits, w.order, w.bitsScratch, w.scratch, w.buckets, count, 0);
	scatter(w.bitsScratch, w.scratch, w.bits, w.order, w.buckets, count, RADIX_BITS as uint32);
	scatter(
		w.bits, w.order, w.bitsScratch, w.scratch, w.buckets, count, (2 * RADIX_BITS) as uint32,
	);
	for (let i = 0; i < count; i++) { w.order[i] = w.scratch[i]; }
}

export function placed(sys: ParticleSystem, i: int32): Vec3 {
	const cap: int32 = sys.capacity;
	const p: Vec3 = vec3(
		sys.data[POS_X * cap + i], sys.data[POS_Y * cap + i], sys.data[POS_Z * cap + i],
	);
	return sys.asset.main.simulationSpace == SimulationSpace.Local ? p * sys.world : p;
}

// Whether `sys` draws at all: false for RenderMode.None, an error for Mesh, and for the point
// program (`visual` false) for anything but a view billboard, which a point cannot orient.
function drawn(sys: ParticleSystem, visual: boolean): Result<boolean, ParticleWriteError> {
	const renderer: Borrow<RendererModule> = sys.asset.renderer;
	if (renderer.renderMode == RenderMode.None) { return Result.ok(false); }
	if (renderer.renderMode == RenderMode.Mesh) {
		return Result.err(ParticleWriteError.UnsupportedRenderMode);
	}
	if (!visual
		&& (renderer.renderMode != RenderMode.Billboard
			|| renderer.alignment != RenderAlignment.View)) {
		return Result.err(ParticleWriteError.UnsupportedRenderMode);
	}
	return Result.ok(true);
}

// Puts `w.order[0, count)` in the order `sys`'s renderer draws its particles, seen from `eye`
// looking along `forward`, and refuses an `out` too short for `count` instances of `stride`.
export function drawOrder(
	ref w: ParticleWriter3D, sys: ParticleSystem, eye: Vec3, forward: Vec3, stride: int32,
	outLength: int32,
): Result<int32, ParticleWriteError> {
	const count: int32 = sys.count;
	if (count > 2147483647 / stride || outLength < count * stride) {
		return Result.err(ParticleWriteError.ShortInstances);
	}
	grow(w, count);
	const cap: int32 = sys.capacity;
	for (let i = 0; i < count; i++) { w.order[i] = i; }
	// Keys sort ascending, so whatever is drawn first gets the smallest key.
	const mode: ParticleSortMode = sys.asset.renderer.sortMode;
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
	return Result.ok(count);
}

export function finite(out: Span<float32>, at: int32, stride: int32): boolean {
	for (let c = 0; c < stride; c++) {
		if (!Number.isFinite(out[at + c])) { return false; }
	}
	return true;
}

// Writes `sys`'s particles into `out`, drawn first to last, seen from `eye` looking along
// `forward` and moving at `cameraVelocity` (read by cameraVelocityScale). `frames` holds one tile
// per sheet frame. Returns the instance count.
export function writeParticles(
	ref w: ParticleWriter3D, sys: ParticleSystem, frames: Readonly<Span<AtlasTile>>, eye: Vec3,
	forward: Vec3, cameraVelocity: Vec3, out: Span<float32>,
): Result<int32, ParticleWriteError> {
	const visible = drawn(sys, true);
	if (!visible.ok) { return Result.err(visible.error); }
	if (!visible.value) { return Result.ok(0); }
	const renderer: Borrow<RendererModule> = sys.asset.renderer;
	const sheet: Borrow<TextureSheetAnimationModule> = sys.asset.textureSheetAnimation;
	const wanted: int32 = sheet.enabled ? sheet.numTilesX * sheet.numTilesY : 1;
	if ((frames.length as int32) != wanted) { return Result.err(ParticleWriteError.FrameCount); }
	const stride: int32 = PARTICLE_VISUAL_INSTANCE_STRIDE;
	const ordered = drawOrder(w, sys, eye, forward, stride, out.length as int32);
	if (!ordered.ok) { return Result.err(ordered.error); }
	const count: int32 = ordered.value;
	const cap: int32 = sys.capacity;
	const flipU: float32 = sheet.enabled
		? renderer.flip.x + sheet.flipU - renderer.flip.x * sheet.flipU
		: renderer.flip.x;
	const flipV: float32 = sheet.enabled
		? renderer.flip.y + sheet.flipV - renderer.flip.y * sheet.flipV
		: renderer.flip.y;
	const last: int32 = wanted - 1;
	// The emitter's axes with its scale taken out, for RenderAlignment.Local.
	const emitterRight: Vec3 = vec3(1.0, 0.0, 0.0).transformDirection(sys.world).normalized();
	const emitterUp: Vec3 = vec3(0.0, 1.0, 0.0).transformDirection(sys.world).normalized();
	const pull: Vec3 = cameraVelocity.scaled(renderer.cameraVelocityScale);
	// allowRoll off is 1, freeform stretching 2, rotateWithStretchDirection 4.
	let flags: float32 = 0.0;
	if (!renderer.allowRoll) { flags = flags + 1.0; }
	if (renderer.freeformStretching) { flags = flags + 2.0; }
	if (renderer.rotateWithStretchDirection) { flags = flags + 4.0; }
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
		const move: Vec3 = vec3(
			sys.data[MOVE_X * cap + i], sys.data[MOVE_Y * cap + i], sys.data[MOVE_Z * cap + i]);
		const world: Vec3 = sys.asset.main.simulationSpace == SimulationSpace.Local ?
			move.transformDirection(sys.world) : move;
		out[at + 16] = world.x;
		out[at + 17] = world.y;
		out[at + 18] = world.z;
		out[at + 19] = renderer.renderMode as float32;
		out[at + 20] = renderer.alignment as float32;
		out[at + 21] = renderer.pivot.z;
		out[at + 22] = flags;
		out[at + 23] = renderer.lengthScale;
		out[at + 24] = renderer.velocityScale;
		out[at + 25] = renderer.minParticleSize;
		out[at + 26] = renderer.maxParticleSize;
		out[at + 27] = pull.x;
		out[at + 28] = pull.y;
		out[at + 29] = pull.z;
		out[at + 30] = emitterRight.x;
		out[at + 31] = emitterRight.y;
		out[at + 32] = emitterRight.z;
		out[at + 33] = emitterUp.x;
		out[at + 34] = emitterUp.y;
		out[at + 35] = emitterUp.z;
		if (!finite(out, at, stride)) { return Result.err(ParticleWriteError.NonFinite); }
	}
	return Result.ok(count);
}

// The same particles in the same order as `writeParticles`, as Program.Particle instances:
// position, width and colour, with no uv, height, anchor or rotation.
export function writeParticlePoints(
	ref w: ParticleWriter3D, sys: ParticleSystem, eye: Vec3, forward: Vec3, out: Span<float32>,
): Result<int32, ParticleWriteError> {
	const visible = drawn(sys, false);
	if (!visible.ok) { return Result.err(visible.error); }
	if (!visible.value) { return Result.ok(0); }
	const stride: int32 = PARTICLE_INSTANCE_STRIDE;
	const ordered = drawOrder(w, sys, eye, forward, stride, out.length as int32);
	if (!ordered.ok) { return Result.err(ordered.error); }
	const count: int32 = ordered.value;
	const cap: int32 = sys.capacity;
	for (let k = 0; k < count; k++) {
		const i: int32 = w.order[k];
		const p: Vec3 = placed(sys, i);
		const at: int32 = k * stride;
		out[at] = p.x;
		out[at + 1] = p.y;
		out[at + 2] = p.z;
		out[at + 3] = sys.data[SIZE_X * cap + i];
		out[at + 4] = sys.data[COLOR_R * cap + i];
		out[at + 5] = sys.data[COLOR_G * cap + i];
		out[at + 6] = sys.data[COLOR_B * cap + i];
		out[at + 7] = sys.data[COLOR_A * cap + i];
		if (!finite(out, at, stride)) { return Result.err(ParticleWriteError.NonFinite); }
	}
	return Result.ok(count);
}

// Writes `chains` as one quad per segment, seen through a camera whose view plane is spanned by
// `right` and `up`: each quad spans its segment's projection on that plane, as wide as the trail,
// with u along the trail and v across it on `t`. Returns the instance count.
export function writeTrails(
	chains: TrailChains, t: AtlasTile, right: Vec3, up: Vec3, out: Span<float32>,
): Result<int32, ParticleWriteError> {
	const stride: int32 = PARTICLE_VISUAL_INSTANCE_STRIDE;
	const segments: int32 = (chains.vertices.length as int32) - chains.chainCount();
	if (segments > 2147483647 / stride || (out.length as int32) < segments * stride) {
		return Result.err(ParticleWriteError.ShortInstances);
	}
	let n: int32 = 0;
	for (let c = 0; c < chains.chainCount(); c++) {
		const end: int32 = chains.chainEnd(c);
		for (let v = chains.starts[c]; v + 1 < end; v++) {
			const a: TrailVertex = chains.vertices[v];
			const b: TrailVertex = chains.vertices[v + 1];
			const d: Vec3 = b.position - a.position;
			const across: float32 = d.dot(right);
			const along: float32 = d.dot(up);
			const at: int32 = n * stride;
			out[at] = (a.position.x + b.position.x) * 0.5;
			out[at + 1] = (a.position.y + b.position.y) * 0.5;
			out[at + 2] = (a.position.z + b.position.z) * 0.5;
			out[at + 3] = Math.sqrt(across * across + along * along) as float32;
			out[at + 4] = (a.width + b.width) * 0.5;
			out[at + 5] = 0.0;
			out[at + 6] = 0.0;
			// The program turns the quad's x axis clockwise by this, onto the segment.
			out[at + 7] = Math.atan2(-along, across) as float32;
			out[at + 8] = t.u + (t.u2 - t.u) * a.u;
			out[at + 9] = t.v;
			out[at + 10] = t.u + (t.u2 - t.u) * b.u;
			out[at + 11] = t.v2;
			out[at + 12] = (a.color.r + b.color.r) * 0.5;
			out[at + 13] = (a.color.g + b.color.g) * 0.5;
			out[at + 14] = (a.color.b + b.color.b) * 0.5;
			out[at + 15] = (a.color.a + b.color.a) * 0.5;
			out[at + 16] = 0.0;
			out[at + 17] = 0.0;
			out[at + 18] = 0.0;
			for (let z = 19; z < stride; z++) { out[at + z] = 0.0; }
			for (let k = 0; k < stride; k++) {
				if (!Number.isFinite(out[at + k])) {
					return Result.err(ParticleWriteError.NonFinite);
				}
			}
			n = n + 1;
		}
	}
	return Result.ok(n);
}
