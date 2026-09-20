// The builders behind tests/golden/table.ms. One function per row, in the table's order;
// `sceneBuilders()` returns them in that order and the runner refuses to start if the two
// lengths disagree — the renderer form of rexa's "the command table agrees with the parser"
// cross-check (docs/TESTING.md, "Distrust the harness before the engine").
//
// A golden records what the renderer DOES, not what it should do. Several builders below
// draw a known defect on purpose, so that the commit which fixes the defect has to
// regenerate exactly that group and nothing else.

import { Node2D, rect, sprite, label, graphics, mask, scaleGrid, at, addChild } from "../../src/void2d/node";
import {
	fillRoundedRect,
	strokeRect,
	fillEllipse,
	fillPie,
	fillRing,
	fillPolygon,
	strokePoly,
	cubicBezier,
	fillGradientRect,
	fillRadialGradient,
} from "../../src/void2d/graphics";
import { colorMatrixGrayscale } from "../../src/void2d/effect";
import { Scene, scene, add } from "../../src/void2d/scene";
import {
	Tile,
	Vec2,
	Color,
	rgba,
	tile,
	sub,
	flipX,
	flipY,
	vec2,
	BlendMode,
	Smooth,
	blurFilter,
	glowFilter,
	dropShadowFilter,
} from "../../src/void2d/types";
import { makeImage, makeView } from "../../src/sokol/gpu";
import {
	HARNESS_CLEAR_R,
	HARNESS_CLEAR_G,
	HARNESS_CLEAR_B,
	HARNESS_FILL_R,
	HARNESS_FILL_G,
	HARNESS_FILL_B,
	HARNESS_RECT_X,
	HARNESS_RECT_Y,
	HARNESS_RECT_W,
	HARNESS_RECT_H,
} from "./table";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../../src/assets/image";

const DARK: Color = { r: 0.08, g: 0.09, b: 0.12, a: 1.0 };
const LIGHT: Color = { r: 0.90, g: 0.91, b: 0.94, a: 1.0 };

// assets/test.png as a sheet, loaded at most once per process.
let sheetTile: Tile = { view: 0, u0: 0.0, v0: 0.0, u1: 1.0, v1: 1.0, w: 0.0, h: 0.0, texW: 0.0, texH: 0.0 };
let sheetLoaded: boolean = false;

function sheet(): Tile {
	if (!sheetLoaded) {
		const pixels = loadImageSync("assets/test.png", 4);
		const w: int32 = imageWidth();
		const h: int32 = imageHeight();
		sheetTile = tile(makeView(makeImage(pixels, w, h)), w as float32, h as float32);
		freeImage(pixels);
		sheetLoaded = true;
	}
	return sheetTile;
}

// ===== harness/ — the hand-computed scene; see table.ms for why its colours are what
// they are, and for the constants the comparator predicts it from =====

function byteColor(r: int32, g: int32, b: int32): Color {
	return rgba((r as float32) / 255.0, (g as float32) / 255.0, (b as float32) / 255.0, 1.0);
}

function harnessSolid(): Scene {
	const s = scene(byteColor(HARNESS_CLEAR_R, HARNESS_CLEAR_G, HARNESS_CLEAR_B));
	s.add(rect(
		HARNESS_RECT_W as float32,
		HARNESS_RECT_H as float32,
		byteColor(HARNESS_FILL_R, HARNESS_FILL_G, HARNESS_FILL_B),
	).at(HARNESS_RECT_X as float32, HARNESS_RECT_Y as float32));
	return s;
}

// ===== prim/ =====

function primRoundedRect(): Scene {
	const s = scene(DARK);
	const g = graphics().at(12.0, 12.0);
	g.fillRoundedRect(0.0, 0.0, 100.0, 60.0, 0.0, rgba(0.30, 0.55, 0.85, 1.0));
	g.fillRoundedRect(116.0, 0.0, 100.0, 60.0, 12.0, rgba(0.30, 0.55, 0.85, 1.0));
	g.fillRoundedRect(0.0, 72.0, 100.0, 60.0, 30.0, rgba(0.85, 0.55, 0.30, 1.0));
	g.fillRoundedRect(116.0, 72.0, 100.0, 60.0, 4.5, rgba(0.85, 0.55, 0.30, 1.0));
	s.add(g);
	return s;
}

