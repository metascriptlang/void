// T4: run the two bench entries and judge their rows against tests/bench/baseline.json
// (docs/TESTING.md "T4"). Counters gate hard — they are deterministic for a given build.
// Milliseconds only report, with a warn threshold, and never fail: a wall-clock gate on a
// shared developer box produces flakes and then gets disabled, which is worse than a number
// nobody gates.
//
// The bench binaries are built by scripts/gate.sh, which passes their paths in; this tool
// runs them, so the whole perf story is one committed command.

import { readFile } from "std/fs";
import { execFileCapture } from "std/process";
import { parseRows } from "../harness/benchRows";

// Counted across both bench binaries, reported once at the end.
let unreadableRows: int32 = 0;
let ignoredLines: int32 = 0;

const BASELINE_PATH: string = "tests/bench/baseline.json";
const UI_BINARY: string = "out/benchUi.exe";
const SPRITES_BINARY: string = "out/benchSprites.exe";
const TEXT_BINARY: string = "out/benchText.exe";

// One `scene.metric value` row as the bench prints it.
interface BenchRow {
	scene: string;
	metric: string;
	value: float64;
}

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

function reportMilliseconds(rows: BenchRow[], scene: string, baseline: float64, warnFactor: float64): void {
	const [reported, actual] = rowValue(rows, scene, "present");
	if (!reported) {
		console.log(`WARN ${scene}.present.ms was not reported`);
		return;
	}
	const marker: string = actual > baseline * warnFactor ? "WARN" : "REPORT";
	console.log(`${marker} ${scene}.present.ms ${actual} (baseline ${baseline}, warn above ${baseline * warnFactor})`);
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

	const uiRows = runBench(UI_BINARY);
	const spriteRows = runBench(SPRITES_BINARY);
	const textRows = runBench(TEXT_BINARY);
	if ((uiRows.length as int32) == 0 || (spriteRows.length as int32) == 0 || (textRows.length as int32) == 0) {
		return 1;
	}

	let failed: int32 = 0;
	const metrics: string[] = [
		"nodes", "retainedNodes", "draws", "buffersAlive", "vertices",
		"uiInstances", "spriteInstances", "uploads", "uploadBytes", "atlasImages",
		"renderTargets", "droppedFrames", "glyphRasterizationsSteady", "glyphPages", "glyphBytes",
		"firstPaintRasterizations", "sweepPeakPages", "sweepRasterizations",
	];
	for (const metric of metrics) {
		if (!checkCounter(uiRows, "ui", metric, counters.ui.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		if (!checkCounter(spriteRows, "sprites", metric, counters.sprites.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		if (!checkCounter(textRows, "text", metric, counters.text.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}
	const lookups: int32 = counters.text.getDynamicField("measureGlyphLookups").asInt32();
	if (!checkCounter(textRows, "text", "measureGlyphLookups", lookups)) { failed = failed + 1; }

	const warnFactor: float64 = milliseconds.warnFactor.asNumber();
	reportMilliseconds(uiRows, "ui", milliseconds.ui.present.asNumber(), warnFactor);
	reportMilliseconds(spriteRows, "sprites", milliseconds.sprites.present.asNumber(), warnFactor);
	reportMilliseconds(textRows, "text", milliseconds.text.present.asNumber(), warnFactor);
	reportFirstPaint(uiRows, "ui");
	reportFirstPaint(spriteRows, "sprites");
	reportFirstPaint(textRows, "text");

	console.log("");
	if (unreadableRows > 0) {
		console.log(`bench: ${unreadableRows} row(s) claimed to be a measurement and could not be read`);
	}
	console.log(`bench: ${failed} counter(s) off the baseline, ${ignoredLines} non-row line(s) ignored`);
	return failed == 0 && unreadableRows == 0 ? 0 : 1;
}

process.exit(runCheck());
