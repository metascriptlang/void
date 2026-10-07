import { Color, rgba, identity2d } from "./types";
import { BlendMode } from "../gpu/state";
import { InstanceMode, uiInstance } from "./instance";
import { DrawContext2D, useContext, currentContext } from "./displayList";
import { openBracket, startContext, finishRecording, drawUiInstance } from "./draw";
import { contextGeneration } from "../gpu/door";
import {
	FrameProfiler, FrameCounters, OverlayMode, readoutLines, counterLines, noCounters,
} from "./profiler";
import { frameStats, lastFrameCounters } from "./frameMarks";
import { GLYPH_WIDTH, GLYPH_HEIGHT, glyphIndex, glyphRow } from "./profilerFont";

export const CHAR_ADVANCE: int32 = GLYPH_WIDTH + 1;
export const LINE_ADVANCE: int32 = GLYPH_HEIGHT + 2;
export const PANEL_PADDING: int32 = 2;
export const PANEL_MARGIN: int32 = 4;
export const CELL_LOGICAL: float32 = 2.0;
export const BAR_WIDTH: int32 = 3;
export const BAR_GAP: int32 = 1;
export const BAR_MAX_HEIGHT: int32 = GLYPH_HEIGHT;
export const HISTOGRAM_BLOCK: int32 = LINE_ADVANCE + BAR_MAX_HEIGHT + 2;
export const REFRESH_FRAMES: int32 = 15;

export enum OverlayInk {
	Panel,
	Text,
	Baseline,
	DrawBar,
	DirtyBar,
}

export struct CellRect {
	x: int32;
	y: int32;
	w: int32;
	h: int32;
	ink: OverlayInk;
}

export struct OverlayModel {
	mode: OverlayMode;
	lines: Vec<string>;
	drawBuckets: Vec<int32>;
	dirtyBuckets: Vec<int32>;
}

export struct OverlayLayout {
	rects: Vec<CellRect>;
	widthCells: int32;
	heightCells: int32;
}

export function nextMode(mode: OverlayMode): OverlayMode {
	return match (mode) {
		OverlayMode.Hidden => OverlayMode.Minimal,
		OverlayMode.Minimal => OverlayMode.Full,
		OverlayMode.Full => OverlayMode.Hidden,
	};
}

function copyBuckets(counts: Vec<int32>): Vec<int32> {
	let out: Vec<int32> = new Array(0);
	for (let i: int32 = 0; i < (counts.length as int32); i++) { out.push(counts[i]); }
	return out;
}

export function overlayModel(
	p: FrameProfiler,
	counters: FrameCounters,
	mode: OverlayMode,
): OverlayModel {
	let lines: Vec<string> = p.readoutLines(mode);
	if (mode == OverlayMode.Full) {
		for (const line of counterLines(counters)) { lines.push(line); }
		return {
			mode: mode,
			lines: lines,
			drawBuckets: copyBuckets(p.drawHistogram.counts),
			dirtyBuckets: copyBuckets(p.dirtyHistogram.counts),
		};
	}
	return { mode: mode, lines: lines, drawBuckets: new Array(0), dirtyBuckets: new Array(0) };
}

function textRects(
	ref rects: Vec<CellRect>,
	text: string,
	left: int32,
	top: int32,
): void {
	const length: int32 = text.length as int32;
	for (let c: int32 = 0; c < length; c++) {
		const glyph: int32 = glyphIndex(text.byteSlice(c, c + 1));
		const glyphLeft: int32 = left + c * CHAR_ADVANCE;
		for (let row: int32 = 0; row < GLYPH_HEIGHT; row++) {
			const bits: int32 = glyphRow(glyph, row);
			let column: int32 = 0;
			while (column < GLYPH_WIDTH) {
				if ((bits & (1 << (GLYPH_WIDTH - 1 - column))) == 0) {
					column = column + 1;
					continue;
				}
				const start: int32 = column;
				while (column < GLYPH_WIDTH && (bits & (1 << (GLYPH_WIDTH - 1 - column))) != 0) {
					column = column + 1;
				}
				rects.push({
					x: glyphLeft + start,
					y: top + row,
					w: column - start,
					h: 1,
					ink: OverlayInk.Text,
				});
			}
		}
	}
}