function primStrokeRect(): Scene {
	const s = scene(DARK);
	const g = graphics().at(12.0, 12.0);
	g.strokeRect(0.0, 0.0, 100.0, 60.0, 1.0, rgba(0.92, 0.95, 1.0, 1.0));
	g.strokeRect(116.0, 0.0, 100.0, 60.0, 4.0, rgba(0.92, 0.95, 1.0, 1.0));
	g.strokeRect(0.0, 72.0, 100.0, 60.0, 9.0, rgba(0.45, 0.85, 0.60, 1.0));
	g.strokeRect(116.0, 72.0, 100.0, 60.0, 0.5, rgba(0.45, 0.85, 0.60, 1.0));
	s.add(g);
	return s;
}

function primEllipsePieRing(): Scene {
	const s = scene(DARK);
	const g = graphics();
	g.fillEllipse(56.0, 56.0, 44.0, 28.0, rgba(0.95, 0.75, 0.25, 1.0));
	g.fillPie(160.0, 56.0, 44.0, 0.0, 4.2, rgba(0.85, 0.40, 0.55, 1.0));
	g.fillRing(108.0, 124.0, 44.0, 25.0, -1.2, 4.5, rgba(0.45, 0.80, 0.55, 1.0));
	s.add(g);
	return s;
}

function primPolygonBezier(): Scene {
	const s = scene(DARK);
	const g = graphics();
	const arrow: Vec2[] = [
		vec2(14.0, 30.0),
		vec2(60.0, 30.0),
		vec2(60.0, 8.0),
		vec2(104.0, 50.0),
		vec2(60.0, 92.0),
		vec2(60.0, 70.0),
		vec2(14.0, 70.0),
	];
	g.fillPolygon(arrow, rgba(0.62, 0.50, 0.92, 1.0));
	const curve: Vec2[] = cubicBezier(
		vec2(120.0, 30.0),
		vec2(160.0, 0.0),
		vec2(180.0, 96.0),
		vec2(230.0, 60.0),
		32,
	);
	g.strokePoly(curve, 5.0, rgba(0.40, 0.75, 1.0, 1.0), false);
	const closed: Vec2[] = [
		vec2(140.0, 110.0),
		vec2(200.0, 110.0),
		vec2(220.0, 148.0),
		vec2(120.0, 148.0),
	];
	g.strokePoly(closed, 3.0, rgba(0.95, 0.60, 0.40, 1.0), true);
	s.add(g);
	return s;
}

// Per-vertex today: graphics.ms tessellates a gradient into vertex colours, which is what P2
// replaces with per-pixel sRGB and Oklab plus dither (VOID2D.md "Primitives").
function primGradientLinear(): Scene {
	const s = scene(DARK);
	const g = graphics().at(12.0, 12.0);
	g.fillGradientRect(0.0, 0.0, 100.0, 60.0, rgba(0.20, 0.45, 0.95, 1.0), rgba(0.95, 0.30, 0.55, 1.0), 0.0);
	g.fillGradientRect(116.0, 0.0, 100.0, 60.0, rgba(0.15, 0.75, 0.55, 1.0), rgba(0.98, 0.85, 0.25, 1.0), 1.5708);
	g.fillGradientRect(0.0, 72.0, 216.0, 60.0, rgba(0.02, 0.02, 0.03, 1.0), rgba(0.14, 0.14, 0.16, 1.0), 0.0);
	s.add(g);
	return s;
}

function primGradientRadial(): Scene {
	const s = scene(DARK);
	const g = graphics();
	g.fillRadialGradient(72.0, 80.0, 60.0, rgba(1.0, 1.0, 1.0, 1.0), rgba(0.30, 0.15, 0.60, 1.0));
	g.fillRadialGradient(186.0, 80.0, 52.0, rgba(0.98, 0.85, 0.25, 1.0), rgba(0.98, 0.85, 0.25, 0.0));
	s.add(g);
	return s;
}

// ===== xform/ =====

