import { Scene2D } from "../void2d/node";
import { rgba } from "../void2d/types";
import { paint, isDirty } from "../void2d/scene";
import { begin2d, frameEnd, finishRecording } from "../void2d/draw";
import { uiInstanceCount, uiInstanceField } from "../void2d/displayList";
import { REC_UI_ORIGIN_SIZE } from "../void2d/instanceLayout";
import {
	OverlayMode, FrameProfiler, FrameCounters, frameProfiler, noCounters,
} from "../void2d/profiler";
import { profilerCollect } from "../void2d/frameMarks";
import {
	FONT_CHARACTERS, FONT_ROWS, GLYPH_WIDTH, GLYPH_HEIGHT, glyphIndex, glyphRow,
} from "../void2d/profilerFont";
import {
	CellRect, OverlayInk, OverlayModel, OverlayLayout, CHAR_ADVANCE, LINE_ADVANCE,
	PANEL_PADDING, PANEL_MARGIN, BAR_MAX_HEIGHT, REFRESH_FRAMES,
	nextMode, overlayModel, layoutOverlay, cellPixels, profilerOverlayMode,
	profilerOverlaySetMode, profilerOverlayCycle, profilerOverlayFeed, profilerOverlayDue,
	profilerOverlayRefresh, profilerOverlayVersion, profilerOverlayRecord, recordingHolds,
} from "../void2d/profilerOverlay";
import { fixtureProfiler, fixtureCounters } from "../../tests/harness/profilerFixture";

function count(layout: OverlayLayout, ink: OverlayInk): int32 {
	let n: int32 = 0;
	for (const r of layout.rects) {
		if (r.ink == ink) { n = n + 1; }
	}
	return n;
}

function lineModel(text: string): OverlayModel {
	let lines: Vec<string> = new Array(0);
	lines.push(text);
	return {
		mode: OverlayMode.Minimal,
		lines: lines,
		drawBuckets: new Array(0),
		dirtyBuckets: new Array(0),
	};
}

function bucketModel(draw: Vec<int32>): OverlayModel {
	let lines: Vec<string> = new Array(0);
	lines.push("X");
	return { mode: OverlayMode.Full, lines: lines, drawBuckets: draw, dirtyBuckets: draw };
}

test "the font has one seven-row glyph per character and every row fits five bits" {
	const glyphs: int32 = FONT_CHARACTERS.length as int32;
	assert (FONT_ROWS.length as int32) == glyphs * GLYPH_HEIGHT;
	for (let i: int32 = 0; i < (FONT_ROWS.length as int32); i++) {
		assert FONT_ROWS[i] >= 0;
		assert FONT_ROWS[i] < (1 << GLYPH_WIDTH);
	}
	for (let i: int32 = 0; i < glyphs; i++) {
		assert glyphIndex(FONT_CHARACTERS.byteSlice(i, i + 1)) == i;
	}
}

test "no two glyphs share a bitmap, space apart" {
	const glyphs: int32 = FONT_CHARACTERS.length as int32;
	for (let a: int32 = 1; a < glyphs; a++) {
		let lit: int32 = 0;
		for (let r: int32 = 0; r < GLYPH_HEIGHT; r++) { lit = lit + glyphRow(a, r); }
		assert lit > 0;
		for (let b: int32 = a + 1; b < glyphs; b++) {
			let same: boolean = true;
			for (let r: int32 = 0; r < GLYPH_HEIGHT; r++) {
				if (glyphRow(a, r) != glyphRow(b, r)) { same = false; }
			}
			assert !same;
		}
	}
}

test "a digit one is seven runs and a zero thirteen, each lit run one rect" {
	assert count(layoutOverlay(lineModel("1")), OverlayInk.Text) == 7;
	assert count(layoutOverlay(lineModel("0")), OverlayInk.Text) == 13;
}

test "a full stop is two runs of two cells at the glyph's bottom two rows" {
	const layout = layoutOverlay(lineModel("."));
	assert count(layout, OverlayInk.Text) == 2;
	const first: CellRect = layout.rects[1];
	const second: CellRect = layout.rects[2];
	assert first.w == 2 && second.w == 2;
	assert first.x == PANEL_PADDING + 1 && second.x == PANEL_PADDING + 1;
	assert first.y == PANEL_PADDING + 5 && second.y == PANEL_PADDING + 6;
}

test "the panel is the first rect and holds every other rect" {
	const model = overlayModel(fixtureProfiler(), fixtureCounters(), OverlayMode.Full);
	const layout = layoutOverlay(model);
	const panel: CellRect = layout.rects[0];
	assert panel.ink == OverlayInk.Panel;
	assert panel.x == 0 && panel.y == 0;
	assert panel.w == layout.widthCells && panel.h == layout.heightCells;
	for (const r of layout.rects) {
		assert r.x >= 0 && r.y >= 0;
		assert r.x + r.w <= panel.w;
		assert r.y + r.h <= panel.h;
	}
}

