// The record against the code (docs/TESTING.md "The record checks itself"): what the tracked
// docs must repeat, checked where it is repeated. Run by scripts/gate.sh from the repo root.

import { readFile } from "std/fs";
import {
	PendingRow,
	pendingRows,
	roadmapPhases,
	phaseSection,
	closesIds,
	contains,
	goldenRowCount,
} from "../harness/record";

const OWNERS_OUTSIDE_THE_ROADMAP: string[] = ["compiler", "human"];

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
	const phases = roadmapPhases(roadmap);
	for (const row of rows) {
		if (!contains(phases, row.owner) && !contains(OWNERS_OUTSIDE_THE_ROADMAP, row.owner)) {
			console.log(`FAIL tests/PENDING.md ${row.id}: ${row.owner} is no roadmap phase`);
			failed = failed + 1;
		}
	}
	for (const phase of phases) {
		const closes = closesIds(phaseSection(roadmap, phase));
		let owns: boolean = false;
		for (const row of rows) {
			if (row.owner.equals(phase)) { owns = true; }
		}
		if (owns && (closes.length as int32) == 0) {
			console.log(`FAIL docs/VOID2D.md ${phase} owns PENDING rows but has no **Closes**`);
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

// Only the total: how many of them pass is the run's to say, and the gate checks that.
function checkGoldenCount(table: string, testing: string): int32 {
	const rows: int32 = goldenRowCount(table);
	for (const line of testing.split("\n")) {
		if (line.startsWith("| D3D11 | **") && line.indexOf(` / ${rows} scenes`) >= 0) { return 0; }
	}
	console.log(
		`FAIL docs/TESTING.md's D3D11 row does not count ${rows} scenes, ` +
		"as tests/golden/table.ms does",
	);
	return 1;
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
	const phases: int32 = roadmapPhases(roadmap).length as int32;
	console.log(
		`record: ${rows.length} PENDING rows against the Closes lines of ${phases} phases, ` +
		`${goldenRowCount(table)} golden scenes against TESTING.md, ${failed} off`,
	);
	return failed == 0 ? 0 : 1;
}

process.exit(main());
