// Node2D is a flat tag + fields, not a discriminated union: a union payload as an interface
// field hits a C-codegen bug. Revisit the union once the compiler handles it.

import { destroyStaticMesh, freeRenderTarget } from "./draw";
import { Vec2, Color, Tile, Transform2D, Filter, BlendMode, rgba, tile, identity2d, inverse2d, noFilter } from "./types";

export enum DrawKind { Group, Rect, Sprite, Label, Anim, Graphics, Mask, ScaleGrid }

export interface Node2D {
	kind: DrawKind;
	x: float32;
	y: float32;
	scaleX: float32;
	scaleY: float32;
	rotation: float32;
	pivotX: float32;
	pivotY: float32;
	alpha: float32;
	visible: boolean;
	smooth: boolean;
	blend: BlendMode;
	zIndex: int32;
	w: float32;
	h: float32;
	color: Color;
	colorAdd: Color;
	colorKey: Color;
	colorMatrix: float32[];
	sheet: Tile;
	borderL: float32;
	borderT: float32;
	borderR: float32;
	borderB: float32;
	text: string;
	size: float32;
	align: float32;
	letterSpacing: float32;
	lineSpacing: float32;
	maxWidth: float32;
	frames: Tile[];
	fps: float32;
	clock: float32;
	mesh: float32[];
	gfxView: uint32;
	gfxBuf: uint32;
	gfxVertCount: int32;
	gfxDirty: boolean;
	children: Node2D[];
	childrenDirty: boolean;
	cachedLocal: Transform2D;
	cachedWorld: Transform2D;
	lastX: float32;
	lastY: float32;
	lastSX: float32;
	lastSY: float32;
	lastRot: float32;
	dirty: boolean;
	txtBuf: uint32;
	txtVertCount: int32;
	textDirty: boolean;
	lastText: string;
	lastSize: float32;
	lastAlign: float32;
	lastLetterSpacing: float32;
	lastLineSpacing: float32;
	lastMaxWidth: float32;
	contentXMin: float32;
	contentYMin: float32;
	contentXMax: float32;
	contentYMax: float32;
	lastAtlasGen: int32;
	fontId: int32;
	lastFontId: int32;
	filter: Filter;
	filterRT: uint32;
	filterRTW: int32;
	filterRTH: int32;
}

function base(kind: DrawKind): Node2D {
	return {
		kind: kind, x: 0.0, y: 0.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0, alpha: 1.0, visible: true, smooth: true, blend: BlendMode.Alpha, zIndex: 0,
		w: 0.0, h: 0.0, color: rgba(1.0, 1.0, 1.0, 1.0), colorAdd: rgba(0.0, 0.0, 0.0, 0.0), colorKey: rgba(0.0, 0.0, 0.0, 0.0), colorMatrix: [], sheet: tile(0, 0.0, 0.0), borderL: 0.0, borderT: 0.0, borderR: 0.0, borderB: 0.0, text: "", size: 0.0, align: 0.0, letterSpacing: 0.0, lineSpacing: 1.0, maxWidth: 0.0, frames: [], fps: 0.0, clock: 0.0, mesh: [], gfxView: 0, gfxBuf: 0, gfxVertCount: 0, gfxDirty: true, children: [], childrenDirty: true,
		cachedLocal: identity2d(), cachedWorld: identity2d(), lastX: 0.0, lastY: 0.0, lastSX: 0.0, lastSY: 0.0, lastRot: 0.0, dirty: true,
		txtBuf: 0, txtVertCount: 0, textDirty: true, lastText: "", lastSize: 0.0, lastAlign: 0.0, lastLetterSpacing: 0.0, lastLineSpacing: 0.0, lastMaxWidth: 0.0,
		contentXMin: 0.0, contentYMin: 0.0, contentXMax: 0.0, contentYMax: 0.0,
		lastAtlasGen: 0,
		fontId: 0, lastFontId: -1,
		filter: noFilter(), filterRT: 0, filterRTW: 0, filterRTH: 0,
	};
}

export function group(): Node2D { return base(DrawKind.Group); }
export function rect(w: float32, h: float32, color: Color): Node2D {
	const n = base(DrawKind.Rect);
	n.w = w; n.h = h; n.color = color;
	return n;
}
export function sprite(t: Tile): Node2D {
	const n = base(DrawKind.Sprite);
	n.sheet = t; n.w = t.w; n.h = t.h;
	return n;
}
export function label(text: string, size: float32, color: Color): Node2D {
	const n = base(DrawKind.Label);
	n.text = text; n.size = size; n.color = color;
	return n;
}
export function anim(frames: Tile[], fps: float32): Node2D {
	const n = base(DrawKind.Anim);
	n.frames = frames; n.fps = fps;
	if (frames.length > 0) { n.w = frames[0].w; n.h = frames[0].h; }
	return n;
}
export function graphics(): Node2D { return base(DrawKind.Graphics); }
export function mask(w: float32, h: float32): Node2D {
	const n = base(DrawKind.Mask);
	n.w = w; n.h = h;
	return n;
}
export function scaleGrid(t: Tile, borderL: float32, borderT: float32, borderR: float32, borderB: float32): Node2D {
	const n = base(DrawKind.ScaleGrid);
	n.sheet = t; n.w = t.w; n.h = t.h;
	n.borderL = borderL; n.borderT = borderT; n.borderR = borderR; n.borderB = borderB;
	return n;
}

export function addChild(this n: Node2D, c: Node2D): Node2D {
	n.children.push(c);
	n.childrenDirty = true;
	return n;
}

export function addChildAt(this n: Node2D, c: Node2D, index: int32): Node2D {
	if (index < 0) { index = 0; }
	const cs: Node2D[] = [];
	const len: int32 = n.children.length as int32;
	let i: int32 = 0;
	while (i < len) {
		if (i == index) { cs.push(c); }
		cs.push(n.children[i]);
		i = i + 1;
	}
	if (index >= len) { cs.push(c); }
	n.children = cs;
	n.childrenDirty = true;
	return n;
}

export function removeChild(this n: Node2D, c: Node2D): void {
	const remaining: Node2D[] = [];
	for (const ch of n.children) {
		if (ch !== c) { remaining.push(ch); }
	}
	n.children = remaining;
	n.childrenDirty = true;
}

export function removeChildren(this n: Node2D): void {
	n.children = [];
	n.childrenDirty = true;
}

export function at(this n: Node2D, x: float32, y: float32): Node2D {
	n.x = x; n.y = y;
	return n;
}

export function localToGlobal(this n: Node2D, p: Vec2): Vec2 {
	return p * n.cachedWorld;
}

export function globalToLocal(this n: Node2D, p: Vec2): Vec2 {
	return p * inverse2d(n.cachedWorld);
}

export function update(this n: Node2D, dt: float32): void {
	if (n.kind === DrawKind.Anim) {
		n.clock = n.clock + dt;
	}
	for (const ch of n.children) {
		ch.update(dt);
	}
}

export function dispose(this n: Node2D): void {
	if (n.gfxBuf != 0) { destroyStaticMesh(n.gfxBuf); n.gfxBuf = 0; }
	if (n.txtBuf != 0) { destroyStaticMesh(n.txtBuf); n.txtBuf = 0; }
	if (n.filterRT != 0) { freeRenderTarget(n.filterRT); n.filterRT = 0; }
	for (const ch of n.children) {
		ch.dispose();
	}
}
