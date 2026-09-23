// The two scenes of the host-view example (examples/ionViews.ms): a board of tiles that fills
// its view, and a panel drawn over a transparent clear. They are laid out in logical pixels
// from the size of the view that draws them.

import { Node2D, rect, at, addChild } from "../void2d/node";
import { Scene, scene, add } from "../void2d/scene";
import { Color, rgba } from "../void2d/types";

const MARGIN: float32 = 24.0;
const GAP: float32 = 10.0;
const EDGE: float32 = 3.0;
const PANEL_W: float32 = 300.0;
const PANEL_H: float32 = 180.0;
const BAR_SLOTS: int32 = 10 as int32;

const TILE_OFF: Color = rgba(0.18, 0.21, 0.28, 1.0);
const TILE_ON: Color = rgba(0.95, 0.72, 0.25, 1.0);
const EDGE_COLOR: Color = rgba(0.30, 0.80, 0.95, 1.0);

export interface BoardState {
	cols: int32;
	rows: int32;
	lit: boolean[];
	tiles: Node2D[];
	edges: Node2D[];
	tileW: float32;
	tileH: float32;
}

export function boardState(cols: int32, rows: int32): BoardState {
	const lit: boolean[] = [];
	for (let i: int32 = 0 as int32; i < cols * rows; i++) lit.push(false);
	return { cols, rows, lit, tiles: [], edges: [], tileW: 0.0, tileH: 0.0 };
}

export function boardScene(b: BoardState): Scene {
	const s = scene(rgba(0.07, 0.08, 0.11, 1.0));
	for (let i: int32 = 0 as int32; i < b.cols * b.rows; i++) {
		const t = rect(1.0, 1.0, TILE_OFF);
		b.tiles.push(t);
		s.add(t);
	}
	for (let i = 0; i < 4; i++) {
		const e = rect(1.0, 1.0, EDGE_COLOR);
		b.edges.push(e);
		s.add(e);
	}
	return s;
}

export function layoutBoard(b: BoardState, w: float32, h: float32): void {
	b.tileW = (w - 2.0 * MARGIN - ((b.cols - 1) as float32) * GAP) / (b.cols as float32);
	b.tileH = (h - 2.0 * MARGIN - ((b.rows - 1) as float32) * GAP) / (b.rows as float32);
	for (let i: int32 = 0 as int32; i < b.cols * b.rows; i++) {
		const t = b.tiles[i];
		const col: int32 = i % b.cols;
		const row: int32 = (i / b.cols) as int32;
		t.at(MARGIN + (col as float32) * (b.tileW + GAP), MARGIN + (row as float32) * (b.tileH + GAP));
		t.w = Math.max(b.tileW, 0.0);
		t.h = Math.max(b.tileH, 0.0);
		t.color = b.lit[i] ? TILE_ON : TILE_OFF;
	}
	placeEdge(b.edges[0], 0.0, 0.0, w, EDGE);
	placeEdge(b.edges[1], 0.0, h - EDGE, w, EDGE);
	placeEdge(b.edges[2], 0.0, 0.0, EDGE, h);
	placeEdge(b.edges[3], w - EDGE, 0.0, EDGE, h);
}

function placeEdge(e: Node2D, x: float32, y: float32, w: float32, h: float32): void {
	e.at(x, y);
	e.w = w;
	e.h = h;
}

export function toggleTileAt(b: BoardState, x: float32, y: float32): boolean {
	if (b.tileW <= 0.0 || b.tileH <= 0.0) return false;
	const cx: float32 = x - MARGIN;
	const cy: float32 = y - MARGIN;
	if (cx < 0.0 || cy < 0.0) return false;
	const col: int32 = (cx / (b.tileW + GAP)) as int32;
	const row: int32 = (cy / (b.tileH + GAP)) as int32;
	if (col >= b.cols || row >= b.rows) return false;
	if (cx - (col as float32) * (b.tileW + GAP) > b.tileW) return false;
	if (cy - (row as float32) * (b.tileH + GAP) > b.tileH) return false;
	const i: int32 = row * b.cols + col;
	b.lit[i] = !b.lit[i];
	return true;
}

export interface OverlayState {
	clicks: int32;
	x: float32;
	y: float32;
	panel: Node2D;
	bars: Node2D[];
}

export function overlayState(): OverlayState {
	return { clicks: 0 as int32, x: 0.0, y: 0.0, panel: rect(PANEL_W, PANEL_H, rgba(0.85, 0.30, 0.40, 0.92)), bars: [] };
}

export function overlayScene(o: OverlayState): Scene {
	const s = scene(rgba(0.0, 0.0, 0.0, 0.0));
	const barW: float32 = (PANEL_W - 2.0 * GAP) / (BAR_SLOTS as float32);
	for (let i: int32 = 0 as int32; i < BAR_SLOTS; i++) {
		const bar = rect(barW - 4.0, PANEL_H - 2.0 * GAP, rgba(1.0, 1.0, 1.0, 0.9)).at(GAP + (i as float32) * barW, GAP);
		o.bars.push(bar);
		o.panel.addChild(bar);
	}
	s.add(o.panel);
	return s;
}

export function layoutOverlay(o: OverlayState, w: float32, h: float32): void {
	o.x = w - PANEL_W - MARGIN;
	o.y = MARGIN;
	o.panel.at(o.x, o.y);
	const shown: int32 = o.clicks % (BAR_SLOTS + 1);
	for (let i: int32 = 0 as int32; i < BAR_SLOTS; i++) o.bars[i].visible = i < shown;
}

export function overlayHit(o: OverlayState, x: float32, y: float32): boolean {
	return x >= o.x && x < o.x + PANEL_W && y >= o.y && y < o.y + PANEL_H;
}

export function bumpOverlay(o: OverlayState): void {
	o.clicks = o.clicks + (1 as int32);
}