test "the panel is as wide as its longest line plus padding on both sides" {
	const layout = layoutOverlay(lineModel("CUR 12.3 MS"));
	assert layout.widthCells == 11 * 6 + 2 * 2;
	assert layout.heightCells == 9 + 2 * 2;
	assert CHAR_ADVANCE == 6 && LINE_ADVANCE == 9 && PANEL_PADDING == 2;
}

test "hidden lays out nothing, minimal one line, full the readout, counters and two histograms" {
	const p: FrameProfiler = fixtureProfiler();
	const c: FrameCounters = fixtureCounters();
	assert overlayModel(p, c, OverlayMode.Hidden).lines.length == 0;
	assert layoutOverlay(overlayModel(p, c, OverlayMode.Hidden)).rects.length == 0;
	assert overlayModel(p, c, OverlayMode.Minimal).lines.length == 1;
	const full = overlayModel(p, c, OverlayMode.Full);
	assert full.lines.length == 9;
	assert full.drawBuckets.length == 10 && full.dirtyBuckets.length == 10;
	const layout = layoutOverlay(full);
	assert count(layout, OverlayInk.DrawBar) + count(layout, OverlayInk.Baseline) +
		count(layout, OverlayInk.DirtyBar) >= 20;
	assert layout.heightCells ==
		2 * PANEL_PADDING + 9 * LINE_ADVANCE + 2 * (LINE_ADVANCE + BAR_MAX_HEIGHT + 2);
}

test "every character any readout can print has a glyph, empty, saturated and N/A included" {
	const empty: FrameProfiler = frameProfiler();
	const blank = overlayModel(empty, noCounters(), OverlayMode.Full);
	assert layoutOverlay(blank).rects.length > 0;
	const lots: FrameProfiler = fixtureProfiler();
	lots.frames = 100000;
	const saturated = overlayModel(lots, fixtureCounters(), OverlayMode.Full);
	assert layoutOverlay(saturated).rects.length > 0;
	const unmeasured: FrameCounters = { ...fixtureCounters(), sokolMeasured: false };
	const noStats = overlayModel(fixtureProfiler(), unmeasured, OverlayMode.Full);
	assert layoutOverlay(noStats).rects.length > 0;
}

test "a bar is as tall as its share of the busiest bucket and an empty one is a baseline" {
	let counts: Vec<int32> = new Array(0);
	counts.push(4);
	counts.push(2);
	counts.push(0);
	counts.push(1);
	const layout = layoutOverlay(bucketModel(counts));
	let heights: Vec<int32> = new Array(0);
	let baselines: int32 = 0;
	for (const r of layout.rects) {
		if (r.ink == OverlayInk.DrawBar) { heights.push(r.h); }
		if (r.ink == OverlayInk.Baseline) { baselines = baselines + 1; }
	}
	assert heights.length == 3;
	assert heights[0] == BAR_MAX_HEIGHT;
	assert heights[1] == (2 * BAR_MAX_HEIGHT) / 4;
	assert heights[2] == 1;
	assert baselines == 2;
}

test "bars of one histogram stand on one floor" {
	let counts: Vec<int32> = new Array(0);
	counts.push(4);
	counts.push(1);
	const layout = layoutOverlay(bucketModel(counts));
	let floor: int32 = -1;
	for (const r of layout.rects) {
		if (r.ink != OverlayInk.DrawBar) { continue; }
		if (floor < 0) { floor = r.y + r.h; }
		assert r.y + r.h == floor;
	}
	assert floor > 0;
}

test "the mode cycles hidden, minimal, full and back" {
	assert nextMode(OverlayMode.Hidden) == OverlayMode.Minimal;
	assert nextMode(OverlayMode.Minimal) == OverlayMode.Full;
	assert nextMode(OverlayMode.Full) == OverlayMode.Hidden;
	profilerOverlaySetMode(OverlayMode.Hidden);
	profilerOverlayCycle();
	assert profilerOverlayMode() == OverlayMode.Minimal;
	profilerOverlayCycle();
	profilerOverlayCycle();
	assert profilerOverlayMode() == OverlayMode.Hidden;
}

test "a cell is two logical pixels rounded to whole device pixels and never below one" {
	assert cellPixels(1.0) == 2;
	assert cellPixels(1.5) == 3;
	assert cellPixels(2.0) == 4;
	assert cellPixels(1.25) == 3;
	assert cellPixels(1.2) == 2;
	assert cellPixels(0.25) == 1;
}

