// A particle effect drawn by void2d: the effect simulates in Unity's units with y up, and every
// live particle becomes one cell of a TileGroup, its sheet frame as the cell's tile
// (docs/PARTICLES.md: one model for 2D and 3D; the TileGroup is RENDER §A.1's 2D particle shape).
// A system's trails draw as triangle strips into a Graphics node under its particles.

import { Mat4, Vec3 } from "../math/math3d";
import { ParticleEffect, RenderMode, TextureSheetAnimationModule } from "../particles/asset";
import { unitDraw } from "../particles/curve";
import { EffectInstance, EffectError, playEffect, stopEffect, updateEffect } from "../particles/effect";
import {
	ParticleSystem, ParticleSystemError, POS_X, POS_Y, ROT_Z, SIZE_X, SIZE_Y, COLOR_R, COLOR_G,
	COLOR_B, COLOR_A, FRAME, DRAW_FLIP_U, DRAW_FLIP_V,
} from "../particles/system";
import { TrailChains, TrailVertex, buildTrails } from "../particles/trail";
import { Scene2D, NodeRef, TileCell } from "./node";
import { fillTexTriangles } from "./graphics";
import { Tile, Transform2D, Vec2, Color, rgba, vec2, whiteTile } from "./types";

const MITER_LIMIT: float32 = 4.0;

export struct ParticleEmitter2D {
	effect: EffectInstance;
	// The TileGroup the particles draw into; its frame is the effect's simulation space.
	node: NodeRef;
	// Per system: its sheet frames, each centred on the particle.
	frames: Vec<Vec<Tile>>;
	cells: TileCell[];
	// Holds the trail nodes, then the particles' node: attach it to draw the effect.
	root: NodeRef;
	// Per system with trails: its Graphics node and the tile its trails sample.
	trailSystems: Vec<int32>;
	trailNodes: Vec<NodeRef>;
	trailTiles: Vec<Tile>;
	chains: TrailChains;
	points: Vec2[];
	uvs: Vec2[];
	colors: Color[];
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
	const sheet: Borrow<TextureSheetAnimationModule> = sys.asset.textureSheetAnimation;
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
	const root: NodeRef = s.group();
	let trailSystems: Vec<int32> = [];
	let trailNodes: Vec<NodeRef> = [];
	let trailTiles: Vec<Tile> = [];
	for (let k = 0; k < (effect.systems.length as int32); k++) {
		if (!effect.systems[k].trails.enabled) { continue; }
		const g: NodeRef = s.graphics();
		root.addChild(g);
		trailSystems.push(k);
		trailNodes.push(g);
		trailTiles.push(whiteTile(1.0, 1.0));
	}
	const node: NodeRef = s.tileGroup();
	root.addChild(node);
	return Result.ok({
		effect: made.value, node: node, frames: frames, cells: [], root: root,
		trailSystems: trailSystems, trailNodes: trailNodes, trailTiles: trailTiles,
		chains: TrailChains.create(), points: [], uvs: [], colors: [],
	});
}

// The tile system `system`'s trails sample: u runs along the trail, v across it. A texture mode
// that repeats wants the tile to be its whole texture, sampled with wrap.
export function setTrailTile(this ref e: ParticleEmitter2D, system: int32, t: Tile): void {
	for (let k = 0; k < (e.trailSystems.length as int32); k++) {
		if (e.trailSystems[k] == system) {
			e.trailTiles[k] = t;
			return;
		}
	}
	console.log(`void2d: setTrailTile asked of system ${system}, which has no Trails module`);
	unreachable;
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
	for (let k = 0; k < (e.trailSystems.length as int32); k++) { e.redrawTrails(k); }
}

function flat(p: Vec3): Vec2 {
	return vec2(p.x, -p.y);
}

// The left normal of a to b, zero when they meet.
function normalOf(a: Vec2, b: Vec2): Vec2 {
	const dx: float32 = b.x - a.x;
	const dy: float32 = b.y - a.y;
	const len: float32 = Math.sqrt(dx * dx + dy * dy) as float32;
	if (len < 1e-6) { return vec2(0.0, 0.0); }
	return vec2(-dy / len, dx / len);
}