function card(w: float32, h: float32): Node2D {
	const g = graphics();
	g.fillRoundedRect(0.0, 0.0, w, h, 10.0, rgba(0.30, 0.55, 0.85, 1.0));
	g.strokeRect(0.0, 0.0, w, h, 2.0, rgba(0.92, 0.95, 1.0, 1.0));
	return g;
}

function xformRotate(): Scene {
	const s = scene(DARK);
	const upright = card(56.0, 36.0).at(40.0, 44.0);
	const tilted = card(56.0, 36.0).at(120.0, 44.0);
	tilted.rotation = 0.122173;
	const diagonal = card(56.0, 36.0).at(200.0, 44.0);
	diagonal.rotation = 0.785398;
	const oblique = card(56.0, 36.0).at(120.0, 120.0);
	oblique.rotation = 0.645772;
	s.add(upright);
	s.add(tilted);
	s.add(diagonal);
	s.add(oblique);
	return s;
}

function xformScale(): Scene {
	const s = scene(DARK);
	const half = card(56.0, 36.0).at(20.0, 60.0);
	half.scaleX = 0.5;
	half.scaleY = 0.5;
	const unit = card(56.0, 36.0).at(70.0, 60.0);
	const double = card(56.0, 36.0).at(140.0, 44.0);
	double.scaleX = 2.0;
	double.scaleY = 2.0;
	s.add(half);
	s.add(unit);
	s.add(double);
	return s;
}

// pivotX/Y is applied for Rect, Sprite and Anim, ignored by Graphics, Label and ScaleGrid,
// and reinterpreted by Mask. This row holds a Rect and a Graphics under the same rotation
// and the same pivot, so the inconsistency is in the picture; P2 replaces it with Tile.dx/dy.
function xformPivot(): Scene {
	const s = scene(DARK);
	const pivotedRect = rect(56.0, 36.0, rgba(0.30, 0.55, 0.85, 1.0)).at(70.0, 50.0);
	pivotedRect.pivotX = 28.0;
	pivotedRect.pivotY = 18.0;
	pivotedRect.rotation = 0.5236;
	const pivotedCard = card(56.0, 36.0).at(180.0, 50.0);
	pivotedCard.pivotX = 28.0;
	pivotedCard.pivotY = 18.0;
	pivotedCard.rotation = 0.5236;
	s.add(pivotedRect);
	s.add(pivotedCard);
	return s;
}

// The approximation VOID2D.md "Open" records: non-uniform scale on a rounded corner.
function xformNonUniform(): Scene {
	const s = scene(DARK);
	const wide = card(56.0, 36.0).at(20.0, 30.0);
	wide.scaleX = 3.0;
	const tall = card(56.0, 36.0).at(20.0, 90.0);
	tall.scaleY = 2.0;
	const skewed = card(56.0, 36.0).at(150.0, 90.0);
	skewed.scaleX = 2.0;
	skewed.scaleY = 0.5;
	skewed.rotation = 0.3491;
	s.add(wide);
	s.add(tall);
	s.add(skewed);
	return s;
}

// ===== snap/ =====

// Hairlines at three DPIs. Nothing snaps today, so a 1-logical-pixel rule at DPI 1.25 lands
// on 1.25 device pixels and the rasterizer decides; P2 lands the rules that make it exactly
// one device pixel, and a zero-width stroke exactly zero (VOID2D.md "Pixel snapping").
function snapHairlines(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 8; i++) {
		s.add(rect(180.0, 1.0, LIGHT).at(14.0, 12.0 + (i as float32) * 9.0));
	}
	s.add(rect(1.0, 80.0, LIGHT).at(210.0, 12.0));
	s.add(rect(2.0, 80.0, LIGHT).at(216.0, 12.0));
	s.add(rect(0.5, 80.0, LIGHT).at(224.0, 12.0));
	return s;
}