test "the readout is rebuilt every fifteen recorded frames and on a mode change, not between" {
	const p: FrameProfiler = fixtureProfiler();
	profilerOverlayFeed(p, fixtureCounters());
	profilerOverlaySetMode(OverlayMode.Full);
	profilerOverlayRefresh();
	const built: int32 = profilerOverlayVersion();
	assert !profilerOverlayDue();
	profilerOverlayRefresh();
	assert profilerOverlayVersion() == built;
	p.frames = p.frames + REFRESH_FRAMES - 1;
	assert !profilerOverlayDue();
	profilerOverlayRefresh();
	assert profilerOverlayVersion() == built;
	p.frames = p.frames + 1;
	assert profilerOverlayDue();
	profilerOverlayRefresh();
	assert profilerOverlayVersion() == built + 1;
	profilerOverlaySetMode(OverlayMode.Minimal);
	assert profilerOverlayDue();
	profilerOverlayRefresh();
	assert profilerOverlayVersion() == built + 2;
}

test "a hidden overlay is never due and rebuilds nothing" {
	profilerOverlayFeed(fixtureProfiler(), fixtureCounters());
	profilerOverlaySetMode(OverlayMode.Hidden);
	const before: int32 = profilerOverlayVersion();
	assert !profilerOverlayDue();
	profilerOverlayRefresh();
	assert profilerOverlayVersion() == before;
}

test "a profiler whose frame count fell below the last build is rebuilt at once" {
	const p: FrameProfiler = fixtureProfiler();
	profilerOverlayFeed(p, fixtureCounters());
	profilerOverlaySetMode(OverlayMode.Full);
	profilerOverlayRefresh();
	assert !profilerOverlayDue();
	p.frames = 3;
	assert profilerOverlayDue();
}

function drawFrame(s: Scene2D): void {
	s.paint(200.0, 100.0, 1.0);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
}

test "switching the overlay on, cycling it and refreshing it leave a host scene clean" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
	drawFrame(s);
	profilerCollect();
	assert !s.isDirty();
	const retained: int32 = s.context.uiInstanceTotal;
	profilerOverlayFeed(fixtureProfiler(), fixtureCounters());
	profilerOverlaySetMode(OverlayMode.Full);
	profilerOverlayRefresh();
	profilerOverlayCycle();
	profilerOverlayCycle();
	profilerOverlayRefresh();
	assert !s.isDirty();
	assert s.dirty.length == 0;
	assert !s.structureChanged;
	assert s.context.uiInstanceTotal == retained;
}

test "recording the overlay puts its panel against the right and top margins in device pixels" {
	profilerOverlayFeed(fixtureProfiler(), fixtureCounters());
	profilerOverlaySetMode(OverlayMode.Full);
	begin2d(384.0, 280.0, 1.0);
	profilerOverlayRecord(384.0, 280.0, 1.0);
	finishRecording();
	assert uiInstanceCount() > 100;
	const x: float32 = uiInstanceField(0, REC_UI_ORIGIN_SIZE);
	const y: float32 = uiInstanceField(0, REC_UI_ORIGIN_SIZE + 1);
	const w: float32 = uiInstanceField(0, REC_UI_ORIGIN_SIZE + 2);
	assert x + w == (384 - PANEL_MARGIN * 2) as float32;
	assert y == (PANEL_MARGIN * 2) as float32;
	frameEnd();
}

test "at a fractional DPI every recorded edge is a whole device pixel" {
	profilerOverlayFeed(fixtureProfiler(), fixtureCounters());
	profilerOverlaySetMode(OverlayMode.Full);
	begin2d(384.0, 160.0, 1.5);
	profilerOverlayRecord(384.0, 160.0, 1.5);
	finishRecording();
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		for (let lane: int32 = 0; lane < 4; lane++) {
			const device: float32 = uiInstanceField(i, REC_UI_ORIGIN_SIZE + lane) * 1.5;
			const nearest: float32 = ((device + 0.5) as int32) as float32;
			assert device - nearest < 0.001 && nearest - device < 0.001;
		}
	}
	frameEnd();
}

test "a recording is reused only while size, dpi, context generation and readout all match" {
	assert recordingHolds(true, 120.0, 60.0, 1.0, 3, 7, 120.0, 60.0, 1.0, 3, 7);
	assert !recordingHolds(false, 120.0, 60.0, 1.0, 3, 7, 120.0, 60.0, 1.0, 3, 7);
	assert !recordingHolds(true, 120.0, 60.0, 1.0, 3, 7, 121.0, 60.0, 1.0, 3, 7);
	assert !recordingHolds(true, 120.0, 60.0, 1.0, 3, 7, 120.0, 61.0, 1.0, 3, 7);
	assert !recordingHolds(true, 120.0, 60.0, 1.0, 3, 7, 120.0, 60.0, 1.5, 3, 7);
	assert !recordingHolds(true, 120.0, 60.0, 1.0, 3, 7, 120.0, 60.0, 1.0, 4, 7);
	assert !recordingHolds(true, 120.0, 60.0, 1.0, 3, 7, 120.0, 60.0, 1.0, 3, 8);
}
