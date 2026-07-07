// void2d rendering — sync (transform cache + content bounds), draw (dispatch + cull + filter),
// getBounds. Extracted from node.ms so each file has one responsibility.

import { Node2D, DrawKind } from "./node";
import { fillQuad, imageQuad, imageQuadUV, drawStaticText, drawStaticGraphics, uploadStaticMesh, destroyStaticMesh, setEffect, setSmooth, pushClip, popClip, atlasGen, begin2d, end2d, setRTMode, blurPass, allocRenderTarget, freeRenderTarget, rtViewId, beginRT, endRT } from "./draw";
import { layoutText, buildGlyphMesh } from "./text";
import { Vec2, Color, Transform2D, Bounds, FilterKind, BlendMode, vec2, rgba, tile, trs2d, emptyBounds } from "./types";
import { colorMatrixAlphaOnly } from "./effect";

function sortByZ(cs: Node2D[]): void {
	const m: int32 = cs.length as int32;
	let i: int32 = 1;
	while (i < m) {
		const cur = cs[i];
		let j: int32 = i - 1;
		while (j >= 0 && cs[j].zIndex > cur.zIndex) {
			cs[j + 1] = cs[j];
			j = j - 1;
		}
		cs[j + 1] = cur;
		i = i + 1;
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

function localBounds(n: Node2D): Bounds {
	if (n.kind === DrawKind.Graphics || n.kind === DrawKind.Label) {
		return { xMin: n.contentXMin, yMin: n.contentYMin, xMax: n.contentXMax, yMax: n.contentYMax };
	}
	return { xMin: -n.pivotX, yMin: -n.pivotY, xMax: n.w - n.pivotX, yMax: n.h - n.pivotY };
}

function renderScaleGrid(n: Node2D, world: Transform2D, col: Color): void {
	const t = n.sheet;
	const srcW: float32 = t.w;
	const srcH: float32 = t.h;
	if (srcW <= 0.0 || srcH <= 0.0) { return; }
	const sx: float32[] = [0.0, n.borderL, srcW - n.borderR, srcW];
	const sy: float32[] = [0.0, n.borderT, srcH - n.borderB, srcH];
	const dx: float32[] = [0.0, n.borderL, n.w - n.borderR, n.w];
	const dy: float32[] = [0.0, n.borderT, n.h - n.borderB, n.h];
	const du: float32 = t.u1 - t.u0;
	const dv: float32 = t.v1 - t.v0;
	let cj: int32 = 0;
	while (cj < 3) {
		let ci: int32 = 0;
		while (ci < 3) {
			const u0: float32 = t.u0 + (sx[ci] / srcW) * du;
			const u1: float32 = t.u0 + (sx[ci + 1] / srcW) * du;
			const v0: float32 = t.v0 + (sy[cj] / srcH) * dv;
			const v1: float32 = t.v0 + (sy[cj + 1] / srcH) * dv;
			const a = vec2(dx[ci], dy[cj]) * world;
			const b = vec2(dx[ci + 1], dy[cj]) * world;
			const c = vec2(dx[ci + 1], dy[cj + 1]) * world;
			const d = vec2(dx[ci], dy[cj + 1]) * world;
			imageQuadUV(t.view, u0, v0, u1, v1, a, b, c, d, col, n.blend);
			ci = ci + 1;
		}
		cj = cj + 1;
	}
}

export function sync(this n: Node2D, parentWorld: Transform2D, parentChanged: boolean): void {
	const localChanged: boolean = n.dirty || n.x != n.lastX || n.y != n.lastY || n.scaleX != n.lastSX || n.scaleY != n.lastSY || n.rotation != n.lastRot;
	if (localChanged) {
		n.cachedLocal = trs2d(n.x, n.y, n.rotation, n.scaleX, n.scaleY);
		n.lastX = n.x; n.lastY = n.y; n.lastSX = n.scaleX; n.lastSY = n.scaleY; n.lastRot = n.rotation;
		n.dirty = false;
	}
	const worldChanged: boolean = localChanged || parentChanged;
	if (worldChanged) {
		n.cachedWorld = parentWorld * n.cachedLocal;
	}
	if (n.kind === DrawKind.Label) {
		const textChanged: boolean = n.textDirty || n.size != n.lastSize || n.align != n.lastAlign
			|| n.letterSpacing != n.lastLetterSpacing || n.lineSpacing != n.lastLineSpacing
			|| n.maxWidth != n.lastMaxWidth || !n.text.equals(n.lastText)
			|| n.fontId != n.lastFontId || atlasGen() != n.lastAtlasGen;
		if (textChanged) {
			const glyphs: float32[] = layoutText(n.size, n.text, n.align, n.letterSpacing, n.lineSpacing, n.maxWidth, n.fontId);
			n.contentXMin = 1e30; n.contentYMin = 1e30; n.contentXMax = -1e30; n.contentYMax = -1e30;
			let gi: int32 = 0;
			while (gi + 8 <= glyphs.length as int32) {
				const gx0: float32 = glyphs[gi]; const gy0: float32 = glyphs[gi + 1];
				const gx1: float32 = glyphs[gi + 4]; const gy1: float32 = glyphs[gi + 5];
				if (gx0 < n.contentXMin) { n.contentXMin = gx0; }
				if (gy0 < n.contentYMin) { n.contentYMin = gy0; }
				if (gx1 > n.contentXMax) { n.contentXMax = gx1; }
				if (gy1 > n.contentYMax) { n.contentYMax = gy1; }
				gi = gi + 8;
			}
			if (n.contentXMin > n.contentXMax) { n.contentXMin = 0.0; n.contentXMax = 0.0; n.contentYMin = 0.0; n.contentYMax = 0.0; }
			const tm: float32[] = buildGlyphMesh(glyphs);
			const tvc: int32 = (tm.length as int32) / 8;
			if (n.txtBuf != 0) { destroyStaticMesh(n.txtBuf); n.txtBuf = 0; }
			if (tvc > 0) { n.txtBuf = uploadStaticMesh(tm, tvc); }
			n.txtVertCount = tvc;
			n.lastText = n.text; n.lastSize = n.size; n.lastAlign = n.align;
			n.lastLetterSpacing = n.letterSpacing; n.lastLineSpacing = n.lineSpacing; n.lastMaxWidth = n.maxWidth;
			n.textDirty = false;
			n.lastAtlasGen = atlasGen();
			n.lastFontId = n.fontId;
		}
	}
	if (n.kind === DrawKind.Graphics && n.gfxDirty) {
		n.contentXMin = 1e30; n.contentYMin = 1e30; n.contentXMax = -1e30; n.contentYMax = -1e30;
		let mi: int32 = 0;
		while (mi + 8 <= n.mesh.length as int32) {
			const mx: float32 = n.mesh[mi]; const my: float32 = n.mesh[mi + 1];
			if (mx < n.contentXMin) { n.contentXMin = mx; }
			if (my < n.contentYMin) { n.contentYMin = my; }
			if (mx > n.contentXMax) { n.contentXMax = mx; }
			if (my > n.contentYMax) { n.contentYMax = my; }
			mi = mi + 8;
		}
		if (n.contentXMin > n.contentXMax) { n.contentXMin = 0.0; n.contentXMax = 0.0; n.contentYMin = 0.0; n.contentYMax = 0.0; }
		const vc: int32 = (n.mesh.length as int32) / 8;
		if (n.gfxBuf != 0) { destroyStaticMesh(n.gfxBuf); n.gfxBuf = 0; }
		if (vc > 0) { n.gfxBuf = uploadStaticMesh(n.mesh, vc); }
		n.gfxVertCount = vc;
		n.gfxDirty = false;
	}
	for (const ch of n.children) {
		ch.sync(n.cachedWorld, worldChanged);
	}
}

function emitNode(n: Node2D, world: Transform2D, na: float32, col: Color, tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2): void {
	setEffect(n.colorMatrix, n.colorAdd, n.colorKey);
	setSmooth(n.smooth);
	if (n.kind === DrawKind.Rect) {
		fillQuad(tl, tr, br, bl, col, n.blend);
	} else if (n.kind === DrawKind.Sprite) {
		imageQuad(n.sheet, tl, tr, br, bl, col, n.blend);
	} else if (n.kind === DrawKind.Anim) {
		const len: int32 = n.frames.length as int32;
		if (len > 0) {
			const fi: int32 = ((n.clock * n.fps) as int32) % len;
			imageQuad(n.frames[fi], tl, tr, br, bl, col, n.blend);
		}
	} else if (n.kind === DrawKind.Label) {
		drawStaticText(n.txtBuf, n.txtVertCount, world, n.color, na, n.blend, n.colorMatrix, n.colorAdd, n.colorKey, n.smooth);
	} else if (n.kind === DrawKind.Graphics) {
		drawStaticGraphics(n.gfxBuf, n.gfxVertCount, n.gfxView, n.blend, world, na, n.colorMatrix, n.colorAdd, n.colorKey, n.smooth);
	} else if (n.kind === DrawKind.ScaleGrid) {
		renderScaleGrid(n, world, col);
	}
}

let scratchRT: uint32 = 0;
let scratchRTW: int32 = 0;
let scratchRTH: int32 = 0;

function ensureScratch(w: int32, h: int32): void {
	if (scratchRT == 0 || scratchRTW < w || scratchRTH < h) {
		if (scratchRT != 0) { freeRenderTarget(scratchRT); }
		scratchRT = allocRenderTarget(w, h);
		scratchRTW = w;
		scratchRTH = h;
	}
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
	const onscreen: boolean =
		fmax4(tl.x, tr.x, br.x, bl.x) >= 0.0 && fmin4(tl.x, tr.x, br.x, bl.x) <= vw
		&& fmax4(tl.y, tr.y, br.y, bl.y) >= 0.0 && fmin4(tl.y, tr.y, br.y, bl.y) <= vh;
	if (onscreen) {
		emitNode(n, world, na, col, tl, tr, br, bl);
	}
	const masking: boolean = n.kind === DrawKind.Mask;
	if (masking) {
		pushClip(fmin4(tl.x, tr.x, br.x, bl.x), fmin4(tl.y, tr.y, br.y, bl.y),
			fmax4(tl.x, tr.x, br.x, bl.x), fmax4(tl.y, tr.y, br.y, bl.y));
	}
	if (n.childrenDirty) { sortByZ(n.children); n.childrenDirty = false; }
	for (const ch of n.children) {
		ch.draw(na, vw, vh);
	}
	if (masking) {
		popClip();
	}
}

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
	const rtW: int32 = (xMax - xMin) as int32;
	const rtH: int32 = (yMax - yMin) as int32;
	if (rtW <= 0 || rtH <= 0) { return; }
	if (n.filterRT == 0 || n.filterRTW < rtW || n.filterRTH < rtH) {
		if (n.filterRT != 0) { freeRenderTarget(n.filterRT); }
		n.filterRT = allocRenderTarget(rtW, rtH);
		n.filterRTW = rtW;
		n.filterRTH = rtH;
	}
	beginRT(n.filterRT, 0.0, 0.0, 0.0, 0.0);
	begin2d(rtW, rtH, 1.0);
	setRTMode(true);
	const rtWorld: Transform2D = trs2d(-xMin, -yMin, 0.0, 1.0, 1.0) * n.cachedWorld;
	if (n.childrenDirty) { sortByZ(n.children); n.childrenDirty = false; }
	for (const ch of n.children) {
		ch.sync(rtWorld, true);
		ch.draw(a * n.alpha, rtW as float32, rtH as float32);
	}
	setRTMode(false);
	end2d();
	endRT();
	if (n.filter.radius > 0.0) {
		ensureScratch(rtW, rtH);
		beginRT(scratchRT, 0.0, 0.0, 0.0, 0.0);
		begin2d(rtW, rtH, 1.0);
		setRTMode(true);
		blurPass(rtViewId(n.filterRT), n.filter.radius / (rtW as float32), 0.0);
		setRTMode(false);
		end2d();
		endRT();
		beginRT(n.filterRT, 0.0, 0.0, 0.0, 0.0);
		begin2d(rtW, rtH, 1.0);
		setRTMode(true);
		blurPass(rtViewId(scratchRT), 0.0, n.filter.radius / (rtH as float32));
		setRTMode(false);
		end2d();
		endRT();
	}
	const na: float32 = a * n.alpha;
	const rtTile = tile(rtViewId(n.filterRT), rtW as float32, rtH as float32);
	for (const ch of n.children) {
		ch.sync(n.cachedWorld, true);
	}
	if (n.filter.kind === FilterKind.Blur) {
		imageQuad(rtTile, vec2(xMin, yMin), vec2(xMax, yMin), vec2(xMax, yMax), vec2(xMin, yMax), rgba(1.0, 1.0, 1.0, na), n.blend);
	} else {
		setEffect(colorMatrixAlphaOnly(n.filter.gain), rgba(n.filter.color.r, n.filter.color.g, n.filter.color.b, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
		const ox: float32 = n.filter.kind === FilterKind.DropShadow ? n.filter.offsetX : 0.0;
		const oy: float32 = n.filter.kind === FilterKind.DropShadow ? n.filter.offsetY : 0.0;
		const fblend: BlendMode = n.filter.kind === FilterKind.Glow ? BlendMode.Add : BlendMode.Alpha;
		imageQuad(rtTile, vec2(xMin + ox, yMin + oy), vec2(xMax + ox, yMin + oy), vec2(xMax + ox, yMax + oy), vec2(xMin + ox, yMax + oy), rgba(1.0, 1.0, 1.0, 1.0), fblend);
		setEffect([], rgba(0.0, 0.0, 0.0, 0.0), rgba(0.0, 0.0, 0.0, 0.0));
		drawContent(n, na, vw, vh);
	}
}

export function getBounds(this n: Node2D, out: Bounds): void {
	const lb = localBounds(n);
	if (lb.xMax > lb.xMin && lb.yMax > lb.yMin) {
		const world = n.cachedWorld;
		const btl = vec2(lb.xMin, lb.yMin) * world;
		const btr = vec2(lb.xMax, lb.yMin) * world;
		const bbr = vec2(lb.xMax, lb.yMax) * world;
		const bbl = vec2(lb.xMin, lb.yMax) * world;
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
