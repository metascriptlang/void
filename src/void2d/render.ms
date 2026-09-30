// void2d rendering — sync (transform cache + content bounds), draw (dispatch + cull + filter),
// getBounds. Extracted from node.ms so each file has one responsibility.

import {
	Scene2D, NodeRef, DrawKind, Changed, Content2D, GraphicsMesh, Scroll2D, TileCell, NO_SLOT,
	NO_NODE_2D, Enclosure, LaneFrame,
} from "./node";
import {
	DisplayList,
	currentList,
	listSerial,
	PaintIndex,
	PaintState,
	recordPaint,
	markPaintState,
	paintStateOf,
	paintStartOf,
	paintEndOf,
	saveRange,
	noteRange,
	copyPainted,
	limitWrites,
	unlimitWrites,
	layLanes,
	lanesReorderable,
	laneSourceHolding,
	laneOutputOf,
	laneOffsetOf,
	laneSourceOffsetOf,
	commandField,
	commandView,
	commandCount,
	targetCommandCount,
	Pipeline,
	BreakReason,
	NO_EFFECT,
	CMD_EFFECT,
	CMD_VERTEX_OFFSET,
	CMD_INSTANCE_OFFSET,
	CMD_BREAK,
	CMD_BLEND,
	CMD_SAMPLER,
} from "./displayList";
import {
	fillQuad,
	drawSpriteAffine,
	beginSprites,
	appendSprite,
	rewriteSprite,
	spriteInstancingAvailable,
	drawUiInstance,
	uiInstancingAvailable,
	imageQuad,
	imageQuadUV,
	drawMesh,
	drawMeshRange,
	setEffect,
	setGradientEffect,
	setSampler,
	pushClip,
	popClip,
	clipIntersectsQuad,
	glyphPageView,
	beginTarget,
	endTarget,
	blurPass,
	allocRenderTarget,
	rtViewId,
	currentRenderScale,
	paintIndex,
	resumePaint,
	continuesLike,
	continueAfter,
	carried,
	enterScope,
	leaveScope,
	inScope,
	splitRun,
	closeLaneRun,
	restoreLaneRun,
	reopenLast,
} from "./draw";
import { InstanceMode, uiInstance } from "./instance";
import {
	NO_LABEL_TEXT,
	shapeLabel,
	placeLabel,
	firstGlyphPageHandle,
	glyphPageHandle,
	markGlyphPageDrawn,
	labelTexts,
	LabelText,
	Decoration,
	DecorationKind,
	CURSOR_WIDTH,
	NO_CURSOR,
	cursorShown,
	labelLines,
} from "./labelText";
import {
	TextLayout,
	TextStyle,
	LineBox,
	LineOptions,
	TextRun,
	PLAIN_LINES,
	NO_GLYPH,
	NO_RUN,
	shapeText,
	wrapText,
} from "./textLayout";
import { GlyphPage, NO_GLYPH_PAGE } from "./glyphAtlas";
import { glyphInkBox } from "./face";
import {
	Vec2,
	Color,
	Tile,
	Transform2D,
	Bounds2D,
	Filter,
	FilterKind,
	BlendMode,
	Smooth,
	vec2,
	rgba,
	tile,
	trs2d,
	inverse2d,
	emptyBounds,
} from "./types";
import { colorMatrixAlphaOnly } from "./effect";
import { NO_BOX_STYLE, BorderStyle, boxStyles } from "./boxStyle";
import { axisAligned, snapEdge, snapOffset, snapBoxEdges, snapStroke } from "./snap";
import {
	GraphicsOpKind, GRAPHICS_OP_FLOATS, GFX_OP_KIND, GFX_OP_VERTEX_OFFSET,
	GFX_OP_VERTEX_COUNT, GFX_OP_SPACE, GFX_OP_DITHER, GFX_OP_MIDDLE,
	GFX_OP_COLOR0, GFX_OP_COLOR1, GFX_OP_COLOR2, GFX_OP_PARAMS,
} from "./graphics";
import { NO_IMAGE_STYLE, imageStyles, fitImage } from "./imageStyle";

function fmin4(a: float32, b: float32, c: float32, d: float32): float32 {
	let m: float32 = a;
	if (b < m) { m = b; }
	if (c < m) { m = c; }
	if (d < m) { m = d; }
	return m;
}

function fmax4(a: float32, b: float32, c: float32, d: float32): float32 {
	let m: float32 = a;
	if (b > m) { m = b; }
	if (c > m) { m = c; }
	if (d > m) { m = d; }
	return m;
}

const SELECTION_RADIUS: float32 = 2.0;
const SELECTION_GLOOP: float32 = 8.0;

function visualTile(s: Scene2D, i: int32): Tile {
	if (s.kinds[i] === DrawKind.Anim) {
		const row: int32 = s.payloads[i];
		const len: int32 = s.anims[row].frames.length as int32;
		if (len > 0) {
			const index: int32 = ((s.anims[row].clock * s.anims[row].fps) as int32) % len;
			return s.anims[row].frames[index];
		}
	}
	return s.contents[i].tile;
}
function showsEditing(s: Scene2D, i: int32): boolean {
	if (s.payloads[i] == NO_LABEL_TEXT) { return false; }
	const text: LabelText = labelTexts[s.payloads[i]];
	return text.selectionLength > 0 || text.cursorIndex != NO_CURSOR;
}

function tileOffsetX(t: Tile, width: float32): float32 {
	return t.w != 0.0 ? t.dx * width / t.w : t.dx;
}

function tileOffsetY(t: Tile, height: float32): float32 {
	return t.h != 0.0 ? t.dy * height / t.h : t.dy;
}

function cellMatrix(c: TileCell): Transform2D {
	if (c.rotation == 0.0) {
		return { a: c.scaleX, b: 0.0, c: 0.0, d: c.scaleY, tx: c.x, ty: c.y };
	}
	return trs2d(c.x, c.y, c.rotation, c.scaleX, c.scaleY);
}

function tileBounds(s: Scene2D, i: int32): void {
	const p: int32 = s.payloads[i];
	if (!s.tileGroups[p].boundsStale) { return; }
	const cells: Span<TileCell> = s.tileCells[p];
	let xMin: float32 = 1e30;
	let yMin: float32 = 1e30;
	let xMax: float32 = -1e30;
	let yMax: float32 = -1e30;
	for (let k: int32 = 0; k < (cells.length as int32); k++) {
		const m: Transform2D = cellMatrix(cells[k]);
		const t: Tile = cells[k].tile;
		const a = vec2(t.dx, t.dy) * m;
		const b = vec2(t.dx + t.w, t.dy) * m;
		const c = vec2(t.dx + t.w, t.dy + t.h) * m;
		const d = vec2(t.dx, t.dy + t.h) * m;
		const x0: float32 = fmin4(a.x, b.x, c.x, d.x);
		const y0: float32 = fmin4(a.y, b.y, c.y, d.y);
		const x1: float32 = fmax4(a.x, b.x, c.x, d.x);
		const y1: float32 = fmax4(a.y, b.y, c.y, d.y);
		if (x0 < xMin) { xMin = x0; }
		if (y0 < yMin) { yMin = y0; }
		if (x1 > xMax) { xMax = x1; }
		if (y1 > yMax) { yMax = y1; }
	}
	if (xMin > xMax) { xMin = 0.0; xMax = 0.0; yMin = 0.0; yMax = 0.0; }
	s.bounds[i] = { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax };
	s.tileGroups[p].boundsStale = false;
}


function localBounds(s: Scene2D, i: int32, query: boolean): Bounds2D {
	const kind: DrawKind = s.kinds[i];
	const payload: int32 = s.payloads[i];
	const w: float32 = s.contents[i].w;
	const h: float32 = s.contents[i].h;
	if (kind === DrawKind.Label && !query && showsEditing(s, i)) {
		const lineSpacing: float32 = labelTexts[payload].style.lineSpacing;
		const leading: float32 = lineSpacing > 0.0 ? lineSpacing * 0.5 : 0.0;
		return {
			xMin: s.bounds[i].xMin - SELECTION_GLOOP, yMin: s.bounds[i].yMin - leading,
			xMax: labelTexts[payload].rowsXMax + SELECTION_GLOOP, yMax: s.bounds[i].yMax + leading,
		};
	}
	if (kind === DrawKind.Label && payload != NO_LABEL_TEXT &&
		(labelTexts[payload].runs.length as int32) > 0) {
		return {
			xMin: s.bounds[i].xMin, yMin: s.bounds[i].yMin,
			xMax: labelTexts[payload].rowsXMax, yMax: s.bounds[i].yMax,
		};
	}
	if (kind === DrawKind.TileGroup) {
		tileBounds(s, i);
		return s.bounds[i];
	}
	if (kind === DrawKind.Graphics || kind === DrawKind.Label) {
		return s.bounds[i];
	}
	if (kind === DrawKind.Selection) {
		return { xMin: -SELECTION_GLOOP, yMin: 0.0, xMax: w + SELECTION_GLOOP, yMax: h };
	}
	if (kind === DrawKind.Sprite || kind === DrawKind.Anim || kind === DrawKind.ScaleGrid) {
		const t: Tile = visualTile(s, i);
		const dx: float32 = tileOffsetX(t, w);
		const dy: float32 = tileOffsetY(t, h);
		return { xMin: dx, yMin: dy, xMax: dx + w, yMax: dy + h };
	}
	return { xMin: 0.0, yMin: 0.0, xMax: w, yMax: h };
}

function boxRenderBounds(s: Scene2D, i: int32, world: Transform2D, lb: Bounds2D): Bounds2D {
	if (s.kinds[i] !== DrawKind.Rect) { return lb; }
	let xMin: float32 = lb.xMin;
	let yMin: float32 = lb.yMin;
	let xMax: float32 = lb.xMax;
	let yMax: float32 = lb.yMax;
	const aligned: boolean = axisAligned(world.a, world.b, world.c, world.d);
	const scale: float32 = currentRenderScale();
	let deviceAX: float32 = 0.0;
	let deviceDX: float32 = 0.0;
	if (aligned) {
		deviceAX = world.a * scale;
		deviceDX = world.d * scale;
		const snapped = snapBoxEdges(
			xMin, yMin, xMax - xMin, yMax - yMin,
			deviceAX, world.tx * scale, deviceDX, world.ty * scale,
		);
		xMin = snapped[0];
		yMin = snapped[1];
		xMax = xMin + snapped[2];
		yMax = yMin + snapped[3];
	}
	if (s.payloads[i] == NO_BOX_STYLE) {
		return { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax };
	}
	const st = boxStyles[s.payloads[i]];
	if (st.shadowColor.a > 0.0 && !st.shadowInset) {
		let offsetX: float32 = st.shadowOffsetX;
		let offsetY: float32 = st.shadowOffsetY;
		if (aligned) {
			offsetX = snapOffset(offsetX * deviceAX) / deviceAX;
			offsetY = snapOffset(offsetY * deviceDX) / deviceDX;
		}
		const absX: float32 = offsetX < 0.0 ? -offsetX : offsetX;
		const absY: float32 = offsetY < 0.0 ? -offsetY : offsetY;
		const mx: float32 = 3.0 * st.shadowBlur + absX;
		const my: float32 = 3.0 * st.shadowBlur + absY;
		xMin = xMin - mx;
		yMin = yMin - my;
		xMax = xMax + mx;
		yMax = yMax + my;
	}
	return { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax };
}