function peak(buckets: Vec<int32>): int32 {
	let most: int32 = 0;
	for (let i: int32 = 0; i < (buckets.length as int32); i++) {
		if (buckets[i] > most) { most = buckets[i]; }
	}
	return most;
}

function barRects(ref rects: Vec<CellRect>, buckets: Vec<int32>, top: int32, ink: OverlayInk): void {
	const most: int32 = peak(buckets);
	const floor: int32 = top + BAR_MAX_HEIGHT;
	for (let i: int32 = 0; i < (buckets.length as int32); i++) {
		const left: int32 = PANEL_PADDING + i * (BAR_WIDTH + BAR_GAP);
		if (buckets[i] == 0) {
			rects.push({ x: left, y: floor - 1, w: BAR_WIDTH, h: 1, ink: OverlayInk.Baseline });
			continue;
		}
		const raw: int32 = (buckets[i] * BAR_MAX_HEIGHT) / most;
		const height: int32 = raw < 1 ? 1 : raw;
		rects.push({ x: left, y: floor - height, w: BAR_WIDTH, h: height, ink: ink });
	}
}

export function layoutOverlay(m: OverlayModel): OverlayLayout {
	let rects: Vec<CellRect> = new Array(0);
	const lineCount: int32 = m.lines.length as int32;
	if (lineCount == 0) { return { rects: rects, widthCells: 0, heightCells: 0 }; }
	const bars: boolean = m.mode == OverlayMode.Full && (m.drawBuckets.length as int32) > 0;
	let widest: int32 = 0;
	for (const line of m.lines) {
		const width: int32 = (line.length as int32) * CHAR_ADVANCE;
		if (width > widest) { widest = width; }
	}
	if (bars) {
		const barsWidth: int32 = (m.drawBuckets.length as int32) * (BAR_WIDTH + BAR_GAP);
		if (barsWidth > widest) { widest = barsWidth; }
	}
	const widthCells: int32 = widest + 2 * PANEL_PADDING;
	const heightCells: int32 = 2 * PANEL_PADDING + lineCount * LINE_ADVANCE +
		(bars ? 2 * HISTOGRAM_BLOCK : 0);
	rects.push({ x: 0, y: 0, w: widthCells, h: heightCells, ink: OverlayInk.Panel });
	for (let i: int32 = 0; i < lineCount; i++) {
		textRects(rects, m.lines[i], PANEL_PADDING, PANEL_PADDING + i * LINE_ADVANCE);
	}
	if (bars) {
		const drawTop: int32 = PANEL_PADDING + lineCount * LINE_ADVANCE;
		textRects(rects, "DRAW", PANEL_PADDING, drawTop);
		barRects(rects, m.drawBuckets, drawTop + LINE_ADVANCE, OverlayInk.DrawBar);
		const dirtyTop: int32 = drawTop + HISTOGRAM_BLOCK;
		textRects(rects, "DIRTY", PANEL_PADDING, dirtyTop);
		barRects(rects, m.dirtyBuckets, dirtyTop + LINE_ADVANCE, OverlayInk.DirtyBar);
	}
	return { rects: rects, widthCells: widthCells, heightCells: heightCells };
}

function inkColor(ink: OverlayInk): Color {
	return match (ink) {
		OverlayInk.Panel => rgba(0.0, 0.0, 0.0, 0.667),
		OverlayInk.Text => rgba(0.2, 1.0, 0.2, 1.0),
		OverlayInk.Baseline => rgba(0.2, 0.4, 0.2, 1.0),
		OverlayInk.DrawBar => rgba(0.3, 0.75, 1.0, 1.0),
		OverlayInk.DirtyBar => rgba(1.0, 0.7, 0.25, 1.0),
	};
}

export function cellPixels(dpi: float32): int32 {
	const cell: int32 = (CELL_LOGICAL * dpi + 0.5) as int32;
	return cell < 1 ? 1 : cell;
}

let overlayMode: OverlayMode = OverlayMode.Hidden;
let liveSource: boolean = true;
let source: FrameProfiler = frameStats;
let sourceCounters: FrameCounters = noCounters();
let model: OverlayModel = overlayModel(frameStats, noCounters(), OverlayMode.Hidden);
let modelDirty: boolean = true;
let modelVersion: int32 = 0;
let modelFrames: int32 = 0;

