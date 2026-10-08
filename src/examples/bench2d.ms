import { Texture } from "../gpu/texture";
import { DEFAULT_FONT, addFallbackFont } from "../void2d/font";
// void2d frame budget (docs/TESTING.md "T4"): a UI scene of 10 000 cards, each a Rect with
// a Label child — box/text alternation in tree order — and a sprite-only scene of the same
// size. tests/bench/bench{Ui,Sprites}.ms are the entries; each prints one machine-readable
// row per metric and exits, and tests/bench/baseline.json is what those rows are gated on.
//
// What gates and what only reports (docs/TESTING.md "T4"): counters are deterministic for a
// given build and fail the gate; milliseconds are reported with a warn threshold and never
// fail a commit, because this is a shared developer box.

import { gfxSetup, makeImage, makeView } from "../sokol/gpu";
import { BlendMode } from "../gpu/state";
import {
	setup2d,
	preparePipelines,
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
import { GlyphAtlas, PageKind } from "../void2d/glyphAtlas";
import { NodeRef, Scene2D } from "../void2d/node";
import { add, present, isDirty } from "../void2d/scene";
import { Color, rgba, tile } from "../void2d/types";
import { Align, TextRun, calcTextWidth, describe } from "../void2d/textLayout";
import { glyphLookups } from "../void2d/face";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";
when (voidProfiler) {
	import { frameStats, profilerCollect } from "../void2d/frameMarks";
	import { ringCount, ringPercentile } from "../void2d/profiler";
}
when (voidSdfText) {
	import { void2dGlyphSdfGenerations } from "../void2d/glyph.h";
}

export enum BenchKind {
	Ui,
	Sprites,
	Text,
	Editor,
	Scroll,
	TextEmoji,
	TextSdf,
}

const COLUMNS: int32 = 100;
const ROWS: int32 = 100;
const CELL_W: float32 = 12.8;
const CELL_H: float32 = 7.2;
const WARMUP_FRAMES: int32 = 20;
const MEASURED_FRAMES: int32 = 120;
const FRAME_DT: float32 = (1.0 / 60.0) as float32;
const SWEEP_FRAMES: int32 = 64;
const SWEEP_MIN: float32 = 0.5;
const SWEEP_MAX: float32 = 4.0;
const SDF_SETTLE_ANGLE: float32 = 0.5;
const CODE_LINES: int32 = 40;
const CODE_LINE: string =
	"fn layout(node: &Node, width: f32) -> Size { node.measure(width) } // 0123456789";

const EMOJI_FACE: string = "tests/fonts/NotoColorEmoji-subset.ttf";
const EMOJI_LINE: string = "emoji \u{1F600}\u{1F44D}\u{1F680}\u{1F389} 0123456789";

const EDITOR_LINES: int32 = 200;
const EDITOR_COLUMNS: int32 = 80;
const EDITOR_SELECTION_FIRST_LINE: int32 = 10;
const EDITOR_SELECTION_LINES: int32 = 12;
const EDITOR_KEYWORD: string = "let ";
const EDITOR_BODY: string = "total = compute(alpha, beta) + table[index] * 3; ";
const EDITOR_COMMENT: string = "// line of an editor buffer";

function editorRun(len: int32, color: Color): TextRun {
	const clear: Color = rgba(0.0, 0.0, 0.0, 0.0);
	return {
		len: len, font: DEFAULT_FONT, color: color, background: clear, underline: clear,
		wavy: false, strikethrough: clear,
	};
}

// 200 lines of 80 columns, three syntax colours per line, a selection over 12 rows and a
// caret at its end: the editor scene P4 closes on and P5's scroll is measured against.
function editorLabel(s: Scene2D): NodeRef {
	let text: string = "";
	const runs: TextRun[] = [];
	const keyword: Color = rgba(0.78, 0.55, 0.95, 1.0);
	const plain: Color = rgba(0.86, 0.90, 0.98, 1.0);
	const comment: Color = rgba(0.50, 0.56, 0.62, 1.0);
	for (let line: int32 = 0; line < EDITOR_LINES; line++) {
		let row: string = EDITOR_KEYWORD + EDITOR_BODY + EDITOR_COMMENT;
		while ((row.length as int32) < EDITOR_COLUMNS) { row += "."; }
		const newline: int32 = line + 1 < EDITOR_LINES ? 1 : 0;
		text += row + (newline == 1 ? "\n" : "");
		runs.push(editorRun(EDITOR_KEYWORD.length as int32, keyword));
		runs.push(editorRun(EDITOR_BODY.length as int32, plain));
		const rest: int32 = EDITOR_COLUMNS - (EDITOR_KEYWORD.length as int32) -
			(EDITOR_BODY.length as int32) + newline;
		runs.push(editorRun(rest, comment));
	}
	const lineUnits: int32 = EDITOR_COLUMNS + 1;
	const start: int32 = EDITOR_SELECTION_FIRST_LINE * lineUnits + 6;
	const length: int32 = EDITOR_SELECTION_LINES * lineUnits;
	const editor = s.label(text, 13.0, rgba(1.0, 1.0, 1.0, 1.0)).at(8.0, 8.0);
	editor.setTextRuns(runs);
	editor.setSelectionRange({ start: start, length: length }, rgba(0.30, 0.50, 0.90, 0.45));
	editor.setCursorBlinkTime(0.0);
	editor.setCursorIndex(start + length, rgba(1.0, 0.85, 0.3, 1.0));
	return editor;
}

let benchScene: Scene2D | null = null;
let benchName: string = "ui";
let nodeCount: int32 = 0;
let retainedNodeCount: int32 = 0;
let frameIndex: int32 = 0;
let presentMs: float64 = 0.0;
let firstPaintMs: float64 = 0.0;
let firstPaintRasterizations: int32 = 0;
let firstPaintUploadBytes: int32 = 0;
let rasterizationsBeforeMeasure: int32 = 0;
let sweepPeakPages: int32 = 0;
let colourBeforeFirstPaint: int32 = 0;
let colourBeforeMeasure: int32 = 0;
let sdfBeforeFirstPaint: int32 = 0;
let sdfBeforeMeasure: int32 = 0;
let codeBlock: NodeRef | null = null;
let turnsCodeBlock: boolean = false;
let scrollArea: NodeRef | null = null;
let warmupFrames: int32 = WARMUP_FRAMES;

export function benchInit(kind: BenchKind): void {
	gfxSetup();
	setup2d();
	const prepared: Vec<BlendMode> = [BlendMode.Alpha];
	preparePipelines(prepared);
	const s = Scene2D.create(rgba(0.08, 0.09, 0.11, 1.0));
	if (kind === BenchKind.Ui) {
		benchName = "ui";
		for (let row: int32 = 0; row < ROWS; row++) {
			for (let column: int32 = 0; column < COLUMNS; column++) {
				const card = s.rect(CELL_W - 1.0, CELL_H - 1.0, rgba(0.2, 0.3, 0.5, 1.0))
					.at((column as float32) * CELL_W, (row as float32) * CELL_H);
				const name: string = String(row * COLUMNS + column);
				card.addChild(s.label(name, 6.0, rgba(1.0, 1.0, 1.0, 1.0)));
				s.add(card);
			}
		}
	} else if (kind === BenchKind.Editor) {
		benchName = "editor";
		s.add(editorLabel(s));
	} else if (kind === BenchKind.Scroll) {
		benchName = "scroll";
		const area = s.mask(1264.0, 704.0).at(8.0, 8.0);
		area.addChild(editorLabel(s));
		s.add(area);
		scrollArea = area;
	} else if (kind === BenchKind.Text) {
		benchName = "text";
		const block = s.group();
		for (let line: int32 = 0; line < CODE_LINES; line++) {
			const y: float32 = 8.0 + (line as float32) * 17.0;
			block.addChild(s.label(CODE_LINE, 13.0, rgba(0.86, 0.90, 0.98, 1.0)).at(8.0, y));
		}
		s.add(block);
		codeBlock = block;
		warmupFrames = SWEEP_FRAMES + WARMUP_FRAMES;
	} else if (kind === BenchKind.TextEmoji) {
		benchName = "textEmoji";
		addFallbackFont(DEFAULT_FONT, EMOJI_FACE);
		const block = s.group();
		for (let line: int32 = 0; line < CODE_LINES; line++) {
			const y: float32 = 8.0 + (line as float32) * 17.0;
			const text: string = line % 8 == 7 ? EMOJI_LINE : CODE_LINE;
			block.addChild(s.label(text, 13.0, rgba(0.86, 0.90, 0.98, 1.0)).at(8.0, y));
		}
		s.add(block);
		codeBlock = block;
		warmupFrames = SWEEP_FRAMES + WARMUP_FRAMES;
	} else if (kind === BenchKind.TextSdf) {
		benchName = "textSdf";
		turnsCodeBlock = true;
		const block = s.group();
		for (let line: int32 = 0; line < CODE_LINES; line++) {
			const y: float32 = 8.0 + (line as float32) * 17.0;
			block.addChild(s.label(CODE_LINE, 13.0, rgba(0.86, 0.90, 0.98, 1.0)).at(8.0, y));
		}
		s.add(block);
		codeBlock = block;
		warmupFrames = 2 * SWEEP_FRAMES + WARMUP_FRAMES;
	} else {
		benchName = "sprites";
		const pixels = loadImageSync("assets/test.png", 4);
		const image: uint32 = makeImage(pixels, imageWidth(), imageHeight());
		const view: Texture = Texture.adopt(image, makeView(image), imageWidth(), imageHeight());
		freeImage(pixels);
		for (let row: int32 = 0; row < ROWS; row++) {
			for (let column: int32 = 0; column < COLUMNS; column++) {
				s.add(s.sprite(tile(view, CELL_W - 1.0, CELL_H - 1.0))
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
	} else if (kind === BenchKind.Editor) {
		nodeCount = 1;
		retainedNodeCount = 1;
	} else if (kind === BenchKind.Scroll) {
		nodeCount = 2;
		retainedNodeCount = 1;
	} else if (kind === BenchKind.Text || kind === BenchKind.TextEmoji || kind === BenchKind.TextSdf) {
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
	const steady: int32 = glyphRasterizations() - rasterizationsBeforeMeasure;
	console.log(`${benchName}.glyphRasterizationsSteady ${steady}`);
	console.log(`${benchName}.glyphPages ${glyphAtlas.pagesOfKind(PageKind.Coverage)}`);
	console.log(`${benchName}.glyphBytes ${glyphAtlas.bytesOfKind(PageKind.Coverage)}`);
	console.log(`${benchName}.colourPages ${glyphAtlas.pagesOfKind(PageKind.Rgba)}`);
	console.log(`${benchName}.colourBytes ${glyphAtlas.bytesOfKind(PageKind.Rgba)}`);
	const colourSteady: int32 = glyphAtlas.colourRasterizations - colourBeforeMeasure;
	console.log(`${benchName}.colourRasterizationsSteady ${colourSteady}`);
	const colourSwept: int32 = colourBeforeMeasure - colourBeforeFirstPaint;
	console.log(`${benchName}.sweepColourRasterizations ${colourSwept}`);
	console.log(`${benchName}.sdfPages ${glyphAtlas.pagesOfKind(PageKind.Sdf)}`);
	console.log(`${benchName}.sdfBytes ${glyphAtlas.bytesOfKind(PageKind.Sdf)}`);
	console.log(`${benchName}.sdfGenerationsSteady ${sdfGenerations() - sdfBeforeMeasure}`);
	console.log(`${benchName}.sweepSdfGenerations ${sdfBeforeMeasure - sdfBeforeFirstPaint}`);
	console.log(`${benchName}.firstPaintRasterizations ${firstPaintRasterizations}`);
	console.log(`${benchName}.firstPaintUploadBytes ${firstPaintUploadBytes}`);
	const idle: boolean = benchScene !== null && (benchScene as Scene2D).isDirty();
	console.log(`${benchName}.idleDirty ${idle ? 1 : 0}`);
	console.log(`${benchName}.sweepPeakPages ${sweepPeakPages}`);
	const swept: int32 = rasterizationsBeforeMeasure - firstPaintRasterizations;
	console.log(`${benchName}.sweepRasterizations ${swept}`);
	console.log(`${benchName}.firstPaint.ms ${firstPaintMs}`);
	console.log(`${benchName}.present.ms ${presentMs / (MEASURED_FRAMES as float64)}`);
	reportProfile();
	if (codeBlock !== null) {
		console.log(`${benchName}.measureGlyphLookups ${measureGlyphLookups()}`);
		const first: NodeRef = codeBlock.getChildAt(0);
		console.log(`${benchName}.lineWidth ${first.textWidth()}`);
		console.log(`${benchName}.lineHeight ${first.textHeight()}`);
	}
}

function sdfGenerations(): int32 {
	when (voidSdfText) {
		return void2dGlyphSdfGenerations() as int32;
	} else {
		return 0;
	}
}

function milliseconds(ns: int64): float64 { return (ns as float64) / 1000000.0; }

function reportProfile(): void {
	when (voidProfiler) {
		profilerCollect();
		const stats = frameStats;
		console.log(`${benchName}.profileFrames ${stats.frames}`);
		if (stats.draws.ringCount() == 0) { return; }
		const draw = stats.draws;
		console.log(`${benchName}.profileDrawP50.ms ${milliseconds(draw.ringPercentile(50))}`);
		console.log(`${benchName}.profileDrawP99.ms ${milliseconds(draw.ringPercentile(99))}`);
		console.log(`${benchName}.profileDrawMax.ms ${milliseconds(draw.ringPercentile(100))}`);
		if (stats.dirtyToPresent.ringCount() == 0) { return; }
		const dirty = stats.dirtyToPresent;
		console.log(`${benchName}.profileDirtyP50.ms ${milliseconds(dirty.ringPercentile(50))}`);
		console.log(`${benchName}.profileDirtyMax.ms ${milliseconds(dirty.ringPercentile(100))}`);
	}
}

// What one measure call costs once the faces are loaded and the fallback cache is warm: the
// Neon host's Yoga measure callback makes this call per text node per layout pass.
function measureGlyphLookups(): int32 {
	const before: uint32 = glyphLookups();
	const measured = calcTextWidth(CODE_LINE, {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	if (!measured.ok) {
		console.log(`bench2d: the code line was refused: ${measured.error.describe()}`);
		unreachable;
	}
	return (glyphLookups() - before) as int32;
}

// The zoom sweep runs inside the warm-up: the code block scales from 0.5 to 4 over the
// sweep frames and settles back at 1 before the measured frames begin, so the measured
// frames prove a steady state after the atlas has churned, not before. The SDF scene turns
// the block through a full circle in the sweep frames after the zoom, then holds it at
// SDF_SETTLE_ANGLE, because a block at identity draws in the coverage regime and would make the
// measured frames say nothing about the SDF cache.
function sweep(frame: int32): void {
	if (codeBlock === null) { return; }
	const step: int32 = frame - 2;
	let scale: float32 = 1.0;
	let angle: float32 = 0.0;
	if (step < SWEEP_FRAMES) {
		const span: float32 = (SWEEP_FRAMES - 1) as float32;
		scale = SWEEP_MIN + (SWEEP_MAX - SWEEP_MIN) * (step as float32) / span;
	} else if (turnsCodeBlock && step < 2 * SWEEP_FRAMES) {
		const span: float32 = (SWEEP_FRAMES - 1) as float32;
		angle = 2.0 * (Math.PI as float32) * ((step - SWEEP_FRAMES) as float32) / span;
	} else if (turnsCodeBlock) {
		angle = SDF_SETTLE_ANGLE;
	}
	codeBlock.setScale(scale);
	if (turnsCodeBlock) { codeBlock.setRotation(angle); }
}

export function benchFrame(): void {
	if (benchScene === null) { return; }
	frameIndex = frameIndex + 1;
	if (frameIndex == 1) {
		const firstStarted: float64 = performance.now();
		benchScene.present();
		firstPaintMs = performance.now() - firstStarted;
		firstPaintRasterizations = glyphRasterizations();
		colourBeforeFirstPaint = glyphAtlas.colourRasterizations;
		sdfBeforeFirstPaint = sdfGenerations();
		firstPaintUploadBytes = uploadBytes();
		return;
	}
	if (frameIndex <= warmupFrames) {
		sweep(frameIndex);
		benchScene.present();
		if (glyphAtlas.pageCount() > sweepPeakPages) { sweepPeakPages = glyphAtlas.pageCount(); }
		rasterizationsBeforeMeasure = glyphRasterizations();
		colourBeforeMeasure = glyphAtlas.colourRasterizations;
		sdfBeforeMeasure = sdfGenerations();
		return;
	}
	benchScene.tick(FRAME_DT);
	if (scrollArea !== null) {
		(scrollArea as NodeRef).scrollTo(0.0, ((frameIndex * 37) % 2600) as float32);
	}
	const started: float64 = performance.now();
	benchScene.present();
	presentMs = presentMs + (performance.now() - started);
	if (frameIndex == warmupFrames + MEASURED_FRAMES) {
		report();
		process.exit(0);
	}
}
