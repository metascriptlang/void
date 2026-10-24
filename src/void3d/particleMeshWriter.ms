// Writes a Mesh-mode particle system as instances of its meshes (docs/PARTICLES-RENDER.md
// A.2.1): per particle the world-space 3x4 affine of its mesh, as three rows (row i = m_i0, m_i1,
// m_i2, t_i), then its colour, as runs of one mesh that are one draw each. The affine is
// composed here in Unity's left-handed frame, from the alignment axes, the particle's 3D
// rotation and size, the pivot and the flip, and crosses to Void's frame with z negated.

import { Vec3, vec3, transformDirection, cross, normalized, scaled } from "../math/math3d";
import {
	MeshDistribution, RenderMode, RenderAlignment, SimulationSpace, RendererModule,
} from "../particles/asset";
import { unitDraw } from "../particles/curve";
import {
	ParticleSystem, SIZE_X, SIZE_Y, SIZE_Z, ROT_X, ROT_Y, ROT_Z, COLOR_R, COLOR_G, COLOR_B, COLOR_A,
	DRAW_FLIP_U, DRAW_FLIP_V, DRAW_FLIP_Z, DRAW_MESH, MOVE_X, MOVE_Y, MOVE_Z,
} from "../particles/system";
import {
	ParticleWriter3D, ParticleWriteError, PARTICLE_MESH_INSTANCE_STRIDE, drawOrder, placed, finite,
} from "./particleWriter";

const TINY: float32 = 1e-6;
// Velocity along world up has no measurement; this is the reference taken then.
const UNMEASURED_PARALLEL_REFERENCE: Vec3 = { x: 0.0, y: 0.0, z: 1.0 };

// How instances of several meshes are ordered: grouped by mesh for a depth-tested material, where
// the order is invisible, or kept in draw order for a blended one, with a run per change of mesh.
export enum MeshDrawOrder {
	ByMesh,
	AsDrawn,
}

// `count` consecutive instances of mesh `mesh`, one instanced draw.
export struct MeshRun {
	mesh: int32;
	count: int32;
}

struct MeshAxes {
	x: Vec3;
	y: Vec3;
	z: Vec3;
}

// Unity's frame is Void's with z negated; the map is its own inverse.
function mirrored(v: Vec3): Vec3 {
	return vec3(v.x, v.y, -v.z);
}

// The mesh index a particle with `seed` draws: equal odds, or by weight, never a zero weight.
export function meshIndexOf(renderer: Borrow<RendererModule>, seed: uint32): int32 {
	const meshes: int32 = renderer.meshCount;
	const u: float32 = unitDraw(seed, DRAW_MESH);
	if (renderer.meshDistribution == MeshDistribution.UniformRandom) {
		const k: int32 = (u * (meshes as float32)) as int32;
		return k < meshes ? k : meshes - 1;
	}
	let total: float32 = 0.0;
	let last: int32 = 0;
	for (let k = 0; k < meshes; k++) {
		total = total + renderer.meshWeights[k];
		if (renderer.meshWeights[k] > 0.0) { last = k; }
	}
	const target: float32 = u * total;
	let below: float32 = 0.0;
	for (let k = 0; k < meshes; k++) {
		below = below + renderer.meshWeights[k];
		if (renderer.meshWeights[k] > 0.0 && target < below) { return k; }
	}
	return last;
}

// The mesh's axes for a particle, in Unity's frame: View is the camera's, World the world's,
// Local the emitter's, Facing looks along the camera-to-particle ray with the camera's up, and
// Velocity looks along the velocity with the world z axis as its reference.
function alignmentAxes(
	alignment: RenderAlignment, camera: MeshAxes, toParticle: Vec3, velocity: Vec3,
	emitter: MeshAxes,
): MeshAxes {
	if (alignment == RenderAlignment.View) { return camera; }
	if (alignment == RenderAlignment.Local) { return emitter; }
	if (alignment == RenderAlignment.Facing && toParticle.length() > TINY) {
		const f: Vec3 = normalized(toParticle);
		const r: Vec3 = normalized(cross(camera.y, f));
		return { x: r, y: cross(f, r), z: f };
	}
	if (alignment == RenderAlignment.Velocity && velocity.length() > TINY) {
		const f: Vec3 = normalized(velocity);
		let r: Vec3 = cross(vec3(0.0, 1.0, 0.0), f);
		if (r.length() < TINY) { r = cross(UNMEASURED_PARALLEL_REFERENCE, f); }
		r = normalized(r);
		return { x: r, y: cross(f, r), z: f };
	}
	return { x: vec3(1.0, 0.0, 0.0), y: vec3(0.0, 1.0, 0.0), z: vec3(0.0, 0.0, 1.0) };
}

