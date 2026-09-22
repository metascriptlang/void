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
	atlasGen,
	beginTarget,
	endTarget,
	blurPass,
	allocRenderTarget,
	rtViewId,
} from "./draw";
import { layoutText, buildGlyphMesh } from "./text";
import { InstanceMode } from "./instance";
import { fontView } from "./draw";
import { Vec2, Color, Transform2D, Bounds, FilterKind, BlendMode, Smooth, vec2, rgba, tile, trs2d, emptyBounds } from "./types";
import { colorMatrixAlphaOnly } from "./effect";
import { NO_BOX_STYLE, boxStyles } from "./boxStyle";
import { axisAligned, snapBoxEdges, snapStroke } from "./snap";
import {
	GraphicsOpKind, GRAPHICS_OP_FLOATS, GFX_OP_KIND, GFX_OP_VERTEX_OFFSET,
	GFX_OP_VERTEX_COUNT, GFX_OP_SPACE, GFX_OP_DITHER, GFX_OP_MIDDLE,
	GFX_OP_COLOR0, GFX_OP_COLOR1, GFX_OP_COLOR2, GFX_OP_PARAMS,
} from "./graphics";

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
			// Read BEFORE laying out, not after. Laying this label out can fill the atlas and
			// grow it, and `fonsExpandAtlas` changes the normalised texture size - so quads
			// produced before the growth carry UVs for the old size while `emitNode` binds the
			// newest atlas. Recording the generation from *after* the layout meant the one label
			// whose own text triggered the growth saw no change next frame and kept its wrong
			// UVs permanently. Taking it first leaves `lastAtlasGen` behind the current one
			// whenever a growth happened during this layout, so the label is laid out again next
			// frame and corrects itself.
			//
			// What remains is one transient frame: labels laid out earlier in the same frame hold
			// old-size UVs until their own next sync. A golden never sees it - the runner draws
			// three frames and captures the last two - and P3 removes the class with fontstash.
			// `tests/PENDING.md atlas-resize-transient-frame` carries it.
			const genBeforeLayout: int32 = atlasGen();
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
			// The glyph mesh stays on the node in LOCAL space and is transformed into the
			// frame's stream when it is emitted. It used to be destroyed and re-created as
			// an sg_buffer on every text change (VOID2D.md "Known defects"), which is both
			// the buffer churn and the reason only about 126 Labels could draw at all.
			n.mesh = buildGlyphMesh(glyphs);
			n.records = glyphs;
			n.meshVertCount = (n.mesh.length as int32) / 8;
			n.lastText = n.text; n.lastSize = n.size; n.lastAlign = n.align;
			n.lastLetterSpacing = n.letterSpacing; n.lastLineSpacing = n.lineSpacing; n.lastMaxWidth = n.maxWidth;
			n.textDirty = false;
			n.lastAtlasGen = genBeforeLayout;
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
		n.meshVertCount = (n.mesh.length as int32) / 8;
		n.gfxDirty = false;
	}
	for (const ch of n.children) {
		ch.sync(n.cachedWorld, worldChanged);
	}
}

