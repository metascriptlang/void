// The image judgement both comparators share: golden 2D (tests/golden/compare.ms) and gate3d's
// Metal frames (tests/capture3d/compare3d.ms). Slot 0 holds the golden, slot 1 the capture, and
// the policy is docs/TESTING.md "T2".

import { readLines } from "std/fs";
import { trimSpaces, parseInt32, NOT_A_NUMBER } from "../harness/parse";
import {
	voidPngDiff,
	voidPngDiffMaxDelta,
	voidPngDiffOverOne,
	voidPngDiffMinX,
	voidPngDiffMinY,
	voidPngDiffMaxX,
	voidPngDiffMaxY,
	voidPngWriteDiffMask,
	voidPngWidth,
	voidPngHeight,
} from "./pngio.h";

export const PENDING_PATH: string = "tests/PENDING.md";
// docs/TESTING.md "Guardrail 9": across backends a delta of 1 is ignored, and a scene fails at
// a max delta of 4 or when more than 0.05 % of its pixels differ by 2 or 3.
const CROSS_FAIL_DELTA: int32 = 4;
const CROSS_MAX_SHARE: float64 = 0.0005;

// A tests/PENDING.md row that carries an image budget.
export interface PendingBudget {
	id: string;
	maxPixels: int32;
	maxDelta: int32;
}

export interface PendingBudgets {
	rows: PendingBudget[];
	malformed: int32;
}

export enum Verdict {
	Pass,
	PassPending,
	Fail,
}

// tests/PENDING.md is a markdown table so that one file serves both a reader and the
// harness. A row is `| id | tier | reason | phase | date | maxPixels | maxDelta |`, and only
// rows whose id starts with `prefix` mean anything to the caller.
export function readPendingBudgets(prefix: string): PendingBudgets {
	const found: PendingBudgets = { rows: [], malformed: 0 };
	const lines = readLines(PENDING_PATH);
	if (!lines.ok) { return found; }
	for (const line of lines.value) {
		const cells = line.split("|");
		// Order matters, and it used to be wrong. The `< 8` test is what lets this parser walk
		// a markdown file at all - prose, headings and the 3-cell index rows all fall out here
		// - so it cannot simply become a failure. But it ran *before* the `golden:` test, which
		// meant a budget row that had lost a column was dropped as quietly as a paragraph.
		// Measured: a `golden:` row with two columns missing left the comparator reporting
		// `45 pass, 0 fail` and exit 0, with the budget it carried silently absent.
		// So: enough cells to read an id, then decide whether this row is ours, and only then
		// insist on the full width - loudly, because by then we know it was meant to be a row.
		if ((cells.length as int32) < 2) { continue; }
		const id = trimSpaces(cells[1]);
		if (!id.startsWith(prefix)) { continue; }
		if ((cells.length as int32) < 8) {
			console.log(`FAIL ${PENDING_PATH} row ${id} has ${cells.length as int32} cells, not the 8 a ` +
				`budget row needs`);
			found.malformed = found.malformed + 1;
			continue;
		}
		const name = id.substring(prefix.length as int32, id.length as int32);
		const maxPixels: int32 = parseInt32(cells[6]);
		const maxDelta: int32 = parseInt32(cells[7]);
		if (maxPixels == NOT_A_NUMBER || maxDelta == NOT_A_NUMBER) {
			console.log(`FAIL ${PENDING_PATH} row ${id} has an unreadable budget: maxPixels ` +
				`'${trimSpaces(cells[6])}', maxDelta '${trimSpaces(cells[7])}'`);
			found.malformed = found.malformed + 1;
			continue;
		}
		found.rows.push({ id: name, maxPixels: maxPixels, maxDelta: maxDelta });
	}
	return found;
}

function budgetFor(budgets: PendingBudget[], name: string): PendingBudget | null {
	for (const budget of budgets) {
		if (budget.id.equals(name)) { return budget; }
	}
	return null;
}

export function reportDiff(name: string, differ: int32): void {
	if (differ <= 0) {
		console.log(`  ${name}: 0 px differ, max delta 0`);
		return;
	}
	console.log(`  ${name}: ${differ} px differ, max delta ${voidPngDiffMaxDelta()}, bbox ` +
		`(${voidPngDiffMinX()},${voidPngDiffMinY()})-(${voidPngDiffMaxX()},${voidPngDiffMaxY()})`);
}

// Diffs the two loaded slots and judges the result. `cross` judges a capture from another
// backend than the golden's, first under the cross-backend bound; `budgetId` names the
// PENDING row that may hold this image; `maskPath` receives the diff mask of a failure.
export function judgeLoaded(
	name: string,
	budgetId: string,
	cross: boolean,
	budgets: PendingBudget[],
	maskPath: string,
): Verdict {
	const differ: int32 = voidPngDiff();
	if (differ < 0) {
		console.log(`FAIL ${name} golden is ${voidPngWidth(0)}x${voidPngHeight(0)} and the capture ` +
			`is ${voidPngWidth(1)}x${voidPngHeight(1)}`);
		return Verdict.Fail;
	}

	if (cross && differ > 0) {
		const pixels: float64 = (voidPngWidth(1) * voidPngHeight(1)) as float64;
		const within: boolean = voidPngDiffMaxDelta() < CROSS_FAIL_DELTA
			&& (voidPngDiffOverOne() as float64) <= pixels * CROSS_MAX_SHARE;
		if (within) {
			reportDiff(name, differ);
			console.log(`PASS ${name} within the cross-backend bound (${voidPngDiffOverOne()} px over ` +
				`delta 1)`);
			return Verdict.PassPending;
		}
	}

	const budget = budgetFor(budgets, budgetId);
	if (budget !== null) {
		if (differ == 0) {
			console.log(`FAIL ${name} is byte-identical and still listed in ${PENDING_PATH} — delete ` +
				`the entry`);
			return Verdict.Fail;
		}
		reportDiff(name, differ);
		if (differ <= budget.maxPixels && voidPngDiffMaxDelta() <= budget.maxDelta) {
			console.log(`PENDING ${name} within its budget (${budget.maxPixels} px, delta ` +
				`${budget.maxDelta})`);
			return Verdict.PassPending;
		}
		voidPngWriteDiffMask(maskPath);
		console.log(`FAIL ${name} is over its budget (${budget.maxPixels} px, delta ` +
			`${budget.maxDelta})`);
		return Verdict.Fail;
	}

	if (differ == 0) {
		console.log(`PASS ${name}`);
		return Verdict.Pass;
	}
	reportDiff(name, differ);
	voidPngWriteDiffMask(maskPath);
	console.log(`FAIL ${name} differs from its golden and has no ${PENDING_PATH} entry`);
	return Verdict.Fail;
}
