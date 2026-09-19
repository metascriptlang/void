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

// Handles the sign and an exponent, because MetaScript prints a float64 in whatever form it
// likes and a counter that regressed to a negative number must not be read as positive -
// that is exactly the regression the counter gate exists to catch.
function parseFloat64(text: string): float64 {
	const length: int32 = text.length as int32;
	let index: int32 = 0;
	let sign: float64 = 1.0;
	if (index < length && (text.charCodeAt(index) as int32) == "-".code) {
		sign = -1.0;
		index = index + 1;
	} else if (index < length && (text.charCodeAt(index) as int32) == "+".code) {
		index = index + 1;
	}
	let value: float64 = 0.0;
	while (index < length) {
		const code: int32 = text.charCodeAt(index) as int32;
		if (code < "0".code || code > "9".code) { break; }
		value = value * 10.0 + ((code - "0".code) as float64);
		index = index + 1;
	}
	if (index < length && (text.charCodeAt(index) as int32) == ".".code) {
		index = index + 1;
		let scale: float64 = 1.0;
		while (index < length) {
			const code: int32 = text.charCodeAt(index) as int32;
			if (code < "0".code || code > "9".code) { break; }
			scale = scale * 10.0;
			value = value + ((code - "0".code) as float64) / scale;
			index = index + 1;
		}
	}
	if (index < length) {
		const marker: int32 = text.charCodeAt(index) as int32;
		if (marker == "e".code || marker == "E".code) {
			index = index + 1;
			let exponentSign: int32 = 1;
			if (index < length && (text.charCodeAt(index) as int32) == "-".code) {
				exponentSign = -1;
				index = index + 1;
			} else if (index < length && (text.charCodeAt(index) as int32) == "+".code) {
				index = index + 1;
			}
			let exponent: int32 = 0;
			while (index < length) {
				const code: int32 = text.charCodeAt(index) as int32;
				if (code < "0".code || code > "9".code) { break; }
				exponent = exponent * 10 + (code - "0".code);
				index = index + 1;
			}
			for (let step: int32 = 0; step < exponent; step++) {
				value = exponentSign > 0 ? value * 10.0 : value / 10.0;
			}
		}
	}
	return sign * value;
}

test "parseFloat64 keeps the sign" {
	assert parseFloat64("-4312") == -4312.0;
}

test "parseFloat64 reads an exponent" {
	assert parseFloat64("1.2e-05") < 0.0001;
	assert parseFloat64("1.5e2") == 150.0;
}

test "parseFloat64 reads a plain decimal" {
	assert parseFloat64("4.48") > 4.47;
	assert parseFloat64("4.48") < 4.49;
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
	const metrics: string[] = ["nodes", "retainedNodes", "draws", "buffersAlive", "buffersRefused"];
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