// A 7-logical-pixel box split in two at a moving fraction. Complementary rounding
// (GHOSTTY.md:61) is what makes the halves touch with no gap and no overlap; today each
// half rounds on its own.
function snapFractionalSplit(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 6; i++) {
		const x: float32 = 16.0 + (i as float32) * 34.0;
		const fraction: float32 = 0.5 + (i as float32) * 0.07;
		s.add(rect(7.0 * fraction, 60.0, rgba(0.95, 0.40, 0.35, 1.0)).at(x, 20.0));
		s.add(rect(7.0 * (1.0 - fraction), 60.0, rgba(0.35, 0.85, 0.50, 1.0)).at(x + 7.0 * fraction, 20.0));
	}
	return s;
}

function snapFractionalOrigin(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 8; i++) {
		const x: float32 = 14.0 + (i as float32) * 28.125;
		s.add(rect(20.0, 40.0, LIGHT).at(x, 20.0 + (i as float32) * 0.125));
	}
	return s;
}

// ===== clip/ =====

function clipNestedMasks(): Scene {
	const s = scene(DARK);
	const outer = mask(160.0, 110.0).at(30.0, 20.0);
	const inner = mask(90.0, 70.0).at(40.0, 25.0);
	inner.addChild(rect(200.0, 200.0, rgba(0.92, 0.52, 0.20, 1.0)).at(-30.0, -30.0));
	outer.addChild(rect(200.0, 40.0, rgba(0.30, 0.55, 0.85, 1.0)).at(-20.0, -10.0));
	outer.addChild(inner);
	s.add(outer);
	return s;
}

// render.ms:204 pushes the AABB of the rotated mask, so the clip is a screen-aligned box
// rather than the rotated rectangle. P2 replaces it with four edge distances and discard.
function clipRotatedMask(): Scene {
	const s = scene(DARK);
	const m = mask(120.0, 80.0).at(128.0, 80.0);
	m.rotation = 0.5236;
	m.pivotX = 60.0;
	m.pivotY = 40.0;
	m.addChild(rect(260.0, 260.0, rgba(0.92, 0.52, 0.20, 1.0)).at(-130.0, -130.0));
	s.add(m);
	return s;
}

// render.ms:191-201 culls against the viewport, not the active clip, so every row of this
// list is emitted even though the mask shows four of them. The picture is right and the cost
// is wrong, which is why the assertion that catches it belongs to T1 and not to this golden.
function clipScrolledList(): Scene {
	const s = scene(DARK);
	const m = mask(200.0, 90.0).at(28.0, 30.0);
	for (let i: int32 = 0; i < 40; i++) {
		const stripe: Color = i % 2 == 0 ? rgba(0.22, 0.26, 0.34, 1.0) : rgba(0.16, 0.19, 0.25, 1.0);
		m.addChild(rect(190.0, 18.0, stripe).at(5.0, (i as float32) * 22.0 - 240.0));
	}
	s.add(m);
	return s;
}

// ===== text/ =====

const CODE_LINE: string = "fn main() { let x: i32 = 42; }";

function textCode(): Scene {
	const s = scene(DARK);
	s.add(label(CODE_LINE, 13.0, rgba(0.86, 0.90, 0.98, 1.0)).at(10.0, 14.0));
	s.add(label(CODE_LINE, 13.0, rgba(0.86, 0.90, 0.98, 1.0)).at(10.5, 36.0));
	s.add(label("0123456789 iiiimmmm WAVE", 13.0, rgba(0.95, 0.80, 0.45, 1.0)).at(10.0, 58.0));
	s.add(label(CODE_LINE, 26.0, rgba(0.86, 0.90, 0.98, 1.0)).at(10.0, 82.0));
	return s;
}

function textWrapped(): Scene {
	const s = scene(DARK);
	const paragraph = label(
		"The quick brown fox jumps over the lazy void dog and keeps running.",
		16.0,
		rgba(0.82, 0.88, 1.0, 1.0),
	).at(12.0, 12.0);
	paragraph.maxWidth = 210.0;
	paragraph.lineSpacing = 1.15;
	paragraph.letterSpacing = 1.0;
	s.add(paragraph);
	return s;
}