// Where vertex k of chain [start, end) sits its edges: its half width along the mitre of its
// two segments.
function offsetAt(chains: TrailChains, start: int32, end: int32, k: int32): Vec2 {
	const p: Vec2 = flat(chains.vertices[k].position);
	const before: Vec2 = k > start ? normalOf(flat(chains.vertices[k - 1].position), p) : vec2(0.0, 0.0);
	const after: Vec2 = k + 1 < end ? normalOf(p, flat(chains.vertices[k + 1].position)) : vec2(0.0, 0.0);
	let mx: float32 = before.x + after.x;
	let my: float32 = before.y + after.y;
	const len: float32 = Math.sqrt(mx * mx + my * my) as float32;
	const half: float32 = chains.vertices[k].width * 0.5;
	if (len < 1e-6) {
		const side: Vec2 = after.x != 0.0 || after.y != 0.0 ? after : before;
		return vec2(side.x * half, side.y * half);
	}
	mx = mx / len;
	my = my / len;
	const edge: Vec2 = after.x != 0.0 || after.y != 0.0 ? after : before;
	const cosine: float32 = mx * edge.x + my * edge.y;
	const scale: float32 = cosine > 1.0 / MITER_LIMIT ? 1.0 / cosine : MITER_LIMIT;
	return vec2(mx * half * scale, my * half * scale);
}

function corner(this ref e: ParticleEmitter2D, p: Vec2, uv: Vec2, c: Color): void {
	e.points.push(p);
	e.uvs.push(uv);
	e.colors.push(c);
}

function redrawTrails(this ref e: ParticleEmitter2D, k: int32): void {
	const sys: ParticleSystem = e.effect.systems[e.trailSystems[k]];
	const node: NodeRef = e.trailNodes[k];
	const t: Tile = e.trailTiles[k];
	node.clear();
	buildTrails(sys, e.chains);
	e.points.length = 0;
	e.uvs.length = 0;
	e.colors.length = 0;
	const du: float32 = t.u1 - t.u0;
	for (let c = 0; c < e.chains.chainCount(); c++) {
		const start: int32 = e.chains.starts[c];
		const end: int32 = e.chains.chainEnd(c);
		for (let v = start; v + 1 < end; v++) {
			const va: TrailVertex = e.chains.vertices[v];
			const vb: TrailVertex = e.chains.vertices[v + 1];
			const a: Vec2 = flat(va.position);
			const b: Vec2 = flat(vb.position);
			const oa: Vec2 = offsetAt(e.chains, start, end, v);
			const ob: Vec2 = offsetAt(e.chains, start, end, v + 1);
			const ua: float32 = t.u0 + va.u * du;
			const ub: float32 = t.u0 + vb.u * du;
			const ca: Color = rgba(va.color.r, va.color.g, va.color.b, va.color.a);
			const cb: Color = rgba(vb.color.r, vb.color.g, vb.color.b, vb.color.a);
			const al: Vec2 = vec2(a.x + oa.x, a.y + oa.y);
			const ar: Vec2 = vec2(a.x - oa.x, a.y - oa.y);
			const bl: Vec2 = vec2(b.x + ob.x, b.y + ob.y);
			const br: Vec2 = vec2(b.x - ob.x, b.y - ob.y);
			e.corner(al, vec2(ua, t.v0), ca);
			e.corner(ar, vec2(ua, t.v1), ca);
			e.corner(br, vec2(ub, t.v1), cb);
			e.corner(al, vec2(ua, t.v0), ca);
			e.corner(br, vec2(ub, t.v1), cb);
			e.corner(bl, vec2(ub, t.v0), cb);
		}
	}
	if ((e.points.length as int32) > 0) { node.fillTexTriangles(t, e.points, e.uvs, e.colors); }
}
