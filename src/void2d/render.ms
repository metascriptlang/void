// void2d rendering — sync (transform cache + content bounds), draw (dispatch + cull + filter),
// getBounds. Extracted from node.ms so each file has one responsibility.

import { Node2D, DrawKind } from "./node";
import {
	fillQuad,
	drawSpriteAffine,
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
} from "./draw";
import { InstanceMode } from "./instance";
import {
	NO_LABEL_TEXT,
	allocateLabelText,
	shapeLabel,
	placeLabel,
	firstGlyphPageHandle,
	glyphPageHandle,
	markGlyphPageDrawn,
	labelTexts,
	LabelText,
	Decoration,
	DecorationKind,
} from "./labelText";
import {
	TextLayout,
	TextStyle,
	NO_GLYPH,
	NO_RUN,
	calcTextWidth as layoutWidth,
} from "./textLayout";
import { GlyphPage, NO_GLYPH_PAGE } from "./glyphAtlas";
import { glyphInkBox } from "./face";
import { Vec2, Color, Tile, Transform2D, Bounds, FilterKind, BlendMode, Smooth, vec2, rgba, tile, trs2d, emptyBounds } from "./types";
import { colorMatrixAlphaOnly } from "./effect";
import { NO_BOX_STYLE, BorderStyle, boxStyles } from "./boxStyle";
import { axisAligned, snapEdge, snapBoxEdges, snapStroke } from "./snap";
import {
	GraphicsOpKind, GRAPHICS_OP_FLOATS, GFX_OP_KIND, GFX_OP_VERTEX_OFFSET,
	GFX_OP_VERTEX_COUNT, GFX_OP_SPACE, GFX_OP_DITHER, GFX_OP_MIDDLE,
	GFX_OP_COLOR0, GFX_OP_COLOR1, GFX_OP_COLOR2, GFX_OP_PARAMS,
} from "./graphics";
import { NO_IMAGE_STYLE, imageStyles, fitImage } from "./imageStyle";

// Not Span<Node2D>: an interface array passed as a span emits an uncast void ** that emcc refuses
// (~/metascript/.inbox/compiler/2026-09-26-interface-array-to-span-void-pointer.md).
function sortByZ(cs: Node2D[]): void {
	const m: int32 = cs.length as int32;
	for (let i: int32 = 1; i < m; i++) {
		const cur = cs[i];
		let j: int32 = i - 1;
		while (j >= 0 && cs[j].zIndex > cur.zIndex) {
			cs[j + 1] = cs[j];
			j = j - 1;
		}
		cs[j + 1] = cur;
	}
}

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

function visualTile(n: Node2D): Tile {
	if (n.kind === DrawKind.Anim && (n.frames.length as int32) > 0) {
		const len: int32 = n.frames.length as int32;
		const index: int32 = ((n.clock * n.fps) as int32) % len;
		return n.frames[index];
	}
	return n.sheet;
}
function tileOffsetX(t: Tile, width: float32): float32 {
	return t.w != 0.0 ? t.dx * width / t.w : t.dx;
}

function tileOffsetY(t: Tile, height: float32): float32 {
	return t.h != 0.0 ? t.dy * height / t.h : t.dy;
}


function localBounds(n: Node2D): Bounds {
	if (n.kind === DrawKind.Graphics || n.kind === DrawKind.Label) {
		return { xMin: n.contentXMin, yMin: n.contentYMin, xMax: n.contentXMax, yMax: n.contentYMax };
	}
	if (n.kind === DrawKind.Selection) {
		return { xMin: -SELECTION_GLOOP, yMin: 0.0, xMax: n.w + SELECTION_GLOOP, yMax: n.h };
	}
	if (n.kind === DrawKind.Sprite || n.kind === DrawKind.Anim || n.kind === DrawKind.ScaleGrid) {
		const t: Tile = visualTile(n);
		const dx: float32 = tileOffsetX(t, n.w);
		const dy: float32 = tileOffsetY(t, n.h);
		return { xMin: dx, yMin: dy, xMax: dx + n.w, yMax: dy + n.h };
	}
	return { xMin: 0.0, yMin: 0.0, xMax: n.w, yMax: n.h };
}

