// The record parsers for tests/record/check.ms, here so T0 can test them without running the
// check (check.ms is an entry point and ends in `process.exit`).

import { trimSpaces } from "./parse";

export interface PendingRow {
	id: string;
	tier: string;
	owner: string;
}

// A Markdown table row's cells. A `|` inside backticks is text, not a separator: PENDING
// reasons quote code such as `FlexStyle | null`.
export function tableCells(line: string): string[] {
	const raw: string[] = [];
	let current: string = "";
	const segments = line.split("`");
	for (let i: int32 = 0; i < (segments.length as int32); i++) {
		if (i % 2 == 1) {
			current += "`" + segments[i] + "`";
			continue;
		}
		const pieces = segments[i].split("|");
		for (let j: int32 = 0; j < (pieces.length as int32); j++) {
			if (j > 0) {
				raw.push(current);
				current = "";
			}
			current += pieces[j];
		}
	}
	const cells: string[] = [];
	for (let k: int32 = 1; k < (raw.length as int32); k++) { cells.push(trimSpaces(raw[k])); }
	return cells;
}

// Any single word but the header's and the separator's: a row is a row because its tier cell
// says so, not because of how its id is spelled.
function isPendingId(cell: string): boolean {
	if ((cell.length as int32) == 0 || cell.indexOf(" ") >= 0) { return false; }
	return !cell.equals("id") && !cell.startsWith("-");
}

// `P6, with the shaper` is owned by P6; `compiler` by the compiler.
function ownerOf(cell: string): string {
	const word: string = cell.split(" ")[0].split(",")[0];
	return word;
}

// Rows are `| id | tier | reason | owner | date |`; the owner's first word is the phase.
export function pendingRows(text: string): PendingRow[] {
	const rows: PendingRow[] = [];
	for (const line of text.split("\n")) {
		const trimmed: string = trimSpaces(line);
		if (!trimmed.startsWith("| ")) { continue; }
		const cells = tableCells(trimmed);
		if ((cells.length as int32) < 5 || !isPendingId(cells[0])) { continue; }
		const tier: string = cells[1];
		if ((tier.length as int32) != 2 || !tier.startsWith("T")) { continue; }
		rows.push({ id: cells[0], tier: tier, owner: ownerOf(cells[3]) });
	}
	return rows;
}

// A roadmap phase's section of VOID2D.md: from its `### P<n> — ` heading to the next `### `.
export function phaseSection(doc: string, phase: string): string {
	const heading: string = "### " + phase + " — ";
	const parts = doc.split(heading);
	if ((parts.length as int32) < 2) { return ""; }
	return heading + parts[1].split("\n### ")[0];
}

// The ids in backticks on a section's `**Closes**` line.
export function closesIds(section: string): string[] {
	const ids: string[] = [];
	for (const line of section.split("\n")) {
		if (!line.startsWith("**Closes**")) { continue; }
		const parts = line.split("`");
		for (let i: int32 = 1; i < (parts.length as int32); i += 2) {
			if (!parts[i].equals("tests/PENDING.md")) { ids.push(parts[i]); }
		}
	}
	return ids;
}

export function contains(values: string[], value: string): boolean {
	for (const v of values) {
		if (v.equals(value)) { return true; }
	}
	return false;
}

// How many scene rows `tests/golden/table.ms` declares; a commented-out row is not one.
export function goldenRowCount(table: string): int32 {
	let rows: int32 = 0;
	for (const line of table.split("\n")) {
		if (trimSpaces(line).startsWith("{ name: \"")) { rows = rows + 1; }
	}
	return rows;
}

test "a table row splits on bars outside backticks only" {
	const cells = tableCells(
		"| legacy:x | T0 | assigning `FlexStyle | null` fails | compiler | 2026-09-22 |",
	);
	assert (cells.length as int32) == 5;
	assert cells[0].equals("legacy:x");
	assert cells[2].equals("assigning `FlexStyle | null` fails");
	assert cells[3].equals("compiler");
}

test "a row is recognised by its tier, whatever its id's case" {
	const rows = pendingRows("| F13:graduation | T2 | an upper-case id | P5 | 2026-09-25 |\n");
	assert (rows.length as int32) == 1 && rows[0].owner.equals("P5");
}

test "pending rows keep the owner's first word and skip prose tables" {
	const rows = pendingRows(
		"| id | tier | reason | owner | date |\n" +
		"|---|---|---|---|---|\n" +
		"| golden-missing:clip/a | T2 | no scene yet | P5 | 2026-09-20 |\n" +
		"| style:x | T0 | measured | P6, with the shaper | 2026-09-21 |\n",
	);
	assert (rows.length as int32) == 2;
	assert rows[0].id.equals("golden-missing:clip/a") && rows[0].owner.equals("P5");
	assert rows[1].owner.equals("P6");
}

test "a phase section ends at the next heading and names what it closes" {
	const doc: string = "### P4 — Text\n\nBody.\n\n**Closes** (`tests/PENDING.md`): `a:b`, `c`.\n\n" +
		"### P5 — Next\n\n**Closes** (`tests/PENDING.md`): `d`.\n";
	const four: string = phaseSection(doc, "P4");
	assert four.indexOf("P5") < 0;
	const ids = closesIds(four);
	assert (ids.length as int32) == 2 && ids[0].equals("a:b") && ids[1].equals("c");
	assert (closesIds(phaseSection(doc, "P5")).length as int32) == 1;
	assert phaseSection(doc, "P7").equals("");
}

test "the golden table's rows are counted by their name field" {
	assert goldenRowCount("[\n\t{ name: \"a/b\", w: 1 },\n\t{ name: \"c/d\", w: 2 },\n]") == 2;
	assert goldenRowCount("[\n\t{ name: \"a/b\" },\n\t// { name: \"c/d\" },\n]") == 1;
}
