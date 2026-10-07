// T4: run the two bench entries and judge their rows against tests/bench/baseline.json
// (docs/TESTING.md "T4"). Counters gate hard — they are deterministic for a given build.
// Milliseconds only report, with a warn threshold, and never fail: a wall-clock gate on a
// shared developer box produces flakes and then gets disabled, which is worse than a number
// nobody gates.
//
// The bench binaries are built by scripts/gate.sh, which passes their paths in; this tool
// runs them, so the whole perf story is one committed command.

import { readFile } from "std/fs";
import { execFileCapture, env } from "std/process";
import { BenchRow, parseRows } from "../harness/benchRows";

// Counted across both bench binaries, reported once at the end.
let unreadableRows: int32 = 0;
let ignoredLines: int32 = 0;

const BASELINE_PATH: string = "tests/bench/baseline.json";

const SUFFIX: string = env.get("BENCH_SUFFIX");

function binary(scene: string): string { return `out/bench${scene}${SUFFIX}.exe`; }

function runBench(binary: string): BenchRow[] {
	const result = execFileCapture(binary, []);
	if (!result.ok) {
		console.log(`FAIL ${binary} did not run: ${result.error.message}`);
		return [];
	}
	const parsed = parseRows(result.value);
	for (const bad of parsed.badLines) {
		console.log(`FAIL bench row '${bad}' has an unreadable value`);
	}
	unreadableRows = unreadableRows + parsed.unreadable;
	ignoredLines = ignoredLines + parsed.ignored;
	if ((parsed.rows.length as int32) == 0) {
		console.log(`FAIL ${binary} produced no bench rows at all (${parsed.ignored} line(s) ignored)`);
	}
	return parsed.rows;
}

// A tuple rather than a sentinel: now that a row can legitimately be negative - which is how
// a broken counter would show up - "not reported" needs a flag of its own.
function rowValue(rows: BenchRow[], scene: string, metric: string): [boolean, float64] {
	for (const row of rows) {
		if (row.scene.equals(scene) && row.metric.equals(metric)) { return [true, row.value]; }
	}
	return [false, 0.0];
}

function checkCounter(rows: BenchRow[], scene: string, metric: string, expected: int32): boolean {
	const [reported, actual] = rowValue(rows, scene, metric);
	if (!reported) {
		console.log(`FAIL ${scene}.${metric} was not reported`);
		return false;
	}
	if ((actual as int32) == expected) {
		console.log(`PASS ${scene}.${metric} ${expected}`);
		return true;
	}
	console.log(`FAIL ${scene}.${metric} is ${actual as int32}, the baseline says ${expected}`);
	return false;
}

function checkAtMost(rows: BenchRow[], scene: string, metric: string, limit: int32): boolean {
	const [reported, actual] = rowValue(rows, scene, metric);
	if (!reported) {
		console.log(`FAIL ${scene}.${metric} was not reported`);
		return false;
	}
	if ((actual as int32) <= limit) {
		console.log(`PASS ${scene}.${metric} ${actual as int32} (at most ${limit})`);
		return true;
	}
	console.log(`FAIL ${scene}.${metric} is ${actual as int32}, the bound is ${limit}`);
	return false;
}

function reportMilliseconds(rows: BenchRow[], scene: string, baseline: float64, warnFactor: float64): void {
	const [reported, actual] = rowValue(rows, scene, "present");
	if (!reported) {
		console.log(`WARN ${scene}.present.ms was not reported`);
		return;
	}
	const marker: string = actual > baseline * warnFactor ? "WARN" : "REPORT";
	console.log(`${marker} ${scene}.present.ms ${actual} (baseline ${baseline}, warn above ${baseline * warnFactor})`);
}

function reportProfile(rows: BenchRow[], scene: string): void {
	for (const row of rows) {
		if (!row.scene.equals(scene) || !row.metric.startsWith("profile")) { continue; }
		console.log(`REPORT ${scene}.${row.metric} ${row.value}`);
	}
}

function reportFirstPaint(rows: BenchRow[], scene: string): void {
	const [reported, firstPaint] = rowValue(rows, scene, "firstPaint");
	if (reported) { console.log(`REPORT ${scene}.firstPaint.ms ${firstPaint}`); }
}