function textMultilineAlign(): Scene {
	const s = scene(DARK);
	const left = label("void2d\nleft\naligned", 20.0, rgba(0.92, 0.96, 1.0, 1.0)).at(14.0, 12.0);
	const centred = label("void2d\ncentred\naligned", 20.0, rgba(0.92, 0.96, 1.0, 1.0)).at(160.0, 12.0);
	centred.align = 0.5;
	const right = label("void2d\nright\naligned", 20.0, rgba(0.92, 0.96, 1.0, 1.0)).at(306.0, 12.0);
	right.align = 1.0;
	s.add(left);
	s.add(centred);
	s.add(right);
	return s;
}

// ===== image/ =====

function imageNearestLinear(): Scene {
	const s = scene(DARK);
	const t = sheet();
	const pixels = t.sub(t.texW * 0.40, t.texH * 0.38, 14.0, 14.0);
	const nearest = sprite(pixels).at(16.0, 20.0);
	nearest.w = 96.0;
	nearest.h = 96.0;
	nearest.smooth = Smooth.Off;
	const linear = sprite(pixels).at(128.0, 20.0);
	linear.w = 96.0;
	linear.h = 96.0;
	s.add(nearest);
	s.add(linear);
	return s;
}

// tileWrap. `sub` divides by texW/texH, so a sub-rect three times the sheet has u1 = v1 = 3:
// under CLAMP_TO_EDGE the last row and column stretch across the whole sprite, under REPEAT
// the sheet tiles 3x3. The two halves of this scene differ in nothing but `tileWrap`, so a
// golden that shows them identical means the flag reached no sampler.
function imageTileWrap(): Scene {
	const s = scene(DARK);
	const t = sheet();
	const thrice = t.sub(0.0, 0.0, t.texW * 3.0, t.texH * 3.0);
	const clamped = sprite(thrice).at(16.0, 16.0);
	clamped.w = 104.0;
	clamped.h = 104.0;
	const wrapped = sprite(thrice).at(136.0, 16.0);
	wrapped.w = 104.0;
	wrapped.h = 104.0;
	wrapped.tileWrap = true;
	s.add(clamped);
	s.add(wrapped);
	return s;
}

// The `smooth` tri-state resolved against a scene whose default is nearest. The left sprite
// says nothing and must follow the scene; the right one says `Smooth.On` and must win over
// it. If `Smooth.Inherit` were treated as "on", the two halves would be identical.
function imageSceneSmooth(): Scene {
	const s = scene(DARK);
	s.defaultSmooth = false;
	const t = sheet();
	const pixels = t.sub(t.texW * 0.40, t.texH * 0.38, 14.0, 14.0);
	const inherits = sprite(pixels).at(16.0, 20.0);
	inherits.w = 96.0;
	inherits.h = 96.0;
	const overrides = sprite(pixels).at(128.0, 20.0);
	overrides.w = 96.0;
	overrides.h = 96.0;
	overrides.smooth = Smooth.On;
	s.add(inherits);
	s.add(overrides);
	return s;
}

function imageSubFlip(): Scene {
	const s = scene(DARK);
	const t = sheet();
	const half = t.sub(0.0, 0.0, t.texW * 0.5, t.texH * 0.5);
	const plain = sprite(half).at(10.0, 16.0);
	plain.w = 68.0;
	plain.h = 68.0;
	const mirroredX = sprite(half.flipX()).at(88.0, 16.0);
	mirroredX.w = 68.0;
	mirroredX.h = 68.0;
	const mirroredY = sprite(half.flipY()).at(166.0, 16.0);
	mirroredY.w = 68.0;
	mirroredY.h = 68.0;
	const whole = sprite(t).at(88.0, 92.0);
	whole.w = 68.0;
	whole.h = 68.0;
	s.add(plain);
	s.add(mirroredX);
	s.add(mirroredY);
	s.add(whole);
	return s;
}