function boxRenderBounds(n: Node2D, world: Transform2D, lb: Bounds): Bounds {
	if (n.kind !== DrawKind.Rect) { return lb; }
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
	if (n.payload == NO_BOX_STYLE) {
		return { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax };
	}
	const st = boxStyles[n.payload];
	if (st.shadowColor.a > 0.0 && !st.shadowInset) {
		let offsetX: float32 = st.shadowOffsetX;
		let offsetY: float32 = st.shadowOffsetY;
		if (aligned) {
			offsetX = snapEdge(offsetX * deviceAX) / deviceAX;
			offsetY = snapEdge(offsetY * deviceDX) / deviceDX;
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

function renderScaleGrid(n: Node2D, world: Transform2D, col: Color): void {
	const t = n.sheet;
	const srcW: float32 = t.w;
	const srcH: float32 = t.h;
	if (srcW <= 0.0 || srcH <= 0.0) { return; }
	const ox: float32 = tileOffsetX(t, n.w);
	const oy: float32 = tileOffsetY(t, n.h);
	const sx: float32[4] = [0.0, n.borderL, srcW - n.borderR, srcW];
	const sy: float32[4] = [0.0, n.borderT, srcH - n.borderB, srcH];
	const dx: float32[4] = [ox, ox + n.borderL, ox + n.w - n.borderR, ox + n.w];
	const dy: float32[4] = [oy, oy + n.borderT, oy + n.h - n.borderB, oy + n.h];
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
			imageQuadUV(t.view, u0, v0, u1, v1, a, b, c, d, col, n.blend);
		}
	}
}

function labelStyle(n: Node2D): TextStyle {
	return {
		font: n.fontId,
		size: n.size,
		letterSpacing: n.letterSpacing,
		lineSpacing: n.lineSpacing,
		maxWidth: n.maxWidth,
		align: n.textAlign,
	};
}

function shapeIfChanged(n: Node2D): void {
	const textChanged: boolean = n.textDirty || n.size != n.lastSize
		|| n.textAlign != n.lastTextAlign
		|| n.letterSpacing != n.lastLetterSpacing || n.lineSpacing != n.lastLineSpacing
		|| n.maxWidth != n.lastMaxWidth || !n.text.equals(n.lastText)
		|| n.fontId != n.lastFontId;
	if (textChanged) {
		if (n.payload == NO_LABEL_TEXT) { n.payload = allocateLabelText(); }
		shapeLabel(n.payload, n.text, labelStyle(n));
		const shaped: LabelText = labelTexts[n.payload];
		n.contentXMin = 0.0; n.contentXMax = 0.0;
		for (const line of shaped.layout.lines) {
			if (line.x < n.contentXMin) { n.contentXMin = line.x; }
			if (line.x + line.width > n.contentXMax) { n.contentXMax = line.x + line.width; }
		}
		n.contentYMin = 0.0;
		n.contentYMax = shaped.layout.height;
		for (const g of shaped.layout.glyphs) {
			if (g.glyph == NO_GLYPH) { continue; }
			const [left, top, right, bottom] = glyphInkBox(g.face, g.glyph, g.size);
			if (right <= left || bottom <= top) { continue; }
			const baseline: float32 = shaped.layout.lines[g.line].baseline;
			if (g.x + left < n.contentXMin) { n.contentXMin = g.x + left; }
			if (g.x + right > n.contentXMax) { n.contentXMax = g.x + right; }
			if (baseline + top < n.contentYMin) { n.contentYMin = baseline + top; }
			if (baseline + bottom > n.contentYMax) { n.contentYMax = baseline + bottom; }
		}
		n.lastText = n.text; n.lastSize = n.size; n.lastTextAlign = n.textAlign;
		n.lastLetterSpacing = n.letterSpacing;
		n.lastLineSpacing = n.lineSpacing;
		n.lastMaxWidth = n.maxWidth;
		n.textDirty = false;
		n.lastFontId = n.fontId;
	}
}

export function sync(this n: Node2D, parentWorld: Transform2D, parentChanged: boolean): void {
	const localChanged: boolean = n.dirty
		|| n.x != n.lastX || n.y != n.lastY
		|| n.scaleX != n.lastSX || n.scaleY != n.lastSY
		|| n.rotation != n.lastRot
		|| n.pivotX != n.lastPivotX || n.pivotY != n.lastPivotY;
	if (localChanged) {
		n.cachedLocal = trs2d(n.x, n.y, n.rotation, n.scaleX, n.scaleY)
			* trs2d(-n.pivotX, -n.pivotY, 0.0, 1.0, 1.0);
		n.lastX = n.x; n.lastY = n.y; n.lastSX = n.scaleX; n.lastSY = n.scaleY; n.lastRot = n.rotation;
		n.lastPivotX = n.pivotX; n.lastPivotY = n.pivotY;
		n.dirty = false;
	}
	const worldChanged: boolean = localChanged || parentChanged;
	if (worldChanged) {
		n.cachedWorld = parentWorld * n.cachedLocal;
	}
	if (n.kind === DrawKind.Label) { shapeIfChanged(n); }
	if (n.kind === DrawKind.Graphics && n.gfxDirty) {
		n.contentXMin = 1e30; n.contentYMin = 1e30; n.contentXMax = -1e30; n.contentYMax = -1e30;
		for (let mi: int32 = 0; mi + 8 <= n.mesh.length as int32; mi += 8) {
			const mx: float32 = n.mesh[mi]; const my: float32 = n.mesh[mi + 1];
			if (mx < n.contentXMin) { n.contentXMin = mx; }
			if (my < n.contentYMin) { n.contentYMin = my; }
			if (mx > n.contentXMax) { n.contentXMax = mx; }
			if (my > n.contentYMax) { n.contentYMax = my; }
		}
		if (n.contentXMin > n.contentXMax) { n.contentXMin = 0.0; n.contentXMax = 0.0; n.contentYMin = 0.0; n.contentYMax = 0.0; }
		n.meshVertCount = (n.mesh.length as int32) / 8;
		n.gfxDirty = false;
	}
	for (const ch of n.children) {
		ch.sync(n.cachedWorld, worldChanged);
	}
}
let imageEffectRejectedReported: boolean = false;
const deviceGrid: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);