function renderScaleGrid(s: Scene2D, i: int32, world: Transform2D, col: Color): void {
	const grid: Content2D = s.contents[i];
	const blend: BlendMode = s.paints[i].blend;
	const t = grid.tile;
	const srcW: float32 = t.w;
	const srcH: float32 = t.h;
	if (srcW <= 0.0 || srcH <= 0.0) { return; }
	const ox: float32 = tileOffsetX(t, grid.w);
	const oy: float32 = tileOffsetY(t, grid.h);
	const sx: float32[4] = [0.0, grid.borderL, srcW - grid.borderR, srcW];
	const sy: float32[4] = [0.0, grid.borderT, srcH - grid.borderB, srcH];
	const dx: float32[4] = [ox, ox + grid.borderL, ox + grid.w - grid.borderR, ox + grid.w];
	const dy: float32[4] = [oy, oy + grid.borderT, oy + grid.h - grid.borderB, oy + grid.h];
	const du: float32 = t.u1 - t.u0;
	const dv: float32 = t.v1 - t.v0;
	for (let cj: int32 = 0; cj < 3; cj++) {
		for (let ci: int32 = 0; ci < 3; ci++) {
			const u0: float32 = t.u0 + (sx[ci] / srcW) * du;
			const u1: float32 = t.u0 + (sx[ci + 1] / srcW) * du;
			const v0: float32 = t.v0 + (sy[cj] / srcH) * dv;
			const v1: float32 = t.v0 + (sy[cj + 1] / srcH) * dv;
			const a = vec2(dx[ci], dy[cj]) * world;
			const b = vec2(dx[ci + 1], dy[cj]) * world;
			const c = vec2(dx[ci + 1], dy[cj + 1]) * world;
			const d = vec2(dx[ci], dy[cj + 1]) * world;
			imageQuadUV(t.view, u0, v0, u1, v1, a, b, c, d, col, blend);
		}
	}
}

function shapeIfChanged(s: Scene2D, i: int32): void {
	const payload: int32 = s.payloads[i];
	const shaped: LabelText = labelTexts[payload];
	if (!shaped.stale) { return; }
	shapeLabel(payload, shaped.text, shaped.style);
	let xMin: float32 = 0.0;
	let xMax: float32 = 0.0;
	for (const line of shaped.layout.lines) {
		if (line.x < xMin) { xMin = line.x; }
		if (line.x + line.width > xMax) { xMax = line.x + line.width; }
	}
	let yMin: float32 = 0.0;
	let yMax: float32 = shaped.layout.height;
	for (const g of shaped.layout.glyphs) {
		if (g.glyph == NO_GLYPH) { continue; }
		const [left, top, right, bottom] = glyphInkBox(g.face, g.glyph, g.size);
		if (right <= left || bottom <= top) { continue; }
		const baseline: float32 = shaped.layout.lines[g.line].baseline;
		if (g.x + left < xMin) { xMin = g.x + left; }
		if (g.x + right > xMax) { xMax = g.x + right; }
		if (baseline + top < yMin) { yMin = baseline + top; }
		if (baseline + bottom > yMax) { yMax = baseline + bottom; }
	}
	let rowsXMax: float32 = xMax;
	for (const line of shaped.layout.lines) {
		const end: float32 = shaped.layout.rowEnd(line);
		if (end > rowsXMax) { rowsXMax = end; }
	}
	s.bounds[i] = { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax };
	shaped.rowsXMax = rowsXMax;
	shaped.stale = false;
}

function meshBounds(s: Scene2D, i: int32): void {
	const m: GraphicsMesh = s.meshes[s.payloads[i]];
	if (!m.stale) { return; }
	let xMin: float32 = 1e30;
	let yMin: float32 = 1e30;
	let xMax: float32 = -1e30;
	let yMax: float32 = -1e30;
	for (let mi: int32 = 0; mi + 8 <= m.mesh.length as int32; mi += 8) {
		const mx: float32 = m.mesh[mi];
		const my: float32 = m.mesh[mi + 1];
		if (mx < xMin) { xMin = mx; }
		if (my < yMin) { yMin = my; }
		if (mx > xMax) { xMax = mx; }
		if (my > yMax) { yMax = my; }
	}
	if (xMin > xMax) { xMin = 0.0; xMax = 0.0; yMin = 0.0; yMax = 0.0; }
	s.bounds[i] = { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax };
	m.vertexCount = (m.mesh.length as int32) / 8;
	m.stale = false;
}

function syncRow(s: Scene2D, i: int32, parentWorld: Transform2D, parentChanged: boolean): void {
	const worldChanged: boolean = parentChanged || s.changed[i].has(Changed.Local);
	if (worldChanged) {
		s.worlds[i] = parentWorld * s.localMatrices[i];
	}
	if (s.kinds[i] === DrawKind.Label) { shapeIfChanged(s, i); }
	if (s.kinds[i] === DrawKind.Graphics) { meshBounds(s, i); }
	const inner: Transform2D = s.childWorld(i);
	for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
		syncRow(s, s.children[i][k], inner, worldChanged);
	}
}

export function sync(this n: NodeRef, parentWorld: Transform2D, parentChanged: boolean): void {
	syncRow(n.scene, n.liveRow("sync"), parentWorld, parentChanged);
}

export function syncOrder(this s: Scene2D, view: Transform2D, viewChanged: boolean): void {
	for (let p: int32 = 0; p < (s.order.length as int32); p++) {
		const i: int32 = s.order[p];
		const up: int32 = s.parents[i];
		const parentMoved: boolean = p == 0 ? viewChanged : s.moved[up];
		const moved: boolean = parentMoved || s.changed[i].has(Changed.Local);
		if (moved) {
			s.worlds[i] = (p == 0 ? view : s.childWorld(up)) * s.localMatrices[i];
		}
		s.moved[i] = moved;
		if (s.kinds[i] === DrawKind.Label) { shapeIfChanged(s, i); }
		if (s.kinds[i] === DrawKind.Graphics) { meshBounds(s, i); }
	}
}
let imageEffectRejectedReported: boolean = false;
const deviceGrid: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);

function sharedGlyphView(): uint32 {
	return glyphPageView(firstGlyphPageHandle());
}

function faded(this c: Color, alpha: float32): Color {
	return rgba(c.r, c.g, c.b, c.a * alpha);
}

function tinted(this c: Color, by: Color): Color {
	return rgba(c.r * by.r, c.g * by.g, c.b * by.b, c.a * by.a);
}

// A run segment's box in local units, its edges on device pixels when the label is
// axis-aligned; `thickness` > 0 makes the height a stroke of at least one device pixel.
export function segmentBox(
	x0: float32,
	x1: float32,
	y: float32,
	height: float32,
	stroke: boolean,
	world: Transform2D,
	scale: float32,
): [float32, float32, float32, float32] {
	if (!axisAligned(world.a, world.b, world.c, world.d)) { return [x0, y, x1 - x0, height]; }
	const a: float32 = world.a * scale;
	const d: float32 = world.d * scale;
	const tx: float32 = world.tx * scale;
	const ty: float32 = world.ty * scale;
	const left: float32 = snapEdge(a * x0 + tx);
	const right: float32 = snapEdge(a * x1 + tx);
	const top: float32 = snapEdge(d * y + ty);
	const bottom: float32 = stroke ? top + snapStroke(height * d) : snapEdge(d * (y + height) + ty);
	return [(left - tx) / a, (top - ty) / d, (right - left) / a, (bottom - top) / d];
}

function emitRunBox(
	blend: BlendMode,
	world: Transform2D,
	box: [float32, float32, float32, float32],
	fill: Color,
): void {
	const [x, y, w, h] = box;
	if (w <= 0.0 || h <= 0.0) { return; }
	const origin = vec2(x, y) * world;
	drawUiInstance(sharedGlyphView(), blend,
		uiInstance(InstanceMode.Box, world, origin.x, origin.y, w, h, fill));
}

function emitRunLine(
	blend: BlendMode,
	world: Transform2D,
	box: [float32, float32, float32, float32],
	wavy: boolean,
	fill: Color,
): void {
	const [x, y, w, h] = box;
	if (w <= 0.0 || h <= 0.0) { return; }
	const quadY: float32 = wavy ? y - h : y;
	const quadH: float32 = wavy ? h * 3.0 : h;
	const origin = vec2(x, quadY) * world;
	drawUiInstance(sharedGlyphView(), blend, {
		...uiInstance(InstanceMode.Underline, world, origin.x, origin.y, w, quadH, fill),
		borders: [h, wavy ? 1.0 : 0.0, 0.0, 0.0],
	});
}

function emitDecorations(
	blend: BlendMode,
	text: LabelText,
	world: Transform2D,
	na: float32,
	backgrounds: boolean,
): void {
	const scale: float32 = currentRenderScale();
	for (let i = 0; i < (text.decorations.length as int32); i++) {
		const d: Decoration = text.decorations[i];
		const background: boolean = d.kind == DecorationKind.Background;
		if (background != backgrounds) { continue; }
		const box = segmentBox(d.x, d.x + d.w, d.y, d.h, !background, world, scale);
		if (background) {
			emitRunBox(blend, world, box, d.color.faded(na));
		} else {
			const wavy: boolean = d.kind == DecorationKind.WavyUnderline;
			emitRunLine(blend, world, box, wavy, d.color.faded(na));
		}
	}
}

const EMPTY_ROW_WIDTH: float32 = 4.0;

function rowEnd(this layout: TextLayout, line: LineBox): float32 {
	if (line.glyphCount == 0) { return line.x; }
	let right: float32 = line.x;
	for (let k = line.firstGlyph + line.glyphCount - 1; k >= line.firstGlyph; k--) {
		const edge: float32 = layout.glyphs[k].x + layout.glyphs[k].advance;
		if (edge > right) { right = edge; }
		if (layout.glyphs[k].clusterStart) { break; }
	}
	return right;
}

function xOnRow(this layout: TextLayout, line: LineBox, index: int32): float32 {
	const end: int32 = line.firstGlyph + line.glyphCount;
	for (let k = line.firstGlyph; k < end; k++) {
		if (layout.glyphs[k].index >= index) { return layout.glyphs[k].x; }
	}
	return layout.rowEnd(line);
}

// The selected span of one line, [x0, x1] in local units, or x1 < x0 when the line holds none of
// it. A selected line break shows as a short tail, as an editor draws it.
function selectedRow(this text: LabelText, li: int32): [float32, float32] {
	const count: int32 = text.layout.lines.length as int32;
	if (li < 0 || li >= count) { return [0.0, -1.0]; }
	const start: int32 = text.selectionStart;
	const end: int32 = start + text.selectionLength;
	const line: LineBox = text.layout.lines[li];
	const owned: int32 = li + 1 < count ? text.layout.lines[li + 1].indexStart : line.indexEnd;
	if (end <= line.indexStart || start >= owned || text.selectionLength <= 0) {
		return [0.0, -1.0];
	}
	const lineEnd: float32 = text.layout.rowEnd(line);
	const x0: float32 = start <= line.indexStart ? line.x : text.layout.xOnRow(line, start);
	let x1: float32 = end >= line.indexEnd ? lineEnd : text.layout.xOnRow(line, end);
	if (end > line.indexEnd && owned > line.indexEnd) { x1 = x1 + EMPTY_ROW_WIDTH; }
	return [x0, x1];
}

