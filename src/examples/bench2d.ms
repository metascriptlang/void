// void2d frame budget (docs/TESTING.md "T4"): a UI scene of 10 000 cards, each a Rect with
// a Label child — box/text alternation in tree order — and a sprite-only scene of the same
// size. tests/bench/bench{Ui,Sprites}.ms are the entries; each prints one machine-readable
// row per metric and exits, and tests/bench/baseline.json is what those rows are gated on.
//
// What gates and what only reports (docs/TESTING.md "T4"): counters are deterministic for a
// given build and fail the gate; milliseconds are reported with a warn threshold and never
// fail a commit, because this is a shared developer box.

import { gfxSetup, makeImage, makeView } from "../sokol/gpu";
import {
	setup2d,
	drawCallCount,
	buffersAlive,
	uploadCount,
	uploadBytes,
	atlasImagesAlive,
	recordedVertexCount,
	droppedFrames,
} from "../void2d/draw";
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
const WARMUP_FRAMES: int32 = 20;
const MEASURED_FRAMES: int32 = 120;

let benchScene: Scene | null = null;
let benchName: string = "ui";
let nodeCount: int32 = 0;
let retainedNodeCount: int32 = 0;
let frameIndex: int32 = 0;
let presentMs: float64 = 0.0;

export function benchInit(kind: BenchKind): void {
	gfxSetup();
	setup2d();
	const s = scene(rgba(0.08, 0.09, 0.11, 1.0));
	if (kind === BenchKind.Ui) {
		benchName = "ui";
		for (let row: int32 = 0; row < ROWS; row++) {
			for (let column: int32 = 0; column < COLUMNS; column++) {
				const card = rect(CELL_W - 1.0, CELL_H - 1.0, rgba(0.2, 0.3, 0.5, 1.0))
					.at((column as float32) * CELL_W, (row as float32) * CELL_H);
				card.addChild(label(String(row * COLUMNS + column), 6.0, rgba(1.0, 1.0, 1.0, 1.0)));
				s.add(card);
			}
		}
	} else {
		benchName = "sprites";
		const pixels = loadImageSync("assets/test.png", 4);
		const view = makeView(makeImage(pixels, imageWidth(), imageHeight()));
		freeImage(pixels);
		for (let row: int32 = 0; row < ROWS; row++) {
			for (let column: int32 = 0; column < COLUMNS; column++) {
				s.add(sprite(tile(view, CELL_W - 1.0, CELL_H - 1.0))
					.at((column as float32) * CELL_W, (row as float32) * CELL_H));
			}
		}
	}
	// Cards and sprites draw through the dynamic batcher and own no GPU buffer; only the
	// Labels do. Keeping the two counts apart is what makes `buffersAlive` readable as
	// "labels that actually drew" instead of a number that happens to line up.
	nodeCount = ROWS * COLUMNS * (kind === BenchKind.Ui ? 2 : 1);
	retainedNodeCount = kind === BenchKind.Ui ? ROWS * COLUMNS : 0;
	benchScene = s;
}

// One `key value` pair per line, so a gate reads rows instead of parsing prose.
//
// `retainedNodes` is how many nodes carry a mesh of their own — the Labels. Since P1 they
// all draw: `buffersAlive` is constant in the node count, because the whole frame shares one
// growing vertex buffer instead of one per node, and `vertices` is what proves every label
// emitted its geometry rather than being silently dropped by a full resource pool.
function report(): void {
	console.log(`${benchName}.nodes ${nodeCount}`);
	console.log(`${benchName}.retainedNodes ${retainedNodeCount}`);
	console.log(`${benchName}.draws ${drawCallCount()}`);
	console.log(`${benchName}.buffersAlive ${buffersAlive()}`);
	console.log(`${benchName}.vertices ${recordedVertexCount()}`);
	console.log(`${benchName}.uploads ${uploadCount()}`);
	console.log(`${benchName}.uploadBytes ${uploadBytes()}`);
	console.log(`${benchName}.atlasImages ${atlasImagesAlive()}`);
	console.log(`${benchName}.droppedFrames ${droppedFrames()}`);
	console.log(`${benchName}.present.ms ${presentMs / (MEASURED_FRAMES as float64)}`);
}

export function benchFrame(): void {
	if (benchScene === null) { return; }
	frameIndex = frameIndex + 1;
	if (frameIndex <= WARMUP_FRAMES) {
		benchScene.present();
		return;
	}
	const started: float64 = performance.now();
	benchScene.present();
	presentMs = presentMs + (performance.now() - started);
	if (frameIndex == WARMUP_FRAMES + MEASURED_FRAMES) {
		report();
		process.exit(0);
	}
}