function sharedGlyphView(): uint32 {
	return glyphPageView(firstGlyphPageHandle());
}

function faded(c: Color, alpha: float32): Color {
	return rgba(c.r, c.g, c.b, c.a * alpha);
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
	n: Node2D,
	world: Transform2D,
	box: [float32, float32, float32, float32],
	fill: Color,
): void {
	const [x, y, w, h] = box;
	if (w <= 0.0 || h <= 0.0) { return; }
	const transparent: Color = rgba(0.0, 0.0, 0.0, 0.0);
	const origin = vec2(x, y) * world;
	drawUiInstance(InstanceMode.Box, sharedGlyphView(), n.blend, world, origin.x, origin.y, w, h,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		fill, transparent, transparent);
}

function emitRunLine(
	n: Node2D,
	world: Transform2D,
	box: [float32, float32, float32, float32],
	wavy: boolean,
	fill: Color,
): void {
	const [x, y, w, h] = box;
	if (w <= 0.0 || h <= 0.0) { return; }
	const transparent: Color = rgba(0.0, 0.0, 0.0, 0.0);
	const quadY: float32 = wavy ? y - h : y;
	const quadH: float32 = wavy ? h * 3.0 : h;
	const origin = vec2(x, quadY) * world;
	drawUiInstance(InstanceMode.Underline, sharedGlyphView(), n.blend, world,
		origin.x, origin.y, w, quadH,
		0.0, 0.0, 0.0, 0.0,
		h, wavy ? 1.0 : 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		fill, transparent, transparent);
}

function emitDecorations(
	n: Node2D,
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
			emitRunBox(n, world, box, faded(d.color, na));
		} else {
			emitRunLine(n, world, box, d.kind == DecorationKind.WavyUnderline, faded(d.color, na));
		}
	}
}