// Makepad's selection (draw_selection.rs:5-113): a quad per row carrying its neighbours' x and
// width, unioned by smooth-min in the fragment shader, so a ragged edge is filleted.
function emitSelection(blend: BlendMode, text: LabelText, world: Transform2D, na: float32): void {
	const fill: Color = text.selectionColor.faded(na);
	for (let li = 0; li < (text.layout.lines.length as int32); li++) {
		const [x0, x1] = text.selectedRow(li);
		if (x1 <= x0) { continue; }
		const [p0, p1] = text.selectedRow(li - 1);
		const [q0, q1] = text.selectedRow(li + 1);
		const line: LineBox = text.layout.lines[li];
		const w: float32 = x1 - x0;
		const leading: float32 = text.style.lineSpacing * 0.5;
		const h: float32 = line.height + text.style.lineSpacing;
		const origin = vec2(x0 - SELECTION_GLOOP, line.top - leading) * world;
		drawUiInstance(sharedGlyphView(), blend, {
			...uiInstance(
				InstanceMode.Selection, world, origin.x, origin.y, w + SELECTION_GLOOP * 2.0, h, fill,
			),
			borders: [w * 0.5, h * 0.5, SELECTION_RADIUS, SELECTION_GLOOP],
			params1: [
				p1 > p0 ? p0 - x0 : 0.0, p1 > p0 ? p1 - p0 : 0.0,
				q1 > q0 ? q0 - x0 : 0.0, q1 > q0 ? q1 - q0 : 0.0,
			],
		});
	}
}

// Ghostty's caret (GHOSTTY.md:90): an instance of its own, so a blink rewrites no glyph.
function emitCaret(blend: BlendMode, text: LabelText, world: Transform2D, na: float32): void {
	if (text.cursorIndex == NO_CURSOR || (text.layout.lines.length as int32) == 0) { return; }
	const line: LineBox = text.layout.lineBoxAt(text.cursorIndex);
	const x: float32 = text.layout.xForIndex(text.cursorIndex);
	const scale: float32 = currentRenderScale();
	let box: [float32, float32, float32, float32] = [x, line.top, CURSOR_WIDTH, line.height];
	if (axisAligned(world.a, world.b, world.c, world.d)) {
		const a: float32 = world.a * scale;
		const snapped = segmentBox(x, x + CURSOR_WIDTH, line.top, line.height, false, world, scale);
		box = [snapped[0], snapped[1], snapStroke(CURSOR_WIDTH * a) / a, snapped[3]];
	}
	emitRunBox(blend, world, box, text.cursorColor.faded(cursorShown(text) ? na : 0.0));
}

let refusedLabelEditing: int32 = 0;
const LABEL_EDITING_EFFECT_REFUSED: string =
	"void2d: text runs, a selection and a caret cannot be combined with colorMatrix, " +
	"colorAdd, or colorKey";

export function labelEditingRefusals(): int32 {
	return refusedLabelEditing;
}

function emitLabel(s: Scene2D, i: int32, world: Transform2D, col: Color, na: float32): void {
	const payload: int32 = s.payloads[i];
	if (payload == NO_LABEL_TEXT) { return; }
	const blend: BlendMode = s.paints[i].blend;
	const scale: float32 = currentRenderScale();
	const text = placeLabel(payload, world, scale);
	if (!text.placedValid) { s.retry.push(i); }
	const editing: boolean = (text.runs.length as int32) > 0 || text.selectionLength > 0 ||
		text.cursorIndex != NO_CURSOR;
	if (editing && !uiInstancingAvailable()) {
		if (refusedLabelEditing == 0) { console.log(LABEL_EDITING_EFFECT_REFUSED); }
		refusedLabelEditing = refusedLabelEditing + 1;
	}
	const styled: boolean = (text.runs.length as int32) > 0 && uiInstancingAvailable();
	if (styled) { emitDecorations(blend, text, world, na, true); }
	if (text.selectionLength > 0 && uiInstancingAvailable()) {
		emitSelection(blend, text, world, na);
	}
	const originX: float32 = Math.floor(world.tx * scale) as float32;
	const originY: float32 = Math.floor(world.ty * scale) as float32;
	const instanced: boolean = uiInstancingAvailable();
	const exact: boolean = text.pixelExact;
	const affine: Transform2D = exact ? deviceGrid : world;
	let viewPage: GlyphPage = NO_GLYPH_PAGE;
	let view: uint32 = 0;
	for (const p of text.placed) {
		if (p.w <= 0.0 || p.h <= 0.0) { continue; }
		if (p.page != viewPage) {
			view = glyphPageView(glyphPageHandle(p.page));
			viewPage = p.page;
			markGlyphPageDrawn(p.page);
		}
		let x: float32 = 0.0;
		let y: float32 = 0.0;
		let w: float32 = p.w;
		let h: float32 = p.h;
		if (exact) {
			x = (originX + p.x) / scale;
			y = (originY + p.y) / scale;
			w = p.w / scale;
			h = p.h / scale;
		} else {
			x = world.a * p.x + world.c * p.y + world.tx;
			y = world.b * p.x + world.d * p.y + world.ty;
		}
		const fill: Color = styled && p.run != NO_RUN ? text.runs[p.run].color.tinted(col) : col;
		if (instanced) {
			drawUiInstance(view, blend, {
				...uiInstance(InstanceMode.Glyph, affine, x, y, w, h, fill),
				uvRadii: [p.u0, p.v0, p.u1, p.v1],
			});
		} else {
			const rx: float32 = affine.a * w;
			const ry: float32 = affine.b * w;
			const dx: float32 = affine.c * h;
			const dy: float32 = affine.d * h;
			imageQuadUV(view, p.u0, p.v0, p.u1, p.v1,
				vec2(x, y),
				vec2(x + rx, y + ry),
				vec2(x + rx + dx, y + ry + dy),
				vec2(x + dx, y + dy),
				fill, blend);
		}
	}
	if (styled) { emitDecorations(blend, text, world, na, false); }
	if (uiInstancingAvailable()) { emitCaret(blend, text, world, na); }
}
let textPrimitiveEffectRejectedReported: boolean = false;
const TEXT_PRIMITIVE_EFFECT_REFUSED: string =
	"void2d: underline and selection cannot be combined with colorMatrix, colorAdd, or colorKey";
let boxEffectRejectedReported: boolean = false;


function emitStyledImage(
	s: Scene2D,
	i: int32,
	t: Tile,
	world: Transform2D,
	col: Color,
	sizeX: float32,
	sizeY: float32,
	lbMin: Vec2,
): boolean {
	const styleIndex: int32 = s.imageStyleOf(i);
	if (styleIndex == NO_IMAGE_STYLE) { return false; }
	if (!uiInstancingAvailable()) {
		if (!imageEffectRejectedReported) {
			console.log("void2d: an image style cannot be combined with colorMatrix, colorAdd, or colorKey");
			imageEffectRejectedReported = true;
		}
		return true;
	}
	const style = imageStyles[styleIndex];
	const fitted = fitImage(t, sizeX, sizeY, style.fit);
	if (fitted.w <= 0.0 || fitted.h <= 0.0) { return true; }
	const origin = vec2(lbMin.x + fitted.x, lbMin.y + fitted.y) * world;
	drawUiInstance(t.view, s.paints[i].blend, {
		...uiInstance(InstanceMode.Image, world, origin.x, origin.y, fitted.w, fitted.h, col),
		uvRadii: [fitted.u0, fitted.v0, fitted.u1, fitted.v1],
		borders: [
			style.radii.topLeft, style.radii.topRight,
			style.radii.bottomRight, style.radii.bottomLeft,
		],
		params1: [style.grayscale ? 1.0 : 0.0, 0.0, 0.0, 0.0],
	});
	return true;
}

function drawnEnd(s: Scene2D, p: int32): int32 {
	const total: int32 = s.tileCells[p].length as int32;
	const first: int32 = s.tileGroups[p].first;
	const window: int32 = s.tileGroups[p].count;
	return window >= total - first ? total : first + window;
}

function tileTint(c: Color, col: Color): Color {
	return rgba(c.r * col.r, c.g * col.g, c.b * col.b, c.a * col.a);
}

function emitTiles(
	s: Scene2D, i: int32, world: Transform2D, col: Color, blend: BlendMode, instanced: boolean,
): void {
	const p: int32 = s.payloads[i];
	const cells: Span<TileCell> = s.tileCells[p];
	const end: int32 = drawnEnd(s, p);
	let open: boolean = false;
	let view: uint32 = 0;
	for (let k: int32 = s.tileGroups[p].first; k < end; k++) {
		const t: Tile = cells[k].tile;
		const m: Transform2D = world * cellMatrix(cells[k]);
		const tint: Color = tileTint(cells[k].color, col);
		const origin = vec2(t.dx, t.dy) * m;
		if (instanced) {
			if (!open || t.view != view) {
				beginSprites(t.view, blend);
				open = true;
				view = t.view;
			}
			appendSprite(m, origin.x, origin.y, t.w, t.h, t.u0, t.v0, t.u1, t.v1, tint);
		} else {
			imageQuad(
				t, origin, vec2(t.dx + t.w, t.dy) * m, vec2(t.dx + t.w, t.dy + t.h) * m,
				vec2(t.dx, t.dy + t.h) * m, tint, blend,
			);
		}
	}
}