function imageColorPipeline(): Scene {
	const s = scene(DARK);
	const t = sheet();
	const greyed = sprite(t).at(10.0, 16.0);
	greyed.w = 64.0;
	greyed.h = 64.0;
	greyed.colorMatrix = colorMatrixGrayscale(1.0);
	const added = sprite(t).at(84.0, 16.0);
	added.w = 64.0;
	added.h = 64.0;
	added.colorAdd = rgba(0.35, 0.0, 0.0, 0.0);
	const keyBackground = rect(64.0, 64.0, rgba(0.20, 0.85, 0.85, 1.0)).at(158.0, 16.0);
	const keyed = sprite(t).at(158.0, 16.0);
	keyed.w = 64.0;
	keyed.h = 64.0;
	keyed.colorKey = rgba(0.05, 0.05, 0.07, 1.0);
	const additive = sprite(t).at(84.0, 90.0);
	additive.w = 64.0;
	additive.h = 64.0;
	additive.blend = BlendMode.Add;
	additive.alpha = 0.6;
	s.add(greyed);
	s.add(added);
	s.add(keyBackground);
	s.add(keyed);
	s.add(rect(64.0, 64.0, rgba(0.35, 0.25, 0.15, 1.0)).at(84.0, 90.0));
	s.add(additive);
	return s;
}

function imageScaleGrid(): Scene {
	const s = scene(DARK);
	const nine = scaleGrid(sheet(), 36.0, 36.0, 36.0, 36.0).at(14.0, 14.0);
	nine.w = 220.0;
	nine.h = 120.0;
	s.add(nine);
	return s;
}

// ===== filter/ — built, but not in tests/golden/table.ms until P1 =====
// Nothing here can be captured today. drawFiltered (render.ms:216-283) calls beginRT while
// the swapchain pass is open; a debug build trips sokol's `!_sg.cur_pass.valid` assertion
// and aborts, and a release build presents a frame that is nothing but the clear colour —
// the siblings drawn before and after the filtered node disappear with it. The path has
// never had a caller: no example and no test sets Node2D.filter (src/test/nodeCheck.ms only
// builds the Filter structs). P1 hoists per-target command lists and adds these rows.
//
// Today's filter path: only children enter the render target, alpha is applied twice under
// Blur, the target is screen-space at DPI 1, and the nested pass drops the pending vertex
// batch (VOID2D.md "Known defects"). These four rows are what P1 has to move, and nothing
// else may move with them.

function filterSubject(): Node2D {
	const g = graphics();
	g.fillRoundedRect(0.0, 0.0, 90.0, 60.0, 14.0, rgba(1.0, 0.82, 0.35, 1.0));
	g.fillEllipse(45.0, 30.0, 22.0, 14.0, rgba(0.30, 0.20, 0.55, 1.0));
	return g;
}

function filterHost(x: float32, y: float32): Node2D {
	const host = rect(0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0)).at(x, y);
	host.addChild(filterSubject());
	return host;
}

function filterBlur(): Scene {
	const s = scene(DARK);
	const host = filterHost(40.0, 40.0);
	host.filter = blurFilter(6.0);
	s.add(host);
	return s;
}

function filterGlow(): Scene {
	const s = scene(DARK);
	const host = filterHost(40.0, 40.0);
	host.filter = glowFilter(rgba(1.0, 0.70, 0.25, 1.0), 8.0, 1.8);
	s.add(host);
	return s;
}

function filterDropShadow(): Scene {
	const s = scene(LIGHT);
	const host = filterHost(40.0, 36.0);
	host.filter = dropShadowFilter(rgba(0.08, 0.08, 0.14, 1.0), 7.0, 10.0, 12.0);
	s.add(host);
	return s;
}

// Group opacity over overlapping children: h2d composites the group once, so the overlap
// does not darken. Today alpha multiplies down the tree and each child blends on its own.
// The right-hand pair goes through a zero-radius filter, which is the render-target path,
// so the two halves of the row show the divergence side by side.
function filterGroupOpacity(): Scene {
	const s = scene(DARK);
	const direct = rect(0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0)).at(30.0, 30.0);
	direct.alpha = 0.5;
	direct.addChild(rect(90.0, 70.0, rgba(0.95, 0.35, 0.30, 1.0)));
	direct.addChild(rect(90.0, 70.0, rgba(0.30, 0.75, 0.95, 1.0)).at(45.0, 25.0));
	const targeted = rect(0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0)).at(150.0, 30.0);
	targeted.alpha = 0.5;
	targeted.filter = blurFilter(0.0);
	targeted.addChild(rect(90.0, 70.0, rgba(0.95, 0.35, 0.30, 1.0)));
	targeted.addChild(rect(90.0, 70.0, rgba(0.30, 0.75, 0.95, 1.0)).at(45.0, 25.0));
	s.add(direct);
	s.add(targeted);
	return s;
}