function emitLabel(n: Node2D, world: Transform2D, col: Color, na: float32): void {
	if (n.payload == NO_LABEL_TEXT) { return; }
	const scale: float32 = currentRenderScale();
	const text = placeLabel(n.payload, world, scale);
	const styled: boolean = (text.runs.length as int32) > 0 && uiInstancingAvailable();
	if (styled) { emitDecorations(n, text, world, na, true); }
	const originX: float32 = Math.floor(world.tx * scale) as float32;
	const originY: float32 = Math.floor(world.ty * scale) as float32;
	const transparent: Color = rgba(0.0, 0.0, 0.0, 0.0);
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
		const fill: Color = styled && p.run != NO_RUN ? faded(text.runs[p.run].color, na) : col;
		if (instanced) {
			drawUiInstance(InstanceMode.Glyph, view, n.blend, affine,
				x, y, w, h,
				p.u0, p.v0, p.u1, p.v1,
				0.0, 0.0, 0.0, 0.0,
				0.0, 0.0, 0.0,
				0.0, 0.0, 0.0, 0.0,
				fill, transparent, transparent);
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
				fill, n.blend);
		}
	}
	if (styled) { emitDecorations(n, text, world, na, false); }
}
let textPrimitiveEffectRejectedReported: boolean = false;
const TEXT_PRIMITIVE_EFFECT_REFUSED: string =
	"void2d: underline and selection cannot be combined with colorMatrix, colorAdd, or colorKey";
let boxEffectRejectedReported: boolean = false;


function emitStyledImage(
	n: Node2D,
	t: Tile,
	world: Transform2D,
	col: Color,
	sizeX: float32,
	sizeY: float32,
	lbMin: Vec2,
): boolean {
	if (n.payload == NO_IMAGE_STYLE) { return false; }
	if (!uiInstancingAvailable()) {
		if (!imageEffectRejectedReported) {
			console.log("void2d: an image style cannot be combined with colorMatrix, colorAdd, or colorKey");
			imageEffectRejectedReported = true;
		}
		return true;
	}
	const style = imageStyles[n.payload];
	const fitted = fitImage(t, sizeX, sizeY, style.fit);
	if (fitted.w <= 0.0 || fitted.h <= 0.0) { return true; }
	const origin = vec2(lbMin.x + fitted.x, lbMin.y + fitted.y) * world;
	drawUiInstance(InstanceMode.Image, t.view, n.blend, world,
		origin.x, origin.y, fitted.w, fitted.h,
		fitted.u0, fitted.v0, fitted.u1, fitted.v1,
		style.radii.topLeft, style.radii.topRight,
		style.radii.bottomRight, style.radii.bottomLeft,
		0.0, 0.0, 0.0,
		style.grayscale ? 1.0 : 0.0, 0.0, 0.0, 0.0,
		col, transparent, transparent);
	return true;
}