function emitNode(
	s: Scene2D, i: int32, world: Transform2D, na: float32, col: Color,
	tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2, sizeX: float32, sizeY: float32, lbMin: Vec2,
	boxBounds: Bounds2D,
): void {
	const blend: BlendMode = s.paints[i].blend;
	const payload: int32 = s.payloads[i];
	setEffect(s.paints[i].colorMatrix, s.paints[i].colorAdd, s.paints[i].colorKey);
	setSampler(s.paints[i].smooth, s.paints[i].tileWrap);
	// P2: a flat quad becomes one instance instead of six transformed vertices, whenever the
	// program can express it. `tl` is the origin because it is what the node's local
	// (xMin,yMin) maps to, and the shader rebuilds the other three corners from the same
	// affine - so a rotated quad is the same pixels by construction and not by a second code
	// path.
	//
	// A Rect goes to the UNIFIED UI pipeline and a Sprite or an Anim to the flat sprite one,
	// and that is the line guardrail 8 draws: a box is a UI primitive whose edges are covered
	// analytically, a sheet quad is a sprite that never runs SDF maths. benchSprites is the
	// scene that measures the second half of that sentence.
	const instanced: boolean = spriteInstancingAvailable();
	match (s.kinds[i]) {
		DrawKind.Rect => {
			if (!uiInstancingAvailable() && payload != NO_BOX_STYLE) {
				if (!boxEffectRejectedReported) {
					console.log(
						"void2d: a box style cannot be combined with colorMatrix, colorAdd, " +
						"or colorKey",
					);
					boxEffectRejectedReported = true;
				}
				return;
			}
			if (uiInstancingAvailable()) {
				let radiusTL: float32 = 0.0;
				let radiusTR: float32 = 0.0;
				let radiusBR: float32 = 0.0;
				let radiusBL: float32 = 0.0;
				let borderL: float32 = 0.0;
				let borderT: float32 = 0.0;
				let borderR: float32 = 0.0;
				let borderB: float32 = 0.0;
				let edge: Color = transparent;
				let borderStyle: float32 = 0.0;
				if (payload != NO_BOX_STYLE) {
					const styleIndex: int32 = payload;
					radiusTL = boxStyles[styleIndex].radii.topLeft;
					radiusTR = boxStyles[styleIndex].radii.topRight;
					radiusBR = boxStyles[styleIndex].radii.bottomRight;
					radiusBL = boxStyles[styleIndex].radii.bottomLeft;
					borderL = boxStyles[styleIndex].borders.left;
					borderT = boxStyles[styleIndex].borders.top;
					borderR = boxStyles[styleIndex].borders.right;
					borderB = boxStyles[styleIndex].borders.bottom;
					const source: Color = boxStyles[styleIndex].borderColor;
					edge = rgba(source.r, source.g, source.b, source.a * na);
					const dashed: boolean =
						boxStyles[styleIndex].borderStyle === BorderStyle.Dashed;
					borderStyle = dashed ? 1.0 : 0.0;
				}
				// cardOneInstance: a shadowed box is ONE instance carrying shadow, fill and
				// border. The visible box is snapped before its quad is inflated, otherwise a
				// fractional shadow margin moves the reconstructed fill edge off the device grid.
				const shadowOn: boolean = payload != NO_BOX_STYLE
					&& boxStyles[payload].shadowColor.a > 0.0;
				const rendered = boxBounds;
				const qOrigin = vec2(rendered.xMin, rendered.yMin) * world;
				const qx: float32 = qOrigin.x;
				const qy: float32 = qOrigin.y;
				const qw: float32 = rendered.xMax - rendered.xMin;
				const qh: float32 = rendered.yMax - rendered.yMin;
				let shadowColor: Color = transparent;
				let sp0: float32 = 0.0;
				let sp1: float32 = 0.0;
				let sp2: float32 = 0.0;
				let sp3: float32 = 0.0;
				const aligned: boolean = axisAligned(world.a, world.b, world.c, world.d);
				const scale: float32 = currentRenderScale();
				let deviceAX: float32 = 0.0;
				let deviceDX: float32 = 0.0;
				if (aligned) {
					deviceAX = world.a * scale;
					deviceDX = world.d * scale;
					borderL = snapStroke(borderL * deviceAX) / deviceAX;
					borderR = snapStroke(borderR * deviceAX) / deviceAX;
					borderT = snapStroke(borderT * deviceDX) / deviceDX;
					borderB = snapStroke(borderB * deviceDX) / deviceDX;
				}
				if (shadowOn) {
					const st = boxStyles[payload];
					const sigma: float32 = st.shadowBlur;
					let offsetX: float32 = st.shadowOffsetX;
					let offsetY: float32 = st.shadowOffsetY;
					if (aligned) {
						offsetX = snapOffset(offsetX * deviceAX) / deviceAX;
						offsetY = snapOffset(offsetY * deviceDX) / deviceDX;
					}
					sp0 = offsetX;
					sp1 = offsetY;
					sp2 = sigma;
					sp3 = st.shadowInset ? 1.0 : 0.0;
					const sc: Color = st.shadowColor;
					shadowColor = rgba(sc.r, sc.g, sc.b, sc.a * na);
				}
				drawUiInstance(sharedGlyphView(), blend, {
					...uiInstance(InstanceMode.Box, world, qx, qy, qw, qh, col),
					uvRadii: [radiusTL, radiusTR, radiusBR, radiusBL],
					borders: [borderL, borderT, borderR, borderB],
					params: [borderStyle, 0.0, 0.0],
					params1: [sp0, sp1, sp2, sp3],
					border: edge,
					extra: shadowColor,
				});
			} else {
				fillQuad(tl, tr, br, bl, col, blend);
			}
		},
		DrawKind.Sprite => {
			const sheet: Tile = s.contents[i].tile;
			if (!emitStyledImage(s, i, sheet, world, col, sizeX, sizeY, lbMin)) {
				if (instanced) {
					drawSpriteAffine(sheet.view, blend, world, tl.x, tl.y, sizeX, sizeY,
						sheet.u0, sheet.v0, sheet.u1, sheet.v1, col);
				} else {
					imageQuad(sheet, tl, tr, br, bl, col, blend);
				}
			}
		},
		DrawKind.Anim => {
			const len: int32 = s.anims[payload].frames.length as int32;
			if (len > 0) {
				const fi: int32 = ((s.anims[payload].clock * s.anims[payload].fps) as int32) % len;
				const fr = s.anims[payload].frames[fi];
				if (!emitStyledImage(s, i, fr, world, col, sizeX, sizeY, lbMin)) {
					if (instanced) {
						drawSpriteAffine(fr.view, blend, world, tl.x, tl.y, sizeX, sizeY,
							fr.u0, fr.v0, fr.u1, fr.v1, col);
					} else {
						imageQuad(fr, tl, tr, br, bl, col, blend);
					}
				}
			}
		},
		DrawKind.Underline => {
			if (uiInstancingAvailable()) {
				drawUiInstance(sharedGlyphView(), blend, {
					...uiInstance(InstanceMode.Underline, world, tl.x, tl.y, sizeX, sizeY, col),
					borders: [s.contents[i].borderL, s.contents[i].borderT, 0.0, 0.0],
				});
			} else if (!textPrimitiveEffectRejectedReported) {
				console.log(TEXT_PRIMITIVE_EFFECT_REFUSED);
				textPrimitiveEffectRejectedReported = true;
			}
		},
		DrawKind.Selection => {
			if (uiInstancingAvailable()) {
				const band: Content2D = s.contents[i];
				drawUiInstance(sharedGlyphView(), blend, {
					...uiInstance(InstanceMode.Selection, world, tl.x, tl.y, sizeX, sizeY, col),
					borders: [band.w * 0.5, band.h * 0.5, SELECTION_RADIUS, SELECTION_GLOOP],
					params1: [band.borderL, band.borderT, band.borderR, band.borderB],
				});
			} else if (!textPrimitiveEffectRejectedReported) {
				console.log(TEXT_PRIMITIVE_EFFECT_REFUSED);
				textPrimitiveEffectRejectedReported = true;
			}
		},
		DrawKind.Label => {
			emitLabel(s, i, world, col, na);
		},
		DrawKind.Graphics => {
			const geometry: GraphicsMesh = s.meshes[payload];
			const ops: float32[] = geometry.records;
			const opTotal: int32 = ops.length as int32;
			if (opTotal == 0) {
				drawMesh(geometry.mesh, geometry.view, blend, world, rgba(1.0, 1.0, 1.0, 1.0), na);
			} else {
				const stride: int32 = GRAPHICS_OP_FLOATS;
				for (let oi: int32 = 0; oi + stride <= opTotal; oi += stride) {
					const kind: int32 = ops[oi + GFX_OP_KIND] as int32;
					const offset: int32 = ops[oi + GFX_OP_VERTEX_OFFSET] as int32;
					const count: int32 = ops[oi + GFX_OP_VERTEX_COUNT] as int32;
					if (kind == GraphicsOpKind.Mesh as int32) {
						setEffect(
							s.paints[i].colorMatrix, s.paints[i].colorAdd, s.paints[i].colorKey,
						);
						drawMeshRange(geometry.mesh, offset, count, geometry.view, blend, world,
							rgba(1.0, 1.0, 1.0, 1.0), na);
					} else {
						const c0: Color = rgba(
							ops[oi + GFX_OP_COLOR0], ops[oi + GFX_OP_COLOR0 + 1],
							ops[oi + GFX_OP_COLOR0 + 2], ops[oi + GFX_OP_COLOR0 + 3]);
						const c1: Color = rgba(
							ops[oi + GFX_OP_COLOR1], ops[oi + GFX_OP_COLOR1 + 1],
							ops[oi + GFX_OP_COLOR1 + 2], ops[oi + GFX_OP_COLOR1 + 3]);
						const c2: Color = rgba(
							ops[oi + GFX_OP_COLOR2], ops[oi + GFX_OP_COLOR2 + 1],
							ops[oi + GFX_OP_COLOR2 + 2], ops[oi + GFX_OP_COLOR2 + 3]);
						setGradientEffect(
							s.paints[i].colorMatrix, s.paints[i].colorAdd, s.paints[i].colorKey,
							kind, ops[oi + GFX_OP_SPACE] as int32,
							ops[oi + GFX_OP_DITHER] != 0.0, ops[oi + GFX_OP_MIDDLE],
							ops[oi + GFX_OP_PARAMS], ops[oi + GFX_OP_PARAMS + 1],
							ops[oi + GFX_OP_PARAMS + 2], ops[oi + GFX_OP_PARAMS + 3],
							c0, c1, c2);
						drawMeshRange(geometry.mesh, offset, count, 0, blend, world,
							rgba(1.0, 1.0, 1.0, 1.0), na);
					}
				}
			}
		},
		DrawKind.ScaleGrid => {
			renderScaleGrid(s, i, world, col);
		},
		DrawKind.TileGroup => {
			emitTiles(s, i, world, col, blend, instanced);
		},
		DrawKind.Group | DrawKind.Mask => {},
	}
}

// A filter target always starts empty: what is not drawn into it must not composite.
const transparent: Color = rgba(0.0, 0.0, 0.0, 0.0);

// The cap matters: sokol's default pools hold 128 images, 128 views and 128 attachment sets,
// and a render target costs one of each. 16 is far below that and still more filters than
// h2d composes in one frame; past it the filter is skipped and says so once, rather than
// failing inside sokol where the message names no node.
const MAX_POOLED_TARGETS: int32 = 16;
const poolRT: Vec<uint32> = [];
const poolW: Vec<int32> = [];
const poolH: Vec<int32> = [];
let poolOwner: Vec<int32> = [];
let poolSerial: Vec<int32> = [];
let poolExhaustedReported: boolean = false;

export function acquireFrameTarget(w: int32, h: int32): uint32 { return acquireTarget(w, h); }
export function renderTargetsAlive(): int32 { return poolRT.length as int32; }

function acquireTarget(w: int32, h: int32): uint32 {
	const owner: DisplayList = currentList();
	for (let i: int32 = 0; i < (poolRT.length as int32); i++) {
		const free: boolean = listSerial(poolOwner[i]) != poolSerial[i];
		if (free && poolW[i] == w && poolH[i] == h) {
			poolOwner[i] = owner.id;
			poolSerial[i] = listSerial(owner.id);
			return poolRT[i];
		}
	}
	if ((poolRT.length as int32) >= MAX_POOLED_TARGETS) {
		if (!poolExhaustedReported) {
			poolExhaustedReported = true;
			console.log(`void2d: more than ${MAX_POOLED_TARGETS} filter targets in one frame - the rest are drawn unfiltered`);
		}
		return 0;
	}
	const rt: uint32 = allocRenderTarget(w, h);
	if (rt == 0) { return 0; }
	poolRT.push(rt);
	poolW.push(w);
	poolH.push(h);
	poolOwner.push(owner.id);
	poolSerial.push(listSerial(owner.id));
	return rt;
}

