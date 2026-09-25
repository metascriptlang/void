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
	recordedUiInstanceCount,
	recordedSpriteInstanceCount,
	droppedFrames,
} from "../void2d/draw";
import { renderTargetsAlive } from "../void2d/render";
import { glyphAtlas, glyphRasterizations } from "../void2d/labelText";
import { GlyphAtlas } from "../void2d/glyphAtlas";
import { Node2D, group, rect, sprite, label, at, addChild } from "../void2d/node";
import { Scene, scene, add, present } from "../void2d/scene";
import { rgba, tile } from "../void2d/types";
import { calcTextWidth } from "../void2d/textLayout";
import { glyphLookups } from "../void2d/face";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";

export enum BenchKind {
	Ui,
	Sprites,
	Text,
}

const COLUMNS: int32 = 100;
const ROWS: int32 = 100;
const CELL_W: float32 = 12.8;
const CELL_H: float32 = 7.2;
const WARMUP_FRAMES: int32 = 20;
const MEASURED_FRAMES: int32 = 120;
const SWEEP_FRAMES: int32 = 64;
const SWEEP_MIN: float32 = 0.5;
const SWEEP_MAX: float32 = 4.0;
const CODE_LINES: int32 = 40;
const CODE_LINE: string = "fn layout(node: &Node, width: f32) -> Size { node.measure(width) } // 0123456789";

let benchScene: Scene | null = null;
let benchName: string = "ui";
let nodeCount: int32 = 0;
let retainedNodeCount: int32 = 0;
let frameIndex: int32 = 0;
let presentMs: float64 = 0.0;
let firstPaintMs: float64 = 0.0;
let firstPaintRasterizations: int32 = 0;
let rasterizationsBeforeMeasure: int32 = 0;
let sweepPeakPages: int32 = 0;
let codeBlock: Node2D | null = null;
let warmupFrames: int32 = WARMUP_FRAMES;

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
	} else if (kind === BenchKind.Text) {
		benchName = "text";
		const block = group();
		for (let line: int32 = 0; line < CODE_LINES; line++) {
			block.addChild(label(CODE_LINE, 13.0, rgba(0.86, 0.90, 0.98, 1.0)).at(8.0, 8.0 + (line as float32) * 17.0));
		}
		s.add(block);
		codeBlock = block;
		warmupFrames = SWEEP_FRAMES + WARMUP_FRAMES;
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
	if (kind === BenchKind.Ui) {
		nodeCount = ROWS * COLUMNS * 2;
		retainedNodeCount = ROWS * COLUMNS;
	} else if (kind === BenchKind.Text) {
		nodeCount = CODE_LINES + 1;
		retainedNodeCount = CODE_LINES;
	} else {
		nodeCount = ROWS * COLUMNS;
		retainedNodeCount = 0;
	}
	benchScene = s;
}

// One `key value` pair per line, so a gate reads rows instead of parsing prose.
//
// The two instance streams are here because P2's acceptance criterion A2 asks for it, and
// what it asks for is a SHAPE, not a number: draws falling while instances hold at the node
// count is the only reading that means "batched". Instances falling with draws means nodes
// were dropped, and `draws` alone cannot tell those apart.
//
// Both streams, per scene, rather than one number: that makes B5 gated rather than argued -
// `sprites.uiInstances` is 0, so a sprite-only frame provably emits nothing into the UI
// pipeline, which a per-mode count could never say because an empty frame reads zero of
// every mode too.
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
	console.log(`${benchName}.uiInstances ${recordedUiInstanceCount()}`);
	console.log(`${benchName}.spriteInstances ${recordedSpriteInstanceCount()}`);
	console.log(`${benchName}.uploads ${uploadCount()}`);
	console.log(`${benchName}.uploadBytes ${uploadBytes()}`);
	console.log(`${benchName}.atlasImages ${atlasImagesAlive()}`);
	console.log(`${benchName}.renderTargets ${renderTargetsAlive()}`);
	console.log(`${benchName}.droppedFrames ${droppedFrames()}`);
	console.log(`${benchName}.glyphRasterizationsSteady ${glyphRasterizations() - rasterizationsBeforeMeasure}`);
	console.log(`${benchName}.glyphPages ${glyphAtlas.pageCount()}`);
	console.log(`${benchName}.glyphBytes ${glyphAtlas.residentBytes()}`);
	console.log(`${benchName}.firstPaintRasterizations ${firstPaintRasterizations}`);
	console.log(`${benchName}.sweepPeakPages ${sweepPeakPages}`);
	console.log(`${benchName}.sweepRasterizations ${rasterizationsBeforeMeasure - firstPaintRasterizations}`);
	console.log(`${benchName}.firstPaint.ms ${firstPaintMs}`);
	console.log(`${benchName}.present.ms ${presentMs / (MEASURED_FRAMES as float64)}`);
	if (codeBlock !== null) { console.log(`${benchName}.measureGlyphLookups ${measureGlyphLookups()}`); }
}

// What one measure call costs once the faces are loaded and the fallback cache is warm: the
// Neon host's Yoga measure callback makes this call per text node per layout pass.
function measureGlyphLookups(): int32 {
	const before: uint32 = glyphLookups();
	calcTextWidth(CODE_LINE, {
		font: 0,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: 0.0,
	});
	return (glyphLookups() - before) as int32;
}

// The zoom sweep runs inside the warm-up: the code block scales from 0.5 to 4 over the
// sweep frames and settles back at 1 before the measured frames begin, so the measured
// frames prove a steady state after the atlas has churned, not before.
function sweep(frame: int32): void {
	if (codeBlock === null) { return; }
	const step: int32 = frame - 2;
	let scale: float32 = 1.0;
	if (step < SWEEP_FRAMES) {
		scale = SWEEP_MIN + (SWEEP_MAX - SWEEP_MIN) * (step as float32) / ((SWEEP_FRAMES - 1) as float32);
	}
	codeBlock.scaleX = scale;
	codeBlock.scaleY = scale;
}

export function benchFrame(): void {
	if (benchScene === null) { return; }
	frameIndex = frameIndex + 1;
	if (frameIndex == 1) {
		const firstStarted: float64 = performance.now();
		benchScene.present();
		firstPaintMs = performance.now() - firstStarted;
		firstPaintRasterizations = glyphRasterizations();
		return;
	}
	if (frameIndex <= warmupFrames) {
		sweep(frameIndex);
		benchScene.present();
		if (glyphAtlas.pageCount() > sweepPeakPages) { sweepPeakPages = glyphAtlas.pageCount(); }
		rasterizationsBeforeMeasure = glyphRasterizations();
		return;
	}
	const started: float64 = performance.now();
	benchScene.present();
	presentMs = presentMs + (performance.now() - started);
	if (frameIndex == warmupFrames + MEASURED_FRAMES) {
		report();
		process.exit(0);
	}
}