export function profilerOverlayMode(): OverlayMode { return overlayMode; }

export function profilerOverlaySetMode(mode: OverlayMode): void {
	overlayMode = mode;
	modelDirty = true;
}

export function profilerOverlayCycle(): void {
	profilerOverlaySetMode(nextMode(overlayMode));
}

export function profilerOverlayFeed(p: FrameProfiler, counters: FrameCounters): void {
	liveSource = false;
	source = p;
	sourceCounters = counters;
	modelDirty = true;
}

export function profilerOverlayFeedLive(): void {
	liveSource = true;
	source = frameStats;
	modelDirty = true;
}

export function profilerOverlayVersion(): int32 { return modelVersion; }

export function profilerOverlayDue(): boolean {
	if (overlayMode == OverlayMode.Hidden) { return false; }
	if (modelDirty) { return true; }
	const frames: int32 = source.frames;
	return frames < modelFrames || frames - modelFrames >= REFRESH_FRAMES;
}

export function profilerOverlayRefresh(): void {
	if (!profilerOverlayDue()) { return; }
	const counters: FrameCounters = liveSource ? lastFrameCounters() : sourceCounters;
	model = overlayModel(source, counters, overlayMode);
	modelFrames = source.frames;
	modelDirty = false;
	modelVersion = modelVersion + 1;
}

function recordLayout(layout: OverlayLayout, w: float32, h: float32, dpi: float32): void {
	const cell: int32 = cellPixels(dpi);
	const framebufferWidth: int32 = (w * dpi + 0.5) as int32;
	const left: int32 = framebufferWidth - (layout.widthCells + PANEL_MARGIN) * cell;
	const top: int32 = PANEL_MARGIN * cell;
	for (const r of layout.rects) {
		drawUiInstance(0 as uint32, BlendMode.Alpha, uiInstance(
			InstanceMode.Box,
			identity2d(),
			((left + r.x * cell) as float32) / dpi,
			((top + r.y * cell) as float32) / dpi,
			((r.w * cell) as float32) / dpi,
			((r.h * cell) as float32) / dpi,
			inkColor(r.ink),
		));
	}
}

export function profilerOverlayRecord(w: float32, h: float32, dpi: float32): void {
	if (overlayMode == OverlayMode.Hidden) { return; }
	profilerOverlayRefresh();
	recordLayout(layoutOverlay(model), w, h, dpi);
}

const overlayContext: DrawContext2D = DrawContext2D.create();
let prepared: boolean = false;
let recorded: boolean = false;
let recordedW: float32 = 0.0;
let recordedH: float32 = 0.0;
let recordedDpi: float32 = 0.0;
let recordedGeneration: int32 = 0;
let recordedVersion: int32 = -1;

export function recordingHolds(
	held: boolean,
	heldW: float32, heldH: float32, heldDpi: float32,
	heldGeneration: int32, heldVersion: int32,
	w: float32, h: float32, dpi: float32,
	generation: int32, version: int32,
): boolean {
	return held && heldW == w && heldH == h && heldDpi == dpi &&
		heldGeneration == generation && heldVersion == version;
}

export function profilerPrepare(w: float32, h: float32, dpi: float32): void {
	if (prepared) {
		console.log("void2d profiler overlay: profilerPrepare again before profilerDraw");
		unreachable;
	}
	if (overlayMode == OverlayMode.Hidden) { return; }
	const host: DrawContext2D = currentContext();
	profilerOverlayRefresh();
	useContext(overlayContext);
	openBracket(w, h, dpi);
	if (!recordingHolds(
		recorded, recordedW, recordedH, recordedDpi, recordedGeneration, recordedVersion,
		w, h, dpi, contextGeneration(), modelVersion,
	)) {
		startContext();
		recordLayout(layoutOverlay(model), w, h, dpi);
		finishRecording();
		recorded = true;
		recordedW = w;
		recordedH = h;
		recordedDpi = dpi;
		recordedGeneration = contextGeneration();
		recordedVersion = modelVersion;
	}
	overlayContext.prepare();
	useContext(host);
	prepared = true;
}

export function profilerDraw(): void {
	if (!prepared) { return; }
	prepared = false;
	const host: DrawContext2D = currentContext();
	overlayContext.drawScreen();
	useContext(host);
}