// ===== regress/ — one row per "Known defects" entry that has pixels =====

// Not in tests/golden/table.ms: see the note there. Kept so P1 can add the row back.
// batcher.c:151-154 fixes the fontstash atlas at 512x512 and there is no FONS_ATLAS_FULL
// handler, so once the atlas fills, later glyphs come back blank. Twenty-two sizes of a
// 62-glyph line is far more coverage than 512x512 holds. P1 holds it, P3 removes the class.
function regressAtlasFull(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 22; i++) {
		const size: float32 = 9.0 + (i as float32) * 2.0;
		s.add(label(
			"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
			size,
			LIGHT,
		).at(4.0, (i as float32) * 11.0));
	}
	return s;
}

// Every Label and Graphics owns an sg_buffer and sokol's default pool holds 128, so past
// about 126 of them the rest silently do not draw. P1 replaces them with one growing buffer.
function regressNodeCap(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 200; i++) {
		const column: float32 = ((i % 20) as float32) * 26.0 + 4.0;
		const row: float32 = ((i / 20) as float32) * 16.0 + 4.0;
		s.add(label(String(i), 11.0, LIGHT).at(column, row));
	}
	return s;
}

// render.ms:216-283 opens the filter's render-target pass inside the swapchain pass, and
// begin2d resets the batch state, so the vertices pending when the filter is reached are
// dropped and the siblings after it draw with the filter's leftover state. The red bar is
// emitted before the filtered node and the blue one after it.
function regressFilterNestedPass(): Scene {
	const s = scene(DARK);
	s.add(rect(220.0, 22.0, rgba(0.95, 0.35, 0.30, 1.0)).at(18.0, 14.0));
	const host = filterHost(60.0, 46.0);
	host.filter = blurFilter(5.0);
	s.add(host);
	s.add(rect(220.0, 22.0, rgba(0.30, 0.75, 0.95, 1.0)).at(18.0, 122.0));
	return s;
}

// scene.ms:89 passes the logical size to begin2d as `wf as int32`, so at DPI 1.5 a 256-pixel
// framebuffer becomes 170 logical pixels instead of 170.666 and the NDC mapping carries the
// fraction as an error that grows with x. The right column sits against the truncated edge.
function regressDpiTruncation(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 9; i++) {
		const y: float32 = 6.0 + (i as float32) * 11.0;
		s.add(rect(6.0, 8.0, rgba(0.95, 0.80, 0.45, 1.0)).at(164.0, y));
		s.add(rect(6.0, 8.0, LIGHT).at(2.0, y));
	}
	s.add(rect(170.0, 2.0, rgba(0.35, 0.85, 0.50, 1.0)).at(0.0, 104.0));
	return s;
}

// batcher.c:141-148 hard-wires both samplers to SG_WRAP_REPEAT, so a tile that reaches the
// edge of its texture blends in the opposite edge instead of clamping. P1's own commit,
// because it changes edge pixels everywhere.
function regressSamplerRepeat(): Scene {
	const s = scene(DARK);
	const t = sheet();
	const rightEdge = sprite(t.sub(t.texW - 6.0, 0.0, 6.0, t.texH)).at(20.0, 16.0);
	rightEdge.w = 60.0;
	rightEdge.h = 120.0;
	const topEdge = sprite(t.sub(0.0, 0.0, t.texW, 6.0)).at(100.0, 16.0);
	topEdge.w = 130.0;
	topEdge.h = 60.0;
	s.add(rightEdge);
	s.add(topEdge);
	return s;
}