function runCheck(): int32 {
	const text = readFile(BASELINE_PATH);
	if (!text.ok) {
		console.log(`FAIL ${BASELINE_PATH} is missing`);
		return 1;
	}
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) {
		console.log(`FAIL ${BASELINE_PATH} is not valid JSON: ${parsed.error}`);
		return 1;
	}
	const baseline = parsed.value;
	const counters = baseline.counters;
	const milliseconds = baseline.milliseconds;

	const uiRows = runBench(binary("Ui"));
	const spriteRows = runBench(binary("Sprites"));
	const textRows = runBench(binary("Text"));
	const editorRows = runBench(binary("Editor"));
	const scrollRows = runBench(binary("Scroll"));
	const empty: boolean = (uiRows.length as int32) == 0 || (spriteRows.length as int32) == 0
		|| (textRows.length as int32) == 0 || (editorRows.length as int32) == 0
		|| (scrollRows.length as int32) == 0;
	if (empty) {
		return 1;
	}

	let failed: int32 = 0;
	const metrics: string[] = [
		"nodes", "retainedNodes", "draws", "buffersAlive", "vertices",
		"uiInstances", "spriteInstances", "uploads", "uploadBytes", "atlasImages",
		"renderTargets", "droppedFrames", "glyphRasterizationsSteady", "glyphPages", "glyphBytes",
		"firstPaintRasterizations", "firstPaintUploadBytes", "idleDirty", "sweepPeakPages", "sweepRasterizations",
	];
	for (const metric of metrics) {
		if (!checkCounter(uiRows, "ui", metric, counters.ui.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		if (!checkCounter(spriteRows, "sprites", metric, counters.sprites.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		const expected: int32 = counters.text.getDynamicField(metric).asInt32();
		if (!checkCounter(textRows, "text", metric, expected)) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		const expected: int32 = counters.editor.getDynamicField(metric).asInt32();
		if (!checkCounter(editorRows, "editor", metric, expected)) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		const expected: int32 = counters.scroll.getDynamicField(metric).asInt32();
		if (!checkCounter(scrollRows, "scroll", metric, expected)) { failed = failed + 1; }
	}
	const emojiRows = runBench(binary("TextEmoji"));
	if ((emojiRows.length as int32) == 0) {
		failed = failed + 1;
	} else {
		const bounds = baseline.colourBounds;
		const limited: string[] = [
			"colourPages", "colourBytes", "sweepColourRasterizations", "colourRasterizationsSteady",
		];
		for (const metric of limited) {
			const limit: int32 = bounds.getDynamicField(metric).asInt32();
			if (!checkAtMost(emojiRows, "textEmoji", metric, limit)) { failed = failed + 1; }
		}
		const [drawn, pages] = rowValue(emojiRows, "textEmoji", "colourPages");
		if (!drawn || (pages as int32) < 1) {
			console.log("FAIL textEmoji.colourPages is 0: no colour glyph was drawn");
			failed = failed + 1;
		}
	}
	const sdfRows = runBench(binary("TextSdf"));
	if ((sdfRows.length as int32) == 0) {
		failed = failed + 1;
	} else {
		const bounds = baseline.sdfBounds;
		const limited: string[] = [
			"sdfPages", "sdfBytes", "sweepSdfGenerations", "sdfGenerationsSteady",
			"sweepRasterizations", "glyphRasterizationsSteady",
		];
		for (const metric of limited) {
			const limit: int32 = bounds.getDynamicField(metric).asInt32();
			if (!checkAtMost(sdfRows, "textSdf", metric, limit)) { failed = failed + 1; }
		}
		const [drawn, generations] = rowValue(sdfRows, "textSdf", "sweepSdfGenerations");
		if (!drawn || (generations as int32) < 1) {
			console.log("FAIL textSdf.sweepSdfGenerations is 0: no glyph was drawn from the field");
			failed = failed + 1;
		}
	}
	const lookups: int32 = counters.text.getDynamicField("measureGlyphLookups").asInt32();
	if (!checkCounter(textRows, "text", "measureGlyphLookups", lookups)) { failed = failed + 1; }

	const warnFactor: float64 = milliseconds.warnFactor.asNumber();
	reportMilliseconds(uiRows, "ui", milliseconds.ui.present.asNumber(), warnFactor);
	reportMilliseconds(spriteRows, "sprites", milliseconds.sprites.present.asNumber(), warnFactor);
	reportMilliseconds(textRows, "text", milliseconds.text.present.asNumber(), warnFactor);
	reportMilliseconds(editorRows, "editor", milliseconds.editor.present.asNumber(), warnFactor);
	reportMilliseconds(scrollRows, "scroll", milliseconds.scroll.present.asNumber(), warnFactor);
	reportFirstPaint(uiRows, "ui");
	reportFirstPaint(spriteRows, "sprites");
	reportFirstPaint(textRows, "text");
	reportFirstPaint(editorRows, "editor");
	reportFirstPaint(scrollRows, "scroll");
	reportProfile(uiRows, "ui");
	reportProfile(spriteRows, "sprites");
	reportProfile(textRows, "text");
	reportProfile(editorRows, "editor");
	reportProfile(scrollRows, "scroll");

	console.log("");
	if (unreadableRows > 0) {
		console.log(`bench: ${unreadableRows} row(s) claimed to be a measurement and could not be read`);
	}
	console.log(`bench: ${failed} counter(s) off the baseline, ${ignoredLines} non-row line(s) ignored`);
	return failed == 0 && unreadableRows == 0 ? 0 : 1;
}

process.exit(runCheck());
