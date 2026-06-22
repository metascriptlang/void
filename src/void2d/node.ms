// Void 2D scene — functional take on h2d (no classes/OOP): a data Node2D + a `kind`
// tag + extension methods (n.addChild / n.at / n.render). Node2D ≈ h2d.Object;
// kind = Group/Rect/Sprite/Label ≈ h2d.Bitmap/Text/Graphics; Tile ≈ h2d.Tile.
// (A discriminated-union payload hit a C-codegen issue when used as an interface field —
//  flat tag + fields is the robust shape; revisit the union later.)

import { fillQuad, imageQuad, drawTextXform } from "./draw";
import { Color, Tile, Transform2D, BlendMode, vec2, rgba, tile, trs2d } from "./types";

export enum DrawKind { Group, Rect, Sprite, Label }

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
	blend: BlendMode;
	w: float32;
	h: float32;
	color: Color;
	sheet: Tile;
	text: string;
	size: float32;
	children: Node2D[];
}

function base(kind: DrawKind): Node2D {
	return {
		kind: kind, x: 0.0, y: 0.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0, alpha: 1.0, visible: true, blend: BlendMode.Alpha,
		w: 0.0, h: 0.0, color: rgba(1.0, 1.0, 1.0, 1.0), sheet: tile(0, 0.0, 0.0), text: "", size: 0.0, children: [],
	};
}

// ===== factories (≈ new Bitmap/Text, functional) =====

export function group(): Node2D {
	return base(DrawKind.Group);
}
export function rect(w: float32, h: float32, color: Color): Node2D {
	const n = base(DrawKind.Rect);
	n.w = w;
	n.h = h;
	n.color = color;
	return n;
}
export function sprite(t: Tile): Node2D {
	const n = base(DrawKind.Sprite);
	n.sheet = t;
	n.w = t.w;
	n.h = t.h;
	return n;
}
export function label(text: string, size: float32, color: Color): Node2D {
	const n = base(DrawKind.Label);
	n.text = text;
	n.size = size;
	n.color = color;
	return n;
}

// ===== extension methods (reads OO, is FP) =====

export function addChild(this n: Node2D, c: Node2D): Node2D {
	n.children.push(c);
	return n;
}

export function at(this n: Node2D, x: float32, y: float32): Node2D {
	n.x = x;
	n.y = y;
	return n;
}

export function render(this n: Node2D, parent: Transform2D, a: float32): void {
	if (!n.visible) { return; }
	const world = parent * trs2d(n.x, n.y, n.rotation, n.scaleX, n.scaleY);
	const na: float32 = a * n.alpha;
	const col = rgba(n.color.r, n.color.g, n.color.b, n.color.a * na);
	const px: float32 = n.pivotX;
	const py: float32 = n.pivotY;
	if (n.kind === DrawKind.Rect) {
		fillQuad(vec2(-px, -py) * world, vec2(n.w - px, -py) * world, vec2(n.w - px, n.h - py) * world, vec2(-px, n.h - py) * world, col, n.blend);
	} else if (n.kind === DrawKind.Sprite) {
		imageQuad(n.sheet, vec2(-px, -py) * world, vec2(n.w - px, -py) * world, vec2(n.w - px, n.h - py) * world, vec2(-px, n.h - py) * world, col, n.blend);
	} else if (n.kind === DrawKind.Label) {
		drawTextXform(world, n.size, n.text, col, n.blend);
	}
	for (const ch of n.children) {
		ch.render(world, na);
	}
}