// Unity's Euler rotation (z, then x, then y) as the columns of its matrix applied to `axes`.
function turned(axes: MeshAxes, rx: float32, ry: float32, rz: float32): MeshAxes {
	const cx: float32 = Math.cos(rx) as float32;
	const sx: float32 = Math.sin(rx) as float32;
	const cy: float32 = Math.cos(ry) as float32;
	const sy: float32 = Math.sin(ry) as float32;
	const cz: float32 = Math.cos(rz) as float32;
	const sz: float32 = Math.sin(rz) as float32;
	const r00: float32 = cy * cz + sy * sx * sz;
	const r01: float32 = -cy * sz + sy * sx * cz;
	const r02: float32 = sy * cx;
	const r10: float32 = cx * sz;
	const r11: float32 = cx * cz;
	const r12: float32 = -sx;
	const r20: float32 = -sy * cz + cy * sx * sz;
	const r21: float32 = sy * sz + cy * sx * cz;
	const r22: float32 = cy * cx;
	return {
		x: axes.x.scaled(r00) + axes.y.scaled(r10) + axes.z.scaled(r20),
		y: axes.x.scaled(r01) + axes.y.scaled(r11) + axes.z.scaled(r21),
		z: axes.x.scaled(r02) + axes.y.scaled(r12) + axes.z.scaled(r22),
	};
}

// One row of the affine in Void's frame: the mirror negates the entries that mix z with x or y.
function writeRow(
	out: Span<float32>, at: int32, row: int32, x: Vec3, y: Vec3, z: Vec3, t: Vec3,
): void {
	const sign: float32 = row == 2 ? -1.0 : 1.0;
	const rx: float32 = row == 0 ? x.x : (row == 1 ? x.y : x.z);
	const ry: float32 = row == 0 ? y.x : (row == 1 ? y.y : y.z);
	const rz: float32 = row == 0 ? z.x : (row == 1 ? z.y : z.z);
	const rt: float32 = row == 0 ? t.x : (row == 1 ? t.y : t.z);
	out[at] = rx * sign;
	out[at + 1] = ry * sign;
	out[at + 2] = -rz * sign;
	out[at + 3] = rt * sign;
}

