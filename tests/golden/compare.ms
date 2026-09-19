// The golden comparator: judges what tests/golden/runner.ms captured. No GPU, no window —
// it reads two PNGs per row and applies the tolerance policy in docs/TESTING.md "T2".
//
// The policy, unchanged from that doc:
//   - byte-identical is the default, and the comparator always reports
//     `N px differ, max delta M, bbox` so a failure says what moved and where;
//   - a scene may differ only if tests/PENDING.md carries an entry for it with a budget,
//     and a pending scene that comes back byte-identical FAILS and its entry is deleted —
//     rexa's graduation rule, applied to images;
//   - a row in the table with no golden is an error, not a skip.
//
// Two rows judge the comparator rather than the renderer (docs/TESTING.md, "Distrust the
// harness before the engine"): `harness/solid`, whose expected bytes are arithmetic, and
// `harness/mustFail`, whose golden is deliberately wrong and which therefore fails if it
// passes. The third self-check, "two draws of the same state are identical", belongs to
// the runner.

import { readLines } from "std/fs";
import { trimSpaces, parseInt32, NOT_A_NUMBER } from "../harness/parse";
import {
	SceneRow,
	sceneRows,
	backendDirectory,
	MUST_FAIL_SCENE,
	HAND_COMPUTED_SCENE,
	HARNESS_CLEAR_R,
	HARNESS_CLEAR_G,
	HARNESS_CLEAR_B,
	HARNESS_FILL_R,
	HARNESS_FILL_G,
	HARNESS_FILL_B,
	HARNESS_RECT_X,
	HARNESS_RECT_Y,
	HARNESS_RECT_W,
	HARNESS_RECT_H,
} from "./table";
import {
	voidPngLoad,
	voidPngWidth,
	voidPngHeight,
	voidPngPixel,
	voidPngDiff,
	voidPngDiffMaxDelta,
	voidPngDiffMinX,
	voidPngDiffMinY,
	voidPngDiffMaxX,
	voidPngDiffMaxY,
	voidPngWriteDiffMask,
} from "./pngio.h";

const GOLDEN_ROOT: string = "tests/golden";
const ACTUAL_ROOT: string = "out/golden";
const PENDING_PATH: string = "tests/PENDING.md";

// A tests/PENDING.md row that carries an image budget.
interface PendingBudget {
	id: string;
	maxPixels: int32;
	maxDelta: int32;
}

enum Verdict {
	Pass,
	PassPending,
	Fail,
}

// tests/PENDING.md is a markdown table so that one file serves both a reader and the
// harness. A row is `| id | tier | reason | phase | date | maxPixels | maxDelta |`, and only
// rows whose id starts with `golden:` mean anything here.
let malformed: int32 = 0;

function readPendingBudgets(): PendingBudget[] {
	const budgets: PendingBudget[] = [];
	const lines = readLines(PENDING_PATH);
	if (!lines.ok) { return budgets; }
	for (const line of lines.value) {
		const cells = line.split("|");
		if ((cells.length as int32) < 8) { continue; }
		const id = trimSpaces(cells[1]);
		if (!id.startsWith("golden:")) { continue; }
		const name = id.substring("golden:".length as int32, id.length as int32);
		const maxPixels: int32 = parseInt32(cells[6]);
		const maxDelta: int32 = parseInt32(cells[7]);
		if (maxPixels == NOT_A_NUMBER || maxDelta == NOT_A_NUMBER) {
			console.log(`FAIL ${PENDING_PATH} row golden:${name} has an unreadable budget: maxPixels '${trimSpaces(cells[6])}', maxDelta '${trimSpaces(cells[7])}'`);
			malformed = malformed + 1;
			continue;
		}
		budgets.push({ id: name, maxPixels: maxPixels, maxDelta: maxDelta });
	}
	return budgets;
}

function budgetFor(budgets: PendingBudget[], name: string): PendingBudget | null {
	for (const budget of budgets) {
		if (budget.id.equals(name)) { return budget; }
	}
	return null;
}

// Slot 0 is the golden, slot 1 the fresh capture. Every byte of harness/solid is predicted
// here: a readback that swaps channels, returns zeros or passes everything fails this row
// before it can be blamed on the renderer.
function checkHandComputed(row: SceneRow): boolean {
	let bad: int32 = 0;
	for (let y: int32 = 0; y < row.height; y++) {
		for (let x: int32 = 0; x < row.width; x++) {
			const inside: boolean = x >= HARNESS_RECT_X && x < HARNESS_RECT_X + HARNESS_RECT_W
				&& y >= HARNESS_RECT_Y && y < HARNESS_RECT_Y + HARNESS_RECT_H;
			const wantR: int32 = inside ? HARNESS_FILL_R : HARNESS_CLEAR_R;
			const wantG: int32 = inside ? HARNESS_FILL_G : HARNESS_CLEAR_G;
			const wantB: int32 = inside ? HARNESS_FILL_B : HARNESS_CLEAR_B;
			if (voidPngPixel(1, x, y, 0) == wantR
				&& voidPngPixel(1, x, y, 1) == wantG
				&& voidPngPixel(1, x, y, 2) == wantB) { continue; }
			if (bad < 4) {
				console.log(`    (${x},${y}) is ${voidPngPixel(1, x, y, 0)},${voidPngPixel(1, x, y, 1)},${voidPngPixel(1, x, y, 2)}, computed ${wantR},${wantG},${wantB}`);
			}
			bad = bad + 1;
		}
	}
	if (bad == 0) { return true; }
	console.log(`  hand-computed check: ${bad} of ${row.width * row.height} pixels are not what the arithmetic says`);
	return false;
}

