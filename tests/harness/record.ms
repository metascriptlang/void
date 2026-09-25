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

export interface PendingRead {
	rows: PendingRow[];
	unread: string[];
}

export enum RowFault {
	Cells,
	Id,
	Tier,
	Owner,
	Date,
}

function isTier(cell: string): boolean {
	return match (cell) {
		"T0" | "T1" | "T2" | "T3" | "T4" | "T5" => true,
		_ => false,
	};
}

function isDate(cell: string): boolean {
	return (cell.length as int32) == 10 && isDigits(cell.byteSlice(0, 4)) &&
		cell.byteSlice(4, 5).equals("-") && isDigits(cell.byteSlice(5, 7)) &&
		cell.byteSlice(7, 8).equals("-") && isDigits(cell.byteSlice(8, 10));
}

// `P6, with the shaper` is owned by P6; `compiler` by the compiler.
function ownerOf(cell: string): string {
	const word: string = cell.split(" ")[0].split(",")[0];
	return word;
}

function pendingRow(cells: string[]): Result<PendingRow, RowFault> {
	if ((cells.length as int32) < 5) { return Result.err(RowFault.Cells); }
	if ((cells[0].length as int32) == 0 || cells[0].indexOf(" ") >= 0) {
		return Result.err(RowFault.Id);
	}
	if (!isTier(cells[1])) { return Result.err(RowFault.Tier); }
	if ((cells[3].length as int32) == 0) { return Result.err(RowFault.Owner); }
	if (!isDate(cells[4])) { return Result.err(RowFault.Date); }
	return Result.ok({ id: cells[0], tier: cells[1], owner: ownerOf(cells[3]) });
}

export function readPending(text: string): PendingRead {
	const rows: PendingRow[] = [];
	const unread: string[] = [];
	const lines = text.split("\n");
	let inTable: boolean = false;
	for (let i: int32 = 0; i < (lines.length as int32); i++) {
		const trimmed: string = trimSpaces(lines[i]);
		if (!trimmed.startsWith("|")) {
			inTable = false;
			continue;
		}
		const cells = tableCells(trimmed);
		if ((cells.length as int32) >= 2 && cells[0].equals("id") && cells[1].equals("tier")) {
			inTable = true;
			continue;
		}
		if (!inTable || ((cells.length as int32) > 0 && cells[0].startsWith("-"))) { continue; }
		const row = pendingRow(cells);
		if (row.ok) {
			rows.push(row.value);
		} else {
			unread.push(`line ${i + 1} (${row.error.toString()}): ${trimmed}`);
		}
	}
	return { rows: rows, unread: unread };
}

// A roadmap phase's section of VOID2D.md: from its `### P<n> — ` heading to the next `### `.
export function phaseSection(doc: string, phase: string): string {
	const heading: string = "### " + phase + " — ";
	const parts = doc.split(heading);
	if ((parts.length as int32) < 2) { return ""; }
	return heading + parts[1].split("\n### ")[0];
}

function isDigits(text: string): boolean {
	if ((text.length as int32) == 0) { return false; }
	for (let i: int32 = 0; i < (text.length as int32); i++) {
		if ("0123456789".indexOf(text.byteSlice(i, i + 1)) < 0) { return false; }
	}
	return true;
}

// Every `### P<n> — ` heading of VOID2D.md, in order.
export function roadmapPhases(doc: string): string[] {
	const phases: string[] = [];
	const parts = doc.split("\n### P");
	for (let i: int32 = 1; i < (parts.length as int32); i++) {
		const number: string = parts[i].split(" — ")[0];
		if (isDigits(number)) { phases.push("P" + number); }
	}
	return phases;
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

const PENDING_HEADER: string = "| id | tier | reason | phase | date |\n|---|---|---|---|---|\n";

test "a row is recognised by its tier, whatever its id's case" {
	const read = readPending(
		PENDING_HEADER + "| F13:graduation | T2 | an upper-case id | P5 | 2026-09-25 |\n",
	);
	assert (read.rows.length as int32) == 1 && read.rows[0].owner.equals("P5");
	assert (read.unread.length as int32) == 0;
}

test "pending rows keep the owner's first word and skip prose tables" {
	const read = readPending(
		"| docs/VOID2D.md line | covered by | phase |\n" +
		"|---|---|---|\n" +
		"| Idle costs a full walk | row `idle-costs-a-walk` | P5 |\n" +
		"\n" +
		PENDING_HEADER +
		"| golden-missing:clip/a | T2 | no scene yet | P5 | 2026-09-20 |\n" +
		"| style:x | T0 | measured | P6, with the shaper | 2026-09-21 |\n",
	);
	assert (read.rows.length as int32) == 2 && (read.unread.length as int32) == 0;
	assert read.rows[0].id.equals("golden-missing:clip/a") && read.rows[0].owner.equals("P5");
	assert read.rows[1].owner.equals("P6");
}

test "a line of a PENDING table that is not a row is named, not skipped" {
	const read = readPending(
		PENDING_HEADER +
		"| a:ok | T1 | fine | P5 | 2026-09-26 |\n" +
		"| a:tiers | T2/T4 | two tiers | P5 | 2026-09-26 |\n" +
		"| a spaced id | T1 | a space in the id | P5 | 2026-09-26 |\n" +
		"| a:undated | T1 | no date cell | P5 |\n" +
		"| a:blank | T1 | an empty date | P5 | |\n" +
		"| a:ownerless | T1 | no owner |  | 2026-09-26 |\n",
	);
	assert (read.rows.length as int32) == 1 && read.rows[0].id.equals("a:ok");
	if ((read.unread.length as int32) != 5) {
		for (const line of read.unread) { console.log(line); }
	}
	assert (read.unread.length as int32) == 5;
	assert read.unread[0].startsWith("line 4 (Tier): | a:tiers");
	assert read.unread[1].startsWith("line 5 (Id): ");
	assert read.unread[2].startsWith("line 6 (Cells): ");
	assert read.unread[3].startsWith("line 7 (Date): ");
	assert read.unread[4].startsWith("line 8 (Owner): ");
}

test "a phase section ends at the next heading and names what it closes" {
	const doc: string = "### P4 — Text\n\nBody.\n\n" +
		"**Closes** (`tests/PENDING.md`): `a:b`, `c`.\n\n" +
		"### P5 — Next\n\n**Closes** (`tests/PENDING.md`): `d`.\n";
	const four: string = phaseSection(doc, "P4");
	assert four.indexOf("P5") < 0;
	const ids = closesIds(four);
	assert (ids.length as int32) == 2 && ids[0].equals("a:b") && ids[1].equals("c");
	assert (closesIds(phaseSection(doc, "P5")).length as int32) == 1;
	assert phaseSection(doc, "P7").equals("");
}

test "the roadmap's phases come from its headings" {
	const phases = roadmapPhases("# Doc\n\n### P0 — Gate\n\n### P12 — Late\n\n### Plan\n");
	assert (phases.length as int32) == 2 && phases[0].equals("P0") && phases[1].equals("P12");
}

test "the golden table's rows are counted by their name field" {
	assert goldenRowCount("[\n\t{ name: \"a/b\", w: 1 },\n\t{ name: \"c/d\", w: 2 },\n]") == 2;
	assert goldenRowCount("[\n\t{ name: \"a/b\" },\n\t// { name: \"c/d\" },\n]") == 1;
}