// Guardrail 3: downsample by 2^k, then blur at a one-texel step - never widen the tap
// spacing. The shader is a five-tap linear-sampled Gaussian whose offsets (1.384615 and
// 3.230769 texels) are the classic sigma-2 kernel, so it is only a Gaussian when `dir` is one
// texel. The pre-P1 code passed `radius / size`, which put the outer taps at 3.2 * radius
// texels: at radius 12 that samples 39 texels away and the result is a comb, not a blur.
// Halving until the radius is about two texels keeps the kernel in its valid regime and makes
// a wide blur cheaper rather than more wrong.
export function blurTargetPooled(rt: uint32, w: int32, h: int32, radius: float32): uint32 {
	let src: uint32 = rt;
	let sw: int32 = w;
	let sh: int32 = h;
	let r: float32 = radius;
	while (r > 2.0 && sw >= 8 && sh >= 8) {
		const dw: int32 = sw / 2;
		const dh: int32 = sh / 2;
		const dst: uint32 = acquireTarget(dw, dh);
		if (dst == 0) { return 0; }
		beginTarget(dst, dw as float32, dh as float32, 1.0, 0.0, 0.0, transparent);
		blitTarget(src, dw as float32, dh as float32);
		endTarget();
		src = dst;
		sw = dw;
		sh = dh;
		r = r * 0.5;
	}
	const tmp: uint32 = acquireTarget(sw, sh);
	if (tmp == 0) { return 0; }
	beginTarget(tmp, sw as float32, sh as float32, 1.0, 0.0, 0.0, transparent);
	blurPass(rtViewId(src), 1.0 / (sw as float32), 0.0);
	endTarget();
	const out: uint32 = acquireTarget(sw, sh);
	if (out == 0) { return 0; }
	beginTarget(out, sw as float32, sh as float32, 1.0, 0.0, 0.0, transparent);
	blurPass(rtViewId(tmp), 0.0, 1.0 / (sh as float32));
	endTarget();
	return out;
}

// One half-scale copy. `BlendMode.None` writes the source through instead of compositing it
// over the target's transparent black, which would otherwise darken every edge texel.
function blitTarget(src: uint32, w: float32, h: float32): void {
	// The target starts with no colour effect, but its sampler inherits the scene default.
	// State both requirements explicitly: downsampling is linear-clamp and effect-free.
	setEffect([], rgba(0.0, 0.0, 0.0, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
	setSampler(Smooth.On, false);
	imageQuad(tile(rtViewId(src), w, h), vec2(0.0, 0.0), vec2(w, 0.0), vec2(w, h), vec2(0.0, h),
		rgba(1.0, 1.0, 1.0, 1.0), BlendMode.None);
}

function drawRow(s: Scene2D, i: int32, a: float32, vw: float32, vh: float32): void {
	if (!s.orders[i].visible) { return; }
	if (s.filters[i].kind !== FilterKind.None) {
		drawFiltered(s, i, a, vw, vh);
		return;
	}
	drawContent(s, i, a, s.paints[i].alpha, vw, vh);
}

export function draw(this n: NodeRef, a: float32, vw: float32, vh: float32): void {
	drawRow(n.scene, n.liveRow("draw"), a, vw, vh);
}

function drawOwn(s: Scene2D, i: int32, na: float32, vw: float32, vh: float32): void {
	const world = s.worlds[i];
	const color: Color = s.paints[i].color;
	const col = rgba(color.r, color.g, color.b, color.a * na);
	const lb = localBounds(s, i, false);
	const tl = vec2(lb.xMin, lb.yMin) * world;
	const tr = vec2(lb.xMax, lb.yMin) * world;
	const br = vec2(lb.xMax, lb.yMax) * world;
	const bl = vec2(lb.xMin, lb.yMax) * world;
	const vb = boxRenderBounds(s, i, world, lb);
	const vtl = vec2(vb.xMin, vb.yMin) * world;
	const vtr = vec2(vb.xMax, vb.yMin) * world;
	const vbr = vec2(vb.xMax, vb.yMax) * world;
	const vbl = vec2(vb.xMin, vb.yMax) * world;
	const reach: Bounds2D = {
		xMin: fmin4(vtl.x, vtr.x, vbr.x, vbl.x), yMin: fmin4(vtl.y, vtr.y, vbr.y, vbl.y),
		xMax: fmax4(vtl.x, vtr.x, vbr.x, vbl.x), yMax: fmax4(vtl.y, vtr.y, vbr.y, vbl.y),
	};
	const scoped: boolean = inScope();
	const clipped: boolean = clipIntersectsQuad(vtl, vtr, vbr, vbl);
	const blank: boolean = s.kinds[i] === DrawKind.Group || s.kinds[i] === DrawKind.Mask;
	s.culls[i] = scoped || !clipped || blank ? emptyBounds() : reach;
	const onscreen: boolean = (scoped || seenAt(reach, s.viewShift, vw, vh)) && clipped;
	if (onscreen) {
		emitNode(
			s, i, world, na, col, tl, tr, br, bl,
			lb.xMax - lb.xMin, lb.yMax - lb.yMin, vec2(lb.xMin, lb.yMin), vb,
		);
	}
}

function seenAt(b: Bounds2D, shift: Vec2, vw: float32, vh: float32): boolean {
	return b.xMax >= 0.0 - shift.x && b.xMin <= vw - shift.x
		&& b.yMax >= 0.0 - shift.y && b.yMin <= vh - shift.y;
}

function deviceRound(v: float32): float32 {
	return Math.round(v as float64) as float32;
}

function targetRect(
	b: Bounds2D, shift: Vec2, vw: float32, vh: float32, dpi: float32, scoped: boolean,
): Bounds2D {
	let x0: float32 = Math.floor((b.xMin * dpi) as float64) as float32;
	let y0: float32 = Math.floor((b.yMin * dpi) as float64) as float32;
	let x1: float32 = Math.ceil((b.xMax * dpi) as float64) as float32;
	let y1: float32 = Math.ceil((b.yMax * dpi) as float64) as float32;
	if (!scoped) {
		const sx: float32 = deviceRound(shift.x * dpi);
		const sy: float32 = deviceRound(shift.y * dpi);
		const right: float32 = deviceRound(vw * dpi) - sx;
		const bottom: float32 = deviceRound(vh * dpi) - sy;
		if (x0 < 0.0 - sx) { x0 = 0.0 - sx; }
		if (y0 < 0.0 - sy) { y0 = 0.0 - sy; }
		if (x1 > right) { x1 = right; }
		if (y1 > bottom) { y1 = bottom; }
	}
	return { xMin: x0, yMin: y0, xMax: x1, yMax: y1 };
}

function panOrder(s: Scene2D, vw: float32, vh: float32): void {
	const was: Vec2 = s.culledShift;
	const now: Vec2 = s.viewShift;
	const dpi: float32 = currentRenderScale();
	for (let p: int32 = 0; p < (s.order.length as int32); p++) {
		const i: int32 = s.order[p];
		const reach: Bounds2D = s.culls[i];
		if (reach.xMin > reach.xMax) { continue; }
		const state: PaintState = paintStateOf(i);
		if (state == PaintState.InTarget) {
			if (s.filters[i].kind !== FilterKind.None
				&& targetRect(reach, was, vw, vh, dpi, false)
					!= targetRect(reach, now, vw, vh, dpi, false)) {
				s.scanNeeded = true;
			}
		} else if (state == PaintState.InLanes) {
			if (seenAt(reach, was, vw, vh) != seenAt(reach, now, vw, vh)) { s.scanNeeded = true; }
		} else if (state == PaintState.Painted && s.queued[i] != s.patchSerial
			&& seenAt(reach, was, vw, vh) != seenAt(reach, now, vw, vh)) {
			s.queued[i] = s.patchSerial;
			s.repaint.push(i);
		}
	}
}

function pushMask(s: Scene2D, i: int32): boolean {
	const world = s.worlds[i];
	const lb = localBounds(s, i, false);
	return pushClip(
		vec2(lb.xMin, lb.yMin) * world,
		vec2(lb.xMax, lb.yMin) * world,
		vec2(lb.xMax, lb.yMax) * world,
		vec2(lb.xMin, lb.yMax) * world,
	);
}

export function snappedShift(v: float32, scale: float32): float32 {
	if (scale <= 0.0) { return v; }
	return (Math.round((v * scale) as float64) as float32) / scale;
}

function localShift(s: Scene2D, i: int32, scale: float32): Vec2 {
	const by: Vec2 = scopeShift(s, i);
	return vec2(snappedShift(by.x, scale), snappedShift(by.y, scale));
}

function enterScopeOf(s: Scene2D, i: int32): void {
	const world = s.worlds[i];
	const lb = localBounds(s, i, false);
	const by: Vec2 = localShift(s, i, currentRenderScale());
	enterScope(
		i,
		vec2(lb.xMin, lb.yMin) * world,
		vec2(lb.xMax, lb.yMin) * world,
		vec2(lb.xMax, lb.yMax) * world,
		vec2(lb.xMin, lb.yMax) * world,
		by.x,
		by.y,
	);
}

export function refreshScopes(this s: Scene2D): void {
	const l: DisplayList = s.list;
	for (let k: int32 = 0; k < l.scopeTotal; k++) {
		const r = l.scopes[k];
		const by: Vec2 = k == l.cameraScope ? s.viewShift : localShift(s, r.row, r.scale);
		l.scopes[k] = { ...r, dx: by.x, dy: by.y };
	}
}

function drawContent(s: Scene2D, i: int32, a: float32, own: float32, vw: float32, vh: float32): void {
	const na: float32 = a * own;
	drawOwn(s, i, na, vw, vh);
	if (s.scrollScope(i)) {
		enterScopeOf(s, i);
		for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
			drawRow(s, s.children[i][k], na, vw, vh);
		}
		leaveScope();
		return;
	}
	const masking: boolean = s.kinds[i] === DrawKind.Mask;
	if (!masking || pushMask(s, i)) {
		for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
			drawRow(s, s.children[i][k], na, vw, vh);
		}
	}
	if (masking) {
		popClip();
	}
}

export function drawOrder(this s: Scene2D, vw: float32, vh: float32): void {
	scanOrder(s, vw, vh, null);
}

export function spliceOrder(this s: Scene2D, old: DisplayList, vw: float32, vh: float32): void {
	scanOrder(s, vw, vh, old);
}

function reusable(s: Scene2D, i: int32, old: DisplayList): boolean {
	if (i >= (old.paintStates.length as int32) || old.paintStates[i] != PaintState.Painted) {
		return false;
	}
	if (s.queued[i] == s.patchSerial || !s.changed[i].isEmpty()) { return false; }
	return continuesLike(old, old.paintStarts[i], old.paintEnds[i]);
}

let overlapRows: Vec<int32> = [];
let overlapBoxes: Vec<Bounds2D> = [];