// draw.ms:20 caps the frame at 65536 vertices and batcher.c:90 sizes the GPU buffer to the
// same, but sg_append_buffer accumulates across flushes within a frame, so once the frame's
// total passes the cap sokol drops the appends and the rest of the scene disappears.
// 12000 quads is 72000 vertices.
function regressVertexCap(): Scene {
	const s = scene(DARK);
	for (let i: int32 = 0; i < 12000; i++) {
		const column: float32 = ((i % 120) as float32) * 2.0;
		const row: float32 = ((i / 120) as float32) * 1.6;
		const swatch: Color = i % 3 == 0 ? rgba(0.95, 0.40, 0.35, 1.0) : rgba(0.35, 0.85, 0.50, 1.0);
		s.add(rect(1.6, 1.2, swatch).at(column, row));
	}
	return s;
}

// ===== the builder list, in tests/golden/table.ms order =====

// The demo rows drive src/examples/renderer2d.ms through its own init/step/present and never
// call a builder; this stands in for their slot so the two lists stay the same length.
function demoPlaceholder(): Scene { return scene(DARK); }

// Paired with the row name, not just positional. A length check cannot catch a builder
// inserted at the wrong index — and the failure that follows is the worst kind: a correct
// image written under the wrong name, which `--update` would then commit as the golden.
export interface SceneBuilder {
	name: string;
	build: () => Scene;
}

export function sceneBuilders(): SceneBuilder[] {
	return [
		{ name: "harness/solid", build: harnessSolid },
		{ name: "harness/mustFail", build: harnessSolid },

		{ name: "prim/roundedRect", build: primRoundedRect },
		{ name: "prim/strokeRect", build: primStrokeRect },
		{ name: "prim/ellipsePieRing", build: primEllipsePieRing },
		{ name: "prim/polygonBezier", build: primPolygonBezier },
		{ name: "prim/gradientLinear", build: primGradientLinear },
		{ name: "prim/gradientRadial", build: primGradientRadial },

		{ name: "xform/rotate", build: xformRotate },
		{ name: "xform/scale", build: xformScale },
		{ name: "xform/pivot", build: xformPivot },
		{ name: "xform/nonUniform", build: xformNonUniform },

		{ name: "snap/hairlineDpi100", build: snapHairlines },
		{ name: "snap/hairlineDpi125", build: snapHairlines },
		{ name: "snap/hairlineDpi150", build: snapHairlines },
		{ name: "snap/fractionalSplit", build: snapFractionalSplit },
		{ name: "snap/fractionalOrigin", build: snapFractionalOrigin },

		{ name: "clip/nestedMasks", build: clipNestedMasks },
		{ name: "clip/rotatedMask", build: clipRotatedMask },
		{ name: "clip/scrolledList", build: clipScrolledList },

		{ name: "text/code13Dpi100", build: textCode },
		{ name: "text/code13Dpi125", build: textCode },
		{ name: "text/code13Dpi150", build: textCode },
		{ name: "text/wrapped", build: textWrapped },
		{ name: "text/multilineAlign", build: textMultilineAlign },

		{ name: "image/nearestLinear", build: imageNearestLinear },
		{ name: "image/tileWrap", build: imageTileWrap },
		{ name: "image/sceneSmooth", build: imageSceneSmooth },
		{ name: "image/subFlip", build: imageSubFlip },
		{ name: "image/colorPipeline", build: imageColorPipeline },
		{ name: "image/scaleGrid", build: imageScaleGrid },

		{ name: "filter/blur", build: filterBlur },
		{ name: "filter/glow", build: filterGlow },
		{ name: "filter/dropShadow", build: filterDropShadow },
		{ name: "filter/groupOpacity", build: filterGroupOpacity },

		{ name: "regress/atlasFull", build: regressAtlasFull },
		{ name: "regress/nodeCap", build: regressNodeCap },
		{ name: "regress/dpiTruncation", build: regressDpiTruncation },
		{ name: "regress/samplerRepeat", build: regressSamplerRepeat },
		{ name: "regress/vertexCap", build: regressVertexCap },
		{ name: "regress/filterNestedPass", build: regressFilterNestedPass },

		{ name: "demo/frame001", build: demoPlaceholder },
		{ name: "demo/frame030", build: demoPlaceholder },
		{ name: "demo/frame090", build: demoPlaceholder },
		{ name: "demo/frame200", build: demoPlaceholder },
	];
}
