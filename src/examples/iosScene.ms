// Void — iOS embed scene (no-asset, ANIMATED). Rotating additive rect + pulsing panel
// + a graphics node (circle/line/triangle). No disk assets (no image/font) so it drops
// into any host (incl. the React-Native VoidView pod) without bundling concerns.

import { gfxSetup } from "../sokol/gpu";
import { setup2d } from "../void2d/draw";
import { Node2D, rect, graphics, at, addChild } from "../void2d/node";
import { fillCircle, strokeLine, fillConvex } from "../void2d/graphics";
import { Scene, scene, add, present, tick } from "../void2d/scene";
import { Vec2, rgba, vec2, BlendMode } from "../void2d/types";

let sc: Scene | null = null;
let panel: Node2D | null = null;
let green: Node2D | null = null;
let t: float32 = 0.0;
let dir: float32 = 1.0;

export function initIos(): void {
	gfxSetup();
	setup2d();

	const root = scene(rgba(0.08, 0.09, 0.12, 1.0));

	const p = rect(360.0, 380.0, rgba(0.16, 0.18, 0.24, 1.0)).at(60.0, 60.0);
	p.addChild(rect(160.0, 70.0, rgba(0.90, 0.30, 0.35, 1.0)).at(30.0, 30.0));

	const g = rect(140.0, 140.0, rgba(0.35, 0.80, 0.45, 1.0)).at(160.0, 170.0);
	g.alpha = 0.7;
	g.blend = BlendMode.Add;
	g.pivotX = 70.0;
	g.pivotY = 70.0;
	p.addChild(g);

	const gfx = graphics().at(70.0, 470.0);
	gfx.fillCircle(70.0, 70.0, 55.0, rgba(0.95, 0.75, 0.25, 1.0));
	gfx.strokeLine(vec2(10.0, 160.0), vec2(190.0, 210.0), 8.0, rgba(0.40, 0.75, 1.0, 1.0));
	const tri: Vec2[] = [vec2(220.0, 210.0), vec2(340.0, 210.0), vec2(280.0, 120.0)];
	gfx.fillConvex(tri, rgba(0.85, 0.40, 0.55, 1.0));

	root.add(p);
	root.add(gfx);

	panel = p;
	green = g;
	sc = root;
}

export function frameIos(): void {
	if (sc === null) { return; }
	if (panel === null) { return; }
	if (green === null) { return; }

	t = t + dir * 1.6;
	if (t > 120.0) { dir = -1.0; }
	if (t < 0.0) { dir = 1.0; }
	const s: float32 = 0.85 + t / 400.0;
	panel.scaleX = s;
	panel.scaleY = s;
	green.rotation = green.rotation + 0.03;

	sc.tick(1.0 / 60.0);
	sc.present();
}
