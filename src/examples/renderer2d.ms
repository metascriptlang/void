// Void — 2D demo (functional h2d-style). Build a scene with factories + extension
// methods (rect/sprite/label, .at, .addChild), then s.present() each frame (owns the pass).
// Reads like Heaps h2d, runs functional. Native + WebGPU + WebGL2.

import { gfxSetup, makeImage, makeView } from "../sokol/gpu";
import { setup2d } from "../void2d/draw";
import { Node2D, rect, sprite, label, at, addChild } from "../void2d/node";
import { Scene, scene, add, present } from "../void2d/scene";
import { rgba, tile, sub, BlendMode } from "../void2d/types";
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

	const greenNode = rect(140.0, 140.0, rgba(0.35, 0.80, 0.45, 1.0)).at(180.0, 180.0);
	greenNode.alpha = 0.6;
	greenNode.blend = BlendMode.Add;
	greenNode.pivotX = 70.0;
	greenNode.pivotY = 70.0;

	const panelNode = rect(360.0, 380.0, rgba(0.16, 0.18, 0.24, 1.0)).at(60.0, 60.0);
	panelNode.addChild(rect(160.0, 70.0, rgba(0.90, 0.30, 0.35, 1.0)).at(30.0, 30.0));
	panelNode.addChild(cropNode);
	panelNode.addChild(greenNode);
	panelNode.addChild(logoNode);
	panelNode.addChild(label("hello void2d", 40.0, rgba(0.95, 0.96, 1.0, 1.0)).at(20.0, 400.0));

	const sceneObj = scene(rgba(0.08, 0.09, 0.12, 1.0));
	sceneObj.add(panelNode);

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

	sc.present();
}