function keyOf(b: Bounds2D, alongX: boolean): float32 { return alongX ? b.xMin : b.yMin; }

when (debug) {
	function checkNoOverlap(s: Scene2D, parent: int32): void {
		while ((overlapRows.length as int32) > 0) { overlapRows.pop(); }
		while ((overlapBoxes.length as int32) > 0) { overlapBoxes.pop(); }
		let spanX0: float32 = 1e30;
		let spanX1: float32 = -1e30;
		let spanY0: float32 = 1e30;
		let spanY1: float32 = -1e30;
		let widths: float32 = 0.0;
		let heights: float32 = 0.0;
		for (let k: int32 = 0; k < (s.children[parent].length as int32); k++) {
			const c: int32 = s.children[parent][k];
			if (!s.orders[c].visible) { continue; }
			let b: Bounds2D = emptyBounds();
			shiftedBounds(s, c, b, vec2(0.0, 0.0), true, false);
			if (b.xMax <= b.xMin || b.yMax <= b.yMin) { continue; }
			overlapRows.push(c);
			overlapBoxes.push(b);
			if (b.xMin < spanX0) { spanX0 = b.xMin; }
			if (b.xMax > spanX1) { spanX1 = b.xMax; }
			if (b.yMin < spanY0) { spanY0 = b.yMin; }
			if (b.yMax > spanY1) { spanY1 = b.yMax; }
			widths = widths + (b.xMax - b.xMin);
			heights = heights + (b.yMax - b.yMin);
		}
		const alongX: boolean = widths * (spanY1 - spanY0) <= heights * (spanX1 - spanX0);
		const m: int32 = overlapRows.length as int32;
		for (let a: int32 = 1; a < m; a++) {
			const row: int32 = overlapRows[a];
			const box: Bounds2D = overlapBoxes[a];
			let k: int32 = a - 1;
			while (k >= 0 && keyOf(overlapBoxes[k], alongX) > keyOf(box, alongX)) {
				overlapRows[k + 1] = overlapRows[k];
				overlapBoxes[k + 1] = overlapBoxes[k];
				k = k - 1;
			}
			overlapRows[k + 1] = row;
			overlapBoxes[k + 1] = box;
		}
		for (let a: int32 = 0; a < m; a++) {
			const ba: Bounds2D = overlapBoxes[a];
			const reach: float32 = alongX ? ba.xMax : ba.yMax;
			for (let b: int32 = a + 1; b < m && keyOf(overlapBoxes[b], alongX) < reach; b++) {
				const bb: Bounds2D = overlapBoxes[b];
				if (ba.xMin < bb.xMax && bb.xMin < ba.xMax && ba.yMin < bb.yMax && bb.yMin < ba.yMax) {
					console.log(
						`void2d: node ${parent} promised setNoOverlap, but its children ` +
						`${overlapRows[a]} and ${overlapRows[b]} overlap`,
					);
					unreachable;
				}
			}
		}
	}
} else {
	function checkNoOverlap(s: Scene2D, parent: int32): void {}
}

function lanesFor(s: Scene2D, i: int32): boolean {
	return s.orders[i].noOverlap && (s.children[i].length as int32) >= 2;
}

function laneParent(s: Scene2D): int32 {
	const frames: int32 = s.lanes.length as int32;
	return frames > 0 ? s.lanes[frames - 1].row : NO_NODE_2D;
}

function openLanes(s: Scene2D, i: int32, end: int32): void {
	const split: boolean = splitRun();
	s.lanes.push({
		row: i, marks: s.laneMarks.length as int32, opened: paintIndex(), openSplit: split,
		targets: targetCommandCount(),
	});
	s.maskEnds.push(end);
	s.maskKinds.push(Enclosure.Lanes);
}

function closeEnclosure(s: Scene2D): void {
	s.maskEnds.pop();
	match (s.maskKinds.pop()) {
		Enclosure.Clip => { popClip(); },
		Enclosure.Scope => { leaveScope(); },
		Enclosure.Lanes => { closeLanes(s); },
	}
}

function closeLanes(s: Scene2D): void {
	const frame: LaneFrame = s.lanes.pop();
	const recorded: boolean = closeLaneRun();
	const c0: int32 = frame.opened.commands;
	const c1: int32 = commandCount();
	const marks: Span<int32> = s.laneMarks;
	const children: Span<int32> = marks[frame.marks..(s.laneMarks.length as int32)];
	const reorder: boolean = targetCommandCount() == frame.targets &&
		(children.length as int32) > 0 && children[0] == c0 && lanesReorderable(c0, c1);
	layLanes(c0, c1, children, reorder, frame.openSplit ? c0 - 1 : -1, frame.opened);
	remapLaneRows(s, frame.row, c0, c1);
	if (recorded) {
		reopenLast();
	} else {
		restoreLaneRun();
	}
	while ((s.laneMarks.length as int32) > frame.marks) { s.laneMarks.pop(); }
	checkNoOverlap(s, frame.row);
}

function remapLaneRows(s: Scene2D, parent: int32, c0: int32, c1: int32): void {
	const top: int32 = s.slots[parent];
	for (let q: int32 = top + 1; q < s.orderEnd[top]; q++) {
		const r: int32 = s.order[q];
		if (paintStateOf(r) != PaintState.Painted) { continue; }
		const start: PaintIndex = paintStartOf(r);
		const end: PaintIndex = paintEndOf(r);
		const sprites: int32 = end.spriteInstances - start.spriteInstances;
		const ui: int32 = end.uiInstances - start.uiInstances;
		const vertices: int32 = end.vertices - start.vertices;
		const streams: int32 = (sprites > 0 ? 1 : 0) + (ui > 0 ? 1 : 0) + (vertices > 0 ? 1 : 0);
		if (streams == 0) { continue; }
		let pipeline: Pipeline = Pipeline.Vertex;
		let at: int32 = start.vertices;
		let count: int32 = vertices;
		if (sprites > 0) { pipeline = Pipeline.Sprite; at = start.spriteInstances; count = sprites; }
		if (ui > 0) { pipeline = Pipeline.Ui; at = start.uiInstances; count = ui; }
		const src: int32 = streams == 1 ? laneSourceHolding(pipeline, at, count, c0) : -1;
		if (src < 0) {
			markPaintState(r, PaintState.InLanes);
			continue;
		}
		const out: int32 = laneOutputOf(src, c0);
		const moved: int32 = laneOffsetOf(src, c0) + (at - laneSourceOffsetOf(src, c0));
		const effect: int32 = commandField(out, CMD_EFFECT) as int32;
		const lane: PaintIndex = {
			...start,
			commands: out,
			effects: start.effects,
			runOpen: true,
			runStart: commandField(out, pipeline == Pipeline.Vertex ? CMD_VERTEX_OFFSET : CMD_INSTANCE_OFFSET) as int32,
			pipeline: pipeline,
			reason: (commandField(out, CMD_BREAK) as int32) as BreakReason,
			view: commandView(out),
			blend: (commandField(out, CMD_BLEND) as int32) as BlendMode,
			sampler: commandField(out, CMD_SAMPLER) as int32,
			effect: effect,
			hasEffect: effect != NO_EFFECT,
		};
		const placed: PaintIndex = match (pipeline) {
			Pipeline.Sprite => ({ ...lane, spriteInstances: moved }),
			Pipeline.Ui => ({ ...lane, uiInstances: moved }),
			Pipeline.Vertex => ({ ...lane, vertices: moved }),
		};
		const past: PaintIndex = match (pipeline) {
			Pipeline.Sprite => ({ ...placed, spriteInstances: moved + count }),
			Pipeline.Ui => ({ ...placed, uiInstances: moved + count }),
			Pipeline.Vertex => ({ ...placed, vertices: moved + count }),
		};
		recordPaint(r, placed, past);
	}
}

function scanOrder(s: Scene2D, vw: float32, vh: float32, old: DisplayList | null): void {
	s.reused = 0;
	const n: int32 = s.order.length as int32;
	let p: int32 = 0;
	while (p < n) {
		while ((s.maskEnds.length as int32) > 0 && s.maskEnds[(s.maskEnds.length as int32) - 1] <= p) {
			closeEnclosure(s);
		}
		const i: int32 = s.order[p];
		const end: int32 = s.orderEnd[p];
		if (s.parents[i] != NO_NODE_2D && s.parents[i] == laneParent(s)) {
			splitRun();
			s.laneMarks.push(commandCount());
		}
		const a: float32 = p == 0 ? 1.0 : s.alphas[s.parents[i]];
		if (!s.orders[i].visible) {
			markRows(s, p, end, PaintState.Unpainted);
			p = end;
		} else if (s.filters[i].kind !== FilterKind.None) {
			markRows(s, p, end, PaintState.InTarget);
			drawFiltered(s, i, a, vw, vh);
			p = end;
		} else {
			const na: float32 = a * s.paints[i].alpha;
			s.alphas[i] = na;
			const start: PaintIndex = paintIndex();
			let q: int32 = p + 1;
			if (old !== null && reusable(s, i, old as DisplayList)) {
				const source: DisplayList = old as DisplayList;
				const first: PaintIndex = source.paintStarts[i];
				let last: PaintIndex = source.paintEnds[i];
				if (s.kinds[i] !== DrawKind.Mask && !lanesFor(s, i)) {
					while (q < n && joins(s, source, q, last)) {
						last = source.paintEnds[s.order[q]];
						q = q + 1;
					}
				}
				copyPainted(source, first, last);
				continueAfter(first, last, start);
				for (let r: int32 = p; r < q; r++) {
					const j: int32 = s.order[r];
					recordPaint(
						j,
						carried(source.paintStarts[j], first, start),
						carried(source.paintEnds[j], first, start),
					);
				}
				s.reused = s.reused + (q - p);
			} else {
				drawOwn(s, i, na, vw, vh);
				recordPaint(i, start, paintIndex());
			}
			let into: boolean = q == p + 1;
			if (into && s.kinds[i] === DrawKind.Mask) {
				if (s.scrollScope(i)) {
					enterScopeOf(s, i);
					s.maskEnds.push(end);
					s.maskKinds.push(Enclosure.Scope);
				} else if (pushMask(s, i)) {
					s.maskEnds.push(end);
					s.maskKinds.push(Enclosure.Clip);
				} else {
					popClip();
					markRows(s, p + 1, end, PaintState.Unpainted);
					into = false;
					q = end;
				}
			}
			if (into && lanesFor(s, i)) { openLanes(s, i, end); }
			p = into ? p + 1 : q;
		}
	}
	while ((s.maskEnds.length as int32) > 0) { closeEnclosure(s); }
}

function joins(s: Scene2D, source: DisplayList, q: int32, last: PaintIndex): boolean {
	const ends: int32 = s.maskEnds.length as int32;
	if (ends > 0 && s.maskEnds[ends - 1] <= q) { return false; }
	const j: int32 = s.order[q];
	if (!s.orders[j].visible || s.filters[j].kind !== FilterKind.None) { return false; }
	if (s.kinds[j] === DrawKind.Mask || lanesFor(s, j) || s.parents[j] == laneParent(s)) {
		return false;
	}
	if (j >= (source.paintStates.length as int32) || source.paintStates[j] != PaintState.Painted) {
		return false;
	}
	if (s.queued[j] == s.patchSerial || !s.changed[j].isEmpty()) { return false; }
	const end: PaintIndex = source.paintEnds[j];
	if (end.commands != last.commands || end.effects != last.effects || end.hasEffect) {
		return false;
	}
	return source.paintStarts[j] == last;
}