function emitNode(
	n: Node2D, world: Transform2D, na: float32, col: Color,
	tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2, sizeX: float32, sizeY: float32, lbMin: Vec2,
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
	if (n.kind === DrawKind.Rect) {
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
			}
			// cardOneInstance: a shadowed box is ONE instance carrying shadow, fill and
			// border. The quad spans the kernel's reach - 3 sigma plus the offset's own
			// displacement, per axis, in LOCAL units so a rotated card's shadow follows its
			// axes; an inset stays inside the element and does not inflate. params1 carries
			// (offsetX, offsetY, sigma, inset) and the extra colour is the shadow; the shader
			// derives the box's half extents back from this same margin formula, so the two
			// are one contract, mirrored like aaWidthForAffine.
			const shadowOn: boolean = n.payload != NO_BOX_STYLE
				&& boxStyles[n.payload].shadowColor.a > 0.0;
			let qx: float32 = tl.x;
			let qy: float32 = tl.y;
			let qw: float32 = sizeX;
			let qh: float32 = sizeY;
			let shadowColor: Color = transparent;
			let sp0: float32 = 0.0;
			let sp1: float32 = 0.0;
			let sp2: float32 = 0.0;
			let sp3: float32 = 0.0;
			if (shadowOn) {
				const st = boxStyles[n.payload];
				const sigma: float32 = st.shadowBlur;
				const ax: float32 = st.shadowOffsetX < 0.0 ? -st.shadowOffsetX : st.shadowOffsetX;
				const ay: float32 = st.shadowOffsetY < 0.0 ? -st.shadowOffsetY : st.shadowOffsetY;
				const mx: float32 = st.shadowInset ? 0.0 : 3.0 * sigma + ax;
				const my: float32 = st.shadowInset ? 0.0 : 3.0 * sigma + ay;
				const quadMin = vec2(lbMin.x - mx, lbMin.y - my) * world;
				qx = quadMin.x;
				qy = quadMin.y;
				qw = sizeX + 2.0 * mx;
				qh = sizeY + 2.0 * my;
				sp0 = st.shadowOffsetX;
				sp1 = st.shadowOffsetY;
				sp2 = sigma;
				sp3 = st.shadowInset ? 1.0 : 0.0;
				const sc: Color = st.shadowColor;
				shadowColor = rgba(sc.r, sc.g, sc.b, sc.a * na);
			}

			// Device-pixel snapping, axis-aligned only (snap.ms carries the why). The shadow's
			// offset rides in local units, so it follows the snapped box by construction.
			if (axisAligned(world.a, world.b, world.c, world.d)) {
				const lbx0: float32 = (qx - world.tx) / world.a;
				const lby0: float32 = (qy - world.ty) / world.d;
				const snapped = snapBoxEdges(lbx0, lby0, qw, qh, world.a, world.tx, world.d, world.ty);
				qx = snapped[0] * world.a + world.tx;
				qy = snapped[1] * world.d + world.ty;
				qw = snapped[2];
				qh = snapped[3];
				borderL = snapStroke(borderL * world.a) / world.a;
				borderR = snapStroke(borderR * world.a) / world.a;
				borderT = snapStroke(borderT * world.d) / world.d;
				borderB = snapStroke(borderB * world.d) / world.d;
			}
			drawUiInstance(InstanceMode.Box, fontView(), n.blend, world, qx, qy, qw, qh,
				radiusTL, radiusTR, radiusBR, radiusBL,
				borderL, borderT, borderR, borderB,
				0.0, 0.0, 0.0,
				sp0, sp1, sp2, sp3,
				col, edge, shadowColor);
		} else {
			fillQuad(tl, tr, br, bl, col, n.blend);
		}
	} else if (n.kind === DrawKind.Sprite) {
		if (instanced) {
			drawSpriteAffine(n.sheet.view, n.blend, world, tl.x, tl.y, sizeX, sizeY,
				n.sheet.u0, n.sheet.v0, n.sheet.u1, n.sheet.v1, col);
		} else {
			imageQuad(n.sheet, tl, tr, br, bl, col, n.blend);
		}
	} else if (n.kind === DrawKind.Anim) {
		const len: int32 = n.frames.length as int32;
		if (len > 0) {
			const fi: int32 = ((n.clock * n.fps) as int32) % len;
			const fr = n.frames[fi];
			if (instanced) {
				drawSpriteAffine(fr.view, n.blend, world, tl.x, tl.y, sizeX, sizeY,
					fr.u0, fr.v0, fr.u1, fr.v1, col);
			} else {
				imageQuad(fr, tl, tr, br, bl, col, n.blend);
			}
		}
	} else if (n.kind === DrawKind.Label) {
		// Glyph mode: one instance per shaped quad, against the same glyph view the card above
		// binds, so a card and its label are one run and not two draws. The atlas is white in
		// rgb and carries coverage in alpha, so the tint is the whole fill and the shader turns
		// the geometric ramp off — fontstash rasterized the antialiasing into the texel, and a
		// coverage ramp on top of it would soften every glyph edge twice. The mesh path stays
		// for the colour pipeline, which the UI program cannot express.
		if (uiInstancingAvailable()) {
			const quads: float32[] = n.records;
			const total: int32 = quads.length as int32;
			let gi: int32 = 0;
			while (gi + 8 <= total) {
				// The instance's affine lane carries only the linear part; the translation
				// rides in the origin, world-space, exactly as `tl` does for the card. Same
				// arithmetic drawMesh applied per vertex, once per quad.
				const ox: float32 = world.a * quads[gi] + world.c * quads[gi + 1] + world.tx;
				const oy: float32 = world.b * quads[gi] + world.d * quads[gi + 1] + world.ty;
				drawUiInstance(InstanceMode.Glyph, fontView(), n.blend, world,
					ox, oy, quads[gi + 4] - quads[gi], quads[gi + 5] - quads[gi + 1],
					quads[gi + 2], quads[gi + 3], quads[gi + 6], quads[gi + 7],
					0.0, 0.0, 0.0, 0.0,
					0.0, 0.0, 0.0,
					0.0, 0.0, 0.0, 0.0,
					col, transparent, transparent);
				gi = gi + 8;
			}
		} else {
			// Glyph coverage is white in the atlas, so the label's colour is the tint.
			drawMesh(n.mesh, fontView(), n.blend, world, n.color, na);
		}
	} else if (n.kind === DrawKind.Graphics) {
		const ops: float32[] = n.records;
		const opTotal: int32 = ops.length as int32;
		if (opTotal == 0) {
			drawMesh(n.mesh, n.gfxView, n.blend, world, rgba(1.0, 1.0, 1.0, 1.0), na);
		} else {
			let oi: int32 = 0;
			while (oi + GRAPHICS_OP_FLOATS <= opTotal) {
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
				oi = oi + GRAPHICS_OP_FLOATS;
			}
		}
	} else if (n.kind === DrawKind.ScaleGrid) {
		renderScaleGrid(n, world, col);
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
		beginTarget(dst, dw as float32, dh as float32, 0.0, 0.0, transparent);
		blitTarget(src, dw as float32, dh as float32);
		endTarget();
		src = dst;
		sw = dw;
		sh = dh;
		r = r * 0.5;
	}
	const tmp: uint32 = acquireTarget(sw, sh);
	if (tmp == 0) { return 0; }
	beginTarget(tmp, sw as float32, sh as float32, 0.0, 0.0, transparent);
	blurPass(rtViewId(src), 1.0 / (sw as float32), 0.0);
	endTarget();
	const out: uint32 = acquireTarget(sw, sh);
	if (out == 0) { return 0; }
	beginTarget(out, sw as float32, sh as float32, 0.0, 0.0, transparent);
	blurPass(rtViewId(tmp), 0.0, 1.0 / (sh as float32));
	endTarget();
	return out;
}

