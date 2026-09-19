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

const BASELINE_PATH: string = "tests/bench/baseline.json";
const UI_BINARY: string = "out/benchUi.exe";
const SPRITES_BINARY: string = "out/benchSprites.exe";

// One `scene.metric value` row as the bench prints it.
interface BenchRow {
	scene: string;
	metric: string;
	value: float64;
}

function parseFloat64(text: string): float64 {
	let value: float64 = 0.0;
	let fraction: float64 = 0.0;
	let scale: float64 = 1.0;
	let seenDot: boolean = false;
	for (let i: int32 = 0; i < text.length as int32; i++) {
		const code: int32 = text.charCodeAt(i) as int32;
		if (code == ".".code) { seenDot = true; continue; }
		if (code < "0".code || code > "9".code) { continue; }
		const digit: float64 = (code - "0".code) as float64;
		if (seenDot) {
			scale = scale * 10.0;
			fraction = fraction + digit / scale;
		} else {
			value = value * 10.0 + digit;
		}
	}
	return value + fraction;
}

function parseRows(output: string): BenchRow[] {
	const rows: BenchRow[] = [];
	for (const line of output.split("\n")) {
		const parts = line.split(" ");
		if ((parts.length as int32) != 2) { continue; }
		const key = parts[0].split(".");
		if ((key.length as int32) < 2) { continue; }
		rows.push({ scene: key[0], metric: key[1], value: parseFloat64(parts[1]) });
	}
	return rows;
}

function runBench(binary: string): BenchRow[] {
	const result = execFileCapture(binary, []);
	if (!result.ok) {
		console.log(`FAIL ${binary} did not run: ${result.error.message}`);
		return [];
	}
	return parseRows(result.value);
}

function rowValue(rows: BenchRow[], scene: string, metric: string): float64 {
	for (const row of rows) {
		if (row.scene.equals(scene) && row.metric.equals(metric)) { return row.value; }
	}
	return -1.0;
}

function checkCounter(rows: BenchRow[], scene: string, metric: string, expected: int32): boolean {
	const actual: float64 = rowValue(rows, scene, metric);
	if (actual < 0.0) {
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
	const actual: float64 = rowValue(rows, scene, "present");
	if (actual < 0.0) {
		console.log(`WARN ${scene}.present.ms was not reported`);
		return;
	}
	const marker: string = actual > baseline * warnFactor ? "WARN" : "REPORT";
	console.log(`${marker} ${scene}.present.ms ${actual} (baseline ${baseline}, warn above ${baseline * warnFactor})`);
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
	if ((uiRows.length as int32) == 0 || (spriteRows.length as int32) == 0) { return 1; }

	let failed: int32 = 0;
	const metrics: string[] = ["nodes", "draws", "buffersAlive", "buffersFailed", "nodesDrawn"];
	for (const metric of metrics) {
		if (!checkCounter(uiRows, "ui", metric, counters.ui.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}
	for (const metric of metrics) {
		if (!checkCounter(spriteRows, "sprites", metric, counters.sprites.getDynamicField(metric).asInt32())) { failed = failed + 1; }
	}

	const warnFactor: float64 = milliseconds.warnFactor.asNumber();
	reportMilliseconds(uiRows, "ui", milliseconds.ui.present.asNumber(), warnFactor);
	reportMilliseconds(spriteRows, "sprites", milliseconds.sprites.present.asNumber(), warnFactor);

	console.log("");
	console.log(`bench: ${failed} counter(s) off the baseline`);
	return failed == 0 ? 0 : 1;
}

process.exit(runCheck());