function markRows(s: Scene2D, from: int32, to: int32, state: PaintState): void {
	for (let p: int32 = from; p < to; p++) { markPaintState(s.order[p], state); }
}

function retilable(s: Scene2D, i: int32, redrawn: boolean): boolean {
	if (s.kinds[i] !== DrawKind.TileGroup || redrawn) { return false; }
	if (s.changed[i] != (0 as BitSet<Changed>).incl(Changed.Content)) { return false; }
	const p: int32 = s.payloads[i];
	if (s.tileGroups[p].reshaped) { return false; }
	const start: PaintIndex = paintStartOf(i);
	const end: PaintIndex = paintEndOf(i);
	if (end.vertices != start.vertices || end.uiInstances != start.uiInstances) { return false; }
	const drawn: int32 = Math.max(0, drawnEnd(s, p) - s.tileGroups[p].first);
	return end.spriteInstances - start.spriteInstances == drawn;
}

function queueRetile(s: Scene2D, i: int32): void {
	const p: int32 = s.payloads[i];
	if (s.tileGroups[p].retileSerial == s.patchSerial) { return; }
	s.tileGroups[p].retileSerial = s.patchSerial;
	s.retile.push(i);
}

function retileRow(s: Scene2D, i: int32): void {
	const p: int32 = s.payloads[i];
	const start: PaintIndex = paintStartOf(i);
	const world: Transform2D = s.worlds[i];
	const color: Color = s.paints[i].color;
	const col: Color = rgba(color.r, color.g, color.b, color.a * s.alphas[i]);
	const first: int32 = s.tileGroups[p].first;
	const end: int32 = drawnEnd(s, p);
	const cells: Span<TileCell> = s.tileCells[p];
	for (let e: int32 = 0; e < (s.tileEdits[p].length as int32); e++) {
		const k: int32 = s.tileEdits[p][e];
		if (k < first || k >= end) { continue; }
		const at: PaintIndex = { ...start, spriteInstances: start.spriteInstances + (k - first) };
		const past: PaintIndex = { ...at, spriteInstances: at.spriteInstances + 1 };
		const t: Tile = cells[k].tile;
		const m: Transform2D = world * cellMatrix(cells[k]);
		const origin = vec2(t.dx, t.dy) * m;
		saveRange(at, past);
		rewriteSprite(
			at.spriteInstances, m, origin.x, origin.y, t.w, t.h, t.u0, t.v0, t.u1, t.v1,
			tileTint(cells[k].color, col),
		);
		noteRange(at, past);
	}
}

function descend(s: Scene2D, d: int32): void {
	const top: int32 = s.slots[d];
	if (top == NO_SLOT) { return; }
	const bits: BitSet<Changed> = s.changed[d];
	if (bits == (0 as BitSet<Changed>).incl(Changed.Scroll) && s.scrollScope(d)) { return; }
	if (bits.has(Changed.Tree) || bits.has(Changed.Order) || bits.has(Changed.Filter)) {
		s.scanNeeded = true;
	}
	if (s.kinds[d] === DrawKind.Mask) { s.scanNeeded = true; }
	const end: int32 = s.orderEnd[top];
	let p: int32 = top;
	while (p < end) {
		const i: int32 = s.order[p];
		const up: int32 = s.parents[i];
		const world: Transform2D = (p == 0 ? s.viewMat : s.childWorld(up)) * s.localMatrices[i];
		const alpha: float32 = (p == 0 ? 1.0 : s.alphas[up]) * s.paints[i].alpha;
		const moved: boolean = world != s.worlds[i];
		if (p > top && !moved && alpha == s.alphas[i] && s.changed[i].isEmpty()) {
			p = s.orderEnd[p];
		} else {
			const state: PaintState = paintStateOf(i);
			if (state == PaintState.InTarget || state == PaintState.InLanes) { s.scanNeeded = true; }
			if (moved && s.kinds[i] === DrawKind.Mask) { s.scanNeeded = true; }
			const faded: boolean = alpha != s.alphas[i];
			s.worlds[i] = world;
			s.alphas[i] = alpha;
			if (s.kinds[i] === DrawKind.Label) { shapeIfChanged(s, i); }
			if (s.kinds[i] === DrawKind.Graphics) { meshBounds(s, i); }
			if (state == PaintState.Painted && s.queued[i] != s.patchSerial) {
				if (retilable(s, i, moved || faded)) {
					queueRetile(s, i);
				} else {
					s.queued[i] = s.patchSerial;
					s.repaint.push(i);
				}
			}
			p = p + 1;
		}
	}
}

export function patchOrder(this s: Scene2D, vw: float32, vh: float32): boolean {
	s.patchSerial = s.patchSerial + 1;
	while ((s.repaint.length as int32) > 0) { s.repaint.pop(); }
	while ((s.retile.length as int32) > 0) { s.retile.pop(); }
	s.scanNeeded = s.structureChanged;
	for (let k: int32 = 0; k < (s.dirty.length as int32); k++) { descend(s, s.dirty[k]); }
	if (s.viewShift != s.culledShift) { panOrder(s, vw, vh); }
	if (s.scanNeeded) { return false; }
	for (let k: int32 = 0; k < (s.repaint.length as int32); k++) {
		const i: int32 = s.repaint[k];
		const start: PaintIndex = paintStartOf(i);
		const end: PaintIndex = paintEndOf(i);
		saveRange(start, end);
		limitWrites(end);
		resumePaint(start);
		drawOwn(s, i, s.alphas[i], vw, vh);
		const kept: boolean = paintIndex() == end;
		unlimitWrites();
		if (!kept) { return false; }
		noteRange(start, end);
	}
	for (let k: int32 = 0; k < (s.retile.length as int32); k++) {
		const i: int32 = s.retile[k];
		if (s.queued[i] != s.patchSerial) {
			retileRow(s, i);
			s.retiled = s.retiled + 1;
		}
	}
	return true;
}