// One half-scale copy. `BlendMode.None` writes the source through instead of compositing it
// over the target's transparent black, which would otherwise darken every edge texel.
function blitTarget(src: uint32, w: float32, h: float32): void {
	// Says what it needs rather than inheriting it. The emitter's sampler and colour pipeline
	// are sticky and were last set by whatever node was emitted before this filter, so a
	// scene with `defaultSmooth = false` point-sampled every halving step - which turns
	// guardrail 3's "downsample by 2^k then blur at one texel" back into a comb - and a
	// grayscale sibling tinted the downsample. `void2dBlur` hardcodes linear-clamp for its tap
	// pass for exactly this reason; this had been left to luck.
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
	const onscreen: boolean =
		fmax4(tl.x, tr.x, br.x, bl.x) >= 0.0 && fmin4(tl.x, tr.x, br.x, bl.x) <= vw
		&& fmax4(tl.y, tr.y, br.y, bl.y) >= 0.0 && fmin4(tl.y, tr.y, br.y, bl.y) <= vh
		&& clipIntersectsQuad(tl, tr, br, bl);
	if (onscreen) {
		emitNode(n, world, na, col, tl, tr, br, bl, lb.xMax - lb.xMin, lb.yMax - lb.yMin, vec2(lb.xMin, lb.yMin));
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
	const rtW: int32 = ceilToInt(xMax - xMin);
	const rtH: int32 = ceilToInt(yMax - yMin);
	if (rtW <= 0 || rtH <= 0) { return; }
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
	beginTarget(rt, rtW as float32, rtH as float32, xMin, yMin, transparent);
	drawContent(n, 1.0, vw, vh);
	endTarget();
	n.alpha = heldAlpha;

	let src: uint32 = rt;
	if (n.filter.radius > 0.0) {
		src = blurTargetPooled(rt, rtW, rtH, n.filter.radius);
		if (src == 0) { return; }
	}

	const na: float32 = a * n.alpha;
	// The target's own extent, not the bounds it was derived from: `rtW`/`rtH` are the ceiling
	// of `xMax - xMin`, so drawing the quad to `xMax` would resample the target by a fraction
	// of a pixel and soften what is supposed to be the sharp copy.
	const qx1: float32 = xMin + (rtW as float32);
	const qy1: float32 = yMin + (rtH as float32);
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
