// Void — 2D demo (functional h2d-style). Build a scene with factories + extension
// methods (rect/sprite/label, .at, .addChild), then s.present() each frame (owns the pass).
// Reads like Heaps h2d, runs functional. Native + WebGPU + WebGL2.

import {
	gfxSetup, makeImage, makeView, keyDown, fbWidth, fbHeight, KEY_W, KEY_A, KEY_S, KEY_D,
} from "../sokol/gpu";
import { RenderTarget } from "../gpu/target";
import { PixelFormat } from "../gpu/door";
import {
	setup2d, preparePipelines, begin2d, flushTargets, beginTarget, endTarget, drawRect, drawImage,
} from "../void2d/draw";
import { blurToTarget, drawGlow, drawDropShadow } from "../void2d/filter";
import { NodeRef, Scene2D } from "../void2d/node";
import { fillRoundedRect, strokeRect, fillEllipse, fillPie, fillRing, fillPolygon, fillTexPolygon, strokePoly, cubicBezier, fillGradientRect, fillRadialGradient } from "../void2d/graphics";
import { colorMatrixGrayscale } from "../void2d/effect";
import { Align } from "../void2d/textLayout";
import { add, present, tick } from "../void2d/scene";
import { Tile, Vec2, rgba, tile, sub, flipX, vec2, Smooth } from "../void2d/types";
import { BlendMode } from "../gpu/state";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";

let sc: Scene2D | null = null;
let panel: NodeRef | null = null;
let logo: NodeRef | null = null;
let green: NodeRef | null = null;
let t: float32 = 0.0;
let dir: float32 = 1.0;
// The camera is recomputed from the surface size on every draw, so a pan cannot live in
// cam.x/y — the fit would overwrite it. It accumulates here and the fit adds it.
let panX: float32 = 0.0;
let panY: float32 = 0.0;
let rtSrc: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let rtA: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let rtB: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let rtGlow: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let rtShadow: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);