// h2d.Object.drawFilters (`h2d/Object.hx:896-956`), which the pre-P1 version got wrong in
// five separate ways. What it does now, and what each line replaces:
//
//   - **the node itself enters the target**, through `drawContent`; before, only `n.children`
//     did, so a filtered Graphics lost its own geometry and kept its children's.
//   - **alpha is applied once.** The subtree goes into the target at alpha 1 and the target is
//     composited at the accumulated alpha. Before, `a * n.alpha` was used for both, so a group
//     at 0.5 came out at 0.25.
//   - **object-local space through a filter matrix**, which here is the translation the
//     emitter subtracts from every vertex (`draw.ms` `originX/originY`). Before, the subtree
//     was re-synced against a second world matrix and then synced back, so it was walked and
//     transformed twice a frame and `localToGlobal` answered in target coordinates in between.
//   - **bounds clipped to the viewport**, so a filtered node mostly offscreen allocates a
//     target the size of the visible part instead of the size of the node.
//   - **no pass is opened here at all.** `beginTarget` brackets a region of the display list;
//     the replay opens the pass, outside the swapchain pass. Before, `beginRT` opened a pass
//     inside the open swapchain pass - sokol's `!_sg.cur_pass.valid` assertion in a debug
//     build, a frame of nothing but the clear colour in release, because the nested `begin2d`
//     also reset the list the frame was being recorded into.
function drawFiltered(s: Scene2D, i: int32, a: float32, vw: float32, vh: float32): void {
	const f: Filter = s.filters[i];
	const blend: BlendMode = s.paints[i].blend;
	let b = emptyBounds();
	boundsRow(s, i, b);
	s.culls[i] = emptyBounds();
	if (b.xMin >= b.xMax || b.yMin >= b.yMax) { return; }
	const pad: float32 = f.radius;
	let padded: Bounds2D = {
		xMin: b.xMin - pad, yMin: b.yMin - pad, xMax: b.xMax + pad, yMax: b.yMax + pad,
	};
	if (f.kind === FilterKind.DropShadow) {
		if (f.offsetX < 0.0) {
			padded = { ...padded, xMin: padded.xMin + f.offsetX };
		} else {
			padded = { ...padded, xMax: padded.xMax + f.offsetX };
		}
		if (f.offsetY < 0.0) {
			padded = { ...padded, yMin: padded.yMin + f.offsetY };
		} else {
			padded = { ...padded, yMax: padded.yMax + f.offsetY };
		}
	}
	// Clipped to the viewport: a target is only ever needed for the part that can be seen.
	const reach: Bounds2D = inScope() ? emptyBounds() : padded;
	s.culls[i] = reach;
	const dpi: float32 = currentRenderScale();
	const device: Bounds2D = targetRect(padded, s.viewShift, vw, vh, dpi, inScope());
	if (device.xMax <= device.xMin || device.yMax <= device.yMin) { return; }
	const xMin: float32 = device.xMin / dpi;
	const yMin: float32 = device.yMin / dpi;
	const rtW: int32 = (device.xMax - device.xMin) as int32;
	const rtH: int32 = (device.yMax - device.yMin) as int32;
	const logicalW: float32 = (rtW as float32) / dpi;
	const logicalH: float32 = (rtH as float32) / dpi;
	const rt: uint32 = acquireTarget(rtW, rtH);
	if (rt == 0) { return; }

	// The subtree at alpha 1, in target space. One walk, one sync, no GPU call.
	beginTarget(rt, logicalW, logicalH, dpi, xMin, yMin, transparent);
	drawContent(s, i, 1.0, 1.0, vw, vh);
	endTarget();
	s.culls[i] = reach;

	let src: uint32 = rt;
	if (f.radius > 0.0) {
		src = blurTargetPooled(rt, rtW, rtH, f.radius * dpi);
		if (src == 0) { return; }
	}

	const na: float32 = a * s.paints[i].alpha;
	// Composite at the exact logical extent represented by the physical target.
	const qx1: float32 = xMin + logicalW;
	const qy1: float32 = yMin + logicalH;
	const rtTile = tile(rtViewId(src), rtW as float32, rtH as float32);
	// Same reason as `blitTarget`: a composite that inherits the previous sibling's colour
	// matrix gets tinted, and one that inherits its sampler gets point-sampled. A render
	// target is always composited linear-clamp with no colour pipeline; the silhouette below
	// sets its own effect and puts this one back afterwards.
	setEffect([], rgba(0.0, 0.0, 0.0, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
	setSampler(Smooth.On, false);
	if (f.kind === FilterKind.Blur) {
		imageQuad(rtTile, vec2(xMin, yMin), vec2(qx1, yMin), vec2(qx1, qy1), vec2(xMin, qy1),
			rgba(1.0, 1.0, 1.0, na), blend);
		return;
	}
	// Glow and DropShadow composite a tinted silhouette of the blur, then the sharp original
	// on top, both at the accumulated alpha.
	//
	// Both halves used to be wrong here and a whole phase of green filter goldens missed it.
	// The sharp copy was produced by `drawContent(n, na, ...)` - a SECOND walk of the subtree
	// straight into the swapchain - and `drawContent` opens with `na = a * n.alpha`, so the
	// alpha was applied twice and the copy drew at `a * alpha^2`. Measured on
	// `filter/dropShadowAlpha` before this line changed: the subject's interior read
	// (76, 68, 45), which is `0.25 * subject + 0.75 * clear` to the byte, against
	// (131, 113, 60) for the once-applied value.
	//
	// It is composited from `rt` now, which already holds the subtree at alpha 1 - that is
	// what h2d does (`h2d/filter/Glow.hx` draws the blurred pass and then the source texture,
	// not a re-render) - so the group composites exactly once, the second walk is gone, and
	// the "one walk, one sync" this function claims is true for these two kinds as well.
	setEffect(colorMatrixAlphaOnly(f.gain),
		rgba(f.color.r, f.color.g, f.color.b, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
	const ox: float32 = f.kind === FilterKind.DropShadow ? f.offsetX : 0.0;
	const oy: float32 = f.kind === FilterKind.DropShadow ? f.offsetY : 0.0;
	const fblend: BlendMode = f.kind === FilterKind.Glow ? BlendMode.Add : BlendMode.Alpha;
	imageQuad(rtTile, vec2(xMin + ox, yMin + oy), vec2(qx1 + ox, yMin + oy),
		vec2(qx1 + ox, qy1 + oy), vec2(xMin + ox, qy1 + oy), rgba(1.0, 1.0, 1.0, na), fblend);
	setEffect([], rgba(0.0, 0.0, 0.0, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
	const sharpTile = tile(rtViewId(rt), rtW as float32, rtH as float32);
	imageQuad(sharpTile, vec2(xMin, yMin), vec2(qx1, yMin), vec2(qx1, qy1), vec2(xMin, qy1),
		rgba(1.0, 1.0, 1.0, na), blend);
}

function scopeShift(s: Scene2D, i: int32): Vec2 {
	const sc: Scroll2D = s.scrolls[s.payloads[i]];
	return vec2(-sc.x * s.worlds[i].a, -sc.y * s.worlds[i].d);
}

function boundsRow(s: Scene2D, i: int32, ref out: Bounds2D): void {
	shiftedBounds(s, i, out, vec2(0.0, 0.0), false, false);
}

function shiftedBounds(
	s: Scene2D, i: int32, ref out: Bounds2D, shift: Vec2, scoped: boolean, query: boolean,
): void {
	const lb = localBounds(s, i, query);
	const world = s.worlds[i];
	if (scoped && s.kinds[i] === DrawKind.Mask) {
		maskedBounds(s, i, out, shift, lb, world, query);
		return;
	}
	const vb = boxRenderBounds(s, i, world, lb);
	if (vb.xMax > vb.xMin && vb.yMax > vb.yMin) {
		const btl = vec2(vb.xMin, vb.yMin) * world;
		const btr = vec2(vb.xMax, vb.yMin) * world;
		const bbr = vec2(vb.xMax, vb.yMax) * world;
		const bbl = vec2(vb.xMin, vb.yMax) * world;
		const bxMin: float32 = fmin4(btl.x, btr.x, bbr.x, bbl.x) + shift.x;
		const byMin: float32 = fmin4(btl.y, btr.y, bbr.y, bbl.y) + shift.y;
		const bxMax: float32 = fmax4(btl.x, btr.x, bbr.x, bbl.x) + shift.x;
		const byMax: float32 = fmax4(btl.y, btr.y, bbr.y, bbl.y) + shift.y;
		if (bxMin < out.xMin) { out.xMin = bxMin; }
		if (byMin < out.yMin) { out.yMin = byMin; }
		if (bxMax > out.xMax) { out.xMax = bxMax; }
		if (byMax > out.yMax) { out.yMax = byMax; }
	}
	let inner: Vec2 = shift;
	if (scoped && s.scrollScope(i)) {
		const by: Vec2 = scopeShift(s, i);
		inner = vec2(shift.x + by.x, shift.y + by.y);
	}
	for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
		const child: int32 = s.children[i][k];
		if (s.orders[child].visible) { shiftedBounds(s, child, out, inner, scoped, query); }
	}
}

function maskedBounds(
	s: Scene2D, i: int32, ref out: Bounds2D, shift: Vec2, lb: Bounds2D, world: Transform2D,
	query: boolean,
): void {
	let inner: Vec2 = shift;
	if (s.scrollScope(i)) {
		const by: Vec2 = scopeShift(s, i);
		inner = vec2(shift.x + by.x, shift.y + by.y);
	}
	let content: Bounds2D = emptyBounds();
	for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
		const child: int32 = s.children[i][k];
		if (s.orders[child].visible) { shiftedBounds(s, child, content, inner, true, query); }
	}
	const mtl = vec2(lb.xMin, lb.yMin) * world;
	const mtr = vec2(lb.xMax, lb.yMin) * world;
	const mbr = vec2(lb.xMax, lb.yMax) * world;
	const mbl = vec2(lb.xMin, lb.yMax) * world;
	const xMin: float32 = fmin4(mtl.x, mtr.x, mbr.x, mbl.x) + shift.x;
	const yMin: float32 = fmin4(mtl.y, mtr.y, mbr.y, mbl.y) + shift.y;
	const xMax: float32 = fmax4(mtl.x, mtr.x, mbr.x, mbl.x) + shift.x;
	const yMax: float32 = fmax4(mtl.y, mtr.y, mbr.y, mbl.y) + shift.y;
	if (content.xMin < xMin) { content.xMin = xMin; }
	if (content.yMin < yMin) { content.yMin = yMin; }
	if (content.xMax > xMax) { content.xMax = xMax; }
	if (content.yMax > yMax) { content.yMax = yMax; }
	if (content.xMax <= content.xMin || content.yMax <= content.yMin) { return; }
	if (content.xMin < out.xMin) { out.xMin = content.xMin; }
	if (content.yMin < out.yMin) { out.yMin = content.yMin; }
	if (content.xMax > out.xMax) { out.xMax = content.xMax; }
	if (content.yMax > out.yMax) { out.yMax = content.yMax; }
}

export function getBounds(this n: NodeRef, ref out: Bounds2D): void {
	const s: Scene2D = n.scene;
	const i: int32 = n.liveRow("getBounds");
	let shift: Vec2 = vec2(0.0, 0.0);
	let top: int32 = i;
	let up: int32 = s.parents[i];
	while (up != NO_NODE_2D) {
		if (s.scrollScope(up)) {
			const by: Vec2 = scopeShift(s, up);
			shift = vec2(shift.x + by.x, shift.y + by.y);
		}
		top = up;
		up = s.parents[up];
	}
	if (top == s.root) { shift = vec2(shift.x + s.viewShift.x, shift.y + s.viewShift.y); }
	out = emptyBounds();
	shiftedBounds(s, i, out, shift, true, true);
	if (out.xMax <= out.xMin || out.yMax <= out.yMin) {
		const origin: Vec2 = vec2(0.0, 0.0) * ownWorld(s, i);
		out = {
			xMin: origin.x + shift.x, yMin: origin.y + shift.y,
			xMax: origin.x + shift.x, yMax: origin.y + shift.y,
		};
	}
}

function hitLocal(s: Scene2D, i: int32, ref p: Vec2): boolean {
	if (!s.orders[i].visible) { return false; }
	const up: int32 = s.parents[i];
	if (up != NO_NODE_2D) {
		if (!hitLocal(s, up, p)) { return false; }
	} else if (i == s.root) {
		const view: Transform2D = { ...s.viewMat, tx: s.viewShift.x, ty: s.viewShift.y };
		if (view.a * view.d - view.b * view.c == 0.0) { return false; }
		p = p * inverse2d(view);
	}
	const m: Transform2D = s.localMatrices[i];
	if (m.a * m.d - m.b * m.c == 0.0) { return false; }
	p = p * inverse2d(m);
	if (s.kinds[i] === DrawKind.Mask) {
		if (s.contents[i].w <= 0.0 || s.contents[i].h <= 0.0 ||
			p.x < 0.0 || p.x > s.contents[i].w || p.y < 0.0 || p.y > s.contents[i].h) {
			return false;
		}
		const by: Vec2 = s.ownScroll(i);
		p = vec2(p.x + by.x, p.y + by.y);
	}
	return true;
}

export function hitTest(this n: NodeRef, p: Vec2): boolean {
	const s: Scene2D = n.scene;
	const i: int32 = n.liveRow("hitTest");
	let local: Vec2 = p;
	if (!hitLocal(s, i, local)) { return false; }
	if (s.kinds[i] === DrawKind.Mask) { return true; }
	if (s.kinds[i] === DrawKind.Label) { shapeIfChanged(s, i); }
	if (s.kinds[i] === DrawKind.Graphics) { meshBounds(s, i); }
	const lb: Bounds2D = localBounds(s, i, true);
	return lb.xMax > lb.xMin && lb.yMax > lb.yMin &&
		local.x >= lb.xMin && local.x <= lb.xMax && local.y >= lb.yMin && local.y <= lb.yMax;
}

function ownWorld(s: Scene2D, i: int32): Transform2D {
	const by: Vec2 = s.ownScroll(i);
	if (by.x == 0.0 && by.y == 0.0) { return s.worlds[i]; }
	return s.worlds[i] * trs2d(-by.x, -by.y, 0.0, 1.0, 1.0);
}

function shapedPayload(n: NodeRef, call: string): int32 {
	const i: int32 = n.labelRow(call);
	shapeIfChanged(n.scene, i);
	return n.scene.payloads[i];
}

export function textLayout(this n: NodeRef): TextLayout {
	return labelTexts[shapedPayload(n, "textLayout")].layout;
}

export function textWidth(this n: NodeRef): float32 {
	return labelTexts[shapedPayload(n, "textWidth")].layout.width;
}

export function textHeight(this n: NodeRef): float32 {
	return labelTexts[shapedPayload(n, "textHeight")].layout.height;
}

function layoutLike(payload: int32, text: string, style: TextStyle): TextLayout {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const options: LineOptions = payload == NO_LABEL_TEXT ? PLAIN_LINES : labelLines(payload);
	return wrapText(shapeText(text, style, noRuns, noBreaks), style, options);
}

export function calcTextWidth(this n: NodeRef, text: string): float32 {
	const payload: int32 = n.scene.payloads[n.labelRow("calcTextWidth")];
	return layoutLike(payload, text, { ...labelTexts[payload].style, maxWidth: 0.0 }).width;
}

export function splitText(this n: NodeRef, text: string): string {
	const payload: int32 = n.scene.payloads[n.labelRow("splitText")];
	return layoutLike(payload, text, labelTexts[payload].style).splitText(text);
}

export function xForIndex(this n: NodeRef, index: int32): float32 {
	return labelTexts[shapedPayload(n, "xForIndex")].layout.xForIndex(index);
}

export function indexAt(this n: NodeRef, x: float32, y: float32): int32 {
	return labelTexts[shapedPayload(n, "indexAt")].layout.indexAt(x, y);
}

export function lineBoxAt(this n: NodeRef, index: int32): LineBox {
	return labelTexts[shapedPayload(n, "lineBoxAt")].layout.lineBoxAt(index);
}