// Writes `sys`'s particles as mesh instances into `out` in `order`, and the runs that cover
// them, first to last, into `runs`: ByMesh gives a run per drawn mesh in mesh order, each in
// draw order; AsDrawn keeps the draw order. The camera is at `eye`, looking along `forward`
// with `up` (Void's frame). `boundsSizes` is each mesh's extent (max - min of its vertices), the
// unit of the pivot. Returns the run count.
export function writeMeshParticles(
	ref w: ParticleWriter3D, sys: ParticleSystem, eye: Vec3, forward: Vec3, up: Vec3,
	boundsSizes: Readonly<Span<Vec3>>, order: MeshDrawOrder, out: Span<float32>,
	runs: Span<MeshRun>,
): Result<int32, ParticleWriteError> {
	const renderer: Borrow<RendererModule> = sys.asset.renderer;
	if (renderer.renderMode != RenderMode.Mesh) {
		return Result.err(ParticleWriteError.UnsupportedRenderMode);
	}
	const meshes: int32 = renderer.meshCount;
	if (meshes < 1 || (boundsSizes.length as int32) < meshes) {
		return Result.err(ParticleWriteError.ShortInstances);
	}
	const stride: int32 = PARTICLE_MESH_INSTANCE_STRIDE;
	const ordered = drawOrder(w, sys, eye, forward, stride, out.length as int32);
	if (!ordered.ok) { return Result.err(ordered.error); }
	const count: int32 = ordered.value;
	const cap: int32 = sys.capacity;
	let counts: int32[4] = [0, 0, 0, 0];
	let runCount: int32 = 0;
	let last: int32 = -1;
	// w.scratch is free once the order is final: it holds each drawn slot's mesh index.
	for (let k = 0; k < count; k++) {
		const m: int32 = meshIndexOf(renderer, sys.seeds[w.order[k]]);
		w.scratch[k] = m;
		counts[m] = counts[m] + 1;
		if (order == MeshDrawOrder.AsDrawn && m != last) {
			if (runCount >= (runs.length as int32)) {
				return Result.err(ParticleWriteError.ShortInstances);
			}
			runs[runCount] = { mesh: m, count: 0 };
			runCount = runCount + 1;
			last = m;
		}
		if (order == MeshDrawOrder.AsDrawn) {
			runs[runCount - 1].count = runs[runCount - 1].count + 1;
		}
	}
	let starts: int32[4] = [0, 0, 0, 0];
	for (let m = 1; m < meshes; m++) { starts[m] = starts[m - 1] + counts[m - 1]; }
	if (order == MeshDrawOrder.ByMesh) {
		for (let m = 0; m < meshes; m++) {
			if (counts[m] == 0) { continue; }
			if (runCount >= (runs.length as int32)) {
				return Result.err(ParticleWriteError.ShortInstances);
			}
			runs[runCount] = { mesh: m, count: counts[m] };
			runCount = runCount + 1;
		}
	}
	const local: boolean = sys.asset.main.simulationSpace == SimulationSpace.Local;
	const eyeU: Vec3 = mirrored(eye);
	const camera: MeshAxes = {
		x: cross(mirrored(up), mirrored(forward)), y: mirrored(up), z: mirrored(forward),
	};
	const worldRight: Vec3 = vec3(1.0, 0.0, 0.0).transformDirection(sys.world);
	const worldUp: Vec3 = vec3(0.0, 1.0, 0.0).transformDirection(sys.world);
	const emitterRight: Vec3 = normalized(mirrored(worldRight));
	const emitterUp: Vec3 = normalized(mirrored(worldUp));
	const emitter: MeshAxes = {
		x: emitterRight, y: emitterUp, z: cross(emitterRight, emitterUp),
	};
	for (let k = 0; k < count; k++) {
		const i: int32 = w.order[k];
		const m: int32 = w.scratch[k];
		const seed: uint32 = sys.seeds[i];
		const p: Vec3 = mirrored(placed(sys, i));
		const move: Vec3 = vec3(
			sys.data[MOVE_X * cap + i], sys.data[MOVE_Y * cap + i], sys.data[MOVE_Z * cap + i]);
		const velocity: Vec3 = mirrored(local ? move.transformDirection(sys.world) : move);
		const axes: MeshAxes = alignmentAxes(
			renderer.alignment, camera, p - eyeU, velocity, emitter);
		const q: MeshAxes = turned(
			axes, sys.data[ROT_X * cap + i], sys.data[ROT_Y * cap + i], sys.data[ROT_Z * cap + i]);
		const mirrorX: float32 = unitDraw(seed, DRAW_FLIP_U) < renderer.flip.x ? -1.0 : 1.0;
		const mirrorY: float32 = unitDraw(seed, DRAW_FLIP_V) < renderer.flip.y ? -1.0 : 1.0;
		const mirrorZ: float32 = unitDraw(seed, DRAW_FLIP_Z) < renderer.flip.z ? -1.0 : 1.0;
		const sx: float32 = sys.data[SIZE_X * cap + i];
		const sy: float32 = sys.data[SIZE_Y * cap + i];
		const sz: float32 = sys.data[SIZE_Z * cap + i];
		const bounds: Vec3 = boundsSizes[m];
		const t: Vec3 = p + q.x.scaled(sx * renderer.pivot.x * bounds.x)
			+ q.y.scaled(sy * renderer.pivot.y * bounds.y)
			- q.z.scaled(sz * renderer.pivot.z * bounds.z);
		const x: Vec3 = q.x.scaled(sx * mirrorX);
		const y: Vec3 = q.y.scaled(sy * mirrorY);
		const z: Vec3 = q.z.scaled(sz * mirrorZ);
		const slot: int32 = order == MeshDrawOrder.ByMesh ? starts[m] : k;
		const at: int32 = slot * stride;
		starts[m] = starts[m] + 1;
		writeRow(out, at, 0, x, y, z, t);
		writeRow(out, at + 4, 1, x, y, z, t);
		writeRow(out, at + 8, 2, x, y, z, t);
		out[at + 12] = sys.data[COLOR_R * cap + i];
		out[at + 13] = sys.data[COLOR_G * cap + i];
		out[at + 14] = sys.data[COLOR_B * cap + i];
		out[at + 15] = sys.data[COLOR_A * cap + i];
		if (!finite(out, at, stride)) { return Result.err(ParticleWriteError.NonFinite); }
	}
	return Result.ok(runCount);
}