function emitNode(
	n: Node2D, world: Transform2D, na: float32, col: Color,
	tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2, sizeX: float32, sizeY: float32, lbMin: Vec2,
	boxBounds: Bounds,
): void {
	setEffect(n.colorMatrix, n.colorAdd, n.colorKey);
	setSampler(n.smooth, n.tileWrap);
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
	match (n.kind) {
		DrawKind.Rect => {
			if (!uiInstancingAvailable() && n.payload != NO_BOX_STYLE) {
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
				if (n.payload != NO_BOX_STYLE) {
					const styleIndex: int32 = n.payload;
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
				const shadowOn: boolean = n.payload != NO_BOX_STYLE
					&& boxStyles[n.payload].shadowColor.a > 0.0;
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
					const st = boxStyles[n.payload];
					const sigma: float32 = st.shadowBlur;
					let offsetX: float32 = st.shadowOffsetX;
					let offsetY: float32 = st.shadowOffsetY;
					if (aligned) {
						offsetX = snapEdge(offsetX * deviceAX) / deviceAX;
						offsetY = snapEdge(offsetY * deviceDX) / deviceDX;
					}
					sp0 = offsetX;
					sp1 = offsetY;
					sp2 = sigma;
					sp3 = st.shadowInset ? 1.0 : 0.0;
					const sc: Color = st.shadowColor;
					shadowColor = rgba(sc.r, sc.g, sc.b, sc.a * na);
				}
				drawUiInstance(InstanceMode.Box, sharedGlyphView(), n.blend, world, qx, qy, qw, qh,
					radiusTL, radiusTR, radiusBR, radiusBL,
					borderL, borderT, borderR, borderB,
					borderStyle, 0.0, 0.0,
					sp0, sp1, sp2, sp3,
					col, edge, shadowColor);
			} else {
				fillQuad(tl, tr, br, bl, col, n.blend);
			}
		},
		DrawKind.Sprite => {
			if (!emitStyledImage(n, n.sheet, world, col, sizeX, sizeY, lbMin)) {
				if (instanced) {
					drawSpriteAffine(n.sheet.view, n.blend, world, tl.x, tl.y, sizeX, sizeY,
						n.sheet.u0, n.sheet.v0, n.sheet.u1, n.sheet.v1, col);
				} else {
					imageQuad(n.sheet, tl, tr, br, bl, col, n.blend);
				}
			}
		},
		DrawKind.Anim => {
			const len: int32 = n.frames.length as int32;
			if (len > 0) {
				const fi: int32 = ((n.clock * n.fps) as int32) % len;
				const fr = n.frames[fi];
				if (!emitStyledImage(n, fr, world, col, sizeX, sizeY, lbMin)) {
					if (instanced) {
						drawSpriteAffine(fr.view, n.blend, world, tl.x, tl.y, sizeX, sizeY,
							fr.u0, fr.v0, fr.u1, fr.v1, col);
					} else {
						imageQuad(fr, tl, tr, br, bl, col, n.blend);
					}
				}
			}
		},
		DrawKind.Underline => {
			if (uiInstancingAvailable()) {
				drawUiInstance(InstanceMode.Underline, sharedGlyphView(), n.blend, world,
					tl.x, tl.y, sizeX, sizeY,
					0.0, 0.0, 0.0, 0.0,
					n.size, n.borderL, 0.0, 0.0,
					0.0, 0.0, 0.0,
					0.0, 0.0, 0.0, 0.0,
					col, transparent, transparent);
			} else if (!textPrimitiveEffectRejectedReported) {
				console.log(TEXT_PRIMITIVE_EFFECT_REFUSED);
				textPrimitiveEffectRejectedReported = true;
			}
		},
		DrawKind.Selection => {
			if (uiInstancingAvailable()) {
				drawUiInstance(InstanceMode.Selection, sharedGlyphView(), n.blend, world,
					tl.x, tl.y, sizeX, sizeY,
					0.0, 0.0, 0.0, 0.0,
					n.w * 0.5, n.h * 0.5, SELECTION_RADIUS, SELECTION_GLOOP,
					0.0, 0.0, 0.0,
					n.borderL, n.borderT, n.borderR, n.borderB,
					col, transparent, transparent);
			} else if (!textPrimitiveEffectRejectedReported) {
				console.log(TEXT_PRIMITIVE_EFFECT_REFUSED);
				textPrimitiveEffectRejectedReported = true;
			}
		},
		DrawKind.Label => {
			emitLabel(n, world, col, na);
		},
		DrawKind.Graphics => {
			const ops: float32[] = n.records;
			const opTotal: int32 = ops.length as int32;
			if (opTotal == 0) {
				drawMesh(n.mesh, n.gfxView, n.blend, world, rgba(1.0, 1.0, 1.0, 1.0), na);
			} else {
				const stride: int32 = GRAPHICS_OP_FLOATS;
				for (let oi: int32 = 0; oi + stride <= opTotal; oi += stride) {
					const kind: int32 = ops[oi + GFX_OP_KIND] as int32;
					const offset: int32 = ops[oi + GFX_OP_VERTEX_OFFSET] as int32;
					const count: int32 = ops[oi + GFX_OP_VERTEX_COUNT] as int32;
					if (kind == GraphicsOpKind.Mesh as int32) {
						setEffect(n.colorMatrix, n.colorAdd, n.colorKey);
						drawMeshRange(n.mesh, offset, count, n.gfxView, n.blend, world,
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
						setGradientEffect(n.colorMatrix, n.colorAdd, n.colorKey,
							kind, ops[oi + GFX_OP_SPACE] as int32,
							ops[oi + GFX_OP_DITHER] != 0.0, ops[oi + GFX_OP_MIDDLE],
							ops[oi + GFX_OP_PARAMS], ops[oi + GFX_OP_PARAMS + 1],
							ops[oi + GFX_OP_PARAMS + 2], ops[oi + GFX_OP_PARAMS + 3],
							c0, c1, c2);
						drawMeshRange(n.mesh, offset, count, 0, n.blend, world,
							rgba(1.0, 1.0, 1.0, 1.0), na);
					}
				}
			}
		},
		DrawKind.ScaleGrid => {
			renderScaleGrid(n, world, col);
		},
		DrawKind.Group | DrawKind.Mask => {},
	}
}

// A filter target always starts empty: what is not drawn into it must not composite.
const transparent: Color = rgba(0.0, 0.0, 0.0, 0.0);

// ===== the frame-linear render-target pool (h3d/impl/TextureCache.hx) =====
//
// No node owns a target any more. A target is taken for the length of one frame and handed
// back at the start of the next, so two filters that never overlap in time share one, and a
// node that stops being filtered stops holding a texture it is not using. Reuse is by exact
// size, because a golden has to be reproducible and a size-bucketed pool would make the
// contents of a target depend on which frame allocated it first.
//
// The cap matters: sokol's default pools hold 128 images, 128 views and 128 attachment sets,
// and a render target costs one of each. 16 is far below that and still more filters than
// h2d composes in one frame; past it the filter is skipped and says so once, rather than
// failing inside sokol where the message names no node.
const MAX_POOLED_TARGETS: int32 = 16;
const poolRT: Vec<uint32> = [];
const poolW: Vec<int32> = [];
const poolH: Vec<int32> = [];
const poolBusy: Vec<boolean> = [];
let poolExhaustedReported: boolean = false;

// Called once per frame, before the walk: every target from last frame becomes available.
// Exported so `filter.ms` can take a scratch target for its own downsample chain rather
// than carrying a second, weaker kernel.
export function acquireFrameTarget(w: int32, h: int32): uint32 { return acquireTarget(w, h); }
export function renderTargetsAlive(): int32 { return poolRT.length as int32; }

export function releaseTargets(): void {
	for (let i: int32 = 0; i < (poolBusy.length as int32); i++) { poolBusy[i] = false; }
}

function acquireTarget(w: int32, h: int32): uint32 {
	for (let i: int32 = 0; i < (poolRT.length as int32); i++) {
		if (!poolBusy[i] && poolW[i] == w && poolH[i] == h) {
			poolBusy[i] = true;
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
	poolBusy.push(true);
	return rt;
}

function ceilToInt(v: float32): int32 {
	const t: int32 = v as int32;
	return (v > (t as float32)) ? t + 1 : t;
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

export function draw(this n: Node2D, a: float32, vw: float32, vh: float32): void {
	if (!n.visible) { return; }
	if (n.filter.kind !== FilterKind.None) {
		drawFiltered(n, a, vw, vh);
		return;
	}
	drawContent(n, a, vw, vh);
}

function drawContent(n: Node2D, a: float32, vw: float32, vh: float32): void {
	const world = n.cachedWorld;
	const na: float32 = a * n.alpha;
	const col = rgba(n.color.r, n.color.g, n.color.b, n.color.a * na);
	const lb = localBounds(n);
	const tl = vec2(lb.xMin, lb.yMin) * world;
	const tr = vec2(lb.xMax, lb.yMin) * world;
	const br = vec2(lb.xMax, lb.yMax) * world;
	const bl = vec2(lb.xMin, lb.yMax) * world;
	const vb = boxRenderBounds(n, world, lb);
	const vtl = vec2(vb.xMin, vb.yMin) * world;
	const vtr = vec2(vb.xMax, vb.yMin) * world;
	const vbr = vec2(vb.xMax, vb.yMax) * world;
	const vbl = vec2(vb.xMin, vb.yMax) * world;
	const onscreen: boolean =
		fmax4(vtl.x, vtr.x, vbr.x, vbl.x) >= 0.0 && fmin4(vtl.x, vtr.x, vbr.x, vbl.x) <= vw
		&& fmax4(vtl.y, vtr.y, vbr.y, vbl.y) >= 0.0 && fmin4(vtl.y, vtr.y, vbr.y, vbl.y) <= vh
		&& clipIntersectsQuad(vtl, vtr, vbr, vbl);
	if (onscreen) {
		emitNode(
			n, world, na, col, tl, tr, br, bl,
			lb.xMax - lb.xMin, lb.yMax - lb.yMin, vec2(lb.xMin, lb.yMin), vb,
		);
	}
	const masking: boolean = n.kind === DrawKind.Mask;
	let clipSupported: boolean = true;
	if (masking) {
		clipSupported = pushClip(tl, tr, br, bl);
	}
	if (clipSupported) {
		if (n.childrenDirty) { sortByZ(n.children); n.childrenDirty = false; }
		for (const ch of n.children) {
			ch.draw(na, vw, vh);
		}
	}
	if (masking) {
		popClip();
	}
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
function drawFiltered(n: Node2D, a: float32, vw: float32, vh: float32): void {
	const b = emptyBounds();
	n.getBounds(b);
	if (b.xMin >= b.xMax || b.yMin >= b.yMax) { return; }
	const pad: float32 = n.filter.radius;
	let xMin: float32 = b.xMin - pad;
	let yMin: float32 = b.yMin - pad;
	let xMax: float32 = b.xMax + pad;
	let yMax: float32 = b.yMax + pad;
	if (n.filter.kind === FilterKind.DropShadow) {
		if (n.filter.offsetX < 0.0) { xMin = xMin + n.filter.offsetX; } else { xMax = xMax + n.filter.offsetX; }
		if (n.filter.offsetY < 0.0) { yMin = yMin + n.filter.offsetY; } else { yMax = yMax + n.filter.offsetY; }
	}
	// Clipped to the viewport: a target is only ever needed for the part that can be seen.
	if (xMin < 0.0) { xMin = 0.0; }
	if (yMin < 0.0) { yMin = 0.0; }
	if (xMax > vw) { xMax = vw; }
	if (yMax > vh) { yMax = vh; }
	if (xMax <= xMin || yMax <= yMin) { return; }
	const dpi: float32 = currentRenderScale();
	xMin = (Math.floor(xMin * dpi) as float32) / dpi;
	yMin = (Math.floor(yMin * dpi) as float32) / dpi;
	const rtW: int32 = ceilToInt((xMax - xMin) * dpi);
	const rtH: int32 = ceilToInt((yMax - yMin) * dpi);
	if (rtW <= 0 || rtH <= 0) { return; }
	const logicalW: float32 = (rtW as float32) / dpi;
	const logicalH: float32 = (rtH as float32) / dpi;
	const rt: uint32 = acquireTarget(rtW, rtH);
	if (rt == 0) { return; }

	// The subtree at alpha 1, in target space. One walk, one sync, no GPU call.
	//
	// `drawContent` multiplies the alpha it is given by `n.alpha` - that is its contract for
	// every other node - so handing it 1.0 would still put the group's own alpha into the
	// target and then apply it again at the composite. Measured before this line existed: a
	// group at 0.5 came out at 0.49 of the background instead of 0.5, and its two overlapping
	// children still double-blended against each other. The filter takes the node's alpha
	// over for the length of the target, which is what h2d does by carrying it on the filter
	// rather than on the object (`h2d/Object.hx:896-956`).
	const heldAlpha: float32 = n.alpha;
	n.alpha = 1.0;
	beginTarget(rt, logicalW, logicalH, dpi, xMin, yMin, transparent);
	drawContent(n, 1.0, vw, vh);
	endTarget();
	n.alpha = heldAlpha;

	let src: uint32 = rt;
	if (n.filter.radius > 0.0) {
		src = blurTargetPooled(rt, rtW, rtH, n.filter.radius * dpi);
		if (src == 0) { return; }
	}

	const na: float32 = a * n.alpha;
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
	if (n.filter.kind === FilterKind.Blur) {
		imageQuad(rtTile, vec2(xMin, yMin), vec2(qx1, yMin), vec2(qx1, qy1), vec2(xMin, qy1),
			rgba(1.0, 1.0, 1.0, na), n.blend);
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
	setEffect(colorMatrixAlphaOnly(n.filter.gain),
		rgba(n.filter.color.r, n.filter.color.g, n.filter.color.b, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
	const ox: float32 = n.filter.kind === FilterKind.DropShadow ? n.filter.offsetX : 0.0;
	const oy: float32 = n.filter.kind === FilterKind.DropShadow ? n.filter.offsetY : 0.0;
	const fblend: BlendMode = n.filter.kind === FilterKind.Glow ? BlendMode.Add : BlendMode.Alpha;
	imageQuad(rtTile, vec2(xMin + ox, yMin + oy), vec2(qx1 + ox, yMin + oy),
		vec2(qx1 + ox, qy1 + oy), vec2(xMin + ox, qy1 + oy), rgba(1.0, 1.0, 1.0, na), fblend);
	setEffect([], rgba(0.0, 0.0, 0.0, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
	const sharpTile = tile(rtViewId(rt), rtW as float32, rtH as float32);
	imageQuad(sharpTile, vec2(xMin, yMin), vec2(qx1, yMin), vec2(qx1, qy1), vec2(xMin, qy1),
		rgba(1.0, 1.0, 1.0, na), n.blend);
}

export function getBounds(this n: Node2D, ref out: Bounds): void {
	const lb = localBounds(n);
	const world = n.cachedWorld;
	const vb = boxRenderBounds(n, world, lb);
	if (vb.xMax > vb.xMin && vb.yMax > vb.yMin) {
		const btl = vec2(vb.xMin, vb.yMin) * world;
		const btr = vec2(vb.xMax, vb.yMin) * world;
		const bbr = vec2(vb.xMax, vb.yMax) * world;
		const bbl = vec2(vb.xMin, vb.yMax) * world;
		const bxMin: float32 = fmin4(btl.x, btr.x, bbr.x, bbl.x);
		const byMin: float32 = fmin4(btl.y, btr.y, bbr.y, bbl.y);
		const bxMax: float32 = fmax4(btl.x, btr.x, bbr.x, bbl.x);
		const byMax: float32 = fmax4(btl.y, btr.y, bbr.y, bbl.y);
		if (bxMin < out.xMin) { out.xMin = bxMin; }
		if (byMin < out.yMin) { out.yMin = byMin; }
		if (bxMax > out.xMax) { out.xMax = bxMax; }
		if (byMax > out.yMax) { out.yMax = byMax; }
	}
	for (const ch of n.children) {
		if (ch.visible) { ch.getBounds(out); }
	}
}

function requireLabel(n: Node2D, call: string): void {
	if (n.kind === DrawKind.Label) { return; }
	console.log(`void2d: ${call} asked of a ${n.kind.toString()} node; only a Label has text`);
	unreachable;
}

export function textLayout(this n: Node2D): TextLayout {
	requireLabel(n, "textLayout");
	shapeIfChanged(n);
	return labelTexts[n.payload].layout;
}

export function textWidth(this n: Node2D): float32 {
	requireLabel(n, "textWidth");
	shapeIfChanged(n);
	return labelTexts[n.payload].layout.width;
}

export function textHeight(this n: Node2D): float32 {
	requireLabel(n, "textHeight");
	shapeIfChanged(n);
	return labelTexts[n.payload].layout.height;
}

export function calcTextWidth(this n: Node2D, text: string): float32 {
	requireLabel(n, "calcTextWidth");
	return layoutWidth(text, labelStyle(n));
}

export function splitText(this n: Node2D, text: string): string {
	requireLabel(n, "splitText");
	return TextLayout.layout(text, labelStyle(n)).splitText(text);
}