export function init2d(): void {
	gfxSetup();
	setup2d();
	const prepared: Vec<BlendMode> = [BlendMode.Alpha, BlendMode.Add, BlendMode.None];
	preparePipelines(prepared);
	const sceneObj = Scene2D.create(rgba(0.08, 0.09, 0.12, 1.0));

	const img = loadImageSync("assets/test.png", 4);
	const iw: int32 = imageWidth();
	const ih: int32 = imageHeight();
	const logoView = makeView(makeImage(img, iw, ih));
	freeImage(img);
	const logoH: float32 = 180.0;
	const logoW: float32 = logoH * (iw as float32) / (ih as float32);

	const logoNode = sceneObj.sprite(tile(logoView, logoW, logoH)).at(30.0, 200.0);

	const sheet = tile(logoView, iw as float32, ih as float32);
	const cropNode = sceneObj.sprite(sheet.sub(0.0, 0.0, (iw as float32) * 0.5, (ih as float32) * 0.5)).at(210.0, 30.0);
	cropNode.setSize(120.0, 120.0).setColorAdd(rgba(0.35, 0.0, 0.0, 0.0));

	const greenNode = sceneObj.rect(140.0, 140.0, rgba(0.35, 0.80, 0.45, 1.0)).at(180.0, 180.0);
	greenNode.setAlpha(0.6).setBlend(BlendMode.Add).setPivot(70.0, 70.0).setZIndex(10);

	const hw: float32 = (iw as float32) * 0.5;
	const hh: float32 = (ih as float32) * 0.5;
	const frames: Tile[] = [
		sheet.sub(0.0, 0.0, hw, hh), sheet.sub(hw, 0.0, hw, hh),
		sheet.sub(hw, hh, hw, hh), sheet.sub(0.0, hh, hw, hh),
	];
	const animNode = sceneObj.anim(frames, 6.0).at(250.0, 250.0);
	animNode.setSize(90.0, 90.0);

	const panelNode = sceneObj.rect(360.0, 380.0, rgba(0.16, 0.18, 0.24, 1.0)).at(60.0, 60.0);
	const redNode = sceneObj.rect(160.0, 70.0, rgba(0.90, 0.30, 0.35, 1.0)).at(30.0, 30.0);
	redNode.setColorMatrix(colorMatrixGrayscale(1.0));
	panelNode.addChild(redNode);
	panelNode.addChild(cropNode);
	panelNode.addChild(greenNode);
	panelNode.addChild(logoNode);
	panelNode.addChild(animNode);
	panelNode.addChild(sceneObj.label("hello void2d", 40.0, rgba(0.95, 0.96, 1.0, 1.0)).at(20.0, 400.0));

	const gfxNode = sceneObj.graphics().at(460.0, 40.0);
	gfxNode.fillRoundedRect(0.0, 0.0, 170.0, 90.0, 22.0, rgba(0.30, 0.55, 0.85, 1.0));
	gfxNode.strokeRect(0.0, 0.0, 170.0, 90.0, 4.0, rgba(0.85, 0.92, 1.0, 1.0));
	gfxNode.fillEllipse(45.0, 165.0, 45.0, 28.0, rgba(0.95, 0.75, 0.25, 1.0));
	gfxNode.fillPie(150.0, 165.0, 45.0, 0.0, 4.2, rgba(0.85, 0.40, 0.55, 1.0));
	gfxNode.fillRing(255.0, 165.0, 45.0, 26.0, -1.2, 4.5, rgba(0.45, 0.80, 0.55, 1.0));
	const curve: Vec2[] = cubicBezier(vec2(0.0, 250.0), vec2(80.0, 200.0), vec2(180.0, 320.0), vec2(280.0, 250.0), 40);
	gfxNode.strokePoly(curve, 6.0, rgba(0.40, 0.75, 1.0, 1.0), false);
	const arrow: Vec2[] = [
		vec2(300.0, 60.0), vec2(345.0, 60.0), vec2(345.0, 35.0), vec2(390.0, 80.0),
		vec2(345.0, 125.0), vec2(345.0, 100.0), vec2(300.0, 100.0),
	];
	gfxNode.fillPolygon(arrow, rgba(0.62, 0.50, 0.92, 1.0));

	const gradNode = sceneObj.graphics().at(40.0, 452.0);
	gradNode.fillGradientRect(0.0, 0.0, 150.0, 95.0, rgba(0.20, 0.45, 0.95, 1.0), rgba(0.95, 0.30, 0.55, 1.0), 0.0);
	gradNode.fillGradientRect(170.0, 0.0, 150.0, 95.0, rgba(0.15, 0.75, 0.55, 1.0), rgba(0.98, 0.85, 0.25, 1.0), 1.5708);
	gradNode.fillRadialGradient(385.0, 47.0, 42.0, rgba(1.0, 1.0, 1.0, 1.0), rgba(0.30, 0.15, 0.60, 1.0));

	const maskNode = sceneObj.mask(150.0, 120.0).at(470.0, 380.0);
	maskNode.addChild(sceneObj.rect(240.0, 240.0, rgba(0.92, 0.52, 0.20, 1.0)).at(-40.0, -40.0));
	maskNode.addChild(sceneObj.label("clipped", 40.0, rgba(0.1, 0.1, 0.14, 1.0)).at(8.0, 50.0));

	const sgNode = sceneObj.scaleGrid(sheet, 36.0, 36.0, 36.0, 36.0).at(650.0, 380.0);
	sgNode.setSize(270.0, 150.0);

	const keyBg = sceneObj.rect(120.0, 120.0, rgba(0.20, 0.85, 0.85, 1.0)).at(470.0, 530.0);
	const keyed = sceneObj.sprite(tile(logoView, 120.0, 120.0)).at(470.0, 530.0);
	keyed.setColorKey(rgba(0.05, 0.05, 0.07, 1.0));

	const flipped = sceneObj.sprite(tile(logoView, 90.0, 90.0).flipX()).at(610.0, 545.0);
	const pixTile = sheet.sub((iw as float32) * 0.40, (ih as float32) * 0.38, 14.0, 14.0);
	const nearestNode = sceneObj.sprite(pixTile).at(720.0, 555.0);
	nearestNode.setSize(80.0, 80.0).setSmooth(Smooth.Off);
	const linearNode = sceneObj.sprite(pixTile).at(810.0, 555.0);
	linearNode.setSize(80.0, 80.0);

	const ml = sceneObj.label("Void 2D\ncentered\nmulti-line", 34.0, rgba(0.92, 0.96, 1.0, 1.0)).at(800.0, 285.0);
	ml.setTextAlign(Align.Center);

	const para = sceneObj.label("The quick brown fox jumps over the lazy void dog.", 26.0, rgba(0.82, 0.88, 1.0, 1.0)).at(40.0, 565.0);
	para.setMaxWidth(330.0).setLineSpacing(5.0).setLetterSpacing(1.0);

	const texGfx = sceneObj.graphics().at(815.0, 170.0);
	const texArrow: Vec2[] = [
		vec2(0.0, 32.0), vec2(48.0, 32.0), vec2(48.0, 6.0), vec2(95.0, 52.0),
		vec2(48.0, 98.0), vec2(48.0, 72.0), vec2(0.0, 72.0),
	];
	texGfx.fillTexPolygon(sheet, texArrow, 0.0, 0.0, 100.0, 100.0, rgba(1.0, 1.0, 1.0, 1.0));

	sceneObj.add(panelNode);
	sceneObj.add(gfxNode);
	sceneObj.add(gradNode);
	sceneObj.add(maskNode);
	sceneObj.add(sgNode);
	sceneObj.add(keyBg);
	sceneObj.add(keyed);
	sceneObj.add(flipped);
	sceneObj.add(nearestNode);
	sceneObj.add(linearNode);
	sceneObj.add(ml);
	sceneObj.add(para);
	sceneObj.add(texGfx);

	rtSrc = RenderTarget.allocate(256, 256, PixelFormat.Rgba8, true);
	rtA = RenderTarget.allocate(256, 256, PixelFormat.Rgba8, true);
	rtB = RenderTarget.allocate(256, 256, PixelFormat.Rgba8, true);
	rtGlow = RenderTarget.allocate(256, 256, PixelFormat.Rgba8, true);
	rtShadow = RenderTarget.allocate(256, 256, PixelFormat.Rgba8, true);
	sceneObj.add(sceneObj.sprite(tile(rtGlow.asTexture(), 120.0, 120.0)).at(700.0, 262.0));
	sceneObj.add(sceneObj.sprite(tile(rtShadow.asTexture(), 120.0, 120.0)).at(828.0, 262.0));

	logo = logoNode;
	green = greenNode;
	panel = panelNode;
	sc = sceneObj;
}

