// Void — 2D demo (functional h2d-style). Build a scene with factories + extension
// methods (rect/sprite/label, .at, .addChild), then s.present() each frame (owns the pass).
// Reads like Heaps h2d, runs functional. Native + WebGPU + WebGL2.

import { gfxSetup, makeImage, makeView, keyDown, KEY_W, KEY_A, KEY_S, KEY_D } from "../sokol/gpu";
import { setup2d } from "../void2d/draw";
import { Node2D, rect, sprite, label, anim, graphics, mask, scaleGrid, at, addChild } from "../void2d/node";
import { fillRoundedRect, strokeRect, fillEllipse, fillPie, fillRing, fillPolygon, strokePoly, cubicBezier } from "../void2d/graphics";
import { colorMatrixGrayscale } from "../void2d/effect";
import { Scene, scene, add, present, tick } from "../void2d/scene";
import { Tile, Vec2, rgba, tile, sub, flipX, vec2, BlendMode } from "../void2d/types";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";

let sc: Scene | null = null;
let panel: Node2D | null = null;
let logo: Node2D | null = null;
let green: Node2D | null = null;
let t: float32 = 0.0;
let dir: float32 = 1.0;

export function init2d(): void {
	gfxSetup();
	setup2d();

	const img = loadImageSync("assets/test.png", 4);
	const iw: int32 = imageWidth();
	const ih: int32 = imageHeight();
	const logoView = makeView(makeImage(img, iw, ih));
	freeImage(img);
	const logoH: float32 = 180.0;
	const logoW: float32 = logoH * (iw as float32) / (ih as float32);

	const logoNode = sprite(tile(logoView, logoW, logoH)).at(30.0, 200.0);

	const sheet = tile(logoView, iw as float32, ih as float32);
	const cropNode = sprite(sheet.sub(0.0, 0.0, (iw as float32) * 0.5, (ih as float32) * 0.5)).at(210.0, 30.0);
	cropNode.w = 120.0;
	cropNode.h = 120.0;
	cropNode.colorAdd = rgba(0.35, 0.0, 0.0, 0.0);

	const greenNode = rect(140.0, 140.0, rgba(0.35, 0.80, 0.45, 1.0)).at(180.0, 180.0);
	greenNode.alpha = 0.6;
	greenNode.blend = BlendMode.Add;
	greenNode.pivotX = 70.0;
	greenNode.pivotY = 70.0;
	greenNode.zIndex = 10;

	const hw: float32 = (iw as float32) * 0.5;
	const hh: float32 = (ih as float32) * 0.5;
	const frames: Tile[] = [
		sheet.sub(0.0, 0.0, hw, hh), sheet.sub(hw, 0.0, hw, hh),
		sheet.sub(hw, hh, hw, hh), sheet.sub(0.0, hh, hw, hh),
	];
	const animNode = anim(frames, 6.0).at(250.0, 250.0);
	animNode.w = 90.0;
	animNode.h = 90.0;

	const panelNode = rect(360.0, 380.0, rgba(0.16, 0.18, 0.24, 1.0)).at(60.0, 60.0);
	const redNode = rect(160.0, 70.0, rgba(0.90, 0.30, 0.35, 1.0)).at(30.0, 30.0);
	redNode.colorMatrix = colorMatrixGrayscale(1.0);
	panelNode.addChild(redNode);
	panelNode.addChild(cropNode);
	panelNode.addChild(greenNode);
	panelNode.addChild(logoNode);
	panelNode.addChild(animNode);
	panelNode.addChild(label("hello void2d", 40.0, rgba(0.95, 0.96, 1.0, 1.0)).at(20.0, 400.0));

	const gfxNode = graphics().at(460.0, 40.0);
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

	const maskNode = mask(150.0, 120.0).at(470.0, 380.0);
	maskNode.addChild(rect(240.0, 240.0, rgba(0.92, 0.52, 0.20, 1.0)).at(-40.0, -40.0));
	maskNode.addChild(label("clipped", 40.0, rgba(0.1, 0.1, 0.14, 1.0)).at(8.0, 50.0));

	const sgNode = scaleGrid(sheet, 36.0, 36.0, 36.0, 36.0).at(650.0, 380.0);
	sgNode.w = 270.0;
	sgNode.h = 150.0;

	const keyBg = rect(120.0, 120.0, rgba(0.20, 0.85, 0.85, 1.0)).at(470.0, 530.0);
	const keyed = sprite(tile(logoView, 120.0, 120.0)).at(470.0, 530.0);
	keyed.colorKey = rgba(0.05, 0.05, 0.07, 1.0);

	const flipped = sprite(tile(logoView, 90.0, 90.0).flipX()).at(610.0, 545.0);
	const pixTile = sheet.sub((iw as float32) * 0.40, (ih as float32) * 0.38, 14.0, 14.0);
	const nearestNode = sprite(pixTile).at(720.0, 555.0);
	nearestNode.w = 80.0;
	nearestNode.h = 80.0;
	nearestNode.smooth = false;
	const linearNode = sprite(pixTile).at(810.0, 555.0);
	linearNode.w = 80.0;
	linearNode.h = 80.0;

	const ml = label("Void 2D\ncentered\nmulti-line", 34.0, rgba(0.92, 0.96, 1.0, 1.0)).at(800.0, 285.0);
	ml.align = 0.5;

	const para = label("The quick brown fox jumps over the lazy void dog.", 26.0, rgba(0.82, 0.88, 1.0, 1.0)).at(40.0, 565.0);
	para.maxWidth = 330.0;
	para.lineSpacing = 1.15;
	para.letterSpacing = 1.0;

	const sceneObj = scene(rgba(0.08, 0.09, 0.12, 1.0));
	sceneObj.add(panelNode);
	sceneObj.add(gfxNode);
	sceneObj.add(maskNode);
	sceneObj.add(sgNode);
	sceneObj.add(keyBg);
	sceneObj.add(keyed);
	sceneObj.add(flipped);
	sceneObj.add(nearestNode);
	sceneObj.add(linearNode);
	sceneObj.add(ml);
	sceneObj.add(para);

	logo = logoNode;
	green = greenNode;
	panel = panelNode;
	sc = sceneObj;
}

export function frame2d(): void {
	if (sc === null) { return; }
	if (panel === null) { return; }
	if (logo === null) { return; }
	if (green === null) { return; }

	t = t + dir * 1.6;
	if (t > 140.0) { dir = -1.0; }
	if (t < 0.0) { dir = 1.0; }
	logo.x = 30.0 + t;
	const s: float32 = 0.85 + t / 466.0;
	panel.scaleX = s;
	panel.scaleY = s;
	green.rotation = green.rotation + 0.03;

	const panSpeed: float32 = 5.0;
	if (keyDown(KEY_D)) { sc.cam.x = sc.cam.x + panSpeed; }
	if (keyDown(KEY_A)) { sc.cam.x = sc.cam.x - panSpeed; }
	if (keyDown(KEY_S)) { sc.cam.y = sc.cam.y + panSpeed; }
	if (keyDown(KEY_W)) { sc.cam.y = sc.cam.y - panSpeed; }

	sc.tick(1.0 / 60.0);
	sc.present();
}
