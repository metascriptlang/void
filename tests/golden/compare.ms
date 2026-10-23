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

import { env } from "std/process";
import { PENDING_PATH, PendingBudget, Verdict, readPendingBudgets, reportDiff, judgeLoaded } from "./judge";
import {
	SceneRow,
	sceneRows,
	backendDirectory,
	sceneExclusion,
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
} from "./pngio.h";

const GOLDEN_ROOT: string = "tests/golden";
const ACTUAL_ROOT: string = "out/golden";
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
				console.log(`    (${x},${y}) is ` +
					`${voidPngPixel(1, x, y, 0)},${voidPngPixel(1, x, y, 1)},` +
					`${voidPngPixel(1, x, y, 2)}, computed ${wantR},${wantG},${wantB}`);
			}
			bad = bad + 1;
		}
	}
	if (bad == 0) { return true; }
	console.log(`  hand-computed check: ${bad} of ${row.width * row.height} pixels are not what the ` +
		`arithmetic says`);
	return false;
}

function judge(
	row: SceneRow,
	budgets: PendingBudget[],
	backend: string,
	captured: string,
): Verdict {
	const goldenPath: string = `${GOLDEN_ROOT}/${backend}/${row.name}.png`;
	const actualPath: string = `${ACTUAL_ROOT}/${captured}/${row.name}.png`;
	const cross: boolean = !captured.equals(backend);

	if (voidPngLoad(1, actualPath) == 0) {
		console.log(`FAIL ${row.name} was not captured (${actualPath} is missing)`);
		return Verdict.Fail;
	}
	if (voidPngLoad(0, goldenPath) == 0) {
		console.log(`FAIL ${row.name} is in the table and has no golden (${goldenPath})`);
		return Verdict.Fail;
	}
	if (voidPngWidth(1) != row.width || voidPngHeight(1) != row.height) {
		console.log(`FAIL ${row.name} capture is ${voidPngWidth(1)}x${voidPngHeight(1)}, the table ` +
			`says ${row.width}x${row.height}`);
		return Verdict.Fail;
	}

	if (row.name.equals(HAND_COMPUTED_SCENE) && !checkHandComputed(row)) {
		console.log(`FAIL ${row.name} does not match its hand-computed pixels — suspect the capture ` +
			`path, not the renderer`);
		return Verdict.Fail;
	}

	// The deliberately wrong golden: the comparator has to report it, or it cannot fail at all.
	if (row.name.equals(MUST_FAIL_SCENE)) {
		const differ: int32 = voidPngDiff();
		if (differ > 0) {
			reportDiff(row.name, differ);
			console.log(`PASS ${row.name} (the deliberately wrong golden was reported, so the comparator ` +
				`can fail)`);
			return Verdict.Pass;
		}
		console.log(`FAIL ${row.name} matched its golden — that golden is supposed to be wrong, so the ` +
			`comparator cannot fail`);
		return Verdict.Fail;
	}

	return judgeLoaded(row.name, cross ? `${row.name}@${captured}` : row.name, cross, budgets,
		`${ACTUAL_ROOT}/${captured}/${row.name}.diff.png`);
}

function runComparison(): int32 {
	// The comparator never runs a backend, so it is told which golden set to read. 1 = D3D11.
	const backend: string = backendDirectory(1);
	// VOID_CONFORM names another backend's captures to judge against the same D3D11 goldens,
	// under the cross-backend bound instead of byte identity.
	const conform: string = env.get("VOID_CONFORM");
	const captured: string = conform.length > 0 ? conform : backend;
	const read = readPendingBudgets("golden:");
	const budgets = read.rows;
	const rows = sceneRows();
	let passed: int32 = 0;
	let pending: int32 = 0;
	let failed: int32 = 0;
	let excluded: int32 = 0;

	for (const row of rows) {
		const why: string = sceneExclusion(captured, row.name);
		if (why.length > 0) {
			console.log(`EXCLUDED ${row.name} ${why}`);
			excluded = excluded + 1;
			continue;
		}
		const verdict = judge(row, budgets, backend, captured);
		if (verdict === Verdict.Pass) { passed = passed + 1; }
		else if (verdict === Verdict.PassPending) { pending = pending + 1; }
		else { failed = failed + 1; }
	}

	const total: int32 = (rows.length as int32) - excluded;
	console.log("");
	if (read.malformed > 0) {
		console.log(`golden ${captured}: ${read.malformed} unreadable ${PENDING_PATH} budget row(s)`);
	}
	console.log(`golden ${captured}: ${passed} pass, ${pending} pending, ${failed} fail of ${total}`
		+ (excluded > 0 ? ` (${excluded} excluded)` : ""));
	console.log(`pass rate ${(passed + pending) * 100 / total}%`);
	return failed == 0 && read.malformed == 0 ? 0 : 1;
}

process.exit(runComparison());
