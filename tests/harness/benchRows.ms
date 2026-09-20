// The bench row parser, out of tests/bench/check.ms so it can be tested without running a
// bench. check.ms is an entry point - it ends in `process.exit` - so importing it to reach
// this function would run the whole check; the parser therefore lives here, where both
// check.ms and src/test/index.ms can reach it.

import { parseFloat64, isNumber, trimSpaces } from "./parse";

export interface BenchRow {
	scene: string;
	metric: string;
	value: float64;
}

// What a parse rejected, so a caller can report it rather than infer it from a short list.
export interface BenchParse {
	rows: BenchRow[];
	unreadable: int32;
	ignored: int32;
	// The text of each line that claimed to be a row and was not readable, so the caller can
	// quote it. A count on its own tells you something is wrong and not what.
	badLines: string[];
}

// A bench row is `<scene>.<metric> <value>`. Anything else on the stream - sokol's own
// `[sg][error]` lines, a stray warning - is not a row, and the parser used to tell the two
// apart by shape alone and then say nothing either way: two lines it could not read looked
// exactly like two lines it correctly ignored.
//
// Now the shape decides only whether a line *claims* to be a row. A line that claims to be
// one and carries an unreadable value is a failure with its text quoted - it used to become
// the number 0, so `ui.draws abc` was reported as "is 0, the baseline says 20000", a wrong
// value where the truth was an unreadable one. Ignored lines are counted, so a run that
// parsed nothing says so instead of handing back an empty set of rows.
export function parseRows(output: string): BenchParse {
	const rows: BenchRow[] = [];
	let unreadableRows: int32 = 0;
	let ignoredLines: int32 = 0;
	const badLines: string[] = [];
	for (const line of output.split("\n")) {
		const trimmed: string = trimSpaces(line);
		if ((trimmed.length as int32) == 0) { continue; }
		const parts = trimmed.split(" ");
		const looksLikeRow: boolean = (parts.length as int32) == 2
			&& ((parts[0].split(".").length as int32) >= 2);
		if (!looksLikeRow) {
			ignoredLines = ignoredLines + 1;
			continue;
		}
		if (!isNumber(parts[1])) {
			unreadableRows = unreadableRows + 1;
			badLines.push(trimmed);
			continue;
		}
		const key = parts[0].split(".");
		rows.push({ scene: key[0], metric: key[1], value: parseFloat64(parts[1]) });
	}
	return { rows: rows, unreadable: unreadableRows, ignored: ignoredLines, badLines: badLines };
}


test "a clean bench stream parses every row and ignores nothing" {
	const p = parseRows("ui.draws 20000\nui.present.ms 17.8");
	assert (p.rows.length as int32) == 2;
	assert p.rows[0].scene.equals("ui") && p.rows[0].metric.equals("draws");
	assert p.rows[0].value == 20000.0;
	assert p.rows[1].metric.equals("present");
	assert p.unreadable == 0;
	assert p.ignored == 0;
}

test "noise on the stream is ignored and counted, not parsed" {
	// The shape sokol's own logging takes. It was survived by accident before: a line with
	// more than two tokens fell through the same `continue` as a line that was read fine.
	const p = parseRows("[sg][error][id:22] something went wrong\nui.draws 20000\nvoid2d: released 2 retired glyph atlas(es)");
	assert (p.rows.length as int32) == 1;
	assert p.rows[0].value == 20000.0;
	assert p.ignored == 2;
	assert p.unreadable == 0;
}

test "a row that claims to be a measurement and is not readable is reported, not turned into zero" {
	// This is the case the old parser got wrong in the dangerous direction: parseFloat64 came
	// back 0.0 and the row was pushed, so `ui.draws abc` was judged against the baseline and
	// reported as "is 0, the baseline says 20000" - a wrong value, not an unreadable one.
	const p = parseRows("ui.draws abc");
	assert (p.rows.length as int32) == 0;
	assert p.unreadable == 1;
	assert (p.badLines.length as int32) == 1;
	assert p.badLines[0].equals("ui.draws abc");
	assert p.ignored == 0;
}

test "a real zero is still a real zero" {
	const p = parseRows("ui.droppedFrames 0");
	assert (p.rows.length as int32) == 1;
	assert p.rows[0].value == 0.0;
	assert p.unreadable == 0;
}

test "blank lines are neither rows nor noise" {
	const p = parseRows("ui.draws 20000\n\n   \nui.uploads 1");
	assert (p.rows.length as int32) == 2;
	assert p.ignored == 0;
	assert p.unreadable == 0;
}
