// void2d frame budget (docs/GPUI.md "Sequencing"): CPU time of Scene.present and draw calls for
// a UI scene (a grid of cards, each a Rect with a Label child — box/text alternation in tree
// order) and a sprite-only scene. An entry calls voidRun with benchInit(kind) / benchFrame;
// every REPORT_EVERY frames it prints the mean present() time, and it exits after REPORTS reports.

import { gfxSetup, makeImage, makeView } from "../sokol/gpu";
import { setup2d, drawCallCount } from "../void2d/draw";
import { rect, sprite, label, at, addChild } from "../void2d/node";
import { Scene, scene, add, present } from "../void2d/scene";
import { rgba, tile } from "../void2d/types";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";

export enum BenchKind {
	Ui,
	Sprites,
}

const COLUMNS: int32 = 100;
const ROWS: int32 = 100;
const CELL_W: float32 = 12.8;
const CELL_H: float32 = 7.2;
const REPORT_EVERY: int32 = 120;
const REPORTS: int32 = 4;

let benchScene: Scene | null = null;
let frameIndex: int32 = 0;
let presentMs: float64 = 0.0;

export function benchInit(kind: BenchKind): void {
	gfxSetup();
	setup2d();
	const s = scene(rgba(0.08, 0.09, 0.11, 1.0));
	if (kind === BenchKind.Ui) {
		for (let row = 0; row < ROWS; row++) {
			for (let column = 0; column < COLUMNS; column++) {
				const card = rect(CELL_W - 1.0, CELL_H - 1.0, rgba(0.2, 0.3, 0.5, 1.0))
					.at((column as float32) * CELL_W, (row as float32) * CELL_H);
				card.addChild(label(String(row * COLUMNS + column), 6.0, rgba(1.0, 1.0, 1.0, 1.0)));
				s.add(card);
			}
		}
	} else {
		const img = loadImageSync("assets/test.png", 4);
		const view = makeView(makeImage(img, imageWidth(), imageHeight()));
		freeImage(img);
		for (let row = 0; row < ROWS; row++) {
			for (let column = 0; column < COLUMNS; column++) {
				s.add(sprite(tile(view, CELL_W - 1.0, CELL_H - 1.0))
					.at((column as float32) * CELL_W, (row as float32) * CELL_H));
			}
		}
	}
	benchScene = s;
}

export function benchFrame(): void {
	if (benchScene === null) { return; }
	const started: float64 = performance.now();
	benchScene.present();
	presentMs = presentMs + (performance.now() - started);
	frameIndex = frameIndex + 1;
	if (frameIndex % REPORT_EVERY == 0) {
		console.log(`present ${presentMs / (REPORT_EVERY as float64)} ms, ${drawCallCount()} draws`);
		presentMs = 0.0;
		if (frameIndex == REPORT_EVERY * REPORTS) { process.exit(0); }
	}
}
