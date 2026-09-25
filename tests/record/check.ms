// The record against the code (docs/TESTING.md "The record checks itself"): what the tracked
// docs must repeat, checked where it is repeated. Run by scripts/gate.sh from the repo root.

import { readFile } from "std/fs";
import {
	PendingRow,
	pendingRows,
	phaseSection,
	closesIds,
	contains,
	goldenRowCount,
} from "../harness/record";

const PHASES: string[] = ["P4", "P5", "P6"];

function read(path: string): string {
	const text = readFile(path);
	if (!text.ok) {
		console.log(`FAIL ${path} cannot be read`);
		return "";
	}
	return text.value;
}

function checkOwners(rows: PendingRow[], roadmap: string): int32 {
	let failed: int32 = 0;
	for (const phase of PHASES) {
		const closes = closesIds(phaseSection(roadmap, phase));
		if ((closes.length as int32) == 0) {
			console.log(`FAIL docs/VOID2D.md ${phase} has no **Closes** line`);
			failed = failed + 1;
		}
		for (const id of closes) {
			let owner: string = "";
			for (const row of rows) {
				if (row.id.equals(id)) { owner = row.owner; }
			}
			if (!owner.equals(phase)) {
				const says: string = owner.equals("") ? "no row" : `owner ${owner}`;
				console.log(`FAIL ${phase} closes ${id}, but tests/PENDING.md has ${says}`);
				failed = failed + 1;
			}
		}
		for (const row of rows) {
			if (row.owner.equals(phase) && !contains(closes, row.id)) {
				console.log(
					`FAIL tests/PENDING.md ${row.id} is owned by ${phase}, ` +
					"whose **Closes** line omits it",
				);
				failed = failed + 1;
			}
		}
	}
	return failed;
}

function checkGoldenCount(table: string, testing: string): int32 {
	const rows: int32 = goldenRowCount(table);
	const claim: string = `| D3D11 | **${rows} / ${rows} scenes byte-identical**`;
	if (testing.indexOf(claim) < 0) {
		console.log(
			`FAIL docs/TESTING.md's D3D11 row does not say ${rows} / ${rows}: ` +
			`tests/golden/table.ms has ${rows} scenes`,
		);
		return 1;
	}
	return 0;
}

function main(): int32 {
	const pending: string = read("tests/PENDING.md");
	const roadmap: string = read("docs/VOID2D.md");
	const testing: string = read("docs/TESTING.md");
	const table: string = read("tests/golden/table.ms");
	const rows = pendingRows(pending);
	let failed: int32 = checkOwners(rows, roadmap) + checkGoldenCount(table, testing);
	if ((rows.length as int32) == 0) {
		console.log("FAIL tests/PENDING.md parsed to no rows");
		failed = failed + 1;
	}
	console.log(`record: ${rows.length} PENDING rows against the Closes lines of ${PHASES.length} phases, ` +
		`${goldenRowCount(table)} golden scenes against TESTING.md, ${failed} off`);
	return failed == 0 ? 0 : 1;
}

process.exit(main());