// A frame is one step of the animation and then one draw of it. They are separate because
// the golden runner draws the same state twice and requires the two captures to be
// identical before either is compared to a golden (docs/TESTING.md, "Distrust the harness
// before the engine"); with them fused there is no way to redraw without moving.
export function frame2d(): void {
	step2d(1.0 / 60.0);
	present2d();
}

export function step2d(dt: float32): void {
	if (sc === null) { return; }
	if (panel === null) { return; }
	if (logo === null) { return; }
	if (green === null) { return; }

	t = t + dir * 1.6;
	if (t > 140.0) { dir = -1.0; }
	if (t < 0.0) { dir = 1.0; }
	logo.setX(30.0 + t);
	const s: float32 = 0.85 + t / 466.0;
	panel.setScale(s);
	green.setRotation(green.local().rotation + 0.03);

	const panSpeed: float32 = 5.0;
	if (keyDown(KEY_D)) { panX = panX + panSpeed; }
	if (keyDown(KEY_A)) { panX = panX - panSpeed; }
	if (keyDown(KEY_S)) { panY = panY + panSpeed; }
	if (keyDown(KEY_W)) { panY = panY - panSpeed; }

	sc.tick(dt);
}

export function present2d(): void {
	if (sc === null) { return; }

	// Auto-fit the ~980x720 scene into whatever surface hosts it (embed views are
	// smaller / different aspect than the 800x600 desktop window). Centered, zoom to fit.
	const fw: float32 = fbWidth() as float32;
	const fh: float32 = fbHeight() as float32;
	const zx: float32 = fw / 980.0;
	const zy: float32 = fh / 720.0;
	sc.cam.zoom = zx < zy ? zx : zy;
	sc.cam.x = 480.0 + panX;
	sc.cam.y = 350.0 + panY;
	sc.cam.anchorX = 0.5;
	sc.cam.anchorY = 0.5;

	// F3 filters: render a bold gold plus once into rtSrc, blur it (preserving rtSrc), then
	// composite a glow (additive halo) and a drop shadow (offset, behind) - each with the sharp
	// original drawn on top. The blurred silhouette rtB is reused by both tiles.
	//
	// Since P1 none of this opens a pass. `begin2d` starts a display list, each `beginTarget`
	// brackets a region of it, and `flushTargets` replays every one of those regions as its own
	// pass with nothing else open. The swapchain list stays empty here - the visible frame is
	// `sc.present()` just below, which starts its own list.
	const plus = rgba(1.0, 0.82, 0.35, 1.0);
	const orig = tile(rtSrc.asTexture(), 256.0, 256.0);
	const clearNone = rgba(0.0, 0.0, 0.0, 0.0);
	begin2d(256.0, 256.0, 1.0);
	beginTarget(rtSrc, 256.0, 256.0, 1.0, 0.0, 0.0, clearNone);
	drawRect(vec2(108.0, 40.0), vec2(40.0, 176.0), plus, BlendMode.Alpha);
	drawRect(vec2(40.0, 108.0), vec2(176.0, 40.0), plus, BlendMode.Alpha);
	endTarget();

	// 16, not 5: the old kernel turned a radius of 5 into a 16-texel spread, and the look the
	// demo was tuned for is the one the corrected kernel reaches by being asked for it.
	blurToTarget(rtSrc, rtB, 16.0, 256.0);

	beginTarget(
		rtGlow, 256.0, 256.0, 1.0, 0.0, 0.0,
		rgba(0.06, 0.07, 0.10, 1.0),
	);
	drawGlow(rtB, 0.0, 0.0, 256.0, 256.0, rgba(1.0, 0.70, 0.25, 1.0), 1.8);
	drawImage(orig, vec2(0.0, 0.0), vec2(256.0, 256.0), rgba(1.0, 1.0, 1.0, 1.0), BlendMode.Alpha);
	endTarget();

	beginTarget(
		rtShadow, 256.0, 256.0, 1.0, 0.0, 0.0,
		rgba(0.88, 0.90, 0.94, 1.0),
	);
	drawDropShadow(rtB, 12.0, 14.0, 256.0, 256.0, rgba(0.08, 0.08, 0.14, 1.0), 1.0);
	drawImage(orig, vec2(0.0, 0.0), vec2(256.0, 256.0), rgba(1.0, 1.0, 1.0, 1.0), BlendMode.Alpha);
	endTarget();
	flushTargets();

	sc.present();
}