function reportDiff(name: string, differ: int32): void {
	if (differ <= 0) {
		console.log(`  ${name}: 0 px differ, max delta 0`);
		return;
	}
	console.log(`  ${name}: ${differ} px differ, max delta ${voidPngDiffMaxDelta()}, bbox (${voidPngDiffMinX()},${voidPngDiffMinY()})-(${voidPngDiffMaxX()},${voidPngDiffMaxY()})`);
}

function judge(row: SceneRow, budgets: PendingBudget[], backend: string): Verdict {
	const goldenPath: string = `${GOLDEN_ROOT}/${backend}/${row.name}.png`;
	const actualPath: string = `${ACTUAL_ROOT}/${backend}/${row.name}.png`;

	if (voidPngLoad(1, actualPath) == 0) {
		console.log(`FAIL ${row.name} was not captured (${actualPath} is missing)`);
		return Verdict.Fail;
	}
	if (voidPngLoad(0, goldenPath) == 0) {
		console.log(`FAIL ${row.name} is in the table and has no golden (${goldenPath})`);
		return Verdict.Fail;
	}
	if (voidPngWidth(1) != row.width || voidPngHeight(1) != row.height) {
		console.log(`FAIL ${row.name} capture is ${voidPngWidth(1)}x${voidPngHeight(1)}, the table says ${row.width}x${row.height}`);
		return Verdict.Fail;
	}

	if (row.name.equals(HAND_COMPUTED_SCENE) && !checkHandComputed(row)) {
		console.log(`FAIL ${row.name} does not match its hand-computed pixels — suspect the capture path, not the renderer`);
		return Verdict.Fail;
	}

	const differ: int32 = voidPngDiff();
	if (differ < 0) {
		console.log(`FAIL ${row.name} golden is ${voidPngWidth(0)}x${voidPngHeight(0)} and the capture is ${voidPngWidth(1)}x${voidPngHeight(1)}`);
		return Verdict.Fail;
	}

	// The deliberately wrong golden: the comparator has to report it, or it cannot fail at all.
	if (row.name.equals(MUST_FAIL_SCENE)) {
		if (differ > 0) {
			reportDiff(row.name, differ);
			console.log(`PASS ${row.name} (the deliberately wrong golden was reported, so the comparator can fail)`);
			return Verdict.Pass;
		}
		console.log(`FAIL ${row.name} matched its golden — that golden is supposed to be wrong, so the comparator cannot fail`);
		return Verdict.Fail;
	}

	const budget = budgetFor(budgets, row.name);
	if (budget !== null) {
		if (differ == 0) {
			console.log(`FAIL ${row.name} is byte-identical and still listed in ${PENDING_PATH} — delete the entry`);
			return Verdict.Fail;
		}
		reportDiff(row.name, differ);
		if (differ <= budget.maxPixels && voidPngDiffMaxDelta() <= budget.maxDelta) {
			console.log(`PENDING ${row.name} within its budget (${budget.maxPixels} px, delta ${budget.maxDelta})`);
			return Verdict.PassPending;
		}
		voidPngWriteDiffMask(`${ACTUAL_ROOT}/${backend}/${row.name}.diff.png`);
		console.log(`FAIL ${row.name} is over its budget (${budget.maxPixels} px, delta ${budget.maxDelta})`);
		return Verdict.Fail;
	}

	if (differ == 0) {
		console.log(`PASS ${row.name}`);
		return Verdict.Pass;
	}
	reportDiff(row.name, differ);
	voidPngWriteDiffMask(`${ACTUAL_ROOT}/${backend}/${row.name}.diff.png`);
	console.log(`FAIL ${row.name} differs from its golden and has no ${PENDING_PATH} entry`);
	return Verdict.Fail;
}

function runComparison(): int32 {
	// The comparator never runs a backend, so it is told which golden set to read. 1 = D3D11.
	const backend: string = backendDirectory(1);
	const budgets = readPendingBudgets();
	const rows = sceneRows();
	let passed: int32 = 0;
	let pending: int32 = 0;
	let failed: int32 = 0;

	for (const row of rows) {
		const verdict = judge(row, budgets, backend);
		if (verdict === Verdict.Pass) { passed = passed + 1; }
		else if (verdict === Verdict.PassPending) { pending = pending + 1; }
		else { failed = failed + 1; }
	}

	const total: int32 = rows.length as int32;
	console.log("");
	if (malformed > 0) {
		console.log(`golden ${backend}: ${malformed} unreadable ${PENDING_PATH} budget row(s)`);
	}
	console.log(`golden ${backend}: ${passed} pass, ${pending} pending, ${failed} fail of ${total}`);
	console.log(`pass rate ${(passed + pending) * 100 / total}%`);
	return failed == 0 && malformed == 0 ? 0 : 1;
}

process.exit(runComparison());
