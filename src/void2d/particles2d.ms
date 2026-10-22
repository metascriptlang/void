// A particle effect drawn by void2d: the effect simulates in Unity's units with y up, and every
// live particle becomes one cell of a TileGroup, its sheet frame as the cell's tile
// (docs/PARTICLES.md: one model for 2D and 3D; the TileGroup is RENDER §A.1's 2D particle shape).

import { Mat4 } from "../math/math3d";
import { ParticleEffect, RenderMode } from "../particles/asset";
import { unitDraw } from "../particles/curve";
import { EffectInstance, EffectError, playEffect, stopEffect, updateEffect } from "../particles/effect";
import {
	ParticleSystem, ParticleSystemError, POS_X, POS_Y, ROT_Z, SIZE_X, SIZE_Y, COLOR_R, COLOR_G,
	COLOR_B, COLOR_A, FRAME, DRAW_FLIP_U, DRAW_FLIP_V,
} from "../particles/system";
import { Scene2D, NodeRef, TileCell } from "./node";
import { Tile, Transform2D, rgba } from "./types";

export struct ParticleEmitter2D {
	effect: EffectInstance;
	// The TileGroup the particles draw into; its frame is the effect's simulation space.
	node: NodeRef;
	// Per system: its sheet frames, each centred on the particle.
	frames: Vec<Vec<Tile>>;
	cells: TileCell[];
}

// The y-up placement of an emitter given in void2d's y-down frame.
function liftY(m: Transform2D): Mat4 {
	return {
		m11: m.a, m12: -m.b, m13: 0.0, m14: 0.0,
		m21: -m.c, m22: m.d, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: 1.0, m34: 0.0,
		m41: m.tx, m42: -m.ty, m43: 0.0, m44: 1.0,
	};
}

// The sheet frames of `t`, left to right then top to bottom, centred on the particle.
function sheetFrames(t: Tile, sys: ParticleSystem): Vec<Tile> {
	const sheet = sys.asset.textureSheetAnimation;
	const across: int32 = sheet.enabled ? sheet.numTilesX : 1;
	const down: int32 = sheet.enabled ? sheet.numTilesY : 1;
	const w: float32 = t.w / (across as float32);
	const h: float32 = t.h / (down as float32);
	const du: float32 = (t.u1 - t.u0) / (across as float32);
	const dv: float32 = (t.v1 - t.v0) / (down as float32);
	let out: Vec<Tile> = [];
	for (let row = 0; row < down; row++) {
		for (let col = 0; col < across; col++) {
			out.push({
				...t,
				u0: t.u0 + du * (col as float32), v0: t.v0 + dv * (row as float32),
				u1: t.u0 + du * ((col + 1) as float32), v1: t.v0 + dv * ((row + 1) as float32),
				w: w, h: h, dx: -w * 0.5, dy: -h * 0.5,
			});
		}
	}
	return out;
}

// An emitter of `effect` whose system k draws from `tiles[k]`, split by its texture sheet.
export function particles(
	this s: Scene2D, effect: ParticleEffect, tiles: Tile[], seed: uint32,
): Result<ParticleEmitter2D, EffectError> {
	if ((tiles.length as int32) != (effect.systems.length as int32)) {
		console.log(`void2d: particles got ${tiles.length} tiles for ${effect.systems.length} systems; give one tile per system`);
		unreachable;
	}
	const made = EffectInstance.create(effect, seed);
	if (!made.ok) { return Result.err(made.error); }
	let frames: Vec<Vec<Tile>> = [];
	for (let k = 0; k < (tiles.length as int32); k++) { frames.push(sheetFrames(tiles[k], made.value.systems[k])); }
	return Result.ok({ effect: made.value, node: s.tileGroup(), frames: frames, cells: [] });
}

export function play(this ref e: ParticleEmitter2D, emitter: Transform2D): void {
	playEffect(e.effect, liftY(emitter));
}

export function stop(this ref e: ParticleEmitter2D, clear: boolean): void {
	stopEffect(e.effect, clear);
	if (clear) { e.redraw(); }
}

// Advances the effect by `dt` seconds with the emitter at `emitter` in the node's frame, then
// rewrites the node's cells. Returns the live particle count.
export function update(this ref e: ParticleEmitter2D, dt: float64, emitter: Transform2D): Result<int32, ParticleSystemError> {
	const count = try updateEffect(e.effect, dt, liftY(emitter));
	e.redraw();
	return Result.ok(count);
}

function redraw(this ref e: ParticleEmitter2D): void {
	e.cells.length = 0;
	for (let k = 0; k < (e.effect.systems.length as int32); k++) {
		const sys: ParticleSystem = e.effect.systems[k];
		if (sys.asset.renderer.renderMode == RenderMode.None) { continue; }
		const cap: int32 = sys.capacity;
		const frames: Vec<Tile> = e.frames[k];
		const last: int32 = (frames.length as int32) - 1;
		const flip = sys.asset.renderer.flip;
		const sheet = sys.asset.textureSheetAnimation;
		const flipU: float32 = sheet.enabled ? flip.x + sheet.flipU - flip.x * sheet.flipU : flip.x;
		const flipV: float32 = sheet.enabled ? flip.y + sheet.flipV - flip.y * sheet.flipV : flip.y;
		for (let i = 0; i < sys.count; i++) {
			let frame: int32 = sheet.enabled ? sys.data[FRAME * cap + i] as int32 : 0;
			if (frame > last) { frame = last; }
			let t: Tile = frames[frame];
			const seed: uint32 = sys.seeds[i];
			if (unitDraw(seed, DRAW_FLIP_U) < flipU) { t = { ...t, u0: t.u1, u1: t.u0 }; }
			if (unitDraw(seed, DRAW_FLIP_V) < flipV) { t = { ...t, v0: t.v1, v1: t.v0 }; }
			e.cells.push({
				x: sys.data[POS_X * cap + i],
				y: -sys.data[POS_Y * cap + i],
				tile: t,
				color: rgba(
					sys.data[COLOR_R * cap + i], sys.data[COLOR_G * cap + i],
					sys.data[COLOR_B * cap + i], sys.data[COLOR_A * cap + i],
				),
				scaleX: sys.data[SIZE_X * cap + i] / t.w,
				scaleY: sys.data[SIZE_Y * cap + i] / t.h,
				rotation: sys.data[ROT_Z * cap + i],
			});
		}
	}
	e.node.setTiles(e.cells);
}
